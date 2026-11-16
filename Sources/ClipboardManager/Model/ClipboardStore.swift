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
    /// 고정하지 않은 이미지의 최대 개수 (Windows 클립보드 기록과 같은 25개).
    /// 고정하지 않은 이미지는 디스크에 저장하지 않으므로 앱을 종료하면 사라진다.
    static let maxUnpinnedImages = 25

    /// 항상 최신순(timestamp 내림차순)으로 유지
    private(set) var items: [ClipboardItem] = []

    var isMonitoring: Bool {
        didSet { defaults.set(isMonitoring, forKey: Self.monitoringKey) }
    }

    var recordsImages: Bool {
        didSet {
            defaults.set(recordsImages, forKey: Self.recordsImagesKey)
            if !recordsImages { removeUnpinnedImages() }
        }
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
    private static let recordsImagesKey = "recordsImages"
    private static let ignoredAppsKey = "ignoredBundleIDs"
    private static let ignoresPasswordManagersKey = "ignoresPasswordManagers"

    init(persistence: HistoryPersistence?, defaults: UserDefaults = .standard) {
        self.persistence = persistence
        self.defaults = defaults
        isMonitoring = defaults.object(forKey: Self.monitoringKey) as? Bool ?? true
        recordsImages = defaults.object(forKey: Self.recordsImagesKey) as? Bool ?? true
        ignoresPasswordManagers = defaults.object(forKey: Self.ignoresPasswordManagersKey) as? Bool ?? true
        ignoredBundleIDs = defaults.stringArray(forKey: Self.ignoredAppsKey) ?? []
        retention = defaults.string(forKey: HistoryRetention.storageKey).flatMap(HistoryRetention.init) ?? .forever
        items = (persistence?.load() ?? []).sorted { $0.timestamp > $1.timestamp }
        trim()
        pruneExpired()
    }

    /// 먼저 고정한 항목이 위 (⌘1부터 차례로)
    var pinnedItems: [ClipboardItem] {
        items.filter(\.isPinned).sorted { ($0.pinnedAt ?? .distantPast) < ($1.pinnedAt ?? .distantPast) }
    }
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

    /// 이 앱에서 복사한 내용을 기록해도 되는지 (비밀번호 관리 앱, 사용자가 제외한 앱)
    func shouldRecord(from bundleID: String?) -> Bool {
        guard let bundleID else { return true }
        if ignoresPasswordManagers && PrivacyRules.passwordManagerBundleIDs.contains(bundleID) { return false }
        return !ignoredBundleIDs.contains(bundleID)
    }

    /// 복사된 텍스트를 기록한다. 비어 있거나 너무 크면 기록하지 않는다.
    func record(_ text: String, sourceBundleID: String?, at date: Date = Date()) {
        guard !text.isEmpty, text.utf8.count <= PrivacyRules.maxItemBytes else { return }
        record(.text(text), sourceBundleID: sourceBundleID, at: date)
    }

    /// 복사된 이미지를 기록한다. 너무 크면 기록하지 않는다.
    func record(_ image: ClipboardImage, sourceBundleID: String?, at date: Date = Date()) {
        guard recordsImages, image.pngData.count <= PrivacyRules.maxImageBytes else { return }
        record(.image(image), sourceBundleID: sourceBundleID, at: date)
    }

    /// 이미 있는 내용이면 새로 만들지 않고 시각만 갱신해 위로 올린다.
    private func record(_ content: ClipboardItem.Content, sourceBundleID: String?, at date: Date) {
        guard isMonitoring, shouldRecord(from: sourceBundleID) else { return }

        var item = ClipboardItem(content: content, timestamp: date, sourceBundleID: sourceBundleID)
        if let index = items.firstIndex(where: { $0.content == content }) {
            item = items.remove(at: index)
            item.timestamp = date
        }
        // 이미지는 백그라운드에서 변환한 뒤 기록되므로, 그사이 복사한 텍스트보다 늦게 들어올 수 있다 → 시각 순서대로 끼워 넣는다
        let position = items.firstIndex { $0.timestamp < date } ?? items.endIndex
        items.insert(item, at: position)
        trim()
        scheduleSave()
    }

    func togglePin(_ id: ClipboardItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].pinnedAt = items[index].isPinned ? nil : Date()
        // 여기서 trim하지 않는다: 기록이 꽉 찬 상태에서 오래된 항목의 고정을 풀면 바로 지워지기 때문.
        // 개수 제한은 다음에 새 항목을 기록할 때 적용된다.
        scheduleSave()
    }

    func remove(_ id: ClipboardItem.ID) {
        items.removeAll { $0.id == id }
        scheduleSave()
    }

    private func removeUnpinnedImages() {
        items.removeAll { !$0.isPinned && $0.image != nil }
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
            persistence?.saveSynchronously(persistedItems)
        } else {
            persistence?.waitForPendingWrites()
        }
    }

    /// 디스크에 저장할 항목. Windows처럼 고정하지 않은 이미지는 메모리에만 두고 종료하면 버린다
    /// (스크린샷에는 민감한 화면이 담기기 쉽고, 크기도 커서 저장/시작이 느려지기 때문)
    private var persistedItems: [ClipboardItem] {
        items.filter { $0.isPinned || $0.image == nil }
    }

    /// 고정하지 않은 항목을 최신순으로 한도까지만 남긴다 (텍스트: 개수/전체 크기, 이미지: 개수)
    private func trim() {
        var textCount = 0
        var textBytes = 0
        var imageCount = 0
        items = items.filter { item in
            if item.isPinned { return true }
            if item.image != nil {
                imageCount += 1
                return imageCount <= Self.maxUnpinnedImages
            }
            textCount += 1
            textBytes += item.byteCount
            return textCount <= Self.maxUnpinnedItems && textBytes <= Self.maxUnpinnedBytes
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
            self.persistence?.save(self.persistedItems)
        }
    }
}
