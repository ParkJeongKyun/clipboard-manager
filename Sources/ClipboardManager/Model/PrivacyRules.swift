import SwiftUI

/// 무엇을 기록하지 않을지에 대한 규칙
enum PrivacyRules {
    /// 비밀번호 관리 앱. 기본적으로 이 앱에서 복사한 내용은 기록하지 않는다 (설정에서 끌 수 있음).
    /// 앱이 비밀번호에 붙이는 "기밀" 표시(nspasteboard.org)는 이 설정과 상관없이 항상 따른다.
    static let passwordManagerBundleIDs: Set<String> = [
        "com.apple.keychainaccess",          // 키체인 접근
        "com.apple.Passwords",               // 암호 앱
        "com.1password.1password",           // 1Password 8
        "com.agilebits.onepassword7",        // 1Password 7
        "com.bitwarden.desktop",             // Bitwarden
        "org.keepassxc.keepassxc",           // KeePassXC
        "in.sinew.Enpass-Desktop"            // Enpass
    ]

    /// 한 항목의 최대 크기. 로그 덤프처럼 큰 텍스트는 기록하지 않는다 (메모리/저장 부담, 민감 정보 대량 보관 방지)
    static let maxItemBytes = 1_000_000
}

/// 고정하지 않은 기록을 보관할 기간
enum HistoryRetention: String, CaseIterable, Identifiable {
    case forever
    case day
    case week
    case month

    static let storageKey = "historyRetention"

    var id: Self { self }

    var interval: TimeInterval? {
        switch self {
        case .forever: nil
        case .day: 60 * 60 * 24
        case .week: 60 * 60 * 24 * 7
        case .month: 60 * 60 * 24 * 30
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .forever: "Forever"
        case .day: "1 Day"
        case .week: "1 Week"
        case .month: "1 Month"
        }
    }
}
