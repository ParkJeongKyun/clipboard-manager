import Foundation

/// 클립보드 히스토리 항목
struct ClipboardItem: Identifiable, Codable, Hashable {
    let id: UUID
    let content: String
    /// 마지막으로 복사된 시각 (같은 내용을 다시 복사하면 갱신)
    var timestamp: Date
    var isPinned: Bool
    /// 복사가 일어난 앱의 번들 ID
    var sourceBundleID: String?

    // 긴 텍스트(최대 1MB)에서 매번 다시 계산하면 느린 값들은 만들 때 한 번만 계산한다 (저장하지 않음)
    let characterCount: Int
    let lineCount: Int
    /// 검색용: 앞부분만 소문자로 바꿔 둔 텍스트
    let searchText: String

    /// 검색 대상 길이. 긴 로그 전체를 매번 검색하면 입력할 때마다 화면이 멈춘다
    static let searchableLength = 20_000

    init(
        id: UUID = UUID(),
        content: String,
        timestamp: Date = Date(),
        isPinned: Bool = false,
        sourceBundleID: String? = nil
    ) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
        self.isPinned = isPinned
        self.sourceBundleID = sourceBundleID
        characterCount = content.count
        lineCount = content.utf8.reduce(1) { $1 == UInt8(ascii: "\n") ? $0 + 1 : $0 }
        searchText = content.prefix(Self.searchableLength).lowercased()
    }

    private enum CodingKeys: String, CodingKey {
        case id, content, timestamp, isPinned, sourceBundleID
    }

    // 1.x에서 저장한 기록(id 없음, contentType 있음)도 읽을 수 있도록 직접 디코딩
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            content: try container.decode(String.self, forKey: .content),
            timestamp: try container.decode(Date.self, forKey: .timestamp),
            isPinned: try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false,
            sourceBundleID: try container.decodeIfPresent(String.self, forKey: .sourceBundleID)
        )
    }

    /// 검색어가 (앞부분에) 들어 있는지. query는 소문자로 바꿔서 넘긴다
    func matches(lowercasedQuery query: String) -> Bool {
        searchText.contains(query)
    }
}

// MARK: - 표시용

extension ClipboardItem {
    /// 공백과 줄바꿈을 한 칸으로 줄인 미리보기 (긴 텍스트도 앞부분만 처리)
    var preview: String {
        content.prefix(300)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
