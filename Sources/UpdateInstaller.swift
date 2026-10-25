import Foundation
import Darwin

struct UpdateInstallJob: Codable {
    let parentPID: Int32
    let currentApp: String
    let stagedApp: String
    let backupDirectory: String
    let resultFile: String
    let version: String
    let build: Int
}

enum UpdateInstaller {
    private static func preserveDevelopmentIdentity(current: URL, incoming: URL) throws {
        let signature = try run("/usr/bin/codesign", ["-dvv", current.path])
        guard let authority = signature.components(separatedBy: "\n").first(where: { $0.hasPrefix("Authority=Apple Development:") })?.dropFirst("Authority=".count) else { return }
        let identities = try run("/usr/bin/security", ["find-identity", "-v", "-p", "codesigning"])
        guard let line = identities.components(separatedBy: "\n").first(where: { $0.contains("\"" + authority + "\"") }),
              let range = line.range(of: "[A-F0-9]{40}", options: .regularExpression) else {
            throw UpdateError(message: "The local development signing identity is unavailable. The previous app was retained; use GitHub Releases for manual installation.")
        }
        // Keep this developer's existing local identity; no certificate is created or exported.
        _ = try run("/usr/bin/codesign", ["--force", "--sign", String(line[range]), "--identifier", "local.joyce.CameoStudio", incoming.path])
    }
    @discardableResult static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError(message: "Update validation or installation failed. The previous app is retained.") }
        return output
    }
    static func validateBundle(_ app: URL, minimum: AppVersion) throws -> AppVersion {
        let manager = FileManager.default
        guard app.pathExtension == "app", try app.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw UpdateError(message: "The downloaded app is invalid.") }
        let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
        guard info["CFBundleIdentifier"] as? String == "local.joyce.CameoStudio", info["CFBundleExecutable"] as? String == "TDCapture",
              let versionText = info["CFBundleShortVersionString"] as? String,
              let buildText = info["CFBundleVersion"] as? String, let build = Int(buildText),
              let version = AppVersion(versionText, build: build), version >= minimum,
              let minimumOS = info["LSMinimumSystemVersion"] as? String else { throw UpdateError(message: "The downloaded app has an unexpected identity or version.") }
        let tokens = minimumOS.split(separator: ".", omittingEmptySubsequences: false)
        guard !tokens.isEmpty, tokens.count <= 3, tokens.allSatisfy({ Int($0) != nil && Int($0)! >= 0 }) else { throw UpdateError(message: "The downloaded app is invalid.") }
        let components = tokens.map { Int($0)! }
        let os = OperatingSystemVersion(majorVersion: components[0], minorVersion: components.count > 1 ? components[1] : 0, patchVersion: components.count > 2 ? components[2] : 0)
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(os) else { throw UpdateError(message: "This update requires a newer version of macOS.") }
        let executable = app.appendingPathComponent("Contents/MacOS/TDCapture")
        guard manager.isExecutableFile(atPath: executable.path) else { throw UpdateError(message: "The downloaded app is invalid.") }
        let architectures = try run("/usr/bin/lipo", ["-archs", executable.path])
        guard architectures.split(whereSeparator: \.isWhitespace).contains("arm64") else { throw UpdateError(message: "The update does not support this Mac.") }
        _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        return version
    }
    static func install(_ job: UpdateInstallJob, waitForParent: Bool = true, launch: (URL) throws -> Void) throws {
        let manager = FileManager.default
        let current = URL(fileURLWithPath: job.currentApp), staged = URL(fileURLWithPath: job.stagedApp)
        let backup = URL(fileURLWithPath: job.backupDirectory, isDirectory: true)
        guard current.pathExtension == "app", current.standardizedFileURL != staged.standardizedFileURL,
              manager.isWritableFile(atPath: current.deletingLastPathComponent().path),
              let expected = AppVersion(job.version, build: job.build) else { throw UpdateError(message: "The app folder is not writable. Move TD Capture to a writable folder and try again.") }
        _ = try validateBundle(staged, minimum: expected)
        if waitForParent {
            let deadline = Date().addingTimeInterval(60)
            while Darwin.kill(job.parentPID, 0) == 0 {
                guard Date() < deadline else { throw UpdateError(message: "TD Capture did not quit. The update was cancelled without changing the app.") }
                Thread.sleep(forTimeInterval: 0.2)
            }
            guard errno == ESRCH else { throw UpdateError(message: "Cannot confirm that TD Capture has quit.") }
        }
        try manager.createDirectory(at: backup, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let previous = backup.appendingPathComponent("Previous.app")
        guard !manager.fileExists(atPath: previous.path), !manager.fileExists(atPath: backup.appendingPathComponent("Failed.app").path) else {
            throw UpdateError(message: "This update attempt already has a recovery copy. Please check for updates again.")
        }
        let incoming = current.deletingLastPathComponent().appendingPathComponent(".TD-Capture-incoming-" + UUID().uuidString + ".app")
        defer { try? manager.removeItem(at: incoming) }
        try manager.copyItem(at: staged, to: incoming)
        try preserveDevelopmentIdentity(current: current, incoming: incoming)
        _ = try validateBundle(incoming, minimum: expected)
        try manager.moveItem(at: current, to: previous)
        do {
            try manager.moveItem(at: incoming, to: current)
            try launch(current)
        } catch {
            // Keep the failed bundle for diagnostics and put the previous one back.
            if manager.fileExists(atPath: current.path) {
                try manager.moveItem(at: current, to: backup.appendingPathComponent("Failed.app"))
            }
            try manager.moveItem(at: previous, to: current)
            throw error
        }
    }
    static func handleJob(at path: String) -> Int32 {
        do {
            let job = try JSONDecoder().decode(UpdateInstallJob.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
            do {
                try install(job) { app in _ = try run("/usr/bin/open", ["-a", app.path]) }
                try? JSONSerialization.data(withJSONObject: ["success": true, "version": job.version, "build": job.build]).write(to: URL(fileURLWithPath: job.resultFile), options: .atomic)
                let work = URL(fileURLWithPath: path).deletingLastPathComponent()
                let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TD Capture/Updates")
                if UUID(uuidString: work.lastPathComponent) != nil, work.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL {
                    try? FileManager.default.removeItem(at: work)
                }
                return 0
            } catch {
                try? JSONSerialization.data(withJSONObject: ["success": false, "message": error.localizedDescription]).write(to: URL(fileURLWithPath: job.resultFile), options: .atomic)
                _ = try? run("/usr/bin/open", ["-a", job.currentApp])
                return 1
            }
        } catch { return 1 }
    }
}
