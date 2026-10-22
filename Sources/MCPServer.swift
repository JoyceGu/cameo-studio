import Foundation
import AppKit

final class NotesMCPServer {
    let store: NoteStore
    let allowApplicationLaunch: Bool
    var initialized = false
    var ready = false
    let currentProtocolVersion = "2025-11-25"
    let supportedProtocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    init(store: NoteStore, allowApplicationLaunch: Bool = true) { self.store = store; self.allowApplicationLaunch = allowApplicationLaunch }

    private func schema(_ properties: [String: Any], required: [String]) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
    }
    var tools: [[String: Any]] {
        let id: [String: Any] = ["type": "string", "format": "uuid", "description": "The note ID returned by create_note or list_notes."]
        let title: [String: Any] = ["type": "string", "minLength": 1, "maxLength": 200]
        let content: [String: Any] = ["type": "string", "description": "Plain text or literal Markdown script, at most 1 MiB of UTF-8 text."]
        let revision: [String: Any] = ["type": "integer", "minimum": 1, "description": "The current revision from get_note; prevents overwriting another editor."]
        func tool(_ name: String, _ description: String, _ input: [String: Any], readOnly: Bool = false) -> [String: Any] {
            ["name": name, "description": description, "inputSchema": input,
             "annotations": ["readOnlyHint": readOnly, "destructiveHint": name == "update_note", "openWorldHint": false]]
        }
        return [
            tool("create_note", "Create a script in the local TD Capture library. Does not replace the teleprompter or start recording.", schema(["title": title, "content": content], required: ["title", "content"])),
            tool("list_notes", "List local script IDs, titles, revisions and timestamps, without script contents.", schema([:], required: []), readOnly: true),
            tool("get_note", "Read one script and its revision before editing it.", schema(["id": id], required: ["id"]), readOnly: true),
            tool("update_note", "Update a script using its current revision. A conflict fails without overwriting either editor. The active teleprompter stays unchanged until open_note.", schema(["id": id, "title": title, "content": content, "expected_revision": revision], required: ["id", "content", "expected_revision"])),
            tool("open_note", "Queue a script for the TD Capture teleprompter and launch the app if needed. Recording, countdown, export, active scrolling and recent typing defer replacement. Never starts recording. Returns a request ID for get_open_status.", schema(["id": id], required: ["id"])),
            tool("get_open_status", "Check whether an open request is queued, opened or failed.", schema(["request_id": ["type": "string", "format": "uuid"]], required: ["request_id"]), readOnly: true)
        ]
    }
    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
    }
    private func string(_ key: String, in arguments: [String: Any]) throws -> String {
        guard let value = arguments[key] as? String else { throw NoteError(message: "Expected a string argument: \(key).") }
        return value
    }
    private func launchApplication() -> Bool {
        guard allowApplicationLaunch, Bundle.main.bundleURL.pathExtension == "app" else { return false }
        // No script content is placed in command-line arguments or a public URL.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", Bundle.main.bundleURL.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 }
        catch { return false }
    }
    private func call(_ name: String, arguments: [String: Any]) throws -> [String: Any] {
        guard let definition = tools.first(where: { $0["name"] as? String == name }),
              let input = definition["inputSchema"] as? [String: Any],
              let properties = input["properties"] as? [String: Any] else { throw NoteError(message: "Unknown tool: \(name).") }
        guard arguments.keys.allSatisfy({ properties[$0] != nil }) else { throw NoteError(message: "Unexpected tool argument.") }
        switch name {
        case "create_note":
            return try object(store.create(title: string("title", in: arguments), content: string("content", in: arguments)))
        case "list_notes":
            let notes = try store.list().map { note -> [String: Any] in
                ["id": note.id, "title": note.title, "revision": note.revision, "createdAt": note.createdAt, "updatedAt": note.updatedAt]
            }
            return ["notes": notes]
        case "get_note": return try object(store.get(string("id", in: arguments)))
        case "update_note":
            guard let revision = arguments["expected_revision"] as? NSNumber,
                  CFGetTypeID(revision) != CFBooleanGetTypeID(), revision.doubleValue.rounded() == revision.doubleValue,
                  revision.doubleValue >= 1, revision.doubleValue <= Double(Int32.max) else { throw NoteError(message: "expected_revision must be a positive integer.") }
            let title: String?
            if let value = arguments["title"] { guard let text = value as? String else { throw NoteError(message: "title must be a string.") }; title = text } else { title = nil }
            return try object(store.update(id: string("id", in: arguments), title: title, content: string("content", in: arguments), expectedRevision: revision.intValue))
        case "open_note":
            let request = try store.enqueueOpen(noteId: string("id", in: arguments))
            let launched = launchApplication()
            return ["request_id": request.id, "note_id": request.noteId, "status": "queued", "app_launch_requested": launched,
                    "message": launched ? "Queued for the teleprompter. Use get_open_status to confirm when it opens." : "Queued. Open TD Capture manually; use get_open_status to confirm when it opens."]
        case "get_open_status": return try object(store.openStatus(string("request_id", in: arguments)))
        default: throw NoteError(message: "Unknown tool.")
        }
    }
    private func error(id: Any = NSNull(), code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }
    func handle(_ data: Data) -> [String: Any]? {
        let raw: Any
        do { raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
        catch { return self.error(code: -32700, message: "Parse error.") }
        guard let request = raw as? [String: Any], request["jsonrpc"] as? String == "2.0", let method = request["method"] as? String else {
            return error(code: -32600, message: "Invalid JSON-RPC request.")
        }
        let id = request["id"]
        if let id, !(id is String) && !(id is NSNumber) { return error(code: -32600, message: "Invalid request ID.") }
        if let number = id as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() || number.doubleValue.rounded() != number.doubleValue { return error(code: -32600, message: "Invalid request ID.") }
        if id == nil {
            if method == "notifications/initialized", initialized { ready = true }
            return nil
        }
        let idValue = id!
        if let params = request["params"], !(params is [String: Any]) { return error(id: idValue, code: -32602, message: "Params must be an object.") }
        let params = request["params"] as? [String: Any] ?? [:]
        if method == "initialize" {
            guard !initialized, let requested = params["protocolVersion"] as? String,
                  params["capabilities"] is [String: Any], params["clientInfo"] is [String: Any] else {
                return error(id: idValue, code: -32602, message: "Invalid initialization parameters or duplicate initialization.")
            }
            initialized = true
            return ["jsonrpc": "2.0", "id": idValue, "result": [
                "protocolVersion": supportedProtocolVersions.contains(requested) ? requested : currentProtocolVersion,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "td-capture-notes", "title": "TD Capture Notes", "version": "0.4.0"],
                "instructions": "Manage scripts in the local TD Capture library. Creating or updating a note never starts recording. Use open_note then get_open_status to load and verify a script in the teleprompter."
            ]]
        }
        if method == "ping" { return ["jsonrpc": "2.0", "id": idValue, "result": [:]] }
        guard ready else { return error(id: idValue, code: -32002, message: "Initialize the server and send notifications/initialized first.") }
        if method == "tools/list" {
            if params["cursor"] != nil { return error(id: idValue, code: -32602, message: "This tool list has no pagination cursor.") }
            return ["jsonrpc": "2.0", "id": idValue, "result": ["tools": tools]]
        }
        if method == "tools/call" {
            guard let name = params["name"] as? String else { return error(id: idValue, code: -32602, message: "Missing tool name.") }
            if let arguments = params["arguments"], !(arguments is [String: Any]) { return error(id: idValue, code: -32602, message: "Tool arguments must be an object.") }
            guard tools.contains(where: { $0["name"] as? String == name }) else { return error(id: idValue, code: -32602, message: "Unknown tool.") }
            do {
                let result = try call(name, arguments: params["arguments"] as? [String: Any] ?? [:])
                let text = String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8)!
                return ["jsonrpc": "2.0", "id": idValue, "result": ["content": [["type": "text", "text": text]], "structuredContent": result, "isError": false]]
            } catch {
                return ["jsonrpc": "2.0", "id": idValue, "result": ["content": [["type": "text", "text": error.localizedDescription]], "isError": true]]
            }
        }
        return error(id: idValue, code: -32601, message: "Method not found.")
    }
    func run() {
        while let line = readLine(strippingNewline: true) {
            guard let data = line.data(using: .utf8) else { continue }
            let response: [String: Any]?
            if data.count > 2_097_152 { response = error(code: -32600, message: "Request exceeds 2 MiB.") }
            else { response = handle(data) }
            if let response, let encoded = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]) {
                FileHandle.standardOutput.write(encoded); FileHandle.standardOutput.write(Data([10]))
            }
        }
    }
}
