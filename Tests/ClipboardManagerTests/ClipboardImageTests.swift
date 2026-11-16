import AppKit
import Foundation
import Testing
@testable import ClipboardManager

@MainActor
struct ClipboardImageTests {
    private func makeStore(persistence: HistoryPersistence? = nil) -> ClipboardStore {
        ClipboardStore(persistence: persistence, defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    /// seed마다 색이 다른 작은 PNG
    private func makeImage(seed: Int, size: Int = 4) throws -> ClipboardImage {
        let png = try #require(makeBitmap(seed: seed, size: size).representation(using: .png, properties: [:]))
        return try #require(ClipboardImage(pngData: png))
    }

    private func makeBitmap(seed: Int, size: Int) -> NSBitmapImageRep {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let color = NSColor(deviceRed: CGFloat(seed % 256) / 255, green: CGFloat(seed / 256 % 256) / 255, blue: 0.5, alpha: 1)
        for x in 0..<size {
            for y in 0..<size { bitmap.setColor(color, atX: x, y: y) }
        }
        return bitmap
    }

    @Test func readsSizeFromPNG() throws {
        let image = try makeImage(seed: 1, size: 7)
        #expect(image.pixelWidth == 7)
        #expect(image.pixelHeight == 7)
    }

    @Test func convertsTIFFToPNG() throws {
        let tiff = try #require(makeBitmap(seed: 2, size: 5).tiffRepresentation)
        let image = try #require(ClipboardImage(pasteboardData: tiff, type: .tiff))
        #expect(image.pngData.starts(with: [0x89, 0x50, 0x4E, 0x47]))  // PNG 시그니처
        #expect(image.pixelWidth == 5)
    }

    @Test func rejectsNonImageData() {
        #expect(ClipboardImage(pngData: Data("not an image".utf8)) == nil)
    }

    @Test func copyingSameImageAgainMovesItToTop() throws {
        let store = makeStore()
        store.record(try makeImage(seed: 1), sourceBundleID: nil)
        store.record("text", sourceBundleID: nil)
        store.record(try makeImage(seed: 1), sourceBundleID: nil)

        #expect(store.items.count == 2)
        #expect(store.items.first?.image != nil)
    }

    @Test func keepsOnlyRecentUnpinnedImagesWithoutAffectingText() throws {
        let store = makeStore()
        store.record("text", sourceBundleID: nil)
        for seed in 0..<(ClipboardStore.maxUnpinnedImages + 5) {
            store.record(try makeImage(seed: seed), sourceBundleID: nil)
        }

        #expect(store.items.filter { $0.image != nil }.count == ClipboardStore.maxUnpinnedImages)
        #expect(store.items.contains { $0.text == "text" })
    }

    @Test func skipsOversizedImage() throws {
        let store = makeStore()
        // PNG 끝 뒤에 붙은 데이터는 무시되므로, 작은 이미지에 덧붙여 4MB를 넘긴다
        let png = try makeImage(seed: 1).pngData + Data(count: PrivacyRules.maxImageBytes)
        store.record(try #require(ClipboardImage(pngData: png)), sourceBundleID: nil)
        #expect(store.items.isEmpty)
    }

    @Test func turningOffImagesRemovesUnpinnedImagesAndStopsRecording() throws {
        let store = makeStore()
        store.record(try makeImage(seed: 1), sourceBundleID: nil)
        store.record(try makeImage(seed: 2), sourceBundleID: nil)
        store.togglePin(store.items[0].id)

        store.recordsImages = false
        store.record(try makeImage(seed: 3), sourceBundleID: nil)

        #expect(store.items.count == 1)
        #expect(store.items.first?.isPinned == true)
    }

    @Test func appliesIgnoredAppsToImages() throws {
        let store = makeStore()
        store.ignoredBundleIDs = ["com.example.bank"]
        store.record(try makeImage(seed: 1), sourceBundleID: "com.example.bank")
        #expect(store.items.isEmpty)
    }

    @Test func insertsLateImageByCopyTime() throws {
        let store = makeStore()
        let now = Date()
        store.record("newer text", sourceBundleID: nil, at: now)
        // 백그라운드 변환이 끝나 늦게 기록된 이미지
        store.record(try makeImage(seed: 1), sourceBundleID: nil, at: now.addingTimeInterval(-1))

        #expect(store.items.first?.text == "newer text")
        #expect(store.items.last?.image != nil)
    }

    /// Windows처럼 고정한 이미지만 디스크에 남는다
    @Test func persistsOnlyPinnedImages() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardManagerTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let keyStore = InMemoryKeyStore()

        let store = makeStore(persistence: HistoryPersistence(directory: directory, keyStore: keyStore))
        let pinned = try makeImage(seed: 1, size: 9)
        store.record(pinned, sourceBundleID: "com.apple.Preview")
        store.togglePin(store.items[0].id)
        store.record(try makeImage(seed: 2), sourceBundleID: nil)
        store.record("text", sourceBundleID: nil)
        store.flush()

        let reloaded = HistoryPersistence(directory: directory, keyStore: keyStore).load()
        #expect(reloaded.count == 2)
        #expect(reloaded.contains { $0.text == "text" })
        let image = try #require(reloaded.first { $0.image != nil })
        #expect(image.isPinned)
        #expect(image.image == pinned)
        #expect(image.image?.pixelWidth == 9)
        #expect(image.sourceBundleID == "com.apple.Preview")
    }

    @Test func makesSmallThumbnail() throws {
        let image = try makeImage(seed: 3, size: 600)
        let thumbnail = try #require(ImageThumbnails.thumbnail(for: image))
        #expect(max(thumbnail.size.width, thumbnail.size.height) <= CGFloat(ImageThumbnails.maxPixelSize))
    }
}
