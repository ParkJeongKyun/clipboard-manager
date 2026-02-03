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
        loadHistory()
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
        
        if currentContent != lastClipboardContent {
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
            let unpinnedItems = clipboardManager.clipboardHistory.filter { !$0.isPinned }
            if unpinnedItems.count > 100 {
                let itemsToRemove = unpinnedItems.dropLast(100)
                clipboardManager.clipboardHistory.removeAll { item in
                    itemsToRemove.contains { $0.timestamp == item.timestamp }
                }
            }
            
            saveHistory()
            DispatchQueue.main.async {
                self.objectWillChange.send()
                NotificationCenter.default.post(name: Notification.Name("clipboardMonitorDidChange"), object: nil)
            }
        }
    }
    
    func removeItem(_ item: ClipboardManager.ClipboardItem) {
        clipboardManager.clipboardHistory.removeAll { $0.timestamp == item.timestamp }
        saveHistory()
        objectWillChange.send()
    }
    
    func togglePin(for item: ClipboardManager.ClipboardItem) {
        _ = clipboardManager.togglePin(for: item)
        saveHistory()
        objectWillChange.send()
    }
    
    private func saveHistory() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            let jsonData = try encoder.encode(clipboardManager.clipboardHistory)
            let fileManager = FileManager.default
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let appDir = appSupport.appendingPathComponent("ClipboardManager")
            
            try fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
            let filePath = appDir.appendingPathComponent("clipboard_history.json")
            try jsonData.write(to: filePath)
        } catch {
            print("⚠️ 히스토리 저장 실패: \(error)")
        }
    }
    
    private func loadHistory() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDir = appSupport.appendingPathComponent("ClipboardManager")
        let filePath = appDir.appendingPathComponent("clipboard_history.json")
        
        guard fileManager.fileExists(atPath: filePath.path) else { return }
        
        do {
            let jsonData = try Data(contentsOf: filePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            clipboardManager.clipboardHistory = try decoder.decode([ClipboardManager.ClipboardItem].self, from: jsonData)
        } catch {
            print("⚠️ 히스토리 로드 실패: \(error)")
        }
    }
    
    deinit {
        stopMonitoring()
    }
}
