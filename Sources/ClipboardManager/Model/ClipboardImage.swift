import AppKit
import CryptoKit
import ImageIO

/// 클립보드에 복사된 이미지. 원본 화질 그대로 PNG로 보관한다.
struct ClipboardImage: Codable, Hashable, Sendable {
    let pngData: Data
    let pixelWidth: Int
    let pixelHeight: Int
    /// 같은 이미지를 다시 복사했는지 비교하는 값 (PNG 데이터의 SHA-256)
    let digest: String

    init?(pngData: Data) {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        self.pngData = pngData
        pixelWidth = width
        pixelHeight = height
        digest = SHA256.hash(data: pngData).map { String(format: "%02x", $0) }.joined()
    }

    /// 클립보드에서 읽은 PNG 또는 TIFF 데이터로 만든다. TIFF는 PNG로 바꾼다 (TIFF는 압축이 없어 매우 크다).
    init?(pasteboardData data: Data, type: NSPasteboard.PasteboardType) {
        if type == .png {
            self.init(pngData: data)
        } else if let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) {
            self.init(pngData: png)
        } else {
            return nil
        }
    }

    // 4MB 이미지끼리 바이트 단위로 비교하지 않도록 digest만 비교 (SwiftUI가 뷰를 갱신할 때도 비교함)
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.digest == rhs.digest }
    func hash(into hasher: inout Hasher) { hasher.combine(digest) }

    // MARK: - Codable
    //
    // 기록 파일에는 digest만 적고, 이미지 내용은 HistoryPersistence가 이미지마다 따로 암호화해 저장한다.
    // (기록 파일에 같이 넣으면 고정 이미지가 많을 때 복사할 때마다 수십 MB를 다시 써야 했다)

    /// digest로 이미지 내용을 읽어 오는 함수. HistoryPersistence가 decoder.userInfo로 넘긴다
    typealias Loader = (String) throws -> Data
    static let loaderKey = CodingUserInfoKey(rawValue: "ClipboardImage.loader")!

    private enum CodingKeys: String, CodingKey { case digest, png }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let data: Data
        if let png = try container.decodeIfPresent(Data.self, forKey: .png) {
            data = png  // 0.1.0은 기록 파일 안에 이미지를 같이 저장했다
        } else {
            let digest = try container.decode(String.self, forKey: .digest)
            guard let load = decoder.userInfo[Self.loaderKey] as? Loader else {
                throw DecodingError.dataCorruptedError(forKey: .digest, in: container, debugDescription: "이미지를 읽을 방법 없음")
            }
            data = try load(digest)
        }
        guard let image = ClipboardImage(pngData: data) else {
            throw DecodingError.dataCorruptedError(forKey: .png, in: container, debugDescription: "이미지 데이터 오류")
        }
        self = image
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(digest, forKey: .digest)
    }
}

/// 목록에 보여줄 작은 미리보기. 원본(최대 4MB)을 행마다 디코딩하면 스크롤이 버벅여서 한 번 만들어 둔다.
enum ImageThumbnails {
    static let maxPixelSize = 240

    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 100
        return cache
    }()

    /// 스레드 안전 (NSCache, ImageIO)
    static func thumbnail(for image: ClipboardImage) -> NSImage? {
        let key = image.digest as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let source = CGImageSourceCreateWithData(image.pngData as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(thumbnail, forKey: key)
        return thumbnail
    }
}
