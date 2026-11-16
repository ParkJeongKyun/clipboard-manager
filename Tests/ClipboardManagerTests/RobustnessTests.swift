import AppKit
import Carbon.HIToolbox
import CryptoKit
import Foundation
import Testing
@testable import ClipboardManager

/// 개인정보 규칙, 키보드 배열, 저장 파일 처리에서 실제 사용 중 생길 수 있는 경우들
@MainActor
struct RobustnessTests {
    private func makeStore() -> ClipboardStore {
        ClipboardStore(persistence: nil, defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardManagerTests-\(UUID().uuidString)")
    }

    // MARK: - 복사한 앱 판단

    @Test func sameAppIsTheOnlySource() {
        #expect(PasteboardWatcher.possibleSources(previous: "com.apple.Notes", current: "com.apple.Notes") == ["com.apple.Notes"])
    }

    /// 비밀번호 앱에서 복사하자마자 다른 앱으로 넘어가도 제외 규칙이 적용되어야 한다
    @Test func switchingAppsRightAfterCopyStillAppliesRulesOfBothApps() {
        let store = makeStore()
        let sources = PasteboardWatcher.possibleSources(previous: "com.1password.1password", current: "com.apple.Notes")
        #expect(sources.first == "com.1password.1password")
        #expect(!sources.allSatisfy(store.shouldRecord(from:)))

        let reversed = PasteboardWatcher.possibleSources(previous: "com.apple.Notes", current: "com.bitwarden.desktop")
        #expect(!reversed.allSatisfy(store.shouldRecord(from:)))
    }

    @Test func unknownPreviousAppDoesNotBlockRecording() {
        let store = makeStore()
        let sources = PasteboardWatcher.possibleSources(previous: nil, current: "com.apple.Notes")
        #expect(sources.allSatisfy(store.shouldRecord(from:)))
    }

    // MARK: - 키보드 배열

    private func keyboardLayout(id: String) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]
        return list?.first
    }

    @Test func findsCommandVOnQWERTY() throws {
        let us = try #require(keyboardLayout(id: "com.apple.keylayout.US"))
        #expect(PasteService.keyCode(producing: "v", withCommandIn: us) == CGKeyCode(kVK_ANSI_V))
    }

    /// Dvorak에서는 QWERTY의 "." 자리가 V다
    @Test func findsCommandVOnDvorak() throws {
        let dvorak = try #require(keyboardLayout(id: "com.apple.keylayout.Dvorak"))
        #expect(PasteService.keyCode(producing: "v", withCommandIn: dvorak) == CGKeyCode(kVK_ANSI_Period))
    }

    /// "Dvorak - QWERTY ⌘"는 ⌘를 누르면 QWERTY가 된다
    @Test func findsCommandVOnDvorakQwertyCommand() throws {
        let dvorakQwerty = try #require(keyboardLayout(id: "com.apple.keylayout.DVORAK-QWERTYCMD"))
        #expect(PasteService.keyCode(producing: "v", withCommandIn: dvorakQwerty) == CGKeyCode(kVK_ANSI_V))
    }

    @Test func currentLayoutAlwaysYieldsAKey() {
        #expect(PasteService.commandVKeyCode() < 128)
        #expect(PasteService.commandVKeyCode(layout: nil) == CGKeyCode(kVK_ANSI_V))
    }

    // MARK: - 저장 파일

    /// 기록 파일에 적힌 이미지 이름으로 폴더 밖 파일을 읽지 않는다
    @Test func rejectsImageReferencesOutsideImageFolder() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = SymmetricKey(size: .bits256)
        let json = """
        [{"id":"\(UUID().uuidString)","image":{"digest":"../../clipboard_history.json"},"timestamp":"2026-11-16T07:00:00.000Z","isPinned":true},
         {"id":"\(UUID().uuidString)","content":"keep","timestamp":"2026-11-16T07:00:00.000Z","isPinned":false}]
        """
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try AES.GCM.seal(Data(json.utf8), using: key).combined!.write(to: directory.appendingPathComponent("clipboard_history.json"))

        let items = HistoryPersistence(directory: directory, keyStore: InMemoryKeyStore(key: key)).load()
        #expect(items.map(\.text) == ["keep"])
    }

    /// 다른 키로 암호화된 이미지 파일(키를 새로 만든 뒤 남은 파일 등)은 그 항목만 건너뛴다
    @Test func imageEncryptedWithOtherKeyIsSkipped() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let keyStore = InMemoryKeyStore()
        let persistence = HistoryPersistence(directory: directory, keyStore: keyStore)
        _ = persistence.load()
        let png = try #require(NSImageFixtures.png(size: 3))
        let image = try #require(ClipboardImage(pngData: png))
        persistence.saveSynchronously([ClipboardItem(content: .image(image), pinnedAt: Date()), ClipboardItem(text: "keep")])

        let otherKey = SymmetricKey(size: .bits256)
        try AES.GCM.seal(png, using: otherKey).combined!
            .write(to: persistence.imageDirectory.appendingPathComponent(image.digest))

        #expect(HistoryPersistence(directory: directory, keyStore: keyStore).load().map(\.text) == ["keep"])
    }

    /// 이전 버전이 읽을 수 있도록 고정 여부(isPinned)도 함께 저장한다
    @Test func encodesIsPinnedForOlderVersions() throws {
        let item = ClipboardItem(text: "a", pinnedAt: Date())
        let json = String(decoding: try JSONEncoder().encode(item), as: UTF8.self)
        #expect(json.contains("\"isPinned\":true"))
        #expect(json.contains("\"pinnedAt\""))
    }

    // MARK: - 보관/정리

    @Test func retentionAlsoRemovesOldUnpinnedImages() throws {
        let store = makeStore()
        let image = try #require(NSImageFixtures.png(size: 2).flatMap(ClipboardImage.init(pngData:)))
        let pinnedImage = try #require(NSImageFixtures.png(size: 5).flatMap(ClipboardImage.init(pngData:)))
        store.record(pinnedImage, sourceBundleID: nil, at: Date().addingTimeInterval(-3 * 86_400))
        store.togglePin(store.items[0].id)
        store.record(image, sourceBundleID: nil, at: Date().addingTimeInterval(-2 * 86_400))

        store.retention = .day

        #expect(store.items.count == 1)
        #expect(store.items.first?.image == pinnedImage)
    }

    @Test func pausedRecordingIgnoresLateImages() throws {
        let store = makeStore()
        store.isMonitoring = false
        store.record(try #require(NSImageFixtures.png(size: 2).flatMap(ClipboardImage.init(pngData:))), sourceBundleID: nil)
        store.record("text", sourceBundleID: nil)
        #expect(store.items.isEmpty)
    }

    @Test func clearUnpinnedKeepsPinnedImages() throws {
        let store = makeStore()
        store.record(try #require(NSImageFixtures.png(size: 2).flatMap(ClipboardImage.init(pngData:))), sourceBundleID: nil)
        store.togglePin(store.items[0].id)
        store.record(try #require(NSImageFixtures.png(size: 3).flatMap(ClipboardImage.init(pngData:))), sourceBundleID: nil)
        store.record("text", sourceBundleID: nil)

        store.clearUnpinned()

        #expect(store.items.count == 1)
        #expect(store.items.first?.isPinned == true)
    }

    // MARK: - 설정

    @Test(arguments: [(-1.0, 0.4), (0.0, 0.4), (0.7, 0.7), (5.0, 1.0)])
    func clampsPanelOpacity(stored: Double, expected: Double) {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(stored, forKey: PanelOpacity.storageKey)
        #expect(PanelOpacity.value(in: defaults) == expected)
    }

    @Test func defaultPanelOpacityIsOpaque() {
        #expect(PanelOpacity.value(in: UserDefaults(suiteName: UUID().uuidString)!) == 1)
    }
}

/// 테스트용 작은 PNG (크기마다 다른 이미지)
enum NSImageFixtures {
    static func png(size: Int) -> Data? {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )
        return bitmap?.representation(using: .png, properties: [:])
    }
}
