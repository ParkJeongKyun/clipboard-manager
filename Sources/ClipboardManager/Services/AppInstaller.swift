import AppKit

/// 다운로드 폴더나 디스크 이미지(DMG)에서 바로 실행했을 때 응용 프로그램 폴더에 설치하고 거기서 다시 실행한다.
/// 설치가 끝나면 남아 있는 설치용 DMG를 꺼내서 창도 닫는다.
///
/// 공증되지 않은 앱을 다운로드 위치에서 실행하면 macOS가 읽기 전용 임시 경로(App Translocation)에서 실행한다.
/// 그 상태로는 로그인 시 자동 실행이 동작하지 않고, 실행할 때마다 위치가 바뀌어 권한 설정도 꼬인다.
@MainActor
enum AppInstaller {
    /// 설치하고 재시작을 시작했으면 true (호출한 쪽은 초기화를 멈춰야 함)
    static func installIfNeeded() -> Bool {
        let bundleURL = Bundle.main.bundleURL
        guard needsMove(bundlePath: bundleURL.path) else {
            // 정상 위치에서 실행 중: 드래그로 설치하고 남겨 둔 DMG가 있으면 꺼낸다
            ejectInstallerDiskImages()
            return false
        }

        do {
            let destination = try install(from: bundleURL)
            // 새 위치에서 실행된 앱이 DMG를 꺼낸다 (지금 프로세스가 DMG 위에서 실행 중이라 직접은 못 꺼냄)
            AppRelauncher.relaunch(at: destination)
            return true
        } catch {
            Log.app.error("응용 프로그램 폴더 설치 실패: \(error.localizedDescription)")
            NSApp.activate()
            NSAlert(error: error).runModal()
            return false
        }
    }

    /// 이 앱이 들어 있는 읽기 전용 볼륨(설치용 DMG)을 모두 꺼낸다
    private static func ejectInstallerDiskImages() {
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsReadOnlyKey], options: [.skipHiddenVolumes]
        ) ?? []
        for volume in volumes {
            guard (try? volume.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == true,
                  let app = Bundle(url: volume.appendingPathComponent(Bundle.main.bundleURL.lastPathComponent)),
                  app.bundleIdentifier == Bundle.main.bundleIdentifier else { continue }
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: volume)
            } catch {
                Log.app.notice("설치용 DMG 꺼내기 실패: \(error.localizedDescription)")
            }
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
