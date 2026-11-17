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

    /// 링크를 공유할 때 보이는 소개 이미지 (GitHub 저장소 Settings → Social preview에 올린다).
    /// GitHub 권장 크기 1280×640, 1MB 이하
    @Test func socialPreview() throws {
        let model = QuickPickerModel(store: makeSampleStore())
        model.moveSelection(by: 1)
        let panel = QuickPickerView(model: model) { _ in }
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))

        let size = NSSize(width: 1280, height: 640)
        let image = try render(SocialPreview(panel: panel, icon: appIcon()), size: size, appearance: .darkAqua)
        let url = outputDirectory.appendingPathComponent("social-preview.png")
        try writeResized(image, to: size, url: url)
        let bytes = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        #expect(bytes < 1_000_000)
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
        if let screenshot = sampleScreenshot() {
            store.record(screenshot, sourceBundleID: "com.apple.Preview", at: now.addingTimeInterval(-60 * 5))
        }
        for (content, _, _, pinned) in samples where pinned {
            if let item = store.items.first(where: { $0.text == content }) { store.togglePin(item.id) }
        }
        return store
    }

    /// 이미지 기록을 보여주기 위한 가짜 스크린샷 (막대 그래프가 있는 창)
    private func sampleScreenshot() -> ClipboardImage? {
        let width = 640, height = 360
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor(white: 0.97, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSColor(white: 0.88, alpha: 1).setFill()
        NSRect(x: 0, y: height - 36, width: width, height: 36).fill()
        let colors: [NSColor] = [.systemBlue, .systemTeal, .systemIndigo, .systemBlue, .systemTeal, .systemIndigo]
        let values = [0.45, 0.7, 0.55, 0.85, 0.6, 0.95]
        for (index, value) in values.enumerated() {
            colors[index].setFill()
            let bar = NSRect(x: 60 + index * 90, y: 40, width: 56, height: Int(Double(height - 120) * value))
            NSBezierPath(roundedRect: bar, xRadius: 6, yRadius: 6).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:]).flatMap(ClipboardImage.init(pngData:))
    }

    private func appIcon() -> NSImage? {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return NSImage(contentsOf: root.appendingPathComponent("Resources/AppIcon.iconset/icon_512x512.png"))
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

    /// Retina로 그려진 이미지를 정해진 픽셀 크기로 줄여 PNG로 저장한다
    private func writeResized(_ image: NSImage, to size: NSSize, url: URL) throws {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
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

/// 소개 이미지: 왼쪽에 아이콘과 소개 문구, 오른쪽에 실제 빠른 선택창
private struct SocialPreview<Panel: View>: View {
    let panel: Panel
    let icon: NSImage?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.16, blue: 0.30), Color(red: 0.02, green: 0.07, blue: 0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            HStack(spacing: 56) {
                VStack(alignment: .leading, spacing: 22) {
                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 120, height: 120)
                    }
                    Text(verbatim: "Clipboard Manager")
                        .font(.system(size: 54, weight: .bold))
                    Text(verbatim: "Win+V for Mac")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Color(red: 0.45, green: 0.75, blue: 1.0))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: "⌃⌘V  ·  text & images  ·  pins  ·  search")
                        Text(verbatim: "Free · open source · encrypted · no tracking")
                    }
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.7))
                }
                .foregroundStyle(.white)
                .frame(width: 600, alignment: .leading)

                panel
                    .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
            }
        }
        .frame(width: 1280, height: 640)
    }
}
