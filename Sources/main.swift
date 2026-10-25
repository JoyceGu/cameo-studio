import AppKit
import AVFoundation
import ScreenCaptureKit
import CoreImage
import CoreMedia
import UniformTypeIdentifiers
import Vision


struct StudioError: LocalizedError {
    let message: String
    var errorDescription: String? { L(message) }
}
func availableCameras() -> [AVCaptureDevice] {
    AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera], mediaType: .video, position: .unspecified).devices
}
func availableMicrophones() -> [AVCaptureDevice] {
    AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
}
struct Layout {
    var fraction: CGFloat = 0.23
    var corner = 3 // 0 upper-left, 1 upper-right, 2 lower-left, 3 lower-right
    var round = true
    var mirror = true
    var x: CGFloat? = nil
    var y: CGFloat? = nil

    func cameraRect(in size: CGSize) -> CGRect {
        let side = min(size.width, size.height) * fraction * 1.5
        let height = round ? side : side * 0.75
        let margin = size.width * 0.025
        let bottomInset = min(max(margin, size.height * 0.12), max(0, size.height - height - margin))
        let originX = x.map { $0 * (size.width - side) } ?? (corner % 2 == 0 ? margin : size.width - side - margin)
        let originY = y.map { $0 * (size.height - height) } ?? (corner < 2 ? size.height - height - margin : bottomInset)
        return CGRect(x: originX, y: originY, width: side, height: height)
    }
}

