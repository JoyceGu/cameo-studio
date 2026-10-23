import AppKit
import UniformTypeIdentifiers

final class NoteDropStack: NSStackView {
    var onFiles: (([URL]) -> Void)?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect); registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private func files(_ sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
            .filter { ["txt", "md", "markdown"].contains($0.pathExtension.lowercased()) }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { files(sender).isEmpty ? [] : .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = files(sender); guard !urls.isEmpty else { return false }; onFiles?(urls); return true
    }
}

final class NotesLibraryPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate, NSTextFieldDelegate, NSWindowDelegate {
    let panel: NSPanel
    let table = NSTableView()
    let titleField = NSTextField(string: "")
    let editor = NSTextView()
    let heading = NSTextField(labelWithString: "")
    let subtitle = NSTextField(labelWithString: "")
    let libraryCaption = NSTextField(labelWithString: "")
    let editorHint = NSTextField(labelWithString: "")
    let message = NSTextField(wrappingLabelWithString: "")
    let newButton = NSButton(title: "", target: nil, action: nil)
    let importButton = NSButton(title: "", target: nil, action: nil)
    let mcpButton = NSButton(title: "", target: nil, action: nil)
    var notes: [ScriptNote] = []
    let store: NoteStore
    var onSelect: ((ScriptNote) -> Void)?
    var onEdited: ((ScriptNote) -> Void)?
    var editorNote: ScriptNote?
    var hasPendingEdits = false
    var lastEditTime: Double = 0
    var reloading = false
    var timer: Timer?

