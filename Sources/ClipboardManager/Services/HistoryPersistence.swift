import CryptoKit
import Foundation
import Security

/// 히스토리를 AES-GCM으로 암호화해 Application Support에 저장한다.
/// 고정한 이미지는 크기가 커서 images/ 아래에 이미지마다 따로 암호화해 두고, 새 이미지가 생길 때만 쓴다.
///
/// 키나 파일을 읽지 못했을 때 기존 기록을 덮어쓰지 않는 것이 최우선이다.
/// - 키 저장소 접근 실패(접근 거부, 잠김 등): 이번 실행 동안 저장하지 않음
/// - 키가 없거나 복호화 실패: 기존 파일을 `.unreadable-*` 로 옮겨 두고 새로 시작
final class HistoryPersistence: @unchecked Sendable {
    let fileURL: URL
    let imageDirectory: URL
    private let keyStore: EncryptionKeyStore
    private let queue = DispatchQueue(label: "com.kyun.clipboard-manager.persistence", qos: .utility)

    // load() 이후에는 queue에서만 접근
    private var key: SymmetricKey?

    init(directory: URL? = nil, keyStore: EncryptionKeyStore = KeychainKeyStore()) {
        let directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipboardManager")
        // 기록 폴더/파일은 본인만 접근 가능하게 (내용은 암호화되어 있지만 이중으로 보호)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        fileURL = directory.appendingPathComponent("clipboard_history.json")
        imageDirectory = directory.appendingPathComponent("images")
        self.keyStore = keyStore
    }

    /// 앱 시작 시 한 번 호출
    func load() -> [ClipboardItem] {
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)

        do {
            if let existingKey = try keyStore.readKey() {
                key = existingKey
            } else {
                if fileExists { moveAsideUnreadableFile(reason: "암호화 키 없음") }
                key = try keyStore.createKey()
                return []
            }
        } catch {
            Log.storage.error("키 저장소 접근 실패, 이번 실행에서는 기록을 저장하지 않음: \(error.localizedDescription)")
            return []
        }

        guard fileExists, let key else { return [] }

        do {
            let encrypted = try Data(contentsOf: fileURL)
            let json = try AES.GCM.open(AES.GCM.SealedBox(combined: encrypted), using: key)
            let decoder = Self.makeDecoder()
            decoder.userInfo[ClipboardImage.loaderKey] = { [self] (digest: String) in try readImage(digest: digest, key: key) } as ClipboardImage.Loader
            // 이미지 파일이 없어지는 등 일부 항목을 읽지 못해도 나머지 기록은 살린다
            return try decoder.decode([LossyItem].self, from: json).compactMap(\.item)
        } catch {
            moveAsideUnreadableFile(reason: "복호화/디코딩 실패: \(error.localizedDescription)")
            return []
        }
    }

    /// 백그라운드에서 저장
    func save(_ items: [ClipboardItem]) {
        queue.async { self.write(items) }
    }

    /// 종료 직전처럼 저장이 끝날 때까지 기다려야 할 때
    func saveSynchronously(_ items: [ClipboardItem]) {
        queue.sync { self.write(items) }
    }

    /// 진행 중인 백그라운드 저장이 끝날 때까지 대기
    func waitForPendingWrites() {
        queue.sync {}
    }

    private func write(_ items: [ClipboardItem]) {
        guard let key else { return }
        do {
            // 이미지를 먼저 써야 기록 파일이 없는 이미지를 가리키는 순간이 생기지 않는다
            let images = items.compactMap(\.image)
            try writeImages(images, key: key)
            let json = try Self.encoder.encode(items)
            guard let encrypted = try AES.GCM.seal(json, using: key).combined else { return }
            try encrypted.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            removeImages(except: Set(images.map(\.digest)))
        } catch {
            Log.storage.error("기록 저장 실패: \(error.localizedDescription)")
        }
    }

    // MARK: - 이미지 파일

    private func imageURL(digest: String) throws -> URL {
        // 파일 이름으로 쓰므로 16진수만 허용 (경로 조작 방지)
        guard !digest.isEmpty, digest.allSatisfy(\.isHexDigit) else { throw CocoaError(.fileReadInvalidFileName) }
        return imageDirectory.appendingPathComponent(digest)
    }

    /// 아직 없는 이미지만 쓴다. 파일 이름이 내용의 해시라서 이미 있으면 내용도 같다
    private func writeImages(_ images: [ClipboardImage], key: SymmetricKey) throws {
        guard !images.isEmpty else { return }
        try FileManager.default.createDirectory(
            at: imageDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        for image in images {
            let url = try imageURL(digest: image.digest)
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            guard let encrypted = try AES.GCM.seal(image.pngData, using: key).combined else { continue }
            try encrypted.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    private func readImage(digest: String, key: SymmetricKey) throws -> Data {
        let encrypted = try Data(contentsOf: try imageURL(digest: digest))
        return try AES.GCM.open(AES.GCM.SealedBox(combined: encrypted), using: key)
    }

    /// 고정을 풀었거나 지운 이미지 파일 정리
    private func removeImages(except digests: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(at: imageDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where !digests.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func moveAsideUnreadableFile(reason: String) {
        let stamp = Int(Date().timeIntervalSince1970)
        let backupURL = fileURL.deletingPathExtension()
            .appendingPathExtension("unreadable-\(stamp).json")
        try? FileManager.default.moveItem(at: fileURL, to: backupURL)
        Log.storage.error("기존 기록을 읽을 수 없어 \(backupURL.lastPathComponent)로 옮김 (\(reason))")
    }

    // 같은 초에 복사한 항목의 순서가 재시작 후 바뀌지 않도록 소수점 초까지 저장
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date))
        }
        return encoder
    }()

    // 1.x는 소수점 없이 저장했으므로 두 형식 모두 읽는다
    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            if let date = (try? withFraction.parse(string)) ?? (try? Date.ISO8601FormatStyle().parse(string)) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "날짜 형식 오류: \(string)")
        }
        return decoder
    }

    /// 읽지 못한 항목은 nil로 남겨 건너뛴다
    private struct LossyItem: Decodable {
        let item: ClipboardItem?

        init(from decoder: Decoder) throws {
            do {
                item = try ClipboardItem(from: decoder)
            } catch {
                Log.storage.error("기록 항목을 읽지 못해 건너뜀: \(error.localizedDescription)")
                item = nil
            }
        }
    }
}

// MARK: - 암호화 키 저장소

protocol EncryptionKeyStore {
    /// 저장된 키. 없으면 nil, 접근에 실패하면 throw
    func readKey() throws -> SymmetricKey?
    func createKey() throws -> SymmetricKey
}

struct KeychainKeyStore: EncryptionKeyStore {
    var service = "ClipboardManager"
    var account = "MasterKey"

    func readKey() throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return (result as? Data).map { SymmetricKey(data: $0) }
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    func createKey() throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key.withUnsafeBytes { Data($0) },
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return key
    }

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
        }
    }
}
