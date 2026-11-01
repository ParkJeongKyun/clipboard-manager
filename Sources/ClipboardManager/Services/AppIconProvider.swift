import AppKit

/// 번들 ID로 앱 아이콘을 찾아 캐시한다
@MainActor
enum AppIconProvider {
    private static var cache: [String: NSImage] = [:]
    private static let fallback = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil) ?? NSImage()

    static func icon(for bundleID: String?) -> NSImage {
        guard let bundleID else { return fallback }
        if let cached = cache[bundleID] { return cached }

        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) } ?? fallback
        cache[bundleID] = icon
        return icon
    }

    static func appName(for bundleID: String?) -> String? {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return url.deletingPathExtension().lastPathComponent
    }
}
