import Foundation
import CoreGraphics

@main struct CaptureRegionGeometryTests {
    static func main() {
        let size = CGSize(width: 1440, height: 900)
        assert(CaptureRegionGeometry.crop(selection: CGRect(x: 100, y: 200, width: 640, height: 360), displaySize: size) == CGRect(x: 100, y: 340, width: 640, height: 360))
        assert(CaptureRegionGeometry.crop(selection: CGRect(x: -20, y: -10, width: 200, height: 100), displaySize: size) == CGRect(x: 0, y: 810, width: 180, height: 90))
        assert(CaptureRegionGeometry.crop(selection: CGRect(x: 10, y: 10, width: 31, height: 100), displaySize: size) == nil)
        assert(CaptureRegionGeometry.crop(selection: CGRect(x: 2000, y: 10, width: 100, height: 100), displaySize: size) == nil)
        assert(CaptureRegionGeometry.crop(selection: CGRect(origin: .zero, size: size), displaySize: size) == CGRect(origin: .zero, size: size))
        // Display-local crop remains unchanged on a secondary display to the left.
        let crop = CaptureRegionGeometry.crop(selection: CGRect(x: 100, y: 200, width: 640, height: 360), displaySize: size)!
        assert(crop.offsetBy(dx: -1440, dy: 120) == CGRect(x: -1340, y: 460, width: 640, height: 360))
        print("Capture region geometry: 6 checks passed")
    }
}
