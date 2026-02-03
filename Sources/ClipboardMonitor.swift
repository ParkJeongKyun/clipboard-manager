import Foundation
import AppKit
import Combine

class ClipboardMonitor: NSObject, ObservableObject {
    static let shared = ClipboardMonitor()
    
    @Published var clipboardManager = ClipboardManager()
    @Published var isMonitoring = true
    
    private var lastClipboardContent: String?
    private var monitoringTimer: Timer?
    private let clipboard = NSPasteboard.general
    
    override init() {
        super.init()
    }
    
    func startMonitoring() {
        guard monitoringTimer == nil else { return }
        checkClipboard()
        
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        
        isMonitoring = true
    }
    
    func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        isMonitoring = false
    }
    
    private func checkClipboard() {
        guard let currentContent = clipboard.string(forType: .string), !currentContent.isEmpty else { return }
        guard currentContent != lastClipboardContent else { return }
        
        lastClipboardContent = currentContent
        
        // 중복 확인
        if clipboardManager.clipboardHistory.last?.content == currentContent {
            return
        }
        
        // 새 항목 추가
        let item = ClipboardManager.ClipboardItem(
            content: currentContent,
            timestamp: Date(),
            contentType: "text"
        )
        
        clipboardManager.clipboardHistory.append(item)
        
        // 최대 크기 제한 (고정 항목 제외)
        trimHistoryIfNeeded()
        
        clipboardManager.saveHistory()
        notifyChanges()
    }
    
    private func trimHistoryIfNeeded() {
        let unpinnedItems = clipboardManager.clipboardHistory.filter { !$0.isPinned }
        guard unpinnedItems.count > 100 else { return }
        
        let itemsToRemove = unpinnedItems.dropLast(100)
        clipboardManager.clipboardHistory.removeAll { item in
            itemsToRemove.contains { $0.timestamp == item.timestamp }
        }
    }
    
    private func notifyChanges() {
        DispatchQueue.main.async {
            self.objectWillChange.send()
            NotificationCenter.default.post(name: Notification.Name("clipboardMonitorDidChange"), object: nil)
        }
    }
    
    func removeItem(_ item: ClipboardManager.ClipboardItem) {
        clipboardManager.clipboardHistory.removeAll { $0.timestamp == item.timestamp }
        clipboardManager.saveHistory()
        objectWillChange.send()
    }
    
    func togglePin(for item: ClipboardManager.ClipboardItem) {
        _ = clipboardManager.togglePin(for: item)
        clipboardManager.saveHistory()
        objectWillChange.send()
    }
    
    deinit {
        stopMonitoring()
    }
}
