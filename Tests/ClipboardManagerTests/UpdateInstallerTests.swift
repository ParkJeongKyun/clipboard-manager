import Foundation
import Testing
@testable import ClipboardManager

struct AppVersionTests {
    @Test(arguments: [
        ("v0.2.0", "0.1.0", true),
        ("0.10.0", "0.9.0", true),   // 문자열 비교가 아니라 숫자 비교
        ("1.0", "0.99.99", true),
        ("0.1.1", "0.1.0", true),
        ("0.1.0", "0.1.0", false),
        ("0.1", "0.1.0", false),     // 1.2 == 1.2.0
        ("0.0.9", "0.1.0", false)
    ])
    func isNewer(candidate: String, current: String, expected: Bool) throws {
        let candidateVersion = try #require(AppVersion(candidate))
        let currentVersion = try #require(AppVersion(current))
        #expect((candidateVersion > currentVersion) == expected)
    }

    @Test func treatsMissingComponentsAsZero() {
        #expect(AppVersion("1.2") == AppVersion("1.2.0"))
    }

    @Test(arguments: ["", "v", "1.0.0-beta", "latest", "1..2"])
    func rejectsUnsupportedFormats(_ string: String) {
        #expect(AppVersion(string) == nil)
    }
}

struct UpdateInstallerTests {
    @Test func decodesGitHubReleaseResponse() throws {
        // GitHub API 응답에서 필요한 필드만 발췌 (나머지 필드는 무시되어야 함)
        let json = """
        {
          "tag_name": "v0.2.0",
          "html_url": "https://github.com/ParkJeongKyun/clipboard-manager/releases/tag/v0.2.0",
          "draft": false,
          "assets": [
            {"name": "ClipboardManager.zip", "size": 1000,
             "browser_download_url": "https://github.com/ParkJeongKyun/clipboard-manager/releases/download/v0.2.0/ClipboardManager.zip"},
            {"name": "SHA256SUMS",
             "browser_download_url": "https://github.com/ParkJeongKyun/clipboard-manager/releases/download/v0.2.0/SHA256SUMS"}
          ]
        }
        """
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))

        #expect(release.version == AppVersion("0.2.0"))
        #expect(release.asset(named: UpdateInstaller.archiveName)?.downloadURL.lastPathComponent == "ClipboardManager.zip")
        #expect(release.asset(named: UpdateInstaller.checksumsName) != nil)
        #expect(release.asset(named: "ClipboardManager.dmg") == nil)
    }

    @Test func findsChecksumInShasumOutput() {
        // Scripts/bundle.sh가 만드는 형식 (shasum -a 256: 해시 + 공백 2칸 + 파일 이름)
        let sums = """
        716DD802B9DAFD8DC417487C6054294A5F048638163B2A4A2904006F4B505DC3  ClipboardManager.zip
        83bf700fd61b59a74056cc0905b5578a29784b1239a39226ef39e5d78b126639  ClipboardManager.dmg
        """
        #expect(UpdateInstaller.expectedChecksum(in: sums, for: "ClipboardManager.zip")
            == "716dd802b9dafd8dc417487c6054294a5f048638163b2a4a2904006f4b505dc3")
        #expect(UpdateInstaller.expectedChecksum(in: sums, for: "ClipboardManager.dmg")?.hasPrefix("83bf") == true)
        #expect(UpdateInstaller.expectedChecksum(in: sums, for: "Other.zip") == nil)
        // 이름 일부만 일치하면 안 됨
        #expect(UpdateInstaller.expectedChecksum(in: sums, for: "Manager.zip") == nil)
    }

    @Test func computesSHA256LikeShasum() {
        // NIST 테스트 벡터: SHA256("abc")
        #expect(UpdateInstaller.sha256Hex(of: Data("abc".utf8))
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
