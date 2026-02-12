import SwiftUI
import AppKit
import Combine
import HotKey
import Carbon

// MARK: - 디버그 로깅
private func debugLog(_ message: String) {
    #if DEBUG
    print("[\(Date().formatted(date: .omitted, time: .standard))] \(message)")
    #endif
}

// MARK: - Accessibility를 통한 붙여넣기
private func pasteUsingAccessibility() {
    guard AXIsProcessTrusted() else {
        debugLog("❌ Accessibility 권한 없음. 설정 > 보안 및 개인 정보 보호 > 접근성에서 앱을 허용해주세요")
        return
    }
    
    // 간단한 방식: Cmd+V 반복 시도
    simulateKeyPressDirectly()
}

// MARK: - 직접 키 시뮬레이션
private func simulateKeyPressDirectly() {
    guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: UInt16(kVK_ANSI_V), keyDown: true),
          let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: UInt16(kVK_ANSI_V), keyDown: false) else {
        debugLog("❌ 키 이벤트 생성 실패")
        return
    }
    
    let modifiers = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue)
    keyDownEvent.flags = modifiers
    keyUpEvent.flags = modifiers
    
    // 포스트 시도 (리턴값 무시)
    keyDownEvent.post(tap: .cghidEventTap)
    usleep(50000)
    keyUpEvent.post(tap: .cghidEventTap)
    debugLog("✅ 키 이벤트 포스트 완료")
}

// MARK: - 전역 붙여넣기 함수 (PopoverView에서 사용)
private func performPasteActionGlobal() {
    guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: UInt16(kVK_ANSI_V), keyDown: true),
          let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: UInt16(kVK_ANSI_V), keyDown: false) else {
        debugLog("❌ 키 이벤트 생성 실패")
        return
    }
    
    let modifiers = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue)
    keyDownEvent.flags = modifiers
    keyUpEvent.flags = modifiers
    
    keyDownEvent.post(tap: .cghidEventTap)
    usleep(100000) // 100ms
    keyUpEvent.post(tap: .cghidEventTap)
    debugLog("✅ 전역 Cmd+V 키 이벤트 전송")
}

