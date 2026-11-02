import Testing
@testable import ClipboardManager

struct AppInstallerTests {
    @Test(arguments: [
        ("/Users/me/Downloads/ClipboardManager.app", true),
        ("/Users/me/Desktop/ClipboardManager.app", true),
        ("/Volumes/Clipboard Manager/ClipboardManager.app", true),
        ("/private/var/folders/xy/T/AppTranslocation/1234/d/ClipboardManager.app", true),
        ("/Applications/ClipboardManager.app", false),
        ("/Users/me/Applications/ClipboardManager.app", false),
        // 개발 중 make run
        ("/Users/me/Code/clipboard-manager/build/ClipboardManager.app", false)
    ])
    @MainActor
    func detectsLocationsThatNeedMove(path: String, expected: Bool) {
        #expect(AppInstaller.needsMove(bundlePath: path, homeDirectory: "/Users/me") == expected)
    }
}
