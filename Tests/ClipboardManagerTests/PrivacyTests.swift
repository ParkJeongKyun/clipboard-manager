import CryptoKit
import Foundation
import Testing
@testable import ClipboardManager

@MainActor
struct PrivacyTests {
    private func makeStore() -> ClipboardStore {
        ClipboardStore(persistence: nil, defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    @Test(arguments: Array(PrivacyRules.passwordManagerBundleIDs))
    func ignoresPasswordManagersByDefault(bundleID: String) {
        let store = makeStore()
        #expect(store.ignoresPasswordManagers)
        store.record("hunter2", sourceBundleID: bundleID)
        #expect(store.items.isEmpty)
    }

    @Test func recordsFromPasswordManagersWhenUserAllows() {
        let store = makeStore()
        store.ignoresPasswordManagers = false
        store.record("user@example.com", sourceBundleID: "com.1password.1password")
        #expect(store.items.map(\.content) == ["user@example.com"])
    }

    @Test func neverRecordsFromUserIgnoredApps() {
        let store = makeStore()
        store.ignoredBundleIDs = ["com.example.bank"]

        store.record("account 123-456", sourceBundleID: "com.example.bank")
        store.record("hello", sourceBundleID: "com.apple.Notes")

        #expect(store.items.map(\.content) == ["hello"])
    }

    @Test func skipsOversizedText() {
        let store = makeStore()
        store.record(String(repeating: "a", count: PrivacyRules.maxItemBytes + 1), sourceBundleID: nil)
        store.record(String(repeating: "a", count: PrivacyRules.maxItemBytes), sourceBundleID: nil)
        #expect(store.items.count == 1)
    }

    @Test func retentionRemovesOldUnpinnedItemsOnly() {
        let store = makeStore()
        let now = Date()
        store.record("old pinned", sourceBundleID: nil, at: now.addingTimeInterval(-3 * 86_400))
        store.togglePin(store.items[0].id)
        store.record("old", sourceBundleID: nil, at: now.addingTimeInterval(-2 * 86_400))
        store.record("new", sourceBundleID: nil, at: now.addingTimeInterval(-60))

        store.retention = .day

        #expect(store.items.map(\.content).sorted() == ["new", "old pinned"])
    }

    @Test func retentionForeverKeepsEverything() {
        let store = makeStore()
        store.record("ancient", sourceBundleID: nil, at: Date().addingTimeInterval(-365 * 86_400))
        store.pruneExpired()
        #expect(store.items.count == 1)
    }

    @Test func historyFileIsOwnerOnly() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardManagerTests-\(UUID().uuidString)")
        let persistence = HistoryPersistence(directory: directory, keyStore: InMemoryKeyStore())
        _ = persistence.load()
        persistence.saveSynchronously([ClipboardItem(content: "secret")])

        let fileMode = try FileManager.default.attributesOfItem(atPath: persistence.fileURL.path)[.posixPermissions] as? Int
        let directoryMode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int
        #expect(fileMode == 0o600)
        #expect(directoryMode == 0o700)
    }

    @Test(arguments: [
        ("https://github.com/ParkJeongKyun/clipboard-manager/releases/download/v0.3.0/ClipboardManager.zip", true),
        ("http://github.com/ParkJeongKyun/clipboard-manager/releases/download/v0.3.0/ClipboardManager.zip", false),
        ("https://github.com/attacker/clipboard-manager/releases/download/v0.3.0/ClipboardManager.zip", false),
        ("https://github.com.evil.example/ParkJeongKyun/clipboard-manager/releases/download/v0.3.0/ClipboardManager.zip", false),
        ("https://github.com/ParkJeongKyun/clipboard-manager/releases/download/../../../attacker/repo/releases/download/v1/ClipboardManager.zip", false),
        ("https://example.com/ParkJeongKyun/clipboard-manager/releases/download/v0.3.0/ClipboardManager.zip", false)
    ])
    func onlyDownloadsFromThisRepository(url: String, expected: Bool) throws {
        #expect(UpdateInstaller.isTrustedDownloadURL(try #require(URL(string: url))) == expected)
    }
}
