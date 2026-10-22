import AppKit
import AVFoundation
import Vision
import CoreImage

struct BackgroundPreset {
    let name: String
    let file: String
}
let backgroundPresets = [
    BackgroundPreset(name: "Bright study", file: "background-study"),
    BackgroundPreset(name: "Soft nature", file: "background-nature"),
    BackgroundPreset(name: "Soft watercolor", file: "background-watercolor")
]
struct BackgroundSettings: Sendable {
    var mode: Int = 0 // original, blur, image
    var preset: Int = 0
    var strength: Double = 18
    static func load() -> BackgroundSettings {
        let d = UserDefaults.standard
        let savedStrength = d.object(forKey: "camera.background.strength") as? Double ?? 18
        return BackgroundSettings(mode: min(2, max(0, d.integer(forKey: "camera.background.mode"))), preset: min(backgroundPresets.count-1, max(0, d.integer(forKey: "camera.background.preset"))), strength: min(40, max(4, savedStrength)))
    }
    func save() {
        let d = UserDefaults.standard
        d.set(mode, forKey: "camera.background.mode"); d.set(preset, forKey: "camera.background.preset"); d.set(strength, forKey: "camera.background.strength")
    }
    var image: CIImage? {
        guard backgroundPresets.indices.contains(preset), let url = Bundle.main.url(forResource: backgroundPresets[preset].file, withExtension: "png") else { return nil }
        return CIImage(contentsOf: url, options: [.applyOrientationProperty: true])
    }
}

// Accessed exclusively by Recorder.effectsQueue. Vision never blocks audio or encoding.
final class BackgroundProcessor {
    let context = CIContext(options: [.cacheIntermediates: false])
    let request: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()
    var settings = BackgroundSettings()
    var replacement: CIImage?
    var lastProcessed: Double = 0
    var lastWarning: String?

    func update(_ value: BackgroundSettings) {
        settings = value; replacement = value.mode == 2 ? value.image : nil
        lastProcessed = 0; lastWarning = nil
    }
    static func fit(_ image: CIImage, to bounds: CGRect) -> CIImage {
        var image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let scale = max(bounds.width / image.extent.width, bounds.height / image.extent.height)
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return image.transformed(by: CGAffineTransform(translationX: bounds.midX - image.extent.midX, y: bounds.midY - image.extent.midY)).cropped(to: bounds)
    }
    static func blend(_ image: CIImage, mask: CIImage, settings: BackgroundSettings, replacement: CIImage?) -> CIImage {
        let bounds = image.extent
        let background: CIImage
        if settings.mode == 1 {
            background = image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: settings.strength]).cropped(to: bounds)
        } else {
            background = replacement.map { fit($0, to: bounds) } ?? CIImage(color: CIColor(red: 0.87, green: 0.9, blue: 0.94)).cropped(to: bounds)
        }
        let scaledMask = mask.transformed(by: CGAffineTransform(scaleX: bounds.width / mask.extent.width, y: bounds.height / mask.extent.height))
            .clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.7]).cropped(to: bounds)
        return image.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: background, kCIInputMaskImageKey: scaledMask]).cropped(to: bounds)
    }
    func process(_ pixel: CVPixelBuffer) -> (CIImage, String?)? {
        let now = ProcessInfo.processInfo.systemUptime
        // Keep segmentation responsive without queuing old camera frames.
        guard now - lastProcessed >= 1.0 / (settings.mode == 0 ? 30 : 15) else { return nil }
        lastProcessed = now
        var image = CIImage(cvPixelBuffer: pixel)
        let scale = min(1, 960 / image.extent.width)
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard settings.mode != 0 else { return (image, nil) }
        do {
            // The request and rendering use the same upright image coordinates.
            try VNImageRequestHandler(ciImage: image, orientation: .up, options: [:]).perform([request])
            guard let observation = request.results?.first else { throw StudioError(message: "Person detection is unavailable. The original background is hidden.") }
            if settings.mode == 2 && replacement == nil { throw StudioError(message: "Background image unavailable. The original background is hidden.") }
            let mask = CIImage(cvPixelBuffer: observation.pixelBuffer)
            return (Self.blend(image, mask: mask, settings: settings, replacement: replacement), nil)
        } catch {
            // Never expose the untreated room when an effect is selected but fails.
            let safe = replacement.map { Self.fit($0, to: image.extent) } ?? CIImage(color: CIColor(red: 0.87, green: 0.9, blue: 0.94)).cropped(to: image.extent)
            return (safe, "Background processing unavailable. The original picture is hidden. Choose Original background or try again.")
        }
    }
}

