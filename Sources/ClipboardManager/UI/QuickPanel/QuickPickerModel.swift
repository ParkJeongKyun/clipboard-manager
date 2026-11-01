import Foundation
import Observation

/// 빠른 선택창의 검색어와 선택 상태
@MainActor
@Observable
final class QuickPickerModel {
    private let store: ClipboardStore

    var query = "" {
        didSet { selectedIndex = 0 }
    }
    private(set) var selectedIndex = 0
    /// 창을 다시 열 때마다 바뀌어 검색창에 포커스를 준다
    private(set) var focusRequest = 0

    init(store: ClipboardStore) {
        self.store = store
    }

    var results: [ClipboardItem] {
        store.search(query)
    }

    var selectedItem: ClipboardItem? {
        item(at: selectedIndex)
    }

    func item(at index: Int) -> ClipboardItem? {
        let results = results
        return results.indices.contains(index) ? results[index] : nil
    }

    func reset() {
        query = ""
        selectedIndex = 0
        focusRequest += 1
    }

    func moveSelection(by offset: Int) {
        let count = results.count
        guard count > 0 else { return }
        selectedIndex = min(max(selectedIndex + offset, 0), count - 1)
    }

    /// 선택 항목이 삭제되거나 목록이 줄었을 때 범위 안으로
    func clampSelection() {
        selectedIndex = min(selectedIndex, max(results.count - 1, 0))
    }
}
