import HotKey
import SwiftUI

enum WindowID {
    static let history = "history"
    static let settings = "settings"
}

/// 전역 단축키 정의. 여기 한 곳만 바꾸면 전역 단축키, 메뉴 표시, 설정 화면 표시가 모두 따라간다.
enum AppShortcut {
    /// ⌃⌘V: macOS 기본 단축키나 주요 앱(⇧⌘V 서식 없이 붙여넣기, ⌥⌘V Finder 이동 등)과 겹치지 않음
    static let quickPanel = KeyCombo(key: .v, modifiers: [.control, .command])

    /// 메뉴에 단축키를 표시하기 위한 SwiftUI 표현
    static var quickPanelMenuShortcut: KeyboardShortcut {
        // Character(String)은 "F1"처럼 여러 글자면 크래시하므로 첫 글자만 사용
        let character = quickPanel.key?.description.lowercased().first ?? "v"
        let flags = quickPanel.modifiers
        var modifiers: EventModifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers)
    }
}

@main
struct ClipboardManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        AppLanguage.applyEnglishFallbackIfNeeded()
    }

    var body: some Scene {
        Window("Clipboard History", id: WindowID.history) {
            HistoryWindowView(store: appDelegate.store)
                .appWindowContent()
        }
        .defaultSize(width: 820, height: 540)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsMenuButton()
            }
        }

        Window("Settings", id: WindowID.settings) {
            SettingsView(store: appDelegate.store, updater: appDelegate.updater)
                .appWindowContent()
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(FirstLaunch.isFirstLaunch ? .presented : .suppressed)

        MenuBarExtra {
            MenuBarMenu(store: appDelegate.store, updater: appDelegate.updater, quickPanel: appDelegate.quickPanel)
        } label: {
            Image(nsImage: appDelegate.store.isMonitoring ? MenuBarIcon.recording : MenuBarIcon.paused)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// 창이 열려 있을 때 앱 메뉴의 "설정…"(⌘,)
private struct SettingsMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Settings…") { openWindow(id: WindowID.settings) }
            .keyboardShortcut(",")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ClipboardStore(persistence: HistoryPersistence())
    let updater = UpdateController()
    private(set) lazy var quickPanel = QuickPanelController(store: store)
    private lazy var watcher = PasteboardWatcher(store: store)
    private var hotKey: HotKey?
    private var maintenanceTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 두 인스턴스가 같은 기록 파일을 번갈아 덮어쓰지 않도록 하나만 남긴다
        if !SingleInstance.resolve() {
            NSApp.terminate(nil)
            return
        }
        // DMG나 다운로드 폴더에서 실행했으면 응용 프로그램 폴더에 설치하고 거기서 다시 실행
        if AppInstaller.installIfNeeded() { return }
        FirstLaunch.markLaunched()

        _ = AppLanguage.atLaunch
        watcher.start()
        updater.start()

        // 새로 복사하지 않아도 보관 기간이 지난 기록이 지워지도록 한 시간마다 정리
        maintenanceTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.pruneExpired() }
        }

        hotKey = HotKey(keyCombo: AppShortcut.quickPanel)
        hotKey?.keyDownHandler = { [weak self] in
            self?.quickPanel.toggle()
        }

        // 자동 붙여넣기 권한은 처음 실행할 때만 요청한다 (거부해도 복사 기능은 동작).
        // 이후에는 붙여넣기를 시도할 때 실행당 한 번만 묻고, 상태는 설정 화면에서 보여준다.
        if FirstLaunch.isFirstLaunch {
            PasteService.requestAccessibility()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flush()
    }
}
