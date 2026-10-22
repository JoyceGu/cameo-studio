import AppKit
import AVFoundation
import ScreenCaptureKit
import CoreImage
import CoreMedia
import UniformTypeIdentifiers
import Vision

// The stored preference is read through thread-safe UserDefaults, including media errors.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    let language = UserDefaults.standard.string(forKey: "ui.language") ?? "zh-Hans"
    let template = language == "en" ? (englishStrings[key] ?? key) : key
    return arguments.isEmpty ? template : String(format: template, locale: Locale(identifier: language == "en" ? "en_US" : "zh_CN"), arguments: arguments)
}
let englishStrings: [String: String] = [
    "背景效果…": "Background…",
    "摄像头背景": "Camera background",
    "选择人像背景": "Choose your camera background",
    "原始背景": "Original background",
    "模糊背景": "Blur background",
    "图片背景": "Image background",
    "模糊强度": "Blur strength",
    "明亮书房": "Bright study",
    "柔和自然": "Soft nature",
    "简洁水彩": "Soft watercolor",
    "效果会同步用于预览和成片。在本机处理；头发、手指和快速移动的边缘可能不够精确。": "Effects appear in the preview and recording. Processed on your Mac; hair, fingers and fast movement may have imperfect edges.",
    "暂时无法识别人像，已隐藏原始背景。": "Person detection is unavailable. The original background is hidden.",
    "背景图片无法载入，已隐藏原始背景。": "Background image unavailable. The original background is hidden.",
    "背景处理暂不可用，已隐藏原始画面。请切回原始背景或重试。": "Background processing unavailable. The original picture is hidden. Choose Original background or try again.",
    "设置": "Settings",
    "设置…": "Settings…",
    "界面语言": "Interface language",
    "更改后立即生效，并自动保存。": "Changes apply immediately and are saved automatically.",
    "关于 TD Capture": "About TD Capture",
    "退出 TD Capture": "Quit TD Capture",
    "编辑": "Edit",
    "撤销": "Undo",
    "剪切": "Cut",
    "复制": "Copy",
    "粘贴": "Paste",
    "全选": "Select All",
    "TD Capture · 录屏与提词器": "TD Capture · Recorder & Teleprompter",
    "把演示、出镜和讲稿放在一起。": "Your screen, camera and script, together.",
    "01  选择画面与声音": "01  Picture & sound",
    "02  人像布局": "02  Camera layout",
    "请点击下方按钮，授权并加载屏幕 / 窗口": "Click below to allow access and load screens / windows",
    "录制来源": "Source",
    "选择 / 刷新录制来源": "Choose / refresh sources",
    "摄像头": "Camera",
    "麦克风": "Microphone",
    "不录麦克风": "No microphone",
    "圆形": "Circle",
    "圆角矩形": "Rounded rectangle",
    "左上角": "Top left",
    "右上角": "Top right",
    "左下角": "Bottom left",
    "右下角": "Bottom right",
    "人像形状": "Shape",
    "成片位置": "Position",
    "人像大小": "Size",
    "镜像人像": "Mirror camera",
    "打开摄像头预览": "Open camera preview",
    "显示摄像头预览": "Show camera preview",
    "打开提词器 ↗": "Open teleprompter ↗",
    "提词器和控制窗口不会进入成片。拖动人像预览可调整成片位置。": "Controls and script stay out of the video. Drag the camera preview to position it.",
    "● 开始录制": "● Start recording",
    "■ 停止并导出": "■ Stop & export",
    "先选择录制来源，再打开摄像头预览。所有处理在本机完成。": "Choose a source, then open the camera preview. Everything stays on your Mac.",
    "MP4 · 最高 1080p / 30 fps · 麦克风声音 · 暂不录系统声音": "MP4 · Up to 1080p / 30 fps · Microphone audio · No system audio",
    "提词器 · 不会录进视频": "Teleprompter · Excluded from recording",
    "▶ 开始滚动": "▶ Start scrolling",
    "Ⅱ 暂停滚动": "Ⅱ Pause scrolling",
    "回到开头": "Back to top",
    "速度": "Speed",
    "字号": "Text size",
    "找不到摄像头，请重新选择。": "Camera not found. Please select it again.",
    "无法连接摄像头。": "Cannot connect to the camera.",
    "无法读取摄像头画面。": "Cannot read camera frames.",
    "无法建立视频编码器。": "Cannot create the video encoder.",
    "无法建立音频编码器。": "Cannot create the audio encoder.",
    "无法创建 MP4 文件。": "Cannot create the MP4 file.",
    "麦克风音轨写入失败。": "Could not write microphone audio.",
    "视频缓冲区创建失败。": "Could not create a video buffer.",
    "视频缓冲区不足。": "Not enough video buffer memory.",
    "视频帧写入失败。": "Could not write a video frame.",
    "没有正在录制的视频。": "No recording is in progress.",
    "没有收到屏幕画面，请检查屏幕录制权限。": "No screen frames received. Check screen recording permission.",
    "MP4 导出失败。": "MP4 export failed.",
    "正在读取屏幕和窗口；首次使用请允许屏幕录制权限。": "Loading screens and windows. Allow screen recording when prompted.",
    "没有可录制的来源。": "No recording sources found.",
    "来源已就绪。打开摄像头预览后即可开始录制。": "Sources ready. Open the camera preview to start recording.",
    "未检测到摄像头。连接后请重启应用。": "No camera detected. Connect one and reopen the app.",
    "请在系统设置 → 隐私与安全性 → 摄像头中允许 TD Capture。": "Allow TD Capture in System Settings → Privacy & Security → Camera.",
    "摄像头已连接。人像会合成进 MP4；提词器不会录入。": "Camera connected. Your camera appears in the MP4; the teleprompter stays out.",
    "请先点击「选择 / 刷新录制来源」。": "Click “Choose / refresh sources” first.",
    "请先打开摄像头预览，确认可以正常出镜。": "Open the camera preview first and check your picture.",
    "请选择一个新的文件名，避免覆盖已有录制。": "Choose a new filename to keep your existing recording.",
    "麦克风权限未允许。请在系统设置中授权，或选择「不录麦克风」。": "Microphone access denied. Allow it in System Settings, or choose “No microphone”.",
    "录制来源已失效，请刷新。": "The source is no longer available. Refresh the source list.",
    "无麦克风声音": "Microphone off",
    "麦克风已开启": "Microphone on",
    "正在完成 MP4，请勿退出…": "Finishing your MP4. Please keep the app open…",
    "视频已保存，但未收到麦克风数据。请检查麦克风权限和设备。": "Video saved, but no microphone audio was received. Check microphone permission and your device.",
    "录制错误：%@": "Recording error: %@",
    "屏幕 %d · %d × %d": "Screen %d · %d × %d",
    "窗口 · %@ · %@": "Window · %@ · %@",
    "无法读取屏幕：%@。请到系统设置 → 隐私与安全性 → 屏幕与系统音频录制中允许 TD Capture，必要时重启应用。": "Cannot load screens: %@. Allow TD Capture in System Settings → Privacy & Security → Screen & System Audio Recording, then reopen the app if needed.",
    "摄像头连接失败：%@": "Camera connection failed: %@",
    "%d 秒后开始录制…": "Recording starts in %d…",
    "正在录制 · %d × %d · %@ · 提词器不入镜": "Recording · %d × %d · %@ · Script excluded",
    "无法开始录制：%@": "Cannot start recording: %@",
    "录制中断，已保存可恢复片段：%@": "Recording interrupted; available footage saved: %@",
    "已保存 MP4（%d 帧）。%@": "MP4 saved (%d frames). %@",
    "导出失败：%@": "Export failed: %@",
    "在这里粘贴你的讲稿。\n\n点击「开始滚动」，一边看稿，一边讲解。\n\n录制时可以把提词器拖到摄像头附近。整个应用的窗口都会从屏幕捕获中排除，因此提词器不会进入成片。\n\n你可以随时暂停滚动、编辑文字，或者回到开头。": "Paste your script here.\n\nClick “Start scrolling” to read while you present.\n\nMove the teleprompter near your camera. All app windows are excluded from screen capture, so your script stays out of the recording.\n\nPause scrolling to edit, or return to the top at any time."
]

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
                    c.resume(throwing: StudioError(message: "找不到摄像头，请重新选择。")); return
                }
                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    guard self.cameraSession.canAddInput(input) else { throw StudioError(message: "无法连接摄像头。") }
                    self.cameraSession.addInput(input)
                    self.cameraSession.sessionPreset = .high
                    let output = AVCaptureVideoDataOutput()
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    output.alwaysDiscardsLateVideoFrames = true
                    output.setSampleBufferDelegate(self, queue: self.effectsQueue)
                    guard self.cameraSession.canAddOutput(output) else { throw StudioError(message: "无法读取摄像头画面。") }
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
        guard w.canAdd(v) else { throw StudioError(message: "无法建立视频编码器。") }
        w.add(v)
        var mic: AVAssetWriterInput?
        if microphone {
            let m = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128000])
            m.expectsMediaDataInRealTime = true
            guard w.canAdd(m) else { throw StudioError(message: "无法建立音频编码器。") }
            w.add(m); mic = m
        }
        guard w.startWriting() else { throw w.error ?? StudioError(message: "无法创建 MP4 文件。") }
        writer = w; videoInput = v; audioInput = mic; adaptor = a
        epoch = nil; lastVideo = nil; screenFrame = nil; videoCount = 0; audioCount = 0; reportedFailure = false; accepting = true
    }

    func start(filter: SCContentFilter, width: Int, height: Int, microphoneID: String?, url: URL) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            queue.async { do { try self.prepare(url: url, width: width, height: height, microphone: microphoneID != nil); c.resume() } catch { c.resume(throwing: error) } }
        }
        let config = SCStreamConfiguration()
        config.width = width; config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 5; config.showsCursor = true
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
        else { fail(writer?.error?.localizedDescription ?? "麦克风音轨写入失败。") }
    }

    func composited(_ screen: CIImage) -> CIImage {
        let bounds = CGRect(origin: .zero, size: size)
        var result = screen.transformed(by: CGAffineTransform(translationX: -screen.extent.minX, y: -screen.extent.minY))
        result = result.transformed(by: CGAffineTransform(scaleX: size.width / result.extent.width, y: size.height / result.extent.height))
        guard var cam = cameraFrame else { return result.cropped(to: bounds) }
        let side = min(size.width, size.height) * layout.fraction * 1.5
        let cw = side, ch = layout.round ? side : side * 0.75
        let margin = size.width * 0.025
        let x = layout.x.map { $0 * (size.width - cw) } ?? ((layout.corner % 2 == 0) ? margin : size.width - cw - margin)
        let y = layout.y.map { $0 * (size.height - ch) } ?? ((layout.corner < 2) ? size.height - ch - margin : margin)
        let rect = CGRect(x: x, y: y, width: cw, height: ch)
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
        guard let pool = a.pixelBufferPool else { fail("视频缓冲区创建失败。"); return }
        var pixel: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixel) == kCVReturnSuccess, let pixel else { fail("视频缓冲区不足。"); return }
        context.render(composited(image), to: pixel, bounds: CGRect(origin: .zero, size: size), colorSpace: CGColorSpaceCreateDeviceRGB())
        if a.append(pixel, withPresentationTime: time) { lastVideo = time; videoCount += 1 }
        else { fail(writer.error?.localizedDescription ?? "视频帧写入失败。") }
    }

    func stop() async throws -> (Int, Int) {
        if let s = stream { try? await s.stopCapture() }; stream = nil
        return try await withCheckedThrowingContinuation { c in
            queue.async {
                self.frameTimer?.cancel(); self.frameTimer = nil
                self.accepting = false
                guard let w = self.writer else { c.resume(throwing: StudioError(message: "没有正在录制的视频。")); return }
                guard self.epoch != nil else { w.cancelWriting(); self.writer = nil; c.resume(throwing: StudioError(message: "没有收到屏幕画面，请检查屏幕录制权限。")); return }
                self.videoInput?.markAsFinished(); self.audioInput?.markAsFinished()
                let counts = (self.videoCount, self.audioCount)
                w.finishWriting {
                    self.queue.async {
                        self.writer = nil; self.videoInput = nil; self.audioInput = nil; self.adaptor = nil
                        if w.status == .completed { c.resume(returning: counts) }
                        else { c.resume(throwing: w.error ?? StudioError(message: "MP4 导出失败。")) }
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
    let panel: NSPanel
    let text = NSTextView()
    let scroll = NSScrollView()
    let speed = NSSlider(value: 32, minValue: 5, maxValue: 120, target: nil, action: nil)
    let fontSize = NSSlider(value: 32, minValue: 20, maxValue: 64, target: nil, action: nil)
    var resetButton: NSButton!
    var speedLabel: NSTextField!
    var fontLabel: NSTextField!
    let play = NSButton(title: "▶ 开始滚动", target: nil, action: nil)
    var timer: Timer?
    var running = false
    var lastTick = ProcessInfo.processInfo.systemUptime
    override init() {
        panel = NSPanel(contentRect: NSRect(x: 160, y: 520, width: 650, height: 330), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        super.init()
        panel.title = "提词器 · 不会录进视频"; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let root = NSStackView(); root.orientation = .vertical; root.spacing = 12; root.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 16, right: 16)
        panel.contentView = root
        let tools = NSStackView(); tools.spacing = 8
        play.target = self; play.action = #selector(toggle)
        resetButton = NSButton(title: L("回到开头"), target: self, action: #selector(resetPosition))
        speedLabel = NSTextField(labelWithString: L("速度")); fontLabel = NSTextField(labelWithString: L("字号"))
        fontSize.target = self; fontSize.action = #selector(changeFont)
        speed.widthAnchor.constraint(equalToConstant: 105).isActive = true
        fontSize.widthAnchor.constraint(equalToConstant: 90).isActive = true
        [play, resetButton!, speedLabel!, speed, fontLabel!, fontSize].forEach { tools.addArrangedSubview($0) }
        root.addArrangedSubview(tools)
        text.string = L("在这里粘贴你的讲稿。\n\n点击「开始滚动」，一边看稿，一边讲解。\n\n录制时可以把提词器拖到摄像头附近。整个应用的窗口都会从屏幕捕获中排除，因此提词器不会进入成片。\n\n你可以随时暂停滚动、编辑文字，或者回到开头。")
        if let saved = UserDefaults.standard.string(forKey: "prompter.script") { text.string = saved }
        text.delegate = self
        let savedSize = UserDefaults.standard.double(forKey: "prompter.fontSize")
        if savedSize >= 20 { fontSize.doubleValue = savedSize }
        text.font = .systemFont(ofSize: fontSize.doubleValue, weight: .medium); text.textColor = .white; text.backgroundColor = NSColor(white: 0.08, alpha: 1)
        text.textContainerInset = NSSize(width: 20, height: 24)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        scroll.documentView = text; scroll.hasVerticalScroller = true; scroll.drawsBackground = true
        root.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -32).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/30, repeats: true) { [weak self] _ in self?.tick() }
    }
    @objc func toggle() { running.toggle(); lastTick = ProcessInfo.processInfo.systemUptime; play.title = L(running ? "Ⅱ 暂停滚动" : "▶ 开始滚动") }
    @objc func resetPosition() { scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView) }
    @objc func changeFont() { text.font = .systemFont(ofSize: fontSize.doubleValue, weight: .medium); UserDefaults.standard.set(fontSize.doubleValue, forKey: "prompter.fontSize") }
    func textDidChange(_ notification: Notification) { UserDefaults.standard.set(text.string, forKey: "prompter.script") }
    func tick() {
        let now = ProcessInfo.processInfo.systemUptime; let dt = min(0.1, now-lastTick); lastTick = now
        guard running, panel.isVisible else { return }
        let maxY = max(0, text.bounds.height - scroll.contentView.bounds.height)
        let y = min(maxY, scroll.contentView.bounds.minY + speed.doubleValue * dt)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y)); scroll.reflectScrolledClipView(scroll.contentView)
        if y >= maxY { running = false; play.title = L("▶ 开始滚动") }
    }
    func applyLanguage() {
        panel.title = L("提词器 · 不会录进视频")
        play.title = L(running ? "Ⅱ 暂停滚动" : "▶ 开始滚动")
        resetButton.title = L("回到开头"); speedLabel.stringValue = L("速度"); fontLabel.stringValue = L("字号")
        // Translate only the untouched starter text. User-authored scripts stay exactly as written.
        if UserDefaults.standard.string(forKey: "prompter.script") == nil {
            let origin = "在这里粘贴你的讲稿。\n\n点击「开始滚动」，一边看稿，一边讲解。\n\n录制时可以把提词器拖到摄像头附近。整个应用的窗口都会从屏幕捕获中排除，因此提词器不会进入成片。\n\n你可以随时暂停滚动、编辑文字，或者回到开头。"
            if text.string == origin || text.string == englishStrings[origin] { text.string = L(origin) }
        }
    }
    func show() { panel.makeKeyAndOrderFront(nil) }
}

