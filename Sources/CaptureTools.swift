import AppKit
import CoreImage
import Carbon

struct CaptureStroke {
    var points: [CGPoint]
    let color: NSColor
    let width: CGFloat // Fraction of source width.
}
struct CaptureToolsState {
    var followPointer = true
    var pointer: CGPoint?
    var pressed = false
    var zoom: CGFloat = 1
    var center = CGPoint(x: 0.5, y: 0.5)
    var strokes: [CaptureStroke] = []
    var revision = 0
}

final class CaptureToolsRenderer {
    private var cachedRevision = -1
    private var cachedSize = CGSize.zero
    private var ink: CIImage?

    static func viewport(size: CGSize, zoom: CGFloat, center: CGPoint) -> CGRect {
        let factor = max(1, min(3, zoom))
        let width = size.width / factor, height = size.height / factor
        let x = max(width / 2, min(size.width - width / 2, center.x * size.width))
        let y = max(height / 2, min(size.height - height / 2, center.y * size.height))
        return CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height)
    }
    func render(_ image: CIImage, bounds: CGRect, state: CaptureToolsState) -> CIImage {
        var result = image
        if cachedRevision != state.revision || cachedSize != bounds.size {
            cachedRevision = state.revision; cachedSize = bounds.size; ink = nil
            if !state.strokes.isEmpty, let context = CGContext(data: nil, width: Int(bounds.width), height: Int(bounds.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                context.setLineCap(.round); context.setLineJoin(.round)
                for stroke in state.strokes {
                    guard let first = stroke.points.first else { continue }
                    context.setStrokeColor(stroke.color.cgColor); context.setFillColor(stroke.color.cgColor)
                    context.setLineWidth(stroke.width * bounds.width)
                    let start = CGPoint(x: first.x * bounds.width, y: first.y * bounds.height)
                    if stroke.points.count == 1 {
                        let radius = stroke.width * bounds.width / 2
                        context.fillEllipse(in: CGRect(x: start.x - radius, y: start.y - radius, width: radius * 2, height: radius * 2))
                    } else {
                        context.beginPath(); context.move(to: start)
                        for point in stroke.points.dropFirst() { context.addLine(to: CGPoint(x: point.x * bounds.width, y: point.y * bounds.height)) }
                        context.strokePath()
                    }
                }
                if let cg = context.makeImage() { ink = CIImage(cgImage: cg) }
            }
        }
        if let ink { result = ink.composited(over: result) }
        if state.followPointer, let pointer = state.pointer {
            let point = CGPoint(x: pointer.x * bounds.width, y: pointer.y * bounds.height)
            let radius: CGFloat = state.pressed ? 32 : 21
            if let halo = CIFilter(name: "CIRadialGradient", parameters: ["inputCenter": CIVector(cgPoint: point), "inputRadius0": radius * 0.65, "inputRadius1": radius, "inputColor0": CIColor(red: 1, green: 0.75, blue: 0.18, alpha: state.pressed ? 0.65 : 0.30), "inputColor1": CIColor.clear])?.outputImage {
                result = halo.cropped(to: bounds).composited(over: result)
            }
        }
        let crop = Self.viewport(size: bounds.size, zoom: state.zoom, center: state.center)
        result = result.transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            .transformed(by: CGAffineTransform(scaleX: bounds.width / crop.width, y: bounds.height / crop.height))
        return result.cropped(to: bounds)
    }
}

