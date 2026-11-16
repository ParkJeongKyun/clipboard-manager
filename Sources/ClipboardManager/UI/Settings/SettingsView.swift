import HotKey
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var store: ClipboardStore
    @Bindable var updater: UpdateController
    @AppStorage(PanelPlacement.storageKey) private var placement = PanelPlacement.defaultValue
    @AppStorage(PanelOpacity.storageKey) private var opacity = PanelOpacity.defaultValue
    @State private var language = AppLanguage.current
    @State private var loginItemStatus = SMAppService.mainApp.status
    @State private var isAccessibilityTrusted = PasteService.isAccessibilityTrusted

    var body: some View {
        // 섹션 사이 간격이 넓어서, 창이 노트북 화면보다 길어지지 않도록 섹션을 3개로 묶는다
        Form {
            Section("General") {
                Picker("Language", selection: $language) {
                    ForEach(AppLanguage.allCases) { $0.title.tag($0) }
                }
                .onChange(of: language) { _, newValue in newValue.apply() }

                if language != AppLanguage.atLaunch {
                    HStack {
                        Text("Restart the app to apply the language change.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart Now") { AppRelauncher.relaunch() }
                    }
                }

                LabeledContent("Quick Picker Shortcut") {
                    Text(verbatim: AppShortcut.quickPanel.description)
                        .font(.body.monospaced())
                }
                Picker(selection: $placement) {
                    ForEach(PanelPlacement.allCases) { Text($0.title).tag($0) }
                } label: {
                    Text("Open At")
                    Text(placement.detail)
                }
                LabeledContent("Quick Picker Opacity") {
                    HStack {
                        Slider(value: $opacity, in: PanelOpacity.range, step: 0.05)
                            .frame(width: 160)
                        Text(opacity, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                // onChange 대신 Binding으로 처리: 상태를 다시 읽어 반영할 때 등록/해제가 또 실행되지 않도록
                Toggle("Launch at Login", isOn: Binding(
                    get: { loginItemStatus == .enabled || loginItemStatus == .requiresApproval },
                    set: setLaunchAtLogin
                ))
                if loginItemStatus == .requiresApproval {
                    HStack {
                        Text("Allow the app in System Settings › Login Items.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }

                LabeledContent {
                    if isAccessibilityTrusted {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Open Settings…") {
                            // 목록에 앱을 등록한 뒤 해당 설정 화면을 연다
                            PasteService.requestAccessibility(force: true)
                            PasteService.openAccessibilitySettings()
                        }
                    }
                } label: {
                    Text("Auto-Paste Permission")
                    if !isAccessibilityTrusted {
                        Text("Without it, items are only copied.")
                    }
                }
            }

            Section("Privacy") {
                Picker(selection: $store.retention) {
                    ForEach(HistoryRetention.allCases) { Text($0.title).tag($0) }
                } label: {
                    Text("Keep History For")
                    Text("Pinned items are always kept.")
                }
                Toggle(isOn: $store.recordsImages) {
                    Text("Record Images")
                    Text("Up to 25 images, 4 MB each. Cleared on quit unless pinned.")
                }
                Toggle(isOn: $store.ignoresPasswordManagers) {
                    Text("Ignore Password Managers")
                    Text("1Password, Bitwarden, Passwords, Keychain Access, and more.")
                }
                LabeledContent("Ignored Apps") {
                    Button("Add App…", action: addIgnoredApp)
                }
                ForEach(store.ignoredBundleIDs, id: \.self) { bundleID in
                    HStack {
                        SourceAppIcon(bundleID: bundleID, size: 16)
                        Text(verbatim: AppIconProvider.appName(for: bundleID) ?? bundleID)
                        Spacer()
                        Button {
                            store.ignoredBundleIDs.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Section("Updates") {
                UpdateStatusRow(updater: updater)
                Toggle("Check for Updates Automatically", isOn: $updater.automaticallyChecks)
                Toggle("Install Updates Automatically", isOn: $updater.automaticallyInstalls)
                    .disabled(!updater.automaticallyChecks)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        // 시스템 설정에서 권한을 바꾸고 돌아왔을 때 반영
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshSystemStatus()
        }
    }

    private func refreshSystemStatus() {
        isAccessibilityTrusted = PasteService.isAccessibilityTrusted
        loginItemStatus = SMAppService.mainApp.status
    }

    /// 기록하지 않을 앱 선택 (예: 은행, 사내 보안 앱)
    private func addIgnoredApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }

        let bundleIDs = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        for bundleID in bundleIDs where !store.ignoredBundleIDs.contains(bundleID) {
            store.ignoredBundleIDs.append(bundleID)
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
        loginItemStatus = SMAppService.mainApp.status
    }
}

/// 업데이트 확인 상태와 동작 버튼
private struct UpdateStatusRow: View {
    let updater: UpdateController

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Version \(AppVersion.current?.description ?? "—")")
                status
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let release = updater.availableRelease {
                Link("Release Notes", destination: release.pageURL)
                Button("Update and Relaunch") { Task { await updater.install() } }
            } else {
                Button("Check Now") { Task { await updater.check(userInitiated: true) } }
                    .disabled(updater.isBusy)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch updater.state {
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking for updates…")
            }
        case .installing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Installing update…")
            }
        case .upToDate:
            Text("You're up to date.")
        case .available(let release):
            Text("Version \(release.version?.description ?? release.tagName) is available.")
                .foregroundStyle(.primary)
        case .failed(let message):
            Text("Update failed: \(message)")
                .foregroundStyle(.red)
        case .idle:
            if let lastCheckDate = updater.lastCheckDate {
                Text("Last checked \(lastCheckDate, format: .relative(presentation: .named))")
            }
        }
    }
}