final class BackgroundPanel: NSObject {
    let panel: NSPanel
    let mode = NSPopUpButton()
    let strength = NSSlider(value: 18, minValue: 4, maxValue: 40, target: nil, action: nil)
    let heading = NSTextField(labelWithString: "")
    let strengthLabel = NSTextField(labelWithString: "")
    let note = NSTextField(wrappingLabelWithString: "")
    let warning = NSTextField(wrappingLabelWithString: "")
    var buttons: [NSButton] = []
    var settings: BackgroundSettings
    var onChange: ((BackgroundSettings) -> Void)?
    init(settings: BackgroundSettings) {
        self.settings = settings
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 350), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        panel.isReleasedWhenClosed = false; panel.level = .floating
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        panel.contentView = root
        root.addArrangedSubview(heading)
        mode.target = self; mode.action = #selector(modeChanged)
        mode.widthAnchor.constraint(equalToConstant: 500).isActive = true; root.addArrangedSubview(mode)
        let sliderRow = NSStackView(views: [strengthLabel, strength]); sliderRow.spacing = 16
        strength.widthAnchor.constraint(equalToConstant: 320).isActive = true
        strength.target = self; strength.action = #selector(strengthChanged); strength.doubleValue = settings.strength
        root.addArrangedSubview(sliderRow)
        let presets = NSStackView(); presets.spacing = 12
        for (i, preset) in backgroundPresets.enumerated() {
            let button = NSButton(title: L(preset.name), target: self, action: #selector(presetSelected(_:)))
            button.tag = i; button.imagePosition = .imageAbove; button.imageScaling = .scaleProportionallyDown
            button.setButtonType(.toggle); button.bezelStyle = .regularSquare
            if let url = Bundle.main.url(forResource: preset.file, withExtension: "png") {
                let image = NSImage(contentsOf: url); image?.size = NSSize(width: 144, height: 81); button.image = image
            }
            button.widthAnchor.constraint(equalToConstant: 156).isActive = true
            button.heightAnchor.constraint(equalToConstant: 118).isActive = true
            buttons.append(button); presets.addArrangedSubview(button)
        }
        root.addArrangedSubview(presets)
        note.preferredMaxLayoutWidth = 500; note.font = .systemFont(ofSize: 12); note.textColor = .secondaryLabelColor
        warning.preferredMaxLayoutWidth = 500; warning.font = .systemFont(ofSize: 12); warning.textColor = .systemOrange
        root.addArrangedSubview(note); root.addArrangedSubview(warning)
        applyLanguage()
    }
    func applyLanguage() {
        panel.title = L("Camera background")
        heading.stringValue = L("Choose your camera background")
        mode.removeAllItems(); mode.addItems(withTitles: [L("Original background"), L("Blur background"), L("Image background")]); mode.selectItem(at: settings.mode)
        strengthLabel.stringValue = L("Blur strength")
        for (i, b) in buttons.enumerated() { b.title = L(backgroundPresets[i].name) }
        note.stringValue = L("Effects appear in the preview and recording. Processed on your Mac; hair, fingers and fast movement may have imperfect edges.")
        refresh()
    }
    func refresh() {
        mode.selectItem(at: settings.mode); strength.isEnabled = settings.mode == 1
        for (i, button) in buttons.enumerated() { button.state = settings.mode == 2 && settings.preset == i ? .on : .off }
    }
    func notify() { settings.save(); refresh(); onChange?(settings) }
    @objc func modeChanged() { settings.mode = mode.indexOfSelectedItem; notify() }
    @objc func strengthChanged() { settings.strength = strength.doubleValue; notify() }
    @objc func presetSelected(_ sender: NSButton) { settings.mode = 2; settings.preset = sender.tag; notify() }
    func show() { panel.center(); panel.makeKeyAndOrderFront(nil) }
}
func runBackgroundTests(photoPath: String, outputPath: String) throws {
    let fm = FileManager.default
    let folder = URL(fileURLWithPath: outputPath)
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    let context = CIContext(options: [.cacheIntermediates: false])
    let bounds = CGRect(x: 0, y: 0, width: 320, height: 240)
    let stripes = CIFilter(name: "CIStripesGenerator", parameters: ["inputCenter": CIVector(x: 0, y: 0), "inputColor0": CIColor.white, "inputColor1": CIColor.black, "inputWidth": 10, "inputSharpness": 1])!.outputImage!.cropped(to: bounds)
    let subjectRect = CGRect(x: 110, y: 50, width: 100, height: 140)
    let subject = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: subjectRect).composited(over: stripes)
    let mask = CIImage(color: CIColor.white).cropped(to: subjectRect).composited(over: CIImage(color: CIColor.black).cropped(to: bounds))
    func pixel(_ image: CIImage, _ x: Int, _ y: Int) throws -> NSColor {
        guard let cg = context.createCGImage(image, from: bounds), let c = NSBitmapImageRep(cgImage: cg).colorAt(x: x, y: y) else { throw StudioError(message: "Test pixel read failed") }
        return c
    }
    let blur = BackgroundProcessor.blend(subject, mask: mask, settings: BackgroundSettings(mode: 1, preset: 0, strength: 20), replacement: nil)
    let face = try pixel(blur, 160, 120), blurredStripe = try pixel(blur, 35, 120)
    guard face.redComponent > 0.9, face.greenComponent < 0.05, blurredStripe.redComponent > 0.2, blurredStripe.redComponent < 0.8 else { throw StudioError(message: "Blur must preserve subject and soften background") }
    let replaced = BackgroundProcessor.blend(subject, mask: mask, settings: BackgroundSettings(mode: 2), replacement: CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: bounds))
    let outside = try pixel(replaced, 35, 120), inside = try pixel(replaced, 160, 120)
    guard outside.blueComponent > 0.9, outside.redComponent < 0.05, inside.redComponent > 0.9 else { throw StudioError(message: "Image replacement must preserve subject") }
    guard let photo = CIImage(contentsOf: URL(fileURLWithPath: photoPath)) else { throw StudioError(message: "Test portrait missing") }
    var buffer: CVPixelBuffer?
    guard CVPixelBufferCreate(nil, Int(photo.extent.width), Int(photo.extent.height), kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer) == kCVReturnSuccess, let buffer else { throw StudioError(message: "Test buffer failed") }
    context.render(photo, to: buffer)
    let processor = BackgroundProcessor()
    for (name, settings) in [
        ("original", BackgroundSettings()),
        ("blur", BackgroundSettings(mode: 1, strength: 28)),
        ("study", BackgroundSettings(mode: 2, preset: 0)),
        ("nature", BackgroundSettings(mode: 2, preset: 1)),
        ("watercolor", BackgroundSettings(mode: 2, preset: 2))
    ] {
        processor.update(settings)
        guard let (image, warning) = processor.process(buffer), warning == nil,
              let cg = context.createCGImage(image, from: image.extent),
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { throw StudioError(message: "Vision effect failed: \(name)") }
        try png.write(to: folder.appendingPathComponent(name + ".png"))
        if settings.mode != 0 {
            guard let observation = processor.request.results?.first else { throw StudioError(message: "No segmentation mask") }
            let maskImage = CIImage(cvPixelBuffer: observation.pixelBuffer)
            let average = maskImage.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: maskImage.extent)])
            var bytes: [UInt8] = [0,0,0,0]
            context.render(average, toBitmap: &bytes, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            guard bytes[0] > 15, bytes[0] < 240 else { throw StudioError(message: "Mask should contain both a person and a background") }
        }
    }
    print("PASS: blur/replacement foreground preservation; Vision person mask; all 3 bundled backgrounds; preview image rendering")
}
