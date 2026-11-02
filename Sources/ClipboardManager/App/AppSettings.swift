import AppKit
import SwiftUI

/// 앱 표시 언어. macOS 표준 방식대로 앱 도메인의 AppleLanguages를 바꾸고 재시작해서 적용한다.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case korean = "ko"

    var id: Self { self }

    /// 실행 시점의 선택값 (재시작이 필요한지 판단용)
    static let atLaunch = current

    /// macOS가 앱 언어를 정할 때 읽는 UserDefaults 키
    private static let defaultsKey = "AppleLanguages"

    static var current: AppLanguage {
        let appDomain = Bundle.main.bundleIdentifier.flatMap(UserDefaults.standard.persistentDomain(forName:))
        guard let code = (appDomain?[defaultsKey] as? [String])?.first else { return .system }
        return code.hasPrefix("ko") ? .korean : .english
    }

    /// "시스템 설정 따르기"일 때 시스템 1순위 언어가 지원 언어가 아니면 이번 실행은 영어로 표시한다.
    /// macOS는 1순위 언어가 없으면 목록 아래쪽에서 고르기 때문에 (예: 일본어, 한국어 → 한국어) 직접 막는다.
    /// 설정에는 저장하지 않으며, 번역 문자열을 처음 읽기 전(앱 시작 직후)에 호출해야 한다.
    static func applyEnglishFallbackIfNeeded() {
        guard current == .system, needsEnglishFallback(preferredLanguages: Locale.preferredLanguages) else { return }
        UserDefaults.standard.setVolatileDomain([defaultsKey: [english.rawValue]], forName: UserDefaults.argumentDomain)
    }

    static func needsEnglishFallback(preferredLanguages: [String]) -> Bool {
        guard let primary = preferredLanguages.first else { return false }
        return ![english, korean].contains { primary.hasPrefix($0.rawValue) }
    }

    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        } else {
            UserDefaults.standard.set([rawValue], forKey: Self.defaultsKey)
        }
    }

    var title: Text {
        switch self {
        case .system: Text("System Default")
        // 언어 이름은 해당 언어로 표시
        case .english: Text(verbatim: "English")
        case .korean: Text(verbatim: "한국어")
        }
    }

    /// 날짜 등 서식에 쓸 로케일. 언어는 실제로 로드된 번역을, 지역(날짜 순서 등)은 시스템 설정을 따른다.
    static var displayLocale: Locale {
        var components = Locale.Components(locale: .current)
        components.languageComponents = Locale.Language.Components(
            identifier: Bundle.main.preferredLocalizations.first ?? "en"
        )
        return Locale(components: components)
    }
}

/// 첫 실행 여부. 메뉴바 앱은 실행해도 보이는 창이 없어서, 처음에는 설정 창을 띄워 실행됐음을 알린다.
enum FirstLaunch {
    private static let key = "hasLaunchedBefore"

    /// 이번 실행이 처음인지 (실행 중에는 바뀌지 않음)
    static let isFirstLaunch = !UserDefaults.standard.bool(forKey: key)

    static func markLaunched() {
        UserDefaults.standard.set(true, forKey: key)
    }
}

/// 빠른 선택창을 띄울 위치
enum PanelPlacement: String, CaseIterable, Identifiable {
    /// 텍스트 입력 커서 아래. 찾지 못하면 마우스 위치
    case caret
    case mouse
    /// 마우스가 있는 화면의 가운데 (Spotlight처럼)
    case center

    static let storageKey = "panelPlacement"
    static let defaultValue = PanelPlacement.mouse

    var id: Self { self }

    static var current: PanelPlacement {
        UserDefaults.standard.string(forKey: storageKey).flatMap(PanelPlacement.init) ?? defaultValue
    }

    var title: LocalizedStringKey {
        switch self {
        case .caret: "Text Cursor"
        case .mouse: "Mouse Pointer"
        case .center: "Center of Screen"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .caret: "Opens below the text cursor. Some apps (Chrome, VS Code, Electron apps) don't report it correctly, so it falls back to the mouse pointer."
        case .mouse: "Always opens at the mouse pointer."
        case .center: "Always opens in the middle of the screen with the mouse pointer."
        }
    }
}

/// 메뉴바 앱이지만 창(기록, 설정)이 열려 있는 동안에는 Dock 아이콘과 앱 메뉴를 보여준다
@MainActor
enum DockPresence {
    private static var openWindowCount = 0

    static func windowOpened() {
        openWindowCount += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    static func windowClosed() {
        openWindowCount = max(openWindowCount - 1, 0)
        if openWindowCount == 0 {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

extension View {
    /// 기록/설정 창 공통: 열려 있는 동안 Dock에 표시 + 선택한 언어의 서식
    func appWindowContent() -> some View {
        appLocale()
            .onAppear { DockPresence.windowOpened() }
            .onDisappear { DockPresence.windowClosed() }
    }

    /// 날짜 등의 서식을 선택한 표시 언어에 맞춘다
    func appLocale() -> some View {
        environment(\.locale, AppLanguage.displayLocale)
    }
}

enum AppRelauncher {
    /// 현재 프로세스가 완전히 종료된 뒤 다시 실행한다. (기본: 같은 위치, 설치 직후에는 새 위치)
    /// 종료 전에 open하면 기존 인스턴스만 앞으로 가져오고 재시작되지 않는다.
    @MainActor
    static func relaunch(at bundleURL: URL = Bundle.main.bundleURL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.1; done; /usr/bin/open \"$0\"",
            bundleURL.path, String(ProcessInfo.processInfo.processIdentifier)
        ]
        try? process.run()
        NSApp.terminate(nil)
    }
}
