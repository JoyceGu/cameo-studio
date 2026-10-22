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

final class NotesLibraryPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let panel: NSPanel
    let table = NSTableView()
    let titleField = NSTextField(string: "")
    let preview = NSTextView()
    let message = NSTextField(wrappingLabelWithString: "")
    let help = NSTextField(wrappingLabelWithString: "")
    let newButton = NSButton(title: "", target: nil, action: nil)
    let importButton = NSButton(title: "", target: nil, action: nil)
    let openButton = NSButton(title: "", target: nil, action: nil)
    let renameButton = NSButton(title: "", target: nil, action: nil)
    let configButton = NSButton(title: "", target: nil, action: nil)
    var notes: [ScriptNote] = []
    var store: NoteStore
    var onOpen: ((String) -> Void)?
    var onRenamed: ((ScriptNote) -> Void)?
    var timer: Timer?

    init(store: NoteStore) {
        self.store = store
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 540), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        panel.isReleasedWhenClosed = false
        let root = NoteDropStack(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20); panel.contentView = root
        root.onFiles = { [weak self] urls in self?.importFiles(urls) }
        let toolbar = NSStackView(views: [newButton, importButton, openButton, configButton]); toolbar.spacing = 12; root.addArrangedSubview(toolbar)
        for (button, action) in [(newButton, #selector(createNote)), (importButton, #selector(importNotes)), (openButton, #selector(openSelected)), (renameButton, #selector(renameSelected)), (configButton, #selector(copyMCPConfiguration))] { button.target = self; button.action = action }
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title")); column.width = 680; table.addTableColumn(column)
        table.headerView = nil; table.rowHeight = 38; table.delegate = self; table.dataSource = self
        let list = NSScrollView(); list.documentView = table; list.hasVerticalScroller = true
        list.widthAnchor.constraint(equalToConstant: 700).isActive = true; list.heightAnchor.constraint(equalToConstant: 160).isActive = true
        root.addArrangedSubview(list)
        titleField.placeholderString = L("Script title"); titleField.widthAnchor.constraint(equalToConstant: 570).isActive = true
        let titleRow = NSStackView(views: [titleField, renameButton]); titleRow.spacing = 12; root.addArrangedSubview(titleRow)
        preview.isEditable = false; preview.isSelectable = true; preview.font = .systemFont(ofSize: 15)
        preview.textContainerInset = NSSize(width: 10, height: 10); preview.isVerticallyResizable = true
        preview.isHorizontallyResizable = false; preview.textContainer?.widthTracksTextView = true; preview.autoresizingMask = [.width]
        let previewScroll = NSScrollView(); previewScroll.documentView = preview; previewScroll.hasVerticalScroller = true
        previewScroll.widthAnchor.constraint(equalToConstant: 700).isActive = true; previewScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        root.addArrangedSubview(previewScroll)
        help.preferredMaxLayoutWidth = 700; help.font = .systemFont(ofSize: 12); help.textColor = .secondaryLabelColor
        message.preferredMaxLayoutWidth = 700; message.font = .systemFont(ofSize: 12)
        root.addArrangedSubview(help); root.addArrangedSubview(message)
        applyLanguage(); refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.panel.isVisible else { return }; self.refresh()
        }
    }
    var selectedNote: ScriptNote? { notes.indices.contains(table.selectedRow) ? notes[table.selectedRow] : nil }
    func numberOfRows(in tableView: NSTableView) -> Int { notes.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let text = NSTextField(labelWithString: notes[row].title + "  ·  r\(notes[row].revision)")
        text.lineBreakMode = .byTruncatingTail; return text
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updateSelection() }
    func updateSelection() {
        let note = selectedNote
        titleField.stringValue = note?.title ?? ""; preview.string = note?.content ?? ""
        openButton.isEnabled = note != nil; renameButton.isEnabled = note != nil
    }
    func refresh(select id: String? = nil) {
        do {
            guard titleField.currentEditor() == nil || id != nil else { return }
            let fresh = try store.list()
            guard fresh != notes || id != nil else { return }
            let selected = id ?? selectedNote?.id
            notes = fresh; table.reloadData()
            if let selected, let index = notes.firstIndex(where: { $0.id == selected }) { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
            else if !notes.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
            updateSelection()
        } catch { showError(error) }
    }
    func showError(_ error: Error) { message.stringValue = L(error.localizedDescription); message.textColor = .systemOrange }
    func showMessage(_ text: String) { message.stringValue = L(text); message.textColor = .secondaryLabelColor }
    func applyLanguage() {
        panel.title = L("Script library")
        newButton.title = L("New script"); importButton.title = L("Import TXT / Markdown…")
        openButton.title = L("Open in teleprompter"); renameButton.title = L("Rename")
        configButton.title = L("Copy MCP configuration")
        titleField.placeholderString = L("Script title")
        help.stringValue = L("Drop TXT or Markdown files here. Edit script text in the teleprompter. Incoming scripts wait while recording or scrolling.")
    }
    @objc func createNote() {
        do {
            let note = try store.create(title: L("Untitled script"), content: "")
            refresh(select: note.id); onOpen?(note.id)
        } catch { showError(error) }
    }
    @objc func importNotes() {
        let picker = NSOpenPanel(); picker.allowsMultipleSelection = true; picker.canChooseDirectories = false
        picker.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "markdown") ?? .plainText]
        guard picker.runModal() == .OK else { return }; importFiles(picker.urls)
    }
    func importFiles(_ urls: [URL]) {
        var last: ScriptNote?
        var failures: [String] = []
        for url in urls {
            do { last = try store.importFile(url) }
            catch { failures.append(url.lastPathComponent + ": " + L(error.localizedDescription)) }
        }
        refresh(select: last?.id)
        if failures.isEmpty { showMessage("Scripts imported. Select one and open it in the teleprompter.") }
        else { message.stringValue = failures.joined(separator: "\n"); message.textColor = .systemOrange }
    }
    @objc func openSelected() { if let note = selectedNote { onOpen?(note.id) } }
    @objc func renameSelected() {
        guard let note = selectedNote else { return }
        do { let updated = try store.update(id: note.id, title: titleField.stringValue, expectedRevision: note.revision); onRenamed?(updated); refresh(select: updated.id) }
        catch { showError(error) }
    }
    @objc func copyMCPConfiguration() {
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
        library.onOpen = { [weak self] id in self?.requestOpen(id) }
        library.onRenamed = { [weak self] note in
            guard let self, note.id == self.activeNote.id, note.content == self.activeNote.content else { return }
            // A local title-only change can safely advance the active revision.
            self.activeNote = note; self.prompter.scriptTitle = note.title; self.prompter.applyLanguage()
        }
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
    func requestOpen(_ id: String) {
        do {
            _ = try store.enqueueOpen(noteId: id)
            if !canOpen() || (prompter.running && prompter.panel.isVisible) || hasUnsavedDraft { library.showMessage("Script queued. It will open after recording, scrolling and editing are idle.") }
            processPendingRequests()
        } catch { library.showError(error) }
    }
    func processPendingRequests() {
        guard canOpen(), !(prompter.running && prompter.panel.isVisible), !hasUnsavedDraft,
              ProcessInfo.processInfo.systemUptime - prompter.lastEditTime > 1 else { return }
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
