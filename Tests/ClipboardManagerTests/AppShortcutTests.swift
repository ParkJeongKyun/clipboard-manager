import SwiftUI
import Testing
@testable import ClipboardManager

struct AppShortcutTests {
    @Test func displayStringMatchesMacConvention() {
        #expect(AppShortcut.quickPanel.description == "⌃⌘V")
    }

    @Test func menuShortcutMatchesGlobalHotKey() {
        let shortcut = AppShortcut.quickPanelMenuShortcut
        #expect(shortcut.key == KeyEquivalent("v"))
        #expect(shortcut.modifiers == [.control, .command])
    }
}
