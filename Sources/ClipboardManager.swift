import Foundation
import AppKit
import CryptoKit

/// ClipboardManager: 클립보드 내용을 관리하는 클래스
class ClipboardManager {
    private let clipboard = NSPasteboard.general
    var clipboardHistory: [ClipboardItem] = []
    private let maxHistorySize = 100
    
    // MARK: - 암호화 관련
    private let keychainServiceName = "ClipboardManager"
    private let keychainAccountName = "MasterKey"
    private lazy var encryptionKey: SymmetricKey = {
        getOrCreateEncryptionKey()
    }()
    
    struct ClipboardItem: Codable, Hashable {
        let content: String
        let timestamp: Date
        let contentType: String // "text", "file", "image", etc.
        var isPinned: Bool = false // 고정 여부
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(timestamp)
        }
        
        static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
            lhs.timestamp == rhs.timestamp
        }
    }
    
    init() {
        self.clipboardHistory = loadHistory() ?? []
    }
    
    /// 현재 클립보드 내용을 가져옵니다
    func getCurrentClipboardContent() -> String? {
        clipboard.string(forType: .string)
    }
    
    /// 클립보드 내용을 저장 목록에 추가합니다
    func saveCurrentClipboard() -> Bool {
        guard let content = getCurrentClipboardContent(), !content.isEmpty else {
            return false
        }
        
        // 중복 확인
        if let lastItem = clipboardHistory.last, lastItem.content == content {
            return false
        }
        
        let item = ClipboardItem(
            content: content,
            timestamp: Date(),
            contentType: "text"
        )
        
        clipboardHistory.append(item)
        
        // 히스토리 크기 제한 (고정되지 않은 항목만)
        let pinnedCount = clipboardHistory.filter { $0.isPinned }.count
        let maxNonPinned = maxHistorySize - pinnedCount
        let nonPinnedItems = clipboardHistory.filter { !$0.isPinned }
        
        if nonPinnedItems.count > maxNonPinned {
            if let firstNonPinned = clipboardHistory.firstIndex(where: { !$0.isPinned }) {
                clipboardHistory.remove(at: firstNonPinned)
            }
        }
        
        saveHistory()
        return true
    }
    
    /// 항목의 핀 상태를 토글합니다
    func togglePin(for item: ClipboardItem) -> Bool {
        if let index = clipboardHistory.firstIndex(where: { $0.timestamp == item.timestamp }) {
            clipboardHistory[index].isPinned.toggle()
            return clipboardHistory[index].isPinned
        }
        return false
    }
    
    /// 고정된 항목들을 반환합니다
    func getPinnedItems() -> [ClipboardItem] {
        return Array(clipboardHistory.filter { $0.isPinned }.reversed())
    }
    
    /// 특정 인덱스의 항목을 클립보드에 복사합니다
    func restoreClipboardItem(at index: Int) -> Bool {
        let sortedHistory = Array(clipboardHistory.reversed())
        guard index >= 0, index < sortedHistory.count else {
            return false
        }
        
        let item = sortedHistory[index]
        clipboard.clearContents()
        clipboard.setString(item.content, forType: .string)
        
        return true
    }
    
    /// 전체 히스토리를 삭제합니다 (고정된 항목은 유지)
    func clearHistory() {
        clipboardHistory.removeAll { !$0.isPinned }
        saveHistory()
    }
    
    /// 최근 N개 항목을 삭제합니다
    func removeLastItems(count: Int) {
        let removeCount = min(count, clipboardHistory.count)
        for _ in 0..<removeCount {
            if let lastNonPinned = clipboardHistory.lastIndex(where: { !$0.isPinned }) {
                clipboardHistory.remove(at: lastNonPinned)
            }
        }
        saveHistory()
    }
    
    /// 히스토리 통계를 출력합니다
    func printStatistics() {
        // DEBUG 빌드에서만 로그 출력
        #if DEBUG
        let pinnedCount = clipboardHistory.filter { $0.isPinned }.count
        print("📊 총 항목: \(clipboardHistory.count)/\(maxHistorySize), 고정: \(pinnedCount)")
        #endif
    }
    
    // MARK: - Private Methods
    
    private let historyFilePath: String = {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDir = appSupport.appendingPathComponent("ClipboardManager")
        
        // 디렉토리 생성
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        
        return appDir.appendingPathComponent("clipboard_history.json").path
    }()
    
    func saveHistory() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            let jsonData = try encoder.encode(clipboardHistory)
            let encryptedData = try encryptData(jsonData)
            try encryptedData.write(to: URL(fileURLWithPath: historyFilePath))
            
            #if DEBUG
            print("✅ 히스토리 저장 및 암호화 완료")
            #endif
        } catch {
            #if DEBUG
            print("⚠️  히스토리 저장 실패: \(error)")
            #endif
        }
    }
    
    private func loadHistory() -> [ClipboardItem]? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: historyFilePath) else {
            return nil
        }
        
        do {
            let encryptedData = try Data(contentsOf: URL(fileURLWithPath: historyFilePath))
            let jsonData = try decryptData(encryptedData)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let items = try decoder.decode([ClipboardItem].self, from: jsonData)
            
            #if DEBUG
            print("✅ 히스토리 로드 및 복호화 완료")
            #endif
            
            return items
        } catch {
            #if DEBUG
            print("⚠️  히스토리 로드 실패: \(error)")
            #endif
            return nil
        }
    }
    
    // MARK: - 암호화/복호화 메서드
    
    private func encryptData(_ data: Data) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: encryptionKey)
        
        guard let combinedData = sealedBox.combined else {
            throw EncryptionError.encryptionFailed
        }
        
        return combinedData
    }
    
    private func decryptData(_ data: Data) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: encryptionKey)
    }
    
    private func getOrCreateEncryptionKey() -> SymmetricKey {
        // Keychain에서 기존 키 가져오기
        if let keyData = retrieveKeyFromKeychain() {
            return SymmetricKey(data: keyData)
        }
        
        // 새로운 키 생성
        let newKey = SymmetricKey(size: .bits256)
        saveKeyToKeychain(newKey.withUnsafeBytes { Data($0) })
        
        #if DEBUG
        print("✅ 새로운 암호화 키 생성 및 Keychain 저장")
        #endif
        
        return newKey
    }
    
    private func saveKeyToKeychain(_ keyData: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: keychainAccountName,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // 기존 항목 삭제
        SecItemDelete(query as CFDictionary)
        
        // 새로운 항목 추가
        let status = SecItemAdd(query as CFDictionary, nil)
        
        #if DEBUG
        if status == errSecSuccess {
            print("✅ 암호화 키 Keychain 저장 성공")
        } else {
            print("⚠️  Keychain 저장 실패: \(status)")
        }
        #endif
    }
    
    private func retrieveKeyFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: keychainAccountName,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess {
            return result as? Data
        }
        
        return nil
    }
    
    // MARK: - 에러 정의
    enum EncryptionError: Error {
        case encryptionFailed
        case decryptionFailed
    }
}
