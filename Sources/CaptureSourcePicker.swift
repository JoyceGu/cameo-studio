import AppKit
import ScreenCaptureKit

struct CaptureTarget {
    let filter: SCContentFilter
    let title: String
    let frame: CGRect // Quartz global coordinates: origin at the main display's top left.
    let windowID: CGWindowID?
    let displayID: CGDirectDisplayID?
    var sourceRect: CGRect? = nil // Display-local points, measured from the top left.

    var supportsPointerCoordinates: Bool { windowID != nil || displayID != nil }

    var currentFrame: CGRect {
        guard let windowID,
              let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let bounds = info.first?[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary), rect.width > 0, rect.height > 0 else { return frame }
        return rect
    }
}

final class CaptureSourcePicker: NSObject, SCContentSharingPickerObserver {
    var onSelect: ((CaptureTarget) -> Void)?
    var onMessage: ((String) -> Void)?
    private var selectionGeneration = 0
    private var requestedScreenAccess = false
    private var awaitingPicker = false
    private var regionSelector: CaptureRegionSelector?
    private let regionGuide = CaptureRegionGuide()
    override init() {
        super.init()
        let picker = SCContentSharingPicker.shared
        picker.add(self); picker.isActive = true
    }
    private func present(mode: SCContentSharingPickerMode, style: SCShareableContentStyle) {
        selectionGeneration += 1
        regionSelector?.cancel(); regionSelector = nil
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = mode
        configuration.excludedBundleIDs = [Bundle.main.bundleIdentifier ?? "local.joyce.CameoStudio"]
        configuration.allowsChangingSelectedContent = false
        picker.defaultConfiguration = configuration
        picker.isActive = true
        awaitingPicker = true
        picker.present(using: style)
    }
    func chooseWindow() { present(mode: .singleWindow, style: .window) }
    func chooseScreen() {
        if NSScreen.screens.count == 1, let screen = NSScreen.screens.first,
           let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value {
            prepareDisplay(id: id); return
        }
        let menu = NSMenu()
        for (index, screen) in NSScreen.screens.enumerated() {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let item = NSMenuItem(title: L("Display %d · %@", index + 1, screen.localizedName), action: #selector(selectDisplay(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = id; menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    @objc private func selectDisplay(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? NSNumber else { return }
        prepareDisplay(id: id.uint32Value)
    }
    private func prepareDisplay(id: CGDirectDisplayID, crop: CGRect? = nil) {
        selectionGeneration += 1; awaitingPicker = false
        let generation = selectionGeneration
        if !CGPreflightScreenCaptureAccess() {
            if !requestedScreenAccess {
                requestedScreenAccess = true
                _ = CGRequestScreenCaptureAccess()
            }
            guard CGPreflightScreenCaptureAccess() else {
                regionGuide.restore()
                onMessage?("Allow screen recording for this TD Capture build in System Settings, then quit and reopen the app. Your previous source is unchanged.")
                showScreenPermissionRecovery(); return
            }
        }
        onMessage?("Checking the selected screen…")
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.currentProcess
                guard let display = content.displays.first(where: { $0.displayID == id }) else {
                    throw NSError(domain: "TDCapture.Source", code: 1, userInfo: [NSLocalizedDescriptionKey: L("Cannot identify the selected screen. Please choose it again.")])
                }
                let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                guard !own.isEmpty else {
                    throw NSError(domain: "TDCapture.Source", code: 2, userInfo: [NSLocalizedDescriptionKey: L("Cannot exclude recorder controls from the selected screen. Please reopen TD Capture and choose the screen again.")])
                }
                let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
                let rect = crop ?? CGRect(origin: .zero, size: display.frame.size)
                let configuration = SCStreamConfiguration()
                configuration.width = 320; configuration.height = max(2, Int(320 * rect.height / max(1, rect.width)))
                configuration.showsCursor = false; configuration.capturesAudio = false
                if let crop { configuration.sourceRect = crop }
                // Validate the same filter and crop that recording will use.
                _ = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                guard generation == self.selectionGeneration else { return }
                let title = crop == nil ? L("Screen · %d × %d", display.width, display.height) : L("Region · %d × %d pt", Int(rect.width), Int(rect.height))
                let target = CaptureTarget(filter: filter, title: title, frame: rect.offsetBy(dx: display.frame.minX, dy: display.frame.minY), windowID: nil, displayID: id, sourceRect: crop)
                self.regionGuide.setTarget(target)
                self.onSelect?(target)
            } catch {
                guard generation == self.selectionGeneration else { return }
                if (error as NSError).code == -3801 { self.showScreenPermissionRecovery() }
                self.report(error)
                self.regionGuide.restore()
            }
        }
    }
    func chooseRegion() {
        selectionGeneration += 1
        awaitingPicker = false
        regionSelector?.cancel()
        regionGuide.hide()
        let generation = selectionGeneration
        let selector = CaptureRegionSelector(); regionSelector = selector
        selector.select(completion: { [weak self] displayID, crop in
            guard let self, generation == self.selectionGeneration else { return }
            self.regionSelector = nil
            self.prepareDisplay(id: displayID, crop: crop)
        }, onCancel: { [weak self] in
            guard let self, generation == self.selectionGeneration else { return }
            self.regionSelector = nil
            self.regionGuide.restore()
            self.onMessage?("Source selection cancelled. Your previous source is unchanged.")
        })
    }
    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        DispatchQueue.main.async {
            guard self.awaitingPicker else { return }
            self.awaitingPicker = false
            self.selectionGeneration += 1
            self.onMessage?("Source selection cancelled. Your previous source is unchanged.")
        }
    }
    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        DispatchQueue.main.async { self.awaitingPicker = false; self.report(error) }
    }
    private func report(_ error: Error) {
        let detail = error as NSError
        onMessage?(L("Source selection failed (%@ %d): %@. Your previous source is unchanged.", detail.domain, detail.code, detail.localizedDescription))
    }
    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        DispatchQueue.main.async {
            guard self.awaitingPicker else { return }
            self.awaitingPicker = false
            if filter.style == .window {
                var frame = filter.contentRect
                var title = L("Selected window")
                var id: CGWindowID?
                if #available(macOS 15.2, *), let window = filter.includedWindows.first {
                    frame = window.frame; id = window.windowID
                    title = (window.owningApplication?.applicationName ?? "") + " · " + (window.title ?? L("Selected window"))
                }
                self.regionGuide.setTarget(nil)
                self.onSelect?(CaptureTarget(filter: filter, title: title, frame: frame, windowID: id, displayID: nil))
            }
        }
    }
    private func showScreenPermissionRecovery() {
        let alert = NSAlert()
        alert.messageText = L("Screen recording permission is unavailable for this build")
        alert.informativeText = L("TD Capture needs Screen & System Audio Recording permission to record a display or region and exclude its controls. Allow the current app in System Settings, then quit and reopen it. If an enabled entry belongs to an older local build, remove it and add this current app. Your previous source is unchanged.")
        alert.addButton(withTitle: L("Open System Settings"))
        alert.addButton(withTitle: L("Cancel"))
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    func close() { selectionGeneration += 1; regionSelector?.cancel(); regionSelector = nil; regionGuide.close(); SCContentSharingPicker.shared.remove(self); SCContentSharingPicker.shared.isActive = false }
}
