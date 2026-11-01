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
        #expect(model.results.map(\.content) == ["pinned", "banana", "apple"])
    }

    @Test func searchFiltersCaseInsensitivelyAndResetsSelection() {
        let (model, _) = makeModel()
        model.moveSelection(by: 2)

        model.query = "APP"

        #expect(model.results.map(\.content) == ["apple"])
        #expect(model.selectedIndex == 0)
    }

    @Test func selectionStaysInBounds() {
        let (model, _) = makeModel()
        model.moveSelection(by: -5)
        #expect(model.selectedIndex == 0)
        model.moveSelection(by: 50)
        #expect(model.selectedIndex == 2)
        #expect(model.selectedItem?.content == "apple")
    }

    @Test func selectionClampsAfterDeletingLastItem() {
        let (model, store) = makeModel()
        model.moveSelection(by: 2)

        store.remove(model.selectedItem!.id)
        model.clampSelection()

        #expect(model.selectedIndex == 1)
        #expect(model.selectedItem?.content == "banana")
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
        #expect(model.item(at: 0)?.content == "pinned")
        #expect(model.item(at: 8) == nil)
    }
}
