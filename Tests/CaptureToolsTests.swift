import AppKit
import CoreImage

@main struct CaptureToolsTests {
    static func main() throws {
        let size = CGSize(width: 200, height: 100)
        let full = CaptureToolsRenderer.viewport(size: size, zoom: 1, center: .zero)
        precondition(full == CGRect(origin: .zero, size: size))
        let edge = CaptureToolsRenderer.viewport(size: size, zoom: 2, center: CGPoint(x: 1, y: 1))
        precondition(edge == CGRect(x: 100, y: 50, width: 100, height: 50))
        let bounds = CGRect(origin: .zero, size: size)
        let background = CIImage(color: .black).cropped(to: bounds)
        let marker = CIImage(color: CIColor(red: 0, green: 1, blue: 0)).cropped(to: CGRect(x: 120, y: 60, width: 20, height: 10))
        var state = CaptureToolsState(); state.followPointer = false; state.zoom = 2; state.center = CGPoint(x: 1, y: 1)
        let renderer = CaptureToolsRenderer(); let context = CIContext()
        func pixel(_ image: CIImage, x: Int, y: Int) -> NSColor {
            let cg = context.createCGImage(image, from: bounds)!
            return NSBitmapImageRep(cgImage: cg).colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
        }
        let zoomed = renderer.render(marker.composited(over: background), bounds: bounds, state: state)
        precondition(pixel(zoomed, x: 50, y: 70).greenComponent > 0.9)
        precondition(pixel(zoomed, x: 10, y: 10).greenComponent < 0.1)
        state.zoom = 1
        state.strokes = [CaptureStroke(points: [CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.8, y: 0.5)], color: .red, width: 0.04)]
        state.revision += 1
        let ink = renderer.render(background, bounds: bounds, state: state)
        precondition(pixel(ink, x: 100, y: 50).redComponent > 0.9)
        state.strokes = []; state.revision += 1
        let cleared = renderer.render(background, bounds: bounds, state: state)
        precondition(pixel(cleared, x: 100, y: 50).redComponent < 0.1)
        state.followPointer = true; state.pointer = CGPoint(x: 0.5, y: 0.5)
        let hover = pixel(renderer.render(background, bounds: bounds, state: state), x: 100, y: 50)
        state.pressed = true
        let click = pixel(renderer.render(background, bounds: bounds, state: state), x: 100, y: 50)
        precondition(click.redComponent > hover.redComponent && hover.redComponent > 0.1)
        print("PASS: zoom mapping, edge clamping, ink compositing, clear cache, pointer and click emphasis")
    }
}