final class Studio: NSObject, @unchecked Sendable, NSApplicationDelegate, NSWindowDelegate {
    var localizedLabels: [(NSTextField, String)] = []
    var promptButton: NSButton!
    var settingsButton: NSButton!
    var backgroundButton: NSButton!
    var backgroundPanel: BackgroundPanel!
    var backgroundWarning: String?
    var settingsPanel: NSPanel?
    var languagePicker: NSPopUpButton?
    var settingsLabel: NSTextField?
    var settingsNote: NSTextField?
    var statusKey = "先选择录制来源，再打开摄像头预览。所有处理在本机完成。"
    var statusArguments: [CVarArg] = []
    let recorder = Recorder()
    var window: NSWindow!
    let source = NSPopUpButton(); let camera = NSPopUpButton(); let microphone = NSPopUpButton()
    let shape = NSPopUpButton(); let position = NSPopUpButton()
    let sizeSlider = NSSlider(value: 0.23, minValue: 0.12, maxValue: 0.42, target: nil, action: nil)
    let mirror = NSButton(checkboxWithTitle: "镜像人像", target: nil, action: nil)
    let start = NSButton(title: "● 开始录制", target: nil, action: nil)
    let previewButton = NSButton(title: "打开摄像头预览", target: nil, action: nil)
    let refreshButton = NSButton(title: "选择 / 刷新录制来源", target: nil, action: nil)
    let status = NSTextField(wrappingLabelWithString: "先选择录制来源，再打开摄像头预览。所有处理在本机完成。")
    let clockLabel = NSTextField(labelWithString: "00:00")
    let cameraView = CameraView(frame: .zero)
    var bubble: DragPanel!
    var prompter: Prompter!
    var content: SCShareableContent?
    var sources: [(SCDisplay?, SCWindow?)] = []
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
            guard let self else { return }; self.showStatus("录制错误：%@", message)
            if self.recording { self.finishRecording(failure: message) }
        }
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func createMenu() {
        let menu = NSMenu(); let app = NSMenuItem(); menu.addItem(app); let sub = NSMenu(); app.submenu = sub
        sub.addItem(withTitle: L("关于 TD Capture"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let settings = sub.addItem(withTitle: L("设置…"), action: #selector(openSettings), keyEquivalent: ","); settings.target = self
        sub.addItem(NSMenuItem.separator()); sub.addItem(withTitle: L("退出 TD Capture"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenuItem(); menu.addItem(edit); edit.title = L("编辑"); edit.submenu = NSMenu(title: L("编辑"))
        for (title, action, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.submenu?.addItem(withTitle: L(title), action: Selector(action), keyEquivalent: key)
        }
        NSApp.mainMenu = menu
    }
    func label(_ s: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSTextField {
        let l = NSTextField(labelWithString: L(s)); localizedLabels.append((l, s)); l.font = .systemFont(ofSize: size, weight: weight); return l
    }
    func row(_ title: String, _ view: NSView) -> NSStackView {
        let l = label(title); l.widthAnchor.constraint(equalToConstant: 112).isActive = true
        let r = NSStackView(views: [l, view]); r.spacing = 12; view.widthAnchor.constraint(equalToConstant: 410).isActive = true; return r
    }
    func buildUI() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 690), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "TD Capture · 录屏与提词器"; window.isReleasedWhenClosed = false; window.delegate = self
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 26, left: 30, bottom: 26, right: 30); window.contentView = root
        settingsButton = NSButton(title: L("设置"), target: self, action: #selector(openSettings))
        let header = NSStackView(views: [label("TD Capture", size: 30, weight: .bold), settingsButton]); header.spacing = 100
        root.addArrangedSubview(header)
        root.addArrangedSubview(label("把演示、出镜和讲稿放在一起。", size: 15))
        root.addArrangedSubview(label("01  选择画面与声音", size: 13, weight: .semibold))
        source.addItem(withTitle: "请点击下方按钮，授权并加载屏幕 / 窗口")
        source.target = self; source.action = #selector(layoutChanged)
        root.addArrangedSubview(row("录制来源", source))
        refreshButton.target = self; refreshButton.action = #selector(refreshSources); root.addArrangedSubview(refreshButton)
        cameras = availableCameras(); microphones = availableMicrophones()
        camera.addItems(withTitles: cameras.map(\.localizedName)); microphone.addItems(withTitles: ["不录麦克风"] + microphones.map(\.localizedName))
        if let defaultMic = AVCaptureDevice.default(for: .audio), let i = microphones.firstIndex(where: { $0.uniqueID == defaultMic.uniqueID }) { microphone.selectItem(at: i+1) }
        else if !microphones.isEmpty { microphone.selectItem(at: 1) }
        camera.target = self; camera.action = #selector(cameraChanged)
        root.addArrangedSubview(row("摄像头", camera)); root.addArrangedSubview(row("麦克风", microphone))
        root.addArrangedSubview(label("02  人像布局", size: 13, weight: .semibold))
        shape.addItems(withTitles: ["圆形", "圆角矩形"]); position.addItems(withTitles: ["左上角", "右上角", "左下角", "右下角"]); position.selectItem(at: 3)
        for c in [shape, position] { c.target = self; c.action = #selector(layoutChanged) }
        sizeSlider.target = self; sizeSlider.action = #selector(layoutChanged)
        mirror.state = .on; mirror.target = self; mirror.action = #selector(layoutChanged)
        root.addArrangedSubview(row("人像形状", shape)); root.addArrangedSubview(row("成片位置", position)); root.addArrangedSubview(row("人像大小", sizeSlider))
        backgroundButton = NSButton(title: L("背景效果…"), target: self, action: #selector(openBackground))
        let previewRow = NSStackView(views: [mirror, previewButton, backgroundButton]); previewRow.spacing = 12; root.addArrangedSubview(previewRow)
        previewButton.target = self; previewButton.action = #selector(openCamera)
        promptButton = NSButton(title: L("打开提词器 ↗"), target: self, action: #selector(openPrompter)); root.addArrangedSubview(promptButton)
        root.addArrangedSubview(label("提词器和控制窗口不会进入成片。拖动人像预览可调整成片位置。", size: 11))
        let actions = NSStackView(); actions.spacing = 24
        start.target = self; start.action = #selector(toggleRecording); start.bezelStyle = .rounded; start.controlSize = .large
        clockLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .medium)
        actions.addArrangedSubview(start); actions.addArrangedSubview(clockLabel); root.addArrangedSubview(actions)
        status.preferredMaxLayoutWidth = 520; status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor
        root.addArrangedSubview(status)
        root.addArrangedSubview(label("MP4 · 最高 1080p / 30 fps · 麦克风声音 · 暂不录系统声音", size: 11))
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
        prompter = Prompter(); applyLanguage(); layoutChanged()
    }
    func showStatus(_ key: String, _ arguments: CVarArg...) {
        statusKey = key; statusArguments = arguments; renderStatus()
    }
    func renderStatus() {
        let template = L(statusKey)
        var arguments = statusArguments
        if statusKey == "正在录制 · %d × %d · %@ · 提词器不入镜", arguments.count == 3, let key = arguments[2] as? String { arguments[2] = L(key) }
        status.stringValue = arguments.isEmpty ? template : String(format: template, arguments: arguments)
    }
    func applyLanguage() {
        window.title = L("TD Capture · 录屏与提词器")
        for (field, key) in localizedLabels { field.stringValue = L(key) }
        settingsButton.title = L("设置"); promptButton.title = L("打开提词器 ↗")
        mirror.title = L("镜像人像"); refreshButton.title = L("选择 / 刷新录制来源")
        start.title = L(recording ? "■ 停止并导出" : "● 开始录制")
        previewButton.title = L(cameraReady ? "显示摄像头预览" : "打开摄像头预览")
        let shapeIndex = shape.indexOfSelectedItem, positionIndex = position.indexOfSelectedItem
        shape.removeAllItems(); shape.addItems(withTitles: [L("圆形"), L("圆角矩形")]); shape.selectItem(at: shapeIndex)
        position.removeAllItems(); position.addItems(withTitles: ["左上角", "右上角", "左下角", "右下角"].map { L($0) }); position.selectItem(at: positionIndex)
        microphone.item(at: 0)?.title = L("不录麦克风")
        if sources.isEmpty { source.item(at: 0)?.title = L("请点击下方按钮，授权并加载屏幕 / 窗口") }
        else {
            var displayNumber = 0
            for (i, pair) in sources.enumerated() {
                if let d = pair.0 { displayNumber += 1; source.item(at: i)?.title = L("屏幕 %d · %d × %d", displayNumber, d.width, d.height) }
                else if let w = pair.1 { source.item(at: i)?.title = L("窗口 · %@ · %@", w.owningApplication?.applicationName ?? "", w.title ?? "") }
            }
        }
        settingsPanel?.title = L("设置"); settingsLabel?.stringValue = L("界面语言")
        settingsNote?.stringValue = L("更改后立即生效，并自动保存。")
        languagePicker?.selectItem(at: UserDefaults.standard.string(forKey: "ui.language") == "en" ? 1 : 0)
        backgroundButton.title = L("背景效果…"); backgroundPanel?.applyLanguage()
        backgroundPanel?.warning.stringValue = backgroundWarning.map { L($0) } ?? ""
        prompter?.applyLanguage(); renderStatus(); createMenu()
    }
    @objc func openSettings() {
        if settingsPanel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 155), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false; panel.level = .floating
            let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 20
            root.edgeInsets = NSEdgeInsets(top: 26, left: 26, bottom: 26, right: 26)
            settingsLabel = NSTextField(labelWithString: L("界面语言"))
            let picker = NSPopUpButton(); picker.addItems(withTitles: ["简体中文", "English"])
            picker.target = self; picker.action = #selector(languageChanged); languagePicker = picker
            let row = NSStackView(views: [settingsLabel!, picker]); row.spacing = 24; root.addArrangedSubview(row)
            settingsNote = NSTextField(labelWithString: L("更改后立即生效，并自动保存。")); settingsNote?.font = .systemFont(ofSize: 12)
            root.addArrangedSubview(settingsNote!); panel.contentView = root; settingsPanel = panel
        }
        settingsPanel?.title = L("设置")
        languagePicker?.selectItem(at: UserDefaults.standard.string(forKey: "ui.language") == "en" ? 1 : 0)
        settingsPanel?.center(); settingsPanel?.makeKeyAndOrderFront(nil)
    }
    @objc func languageChanged() {
        UserDefaults.standard.set(languagePicker?.indexOfSelectedItem == 1 ? "en" : "zh-Hans", forKey: "ui.language")
        applyLanguage()
    }
    @objc func refreshSources() {
        guard !busy, !recording else { return }
        busy = true; start.isEnabled = false; refreshButton.isEnabled = false
        showStatus("正在读取屏幕和窗口；首次使用请允许屏幕录制权限。")
        Task { @MainActor in
            defer { busy = false; start.isEnabled = true; refreshButton.isEnabled = true }
            do {
                content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                sources = []; source.removeAllItems()
                for (i, display) in (content?.displays ?? []).enumerated() {
                    source.addItem(withTitle: L("屏幕 %d · %d × %d", i+1, display.width, display.height)); sources.append((display, nil))
                }
                for w in (content?.windows ?? []).filter({ $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier && $0.windowLayer == 0 && $0.frame.width > 160 && $0.frame.height > 100 && !($0.title ?? "").isEmpty }) {
                    source.addItem(withTitle: L("窗口 · %@ · %@", w.owningApplication?.applicationName ?? "", w.title ?? "")); sources.append((nil, w))
                }
                showStatus(sources.isEmpty ? "没有可录制的来源。" : "来源已就绪。打开摄像头预览后即可开始录制。")
            } catch { showStatus("无法读取屏幕：%@。请到系统设置 → 隐私与安全性 → 屏幕与系统音频录制中允许 TD Capture，必要时重启应用。", error.localizedDescription) }
        }
    }
    @objc func cameraChanged() {
        if cameraReady { recorder.stopCamera(); cameraReady = false; bubble.orderOut(nil); previewButton.title = L("打开摄像头预览") }
    }
    @objc func openCamera() {
        guard !busy, !recording else { return }
        guard camera.indexOfSelectedItem >= 0, cameras.indices.contains(camera.indexOfSelectedItem) else { showStatus("未检测到摄像头。连接后请重启应用。"); return }
        busy = true; start.isEnabled = false; previewButton.isEnabled = false
        Task { @MainActor in
            defer { busy = false; start.isEnabled = true; previewButton.isEnabled = true }
            guard await AVCaptureDevice.requestAccess(for: .video) else { showStatus("请在系统设置 → 隐私与安全性 → 摄像头中允许 TD Capture。"); return }
            do {
                try await recorder.configureCamera(id: cameras[camera.indexOfSelectedItem].uniqueID)
                cameraReady = true; previewButton.title = L("显示摄像头预览"); layoutChanged(); bubble.orderFrontRegardless()
                showStatus("摄像头已连接。人像会合成进 MP4；提词器不会录入。")
            } catch { cameraReady = false; showStatus("摄像头连接失败：%@", error.localizedDescription) }
        }
    }
    @objc func openBackground() { backgroundPanel.show() }
    @objc func openPrompter() { prompter.show() }
    @objc func layoutChanged() {
        selectedLayout.fraction = sizeSlider.doubleValue; selectedLayout.corner = position.indexOfSelectedItem
        selectedLayout.round = shape.indexOfSelectedItem == 0; selectedLayout.mirror = mirror.state == .on
        selectedLayout.x = nil; selectedLayout.y = nil; recorder.updateLayout(selectedLayout)
        guard bubble != nil else { return }
        let screen = targetScreen(); let frame = screen.frame
        let side = min(frame.width, frame.height) * selectedLayout.fraction * 1.5
        let height = selectedLayout.round ? side : side * 0.75
        let m = frame.width * 0.025
        let x = frame.minX + (selectedLayout.corner % 2 == 0 ? m : frame.width - side - m)
        let y = frame.minY + (selectedLayout.corner < 2 ? frame.height - height - m : m)
        bubble.setFrame(NSRect(x: x, y: y, width: side, height: height), display: true)
        cameraView.layer?.cornerRadius = selectedLayout.round ? side/2 : 16; cameraView.layer?.masksToBounds = true
        cameraView.mirrored = selectedLayout.mirror
    }
    func targetScreen() -> NSScreen {
        if sources.indices.contains(source.indexOfSelectedItem), let display = sources[source.indexOfSelectedItem].0,
           let s = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID }) { return s }
        return bubble?.screen ?? NSScreen.main ?? NSScreen.screens[0]
    }
    @objc func bubbleMoved() {
        guard cameraReady else { return }
        let frame = targetScreen().frame; let b = bubble.frame
        selectedLayout.x = max(0, min(1, (b.minX-frame.minX)/max(1, frame.width-b.width)))
        selectedLayout.y = max(0, min(1, (b.minY-frame.minY)/max(1, frame.height-b.height)))
        recorder.updateLayout(selectedLayout)
    }
    func lockControls(_ locked: Bool) {
        [source, camera, microphone, previewButton, refreshButton].forEach { $0.isEnabled = !locked }
    }
    @objc func toggleRecording() {
        if recording { finishRecording(); return }
        guard !busy else { return }
        guard sources.indices.contains(source.indexOfSelectedItem), let content else { showStatus("请先点击「选择 / 刷新录制来源」。"); return }
        guard cameraReady else { showStatus("请先打开摄像头预览，确认可以正常出镜。"); return }
        let save = NSSavePanel(); save.allowedContentTypes = [.mpeg4Movie]; save.nameFieldStringValue = "TD-Capture-\(Self.stamp()).mp4"; save.canCreateDirectories = true
        guard save.runModal() == .OK, let url = save.url else { return }
        // AVAssetWriter requires a new path. Preserve existing recordings rather than deleting them.
        guard !FileManager.default.fileExists(atPath: url.path) else { showStatus("请选择一个新的文件名，避免覆盖已有录制。"); return }
        busy = true; start.isEnabled = false; lockControls(true)
        let item = sources[source.indexOfSelectedItem]
        let micID = microphone.indexOfSelectedItem > 0 ? microphones[microphone.indexOfSelectedItem-1].uniqueID : nil
        Task { @MainActor in
            do {
                if micID != nil, !(await AVCaptureDevice.requestAccess(for: .audio)) { throw StudioError(message: "麦克风权限未允许。请在系统设置中授权，或选择「不录麦克风」。") }
                let filter: SCContentFilter; let original: CGSize
                if let d = item.0 {
                    let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                    filter = SCContentFilter(display: d, excludingApplications: own, exceptingWindows: [])
                    original = CGSize(width: d.width, height: d.height)
                } else if let w = item.1 { filter = SCContentFilter(desktopIndependentWindow: w); original = w.frame.size }
                else { throw StudioError(message: "录制来源已失效，请刷新。") }
                let scale = min(1, min(1920 / original.width, 1080 / original.height))
                let width = max(2, Int(original.width * scale)/2*2), height = max(2, Int(original.height * scale)/2*2)
                outputURL = url
                for n in (1...3).reversed() { showStatus("%d 秒后开始录制…", n); try await Task.sleep(nanoseconds: 1_000_000_000) }
                try await recorder.start(filter: filter, width: width, height: height, microphoneID: micID, url: url)
                recording = true; busy = false; started = Date(); start.isEnabled = true; start.title = L("■ 停止并导出")
                showStatus("正在录制 · %d × %d · %@ · 提词器不入镜", width, height, micID == nil ? "无麦克风声音" : "麦克风已开启")
                ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self = self] _ in
                    guard let self else { return }; let s = Int(Date().timeIntervalSince(self.started)); self.clockLabel.stringValue = String(format: "%02d:%02d", s/60, s%60)
                }
            } catch { busy = false; start.isEnabled = true; lockControls(false); showStatus("无法开始录制：%@", error.localizedDescription) }
        }
    }
    func finishRecording(failure: String? = nil) {
        guard recording, !busy else { return }
        busy = true; recording = false; start.isEnabled = false; ticker?.invalidate(); ticker = nil
        showStatus("正在完成 MP4，请勿退出…")
        Task { @MainActor in
            do {
                let counts = try await recorder.stop()
                if let failure { showStatus("录制中断，已保存可恢复片段：%@", failure) }
                else if microphone.indexOfSelectedItem > 0 && counts.1 == 0 { showStatus("视频已保存，但未收到麦克风数据。请检查麦克风权限和设备。") }
                else { showStatus("已保存 MP4（%d 帧）。%@", counts.0, outputURL?.lastPathComponent ?? "") }
                if let outputURL { NSWorkspace.shared.activateFileViewerSelecting([outputURL]) }
            } catch { showStatus("导出失败：%@", error.localizedDescription) }
            busy = false; start.isEnabled = true; start.title = L("● 开始录制"); lockControls(false)
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
    func applicationWillTerminate(_ notification: Notification) { recorder.stopCamera() }
}

if let index = CommandLine.arguments.firstIndex(of: "--background-self-test"), CommandLine.arguments.count > index + 2 {
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
        for i in 0..<60 {
            while r.videoInput?.isReadyForMoreMediaData == false { Thread.sleep(forTimeInterval: 0.005) }
            let image = CIImage(color: CIColor(red: 0.05, green: CGFloat(i)/120, blue: 0.3)).cropped(to: CGRect(x: 0, y: 0, width: 1280, height: 720))
            r.appendScreen(image, time: CMTime(value: Int64(i), timescale: 30))
            var asbd = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
            var format: CMAudioFormatDescription?
            guard CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format) == noErr else { throw StudioError(message: "测试音频格式失败") }
            var block: CMBlockBuffer?
            guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: 3200, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: 3200, flags: 0, blockBufferOut: &block) == noErr, let block else { throw StudioError(message: "测试音频缓冲区失败") }
            let samples: [Int16] = (0..<1600).map { n in Int16(sin(Double(i * 1600 + n) * 440 * 2 * .pi / 48000) * 4000) }
            _ = samples.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: 3200) }
            var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48000), presentationTimeStamp: CMTime(value: Int64(i*1600), timescale: 48000), decodeTimeStamp: .invalid)
            var sample: CMSampleBuffer?
            guard CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1600, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample) == noErr, let sample else { throw StudioError(message: "测试音频样本失败") }
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
                guard audio.count == 1, counts.1 == 60 else { throw StudioError(message: "AAC 音轨验证失败") }
                let generator = AVAssetImageGenerator(asset: asset)
                let cg = try await generator.image(at: CMTime(value: 1, timescale: 1)).image
                let rep = NSBitmapImageRep(cgImage: cg)
                let face = rep.colorAt(x: 1120, y: 560)!
                let background = rep.colorAt(x: 100, y: 100)!
                guard face.redComponent > 0.8, background.redComponent < 0.2 else { throw StudioError(message: "人像合成像素验证失败") }
                if let png = rep.representation(using: .png, properties: [:]) { try png.write(to: url.deletingPathExtension().appendingPathExtension("png")) }
                guard counts.0 == 60, tracks.count == 1, CMTimeGetSeconds(duration) > 1.9 else { throw StudioError(message: "编码验证失败") }
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
