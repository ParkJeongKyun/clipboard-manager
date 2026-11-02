import AppKit

/// 번들 ID로 앱 아이콘과 이름을 찾아 캐시한다 (목록을 그릴 때마다 LaunchServices를 조회하지 않도록)
@MainActor
enum AppIconProvider {
    private struct AppInfo {
        let icon: NSImage
        let name: String?
    }

    private static var cache: [String: AppInfo] = [:]
    private static let fallbackIcon = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil) ?? NSImage()

    static func icon(for bundleID: String?) -> NSImage {
        bundleID.map { info(for: $0).icon } ?? fallbackIcon
    }

    static func appName(for bundleID: String?) -> String? {
        bundleID.flatMap { info(for: $0).name }
    }

    private static func info(for bundleID: String) -> AppInfo {
        if let cached = cache[bundleID] { return cached }

        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        let info = AppInfo(
            icon: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? fallbackIcon,
            name: url?.deletingPathExtension().lastPathComponent
        )
        cache[bundleID] = info
        return info
    }
}