// Encoded media, layout and writer operations share one serial queue; camera effects use a separate queue.
final class Recorder: NSObject, @unchecked Sendable, SCStreamOutput, SCStreamDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    let queue = DispatchQueue(label: "studio.media", qos: .userInitiated)
    let cameraQueue = DispatchQueue(label: "studio.camera")
    let effectsQueue = DispatchQueue(label: "studio.camera.effects", qos: .userInitiated)
    let background = BackgroundProcessor()
    var onPreview: ((CGImage) -> Void)?
    var onBackgroundWarning: ((String?) -> Void)?
    let cameraSession = AVCaptureSession()
    let context = CIContext(options: [.cacheIntermediates: false])
    var stream: SCStream?
    var writer: AVAssetWriter?
    var videoInput: AVAssetWriterInput?
    var audioInput: AVAssetWriterInput?
    var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    var cameraFrame: CIImage?
    var screenFrame: CIImage?
    var frameTimer: DispatchSourceTimer?
    var layout = Layout()
    var size = CGSize(width: 1920, height: 1080)
    var epoch: CMTime?
    var lastVideo: CMTime?
    var videoCount = 0
    var audioCount = 0
    var accepting = false
    var onFailure: ((String) -> Void)?
    var reportedFailure = false
    var tools = CaptureToolsState()
    let toolsRenderer = CaptureToolsRenderer()
    func updateTools(_ state: CaptureToolsState) { queue.async { self.tools = state } }

    func updateLayout(_ value: Layout) { queue.async { self.layout = value } }

    func configureCamera(id: String) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            cameraQueue.async {
                self.cameraSession.stopRunning()
                self.cameraSession.beginConfiguration()
                defer { self.cameraSession.commitConfiguration() }
                self.cameraSession.inputs.forEach { self.cameraSession.removeInput($0) }
                self.cameraSession.outputs.forEach { self.cameraSession.removeOutput($0) }
                guard let device = availableCameras().first(where: { $0.uniqueID == id }) else {
                    c.resume(throwing: StudioError(message: "Camera not found. Please select it again.")); return
                }
                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    guard self.cameraSession.canAddInput(input) else { throw StudioError(message: "Cannot connect to the camera.") }
                    self.cameraSession.addInput(input)
                    self.cameraSession.sessionPreset = .high
                    let output = AVCaptureVideoDataOutput()
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    output.alwaysDiscardsLateVideoFrames = true
                    output.setSampleBufferDelegate(self, queue: self.effectsQueue)
                    guard self.cameraSession.canAddOutput(output) else { throw StudioError(message: "Cannot read camera frames.") }
                    self.cameraSession.addOutput(output)
                    c.resume()
                } catch { c.resume(throwing: error) }
            }
        }
        await withCheckedContinuation { c in cameraQueue.async { self.cameraSession.startRunning(); c.resume() } }
    }

    func stopCamera() { cameraQueue.async { self.cameraSession.stopRunning(); self.queue.async { self.cameraFrame = nil } } }
    func updateBackground(_ settings: BackgroundSettings) {
        effectsQueue.async { self.background.update(settings) }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixel = CMSampleBufferGetImageBuffer(sampleBuffer), let (image, warning) = background.process(pixel) else { return }
        // Materialize the result once so the encoder doesn't repeat Vision/filter work.
        guard let cg = background.context.createCGImage(image, from: image.extent) else { return }
        queue.async { self.cameraFrame = CIImage(cgImage: cg) }
        let warningChanged = background.lastWarning != warning
        background.lastWarning = warning
        DispatchQueue.main.async {
            self.onPreview?(cg)
            if warningChanged { self.onBackgroundWarning?(warning) }
        }
    }

    func prepare(url: URL, width: Int, height: Int, microphone: Bool) throws {
        size = CGSize(width: width, height: height)
        let w = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let v = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000, AVVideoExpectedSourceFrameRateKey: 30]
        ])
        v.expectsMediaDataInRealTime = true
        let a = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: v, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        guard w.canAdd(v) else { throw StudioError(message: "Cannot create the video encoder.") }
        w.add(v)
        var mic: AVAssetWriterInput?
        if microphone {
            let m = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128000])
            m.expectsMediaDataInRealTime = true
            guard w.canAdd(m) else { throw StudioError(message: "Cannot create the audio encoder.") }
            w.add(m); mic = m
        }
        guard w.startWriting() else { throw w.error ?? StudioError(message: "Cannot create the MP4 file.") }
        writer = w; videoInput = v; audioInput = mic; adaptor = a
        epoch = nil; lastVideo = nil; screenFrame = nil; videoCount = 0; audioCount = 0; reportedFailure = false; accepting = true
    }

    func start(filter: SCContentFilter, width: Int, height: Int, microphoneID: String?, url: URL, sourceRect: CGRect? = nil) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            queue.async { do { try self.prepare(url: url, width: width, height: height, microphone: microphoneID != nil); c.resume() } catch { c.resume(throwing: error) } }
        }
        let config = SCStreamConfiguration()
        config.width = width; config.height = height
        if let sourceRect { config.sourceRect = sourceRect }
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 5; config.showsCursor = true
        config.ignoreShadowsSingleWindow = true
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.capturesAudio = false
        config.captureMicrophone = microphoneID != nil
        config.microphoneCaptureDeviceID = microphoneID
        let s = SCStream(filter: filter, configuration: config, delegate: self)
        stream = s
        do {
            try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            if microphoneID != nil { try s.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue) }
            try await s.startCapture()
            queue.async {
                let timer = DispatchSource.makeTimerSource(queue: self.queue)
                timer.schedule(deadline: .now(), repeating: .nanoseconds(33_333_333), leeway: .milliseconds(2))
                timer.setEventHandler { [weak self = self] in
                    guard let self, self.accepting, let image = self.screenFrame else { return }
                    // ScreenCaptureKit and the microphone use the host clock. Tick even
                    // when the desktop is unchanged, so the camera keeps moving.
                    self.appendScreen(image, time: CMClockGetTime(CMClockGetHostTimeClock()))
                }
                self.frameTimer = timer; timer.resume()
            }
        } catch {
            queue.sync { accepting = false; writer?.cancelWriting(); writer = nil }
            stream = nil
            throw error
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { fail(error.localizedDescription) }
    func fail(_ message: String) {
        queue.async {
            guard !self.reportedFailure else { return }; self.reportedFailure = true
            DispatchQueue.main.async { self.onFailure?(message) }
        }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard accepting, CMSampleBufferIsValid(sampleBuffer) else { return }
        switch type {
        case .screen:
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
                  let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            screenFrame = CIImage(cvPixelBuffer: pixel)
        case .microphone:
            appendAudio(sampleBuffer)
        default: break
        }
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard accepting, let epoch, time >= epoch, let a = audioInput, a.isReadyForMoreMediaData else { return }
        if a.append(sampleBuffer) { audioCount += 1 }
        else { fail(writer?.error?.localizedDescription ?? "Could not write microphone audio.") }
    }

    func composited(_ screen: CIImage) -> CIImage {
        let bounds = CGRect(origin: .zero, size: size)
        var result = screen.transformed(by: CGAffineTransform(translationX: -screen.extent.minX, y: -screen.extent.minY))
        result = result.transformed(by: CGAffineTransform(scaleX: size.width / result.extent.width, y: size.height / result.extent.height))
        result = toolsRenderer.render(result, bounds: bounds, state: tools)
        guard var cam = cameraFrame else { return result.cropped(to: bounds) }
        let rect = layout.cameraRect(in: size)
        let side = rect.width, cw = rect.width, ch = rect.height
        let x = rect.minX, y = rect.minY
        cam = cam.transformed(by: CGAffineTransform(translationX: -cam.extent.minX, y: -cam.extent.minY))
        if layout.mirror { cam = cam.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: cam.extent.width, ty: 0)) }
        let scale = max(cw / cam.extent.width, ch / cam.extent.height)
        cam = cam.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        cam = cam.transformed(by: CGAffineTransform(translationX: x - (cam.extent.width - cw)/2, y: y - (cam.extent.height - ch)/2)).cropped(to: rect)
        let radius = layout.round ? side / 2 : 24.0
        let mask = CIFilter(name: "CIRoundedRectangleGenerator", parameters: ["inputExtent": CIVector(cgRect: rect), "inputRadius": radius, "inputColor": CIColor.white])!.outputImage!.cropped(to: bounds)
        result = cam.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: result, kCIInputMaskImageKey: mask])
        return result.cropped(to: bounds)
    }

    func appendScreen(_ image: CIImage, time: CMTime) {
        guard accepting, let writer, writer.status == .writing, let v = videoInput, v.isReadyForMoreMediaData, let a = adaptor else { return }
        if let lastVideo, time <= lastVideo { return }
        if epoch == nil { writer.startSession(atSourceTime: time); epoch = time }
        guard let pool = a.pixelBufferPool else { fail("Could not create a video buffer."); return }
        var pixel: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixel) == kCVReturnSuccess, let pixel else { fail("Not enough video buffer memory."); return }
        context.render(composited(image), to: pixel, bounds: CGRect(origin: .zero, size: size), colorSpace: CGColorSpaceCreateDeviceRGB())
        if a.append(pixel, withPresentationTime: time) { lastVideo = time; videoCount += 1 }
        else { fail(writer.error?.localizedDescription ?? "Could not write a video frame.") }
    }

    func stop() async throws -> (Int, Int) {
        if let s = stream { try? await s.stopCapture() }; stream = nil
        return try await withCheckedThrowingContinuation { c in
            queue.async {
                self.frameTimer?.cancel(); self.frameTimer = nil
                self.accepting = false
                guard let w = self.writer else { c.resume(throwing: StudioError(message: "No recording is in progress.")); return }
                guard self.epoch != nil else { w.cancelWriting(); self.writer = nil; c.resume(throwing: StudioError(message: "No screen frames received. Check screen recording permission.")); return }
                self.videoInput?.markAsFinished(); self.audioInput?.markAsFinished()
                let counts = (self.videoCount, self.audioCount)
                w.finishWriting {
                    self.queue.async {
                        self.writer = nil; self.videoInput = nil; self.audioInput = nil; self.adaptor = nil
                        if w.status == .completed { c.resume(returning: counts) }
                        else { c.resume(throwing: w.error ?? StudioError(message: "MP4 export failed.")) }
                    }
                }
            }
        }
    }
}

final class CameraView: NSView {
    let imageLayer = CALayer()
    var mirrored = true { didSet { imageLayer.setAffineTransform(CGAffineTransform(scaleX: mirrored ? -1 : 1, y: 1)) } }
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true; layer?.backgroundColor = NSColor.black.cgColor
        imageLayer.contentsGravity = .resizeAspectFill; imageLayer.masksToBounds = true; layer?.addSublayer(imageLayer)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var mouseDownCanMoveWindow: Bool { true }
    override func layout() { super.layout(); CATransaction.begin(); CATransaction.setDisableActions(true); imageLayer.frame = bounds; CATransaction.commit() }
    func show(_ image: CGImage) { CATransaction.begin(); CATransaction.setDisableActions(true); imageLayer.contents = image; CATransaction.commit() }
}

final class DragPanel: NSPanel {
    var moved: (() -> Void)?
    override func mouseUp(with event: NSEvent) { super.mouseUp(with: event); moved?() }
}

