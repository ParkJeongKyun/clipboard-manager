import AppKit

/// 다운로드 폴더나 디스크 이미지에서 바로 실행했을 때 응용 프로그램 폴더로 옮겨 준다.
///
/// 공증되지 않은 앱을 다운로드 위치에서 실행하면 macOS가 읽기 전용 임시 경로(App Translocation)에서 실행한다.
/// 그 상태로는 로그인 시 자동 실행이 동작하지 않고, 실행할 때마다 위치가 바뀌어 권한 설정도 꼬인다.
@MainActor
enum AppInstaller {
    /// 이동했으면 true (새 위치에서 재시작하므로 호출한 쪽은 초기화를 멈춰야 함)
    static func moveToApplicationsIfNeeded() -> Bool {
        let bundleURL = Bundle.main.bundleURL
        guard needsMove(bundlePath: bundleURL.path) else { return false }

        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "Move to Applications folder?")
        alert.informativeText = String(localized: "Clipboard Manager needs to run from the Applications folder for launch at login and permissions to work. It will be copied there and relaunched.")
        alert.addButton(withTitle: String(localized: "Move to Applications"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        do {
            let destination = try install(from: bundleURL)
            AppRelauncher.relaunch(at: destination)
            return true
        } catch {
            Log.app.error("응용 프로그램 폴더로 이동 실패: \(error.localizedDescription)")
            NSAlert(error: error).runModal()
            return false
        }
    }

    /// 다운로드/데스크탑, 디스크 이미지(/Volumes), 임시 실행 경로이면 이동이 필요
    static func needsMove(bundlePath: String, homeDirectory: String = NSHomeDirectory()) -> Bool {
        bundlePath.contains("/AppTranslocation/")
            || bundlePath.hasPrefix("/Volumes/")
            || bundlePath.hasPrefix(homeDirectory + "/Downloads/")
            || bundlePath.hasPrefix(homeDirectory + "/Desktop/")
    }

    /// /Applications에 복사하고, 쓸 수 없으면 ~/Applications에 복사한다
    private static func install(from source: URL) throws -> URL {
        let fileManager = FileManager.default
        let directories = [
            URL(fileURLWithPath: "/Applications"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        quitOtherInstances()

        var lastError: Error?
        for directory in directories {
            let destination = directory.appendingPathComponent(source.lastPathComponent)
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.trashItem(at: destination, resultingItemURL: nil)
                }
                try fileManager.copyItem(at: source, to: destination)
                removeQuarantine(at: destination)
                return destination
            } catch {
                lastError = error
            }
        }
        throw lastError ?? CocoaError(.fileWriteUnknown)
    }

    /// 이미 설치된 버전이 실행 중이면 종료 (전역 단축키와 기록 파일을 같이 쓰지 않도록)
    private static func quitOtherInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        where app.processIdentifier != ownPID {
            app.terminate()
        }
    }

    /// 사용자가 이미 실행을 허용한 앱이므로, 새 위치에서 다시 확인 창이 뜨지 않게 격리 속성을 지운다
    private static func removeQuarantine(at url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-dr", "com.apple.quarantine", url.path]
        try? process.run()
        process.waitUntilExit()
    }
}
