import AppKit
import SwiftUI
import Testing
@testable import ClipboardManager

/// README용 스크린샷 생성. 실제 앱 화면을 샘플 데이터로 화면 밖 창에 그려서 PNG로 저장한다.
/// 사용자의 실제 기록이나 설정은 건드리지 않는다.
///
///   make screenshots   (SCREENSHOTS_DIR가 없으면 이 테스트는 건너뜀)
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SCREENSHOTS_DIR"] != nil))
struct ScreenshotTests {
    private let outputDirectory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SCREENSHOTS_DIR"] ?? "")

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func quickPicker(appearance: NSAppearance.Name) throws {
        let model = QuickPickerModel(store: makeSampleStore())
        model.moveSelection(by: 1)
        let panel = QuickPickerView(model: model) { _ in }
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))

        let image = try render(Showcase(content: panel), size: NSSize(width: 520, height: 580), appearance: appearance)
        try save(image, name: "quick-picker", appearance: appearance)
    }


    // MARK: - 샘플 데이터

    private func makeSampleStore() -> ClipboardStore {
        let store = ClipboardStore(persistence: nil, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let now = Date()
        let samples: [(String, String, TimeInterval, Bool)] = [
            ("Thanks for the review! I'll address the comments today.", "notion.id", 60 * 60 * 26, true),
            ("brew install --cask visual-studio-code", "com.apple.Terminal", 60 * 60 * 5, true),
            ("hello@example.com", "com.apple.mail", 60 * 60 * 3, false),
            ("Meeting notes: ship v0.2.0 on Friday, then update the README screenshots.", "com.apple.Notes", 60 * 50, false),
            ("git log --oneline --graph --decorate", "com.apple.Terminal", 60 * 22, false),
            ("func greet(_ name: String) -> String {\n    \"Hello, \\(name)!\"\n}\n\nprint(greet(\"Clipboard\"))", "com.microsoft.VSCode", 60 * 9, false),
            ("https://github.com/ParkJeongKyun/clipboard-manager", "com.apple.Safari", 60 * 2, false)
        ]
        for (content, bundleID, age, _) in samples {
            store.record(content, sourceBundleID: bundleID, at: now.addingTimeInterval(-age))
        }
        for (content, _, _, pinned) in samples where pinned {
            if let item = store.items.first(where: { $0.content == content }) { store.togglePin(item.id) }
        }
        return store
    }

    // MARK: - 렌더링

    /// 뷰를 화면 밖 창에 띄워 그린다.
    /// (사이드바 같은 반투명 배경은 화면 밖 캡처에 그려지지 않아 기록 창은 대상에서 제외)
    private func render<V: View>(_ view: V, size: NSSize, appearance: NSAppearance.Name) throws -> NSImage {
        _ = NSApplication.shared
        let hostingView = NSHostingView(rootView: view.environment(\.locale, Locale(identifier: "en_US")))

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hostingView
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        // SwiftUI가 레이아웃과 비동기 갱신(목록, 아이콘)을 마칠 시간
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))


        let bounds = hostingView.bounds
        let rep = try #require(hostingView.bitmapImageRepForCachingDisplay(in: bounds))
        hostingView.cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    private func save(_ image: NSImage, name: String, appearance: NSAppearance.Name) throws {
        let suffix = appearance == .darkAqua ? "dark" : "light"
        let url = outputDirectory.appendingPathComponent("\(name)-\(suffix).png")
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try png.write(to: url)
    }
}

/// 스크린샷 배경: 앱 아이콘 색의 부드러운 그라데이션 위에 그림자를 준 창
private struct Showcase<Content: View>: View {
    let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.05, green: 0.16, blue: 0.30), Color(red: 0.02, green: 0.07, blue: 0.15)]
                    : [Color(red: 0.70, green: 0.88, blue: 0.99), Color(red: 0.40, green: 0.72, blue: 0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            content
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.25), radius: 24, y: 12)
        }
    }
}
