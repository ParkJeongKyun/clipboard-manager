import AppKit
import ApplicationServices

/// 접근성 API로 현재 포커스된 텍스트 입력 위치(캐럿)를 찾는다.
/// 지원하지 않는 앱(일부 Electron/웹뷰 등)에서는 nil.
enum CaretLocator {
    /// 화면 좌표(Cocoa, 왼쪽 아래 원점) 기준 캐럿 영역
    static func caretRect() -> NSRect? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        // 응답 없는 앱 때문에 단축키 반응이 늦어지지 않도록
        AXUIElementSetMessagingTimeout(systemWide, 0.1)

        guard let focused: AXUIElement = copyAttribute(systemWide, kAXFocusedUIElementAttribute),
              let range: AXValue = copyAttribute(focused, kAXSelectedTextRangeAttribute) else { return nil }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            focused, kAXBoundsForRangeParameterizedAttribute as CFString, range, &boundsValue
        ) == .success, let boundsValue, CFGetTypeID(boundsValue) == AXValueGetTypeID() else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect), rect != .zero else { return nil }

        // 접근성 좌표는 주 화면 왼쪽 위 원점 → Cocoa 좌표로 변환
        guard let primaryScreen = NSScreen.screens.first else { return nil }
        rect.origin.y = primaryScreen.frame.maxY - rect.maxY

        // 일부 앱은 텍스트 영역 전체나 엉뚱한 좌표를 돌려준다 → 마우스 위치로 대체
        let isOnScreen = NSScreen.screens.contains { $0.frame.contains(rect.origin) }
        guard isOnScreen, rect.height < 100 else { return nil }
        return rect
    }

    private static func copyAttribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