private final class AnnotationCanvas: NSView {
    var strokes: [CaptureStroke] = [] { didSet { needsDisplay = true } }
    var onPoint: ((CGPoint, Bool) -> Void)?
    var drawingEnabled = false { didSet { needsDisplay = true } }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { send(event, begins: true) }
    override func mouseDragged(with event: NSEvent) { send(event, begins: false) }
    private func send(_ event: NSEvent, begins: Bool) {
        let p = convert(event.locationInWindow, from: nil)
        guard bounds.width > 0, bounds.height > 0 else { return }
        onPoint?(CGPoint(x: max(0, min(1, p.x / bounds.width)), y: max(0, min(1, p.y / bounds.height))), begins)
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func draw(_ dirtyRect: NSRect) {
        if drawingEnabled {
            // A visible hit surface makes drawing mode discoverable and avoids
            // an entirely transparent window being treated as click-through.
            SetupTheme.accent.withAlphaComponent(0.07).setFill(); bounds.fill()
            SetupTheme.accent.withAlphaComponent(0.8).setStroke()
            let border = NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2)); border.lineWidth = 2; border.stroke()
        }
        for stroke in strokes {
            guard let first = stroke.points.first else { continue }
            stroke.color.setStroke(); stroke.color.setFill()
            let path = NSBezierPath(); path.lineWidth = stroke.width * bounds.width; path.lineCapStyle = .round; path.lineJoinStyle = .round
            let p = NSPoint(x: first.x * bounds.width, y: first.y * bounds.height)
            if stroke.points.count == 1 {
                let radius = path.lineWidth / 2
                NSBezierPath(ovalIn: NSRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)).fill()
            } else {
                path.move(to: p)
                for point in stroke.points.dropFirst() { path.line(to: NSPoint(x: point.x * bounds.width, y: point.y * bounds.height)) }
                path.stroke()
            }
        }
    }
}
private final class AnnotationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private let captureHotKeyHandler: EventHandlerUPP = { _, event, context in
    guard let event, let context else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
    guard result == noErr else { return result }
    let controller = Unmanaged<CaptureControlPanel>.fromOpaque(context).takeUnretainedValue()
    let command = id.id
    DispatchQueue.main.async { controller.handleShortcut(command) }
    return noErr
}

final class CaptureControlPanel: NSObject, NSWindowDelegate {
    let panel: NSPanel
    private let heading = NSTextField(labelWithString: "")
    private let follow = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let pen = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let shortcuts = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let shortcutHeading = NSTextField(labelWithString: "")
    private let clear = NSButton(title: "", target: nil, action: nil)
    private let color = NSPopUpButton()
    private let help = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let zoomHUD = AnnotationPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let hudLabel = NSTextField(labelWithString: "")
    private var hudDismiss: DispatchWorkItem?
    private let canvas = AnnotationCanvas()
    private let overlay = AnnotationPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var target: CaptureTarget?
    private var timer: Timer?
    private var activeSession = false
    private var hotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var localKeyMonitor: Any?
    private var state = CaptureToolsState()
    var onState: ((CaptureToolsState) -> Void)?