final class Prompter: NSObject, NSTextViewDelegate {
    var onScriptEdited: ((String) -> Void)?
    var scriptTitle: String = ""
    var lastEditTime: Double = 0
    let panel: NSPanel
    let text = NSTextView()
    let scroll = NSScrollView()
    let speed = NSSlider(value: 32, minValue: 5, maxValue: 120, target: nil, action: nil)
    let fontSize = NSSlider(value: 32, minValue: 20, maxValue: 64, target: nil, action: nil)
    var resetButton: NSButton!
    var speedLabel: NSTextField!
    var fontLabel: NSTextField!
    let play = NSButton(title: "▶ Start scrolling", target: nil, action: nil)
    var timer: Timer?
    var running = false
    var lastTick = ProcessInfo.processInfo.systemUptime
    override init() {
        panel = NSPanel(contentRect: NSRect(x: 160, y: 520, width: 650, height: 330), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        super.init()
        panel.title = "Teleprompter · Excluded from recording"; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let root = NSStackView(); root.orientation = .vertical; root.spacing = 12; root.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 16, right: 16)
        panel.contentView = root
        let tools = NSStackView(); tools.spacing = 8
        play.target = self; play.action = #selector(toggle)
        resetButton = NSButton(title: L("Back to top"), target: self, action: #selector(resetPosition))
        speedLabel = NSTextField(labelWithString: L("Speed")); fontLabel = NSTextField(labelWithString: L("Text size"))
        fontSize.target = self; fontSize.action = #selector(changeFont)
        speed.widthAnchor.constraint(equalToConstant: 105).isActive = true
        fontSize.widthAnchor.constraint(equalToConstant: 90).isActive = true
        [play, resetButton!, speedLabel!, speed, fontLabel!, fontSize].forEach { tools.addArrangedSubview($0) }
        root.addArrangedSubview(tools)
        text.string = L("Paste your script here.\n\nClick “Start scrolling” to read while you present.\n\nMove the teleprompter near your camera. All app windows are excluded from screen capture, so your script stays out of the recording.\n\nPause scrolling to edit, or return to the top at any time.")
        if let saved = UserDefaults.standard.string(forKey: "prompter.script") { text.string = saved }
        text.delegate = self
        let savedSize = UserDefaults.standard.double(forKey: "prompter.fontSize")
        if savedSize >= 20 { fontSize.doubleValue = savedSize }
        let readingBackground = NSColor(white: 0.08, alpha: 1)
        text.font = .systemFont(ofSize: fontSize.doubleValue, weight: .medium); text.textColor = .white; text.backgroundColor = readingBackground
        text.drawsBackground = true
        text.textContainerInset = NSSize(width: 20, height: 24)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        scroll.documentView = text; scroll.hasVerticalScroller = true; scroll.drawsBackground = true
        // Match all scroll surfaces so newly exposed strips stay dark.
        // tick() also invalidates the visible text during fractional scrolling.
        scroll.backgroundColor = readingBackground
        scroll.contentView.backgroundColor = readingBackground
        scroll.contentView.drawsBackground = true
        scroll.wantsLayer = true
        root.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -32).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/30, repeats: true) { [weak self] _ in self?.tick() }
    }
    @objc func toggle() { running.toggle(); lastTick = ProcessInfo.processInfo.systemUptime; play.title = L(running ? "Ⅱ Pause scrolling" : "▶ Start scrolling") }
    @objc func resetPosition() { scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView) }
    @objc func changeFont() { text.font = .systemFont(ofSize: fontSize.doubleValue, weight: .medium); UserDefaults.standard.set(fontSize.doubleValue, forKey: "prompter.fontSize") }
    func textDidChange(_ notification: Notification) {
        lastEditTime = ProcessInfo.processInfo.systemUptime
        UserDefaults.standard.set(text.string, forKey: "prompter.script")
        onScriptEdited?(text.string)
    }
    func tick() {
        let now = ProcessInfo.processInfo.systemUptime; let dt = min(0.1, now-lastTick); lastTick = now
        guard running, panel.isVisible else { return }
        let maxY = max(0, text.bounds.height - scroll.contentView.bounds.height)
        let y = min(maxY, scroll.contentView.bounds.minY + speed.doubleValue * dt)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y)); scroll.reflectScrolledClipView(scroll.contentView)
        text.setNeedsDisplay(text.visibleRect)
        scroll.contentView.needsDisplay = true
        if y >= maxY { running = false; play.title = L("▶ Start scrolling") }
    }
    func applyLanguage() {
        panel.title = L("Teleprompter · Excluded from recording") + (scriptTitle.isEmpty ? "" : " — " + scriptTitle)
        play.title = L(running ? "Ⅱ Pause scrolling" : "▶ Start scrolling")
        resetButton.title = L("Back to top"); speedLabel.stringValue = L("Speed"); fontLabel.stringValue = L("Text size")
        // Translate only the untouched starter text. User-authored scripts stay exactly as written.
        if UserDefaults.standard.string(forKey: "prompter.script") == nil {
            let origin = "Paste your script here.\n\nClick “Start scrolling” to read while you present.\n\nMove the teleprompter near your camera. All app windows are excluded from screen capture, so your script stays out of the recording.\n\nPause scrolling to edit, or return to the top at any time."
            if text.string == origin || text.string == localizedChineseStrings[origin] { text.string = L(origin) }
        }
    }
    func show() { panel.makeKeyAndOrderFront(nil) }
}

