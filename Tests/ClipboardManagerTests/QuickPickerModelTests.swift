import Foundation
import Testing
@testable import ClipboardManager

@MainActor
struct QuickPickerModelTests {
    /// "pinned"(고정), "banana", "apple" 순으로 들어간 store
    private func makeModel() -> (QuickPickerModel, ClipboardStore) {
        let store = ClipboardStore(persistence: nil, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.record("pinned", sourceBundleID: nil)
        store.togglePin(store.items[0].id)
        store.record("apple", sourceBundleID: nil)
        store.record("banana", sourceBundleID: nil)
        return (QuickPickerModel(store: store), store)
    }

    @Test func pinnedItemsComeFirst() {
        let (model, _) = makeModel()
        #expect(model.results.map(\.text) == ["pinned", "banana", "apple"])
    }

    /// 먼저 고정한 항목이 ⌘1. 고정한 항목을 다시 복사해도 고정 순서는 그대로
    @Test func pinnedItemsKeepPinOrder() {
        let (model, store) = makeModel()
        store.togglePin(try! #require(store.items.first { $0.text == "apple" }).id)
        store.togglePin(try! #require(store.items.first { $0.text == "banana" }).id)
        #expect(model.results.map(\.text) == ["pinned", "apple", "banana"])

        store.record("pinned", sourceBundleID: nil)
        #expect(model.results.map(\.text) == ["pinned", "apple", "banana"])

        // 고정을 풀었다가 다시 고정하면 맨 뒤로
        let pinnedID = try! #require(store.items.first { $0.text == "pinned" }).id
        store.togglePin(pinnedID)
        store.togglePin(pinnedID)
        #expect(model.results.map(\.text) == ["apple", "banana", "pinned"])
    }

    @Test func searchFiltersCaseInsensitivelyAndResetsSelection() {
        let (model, _) = makeModel()
        model.moveSelection(by: 2)

        model.query = "APP"

        #expect(model.results.map(\.text) == ["apple"])
        #expect(model.selectedIndex == 0)
    }

    @Test func selectionStaysInBounds() {
        let (model, _) = makeModel()
        model.moveSelection(by: -5)
        #expect(model.selectedIndex == 0)
        model.moveSelection(by: 50)
        #expect(model.selectedIndex == 2)
        #expect(model.selectedItem?.text == "apple")
    }

    @Test func selectionClampsAfterDeletingLastItem() {
        let (model, store) = makeModel()
        model.moveSelection(by: 2)

        store.remove(model.selectedItem!.id)
        model.clampSelection()

        #expect(model.selectedIndex == 1)
        #expect(model.selectedItem?.text == "banana")
    }

    @Test func resetClearsQueryAndSelection() {
        let (model, _) = makeModel()
        model.query = "a"
        model.moveSelection(by: 1)
        let focusRequest = model.focusRequest

        model.reset()

        #expect(model.query.isEmpty)
        #expect(model.selectedIndex == 0)
        #expect(model.focusRequest == focusRequest + 1)
    }

    @Test func itemAtIndexReturnsNilOutOfRange() {
        let (model, _) = makeModel()
        #expect(model.item(at: 0)?.text == "pinned")
        #expect(model.item(at: 8) == nil)
    }
}
