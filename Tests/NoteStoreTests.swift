import Foundation

@main
struct NoteStoreTests {
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw NoteError(message: message) }
    }
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("td-capture-import-tests-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let store = try NoteStore(directory: root.appendingPathComponent("Notes"))
        let markdown = root.appendingPathComponent("Demo.md")
        try Data("# Example\r\n\r\nKeep **Markdown** and emoji 🎥.\r\n".utf8).write(to: markdown)
        let imported = try store.importFile(markdown)
        try check(imported.title == "Demo", "Import should use the filename as title")
        try check(imported.content == "# Example\n\nKeep **Markdown** and emoji 🎥.\n", "Import should preserve content and normalize line endings")
        let utf16 = root.appendingPathComponent("Unicode.txt")
        try "A UTF-16 script 🎬".data(using: .utf16)!.write(to: utf16)
        let unicode = try store.importFile(utf16)
        try check(unicode.content == "A UTF-16 script 🎬", "UTF-16 import must decode correctly")
        let invalid = root.appendingPathComponent("Broken.txt")
        try Data([0xc3, 0x28]).write(to: invalid)
        do { _ = try store.importFile(invalid); throw NoteError(message: "Invalid encoding was accepted") }
        catch let error as NoteError { try check(error.message == "The file must use UTF-8 or UTF-16 encoding.", "Unexpected import error") }
        let unsupported = root.appendingPathComponent("Unsupported.pdf")
        try Data("Not a text file".utf8).write(to: unsupported)
        do { _ = try store.importFile(unsupported); throw NoteError(message: "Unsupported file was accepted") }
        catch let error as NoteError { try check(error.message == "Choose a TXT or Markdown file.", "Unexpected file type error") }
        let oversized = root.appendingPathComponent("Large.txt")
        try Data(repeating: 65, count: NoteStore.maximumContentBytes + 1).write(to: oversized)
        do { _ = try store.importFile(oversized); throw NoteError(message: "Oversized file was accepted") }
        catch let error as NoteError { try check(error.message == "Choose a text file no larger than 1 MiB.", "Unexpected file size error") }
        let request = try store.enqueueOpen(noteId: imported.id)
        try check(try store.pendingRequests().count == 1, "Open request should persist")
        try store.complete(request, status: "opened", message: "Test acknowledgment")
        try check(try store.pendingRequests().isEmpty, "Completed request should leave the queue")
        try check(try store.openStatus(request.id).status == "opened", "Open acknowledgment should persist")
        let renamed = try store.update(id: imported.id, title: "Renamed", expectedRevision: imported.revision)
        try check(renamed.content == imported.content && renamed.revision == 2, "Renaming should retain script content")
        print("PASS: TXT/Markdown and UTF-16 import, invalid/oversized files, persistent open queue and acknowledgments, title updates")
    }
}
