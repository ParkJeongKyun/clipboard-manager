import Foundation
import Observation

/// 클립보드 기록의 단일 저장소. 모든 화면(빠른 선택창, 메뉴바, 기록 창)이 이 객체만 바라본다.
@MainActor
@Observable
final class ClipboardStore {
    /// 고정하지 않은 항목의 최대 개수
    static let maxUnpinnedItems = 100
    /// 고정하지 않은 항목의 전체 크기 상한. 큰 텍스트가 쌓여도 메모리/저장/시작 시간이 커지지 않도록
    static let maxUnpinnedBytes = 20_000_000

    /// 항상 최신순(timestamp 내림차순)으로 유지
    private(set) var items: [ClipboardItem] = []

    var isMonitoring: Bool {
        didSet { defaults.set(isMonitoring, forKey: Self.monitoringKey) }
    }

    /// 비밀번호 관리 앱(PrivacyRules.passwordManagerBundleIDs)에서 복사한 내용을 기록하지 않을지
    var ignoresPasswordManagers: Bool {
        didSet { defaults.set(ignoresPasswordManagers, forKey: Self.ignoresPasswordManagersKey) }
    }

    /// 사용자가 추가한 기록 제외 앱 (번들 ID)
    var ignoredBundleIDs: [String] {
        didSet { defaults.set(ignoredBundleIDs, forKey: Self.ignoredAppsKey) }
    }

    var retention: HistoryRetention {
        didSet {
            defaults.set(retention.rawValue, forKey: HistoryRetention.storageKey)
            pruneExpired()
        }
    }

    @ObservationIgnored private let persistence: HistoryPersistence?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private static let monitoringKey = "isMonitoring"
    private static let ignoredAppsKey = "ignoredBundleIDs"
    private static let ignoresPasswordManagersKey = "ignoresPasswordManagers"

    init(persistence: HistoryPersistence?, defaults: UserDefaults = .standard) {
        self.persistence = persistence
        self.defaults = defaults
        isMonitoring = defaults.object(forKey: Self.monitoringKey) as? Bool ?? true
        ignoresPasswordManagers = defaults.object(forKey: Self.ignoresPasswordManagersKey) as? Bool ?? true
        ignoredBundleIDs = defaults.stringArray(forKey: Self.ignoredAppsKey) ?? []
        retention = defaults.string(forKey: HistoryRetention.storageKey).flatMap(HistoryRetention.init) ?? .forever
        items = (persistence?.load() ?? []).sorted { $0.timestamp > $1.timestamp }
        trim()
        pruneExpired()
    }

    var pinnedItems: [ClipboardItem] { items.filter(\.isPinned) }
    var recentItems: [ClipboardItem] { items.filter { !$0.isPinned } }

    /// 고정 항목 먼저, 그다음 최신순. 검색어가 있으면 내용으로 필터링
    func search(_ query: String) -> [ClipboardItem] {
        let ordered = pinnedItems + recentItems
        guard !query.isEmpty else { return ordered }
        let lowercasedQuery = query.lowercased()
        return ordered.filter { $0.matches(lowercasedQuery: lowercasedQuery) }
    }

    func item(withID id: ClipboardItem.ID) -> ClipboardItem? {
        items.first { $0.id == id }
    }

    /// 기록해도 되는 내용인지: 비어 있거나 너무 크거나, 제외된 앱에서 복사했으면 기록하지 않는다
    func shouldRecord(_ content: String, from bundleID: String?) -> Bool {
        guard !content.isEmpty, content.utf8.count <= PrivacyRules.maxItemBytes else { return false }
        guard let bundleID else { return true }
        if ignoresPasswordManagers && PrivacyRules.passwordManagerBundleIDs.contains(bundleID) { return false }
        return !ignoredBundleIDs.contains(bundleID)
    }

    /// 복사된 텍스트를 기록한다. 이미 있는 내용이면 새로 만들지 않고 맨 위로 올린다.
    func record(_ content: String, sourceBundleID: String?, at date: Date = Date()) {
        guard shouldRecord(content, from: sourceBundleID) else { return }

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
        // 여기서 trim하지 않는다: 기록이 꽉 찬 상태에서 오래된 항목의 고정을 풀면 바로 지워지기 때문.
        // 개수 제한은 다음에 새 항목을 기록할 때 적용된다.
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

    /// 보관 기간이 지난 고정되지 않은 항목을 지운다
    func pruneExpired(now: Date = Date()) {
        guard let interval = retention.interval else { return }
        let cutoff = now.addingTimeInterval(-interval)
        let countBefore = items.count
        items.removeAll { !$0.isPinned && $0.timestamp < cutoff }
        if items.count != countBefore { scheduleSave() }
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

    /// 고정하지 않은 항목을 최신순으로 개수/전체 크기 한도까지만 남긴다
    private func trim() {
        var unpinnedCount = 0
        var unpinnedBytes = 0
        items = items.filter { item in
            if item.isPinned { return true }
            unpinnedCount += 1
            unpinnedBytes += item.content.utf8.count
            return unpinnedCount <= Self.maxUnpinnedItems && unpinnedBytes <= Self.maxUnpinnedBytes
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
