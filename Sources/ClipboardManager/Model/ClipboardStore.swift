import Foundation
import Observation

/// 클립보드 기록의 단일 저장소. 모든 화면(빠른 선택창, 메뉴바, 기록 창)이 이 객체만 바라본다.
@MainActor
@Observable
final class ClipboardStore {
    /// 고정하지 않은 항목의 최대 개수
    static let maxUnpinnedItems = 100

    /// 항상 최신순(timestamp 내림차순)으로 유지
    private(set) var items: [ClipboardItem] = []

    var isMonitoring: Bool {
        didSet { defaults.set(isMonitoring, forKey: Self.monitoringKey) }
    }

    @ObservationIgnored private let persistence: HistoryPersistence?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private static let monitoringKey = "isMonitoring"

    init(persistence: HistoryPersistence?, defaults: UserDefaults = .standard) {
        self.persistence = persistence
        self.defaults = defaults
        isMonitoring = defaults.object(forKey: Self.monitoringKey) as? Bool ?? true
        items = (persistence?.load() ?? []).sorted { $0.timestamp > $1.timestamp }
        trim()
    }

    var pinnedItems: [ClipboardItem] { items.filter(\.isPinned) }
    var recentItems: [ClipboardItem] { items.filter { !$0.isPinned } }

    /// 고정 항목 먼저, 그다음 최신순. 검색어가 있으면 내용으로 필터링
    func search(_ query: String) -> [ClipboardItem] {
        let ordered = pinnedItems + recentItems
        guard !query.isEmpty else { return ordered }
        return ordered.filter { $0.content.localizedCaseInsensitiveContains(query) }
    }

    func item(withID id: ClipboardItem.ID) -> ClipboardItem? {
        items.first { $0.id == id }
    }

    /// 복사된 텍스트를 기록한다. 이미 있는 내용이면 새로 만들지 않고 맨 위로 올린다.
    func record(_ content: String, sourceBundleID: String?, at date: Date = Date()) {
        guard !content.isEmpty else { return }

        if let index = items.firstIndex(where: { $0.content == content }) {
            var item = items.remove(at: index)
            item.timestamp = date
            items.insert(item, at: 0)
        } else {
            items.insert(ClipboardItem(content: content, timestamp: date, sourceBundleID: sourceBundleID), at: 0)
            trim()
        }
        scheduleSave()
    }

    func togglePin(_ id: ClipboardItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
        trim()
        scheduleSave()
    }

    func remove(_ id: ClipboardItem.ID) {
        items.removeAll { $0.id == id }
        scheduleSave()
    }

    /// 고정 항목을 제외하고 모두 삭제
    func clearUnpinned() {
        items.removeAll { !$0.isPinned }
        scheduleSave()
    }

    /// 앱 종료 시 대기 중이거나 진행 중인 저장을 끝낸다
    func flush() {
        if let saveTask {
            saveTask.cancel()
            self.saveTask = nil
            persistence?.saveSynchronously(items)
        } else {
            persistence?.waitForPendingWrites()
        }
    }

    private func trim() {
        var unpinnedCount = 0
        items = items.filter { item in
            if item.isPinned { return true }
            unpinnedCount += 1
            return unpinnedCount <= Self.maxUnpinnedItems
        }
    }

    /// 연속 복사 시 매번 전체를 암호화하지 않도록 0.5초 모아서 저장
    private func scheduleSave() {
        guard persistence != nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            self.saveTask = nil
            self.persistence?.save(self.items)
        }
    }
}
