import AppKit

/// 앱 아이콘(클립보드 + 별표)을 단색으로 줄인 메뉴바 아이콘.
/// 템플릿 이미지라 메뉴바의 라이트/다크 모드에 맞춰 색이 자동으로 바뀐다.
@MainActor
enum MenuBarIcon {
    static let recording = make(isPaused: false)
    /// 기록 일시정지 중에는 별표 대신 일시정지 표시
    static let paused = make(isPaused: true)

    private static func make(isPaused: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            draw(isPaused: isPaused)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = isPaused
            ? String(localized: "Clipboard Manager (Paused)")
            : String(localized: "Clipboard Manager")
        return image
    }

    /// 18pt 캔버스 기준 (왼쪽 아래 원점)
    private static func draw(isPaused: Bool) {
        NSColor.black.set()

        // 클립보드 판 (윤곽선)
        let board = NSBezierPath(roundedRect: NSRect(x: 3.2, y: 1.2, width: 11.6, height: 13.6), xRadius: 2.4, yRadius: 2.4)
        board.lineWidth = 1.4
        board.stroke()

        // 상단 집게
        NSBezierPath(roundedRect: NSRect(x: 6, y: 13, width: 6, height: 3.6), xRadius: 1.3, yRadius: 1.3).fill()

        if isPaused {
            NSBezierPath(roundedRect: NSRect(x: 6.6, y: 4.4, width: 1.6, height: 5.8), xRadius: 0.8, yRadius: 0.8).fill()
            NSBezierPath(roundedRect: NSRect(x: 9.8, y: 4.4, width: 1.6, height: 5.8), xRadius: 0.8, yRadius: 0.8).fill()
            return
        }

        // 별표 (8갈래)
        let center = NSPoint(x: 9, y: 7.3)
        let armLength: CGFloat = 3.3
        let asterisk = NSBezierPath()
        asterisk.lineWidth = 1.4
        asterisk.lineCapStyle = .round
        for step in 0..<4 {
            let angle = CGFloat(step) * .pi / 4
            let dx = cos(angle) * armLength
            let dy = sin(angle) * armLength
            asterisk.move(to: NSPoint(x: center.x - dx, y: center.y - dy))
            asterisk.line(to: NSPoint(x: center.x + dx, y: center.y + dy))
        }
        asterisk.stroke()
    }
}
