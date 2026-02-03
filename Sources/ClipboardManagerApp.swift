import SwiftUI
import AppKit

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
    var popover: NSPopover?
    var clipboardMonitor: ClipboardMonitor?
    private var lastMenuUpdateTime: Date = Date.distantPast
    private let menuUpdateDebounceInterval: TimeInterval = 0.3
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        clipboardMonitor = ClipboardMonitor.shared
        setupMenuBar()
        setupGlobalHotKey()
        setupMenuUpdateObserver()
        clipboardMonitor?.startMonitoring()
        NSApp.activate(ignoringOtherApps: true)
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
            button.title = "📋"
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        // 팝오버 설정
        popover = NSPopover()
        popover?.contentViewController = NSHostingController(rootView: PopoverView()
            .environmentObject(clipboardMonitor ?? ClipboardMonitor.shared))
        popover?.behavior = .transient
        
        // 메뉴 구성
        setupMenu()
    }
    
    private func setupGlobalHotKey() {
        // Cmd+Shift+V 전역 단축키 설정
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags
            
            // Cmd+Shift+V 체크
            if flags.contains(.command) && flags.contains(.shift) && event.keyCode == 9 { // 9는 V 키 코드
                DispatchQueue.main.async {
                    self?.handleGlobalHotKey()
                }
            }
        }
    }
    
    @objc func handleGlobalHotKey() {
        if let mainWindow = NSApplication.shared.windows.first {
            if mainWindow.isVisible {
                mainWindow.orderOut(nil)
            } else {
                mainWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    private func setupMenu() {
        lastMenuUpdateTime = Date()
        guard let clipboardMonitor = clipboardMonitor else { return }
        
        let menu = NSMenu()
        
        // 고정된 항목 섹션
        let pinnedItems = clipboardMonitor.clipboardManager.getPinnedItems()
        if !pinnedItems.isEmpty {
            let pinnedTitle = NSMenuItem(title: "⭐ 고정됨", action: nil, keyEquivalent: "")
            pinnedTitle.isEnabled = false
            menu.addItem(pinnedTitle)
            
            for item in pinnedItems.prefix(3) {
                let preview = String(item.content.prefix(35)).replacingOccurrences(of: "\n", with: " ")
                let menuItem = NSMenuItem(
                    title: "⭐ \(preview)...",
                    action: #selector(restoreClipboardItem(_:)),
                    keyEquivalent: ""
                )
                menuItem.representedObject = item
                menu.addItem(menuItem)
            }
            
            menu.addItem(NSMenuItem.separator())
        }
        
        // 최근 항목 섹션
        let recentItems = Array(clipboardMonitor.clipboardManager.clipboardHistory.suffix(5)).reversed()
        if !recentItems.isEmpty {
            let recentTitle = NSMenuItem(title: "최근 항목", action: nil, keyEquivalent: "")
            recentTitle.isEnabled = false
            menu.addItem(recentTitle)
            
            for (index, item) in recentItems.enumerated() {
                let preview = String(item.content.prefix(35)).replacingOccurrences(of: "\n", with: " ")
                let menuItem = NSMenuItem(
                    title: "[\(index + 1)] \(preview)...",
                    action: #selector(restoreClipboardItem(_:)),
                    keyEquivalent: ""
                )
                menuItem.representedObject = item
                menu.addItem(menuItem)
            }
            
            menu.addItem(NSMenuItem.separator())
        }
        
        // 창 표시/숨기기
        let mainWindow = NSApplication.shared.windows.first
        let windowTitle = (mainWindow?.isVisible ?? false ? "창 숨기기" : "창 표시") + " (⌘⇧V)"
        let windowItem = NSMenuItem(title: windowTitle, action: #selector(toggleWindow), keyEquivalent: "")
        menu.addItem(windowItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 종료
        let quitItem = NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
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
    
    @objc func toggleWindow() {
        if let mainWindow = NSApplication.shared.windows.first {
            if mainWindow.isVisible {
                mainWindow.orderOut(nil)
            } else {
                mainWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        scheduleMenuUpdate()
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
