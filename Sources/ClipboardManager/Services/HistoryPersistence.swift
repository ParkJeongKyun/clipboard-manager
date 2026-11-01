import CryptoKit
import Foundation
import Security

/// 히스토리를 AES-GCM으로 암호화해 Application Support에 저장한다.
///
/// 키나 파일을 읽지 못했을 때 기존 기록을 덮어쓰지 않는 것이 최우선이다.
/// - 키 저장소 접근 실패(접근 거부, 잠김 등): 이번 실행 동안 저장하지 않음
/// - 키가 없거나 복호화 실패: 기존 파일을 `.unreadable-*` 로 옮겨 두고 새로 시작
final class HistoryPersistence: @unchecked Sendable {
    let fileURL: URL
    private let keyStore: EncryptionKeyStore
    private let queue = DispatchQueue(label: "com.kyun.clipboard-manager.persistence", qos: .utility)

    // load() 이후에는 queue에서만 접근
    private var key: SymmetricKey?

    init(directory: URL? = nil, keyStore: EncryptionKeyStore = KeychainKeyStore()) {
        let directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipboardManager")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("clipboard_history.json")
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
            return try Self.decoder.decode([ClipboardItem].self, from: json)
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
            let json = try Self.encoder.encode(items)
            guard let encrypted = try AES.GCM.seal(json, using: key).combined else { return }
            try encrypted.write(to: fileURL, options: .atomic)
        } catch {
            Log.storage.error("기록 저장 실패: \(error.localizedDescription)")
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
    private static let decoder: JSONDecoder = {
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
    }()
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
