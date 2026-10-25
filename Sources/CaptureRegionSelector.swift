import AppKit

private final class RegionSelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class RegionSelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    private var anchor: CGPoint?
    private var selection = CGRect.zero
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish?(nil) } else { super.keyDown(with: event) }
    }
    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
        selection = .zero; needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(anchor.x, point.x), y: min(anchor.y, point.y),
                           width: abs(point.x - anchor.x), height: abs(point.y - anchor.y)).intersection(bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        guard selection.width >= 32, selection.height >= 32 else { return }
        onFinish?(selection.integral.intersection(bounds))
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.38).setFill(); bounds.fill()
        if !selection.isEmpty {
            NSColor.clear.setFill(); selection.fill(using: .copy)
        }
        let message = selection.isEmpty ? L("Drag to select a recording area · Esc to cancel") : L("Release to select · %d × %d pt · Esc to cancel", Int(selection.width), Int(selection.height))
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: NSColor.white, .backgroundColor: NSColor.black.withAlphaComponent(0.75)]
        message.draw(at: CGPoint(x: 24, y: bounds.height - 60), withAttributes: attributes)
    }
}

final class CaptureRegionSelector {
    private var panels: [NSPanel] = []
    private var completion: ((CGDirectDisplayID, CGRect) -> Void)?
    private var onCancel: (() -> Void)?
    func select(completion: @escaping (CGDirectDisplayID, CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.completion = completion; self.onCancel = onCancel
        for screen in NSScreen.screens {
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { continue }
            let panel = RegionSelectionPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.title = L("Select recording region")
            panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.level = .screenSaver; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            let view = RegionSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.onFinish = { [weak self] rect in
                guard let self else { return }
                guard let rect else { self.cancel(); return }
                guard let crop = CaptureRegionGeometry.crop(selection: rect, displaySize: screen.frame.size) else { return }
                let callback = self.completion
                self.dismiss(); callback?(id, crop)
            }
            panel.contentView = view; panels.append(panel)
            panel.orderFrontRegardless(); panel.makeFirstResponder(view)
        }
        guard !panels.isEmpty else { cancel(); return }
        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation
        let active = panels.first(where: { $0.frame.contains(mouse) }) ?? panels[0]
        active.makeKeyAndOrderFront(nil)
    }
    func cancel() {
        let callback = onCancel; dismiss(); callback?()
    }
    private func dismiss() {
        panels.forEach { $0.orderOut(nil) }; panels.removeAll()
        completion = nil; onCancel = nil
    }
}