    init(store: NoteStore) {
        self.store = store
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 900, height: 736), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        panel.isReleasedWhenClosed = false; panel.delegate = self
        panel.appearance = NSAppearance(named: .aqua)
        panel.titlebarAppearsTransparent = true; panel.titleVisibility = .hidden
        let canvas = WatercolorSetupView(); panel.contentView = canvas
        let root = NoteDropStack(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 16
        root.translatesAutoresizingMaskIntoConstraints = false; canvas.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: 28),
            root.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -28),
            root.topAnchor.constraint(equalTo: canvas.topAnchor, constant: 46),
            root.bottomAnchor.constraint(lessThanOrEqualTo: canvas.bottomAnchor, constant: -24)
        ])
        root.onFiles = { [weak self] urls in self?.importFiles(urls) }
        heading.font = .systemFont(ofSize: 26, weight: .semibold); heading.textColor = SetupTheme.ink
        heading.heightAnchor.constraint(equalToConstant: 42).isActive = true
        subtitle.font = .systemFont(ofSize: 12); subtitle.textColor = SetupTheme.muted
        subtitle.heightAnchor.constraint(equalToConstant: 20).isActive = true
        root.addArrangedSubview(SetupTheme.stack([heading, subtitle], vertical: true, spacing: 6))
        let actions = SetupTheme.stack([newButton, importButton, mcpButton], spacing: 12)
        for (button, action, symbol) in [(newButton, #selector(createNote), "plus"), (importButton, #selector(importNotes), "doc.badge.arrow.up"), (mcpButton, #selector(showMCPImport), "point.3.connected.trianglepath.dotted")] {
            button.target = self; button.action = action; SetupTheme.button(button)
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil); button.imagePosition = .imageLeading
            button.widthAnchor.constraint(equalToConstant: 273).isActive = true
        }
        root.addArrangedSubview(actions)

        let listCard = SetupCard(padding: 16)
        libraryCaption.font = .systemFont(ofSize: 12, weight: .semibold); libraryCaption.textColor = SetupTheme.muted
        listCard.content.addArrangedSubview(libraryCaption)
        libraryCaption.heightAnchor.constraint(equalToConstant: 20).isActive = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title")); column.width = 188
        table.addTableColumn(column); table.headerView = nil; table.rowHeight = 44
        table.delegate = self; table.dataSource = self; table.style = .sourceList
        table.target = self; table.action = #selector(selectScript)
        table.backgroundColor = .clear; table.allowsEmptySelection = false
        let list = NSScrollView(); list.documentView = table; list.hasVerticalScroller = true; list.drawsBackground = false
        listCard.content.addArrangedSubview(list)
        list.widthAnchor.constraint(equalToConstant: 192).isActive = true
        list.heightAnchor.constraint(equalToConstant: 348).isActive = true

        let editorCard = SetupCard(padding: 20)
        titleField.isBordered = false; titleField.drawsBackground = false
        titleField.font = .systemFont(ofSize: 19, weight: .semibold); titleField.textColor = SetupTheme.ink
        titleField.delegate = self
        editorCard.content.addArrangedSubview(titleField)
        titleField.widthAnchor.constraint(equalTo: editorCard.content.widthAnchor).isActive = true
        titleField.heightAnchor.constraint(equalToConstant: 34).isActive = true
        editor.isRichText = false; editor.isEditable = true; editor.isSelectable = true; editor.allowsUndo = true
        editor.delegate = self; editor.font = .systemFont(ofSize: 15); editor.textColor = SetupTheme.ink
        editor.backgroundColor = .clear; editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: 6, height: 12)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.textContainer?.widthTracksTextView = true; editor.autoresizingMask = [.width]
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 7
        editor.defaultParagraphStyle = paragraph
        let editorScroll = NSScrollView(); editorScroll.documentView = editor; editorScroll.hasVerticalScroller = true; editorScroll.drawsBackground = false
        editorCard.content.addArrangedSubview(editorScroll)
        editorScroll.widthAnchor.constraint(equalTo: editorCard.content.widthAnchor).isActive = true
        editorScroll.heightAnchor.constraint(equalToConstant: 284).isActive = true
        editorHint.font = .systemFont(ofSize: 11); editorHint.textColor = SetupTheme.muted
        editorCard.content.addArrangedSubview(editorHint)
        editorHint.heightAnchor.constraint(equalToConstant: 18).isActive = true
        let body = SetupTheme.stack([listCard, editorCard], spacing: 16); root.addArrangedSubview(body)
        NSLayoutConstraint.activate([
            body.widthAnchor.constraint(equalTo: root.widthAnchor),
            listCard.widthAnchor.constraint(equalToConstant: 224),
            editorCard.widthAnchor.constraint(equalToConstant: 604),
            listCard.heightAnchor.constraint(equalToConstant: 420),
            editorCard.heightAnchor.constraint(equalTo: listCard.heightAnchor)
        ])
        message.font = .systemFont(ofSize: 11); message.textColor = SetupTheme.muted
        message.preferredMaxLayoutWidth = 844; root.addArrangedSubview(message)
        message.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        applyLanguage(); refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.panel.isVisible else { return }; self.refresh()
        }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { notes.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let text = NSTextField(labelWithString: notes[row].title)
        text.font = .systemFont(ofSize: 13, weight: .medium); text.lineBreakMode = .byTruncatingTail
        let cell = NSView(); text.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(text)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            text.heightAnchor.constraint(equalToConstant: 24)
        ])
        return cell
    }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { reloading || saveEditor() }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !reloading, notes.indices.contains(table.selectedRow) else { return }
        loadEditor(notes[table.selectedRow]); onSelect?(notes[table.selectedRow])
    }
    @objc private func selectScript() {
        guard saveEditor(), let note = editorNote else { return }; onSelect?(note)
    }
    private func loadEditor(_ note: ScriptNote) {
        editorNote = note; hasPendingEdits = false
        titleField.stringValue = note.title; editor.string = note.content
        editor.undoManager?.removeAllActions()
        editor.isEditable = true; titleField.isEnabled = true
        editor.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }
    func refresh(select id: String? = nil) {
        do {
            // Never replace a focused editor with a timer refresh or an MCP update.
            let editing = titleField.currentEditor() != nil || panel.firstResponder === editor
            guard id != nil || (!editing && !hasPendingEdits) else { return }
            let fresh = try store.list()
            guard fresh != notes || id != nil else { return }
            let selected = id ?? editorNote?.id
            reloading = true; notes = fresh; table.reloadData()
            if let index = notes.firstIndex(where: { $0.id == selected }) {
                table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                loadEditor(notes[index])
            } else if let first = notes.first {
                table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false); loadEditor(first)
            } else {
                editorNote = nil; editor.string = ""; titleField.stringValue = ""
                editor.isEditable = false; titleField.isEnabled = false
            }
            reloading = false
        } catch { reloading = false; showError(error) }
    }
    @discardableResult private func saveEditor() -> Bool {
        guard let note = editorNote else { return true }
        let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTitle = title.isEmpty ? L("Untitled script") : title
        guard effectiveTitle != note.title || editor.string != note.content else { hasPendingEdits = false; return true }
        do {
            let updated: ScriptNote
            let latest = try store.get(note.id)
            if latest.revision != note.revision {
                // Preserve the visible draft when another MCP client edited this note.
                updated = try store.create(title: String((effectiveTitle + " (local copy)").prefix(200)), content: editor.string)
                showMessage("Another editor changed this script. Your edits were saved as a separate local copy.")
            } else {
                updated = try store.update(id: note.id, title: effectiveTitle, content: editor.string, expectedRevision: note.revision)
                showMessage("Saved on this Mac.")
            }
            editorNote = updated; hasPendingEdits = false
            if let index = notes.firstIndex(where: { $0.id == updated.id }) { notes[index] = updated }
            else { notes.insert(updated, at: 0) }
            reloading = true; table.reloadData()
            if let index = notes.firstIndex(where: { $0.id == updated.id }) { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
            reloading = false
            onEdited?(updated); return true
        } catch { hasPendingEdits = true; showError(error); return false }
    }
    func textDidChange(_ notification: Notification) { lastEditTime = ProcessInfo.processInfo.systemUptime; hasPendingEdits = true; _ = saveEditor() }
    func controlTextDidChange(_ notification: Notification) { lastEditTime = ProcessInfo.processInfo.systemUptime; hasPendingEdits = true; _ = saveEditor() }
    func controlTextDidEndEditing(_ notification: Notification) { _ = saveEditor() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { saveEditor() }
    func showError(_ error: Error) { message.stringValue = L(error.localizedDescription); message.textColor = .systemOrange }
    func showMessage(_ text: String) { message.stringValue = L(text); message.textColor = SetupTheme.muted }
    func applyLanguage() {
        panel.title = L("Script library"); heading.stringValue = L("Script library")
        subtitle.stringValue = L("Write, paste or import. Keep your next take ready.")
        newButton.title = L("New script"); importButton.title = L("Import from file"); mcpButton.title = L("Import via MCP")
        libraryCaption.stringValue = L("Your scripts"); titleField.placeholderString = L("Script title")
        editorHint.stringValue = L("Paste or type your script here. Changes save automatically.")
        showMessage("TXT / Markdown supported. You can also drop files into this window.")
    }
    @objc func createNote() {
        guard saveEditor() else { return }
        do {
            let note = try store.create(title: L("Untitled script"), content: "")
            refresh(select: note.id); onSelect?(note)
            panel.makeFirstResponder(editor)
            showMessage("Paste or type your script here. Changes save automatically.")
        } catch { showError(error) }
    }
    @objc func importNotes() {
        guard saveEditor() else { return }
        let picker = NSOpenPanel(); picker.allowsMultipleSelection = true; picker.canChooseDirectories = false
        picker.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "markdown") ?? .plainText]
        guard picker.runModal() == .OK else { return }; importFiles(picker.urls)
    }
    func importFiles(_ urls: [URL]) {
        guard saveEditor() else { return }
        var last: ScriptNote?; var failures: [String] = []
        for url in urls {
            do { last = try store.importFile(url) }
            catch { failures.append(url.lastPathComponent + ": " + L(error.localizedDescription)) }
        }
        refresh(select: last?.id)
        if let last { onSelect?(last) }
        if failures.isEmpty { showMessage("Imported and saved on this Mac.") }
        else { message.stringValue = failures.joined(separator: "\n"); message.textColor = .systemOrange }
    }
    @objc func showMCPImport() {
        let alert = NSAlert(); alert.messageText = L("Import via MCP")
        alert.informativeText = L("Connect your AI client once, then ask it to create a script in TD Capture. Imported scripts appear in this library.\n\n1. Copy the connection configuration.\n2. Add it to an AI client that supports local stdio MCP.\n3. Ask the AI to create a note in TD Capture.\n\nThis button sets up the connection; it does not upload files or connect a client automatically.")
        alert.addButton(withTitle: L("Copy connection configuration")); alert.addButton(withTitle: L("Cancel"))
        alert.beginSheetModal(for: panel) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.copyMCPConfiguration() }
        }
    }
    private func copyMCPConfiguration() {
        guard let executable = Bundle.main.executableURL else { return }
        let config: [String: Any] = ["mcpServers": ["td-capture": ["command": executable.path, "args": ["--mcp"]]]]
        guard let data = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), let text = String(data: data, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        showMessage("MCP configuration copied. Add it to an AI client that supports local stdio MCP servers.")
    }
    func show() { refresh(); panel.center(); panel.makeKeyAndOrderFront(nil) }
}

