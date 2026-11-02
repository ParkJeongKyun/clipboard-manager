import SwiftUI

/// 메뉴바 아이콘을 눌렀을 때 나오는 메뉴. 기록 항목은 빠른 선택창에서 보여주므로 여기에는 동작만 둔다.
struct MenuBarMenu: View {
    @Bindable var store: ClipboardStore
    let updater: UpdateController
    let quickPanel: QuickPanelController

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let version = updater.availableRelease?.version {
            Button("Update to \(version.description) and Relaunch") {
                Task { await updater.install() }
            }
            Divider()
        } else if updater.state == .installing {
            Text("Installing update…")
            Divider()
        }

        Button("Open Quick Picker") { quickPanel.show() }
            .keyboardShortcut(AppShortcut.quickPanelMenuShortcut)
        Button("Show History…") { open(WindowID.history) }

        Divider()

        Toggle("Pause Recording", isOn: Binding(
            get: { !store.isMonitoring },
            set: { store.isMonitoring = !$0 }
        ))

        Divider()

        Button("Settings…") { open(WindowID.settings) }
            .keyboardShortcut(",")
        Button("Quit Clipboard Manager") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func open(_ id: String) {
        openWindow(id: id)
        NSApp.activate()
    }
}
