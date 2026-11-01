import Foundation
import Testing
@testable import ClipboardManager

@MainActor
struct ClipboardStoreTests {
    private func makeStore() -> ClipboardStore {
        ClipboardStore(persistence: nil, defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    @Test func recordsNewestFirst() {
        let store = makeStore()
        store.record("a", sourceBundleID: nil)
        store.record("b", sourceBundleID: nil)
        #expect(store.items.map(\.content) == ["b", "a"])
    }

    @Test func recopyMovesExistingItemToTopKeepingIdentityAndPin() {
        let store = makeStore()
        store.record("a", sourceBundleID: "com.example.source")
        let original = store.items[0]
        store.togglePin(original.id)
        store.record("b", sourceBundleID: nil)

        store.record("a", sourceBundleID: "com.example.other")

        #expect(store.items.count == 2)
        #expect(store.items[0].id == original.id)
        #expect(store.items[0].isPinned)
        #expect(store.items[0].sourceBundleID == "com.example.source")
    }

    @Test func ignoresEmptyText() {
        let store = makeStore()
        store.record("", sourceBundleID: nil)
        #expect(store.items.isEmpty)
    }

    @Test func trimsOnlyUnpinnedItems() {
        let store = makeStore()
        store.record("pinned", sourceBundleID: nil)
        store.togglePin(store.items[0].id)

        for i in 0..<(ClipboardStore.maxUnpinnedItems + 5) {
            store.record("item \(i)", sourceBundleID: nil)
        }

        #expect(store.recentItems.count == ClipboardStore.maxUnpinnedItems)
        #expect(store.pinnedItems.map(\.content) == ["pinned"])
        // 가장 오래된 항목부터 밀려남
        #expect(store.recentItems.last?.content == "item 5")
    }

    @Test func clearUnpinnedKeepsPinned() {
        let store = makeStore()
        store.record("keep", sourceBundleID: nil)
        store.togglePin(store.items[0].id)
        store.record("drop", sourceBundleID: nil)

        store.clearUnpinned()

        #expect(store.items.map(\.content) == ["keep"])
    }

    @Test func decodesLegacyHistoryFormat() throws {
        // 1.x에서 저장한 형식: id 없음, contentType 있음
        let json = """
        [{"content":"hello","timestamp":"2026-02-03T10:00:00Z","contentType":"text","isPinned":true},
         {"content":"world","timestamp":"2026-02-03T10:01:00Z","contentType":"text"}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let items = try decoder.decode([ClipboardItem].self, from: Data(json.utf8))

        #expect(items.map(\.content) == ["hello", "world"])
        #expect(items.map(\.isPinned) == [true, false])
        #expect(items[0].id != items[1].id)
    }

    @Test func previewCollapsesWhitespace() {
        let item = ClipboardItem(content: "  first line\n\n   second\tline  ")
        #expect(item.preview == "first line second line")
        #expect(item.lineCount == 3)
    }
}
