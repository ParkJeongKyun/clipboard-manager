import AppKit
import Carbon.HIToolbox

/// 클립보드 쓰기와 ⌘V 전송
@MainActor
enum PasteService {
    static func copy(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.content {
        case .text(let text): pasteboard.setString(text, forType: .string)
        case .image(let image): pasteboard.setData(image.pngData, forType: .png)
        }
    }

    /// 항목을 클립보드에 넣고 현재 포커스된 앱에 붙여넣는다
    static func paste(_ item: ClipboardItem) {
        copy(item)
        // 창/메뉴가 닫히고 키 포커스가 원래 앱으로 돌아갈 틈만 준다
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            sendCommandV()
        }
    }

    /// 자동 붙여넣기에 필요한 손쉬운 사용(접근성) 권한
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 이번 실행에서 이미 권한을 요청했는지 (요청 창이 붙여넣을 때마다 뜨지 않도록)
    private static var didRequestAccessibility = false

    /// 권한이 없으면 시스템 권한 요청 창을 띄운다. 실행당 한 번만 묻고, force면 항상 묻는다 (설정 화면 버튼).
    @discardableResult
    static func requestAccessibility(force: Bool = false) -> Bool {
        if isAccessibilityTrusted { return true }
        guard force || !didRequestAccessibility else { return false }
        didRequestAccessibility = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static let lastLaunchedBuildKey = "lastLaunchedBuild"

    /// 앱이 바뀐 뒤(첫 설치, 업데이트) 처음 실행할 때 권한이 없으면 요청한다.
    ///
    /// ad-hoc 서명이라 macOS는 업데이트된 앱을 다른 앱으로 본다. 손쉬운 사용 목록에는 켜진 옛 항목이 남지만 동작하지 않아서
    /// 사용자가 직접 지우고 다시 추가해야 했다. 그래서 옛 항목을 지운 뒤 다시 요청해 새 항목이 바로 목록에 올라오게 한다.
    static func requestAccessibilityIfAppChanged(defaults: UserDefaults = .standard) {
        let info = Bundle.main.infoDictionary ?? [:]
        let build = "\(info["CFBundleShortVersionString"] ?? "")-\(info["CFBundleVersion"] ?? "")"
        let previousBuild = defaults.string(forKey: lastLaunchedBuildKey)
        defaults.set(build, forKey: lastLaunchedBuildKey)

        guard previousBuild != build, !isAccessibilityTrusted else { return }
        if !FirstLaunch.isFirstLaunch {
            resetAccessibilityEntry()
        }
        requestAccessibility()
    }

    /// 손쉬운 사용 목록에서 이 앱 항목을 지운다 (삭제 스크립트와 같은 방법)
    private static func resetAccessibilityEntry() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            Log.app.error("손쉬운 사용 항목 정리 실패: \(error.localizedDescription)")
        }
    }

    /// 시스템 설정의 손쉬운 사용 목록을 바로 연다
    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func sendCommandV() {
        guard requestAccessibility() else {
            Log.app.notice("접근성 권한이 없어 클립보드 복사만 수행")
            return
        }

        let source = CGEventSource(stateID: .combinedSessionState)
        // 단축키로 누르고 있던 ⌃ 등의 수정키가 ⌘V에 섞이지 않도록 로컬 키 입력을 잠시 무시
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let keyCode = CGKeyCode(kVK_ANSI_V)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }
}
