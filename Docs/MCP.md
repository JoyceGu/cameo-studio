# Local notes MCP server

TD Capture 0.4.0 bundles a local, tools-only MCP server in its application executable. It uses newline-delimited JSON-RPC over stdio, with initialization and tool calls based on the MCP 2025-11-25 specification. Compatible initialization versions also include 2025-06-18, 2025-03-26 and 2024-11-05.

No Node.js, Python runtime, background web server, account or API key is needed to run the server. A client must support **local stdio MCP servers**; this is not a remote HTTP connector.

## Configure an AI client

1. Keep the app in a stable location, for example `/Applications/TD Capture.app`.
2. In TD Capture, open **Script library → Copy MCP configuration**. The copied command points to the actual installed app.
3. Add the entry to your AI client's MCP configuration using that client's configuration format, then reconnect or restart the client.

For clients using the `mcpServers` JSON convention:

```json
{
  "mcpServers": {
    "td-capture": {
      "command": "/Applications/TD Capture.app/Contents/MacOS/TDCapture",
      "args": ["--mcp"]
    }
  }
}
```

Use the executable as `command`, not the app directory or the macOS `open` command. Do not place shell quotes inside the JSON path. If you move the app, copy the configuration again. Adding a server makes its local script tools available to the configured AI client; configure only clients you intend to give access to those notes.

No AI client's configuration is modified automatically by TD Capture.

## Tools

| Tool | Arguments | Result |
| --- | --- | --- |
| `create_note` | `title`, `content` | New note including `id` and `revision` |
| `list_notes` | None | IDs, titles, revisions and timestamps; no script bodies |
| `get_note` | `id` | Full note including its current revision |
| `update_note` | `id`, `content`, `expected_revision`; optional `title` | Updated note or a conflict error |
| `open_note` | `id` | Queued request with `request_id`; requests app launch if needed |
| `get_open_status` | `request_id` | `queued`, `opened` or `failed` |

Titles contain 1–200 characters. Content is plain text or literal Markdown, up to 1 MiB of UTF-8 text. The library does not render or execute Markdown. All IDs are UUIDs. No tool accepts an arbitrary filesystem path.

A typical instruction to an AI assistant is:

> Create a three-minute demo script in TD Capture, then open it in the teleprompter. Do not start recording.

The client calls `create_note`, then `open_note`, then checks `get_open_status`. For changes, read `get_note` first and pass the returned `revision` as `expected_revision` to `update_note`.

A queued response does **not** mean the script has opened. If the app cannot be launched automatically, open TD Capture manually. Requests remain queued while recording, counting down, exporting, actively scrolling or during recent typing. Pause scrolling and wait until the recorder is idle to apply them. No MCP tool starts recording or activates the camera/microphone.

Updating a note changes the library copy. The teleprompter's current script is not replaced automatically; use `open_note`. If a user types into an older version after an external update, their changes are preserved in a new local copy rather than overwriting the updated note.

## Local data

Notes are stored under:

```text
~/Library/Application Support/TD Capture/Notes/
```

Each note is an atomic JSON document containing `id`, `title`, `content`, `createdAt`, `updatedAt` and `revision`. A process lock serializes writes from the app and multiple MCP clients. Open requests and acknowledgments live in subdirectories. Existing single-script preferences migrate into the library once; UserDefaults also retains the active script as a local compatibility/recovery backup.

TD Capture does not upload scripts. A configured AI client can read note contents through `get_note`; how that client handles text is governed by that client.

## Development checks

After building the app:

```sh
python3 Tests/test_notes_mcp.py

xcrun swiftc -swift-version 5 Sources/NoteStore.swift Tests/NoteStoreTests.swift -o /tmp/td-capture-note-tests
/tmp/td-capture-note-tests
```

The black-box protocol tests run isolated servers with:

```sh
"TD Capture.app/Contents/MacOS/TDCapture" --mcp --notes-directory /tmp/td-capture-test-notes --no-activate
```

`--notes-directory` and `--no-activate` are development options for isolated server tests. Do not add them to a regular client configuration: the GUI uses its normal library. `TD_CAPTURE_NOTES_DIR` is also available for controlled development environments. The CLI exits cleanly on stdin EOF; protocol responses are the only output on stdout.

Protocol references: [lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle), [tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools), [stdio transport](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports).
