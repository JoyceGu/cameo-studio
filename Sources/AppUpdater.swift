import AppKit

final class AppUpdater: NSObject {
    let view = NSStackView()
    let versionLabel = NSTextField(labelWithString: "")
    let message = NSTextField(wrappingLabelWithString: "")
    let checkButton = NSButton(title: "", target: nil, action: nil)
    let installButton = NSButton(title: "", target: nil, action: nil)
    let releasesButton = NSButton(title: "", target: nil, action: nil)
    let progress = NSProgressIndicator()
    var canInstall: (() -> Bool)?
    var onInstallStateChanged: ((Bool) -> Void)?
    private(set) var isInstalling = false
    private var working = false
    private var candidate: (AppVersion, GitHubRelease.Asset)?
    private var statusKey = "Check GitHub Releases for the latest version."
    private var statusArguments: [CVarArg] = []
    private let session: URLSession
    private let current: AppVersion
    private let app: URL
    private let updates: URL

    override init() {
        app = Bundle.main.bundleURL
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let build = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
        current = AppVersion(version, build: build) ?? AppVersion("0.0.0")!
        updates = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TD Capture/Updates", isDirectory: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60; configuration.timeoutIntervalForResource = 300
        session = URLSession(configuration: configuration)
        super.init()
        view.orientation = .vertical; view.alignment = .leading; view.spacing = 10
        versionLabel.font = .systemFont(ofSize: 12); versionLabel.textColor = .secondaryLabelColor
        message.font = .systemFont(ofSize: 12); message.preferredMaxLayoutWidth = 448
        message.widthAnchor.constraint(equalToConstant: 448).isActive = true
        progress.style = .spinning; progress.controlSize = .small; progress.isDisplayedWhenStopped = false
        checkButton.target = self; checkButton.action = #selector(checkForUpdates)
        installButton.target = self; installButton.action = #selector(downloadAndInstall)
        releasesButton.target = self; releasesButton.action = #selector(openReleases)
        installButton.isHidden = true
        let actions = NSStackView(views: [checkButton, installButton, progress]); actions.spacing = 10
        [versionLabel, actions, message, releasesButton].forEach { view.addArrangedSubview($0) }
        releasesButton.isBordered = false; releasesButton.contentTintColor = .linkColor
        if let data = try? Data(contentsOf: updates.appendingPathComponent("LastUpdate.json")),
           let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any], result["success"] as? Bool == false {
            statusKey = "The previous update did not finish. Your previous app and local data were retained."
        }
        applyLanguage()
    }
    func applyLanguage() {
        versionLabel.stringValue = L("Current version: %@ (build %d)", current.string, current.build)
        checkButton.title = L("Check for updates")
        installButton.title = L("Download and install…")
        releasesButton.title = L("View GitHub Releases")
        message.stringValue = String(format: L(statusKey), arguments: statusArguments)
    }
    private func status(_ key: String, _ arguments: CVarArg...) {
        statusKey = key; statusArguments = arguments; applyLanguage()
    }
    private func setWorking(_ value: Bool) {
        working = value; checkButton.isEnabled = !value; installButton.isEnabled = !value
        if value { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
    }
    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("TD-Capture/\(current.string)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }
    @objc func checkForUpdates() {
        guard !working else { return }
        candidate = nil; installButton.isHidden = true; setWorking(true)
        status("Checking GitHub Releases…")
        Task { @MainActor in
            defer { setWorking(false) }
            do {
                let url = URL(string: "https://api.github.com/repos/JoyceGu/td-capture/releases/latest")!
                let (data, response) = try await session.data(for: request(url))
                guard let http = response as? HTTPURLResponse else { throw UpdateError(message: "Cannot read the update response.") }
                if http.statusCode == 403 || http.statusCode == 429 { throw UpdateError(message: "GitHub is limiting update checks. Please try again later.") }
                guard http.statusCode == 200, data.count <= 1_048_576 else { throw UpdateError(message: "Cannot read the latest GitHub release.") }
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                guard let version = release.version, !release.draft, !release.prerelease else { throw UpdateError(message: "No compatible stable release was found.") }
                guard version > current else { status("You are up to date."); return }
                let next = try release.candidate()
                candidate = next; installButton.isHidden = false
                status("Version %@ (build %d) is available. Scripts and settings stay on this Mac.", next.0.string, next.0.build)
            } catch { status("Update check failed: %@", L(error.localizedDescription)) }
        }
    }
    @objc private func openReleases() { NSWorkspace.shared.open(URL(string: "https://github.com/JoyceGu/td-capture/releases/latest")!) }
    @objc private func downloadAndInstall() {
        guard !working, let candidate else { return }
        guard canInstall?() == true else { status("Stop recording, exporting and teleprompter scrolling before updating."); return }
        guard app.pathExtension == "app", !app.path.contains("/AppTranslocation/"), FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path) else {
            status("The app folder is not writable. Move TD Capture to a writable folder and try again."); return
        }
        setWorking(true); status("Downloading and verifying the update…")
        Task { @MainActor in
            let manager = FileManager.default
            let token = UUID().uuidString
            let work = updates.appendingPathComponent(token, isDirectory: true)
            var handedOff = false
            defer {
                if !handedOff { try? manager.removeItem(at: work); setWorking(false) }
            }
            do {
                try manager.createDirectory(at: work, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let url = URL(string: candidate.1.browser_download_url)!
                let (downloaded, response) = try await session.download(for: URLRequest(url: url))
                defer { try? manager.removeItem(at: downloaded) }
                guard (response as? HTTPURLResponse)?.statusCode == 200, response.url?.scheme == "https" else { throw UpdateError(message: "The update download failed.") }
                let size = try downloaded.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size == candidate.1.size, size <= UpdateArchive.maximumBytes else { throw UpdateError(message: "The update download is incomplete or too large.") }
                let data = try Data(contentsOf: downloaded, options: .mappedIfSafe)
                try UpdateArchive.validate(data, digest: candidate.1.digest!)
                let archive = work.appendingPathComponent("update.zip")
                try manager.copyItem(at: downloaded, to: archive)
                let unpacked = work.appendingPathComponent("Unpacked", isDirectory: true)
                _ = try UpdateInstaller.run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path])
                let staged = unpacked.appendingPathComponent("TD Capture.app")
                let actual = try UpdateInstaller.validateBundle(staged, minimum: candidate.0)
                guard actual.parts == candidate.0.parts, actual > current else { throw UpdateError(message: "The downloaded app has an unexpected identity or version.") }
                let alert = NSAlert()
                alert.messageText = L("Install update and restart?")
                alert.informativeText = L("Version %@ (build %d) is verified. Your scripts and settings will be backed up and kept. macOS may ask to renew recording permissions.", actual.string, actual.build)
                alert.addButton(withTitle: L("Install and restart")); alert.addButton(withTitle: L("Cancel"))
                guard alert.runModal() == .alertFirstButtonReturn else { status("Update cancelled. Your app and data are unchanged."); return }
                guard canInstall?() == true else { status("Stop recording, exporting and teleprompter scrolling before updating."); return }
                let backup = updates.deletingLastPathComponent().appendingPathComponent("UpdateBackups/" + token, isDirectory: true)
                try manager.createDirectory(at: backup, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try NoteStore().backupLibrary(to: backup.appendingPathComponent("Notes", isDirectory: true))
                UserDefaults.standard.synchronize()
                let preferences = UserDefaults.standard.persistentDomain(forName: "local.joyce.CameoStudio") ?? [:]
                let preferencesURL = backup.appendingPathComponent("preferences.plist")
                try PropertyListSerialization.data(fromPropertyList: preferences, format: .binary, options: 0).write(to: preferencesURL, options: .atomic)
                try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: preferencesURL.path)
                let job = UpdateInstallJob(parentPID: ProcessInfo.processInfo.processIdentifier, currentApp: app.path, stagedApp: staged.path, backupDirectory: backup.path, resultFile: updates.appendingPathComponent("LastUpdate.json").path, version: actual.string, build: actual.build)
                let jobURL = work.appendingPathComponent("install.json")
                try JSONEncoder().encode(job).write(to: jobURL, options: .atomic)
                try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: jobURL.path)
                guard let executable = Bundle.main.executableURL else { throw UpdateError(message: "Cannot start the update installer.") }
                let helper = Process(); helper.executableURL = executable; helper.arguments = ["--install-update", jobURL.path]
                helper.standardOutput = FileHandle.nullDevice; helper.standardError = FileHandle.nullDevice
                isInstalling = true; onInstallStateChanged?(true)
                do { try helper.run() }
                catch { isInstalling = false; onInstallStateChanged?(false); throw error }
                handedOff = true; NSApp.terminate(nil)
            } catch { status("Update installation failed: %@", L(error.localizedDescription)) }
        }
    }
}