final class Studio: NSObject, @unchecked Sendable, NSApplicationDelegate, NSWindowDelegate {
    var localizedLabels: [(NSTextField, String)] = []
    var promptButton: NSButton!
    var notesButton: NSButton!
    var notesCoordinator: NotesCoordinator?
    var settingsButton: NSButton!
    var backgroundButton: NSButton!
    var backgroundPanel: BackgroundPanel!
    var backgroundWarning: String?
    var settingsPanel: NSPanel?
    var languagePicker: NSPopUpButton?
    var settingsLabel: NSTextField?
    var settingsNote: NSTextField?
    var statusKey = "Choose a source, then open the camera preview. Everything stays on your Mac."
    var statusArguments: [CVarArg] = []
    let recorder = Recorder()
    var window: NSWindow!
    let source = NSButton(); let camera = NSPopUpButton(); let microphone = NSPopUpButton()
    let shape = NSPopUpButton(); let position = NSPopUpButton()
    let sizeSlider = NSSlider(value: 0.20, minValue: 0.08, maxValue: 0.63, target: nil, action: nil)
    var sizeCaption: NSTextField?
    let mirror = NSButton(checkboxWithTitle: "Mirror camera", target: nil, action: nil)
    let start = SetupRecordButton(title: "● Start recording", target: nil, action: nil)
    let previewButton = NSButton(title: "Open camera preview", target: nil, action: nil)
    let refreshButton = NSButton(title: "Choose / refresh sources", target: nil, action: nil)
    let regionButton = NSButton(title: "Choose a region…", target: nil, action: nil)
    let status = NSTextField(wrappingLabelWithString: "Choose a source, then open the camera preview. Everything stays on your Mac.")
    let clockLabel = NSTextField(labelWithString: "00:00")
    let cameraView = CameraView(frame: .zero)
    var bubble: DragPanel!
    var prompter: Prompter!
    var selectedCapture: CaptureTarget?
    var sourcePicker: CaptureSourcePicker!
    var controlPanel: CaptureControlPanel!
    var controlButton: NSButton!
    var cameras: [AVCaptureDevice] = []; var microphones: [AVCaptureDevice] = []
    var recording = false; var busy = false; var cameraReady = false
    var started = Date(); var outputURL: URL?
    var selectedLayout = Layout()
    var ticker: Timer?
    var terminationPending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        createMenu(); buildUI()
        recorder.onFailure = { [weak self] message in
            guard let self else { return }; self.showStatus("Recording error: %@", message)
            if self.recording { self.finishRecording(failure: message) }
        }
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func createMenu() {
        let menu = NSMenu(); let app = NSMenuItem(); menu.addItem(app); let sub = NSMenu(); app.submenu = sub
        sub.addItem(withTitle: L("About TD Capture"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let settings = sub.addItem(withTitle: L("Settings…"), action: #selector(openSettings), keyEquivalent: ","); settings.target = self
        sub.addItem(NSMenuItem.separator()); sub.addItem(withTitle: L("Quit TD Capture"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenuItem(); menu.addItem(edit); edit.title = L("Edit"); edit.submenu = NSMenu(title: L("Edit"))
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.submenu?.addItem(withTitle: L(title), action: Selector(action), keyEquivalent: key)
        }
        NSApp.mainMenu = menu
    }
    func label(_ s: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSTextField {
        let l = NSTextField(labelWithString: L(s)); localizedLabels.append((l, s)); l.font = .systemFont(ofSize: size, weight: weight)
        if size <= 16 {
            l.heightAnchor.constraint(greaterThanOrEqualToConstant: ceil(size * 1.65)).isActive = true
            l.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        return l
    }
    func setupField(_ title: String, _ control: NSView, width: CGFloat) -> NSStackView {
        let caption = label(title, size: 12, weight: .medium)
        caption.textColor = SetupTheme.muted
        control.widthAnchor.constraint(equalToConstant: width).isActive = true
        if let popup = control as? NSPopUpButton {
            popup.controlSize = .large; popup.font = .systemFont(ofSize: 13)
            popup.heightAnchor.constraint(equalToConstant: 30).isActive = true
        }
        return SetupTheme.stack([caption, control], vertical: true, spacing: 5)
    }
    func setupHeading(_ title: String, symbol: String, detail: String) -> NSStackView {
        let heading = label(title, size: 16, weight: .semibold); heading.textColor = SetupTheme.ink
        let subtitle = label(detail, size: 11); subtitle.textColor = SetupTheme.muted
        // Reserve actual line heights for Chinese fallback fonts; intrinsic heights
        // alone can clip glyphs or collapse the space between these two lines.
        heading.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
        subtitle.heightAnchor.constraint(greaterThanOrEqualToConstant: 18).isActive = true
        heading.setContentCompressionResistancePriority(.required, for: .vertical)
        subtitle.setContentCompressionResistancePriority(.required, for: .vertical)
        return SetupTheme.stack([SetupTheme.symbol(symbol), SetupTheme.stack([heading, subtitle], vertical: true, spacing: 6)], spacing: 9)
    }
    func buildUI() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 800), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "TD Capture · Recorder & Teleprompter"; window.isReleasedWhenClosed = false; window.delegate = self
        window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .aqua)
        let canvas = WatercolorSetupView(); window.contentView = canvas
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false; canvas.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: 28),
            root.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -28),
            root.topAnchor.constraint(equalTo: canvas.topAnchor, constant: 46),
            root.bottomAnchor.constraint(lessThanOrEqualTo: canvas.bottomAnchor, constant: -22)
        ])
        let brand = label("TD Capture", size: 32, weight: .medium)
        brand.font = NSFont(name: "Georgia", size: 32) ?? .systemFont(ofSize: 32, weight: .medium)
        brand.textColor = SetupTheme.ink
        let subtitle = label("Your screen, camera and script, together.", size: 13); subtitle.textColor = SetupTheme.muted
        let identity = SetupTheme.stack([brand, subtitle], vertical: true, spacing: 6)
        settingsButton = NSButton(title: L("Settings"), target: self, action: #selector(openSettings))
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil); settingsButton.imagePosition = .imageLeading
        SetupTheme.button(settingsButton)
        let header = SetupTheme.stack([identity, NSView(), settingsButton]); root.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let captureCard = SetupCard()
        captureCard.content.addArrangedSubview(setupHeading("Picture & sound", symbol: "rectangle.on.rectangle", detail: "Choose what your audience sees and hears."))
        source.title = L("Choose a window…"); source.bezelStyle = .rounded; source.controlSize = .large; source.cell?.lineBreakMode = .byTruncatingMiddle
        source.target = self; source.action = #selector(chooseWindow)
        sourcePicker = CaptureSourcePicker()
        sourcePicker.onSelect = { [weak self] target in
            guard let self, !self.recording, !self.busy else { return }
            self.selectedCapture = target; self.source.title = target.title
            self.controlPanel?.setTarget(target); self.layoutChanged()
            self.showStatus("Source selected. Open the camera preview to start recording.")
        }
        sourcePicker.onMessage = { [weak self] message in self?.showStatus(message) }
        captureCard.content.addArrangedSubview(setupField("Source", source, width: 370))
        refreshButton.target = self; refreshButton.action = #selector(refreshSources)
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil); refreshButton.imagePosition = .imageLeading
        SetupTheme.button(refreshButton)
        regionButton.target = self; regionButton.action = #selector(chooseRegion)
        regionButton.image = NSImage(systemSymbolName: "crop", accessibilityDescription: nil); regionButton.imagePosition = .imageLeading
        SetupTheme.button(regionButton)
        captureCard.content.addArrangedSubview(SetupTheme.stack([refreshButton, regionButton], spacing: 8))
        cameras = availableCameras(); microphones = availableMicrophones()
        camera.addItems(withTitles: cameras.map(\.localizedName)); microphone.addItems(withTitles: ["No microphone"] + microphones.map(\.localizedName))
        if let defaultMic = AVCaptureDevice.default(for: .audio), let i = microphones.firstIndex(where: { $0.uniqueID == defaultMic.uniqueID }) { microphone.selectItem(at: i+1) }
        else if !microphones.isEmpty { microphone.selectItem(at: 1) }
        camera.target = self; camera.action = #selector(cameraChanged)
        captureCard.content.addArrangedSubview(setupField("Camera", camera, width: 370))
        captureCard.content.addArrangedSubview(setupField("Microphone", microphone, width: 370))
        let audioNote = label("Microphone audio only · System audio is not recorded", size: 10)
        audioNote.textColor = SetupTheme.muted; captureCard.content.addArrangedSubview(audioNote)

        let layoutCard = SetupCard()
        layoutCard.content.addArrangedSubview(setupHeading("Make it yours", symbol: "person.crop.rectangle", detail: "A little presence. Your own style."))
        shape.addItems(withTitles: ["Circle", "Rounded rectangle"]); position.addItems(withTitles: ["Top left", "Top right", "Bottom left", "Bottom right"]); position.selectItem(at: 3)
        for control in [shape, position] { control.target = self; control.action = #selector(layoutChanged) }
        layoutCard.content.addArrangedSubview(SetupTheme.stack([setupField("Shape", shape, width: 174), setupField("Position", position, width: 174)], spacing: 16))
        sizeSlider.cell = SetupSliderCell()
        sizeSlider.minValue = 0.08; sizeSlider.maxValue = 0.63
        let savedOverlaySize = UserDefaults.standard.double(forKey: "camera.overlayShortEdgeFraction")
        sizeSlider.doubleValue = (0.08...0.63).contains(savedOverlaySize) ? savedOverlaySize : 0.20
        sizeSlider.target = self; sizeSlider.action = #selector(layoutChanged)
        sizeSlider.controlSize = .small
        let sizeField = setupField("Size", sizeSlider, width: 364)
        sizeCaption = sizeField.arrangedSubviews.first as? NSTextField
        layoutCard.content.addArrangedSubview(sizeField)
        mirror.state = .on; mirror.target = self; mirror.action = #selector(layoutChanged)
        mirror.font = .systemFont(ofSize: 12); layoutCard.content.addArrangedSubview(mirror)
        backgroundButton = NSButton(title: L("Background…"), target: self, action: #selector(openBackground))
        backgroundButton.image = NSImage(systemSymbolName: "camera.filters", accessibilityDescription: nil); backgroundButton.imagePosition = .imageLeading
        previewButton.target = self; previewButton.action = #selector(openCamera)
        SetupTheme.button(previewButton); SetupTheme.button(backgroundButton)
        layoutCard.content.addArrangedSubview(SetupTheme.stack([previewButton, backgroundButton], spacing: 8))
        let hint = label("Drag the camera preview to find your spot.", size: 11); hint.textColor = SetupTheme.muted
        layoutCard.content.addArrangedSubview(hint)
        let cards = SetupTheme.stack([captureCard, layoutCard], spacing: 16)
        root.addArrangedSubview(cards)
        NSLayoutConstraint.activate([
            cards.widthAnchor.constraint(equalTo: root.widthAnchor),
            captureCard.widthAnchor.constraint(equalToConstant: 410),
            layoutCard.widthAnchor.constraint(equalToConstant: 418),
            captureCard.heightAnchor.constraint(equalToConstant: 380),
            layoutCard.heightAnchor.constraint(equalTo: captureCard.heightAnchor)
        ])

        let scriptCard = SetupCard(tint: NSColor(srgbRed: 0.94, green: 0.96, blue: 0.92, alpha: 1), padding: 18)
        promptButton = NSButton(title: L("Open teleprompter ↗"), target: self, action: #selector(openPrompter))
        notesButton = NSButton(title: L("Script library…"), target: self, action: #selector(openNotes))
        SetupTheme.button(promptButton); SetupTheme.button(notesButton)
        let scriptRow = SetupTheme.stack([setupHeading("Find your words", symbol: "text.alignleft", detail: "Your notes, just outside the frame."), NSView(), notesButton, promptButton])
        scriptCard.content.addArrangedSubview(scriptRow)
        scriptRow.widthAnchor.constraint(equalTo: scriptCard.content.widthAnchor).isActive = true
        controlButton = NSButton(title: L("Recording controls…"), target: self, action: #selector(openControls))
        SetupTheme.button(controlButton)
        header.insertArrangedSubview(controlButton, at: 2)
        controlPanel = CaptureControlPanel()
        controlPanel.onState = { [weak self] state in self?.recorder.updateTools(state) }
        root.addArrangedSubview(scriptCard)
        scriptCard.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        scriptCard.heightAnchor.constraint(equalToConstant: 92).isActive = true

        let footer = SetupCard(padding: 18)
        start.target = self; start.action = #selector(toggleRecording); SetupTheme.button(start, prominent: true)
        start.widthAnchor.constraint(greaterThanOrEqualToConstant: 184).isActive = true
        start.heightAnchor.constraint(equalToConstant: 42).isActive = true
        clockLabel.font = .monospacedDigitSystemFont(ofSize: 26, weight: .regular); clockLabel.textColor = SetupTheme.ink
        let format = label("MP4 · Up to 1080p / 30 fps", size: 11); format.textColor = SetupTheme.muted
        let recordingRow = SetupTheme.stack([SetupTheme.stack([clockLabel, format], vertical: true, spacing: 4), NSView(), start])
        footer.content.addArrangedSubview(recordingRow); recordingRow.widthAnchor.constraint(equalTo: footer.content.widthAnchor).isActive = true
        status.preferredMaxLayoutWidth = 804; status.font = .systemFont(ofSize: 11); status.textColor = SetupTheme.muted
        footer.content.spacing = 10; footer.content.addArrangedSubview(status)
        status.widthAnchor.constraint(equalTo: footer.content.widthAnchor).isActive = true
        root.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        footer.heightAnchor.constraint(equalToConstant: 128).isActive = true
        bubble = DragPanel(contentRect: NSRect(x: 100, y: 100, width: 220, height: 220), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        bubble.level = .floating; bubble.isMovableByWindowBackground = true; bubble.isOpaque = false; bubble.backgroundColor = .clear; bubble.hasShadow = true
        bubble.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; bubble.contentView = cameraView
        recorder.onPreview = { [weak self] image in self?.cameraView.show(image) }
        recorder.onBackgroundWarning = { [weak self] warning in
            guard let self else { return }
            self.backgroundWarning = warning; self.backgroundPanel.warning.stringValue = warning.map { L($0) } ?? ""
        }
        backgroundPanel = BackgroundPanel(settings: .load())
        backgroundPanel.onChange = { [weak self] settings in
            self?.recorder.updateBackground(settings)
            self?.backgroundWarning = nil; self?.backgroundPanel.warning.stringValue = ""
        }
        recorder.updateBackground(backgroundPanel.settings)
        NotificationCenter.default.addObserver(self, selector: #selector(bubbleMoved), name: NSWindow.didMoveNotification, object: bubble)
        prompter = Prompter()
        do {
            notesCoordinator = try NotesCoordinator(prompter: prompter, canOpen: { [weak self] in
                guard let self else { return false }; return !self.recording && !self.busy
            })
            notesCoordinator?.onMessage = { [weak self] text in self?.showStatus(text) }
        } catch { showStatus(error.localizedDescription) }
        applyLanguage(); layoutChanged()
    }
    func showStatus(_ key: String, _ arguments: CVarArg...) {
        statusKey = key; statusArguments = arguments; renderStatus()
    }
    func renderStatus() {
        let template = L(statusKey)
        var arguments = statusArguments
        if statusKey == "Recording · %d × %d · %@ · Script excluded", arguments.count == 3, let key = arguments[2] as? String { arguments[2] = L(key) }
        status.stringValue = arguments.isEmpty ? template : String(format: template, arguments: arguments)
    }
    func applyLanguage() {
        window.title = L("TD Capture · Recorder & Teleprompter")
        for (field, key) in localizedLabels { field.stringValue = L(key) }
        settingsButton.title = L("Settings"); promptButton.title = L("Open teleprompter ↗"); notesButton.title = L("Script library…")
        updatePortraitSizeLabel()
        mirror.title = L("Mirror camera"); refreshButton.title = L("Choose / refresh sources")
        start.title = L(recording ? "■ Stop & export" : "● Start recording")
        previewButton.title = L(cameraReady ? "Show camera preview" : "Open camera preview")
        let shapeIndex = shape.indexOfSelectedItem, positionIndex = position.indexOfSelectedItem
        shape.removeAllItems(); shape.addItems(withTitles: [L("Circle"), L("Rounded rectangle")]); shape.selectItem(at: shapeIndex)
        position.removeAllItems(); position.addItems(withTitles: ["Top left", "Top right", "Bottom left", "Bottom right"].map { L($0) }); position.selectItem(at: positionIndex)
        microphone.item(at: 0)?.title = L("No microphone")
        if selectedCapture == nil { source.title = L("Choose a window…") }
        refreshButton.title = L("Record an entire screen…")
        regionButton.title = L("Choose a region…")
        controlButton?.title = L("Recording controls…"); controlPanel?.applyLanguage()
        settingsPanel?.title = L("Settings"); settingsLabel?.stringValue = L("Interface language")
        settingsNote?.stringValue = L("Changes apply immediately and are saved automatically.")
        languagePicker?.selectItem(at: UserDefaults.standard.string(forKey: "ui.language") == "en" ? 1 : 0)
        backgroundButton.title = L("Background…"); backgroundPanel?.applyLanguage()
        backgroundPanel?.warning.stringValue = backgroundWarning.map { L($0) } ?? ""
        prompter?.applyLanguage(); notesCoordinator?.applyLanguage(); renderStatus(); createMenu()
    }
    @objc func openSettings() {
        if settingsPanel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 155), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false; panel.level = .floating
            let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 20
            root.edgeInsets = NSEdgeInsets(top: 26, left: 26, bottom: 26, right: 26)
            settingsLabel = NSTextField(labelWithString: L("Interface language"))
            let picker = NSPopUpButton(); picker.addItems(withTitles: [L("Simplified Chinese"), "English"])
            picker.target = self; picker.action = #selector(languageChanged); languagePicker = picker
            let row = NSStackView(views: [settingsLabel!, picker]); row.spacing = 24; root.addArrangedSubview(row)
            settingsNote = NSTextField(labelWithString: L("Changes apply immediately and are saved automatically.")); settingsNote?.font = .systemFont(ofSize: 12)
            root.addArrangedSubview(settingsNote!); panel.contentView = root; settingsPanel = panel
        }
        settingsPanel?.title = L("Settings")
        languagePicker?.selectItem(at: UserDefaults.standard.string(forKey: "ui.language") == "en" ? 1 : 0)
        settingsPanel?.center(); settingsPanel?.makeKeyAndOrderFront(nil)
    }
    @objc func languageChanged() {
        UserDefaults.standard.set(languagePicker?.indexOfSelectedItem == 1 ? "en" : "zh-Hans", forKey: "ui.language")
        applyLanguage()
    }
    @objc func chooseWindow() { guard !busy, !recording else { return }; sourcePicker.chooseWindow() }
    @objc func refreshSources() { guard !busy, !recording else { return }; sourcePicker.chooseScreen() }
    @objc func chooseRegion() { guard !busy, !recording else { return }; sourcePicker.chooseRegion() }
    @objc func openControls() { controlPanel.show() }
    @objc func cameraChanged() {
        if cameraReady { recorder.stopCamera(); cameraReady = false; bubble.orderOut(nil); previewButton.title = L("Open camera preview") }
    }
    @objc func openCamera() {
        guard !busy, !recording else { return }
        guard camera.indexOfSelectedItem >= 0, cameras.indices.contains(camera.indexOfSelectedItem) else { showStatus("No camera detected. Connect one and reopen the app."); return }
        busy = true; start.isEnabled = false; previewButton.isEnabled = false
        Task { @MainActor in
            defer { busy = false; start.isEnabled = true; previewButton.isEnabled = true }
            guard await AVCaptureDevice.requestAccess(for: .video) else { showStatus("Allow TD Capture in System Settings → Privacy & Security → Camera."); return }
            do {
                try await recorder.configureCamera(id: cameras[camera.indexOfSelectedItem].uniqueID)
                cameraReady = true; previewButton.title = L("Show camera preview"); layoutChanged(); bubble.orderFrontRegardless()
                showStatus("Camera connected. Your camera appears in the MP4; the teleprompter stays out.")
            } catch { cameraReady = false; showStatus("Camera connection failed: %@", error.localizedDescription) }
        }
    }
    @objc func openBackground() { backgroundPanel.show() }
    @objc func openNotes() {
        guard let notesCoordinator else { showStatus("The script library is unavailable. Check local storage permissions and reopen the app."); return }
        notesCoordinator.library.show()
    }
    @objc func openPrompter() { prompter.show() }
    func updatePortraitSizeLabel() {
        sizeCaption?.stringValue = L("Size · %.0f%% of the short edge", sizeSlider.doubleValue * 100)
        sizeSlider.setAccessibilityLabel(L("Camera size as a percentage of the recording's short edge"))
        sizeSlider.setAccessibilityValueDescription(String(format: "%.0f%%", sizeSlider.doubleValue * 100))
    }
    @objc func layoutChanged() {
        // The compositor's legacy fraction includes a 1.5 scale; the UI exposes
        // the final width/diameter directly as a fraction of the short edge.
        selectedLayout.fraction = sizeSlider.doubleValue / 1.5;
        UserDefaults.standard.set(sizeSlider.doubleValue, forKey: "camera.overlayShortEdgeFraction")
        updatePortraitSizeLabel(); selectedLayout.corner = position.indexOfSelectedItem
        selectedLayout.round = shape.indexOfSelectedItem == 0; selectedLayout.mirror = mirror.state == .on
        selectedLayout.x = nil; selectedLayout.y = nil; recorder.updateLayout(selectedLayout)
        guard bubble != nil else { return }
        let frame = portraitPlacementFrame()
        let portrait = selectedLayout.cameraRect(in: frame.size)
        let side = portrait.width
        bubble.setFrame(portrait.offsetBy(dx: frame.minX, dy: frame.minY), display: true)
        cameraView.layer?.cornerRadius = selectedLayout.round ? side/2 : 16; cameraView.layer?.masksToBounds = true
        cameraView.mirrored = selectedLayout.mirror
    }
    func targetScreen() -> NSScreen {
        if let id = selectedCapture?.displayID,
           let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }) { return screen }
        return bubble?.screen ?? NSScreen.main ?? NSScreen.screens[0]
    }
    func portraitPlacementFrame() -> CGRect {
        if let target = selectedCapture, target.sourceRect != nil {
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            let frame = target.currentFrame
            return CGRect(x: frame.minX, y: top - frame.maxY, width: frame.width, height: frame.height)
        }
        return targetScreen().frame
    }
    @objc func bubbleMoved() {
        guard cameraReady else { return }
        let frame = portraitPlacementFrame(); let b = bubble.frame
        selectedLayout.x = max(0, min(1, (b.minX-frame.minX)/max(1, frame.width-b.width)))
        selectedLayout.y = max(0, min(1, (b.minY-frame.minY)/max(1, frame.height-b.height)))
        recorder.updateLayout(selectedLayout)
    }
    func lockControls(_ locked: Bool) {
        [source, camera, microphone, previewButton, refreshButton, regionButton].forEach { $0.isEnabled = !locked }
    }
    @objc func toggleRecording() {
        if recording { finishRecording(); return }
        guard !busy else { return }
        guard let target = selectedCapture else { showStatus("Choose a window or screen first."); return }
        guard cameraReady else { showStatus("Open the camera preview first and check your picture."); return }
        let save = NSSavePanel(); save.allowedContentTypes = [.mpeg4Movie]; save.nameFieldStringValue = "TD-Capture-\(Self.stamp()).mp4"; save.canCreateDirectories = true
        guard save.runModal() == .OK, let url = save.url else { return }
        // AVAssetWriter requires a new path. Preserve existing recordings rather than deleting them.
        guard !FileManager.default.fileExists(atPath: url.path) else { showStatus("Choose a new filename to keep your existing recording."); return }
        busy = true; start.isEnabled = false; lockControls(true)
        let micID = microphone.indexOfSelectedItem > 0 ? microphones[microphone.indexOfSelectedItem-1].uniqueID : nil
        Task { @MainActor in
            do {
                if micID != nil, !(await AVCaptureDevice.requestAccess(for: .audio)) { throw StudioError(message: "Microphone access denied. Allow it in System Settings, or choose “No microphone”.") }
                let filter = target.filter
                let original = CGSize(width: target.currentFrame.width * CGFloat(filter.pointPixelScale), height: target.currentFrame.height * CGFloat(filter.pointPixelScale))
                let scale = min(1, min(1920 / original.width, 1080 / original.height))
                let width = max(2, Int(original.width * scale)/2*2), height = max(2, Int(original.height * scale)/2*2)
                outputURL = url
                for n in (1...3).reversed() { showStatus("Recording starts in %d…", n); try await Task.sleep(nanoseconds: 1_000_000_000) }
                controlPanel.startSession(target: target)
                try await recorder.start(filter: filter, width: width, height: height, microphoneID: micID, url: url, sourceRect: target.sourceRect)
                recording = true; busy = false; started = Date(); start.isEnabled = true; start.title = L("■ Stop & export")
                showStatus("Recording · %d × %d · %@ · Script excluded", width, height, micID == nil ? "Microphone off" : "Microphone on")
                ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self = self] _ in
                    guard let self else { return }; let s = Int(Date().timeIntervalSince(self.started)); self.clockLabel.stringValue = String(format: "%02d:%02d", s/60, s%60)
                }
            } catch { controlPanel.endSession(); busy = false; start.isEnabled = true; lockControls(false); showStatus("Cannot start recording: %@", error.localizedDescription) }
        }
    }
    func finishRecording(failure: String? = nil) {
        guard recording, !busy else { return }
        controlPanel.endSession()
        busy = true; recording = false; start.isEnabled = false; ticker?.invalidate(); ticker = nil
        showStatus("Finishing your MP4. Please keep the app open…")
        Task { @MainActor in
            do {
                let counts = try await recorder.stop()
                if let failure { showStatus("Recording interrupted; available footage saved: %@", failure) }
                else if microphone.indexOfSelectedItem > 0 && counts.1 == 0 { showStatus("Video saved, but no microphone audio was received. Check microphone permission and your device.") }
                else { showStatus("MP4 saved (%d frames). %@", counts.0, outputURL?.lastPathComponent ?? "") }
                if let outputURL { NSWorkspace.shared.activateFileViewerSelecting([outputURL]) }
            } catch { showStatus("Export failed: %@", error.localizedDescription) }
            busy = false; start.isEnabled = true; start.title = L("● Start recording"); lockControls(false)
            if terminationPending { NSApp.reply(toApplicationShouldTerminate: true) }
        }
    }
    static func stamp() -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmmss"; return f.string(from: Date()) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if recording { terminationPending = true; finishRecording(); return .terminateLater }
        if busy { return .terminateCancel }
        return .terminateNow
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if recording || busy { window.miniaturize(nil); return false }
        NSApp.terminate(nil); return false
    }
    func applicationWillTerminate(_ notification: Notification) { controlPanel.close(); sourcePicker.close(); recorder.stopCamera() }
}

