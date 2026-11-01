import ServiceManagement
import SwiftUI

/// 메뉴바 아이콘을 눌렀을 때 나오는 메뉴
struct MenuBarMenu: View {
    @Bindable var store: ClipboardStore
    let quickPanel: QuickPanelController

    @Environment(\.openWindow) private var openWindow

    private static let itemsPerSection = 10

    var body: some View {
        Button("빠른 선택창 열기") { quickPanel.show() }
            .keyboardShortcut(AppShortcut.quickPanelMenuShortcut)

        let pinned = store.pinnedItems.prefix(Self.itemsPerSection)
        if !pinned.isEmpty {
            Section("고정됨") {
                ForEach(pinned) { itemButton($0) }
            }
        }

        let recent = store.recentItems.prefix(Self.itemsPerSection)
        Section("최근") {
            if recent.isEmpty {
                Text("기록 없음")
            }
            ForEach(recent) { itemButton($0) }
        }

        Divider()

        Button("기록 창 열기…") {
            openWindow(id: WindowID.history)
            NSApp.activate()
        }
        Toggle("기록 일시정지", isOn: Binding(
            get: { !store.isMonitoring },
            set: { store.isMonitoring = !$0 }
        ))
        Button("고정되지 않은 기록 지우기") { store.clearUnpinned() }
            .disabled(store.recentItems.isEmpty)

        Divider()

        Toggle("로그인 시 자동 실행", isOn: Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: setLaunchAtLogin
        ))
        if !PasteService.isAccessibilityTrusted {
            Button("자동 붙여넣기 권한 허용…") { PasteService.requestAccessibility() }
        }

        Divider()

        Button("클립보드 관리자 종료") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func itemButton(_ item: ClipboardItem) -> some View {
        Button(String(item.preview.prefix(50))) {
            PasteService.paste(item.content)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("로그인 항목 변경 실패: \(error.localizedDescription)")
        }
    }
}
