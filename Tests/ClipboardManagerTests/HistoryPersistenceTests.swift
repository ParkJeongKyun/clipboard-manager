import CryptoKit
import Foundation
import Testing
@testable import ClipboardManager

/// 실제 Keychain 대신 쓰는 테스트용 키 저장소
final class InMemoryKeyStore: EncryptionKeyStore {
    var key: SymmetricKey?
    var shouldFail = false

    init(key: SymmetricKey? = nil) {
        self.key = key
    }

    func readKey() throws -> SymmetricKey? {
        if shouldFail { throw CocoaError(.fileReadNoPermission) }
        return key
    }

    func createKey() throws -> SymmetricKey {
        let newKey = SymmetricKey(size: .bits256)
        key = newKey
        return newKey
    }
}

@MainActor
struct HistoryPersistenceTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClipboardManagerTests-\(UUID().uuidString)")

    private func backupFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.contains("unreadable") }
    }

    @Test func savesAndLoadsEncryptedHistory() throws {
        let keyStore = InMemoryKeyStore()
        let persistence = HistoryPersistence(directory: directory, keyStore: keyStore)
        #expect(persistence.load().isEmpty)

        let items = [ClipboardItem(content: "secret", isPinned: true, sourceBundleID: "com.example")]
        persistence.saveSynchronously(items)

        // 파일에 평문이 남지 않아야 함
        let raw = try Data(contentsOf: persistence.fileURL)
        #expect(String(decoding: raw, as: UTF8.self).contains("secret") == false)

        let reloaded = try #require(HistoryPersistence(directory: directory, keyStore: keyStore).load().first)
        let original = items[0]
        #expect(reloaded.id == original.id)
        #expect(reloaded.content == original.content)
        #expect(reloaded.isPinned == original.isPinned)
        #expect(reloaded.sourceBundleID == original.sourceBundleID)
        // 밀리초 단위까지 보존 (같은 초에 복사한 항목도 순서 유지)
        #expect(abs(reloaded.timestamp.timeIntervalSince(original.timestamp)) < 0.001)
    }

    @Test func readsHistoryWrittenByVersion1() throws {
        // 1.x 형식(id 없음, contentType 있음)을 같은 방식으로 암호화한 파일
        let key = SymmetricKey(size: .bits256)
        let legacyJSON = #"[{"content":"old","timestamp":"2026-02-03T10:00:00Z","contentType":"text","isPinned":true}]"#
        let sealed = try AES.GCM.seal(Data(legacyJSON.utf8), using: key).combined!
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try sealed.write(to: directory.appendingPathComponent("clipboard_history.json"))

        let items = HistoryPersistence(directory: directory, keyStore: InMemoryKeyStore(key: key)).load()

        #expect(items.map(\.content) == ["old"])
        #expect(items.first?.isPinned == true)
    }

    @Test func keyStoreFailureNeverOverwritesExistingHistory() throws {
        let keyStore = InMemoryKeyStore()
        let writer = HistoryPersistence(directory: directory, keyStore: keyStore)
        _ = writer.load()
        writer.saveSynchronously([ClipboardItem(content: "keep me")])
        let persistence = HistoryPersistence(directory: directory, keyStore: keyStore)
        #expect(persistence.load().isEmpty == false)
        let original = try Data(contentsOf: persistence.fileURL)

        // Keychain 접근 거부 상황
        keyStore.shouldFail = true
        let denied = HistoryPersistence(directory: directory, keyStore: keyStore)
        #expect(denied.load().isEmpty)
        denied.saveSynchronously([ClipboardItem(content: "new")])

        #expect(try Data(contentsOf: denied.fileURL) == original)
        #expect(try backupFiles().isEmpty)
    }

    @Test func unreadableFileIsMovedAsideInsteadOfOverwritten() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not encrypted".utf8).write(to: directory.appendingPathComponent("clipboard_history.json"))

        let persistence = HistoryPersistence(directory: directory, keyStore: InMemoryKeyStore(key: SymmetricKey(size: .bits256)))
        #expect(persistence.load().isEmpty)

        #expect(try backupFiles().count == 1)
    }

    @Test func missingKeyMovesOldFileAside() throws {
        let first = HistoryPersistence(directory: directory, keyStore: InMemoryKeyStore())
        _ = first.load()
        first.saveSynchronously([ClipboardItem(content: "a")])

        // 키를 잃어버린 상황 (다른 빈 키 저장소)
        let second = HistoryPersistence(directory: directory, keyStore: InMemoryKeyStore())
        #expect(second.load().isEmpty)
        #expect(try backupFiles().count == 1)
    }

    @Test func storeFlushWritesPendingChanges() throws {
        let keyStore = InMemoryKeyStore()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = ClipboardStore(persistence: HistoryPersistence(directory: directory, keyStore: keyStore), defaults: defaults)

        store.record("flushed", sourceBundleID: nil)
        store.flush() // 0.5초 대기 없이 바로 저장

        let reloaded = HistoryPersistence(directory: directory, keyStore: keyStore).load()
        #expect(reloaded.map(\.content) == ["flushed"])
    }
}