if CommandLine.arguments.contains("--mcp") {
    do {
        var directory: URL?
        if let index = CommandLine.arguments.firstIndex(of: "--notes-directory"), CommandLine.arguments.count > index + 1 {
            directory = URL(fileURLWithPath: CommandLine.arguments[index+1], isDirectory: true)
        }
        NotesMCPServer(store: try NoteStore(directory: directory), allowApplicationLaunch: !CommandLine.arguments.contains("--no-activate")).run()
        exit(0)
    } catch { fputs("TD Capture MCP: \(error.localizedDescription)\n", stderr); exit(1) }
} else if let index = CommandLine.arguments.firstIndex(of: "--background-self-test"), CommandLine.arguments.count > index + 2 {
    do { try runBackgroundTests(photoPath: CommandLine.arguments[index+1], outputPath: CommandLine.arguments[index+2]); exit(0) }
    catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
} else if CommandLine.arguments.contains("--self-test") {
    // Runs the real compositor and H.264 writer with deterministic synthetic video.
    let path = CommandLine.arguments.last!
    let r = Recorder()
    let url = URL(fileURLWithPath: path)
    do {
        try r.prepare(url: url, width: 1280, height: 720, microphone: true)
        r.cameraFrame = CIImage(color: CIColor(red: 1, green: 0.3, blue: 0.15)).cropped(to: CGRect(x: 0, y: 0, width: 640, height: 480))
        if CommandLine.arguments.contains("--tools-effects") {
            r.tools.followPointer = true; r.tools.pointer = CGPoint(x: 0.4, y: 0.4)
            r.tools.zoom = 2; r.tools.center = CGPoint(x: 0.5, y: 0.5)
            r.tools.strokes = [CaptureStroke(points: [CGPoint(x: 0.3, y: 0.5), CGPoint(x: 0.7, y: 0.5)], color: NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1), width: 0.012)]
            r.tools.revision += 1
        }
        for i in 0..<60 {
            while r.videoInput?.isReadyForMoreMediaData == false { Thread.sleep(forTimeInterval: 0.005) }
            let image = CIImage(color: CIColor(red: 0.05, green: CGFloat(i)/120, blue: 0.3)).cropped(to: CGRect(x: 0, y: 0, width: 1280, height: 720))
            r.appendScreen(image, time: CMTime(value: Int64(i), timescale: 30))
            var asbd = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
            var format: CMAudioFormatDescription?
            guard CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format) == noErr else { throw StudioError(message: "Test audio format failed") }
            var block: CMBlockBuffer?
            guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: 3200, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: 3200, flags: 0, blockBufferOut: &block) == noErr, let block else { throw StudioError(message: "Test audio buffer failed") }
            let samples: [Int16] = (0..<1600).map { n in Int16(sin(Double(i * 1600 + n) * 440 * 2 * .pi / 48000) * 4000) }
            _ = samples.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: 3200) }
            var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48000), presentationTimeStamp: CMTime(value: Int64(i*1600), timescale: 48000), decodeTimeStamp: .invalid)
            var sample: CMSampleBuffer?
            guard CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1600, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample) == noErr, let sample else { throw StudioError(message: "Test audio sample failed") }
            while r.audioInput?.isReadyForMoreMediaData == false { Thread.sleep(forTimeInterval: 0.005) }
            r.appendAudio(sample)
        }
        Task {
            do {
                let counts = try await r.stop()
                let asset = AVURLAsset(url: url)
                let duration = try await asset.load(.duration)
                let tracks = try await asset.loadTracks(withMediaType: .video)
                let audio = try await asset.loadTracks(withMediaType: .audio)
                guard audio.count == 1, counts.1 == 60 else { throw StudioError(message: "AAC track validation failed") }
                let generator = AVAssetImageGenerator(asset: asset)
                let cg = try await generator.image(at: CMTime(value: 1, timescale: 1)).image
                let rep = NSBitmapImageRep(cgImage: cg)
                let face = rep.colorAt(x: 1120, y: 560)!
                let background = rep.colorAt(x: 100, y: 100)!
                guard face.redComponent > 0.8, background.redComponent < 0.2 else { throw StudioError(message: "Camera composite pixel validation failed") }
                if CommandLine.arguments.contains("--tools-effects") {
                    let ink = rep.colorAt(x: 640, y: 360)!.usingColorSpace(.deviceRGB)!
                    guard ink.redComponent > 0.7, ink.blueComponent > 0.6, ink.greenComponent < 0.3 else { throw StudioError(message: "Encoded drawing pixel validation failed") }
                    let pointer = rep.colorAt(x: 384, y: 504)!.usingColorSpace(.deviceRGB)!
                    guard pointer.redComponent > 0.15 else { throw StudioError(message: "Encoded pointer pixel validation failed") }
                    print("PASS: zoom, drawing and pointer emphasis verified in encoded MP4; camera overlay stays fixed")
                }
                if let png = rep.representation(using: .png, properties: [:]) { try png.write(to: url.deletingPathExtension().appendingPathExtension("png")) }
                guard counts.0 == 60, tracks.count == 1, CMTimeGetSeconds(duration) > 1.9 else { throw StudioError(message: "Encoding validation failed") }
                print("PASS: camera overlay pixels verified; 60 video frames + 60 audio buffers; H.264/AAC MP4; \(CMTimeGetSeconds(duration)) seconds")
                exit(0)
            } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        }
        dispatchMain()
    } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
} else {
    let app = NSApplication.shared
    let delegate = Studio()
    app.delegate = delegate
    app.run()
}
