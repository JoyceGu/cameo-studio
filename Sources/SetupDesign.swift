import AppKit

// The setup palette follows the bundled watercolor background, with opaque text
// and native controls so the paper treatment never reduces legibility.
enum SetupTheme {
    static let ink = NSColor(srgbRed: 0.20, green: 0.23, blue: 0.28, alpha: 1)
    static let muted = NSColor(srgbRed: 0.40, green: 0.43, blue: 0.47, alpha: 1)
    static let accent = NSColor(srgbRed: 0.40, green: 0.36, blue: 0.59, alpha: 1)
    static let sage = NSColor(srgbRed: 0.34, green: 0.46, blue: 0.39, alpha: 1)

    static func stack(_ views: [NSView], vertical: Bool = false, spacing: CGFloat = 12) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = vertical ? .vertical : .horizontal
        stack.alignment = vertical ? .leading : .centerY
        stack.spacing = spacing
        return stack
    }

    static func symbol(_ name: String, color: NSColor = accent, size: CGFloat = 18) -> NSImageView {
        let image = NSImageView()
        image.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .medium))
        image.contentTintColor = color
        image.widthAnchor.constraint(equalToConstant: size + 8).isActive = true
        image.heightAnchor.constraint(equalToConstant: size + 8).isActive = true
        return image
    }

    static func button(_ button: NSButton, prominent: Bool = false) {
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.contentTintColor = prominent ? .white : ink
        if prominent { button.bezelColor = accent }
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
    }
}

final class WatercolorSetupView: NSView {
    private let paper = Bundle.main.url(forResource: "background-watercolor", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 0.97, green: 0.96, blue: 0.93, alpha: 1).setFill()
        bounds.fill()
        paper?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 0.88)
    }
}

final class SetupCard: NSView {
    let content = NSStackView()
    init(tint: NSColor = .white, padding: CGFloat = 20) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = tint.withAlphaComponent(0.86).cgColor
        layer?.cornerRadius = 20
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        layer?.shadowColor = SetupTheme.ink.cgColor
        layer?.shadowOpacity = 0.04
        layer?.shadowRadius = 12
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        content.orientation = .vertical; content.alignment = .leading; content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            content.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            content.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -padding)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

final class SetupRecordButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 16, yRadius: 16)
        let fill = isEnabled ? SetupTheme.accent : SetupTheme.muted.withAlphaComponent(0.45)
        (cell?.isHighlighted == true ? fill.blended(withFraction: 0.16, of: .black) ?? fill : fill).setFill()
        shape.fill()
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke(); shape.lineWidth = 3; shape.stroke()
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let text = title as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
}

final class SetupSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = NSRect(x: rect.minX, y: rect.midY - 2, width: rect.width, height: 4)
        NSColor(srgbRed: 0.87, green: 0.87, blue: 0.89, alpha: 1).setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
        let progress = max(0, min(1, (doubleValue - minValue) / max(0.001, maxValue - minValue)))
        let filled = NSRect(x: track.minX, y: track.minY, width: track.width * progress, height: track.height)
        SetupTheme.accent.withAlphaComponent(isEnabled ? 1 : 0.4).setFill()
        NSBezierPath(roundedRect: filled, xRadius: 2, yRadius: 2).fill()
    }
}
