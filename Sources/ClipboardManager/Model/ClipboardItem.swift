import Foundation

/// 클립보드 히스토리 항목
struct ClipboardItem: Identifiable, Codable, Hashable {
    enum Content: Hashable {
        case text(String)
        case image(ClipboardImage)
    }

    let id: UUID
    let content: Content
    /// 마지막으로 복사된 시각 (같은 내용을 다시 복사하면 갱신)
    var timestamp: Date
    var isPinned: Bool
    /// 복사가 일어난 앱의 번들 ID
    var sourceBundleID: String?

    // 긴 텍스트(최대 1MB)에서 매번 다시 계산하면 느린 값들은 만들 때 한 번만 계산한다 (저장하지 않음)
    let characterCount: Int
    let lineCount: Int
    /// 검색용: 앞부분만 소문자로 바꿔 둔 텍스트 (이미지는 빈 문자열)
    let searchText: String

    /// 검색 대상 길이. 긴 로그 전체를 매번 검색하면 입력할 때마다 화면이 멈춘다
    static let searchableLength = 20_000

    init(
        id: UUID = UUID(),
        content: Content,
        timestamp: Date = Date(),
        isPinned: Bool = false,
        sourceBundleID: String? = nil
    ) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
        self.isPinned = isPinned
        self.sourceBundleID = sourceBundleID
        switch content {
        case .text(let text):
            characterCount = text.count
            lineCount = text.utf8.reduce(1) { $1 == UInt8(ascii: "\n") ? $0 + 1 : $0 }
            searchText = text.prefix(Self.searchableLength).lowercased()
        case .image:
            characterCount = 0
            lineCount = 0
            searchText = ""
        }
    }

    init(
        id: UUID = UUID(),
        text: String,
        timestamp: Date = Date(),
        isPinned: Bool = false,
        sourceBundleID: String? = nil
    ) {
        self.init(id: id, content: .text(text), timestamp: timestamp, isPinned: isPinned, sourceBundleID: sourceBundleID)
    }

    var text: String? {
        if case .text(let text) = content { text } else { nil }
    }

    var image: ClipboardImage? {
        if case .image(let image) = content { image } else { nil }
    }

    /// 메모리/저장 크기 제한 계산용
    var byteCount: Int {
        switch content {
        case .text(let text): text.utf8.count
        case .image(let image): image.pngData.count
        }
    }

    /// 검색어가 (앞부분에) 들어 있는지. query는 소문자로 바꿔서 넘긴다
    func matches(lowercasedQuery query: String) -> Bool {
        searchText.contains(query)
    }

    // MARK: - Codable

    // 텍스트는 예전과 같이 content 키에 문자열로, 이미지는 image 키에 저장한다
    private enum CodingKeys: String, CodingKey {
        case id, content, image, timestamp, isPinned, sourceBundleID
    }

    // 1.x에서 저장한 기록(id 없음, contentType 있음)도 읽을 수 있도록 직접 디코딩
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let content: Content = if let image = try container.decodeIfPresent(ClipboardImage.self, forKey: .image) {
            .image(image)
        } else {
            .text(try container.decode(String.self, forKey: .content))
        }
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            content: content,
            timestamp: try container.decode(Date.self, forKey: .timestamp),
            isPinned: try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false,
            sourceBundleID: try container.decodeIfPresent(String.self, forKey: .sourceBundleID)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        switch content {
        case .text(let text): try container.encode(text, forKey: .content)
        case .image(let image): try container.encode(image, forKey: .image)
        }
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(sourceBundleID, forKey: .sourceBundleID)
    }
}

// MARK: - 표시용

extension ClipboardItem {
    /// 공백과 줄바꿈을 한 칸으로 줄인 미리보기 (긴 텍스트도 앞부분만 처리)
    var preview: String {
        guard let text else { return "" }
        return text.prefix(300)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