final class NotesCoordinator {
    let store: NoteStore
    let prompter: Prompter
    let library: NotesLibraryPanel
    var activeNote: ScriptNote
    var canOpen: () -> Bool
    var timer: Timer?
    var onMessage: ((String) -> Void)?
    var lastError: String?
    var hasUnsavedDraft = false

    init(prompter: Prompter, canOpen: @escaping () -> Bool) throws {
        self.prompter = prompter; self.canOpen = canOpen; store = try NoteStore()
        let defaults = UserDefaults.standard
        var notes = try store.list()
        if !defaults.bool(forKey: "notes.legacyMigrationCompleted") {
            if let legacy = defaults.string(forKey: "prompter.script"), !legacy.isEmpty {
                let imported = try store.create(title: L("Previous script"), content: legacy)
                defaults.set(imported.id, forKey: "notes.activeId")
            }
            defaults.set(true, forKey: "notes.legacyMigrationCompleted"); notes = try store.list()
        }
        if notes.isEmpty { notes = [try store.create(title: L("My first script"), content: prompter.text.string)] }
        let selectedId = defaults.string(forKey: "notes.activeId")
        activeNote = notes.first(where: { $0.id == selectedId }) ?? notes[0]
        if defaults.bool(forKey: "notes.hasUnsavedDraft"), let backup = defaults.string(forKey: "prompter.script"), backup != activeNote.content {
            activeNote = try store.create(title: String((activeNote.title + " (recovered copy)").prefix(200)), content: backup)
        }
        defaults.set(false, forKey: "notes.hasUnsavedDraft")
        library = NotesLibraryPanel(store: store)
        display(activeNote, show: false)
        prompter.onScriptEdited = { [weak self] content in self?.saveEdit(content) }
        library.onSelect = { [weak self] note in self?.useLibraryNote(note) }
        library.onEdited = { [weak self] note in self?.useLibraryNote(note) }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.processPendingRequests() }
    }
    private func display(_ note: ScriptNote, show: Bool) {
        activeNote = note; hasUnsavedDraft = false
        prompter.running = false; prompter.play.title = L("▶ Start scrolling")
        UserDefaults.standard.set(note.id, forKey: "notes.activeId")
        UserDefaults.standard.set(note.content, forKey: "prompter.script")
        prompter.text.string = note.content; prompter.scriptTitle = note.title
        prompter.resetPosition(); prompter.applyLanguage()
        if show { prompter.show() }
    }
    private func saveEdit(_ content: String) {
        do {
            activeNote = try store.update(id: activeNote.id, content: content, expectedRevision: activeNote.revision)
            hasUnsavedDraft = false; UserDefaults.standard.set(false, forKey: "notes.hasUnsavedDraft")
        } catch {
            // Preserve a local copy on revision conflicts; never overwrite the remote update.
            if let latest = try? store.get(activeNote.id), latest.revision != activeNote.revision,
               let recovered = try? store.create(title: String((activeNote.title + " (local copy)").prefix(200)), content: content) {
                activeNote = recovered; hasUnsavedDraft = false; prompter.scriptTitle = recovered.title
                UserDefaults.standard.set(recovered.id, forKey: "notes.activeId")
                prompter.applyLanguage(); onMessage?("Another editor changed this script. Your edits were saved as a separate local copy.")
            } else {
                hasUnsavedDraft = true; UserDefaults.standard.set(true, forKey: "notes.hasUnsavedDraft"); onMessage?(error.localizedDescription)
            }
        }
    }
    private func useLibraryNote(_ note: ScriptNote) {
        guard canOpen(), !(prompter.running && prompter.panel.isVisible), !hasUnsavedDraft,
              ProcessInfo.processInfo.systemUptime - prompter.lastEditTime > 1 else {
            library.showMessage("Saved. Select this script again when recording and scrolling stop to use it.")
            return
        }
        display(note, show: false)
    }
    func requestOpen(_ id: String) {
        do {
            _ = try store.enqueueOpen(noteId: id)
            if !canOpen() || (prompter.running && prompter.panel.isVisible) || hasUnsavedDraft { library.showMessage("Script queued. It will open after recording, scrolling and editing are idle.") }
            processPendingRequests()
        } catch { library.showError(error) }
    }
    func processPendingRequests() {
        guard canOpen(), !(prompter.running && prompter.panel.isVisible), !hasUnsavedDraft,
              ProcessInfo.processInfo.systemUptime - prompter.lastEditTime > 1,
              !library.hasPendingEdits, ProcessInfo.processInfo.systemUptime - library.lastEditTime > 1 else { return }
        do {
            guard let request = try store.pendingRequests().first else { return }
            do {
                let note = try store.get(request.noteId)
                display(note, show: true)
                try store.complete(request, status: "opened", message: "Opened in the teleprompter. Recording has not been started.")
                library.refresh(select: note.id)
            } catch {
                try store.complete(request, status: "failed", message: error.localizedDescription)
                onMessage?(error.localizedDescription)
            }
            lastError = nil
        } catch {
            if lastError != error.localizedDescription { onMessage?(error.localizedDescription); lastError = error.localizedDescription }
        }
    }
    func applyLanguage() { library.applyLanguage(); prompter.applyLanguage() }
}
