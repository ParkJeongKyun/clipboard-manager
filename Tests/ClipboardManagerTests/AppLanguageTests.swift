import Testing
@testable import ClipboardManager

struct AppLanguageTests {
    @Test(arguments: [
        // 1순위가 지원 언어가 아니면 영어 (아래쪽에 한국어가 있어도)
        (["ja-JP", "ko-KR"], true),
        (["zh-Hans-CN", "ko-KR", "en-US"], true),
        (["ja-JP"], true),
        // 1순위가 영어/한국어면 macOS 기본 동작 그대로
        (["ko-KR", "en-US"], false),
        (["ko"], false),
        (["en-GB", "ko-KR"], false),
        (["en-KR"], false),
        ([], false)
    ])
    func englishFallback(preferredLanguages: [String], expected: Bool) {
        #expect(AppLanguage.needsEnglishFallback(preferredLanguages: preferredLanguages) == expected)
    }
}
