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
        
        // 즉시 현재 클립보드 확인
        checkClipboard()
        
        // 0.5초마다 체크
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
        guard let currentContent = clipboard.string(forType: .string) else { return }
        
        if currentContent != lastClipboardContent && !currentContent.isEmpty {
            lastClipboardContent = currentContent
            
            // 중복 확인
            if let lastItem = clipboardManager.clipboardHistory.last,
               lastItem.content == currentContent {
                return
            }
            
            // 새 항목 추가
            let item = ClipboardManager.ClipboardItem(
                content: currentContent,
                timestamp: Date(),
                contentType: "text"
            )
            
            clipboardManager.clipboardHistory.append(item)
            
            // 최대 크기 제한
            if clipboardManager.clipboardHistory.count > 100 {
                clipboardManager.clipboardHistory.removeFirst()
            }
            
            saveHistory()
            DispatchQueue.main.async {
                self.objectWillChange.send()
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
            print("⚠️  히스토리 저장 실패: \(error)")
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
            print("⚠️  히스토리 로드 실패: \(error)")
        }
    }
    
    deinit {
        stopMonitoring()
    }
}
