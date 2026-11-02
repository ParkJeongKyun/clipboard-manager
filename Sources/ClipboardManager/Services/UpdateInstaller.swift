import CryptoKit
import Foundation

/// "v1.2.3", "1.2" 같은 버전 문자열. 1.2와 1.2.0은 같은 버전으로 본다.
struct AppVersion: Comparable, CustomStringConvertible {
    let components: [Int]

    init?(_ string: String) {
        let numbers = string.trimmingPrefix("v").split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        // "1.0.0-beta" 같은 형식은 지원하지 않음 (GitHub의 latest는 정식 릴리즈만 돌려준다)
        guard !numbers.isEmpty, !numbers.contains(nil) else { return nil }
        components = numbers.compactMap { $0 }
    }

    /// 실행 중인 앱의 버전 (번들 밖에서 실행하면 nil)
    static var current: AppVersion? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

/// GitHub 릴리즈 API 응답 중 필요한 필드
struct GitHubRelease: Decodable, Equatable {
    struct Asset: Decodable, Equatable {
        let name: String
        let downloadURL: URL

        private enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let pageURL: URL
    let assets: [Asset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case pageURL = "html_url"
        case assets
    }

    var version: AppVersion? { AppVersion(tagName) }

    func asset(named name: String) -> Asset? {
        assets.first { $0.name == name }
    }
}

enum UpdateError: LocalizedError {
    case badResponse(Int)
    case missingAsset
    case checksumMismatch
    case invalidApp
    case notWritable
    case untrustedURL

    var errorDescription: String? {
        switch self {
        case .badResponse(let status): String(localized: "The server responded with an error (\(status)).")
        case .missingAsset: String(localized: "The release is missing the update file.")
        case .checksumMismatch: String(localized: "The downloaded file is corrupted.")
        case .invalidApp: String(localized: "The downloaded app is not valid.")
        case .notWritable: String(localized: "Can't update the app in its current location. Move it to the Applications folder first.")
        case .untrustedURL: String(localized: "The update file is not hosted on GitHub.")
        }
    }
}

/// 릴리즈를 확인하고, 새 버전을 받아 검증한 뒤 현재 앱을 교체한다. (install.sh와 같은 절차)
enum UpdateInstaller {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/ParkJeongKyun/clipboard-manager/releases/latest")!
    // Scripts/bundle.sh --dist가 만드는 파일 이름 (버전 번호 없음)
    static let archiveName = "ClipboardManager.zip"
    static let checksumsName = "SHA256SUMS"
    private static let appName = "ClipboardManager.app"

    static func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        return try JSONDecoder().decode(GitHubRelease.self, from: try await download(request))
    }

    /// 교체가 끝나면 앱 위치를 돌려준다 (그 위치에서 재시작하면 됨)
    static func install(_ release: GitHubRelease, replacing appURL: URL = Bundle.main.bundleURL) async throws -> URL {
        guard let archive = release.asset(named: archiveName),
              let checksums = release.asset(named: checksumsName) else { throw UpdateError.missingAsset }
        // 이 저장소의 GitHub 릴리즈 파일만 받는다 (HTTPS, github.com의 저장소 경로)
        guard isTrustedDownloadURL(archive.downloadURL), isTrustedDownloadURL(checksums.downloadURL) else {
            throw UpdateError.untrustedURL
        }
        // 임시 실행 경로(App Translocation)나 쓰기 권한 없는 위치는 교체할 수 없다
        guard !appURL.path.contains("/AppTranslocation/"),
              FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path) else {
            throw UpdateError.notWritable
        }

        let archiveData = try await download(URLRequest(url: archive.downloadURL))
        let checksumsText = String(decoding: try await download(URLRequest(url: checksums.downloadURL)), as: UTF8.self)
        guard let expected = expectedChecksum(in: checksumsText, for: archiveName),
              sha256Hex(of: archiveData) == expected else { throw UpdateError.checksumMismatch }

        // 교체(replaceItemAt)가 같은 볼륨에서 이뤄지도록 앱과 같은 볼륨의 임시 폴더 사용
        let workDirectory = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: appURL, create: true
        )
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        let archiveURL = workDirectory.appendingPathComponent(archiveName)
        try archiveData.write(to: archiveURL)
        try await run("/usr/bin/ditto", ["-x", "-k", archiveURL.path, workDirectory.path], failure: .checksumMismatch)

        let newAppURL = workDirectory.appendingPathComponent(appName)
        // 압축 안에 앱 대신 다른 위치를 가리키는 링크가 들어 있으면 거부
        guard (try? newAppURL.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == false else {
            throw UpdateError.invalidApp
        }
        try await verify(newAppURL, expectedVersion: release.version)

        return try FileManager.default.replaceItemAt(appURL, withItemAt: newAppURL) ?? appURL
    }

    static func isTrustedDownloadURL(_ url: URL) -> Bool {
        url.scheme == "https"
            && url.host() == "github.com"
            && url.path().hasPrefix("/ParkJeongKyun/clipboard-manager/releases/download/")
            // "../"로 다른 저장소 경로를 가리키는 경우 차단
            && !url.pathComponents.contains("..")
    }

    /// SHA256SUMS(`shasum -a 256` 출력)에서 파일의 체크섬을 찾는다
    static func expectedChecksum(in checksums: String, for fileName: String) -> String? {
        checksums.split(whereSeparator: \.isNewline)
            .map { $0.split(separator: " ") }
            .first { $0.count == 2 && $0[1] == fileName }
            .map { $0[0].lowercased() }
    }

    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// 서명이 온전하고, 같은 앱(번들 ID)이며, 릴리즈 태그와 버전이 일치하는지
    private static func verify(_ appURL: URL, expectedVersion: AppVersion?) async throws {
        try await run("/usr/bin/codesign", ["--verify", "--strict", appURL.path], failure: .invalidApp)
        guard let bundle = Bundle(url: appURL),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init),
              let expectedVersion, version == expectedVersion else {
            throw UpdateError.invalidApp
        }
    }

    private static func download(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError.badResponse(status) }
        return data
    }

    private static func run(_ tool: String, _ arguments: [String], failure: UpdateError) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: failure)
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
