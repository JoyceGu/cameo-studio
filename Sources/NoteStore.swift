import Foundation
import Darwin

struct NoteError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct ScriptNote: Codable, Equatable {
    let id: String
    var title: String
    var content: String
    let createdAt: String
    var updatedAt: String
    var revision: Int
}

struct NoteOpenRequest: Codable {
    let id: String
    let noteId: String
    let createdAt: String
}

struct NoteOpenStatus: Codable {
    let requestId: String
    let noteId: String
    let status: String
    let message: String
}

final class NoteStore {
    static let maximumContentBytes = 1_048_576
    let directory: URL
    private let manager = FileManager.default

    init(directory: URL? = nil) throws {
        if let directory { self.directory = directory }
        else if let override = ProcessInfo.processInfo.environment["TD_CAPTURE_NOTES_DIR"] {
            self.directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            self.directory = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("TD Capture/Notes", isDirectory: true)
        }
        for path in [self.directory, requestsDirectory, resultsDirectory, deletedDirectory] {
            try manager.createDirectory(at: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }

    private var requestsDirectory: URL { directory.appendingPathComponent("OpenRequests", isDirectory: true) }
    private var resultsDirectory: URL { directory.appendingPathComponent("OpenResults", isDirectory: true) }
    private var deletedDirectory: URL { directory.appendingPathComponent("Deleted", isDirectory: true) }
    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
    private func validateId(_ value: String) throws -> String {
        guard let uuid = UUID(uuidString: value) else { throw NoteError(message: "Invalid note or request ID.") }
        return uuid.uuidString.lowercased()
    }
    private func file(for id: String) throws -> URL { directory.appendingPathComponent(try validateId(id) + ".json") }
    private func validatedTitle(_ value: String) throws -> String {
        let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 200 else { throw NoteError(message: "The title must contain 1 to 200 characters.") }
        return title
    }
    private func validateContent(_ value: String) throws {
        guard value.utf8.count <= Self.maximumContentBytes, !value.contains("\0") else { throw NoteError(message: "The script must be text without null bytes and no larger than 1 MiB.") }
    }
    private func locked<T>(_ operation: () throws -> T) throws -> T {
        let path = directory.appendingPathComponent(".lock").path
        let descriptor = Darwin.open(path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw NoteError(message: "Cannot lock the local script library.") }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw NoteError(message: "Cannot lock the local script library.") }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }
    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func readUnlocked(_ id: String) throws -> ScriptNote {
        let path = try file(for: id)
        guard manager.fileExists(atPath: path.path) else { throw NoteError(message: "The script was not found.") }
        return try JSONDecoder().decode(ScriptNote.self, from: Data(contentsOf: path))
    }
    func list() throws -> [ScriptNote] {
        try locked {
            let files = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            return try files.filter { $0.pathExtension == "json" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
                .map { try JSONDecoder().decode(ScriptNote.self, from: Data(contentsOf: $0)) }
                .sorted { $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt }
        }
    }
    func get(_ id: String) throws -> ScriptNote { try locked { try readUnlocked(id) } }
    func backupLibrary(to destination: URL) throws {
        try locked { try manager.copyItem(at: directory, to: destination) }
    }
    func deletedNotes() throws -> [ScriptNote] {
        try locked {
            try manager.contentsOfDirectory(at: deletedDirectory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
                .map { try JSONDecoder().decode(ScriptNote.self, from: Data(contentsOf: $0)) }
                .sorted { $0.updatedAt > $1.updatedAt }
        }
    }
    func delete(id: String, expectedRevision: Int) throws {
        try locked {
            var note = try readUnlocked(id)
            guard note.revision == expectedRevision else { throw NoteError(message: "This script changed elsewhere. Reload it before deleting.") }
            note.updatedAt = Self.timestamp()
            // Write the recovery copy before removing the library entry.
            try write(note, to: deletedDirectory.appendingPathComponent(note.id + ".json"))
            try manager.removeItem(at: file(for: note.id))
        }
    }
    func restoreDeleted(_ id: String) throws -> ScriptNote {
        try locked {
            let id = try validateId(id)
            let archived = deletedDirectory.appendingPathComponent(id + ".json")
            guard manager.fileExists(atPath: archived.path) else { throw NoteError(message: "The deleted script was not found.") }
            let destination = try file(for: id)
            guard !manager.fileExists(atPath: destination.path) else { throw NoteError(message: "A script with this ID already exists. No content was overwritten.") }
            var note = try JSONDecoder().decode(ScriptNote.self, from: Data(contentsOf: archived))
            note.revision += 1; note.updatedAt = Self.timestamp()
            try write(note, to: destination)
            try manager.removeItem(at: archived)
            return note
        }
    }
    func create(title: String, content: String) throws -> ScriptNote {
        let title = try validatedTitle(title); try validateContent(content)
        return try locked {
            let now = Self.timestamp()
            let note = ScriptNote(id: UUID().uuidString.lowercased(), title: title, content: content, createdAt: now, updatedAt: now, revision: 1)
            try write(note, to: file(for: note.id)); return note
        }
    }
    func update(id: String, title: String? = nil, content: String? = nil, expectedRevision: Int) throws -> ScriptNote {
        if let content { try validateContent(content) }
        let newTitle = try title.map { try validatedTitle($0) }
        return try locked {
            var note = try readUnlocked(id)
            guard note.revision == expectedRevision else { throw NoteError(message: "This script changed elsewhere. Reload it before saving; your text has not been overwritten.") }
            if let newTitle { note.title = newTitle }; if let content { note.content = content }
            note.revision += 1; note.updatedAt = Self.timestamp()
            try write(note, to: file(for: note.id)); return note
        }
    }
    func importFile(_ url: URL) throws -> ScriptNote {
        guard ["txt", "md", "markdown"].contains(url.pathExtension.lowercased()) else { throw NoteError(message: "Choose a TXT or Markdown file.") }
        let metadata = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard metadata.isRegularFile == true, (metadata.fileSize ?? Int.max) <= Self.maximumContentBytes else { throw NoteError(message: "Choose a text file no larger than 1 MiB.") }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let decoded: String?
        if data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]) { decoded = String(data: data, encoding: .utf16) }
        else { decoded = String(data: data, encoding: .utf8) }
        guard let decoded else { throw NoteError(message: "The file must use UTF-8 or UTF-16 encoding.") }
        let content = decoded.replacingOccurrences(of: "\u{feff}", with: "").replacingOccurrences(of: "\r\n", with: "\n")
        let title = String(url.deletingPathExtension().lastPathComponent.prefix(200))
        return try create(title: title.isEmpty ? "Imported script" : title, content: content)
    }
    func enqueueOpen(noteId: String) throws -> NoteOpenRequest {
        try locked {
            let note = try readUnlocked(noteId)
            let request = NoteOpenRequest(id: UUID().uuidString.lowercased(), noteId: note.id, createdAt: Self.timestamp())
            try write(request, to: requestsDirectory.appendingPathComponent(request.id + ".json"))
            return request
        }
    }
    func pendingRequests() throws -> [NoteOpenRequest] {
        try locked {
            try manager.contentsOfDirectory(at: requestsDirectory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
                .map { try JSONDecoder().decode(NoteOpenRequest.self, from: Data(contentsOf: $0)) }
                .sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt }
        }
    }
    func complete(_ request: NoteOpenRequest, status: String, message: String) throws {
        try locked {
            let id = try validateId(request.id)
            try write(NoteOpenStatus(requestId: id, noteId: request.noteId, status: status, message: message), to: resultsDirectory.appendingPathComponent(id + ".json"))
            let pending = requestsDirectory.appendingPathComponent(id + ".json")
            if manager.fileExists(atPath: pending.path) { try manager.removeItem(at: pending) }
        }
    }
    func openStatus(_ requestId: String) throws -> NoteOpenStatus {
        try locked {
            let id = try validateId(requestId)
            let result = resultsDirectory.appendingPathComponent(id + ".json")
            if manager.fileExists(atPath: result.path) { return try JSONDecoder().decode(NoteOpenStatus.self, from: Data(contentsOf: result)) }
            let pending = requestsDirectory.appendingPathComponent(id + ".json")
            guard manager.fileExists(atPath: pending.path) else { throw NoteError(message: "The open request was not found.") }
            let request = try JSONDecoder().decode(NoteOpenRequest.self, from: Data(contentsOf: pending))
            return NoteOpenStatus(requestId: id, noteId: request.noteId, status: "queued", message: "Waiting for TD Capture to be idle. Recording and active scrolling defer script replacement.")
        }
    }
}
