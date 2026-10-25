import AppKit

@main struct CaptureRegionGuideTests {
    static func main() {
        let view = CaptureRegionGuideView(frame: CGRect(x: 0, y: 0, width: 200, height: 160))
        view.region = CGRect(x: 50, y: 40, width: 100, height: 80)
        let image = NSImage(size: view.bounds.size)
        image.lockFocus(); view.draw(view.bounds); image.unlockFocus()
        let bitmap = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        let sx = CGFloat(bitmap.pixelsWide) / 200
        let sy = CGFloat(bitmap.pixelsHigh) / 160
        func color(_ x: CGFloat, _ y: CGFloat) -> NSColor {
            bitmap.colorAt(x: Int(x * sx), y: Int(y * sy))!.usingColorSpace(.deviceRGB)!
        }
        assert(color(100, 80).alphaComponent < 0.01, "The selected region must remain transparent")
        assert(abs(color(10, 10).alphaComponent - 0.28) < 0.02, "Only the outside region should be dimmed")
        assert(abs(color(48, 80).alphaComponent - 0.28) < 0.02, "The boundary must not add a colored border")
        print("Capture region guide: transparent center, dimmed outside and borderless boundary passed")
    }
}
