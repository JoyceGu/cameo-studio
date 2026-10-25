import AppKit

final class CaptureRegionGuideView: NSView {
    var region: CGRect = .zero
    override func draw(_ dirtyRect: NSRect) {
        // An even-odd path leaves the recording area fully transparent.
        let shade = NSBezierPath(rect: bounds)
        shade.appendRect(region); shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.28).setFill(); shade.fill()
    }
}

final class CaptureRegionGuide {
    private var panel: NSPanel?
    private var target: CaptureTarget?
    func setTarget(_ target: CaptureTarget?) {
        self.target = target
        restore()
    }
    func hide() { panel?.orderOut(nil) }
    func restore() {
        hide()
        guard let target, let crop = target.sourceRect,
              let screen = NSScreen.screens.first(where: {
                  ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == target.displayID
              }) else { panel = nil; return }
        let guide = panel ?? NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        guide.title = L("Recording region guide")
        guide.isReleasedWhenClosed = false; guide.isOpaque = false; guide.backgroundColor = .clear
        guide.ignoresMouseEvents = true; guide.hidesOnDeactivate = false
        guide.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        guide.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // The display filter also excludes the entire TD Capture application.
        guide.sharingType = .none
        guide.setFrame(screen.frame, display: false)
        let view = CaptureRegionGuideView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.region = CGRect(x: crop.minX, y: screen.frame.height - crop.maxY, width: crop.width, height: crop.height)
        guide.contentView = view; panel = guide
        guide.orderFrontRegardless()
    }
    func close() { target = nil; hide(); panel = nil }
}
