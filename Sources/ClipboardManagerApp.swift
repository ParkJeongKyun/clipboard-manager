import SwiftUI
import AppKit
import Combine
import HotKey

// MARK: - 디버그 로깅
private func debugLog(_ message: String) {
    #if DEBUG
    print("[\(Date().formatted(date: .omitted, time: .standard))] \(message)")
    #endif
}

@main
struct ClipboardManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var clipboardMonitor = ClipboardMonitor.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(clipboardMonitor)
                .frame(minWidth: 600, minHeight: 400)
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Clipboard Manager에 대해") {
                    showAbout()
                }
            }
        }
    }
    
    private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Clipboard Manager"
        alert.informativeText = "macOS 클립보드 관리 도구\n\nSwift 6.2.3 (SwiftUI)"
        alert.addButton(withTitle: "확인")
        alert.runModal()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    weak var popover: NSPopover?
    var clipboardMonitor: ClipboardMonitor?
    private var lastMenuUpdateTime: Date = Date.distantPast
    private let menuUpdateDebounceInterval: TimeInterval = 0.3
    private var hotKey: HotKey?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("🚀 애플리케이션 초기화 시작")
        
        clipboardMonitor = ClipboardMonitor.shared
        setupMenuBar()
        setupGlobalHotKey()
        setupMenuUpdateObserver()
        clipboardMonitor?.startMonitoring()
        NSApp.activate(ignoringOtherApps: true)
        
        debugLog("✅ 애플리케이션 초기화 완료")
    }
    
    private func setupMenuUpdateObserver() {
        // ClipboardMonitor의 변경 시 메뉴 업데이트
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scheduleMenuUpdateObjC),
            name: Notification.Name("clipboardMonitorDidChange"),
            object: nil
        )
    }
    
    private func scheduleMenuUpdate() {
        let now = Date()
        if now.timeIntervalSince(lastMenuUpdateTime) >= menuUpdateDebounceInterval {
            setupMenu()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + menuUpdateDebounceInterval) { [weak self] in
                self?.setupMenu()
            }
        }
    }
    
    @objc private func scheduleMenuUpdateObjC() {
        scheduleMenuUpdate()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // 윈도우 닫아도 앱은 계속 실행
    }
    
    private func setupMenuBar() {
        // 메뉴바 아이템 생성
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            // SF Symbol 사용: 클립보드 아이콘
            if #available(macOS 11.0, *) {
                let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard")
                button.image = image
                button.image?.size = NSSize(width: 18, height: 18)
            } else {
                button.title = "📋"
            }
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        // 팝오버 설정
        let newPopover = NSPopover()
        newPopover.contentViewController = NSHostingController(rootView: PopoverView()
            .environmentObject(clipboardMonitor ?? ClipboardMonitor.shared))
        newPopover.behavior = .transient
        self.popover = newPopover
        
        // 메뉴 구성
        setupMenu()
    }
    
    private func setupGlobalHotKey() {
        do {
            hotKey = HotKey(key: .v, modifiers: [.command, .shift])
            hotKey?.keyDownHandler = { [weak self] in
                self?.showQuickSelectMenu()
            }
            debugLog("✅ 단축키 등록 성공 (⌘⇧V)")
        } catch {
            debugLog("❌ 단축키 등록 실패: \(error)")
        }
    }
    
    private func showQuickSelectMenu() {
        DispatchQueue.main.async {
            guard let button = self.statusItem?.button, let menu = self.statusItem?.menu else { return }
            self.statusItem?.popUpMenu(menu)
        }
    }
    
    private func setupMenu() {
        lastMenuUpdateTime = Date()
        guard let clipboardMonitor = clipboardMonitor else { return }
        
        let menu = NSMenu()
        
        // 고정된 항목 추가
        addPinnedItemsToMenu(menu, from: clipboardMonitor)
        
        // 최근 항목 추가
        addRecentItemsToMenu(menu, from: clipboardMonitor)
        
        // 액션 버튼들 추가
        addActionItemsToMenu(menu)
        
        statusItem?.menu = menu
    }
    
    private func addPinnedItemsToMenu(_ menu: NSMenu, from monitor: ClipboardMonitor) {
        let pinnedItems = monitor.clipboardManager.getPinnedItems()
        guard !pinnedItems.isEmpty else { return }
        
        let pinnedTitle = NSMenuItem(title: "⭐ 고정됨", action: nil, keyEquivalent: "")
        pinnedTitle.isEnabled = false
        menu.addItem(pinnedTitle)
        
        for item in pinnedItems.prefix(3) {
            let menuItem = NSMenuItem(
                title: "⭐ \(formatPreview(item.content))",
                action: #selector(restoreClipboardItem(_:)),
                keyEquivalent: ""
            )
            menuItem.representedObject = item
            menu.addItem(menuItem)
        }
        
        menu.addItem(NSMenuItem.separator())
    }
    
    private func addRecentItemsToMenu(_ menu: NSMenu, from monitor: ClipboardMonitor) {
        let recentItems = Array(monitor.clipboardManager.clipboardHistory.suffix(5)).reversed()
        guard !recentItems.isEmpty else { return }
        
        let recentTitle = NSMenuItem(title: "최근 항목", action: nil, keyEquivalent: "")
        recentTitle.isEnabled = false
        menu.addItem(recentTitle)
        
        for (index, item) in recentItems.enumerated() {
            let menuItem = NSMenuItem(
                title: "[\(index + 1)] \(formatPreview(item.content))",
                action: #selector(restoreClipboardItem(_:)),
                keyEquivalent: ""
            )
            menuItem.representedObject = item
            menu.addItem(menuItem)
        }
        
        menu.addItem(NSMenuItem.separator())
    }
    
    private func addActionItemsToMenu(_ menu: NSMenu) {
        let quickSelectItem = NSMenuItem(title: "상단바 메뉴 보기 (⌘⇧V)", action: #selector(showQuickSelectMenuFromMenu), keyEquivalent: "v")
        quickSelectItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(quickSelectItem)
        menu.addItem(NSMenuItem.separator())
        
        let closeItem = NSMenuItem(title: "상단바 메뉴 닫기", action: #selector(closeMenu), keyEquivalent: "")
        menu.addItem(closeItem)
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }
    
    private func formatPreview(_ text: String) -> String {
        return String(text.prefix(35)).replacingOccurrences(of: "\n", with: " ") + "..."
    }
    
    @objc func closeMenu() {
        statusItem?.menu = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.setupMenu()
        }
    }
    
    @objc func togglePopover() {
        if let popover = popover, let button = statusItem?.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }

    
    @objc func showQuickSelectMenuFromMenu() {
        showQuickSelectMenu()
    }
    
    @objc func restoreClipboardItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ClipboardManager.ClipboardItem else {
            return
        }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.content, forType: .string)
        
        // 알림
        let notification = NSUserNotification()
        notification.title = "✅ 복원됨"
        notification.informativeText = "클립보드에 복원되었습니다"
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - PopoverView
struct PopoverView: View {
    @EnvironmentObject var clipboardMonitor: ClipboardMonitor
    @State private var searchText = ""
    
