import Foundation
import CryptoKit

@main struct UpdateTests {
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw UpdateError(message: message) }
    }
    static func rejects(_ block: () throws -> Void, _ message: String) throws {
        do { try block() } catch { return }
        throw UpdateError(message: message)
    }
    static func main() throws {
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let root = fixtures.appendingPathComponent("run-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = URL(fileURLWithPath: CommandLine.arguments[2])
        try check(AppVersion("0.5.0", build: 8)! < AppVersion("0.5.0", build: 9)!, "Build upgrades must be detected")
        try check(AppVersion("0.5.9", build: 100)! < AppVersion("0.6.0", build: 1)!, "Version upgrades must outrank builds")
        try check(AppVersion("0.9.0")! < AppVersion("0.10.0")!, "Numeric versions must not sort lexically")
        try check(AppVersion("v0.5.0") != nil && AppVersion("0.5.0-beta") == nil, "Only stable three-part versions are supported")
        let releaseJSON: [String: Any] = ["tag_name": "v0.5.0", "name": "TD Capture 0.5.0 (build 9)", "draft": false, "prerelease": false, "assets": [["name": "TD-Capture-0.5.0-macOS-arm64.zip", "size": 100, "digest": "sha256:" + String(repeating: "a", count: 64), "browser_download_url": "https://github.com/JoyceGu/td-capture/releases/download/v0.5.0/TD-Capture-0.5.0-macOS-arm64.zip"]]]
        func release(_ object: [String: Any]) throws -> GitHubRelease { try JSONDecoder().decode(GitHubRelease.self, from: JSONSerialization.data(withJSONObject: object)) }
        try check(try release(releaseJSON).candidate().0.build == 9, "Same-version GitHub releases need their build number")
        var pre = releaseJSON; pre["prerelease"] = true
        try rejects({ _ = try release(pre).candidate() }, "Prereleases must be excluded")
        var tampered = releaseJSON
        tampered["assets"] = [["name": "TD-Capture-0.5.0-macOS-arm64.zip", "size": 100, "digest": "sha256:" + String(repeating: "a", count: 64), "browser_download_url": "https://example.com/untrusted.zip"]]
        try rejects({ _ = try release(tampered).candidate() }, "Downloads must belong to the expected repository")
        func digest(_ data: Data) -> String { "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        let good = try Data(contentsOf: fixtures.appendingPathComponent("good.zip"))
        try UpdateArchive.validate(good, digest: digest(good))
        try rejects({ try UpdateArchive.validate(good, digest: "sha256:" + String(repeating: "0", count: 64)) }, "Checksum failures must stop extraction")
        for name in ["traversal", "symlink", "local-mismatch"] {
            let data = try Data(contentsOf: fixtures.appendingPathComponent(name + ".zip"))
            try rejects({ try UpdateArchive.validate(data, digest: digest(data)) }, "Unsafe archive accepted: " + name)
        }
        if CommandLine.arguments.count > 3 {
            let realArchive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
            try UpdateArchive.validate(realArchive, digest: digest(realArchive))
        }
        let manager = FileManager.default
        func app(_ name: String, build: Int) throws -> URL {
            let app = root.appendingPathComponent(name + ".app")
            let macOS = app.appendingPathComponent("Contents/MacOS")
            try manager.createDirectory(at: macOS, withIntermediateDirectories: true)
            try manager.copyItem(at: executable, to: macOS.appendingPathComponent("TDCapture"))
            let info: [String: Any] = ["CFBundleIdentifier": "local.joyce.CameoStudio", "CFBundleExecutable": "TDCapture", "CFBundlePackageType": "APPL", "CFBundleVersion": String(build), "CFBundleShortVersionString": "0.5.0", "LSMinimumSystemVersion": "15.0"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
            _ = try UpdateInstaller.run("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
            return app
        }
        let current = try app("Current", build: 8), staged = try app("Staged", build: 9)
        try rejects({ _ = try UpdateInstaller.validateBundle(current, minimum: AppVersion("0.5.0", build: 9)!) }, "Older apps must fail validation")
        let userData = root.appendingPathComponent("user-notes.txt")
        try Data("Keep my script and settings".utf8).write(to: userData)
        let job = UpdateInstallJob(parentPID: 0, currentApp: current.path, stagedApp: staged.path, backupDirectory: root.appendingPathComponent("Backup").path, resultFile: root.appendingPathComponent("result.json").path, version: "0.5.0", build: 9)
        try UpdateInstaller.install(job, waitForParent: false) { _ in }
        try check(try UpdateInstaller.validateBundle(current, minimum: AppVersion("0.5.0", build: 9)!).build == 9, "The installed app must match the update")
        try check(manager.fileExists(atPath: root.appendingPathComponent("Backup/Previous.app").path), "The previous app must remain recoverable")
        try check(try String(contentsOf: userData, encoding: .utf8) == "Keep my script and settings", "Installation must not modify local user data")
        let rollbackApp = try app("Rollback", build: 8)
        let rollbackJob = UpdateInstallJob(parentPID: 0, currentApp: rollbackApp.path, stagedApp: staged.path, backupDirectory: root.appendingPathComponent("RollbackBackup").path, resultFile: root.appendingPathComponent("result2.json").path, version: "0.5.0", build: 9)
        try rejects({ try UpdateInstaller.install(rollbackJob, waitForParent: false) { _ in throw UpdateError(message: "Simulated launch failure") } }, "Launch failure must be reported")
        try check(try UpdateInstaller.validateBundle(rollbackApp, minimum: AppVersion("0.5.0", build: 8)!).build == 8, "Launch failure must restore the previous app")
        print("PASS: version/build ordering, release validation, checksum, safe ZIP paths, installation, app recovery and untouched user data")
    }
}
