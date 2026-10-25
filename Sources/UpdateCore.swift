import Foundation
import CryptoKit

struct UpdateError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct AppVersion: Comparable, Equatable {
    let parts: [Int]
    let build: Int
    init?(_ text: String, build: Int = 0) {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let tokens = value.split(separator: ".", omittingEmptySubsequences: false)
        guard tokens.count == 3, tokens.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              tokens.allSatisfy({ Int($0) != nil }), build >= 0 else { return nil }
        parts = tokens.map { Int($0)! }; self.build = build
    }
    var string: String { parts.map(String.init).joined(separator: ".") }
    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.parts != rhs.parts { return lhs.parts.lexicographicallyPrecedes(rhs.parts) }
        return lhs.build < rhs.build
    }
}

struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browser_download_url: String
        let size: Int
        let digest: String?
    }
    let tag_name: String
    let name: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
    var version: AppVersion? {
        let title = name ?? ""
        let expression = try! NSRegularExpression(pattern: "build\\s+(\\d+)", options: .caseInsensitive)
        let match = expression.firstMatch(in: title, range: NSRange(title.startIndex..., in: title))
        let build = match.flatMap { Range($0.range(at: 1), in: title) }.flatMap { Int(title[$0]) } ?? 0
        return AppVersion(tag_name, build: build)
    }
    func candidate() throws -> (AppVersion, Asset) {
        guard !draft, !prerelease, let version else { throw UpdateError(message: "No compatible stable release was found.") }
        let expected = "TD-Capture-\(version.string)-macOS-arm64.zip"
        guard let asset = assets.first(where: { $0.name == expected }), asset.size > 0, asset.size <= UpdateArchive.maximumBytes,
              asset.browser_download_url == "https://github.com/JoyceGu/td-capture/releases/download/\(tag_name)/\(expected)",
              let digest = asset.digest, digest.hasPrefix("sha256:"), digest.dropFirst(7).count == 64,
              digest.dropFirst(7).allSatisfy({ $0.isHexDigit }) else {
            throw UpdateError(message: "The release has no verified Apple Silicon installer. Open GitHub Releases for a manual download.")
        }
        return (version, asset)
    }
}

enum UpdateArchive {
    static let maximumBytes = 200 * 1024 * 1024
    static func validate(_ data: Data, digest: String) throws {
        let actual = "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == digest.lowercased() else { throw UpdateError(message: "The download checksum does not match. The app was not changed.") }
        guard data.count <= maximumBytes, data.count >= 22 else { throw UpdateError(message: "The update archive is invalid.") }
        func number(_ offset: Int, _ bytes: Int) -> Int {
            guard offset >= 0, offset + bytes <= data.count else { return -1 }
            return (0..<bytes).reduce(0) { $0 | (Int(data[offset + $1]) << ($1 * 8)) }
        }
        let end = stride(from: data.count - 22, through: max(0, data.count - 65_557), by: -1).first {
            number($0, 4) == 0x06054b50 && $0 + 22 + number($0 + 20, 2) == data.count
        }
        guard let end, number(end + 4, 2) == 0, number(end + 6, 2) == 0,
              number(end + 8, 2) == number(end + 10, 2) else { throw UpdateError(message: "The update archive is invalid.") }
        let count = number(end + 10, 2), length = number(end + 12, 4), offset = number(end + 16, 4)
        guard count > 0, count < 10_000, offset >= 0, length > 0, offset + length == end else { throw UpdateError(message: "The update archive is invalid.") }
        var cursor = offset; var expanded = 0
        for _ in 0..<count {
            guard cursor + 46 <= end, number(cursor, 4) == 0x02014b50 else { throw UpdateError(message: "The update archive is invalid.") }
            let nameLength = number(cursor + 28, 2)
            let next = cursor + 46 + nameLength + number(cursor + 30, 2) + number(cursor + 32, 2)
            guard next <= end, let name = String(data: data[(cursor + 46)..<(cursor + 46 + nameLength)], encoding: .utf8) else { throw UpdateError(message: "The update archive is invalid.") }
            let components = name.split(separator: "/", omittingEmptySubsequences: true)
            let mode = (number(cursor + 38, 4) >> 16) & 0xf000
            let local = number(cursor + 42, 4)
            let localNameLength = number(local + 26, 2)
            let localExtraLength = number(local + 28, 2)
            guard local >= 0, local + 30 <= offset, number(local, 4) == 0x04034b50,
                  localNameLength == nameLength, localExtraLength >= 0,
                  local + 30 + localNameLength + localExtraLength + number(cursor + 20, 4) <= offset,
                  number(local + 6, 2) == number(cursor + 8, 2), number(local + 8, 2) == number(cursor + 10, 2),
                  data[(local + 30)..<(local + 30 + localNameLength)] == data[(cursor + 46)..<(cursor + 46 + nameLength)] else {
                throw UpdateError(message: "The update archive is invalid.")
            }
            expanded += number(cursor + 24, 4)
            guard !name.hasPrefix("/"), !name.contains("\\"), !name.contains("\0"), !components.contains(".."), !components.contains("."),
                  components.first == "TD Capture.app" || components.first == "__MACOSX",
                  mode == 0 || mode == 0x8000 || mode == 0x4000,
                  number(cursor + 8, 2) & 1 == 0, [0, 8].contains(number(cursor + 10, 2)), expanded <= 500 * 1024 * 1024 else {
                throw UpdateError(message: "The update archive contains unsafe paths or unsupported files.")
            }
            cursor = next
        }
        guard cursor == end else { throw UpdateError(message: "The update archive is invalid.") }
    }
}
