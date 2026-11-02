import Foundation
import Testing
@testable import ClipboardManager

@MainActor
struct SingleInstanceTests {
    private let earlier = Date(timeIntervalSince1970: 1_000)
    private let later = Date(timeIntervalSince1970: 2_000)

    @Test func newerVersionWins() {
        // 구버전이 먼저 실행 중이어도, 새로 설치한 새 버전이 남는다 (DMG로 업데이트한 경우)
        #expect(SingleInstance.shouldYield(myVersion: AppVersion("0.2.0"), myLaunchDate: earlier,
                                           otherVersion: AppVersion("0.3.0"), otherLaunchDate: later))
        #expect(!SingleInstance.shouldYield(myVersion: AppVersion("0.3.0"), myLaunchDate: later,
                                            otherVersion: AppVersion("0.2.0"), otherLaunchDate: earlier))
    }

    @Test func sameVersionKeepsEarlierLaunch() {
        #expect(SingleInstance.shouldYield(myVersion: AppVersion("0.2.0"), myLaunchDate: later,
                                           otherVersion: AppVersion("0.2.0"), otherLaunchDate: earlier))
        #expect(!SingleInstance.shouldYield(myVersion: AppVersion("0.2.0"), myLaunchDate: earlier,
                                            otherVersion: AppVersion("0.2.0"), otherLaunchDate: later))
    }

    /// 두 인스턴스가 각자 판단해도 정확히 하나만 양보해야 한다 (둘 다 종료되거나 둘 다 남으면 안 됨)
    @Test(arguments: [
        ("0.2.0", "0.3.0"), ("0.3.0", "0.2.0"), ("0.2.0", "0.2.0"), ("0.2", "0.2.0")
    ])
    func exactlyOneInstanceYields(versionA: String, versionB: String) {
        let aYields = SingleInstance.shouldYield(myVersion: AppVersion(versionA), myLaunchDate: earlier,
                                                 otherVersion: AppVersion(versionB), otherLaunchDate: later)
        let bYields = SingleInstance.shouldYield(myVersion: AppVersion(versionB), myLaunchDate: later,
                                                 otherVersion: AppVersion(versionA), otherLaunchDate: earlier)
        #expect(aYields != bYields)
    }

    @Test func unpinningDoesNotDeleteWhenHistoryIsFull() {
        let store = ClipboardStore(persistence: nil, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let now = Date()
        store.record("old pinned", sourceBundleID: nil, at: now.addingTimeInterval(-10_000))
        let pinned = store.items[0].id
        store.togglePin(pinned)
        for i in 0..<ClipboardStore.maxUnpinnedItems {
            store.record("item \(i)", sourceBundleID: nil, at: now.addingTimeInterval(Double(i)))
        }

        store.togglePin(pinned)

        #expect(store.item(withID: pinned) != nil)
    }
}
