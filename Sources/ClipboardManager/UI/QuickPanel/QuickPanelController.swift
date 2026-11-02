import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Windows의 Win+V처럼 커서 근처에 뜨는 빠른 선택창.
///
/// `.nonactivatingPanel`이라 열려 있어도 원래 앱이 활성 상태를 유지한다.
/// 그래서 창을 닫자마자 ⌘V를 보내도 원래 앱에 바로 붙여넣어진다.
@MainActor
final class QuickPanelController: NSObject, NSWindowDelegate {
    static let panelSize = NSSize(width: 400, height: 460)

    private let store: ClipboardStore
    private let model: QuickPickerModel
    private var keyMonitor: Any?

    private lazy var panel: QuickPanel = {
        let panel = QuickPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize))
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: QuickPickerView(model: model) { [weak self] item in
            self?.paste(item)
        }
        .appLocale())
        return panel
    }()

    init(store: ClipboardStore) {
        self.store = store
        self.model = QuickPickerModel(store: store)
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        model.reset()
        panel.setFrameOrigin(preferredOrigin())
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    // 다른 곳을 클릭하면 닫기
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    // MARK: - 동작

    private func paste(_ item: ClipboardItem) {
        hide()
        PasteService.paste(item.content)
    }

    private func copyOnly(_ item: ClipboardItem) {
        hide()
        PasteService.copy(item.content)
    }

    // MARK: - 키보드

    /// 검색창이 포커스를 가진 상태에서도 방향키/엔터 등을 먼저 가로챈다
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// 처리했으면 true
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = modifiers.contains(.command)

        switch Int(event.keyCode) {
        case kVK_UpArrow:
            model.moveSelection(by: -1)
        case kVK_DownArrow:
            model.moveSelection(by: 1)
        case kVK_PageUp:
            model.moveSelection(by: -8)
        case kVK_PageDown:
            model.moveSelection(by: 8)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            guard let item = model.selectedItem else { return true }
            command ? copyOnly(item) : paste(item)
        case kVK_Escape:
            if model.query.isEmpty { hide() } else { model.query = "" }
        case kVK_ANSI_P where command:
            guard let item = model.selectedItem else { return true }
            store.togglePin(item.id)
            model.clampSelection()
        case kVK_Delete where command, kVK_ForwardDelete where command:
            guard let item = model.selectedItem else { return true }
            store.remove(item.id)
            model.clampSelection()
        default:
            // ⌘1~⌘9: 해당 순번 바로 붙여넣기 (한글 입력 상태에서도 숫자는 그대로 들어옴)
            guard command,
                  let number = event.charactersIgnoringModifiers.flatMap(Int.init),
                  (1...9).contains(number) else { return false }
            if let item = model.item(at: number - 1) { paste(item) }
        }
        return true
    }

    // MARK: - 위치

    /// 설정의 "창 위치"에 따라 정하고, 화면 밖으로 나가지 않게 보정한다
    private func preferredOrigin() -> NSPoint {
        let size = Self.panelSize
        let mouse = NSEvent.mouseLocation
        let placement = PanelPlacement.current
        let caret = placement == .caret ? CaretLocator.caretRect() : nil
        let anchor = caret.map { NSPoint(x: $0.minX, y: $0.minY) } ?? mouse

        let screen = NSScreen.screens.first { NSMouseInRect(anchor, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return .zero }

        var origin: NSPoint
        if placement == .center {
            // Spotlight처럼 가운데보다 약간 위
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2 + visible.height * 0.1)
        } else {
            // 기준점 바로 아래, 공간이 부족하면 위로
            origin = NSPoint(x: anchor.x, y: anchor.y - size.height - 6)
            if origin.y < visible.minY {
                origin.y = (caret?.maxY ?? anchor.y) + 6
            }
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        return origin
    }
}

/// 키 입력은 받지만 앱을 활성화하지 않는 패널
private final class QuickPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
