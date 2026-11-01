import AppKit
import Carbon.HIToolbox

/// 클립보드 쓰기와 ⌘V 전송
@MainActor
enum PasteService {
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// 텍스트를 클립보드에 넣고 현재 포커스된 앱에 붙여넣는다
    static func paste(_ text: String) {
        copy(text)
        // 창/메뉴가 닫히고 키 포커스가 원래 앱으로 돌아갈 틈만 준다
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            sendCommandV()
        }
    }

    /// 자동 붙여넣기에 필요한 손쉬운 사용(접근성) 권한
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 권한이 없으면 시스템 권한 요청 창을 띄운다
    @discardableResult
    static func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
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
