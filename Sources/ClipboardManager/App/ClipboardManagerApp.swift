import HotKey
import SwiftUI

enum WindowID {
    static let history = "history"
}

/// 전역 단축키 정의 (한곳에서만 바꾸면 되도록)
enum AppShortcut {
    /// ⌃⌘V: macOS 기본 단축키나 주요 앱(⇧⌘V 서식 없이 붙여넣기, ⌥⌘V Finder 이동 등)과 겹치지 않음
    static let quickPanelKey = Key.v
    static let quickPanelModifiers: NSEvent.ModifierFlags = [.control, .command]
    static let quickPanelMenuShortcut = KeyboardShortcut("v", modifiers: [.control, .command])
}

@main
struct ClipboardManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("클립보드 기록", id: WindowID.history) {
            HistoryWindowView(store: appDelegate.store)
        }
        .defaultSize(width: 820, height: 540)
        .defaultLaunchBehavior(.suppressed)

        MenuBarExtra {
            MenuBarMenu(store: appDelegate.store, quickPanel: appDelegate.quickPanel)
        } label: {
            Image(nsImage: appDelegate.store.isMonitoring ? MenuBarIcon.recording : MenuBarIcon.paused)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ClipboardStore(persistence: HistoryPersistence())
    private(set) lazy var quickPanel = QuickPanelController(store: store)
    private lazy var watcher = PasteboardWatcher(store: store)
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        watcher.start()

        hotKey = HotKey(key: AppShortcut.quickPanelKey, modifiers: AppShortcut.quickPanelModifiers)
        hotKey?.keyDownHandler = { [weak self] in
            self?.quickPanel.toggle()
        }

        // 처음 실행 시 자동 붙여넣기 권한 요청 (거부해도 복사 기능은 동작)
        if !PasteService.isAccessibilityTrusted {
            PasteService.requestAccessibility()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flush()
    }
}