    override init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 560), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        super.init()
        panel.isReleasedWhenClosed = false; panel.delegate = self
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .aqua)
        let paper = WatercolorSetupView(); panel.contentView = paper
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false; paper.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: paper.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: paper.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: paper.topAnchor, constant: 24),
            root.bottomAnchor.constraint(lessThanOrEqualTo: paper.bottomAnchor, constant: -20)
        ])
        heading.font = .systemFont(ofSize: 20, weight: .semibold); heading.textColor = SetupTheme.ink
        heading.heightAnchor.constraint(equalToConstant: 32).isActive = true; root.addArrangedSubview(heading)
        for control in [follow, pen, shortcuts] {
            control.target = self; control.action = #selector(optionsChanged)
            control.font = .systemFont(ofSize: 13); control.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
        follow.state = .on
        let savedShortcuts = UserDefaults.standard.object(forKey: "controls.shortcutsEnabled") as? Bool
        shortcuts.state = (savedShortcuts ?? true) ? .on : .off
        let options = SetupTheme.stack([follow, pen], vertical: true, spacing: 10)
        root.addArrangedSubview(options)
        color.addItems(withTitles: ["Rose", "Amber", "Blue"])
        clear.target = self; clear.action = #selector(clearInk); SetupTheme.button(clear)
        options.addArrangedSubview(SetupTheme.stack([color, clear]))
        options.addArrangedSubview(shortcuts)
        let shortcutSection = SetupTheme.stack([], vertical: true, spacing: 10)
        root.addArrangedSubview(shortcutSection)
        shortcutSection.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        shortcutHeading.font = .systemFont(ofSize: 14, weight: .semibold); shortcutHeading.textColor = SetupTheme.ink
        shortcutHeading.heightAnchor.constraint(equalToConstant: 24).isActive = true
        shortcutSection.addArrangedSubview(shortcutHeading)
        help.font = .systemFont(ofSize: 11); help.textColor = SetupTheme.muted; help.preferredMaxLayoutWidth = 372
        shortcutSection.addArrangedSubview(help)
        help.widthAnchor.constraint(equalTo: shortcutSection.widthAnchor).isActive = true
        status.font = .systemFont(ofSize: 11); status.textColor = SetupTheme.muted; status.preferredMaxLayoutWidth = 372
        root.addArrangedSubview(status)
        status.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        overlay.isReleasedWhenClosed = false; overlay.isOpaque = false; overlay.backgroundColor = .clear; overlay.hasShadow = false
        overlay.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; overlay.contentView = canvas
        zoomHUD.isReleasedWhenClosed = false; zoomHUD.isOpaque = false; zoomHUD.backgroundColor = .clear
        zoomHUD.ignoresMouseEvents = true; zoomHUD.hasShadow = true
        zoomHUD.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 3)
        zoomHUD.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hudBackground = NSVisualEffectView(); hudBackground.material = .hudWindow; hudBackground.state = .active
        hudBackground.wantsLayer = true; hudBackground.layer?.cornerRadius = 14; hudBackground.layer?.masksToBounds = true
        zoomHUD.contentView = hudBackground
        hudLabel.font = .systemFont(ofSize: 14, weight: .semibold); hudLabel.alignment = .center
        hudLabel.translatesAutoresizingMaskIntoConstraints = false; hudBackground.addSubview(hudLabel)
        NSLayoutConstraint.activate([
            hudLabel.leadingAnchor.constraint(equalTo: hudBackground.leadingAnchor, constant: 20),
            hudLabel.trailingAnchor.constraint(equalTo: hudBackground.trailingAnchor, constant: -20),
            hudLabel.centerYAnchor.constraint(equalTo: hudBackground.centerYAnchor)
        ])
        canvas.onPoint = { [weak self] point, begins in self?.addPoint(point, begins: begins) }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        // App-directed key events and regular system hotkeys take separate routes.
        // Carbon consumes registered system events; the local fallback handles
        // key equivalents delivered directly to this application's event queue.
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.shortcuts.state == .on,
                  event.modifierFlags.intersection([.command, .option, .control]) == [.command, .option],
                  !event.modifierFlags.contains(.shift) || Int(event.keyCode) == kVK_ANSI_Equal,
                  let command = [(kVK_ANSI_Equal, UInt32(1)), (kVK_ANSI_Minus, 2), (kVK_ANSI_0, 3), (kVK_ANSI_P, 4), (kVK_ANSI_K, 6)].first(where: { $0.0 == Int(event.keyCode) })?.1 else { return event }
            self.handleShortcut(command); return nil
        }
        applyLanguage(); configureShortcuts()
    }
    func applyLanguage() {
        panel.title = L("Recording controls"); heading.stringValue = L("Recording controls")
        follow.title = L("Track and highlight pointer"); pen.title = L("Draw on the source")
        shortcuts.title = L("Enable keyboard shortcuts"); clear.title = L("Clear drawing")
        shortcutHeading.stringValue = L("Keyboard shortcuts")
        pen.toolTip = L("Drag inside the selected source to draw. ⌘⌥P toggles the pen when shortcuts are enabled.")
        let selected = color.indexOfSelectedItem; color.removeAllItems()
        color.addItems(withTitles: ["Rose", "Amber", "Blue"].map { L($0) }); color.selectItem(at: max(0, selected))
        help.stringValue = L("⌘⌥ =     Magnify to 3×\n⌘⌥ − / 0   Return to 1×\n⌘⌥ P     Toggle pen on / off\n⌘⌥ K     Clear all drawing")
        status.stringValue = L("Choose a source first. This panel stays out of the recording.")
    }
    func setTarget(_ target: CaptureTarget) {
        self.target = target; state = CaptureToolsState()
        follow.isEnabled = target.supportsPointerCoordinates; pen.isEnabled = target.supportsPointerCoordinates
        state.followPointer = follow.state == .on && target.supportsPointerCoordinates
        pen.state = .off; canvas.strokes = []; overlay.orderOut(nil)
        status.stringValue = L(target.supportsPointerCoordinates ? "Source ready. Drawing and zoom will be included in the video." : "Window pointer tracking and drawing require macOS 15.2 or later. Centered zoom is still available.")
        updateHUD(); publish()
    }
    func startSession(target: CaptureTarget) { self.target = target; activeSession = true; tick() }
    func endSession() { activeSession = false; pen.state = .off; canvas.drawingEnabled = false; overlay.orderOut(nil); updateHUD() }
    func show() { panel.center(); panel.makeKeyAndOrderFront(nil) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { pen.state = .off; updateOverlay(); updateHUD(); return true }
    @objc private func optionsChanged() {
        UserDefaults.standard.set(shortcuts.state == .on, forKey: "controls.shortcutsEnabled")
        state.followPointer = follow.state == .on && target?.supportsPointerCoordinates == true
        configureShortcuts()
        if pen.state == .on {
            guard let target, target.supportsPointerCoordinates else {
                pen.state = .off; updateHUD()
                let alert = NSAlert(); alert.messageText = L("Choose a recording source first")
                alert.informativeText = L("The pen draws over the selected window or screen. Choose a source on the setup screen, then enable the pen and drag inside its purple border. The strokes are saved into the video.")
                alert.addButton(withTitle: L("OK")); alert.beginSheetModal(for: panel)
                status.stringValue = L("Choose a source before drawing."); return
            }
            status.stringValue = L("Pen on: drag inside the purple border to draw. Turn it off to click normally.")
        } else { status.stringValue = L("Pen off: normal clicks are restored. Existing strokes remain until cleared.") }
        updateOverlay(); updateHUD(); publish()
    }
    private func updateHUD(transient: String? = nil) {
        hudDismiss?.cancel()
        var parts: [String] = []
        if state.zoom > 1 { parts.append(L("Recording zoom · %.1f×", Double(state.zoom))) }
        if pen.state == .on { parts.append(L("Pen on · Drag to draw · ⌘⌥P to exit")) }
        if parts.isEmpty, let transient { parts = [transient] }
        guard !parts.isEmpty else { zoomHUD.orderOut(nil); return }
        hudLabel.stringValue = parts.joined(separator: "  ·  ")
        let width = min(760, max(240, hudLabel.intrinsicContentSize.width + 40))
        let screen = NSScreen.screens.first(where: { screen in
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            let frame = target?.currentFrame ?? .zero
            return screen.frame.contains(NSPoint(x: frame.midX, y: top - frame.midY))
        }) ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        zoomHUD.setFrame(NSRect(x: visible.midX - width / 2, y: visible.maxY - 62, width: width, height: 44), display: true)
        zoomHUD.orderFrontRegardless()
        if state.zoom == 1 && pen.state != .on {
            let dismiss = DispatchWorkItem { [weak self] in self?.zoomHUD.orderOut(nil) }
            hudDismiss = dismiss; DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: dismiss)
        }
    }
    private func updateOverlay() {
        guard let target, target.supportsPointerCoordinates else { overlay.orderOut(nil); return }
        let frame = target.currentFrame
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        overlay.setFrame(NSRect(x: frame.minX, y: top - frame.maxY, width: frame.width, height: frame.height), display: true)
        canvas.drawingEnabled = pen.state == .on
        overlay.ignoresMouseEvents = pen.state != .on
        overlay.invalidateCursorRects(for: canvas)
        if pen.state == .on || (!state.strokes.isEmpty && (activeSession || panel.isVisible)) { overlay.orderFrontRegardless() }
        else { overlay.orderOut(nil) }
    }
    private func tick() {
        guard activeSession || panel.isVisible || pen.state == .on, let target, target.supportsPointerCoordinates else { return }
        let frame = target.currentFrame
        let point = CGEvent(source: nil)?.location ?? .zero
        if frame.contains(point) && frame.width > 0 && frame.height > 0 {
            state.pointer = CGPoint(x: (point.x - frame.minX) / frame.width, y: 1 - (point.y - frame.minY) / frame.height)
            if state.followPointer, let pointer = state.pointer { state.center = pointer }
        } else { state.pointer = nil }
        state.pressed = NSEvent.pressedMouseButtons & 1 != 0
        updateOverlay(); publish()
    }
    private func addPoint(_ point: CGPoint, begins: Bool) {
        let colors: [NSColor] = [.systemPink, .systemOrange, .systemBlue]
        if begins {
            guard state.strokes.count < 200 else { status.stringValue = L("Drawing limit reached. Clear the drawing to continue."); return }
            state.strokes.append(CaptureStroke(points: [point], color: colors[max(0, color.indexOfSelectedItem)], width: 0.0035))
        } else if !state.strokes.isEmpty, state.strokes[state.strokes.count - 1].points.count < 4000 {
            state.strokes[state.strokes.count - 1].points.append(point)
        }
        state.revision += 1; canvas.strokes = state.strokes; publish()
    }
    @objc private func clearInk() {
        state.strokes = []; state.revision += 1; canvas.strokes = []
        status.stringValue = L("Drawing cleared. The current pen mode is unchanged.")
        updateOverlay(); publish()
    }
    @objc private func increaseZoom() { setZoom(3) }
    @objc private func decreaseZoom() { setZoom(1) }
    @objc private func resetZoom() { setZoom(1) }
    private func setZoom(_ value: CGFloat) {
        let previous = state.zoom
        tick(); state.zoom = max(1, min(3, value))
        if let pointer = state.pointer { state.center = pointer }
        let message = state.zoom > previous ? "Zoomed in to %.1f×. The exported video is magnified." :
            (state.zoom < previous ? "Zoomed out to %.1f×." : "Zoom is already %.1f×.")
        status.stringValue = L(message, Double(state.zoom))
        updateHUD(transient: L("Restored to original size · 1×")); publish()
    }
    private func publish() { onState?(state) }
    private func configureShortcuts() {
        guard shortcuts.state == .on else {
            let wasEnabled = !hotKeys.isEmpty
            unregisterShortcuts()
            if wasEnabled { status.stringValue = L("Global shortcuts disabled.") }
            return
        }
        guard hotKeys.isEmpty else { return }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            guard InstallEventHandler(GetEventDispatcherTarget(), captureHotKeyHandler, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler) == noErr else { shortcuts.state = .off; return }
        }
        let combinations: [(Int, UInt32)] = [
            (kVK_ANSI_Equal, UInt32(cmdKey | optionKey)),
            (kVK_ANSI_Minus, UInt32(cmdKey | optionKey)),
            (kVK_ANSI_0, UInt32(cmdKey | optionKey)),
            (kVK_ANSI_P, UInt32(cmdKey | optionKey)),
            (kVK_ANSI_Equal, UInt32(cmdKey | optionKey | shiftKey)),
            (kVK_ANSI_K, UInt32(cmdKey | optionKey))
        ]
        for (index, combination) in combinations.enumerated() {
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: 0x54444350, id: UInt32(index + 1))
            let result = RegisterEventHotKey(UInt32(combination.0), combination.1, id, GetEventDispatcherTarget(), 0, &reference)
            guard result == noErr, let reference else {
                unregisterShortcuts(); shortcuts.state = .off; status.stringValue = L("A shortcut is already in use. Disable it in the other app and try again."); return
            }
            hotKeys.append(reference)
        }
        status.stringValue = L("Global shortcuts enabled. They work while another app is focused.")
    }
    private func unregisterShortcuts() { for key in hotKeys { UnregisterEventHotKey(key) }; hotKeys = [] }
    func handleShortcut(_ command: UInt32) {
        guard shortcuts.state == .on else { return }
        switch command {
        case 1, 5: increaseZoom()
        case 2: decreaseZoom()
        case 3: resetZoom()
        case 4: pen.state = pen.state == .on ? .off : .on; optionsChanged()
        case 6: clearInk()
        default: break
        }
    }
    func close() { hudDismiss?.cancel(); zoomHUD.orderOut(nil); unregisterShortcuts(); if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }; if let handler { RemoveEventHandler(handler) }; timer?.invalidate(); overlay.orderOut(nil) }
}
