import Foundation
import CoreGraphics

enum CaptureRegionGeometry {
    static func crop(selection: CGRect, displaySize: CGSize) -> CGRect? {
        let rect = selection.standardized.integral.intersection(CGRect(origin: .zero, size: displaySize))
        guard !rect.isNull, rect.width >= 32, rect.height >= 32 else { return nil }
        return CGRect(x: rect.minX, y: displaySize.height - rect.maxY, width: rect.width, height: rect.height)
    }
}
