import AppKit
import ScreenCaptureKit

struct CaptureTarget {
    let filter: SCContentFilter
    let title: String
    let frame: CGRect // Quartz global coordinates: origin at the main display's top left.
    let windowID: CGWindowID?
    let displayID: CGDirectDisplayID?

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
    override init() {
        super.init()
        let picker = SCContentSharingPicker.shared
        picker.add(self); picker.isActive = true
    }
    private func present(mode: SCContentSharingPickerMode, style: SCShareableContentStyle) {
        selectionGeneration += 1
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = mode
        configuration.excludedBundleIDs = [Bundle.main.bundleIdentifier ?? "local.joyce.CameoStudio"]
        configuration.allowsChangingSelectedContent = false
        picker.defaultConfiguration = configuration
        picker.isActive = true
        picker.present(using: style)
    }
    func chooseWindow() { present(mode: .singleWindow, style: .window) }
    func chooseScreen() { present(mode: .singleDisplay, style: .display) }
    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        DispatchQueue.main.async {
            self.selectionGeneration += 1
            self.onMessage?("Source selection cancelled. Your previous source is unchanged.")
        }
    }
    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        DispatchQueue.main.async { self.report(error) }
    }
    private func report(_ error: Error) {
        let detail = error as NSError
        onMessage?(L("Source selection failed (%@ %d): %@. Your previous source is unchanged.", detail.domain, detail.code, detail.localizedDescription))
    }
    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        DispatchQueue.main.async {
            let generation = self.selectionGeneration
            if filter.style == .display {
                self.onMessage?("Checking the selected screen…")
                Task { @MainActor in
                    var stage = "Read the system-selected screen"
                    do {
                        // Keep the picker's consent-bearing filter intact for the first
                        // check. A newly constructed filter does not inherit that consent.
                        let configuration = SCStreamConfiguration()
                        configuration.width = 320
                        configuration.height = max(2, Int(320 * filter.contentRect.height / max(1, filter.contentRect.width)))
                        configuration.showsCursor = false; configuration.capturesAudio = false
                        _ = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                        stage = "Read recorder window metadata"
                        // This redacted API exposes our own process without requesting
                        // broad screen access. Keep our UI excluded from full-display video.
                        let ownContent = try await SCShareableContent.currentProcess
                        let display: SCDisplay
                        if #available(macOS 15.2, *), let selected = filter.includedDisplays.first {
                            display = selected
                        } else {
                            let exact = ownContent.displays.filter { $0.frame == filter.contentRect }
                            let sameSize = ownContent.displays.filter { $0.frame.size == filter.contentRect.size }
                            guard let selected = exact.first ?? (sameSize.count == 1 ? sameSize.first : nil) else {
                                throw NSError(domain: "TDCapture.Source", code: 1, userInfo: [NSLocalizedDescriptionKey: L("Cannot identify the selected screen. Please choose it again.")])
                            }
                            display = selected
                        }
                        let own = ownContent.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                        guard !own.isEmpty else {
                            throw NSError(domain: "TDCapture.Source", code: 2, userInfo: [NSLocalizedDescriptionKey: L("Cannot exclude recorder controls from the selected screen. Please reopen TD Capture and choose the screen again.")])
                        }
                        // Excluding our UI requires a separate filter and broad screen
                        // recording permission, even after a successful picker selection.
                        stage = "Exclude recorder controls and teleprompter"
                        let captureFilter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
                        // Validate a real frame instead of treating a Settings toggle as
                        // proof of access. The frame is discarded, never saved or uploaded.
                        _ = try await SCScreenshotManager.captureImage(contentFilter: captureFilter, configuration: configuration)
                        guard generation == self.selectionGeneration else { return }
                        let title = L("Screen · %d × %d", display.width, display.height)
                        self.onSelect?(CaptureTarget(filter: captureFilter, title: title, frame: display.frame, windowID: nil, displayID: display.displayID))
                    } catch {
                        guard generation == self.selectionGeneration else { return }
                        let detail = error as NSError
                        if stage == "Exclude recorder controls and teleprompter", detail.code == -3801 {
                            self.showScreenPermissionRecovery()
                        }
                        self.onMessage?(L("Screen check failed at %@ (%@ %d): %@. Your previous source is unchanged.", L(stage), detail.domain, detail.code, detail.localizedDescription))
                    }
                }
            } else {
                var frame = filter.contentRect
                var title = L("Selected window")
                var id: CGWindowID?
                if #available(macOS 15.2, *), let window = filter.includedWindows.first {
                    frame = window.frame; id = window.windowID
                    title = (window.owningApplication?.applicationName ?? "") + " · " + (window.title ?? L("Selected window"))
                }
                self.onSelect?(CaptureTarget(filter: filter, title: title, frame: frame, windowID: id, displayID: nil))
            }
        }
    }
    private func showScreenPermissionRecovery() {
        let alert = NSAlert()
        alert.messageText = L("Screen selected, but recorder exclusion was denied")
        alert.informativeText = L("macOS allowed the selected screen, but denied the separate access needed to keep recorder controls and your script out of the video. A Settings switch can refer to an older local build. In Screen & System Audio Recording, remove the TD Capture entry with −, add this current app with +, and reopen it if macOS asks. Your previous source is unchanged.")
        alert.addButton(withTitle: L("Open System Settings"))
        alert.addButton(withTitle: L("Cancel"))
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    func close() { selectionGeneration += 1; SCContentSharingPicker.shared.remove(self); SCContentSharingPicker.shared.isActive = false }
}
