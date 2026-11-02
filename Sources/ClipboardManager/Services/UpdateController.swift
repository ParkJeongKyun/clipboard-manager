import Foundation
import Observation

/// 업데이트 확인/설치 상태. 메뉴바와 설정 화면이 같이 바라본다.
@MainActor
@Observable
final class UpdateController {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(GitHubRelease)
        case installing
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastCheckDate: Date? {
        didSet { defaults.set(lastCheckDate, forKey: Keys.lastCheckDate) }
    }
    var automaticallyChecks: Bool {
        didSet { defaults.set(automaticallyChecks, forKey: Keys.automaticallyChecks) }
    }
    var automaticallyInstalls: Bool {
        didSet { defaults.set(automaticallyInstalls, forKey: Keys.automaticallyInstalls) }
    }

    /// 자동 확인 간격. 자주 껐다 켜도 GitHub API를 과하게 부르지 않도록 마지막 확인 시각 기준
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var timer: Timer?

    private enum Keys {
        static let lastCheckDate = "lastUpdateCheck"
        static let automaticallyChecks = "automaticallyChecksForUpdates"
        static let automaticallyInstalls = "automaticallyInstallsUpdates"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lastCheckDate = defaults.object(forKey: Keys.lastCheckDate) as? Date
        automaticallyChecks = defaults.object(forKey: Keys.automaticallyChecks) as? Bool ?? true
        automaticallyInstalls = defaults.bool(forKey: Keys.automaticallyInstalls)
    }

    var availableRelease: GitHubRelease? {
        if case .available(let release) = state { release } else { nil }
    }

    var isBusy: Bool {
        state == .checking || state == .installing
    }

    func start() {
        // 로그인 직후에는 네트워크가 아직 준비되지 않았을 수 있어 잠시 뒤 확인
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.checkIfDue()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
    }

    private func checkIfDue() {
        guard automaticallyChecks else { return }
        if let lastCheckDate, Date().timeIntervalSince(lastCheckDate) < Self.checkInterval { return }
        Task { await check(userInitiated: false) }
    }

    /// 사용자가 직접 확인한 경우에만 오류를 보여준다 (자동 확인 실패는 다음에 다시 시도)
    func check(userInitiated: Bool) async {
        guard !isBusy, let currentVersion = AppVersion.current else { return }
        state = .checking

        do {
            let release = try await UpdateInstaller.fetchLatestRelease()
            lastCheckDate = Date()
            guard let latestVersion = release.version, latestVersion > currentVersion else {
                state = .upToDate
                return
            }
            state = .available(release)
            if automaticallyInstalls && !userInitiated {
                await install()
            }
        } catch {
            Log.app.error("업데이트 확인 실패: \(error.localizedDescription)")
            state = userInitiated ? .failed(error.localizedDescription) : .idle
        }
    }

    func install() async {
        guard let release = availableRelease else { return }
        state = .installing
        do {
            let appURL = try await UpdateInstaller.install(release)
            AppRelauncher.relaunch(at: appURL)
        } catch {
            Log.app.error("업데이트 설치 실패: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }
}