// MARK: - 키 입력 시뮬레이션
private func simulateKeyPress(keyCode: UInt16, modifiers: CGEventFlags) {
    guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
          let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
        debugLog("❌ 키 이벤트 생성 실패")
        return
    }
    
    keyDownEvent.flags = modifiers
    keyUpEvent.flags = modifiers
    
    // CGEventTap으로 포스트 시도
    keyDownEvent.post(tap: .cghidEventTap)
    usleep(50000) // 50ms 대기
    keyUpEvent.post(tap: .cghidEventTap)
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
        
        // 접근성 권한 체크 및 요청
        checkAccessibilityPermission()
        
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
            hotKey = HotKey(key: .v, modifiers: [.command, .control])
            hotKey?.keyDownHandler = { [weak self] in
                self?.showQuickSelectMenu()
            }
            debugLog("✅ 단축키 등록 성공 (⌃⌘V)")
        } catch {
            debugLog("❌ 단축키 등록 실패: \(error)")
        }
    }
    
    // MARK: - 접근성 권한 체크
    private func checkAccessibilityPermission() {
        if !AXIsProcessTrusted() {
            debugLog("⚠️ Accessibility 권한 없음")
            // 처음 실행시에만 권한 요청 (나중에 수동으로도 가능)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.openAccessibilitySettings()
            }
        } else {
            debugLog("✅ Accessibility 권한 확인됨")
        }
    }
    
    private func openAccessibilitySettings() {
        debugLog("⚠️ Accessibility 권한이 필요합니다")
        
        let alert = NSAlert()
        alert.messageText = "Accessibility 권한 필요"
        alert.informativeText = "자동 붙여넣기 기능을 사용하려면 '시스템 설정 > 보안 및 개인 정보 보호 > 접근성'에서 이 앱에 접근권을 부여하세요."
        alert.addButton(withTitle: "설정 열기")
        alert.addButton(withTitle: "취소")
        
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
                debugLog("✅ 설정 창 열기 요청")
            }
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
        
        // 최상단: 메뉴 닫기
        let closeItem = NSMenuItem(title: "상단바 메뉴 닫기 (ESC)", action: #selector(closeMenu), keyEquivalent: "\u{1B}")
        closeItem.keyEquivalentModifierMask = [] // ESC는 modifier 없음
        menu.addItem(closeItem)
        menu.addItem(NSMenuItem.separator())
        
        // 고정된 항목 추가
        addPinnedItemsToMenu(menu, from: clipboardMonitor)
        
        // 최근 항목 추가
        addRecentItemsToMenu(menu, from: clipboardMonitor)
        
        // 하단: 액션 버튼들 (분리 없음)
        addActionItemsToMenu(menu)
        
        statusItem?.menu = menu
    }
    
    private func addPinnedItemsToMenu(_ menu: NSMenu, from monitor: ClipboardMonitor) {
        let pinnedItems = monitor.clipboardManager.getPinnedItems()
        guard !pinnedItems.isEmpty else { return }
        
        let pinnedTitle = NSMenuItem(title: "⭐ 고정됨", action: nil, keyEquivalent: "")
        pinnedTitle.isEnabled = false
        menu.addItem(pinnedTitle)
        
        for item in pinnedItems {
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
        let allItems = Array(monitor.clipboardManager.clipboardHistory.suffix(10)).reversed()
        let recentItems = allItems.filter { !$0.isPinned }
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
        menu.addItem(NSMenuItem.separator())
        
        let quickSelectItem = NSMenuItem(title: "상단바 메뉴 보기 (⇧⌘V)", action: #selector(showQuickSelectMenuFromMenu), keyEquivalent: "v")
        quickSelectItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(quickSelectItem)
        
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
            debugLog("❌ 항목 추출 실패")
            return
        }
        
        // 1. 클립보드 업데이트
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.content, forType: .string)
        debugLog("✅ 클립보드 업데이트: \(item.content.prefix(50))...")
        
        // 2. 메뉴 닫기 (즉시)
        closeMenu()
        
        // 3. 타겟 앱이 포커스를 다시 가져올 시간 제공 (약 200-300ms)
        //    이 시간이 충분하지 않으면 우리 앱이 포커스를 유지한 채로 Cmd+V가 우리 앱으로 전달됨
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.performPasteAction()
        }
    }
    
    private func performPasteAction() {
        // 현재 포커스된 앱이 무엇인지 확인 (디버깅 목적)
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            debugLog("🎯 타겟 앱: \(frontmostApp.localizedName ?? "Unknown")")
        }
        
        guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: UInt16(kVK_ANSI_V), keyDown: true),
              let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: UInt16(kVK_ANSI_V), keyDown: false) else {
            debugLog("❌ 키 이벤트 생성 실패")
            return
        }
        
        let modifiers = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue)
        keyDownEvent.flags = modifiers
        keyUpEvent.flags = modifiers
        
        // CGEventTap을 통해 시스템에 키 이벤트 주입
        // 이 방식은 Alfred, Paste, Clipy 등 유명 클립보드 앱들이 사용하는 표준 방식
        keyDownEvent.post(tap: .cghidEventTap)
        
        // Race Condition 방지: 클립보드 데이터가 완전히 쓰여진 후 Cmd+V가 인식되도록
        // 보통 50-100ms가 안전한 범위 (기기 성능에 따라 조정 가능)
        usleep(100000) // 100ms
        
        keyUpEvent.post(tap: .cghidEventTap)
        debugLog("✅ Cmd+V 키 이벤트 전송 완료")
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
                    .foregroundColor(.white)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.08))
            
            // 항목 목록
            if filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 32))
                        .foregroundColor(.cyan)
                    
                    Text("항목 없음")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.11, green: 0.11, blue: 0.12))
            } else {
                List(filteredItems.reversed(), id: \.timestamp) { item in
                    HStack {
                        Image(systemName: item.isPinned ? "pin.fill" : "doc.on.clipboard")
                            .foregroundColor(item.isPinned ? .orange : .cyan)
                            .frame(width: 20)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.content.split(separator: "\n").first.map(String.init) ?? item.content)
                                .font(.caption)
                                .lineLimit(2)
                                .foregroundColor(.white)
                            
                            HStack(spacing: 8) {
                                Text("\(item.content.count)")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                
                                if item.isPinned {
                                    Image(systemName: "pin.fill")
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
                            debugLog("✅ 클립보드 업데이트: \(item.content.prefix(50))...")
                            
                            // 팝오버 닫기 후 붙여넣기
                            if let window = NSApplication.shared.windows.first(where: { $0.isVisible && !$0.isKeyWindow }) {
                                window.close()
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                performPasteActionGlobal()
                            }
                        }) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.caption2)
                                .foregroundColor(.cyan)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(6)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(6)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 350, height: 400)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
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
                Image(systemName: "doc.on.clipboard")
                    .foregroundColor(.cyan)
                Text("↑↓ 선택 | Enter 붙여넣기 | Esc 취소")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(8)
            }
            .background(Color.white.opacity(0.08))
            
            if items.isEmpty {
                VStack {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 32))
                        .foregroundColor(.cyan)
                    Text("항목 없음")
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.11, green: 0.11, blue: 0.12))
            } else {
                List(Array(items.enumerated()), id: \.element.timestamp) { index, item in
                    HStack {
                        Image(systemName: index == selectedIndex ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(index == selectedIndex ? .cyan : .gray)
                        
                        Image(systemName: "doc.on.clipboard")
                            .foregroundColor(.cyan)
                            .font(.caption)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.content.split(separator: "\n").first.map(String.init) ?? item.content)
                                .font(.body)
                                .lineLimit(1)
                                .foregroundColor(.white)
                            
                            HStack(spacing: 8) {
                                Text("\(item.content.count)")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                
                                if item.isPinned {
                                    Image(systemName: "pin.fill")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .background(index == selectedIndex ? Color.cyan.opacity(0.2) : Color.clear)
                    .onTapGesture {
                        selectedIndex = index
                        onSelect(item)
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
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