    var filteredItems: [ClipboardManager.ClipboardItem] {
        let items = clipboardMonitor.clipboardManager.clipboardHistory
        if searchText.isEmpty {
            return items
        }
        return items.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 검색 바
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                
                TextField("검색...", text: $searchText)
                    .textFieldStyle(.plain)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(.controlBackgroundColor).opacity(0.5))
            
            // 항목 목록
            if filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clipboard")
                        .font(.system(size: 32))
                        .foregroundColor(.gray)
                    
                    Text("항목 없음")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredItems.reversed(), id: \.timestamp) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.content.split(separator: "\n").first.map(String.init) ?? item.content)
                                .font(.caption)
                                .lineLimit(2)
                            
                            HStack(spacing: 8) {
                                Text("\(item.content.count) 글자")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                if item.isPinned {
                                    Image(systemName: "star.fill")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(item.content, forType: .string)
                        }) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(6)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 350, height: 400)
    }
}
// MARK: - QuickSelectView (키보드 네비게이션)
struct QuickSelectView: View {
    let items: [ClipboardManager.ClipboardItem]
    let onSelect: (ClipboardManager.ClipboardItem) -> Void
    
    @State private var selectedIndex: Int = 0
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("↑↓ 선택 | Enter 복사 | Esc 취소")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(8)
            }
            .background(Color(.controlBackgroundColor).opacity(0.5))
            
            if items.isEmpty {
                VStack {
                    Text("항목 없음")
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(Array(items.enumerated()), id: \.element.timestamp) { index, item in
                    HStack {
                        if index == selectedIndex {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        } else {
                            Image(systemName: "circle")
                                .foregroundColor(.gray)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.content.split(separator: "\n").first.map(String.init) ?? item.content)
                                .font(.body)
                                .lineLimit(1)
                            
                            HStack(spacing: 8) {
                                Text("\(item.content.count) 글자")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                if item.isPinned {
                                    Image(systemName: "star.fill")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .background(index == selectedIndex ? Color.blue.opacity(0.2) : Color.clear)
                    .onTapGesture {
                        selectedIndex = index
                        onSelect(item)
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .focused($isFocused)
        .onAppear {
            isFocused = true
        }
        .onKeyPress { press in
            switch press.key {
            case .upArrow:
                selectedIndex = max(0, selectedIndex - 1)
                return .handled
            case .downArrow:
                selectedIndex = min(items.count - 1, selectedIndex + 1)
                return .handled
            case .return:
                if selectedIndex < items.count {
                    onSelect(items[selectedIndex])
                }
                return .handled
            case .escape:
                if let window = NSApplication.shared.keyWindow {
                    window.close()
                }
                return .handled
            default:
                return .ignored
            }
        }
    }
}