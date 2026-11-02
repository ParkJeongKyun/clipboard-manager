import AppKit

/// 앱이 여러 위치에 설치되어 동시에 실행되면(예: ~/Applications와 /Applications, 로그인 항목 중복)
/// 한 인스턴스만 남긴다.
///
/// 규칙: 버전이 높은 쪽이 남고, 같으면 먼저 실행된 쪽이 남는다.
/// 양쪽이 같은 규칙으로 판단하므로 동시에 시작해도 정확히 하나만 남는다.
@MainActor
enum SingleInstance {
    /// 이 인스턴스가 계속 실행되어야 하면 true (다른 인스턴스는 종료시킴)
    static func resolve() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }
        let me = NSRunningApplication.current
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != me.processIdentifier && !$0.isTerminated }

        for other in others {
            if shouldYield(myVersion: AppVersion.current, myLaunchDate: me.launchDate,
                           otherVersion: version(of: other), otherLaunchDate: other.launchDate) {
                // 다른 인스턴스가 이미 실행 중이라는 걸 알 수 있게 앞으로 가져온다
                other.activate()
                return false
            }
        }
        terminateAndWait(others)
        return true
    }

    /// 상대에게 양보해야 하면 true
    static func shouldYield(myVersion: AppVersion?, myLaunchDate: Date?,
                            otherVersion: AppVersion?, otherLaunchDate: Date?) -> Bool {
        if let myVersion, let otherVersion, myVersion != otherVersion {
            return otherVersion > myVersion
        }
        // 버전이 같거나 알 수 없으면 먼저 실행된 쪽이 남는다
        return (otherLaunchDate ?? .distantPast) < (myLaunchDate ?? .distantPast)
    }

    /// 다른 인스턴스를 종료하고 실제로 끝날 때까지 기다린다 (최대 5초, 안 끝나면 강제 종료)
    static func terminateAndWait(_ apps: [NSRunningApplication]) {
        guard !apps.isEmpty else { return }
        apps.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(5)
        while apps.contains(where: { !$0.isTerminated }), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        apps.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
    }

    private static func version(of app: NSRunningApplication) -> AppVersion? {
        app.bundleURL
            .flatMap(Bundle.init(url:))
            .flatMap { $0.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
            .flatMap(AppVersion.init)
    }
}
