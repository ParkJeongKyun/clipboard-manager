import SwiftUI
import UniformTypeIdentifiers

// 빠른 선택창과 기록 창에서 같이 쓰는 작은 뷰들

/// 복사한 앱의 아이콘
struct SourceAppIcon: View {
    let bundleID: String?
    var size: CGFloat = 18

    var body: some View {
        Image(nsImage: AppIconProvider.icon(for: bundleID))
            .resizable()
            .frame(width: size, height: size)
    }
}

/// 고정된 항목 표시
struct PinBadge: View {
    var body: some View {
        Image(systemName: "pin.fill")
            .font(.caption)
            .foregroundStyle(.orange)
    }
}

/// "3 lines  120 chars" (한 줄짜리는 줄 수 생략), 이미지는 "Image  1920 × 1080"
struct ItemStats: View {
    let item: ClipboardItem

    var body: some View {
        if let image = item.image {
            Text("Image")
            Text(verbatim: "\(image.pixelWidth) × \(image.pixelHeight)")
        } else {
            if item.lineCount > 1 {
                Text("\(item.lineCount) lines")
            }
            Text("\(item.characterCount) chars")
        }
    }
}

/// 목록 행에 보여줄 이미지 미리보기
struct ImageThumbnail: View {
    let image: ClipboardImage
    var maxHeight: CGFloat = 48

    var body: some View {
        if let thumbnail = ImageThumbnails.thumbnail(for: image) {
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
                // 아이콘처럼 작은 이미지는 늘리지 않는다
                .frame(maxWidth: thumbnail.size.width, maxHeight: min(maxHeight, thumbnail.size.height))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }
}

/// 목록이 비었을 때
struct HistoryEmptyView: View {
    let isSearching: Bool

    var body: some View {
        if isSearching {
            ContentUnavailableView("No Results", systemImage: "magnifyingglass")
        } else {
            ContentUnavailableView(
                "No History",
                systemImage: "doc.on.clipboard",
                description: Text("Copied text and images will appear here.")
            )
        }
    }
}

extension ClipboardItem {
    /// ⌘C로 복사할 때 클립보드에 넣을 내용
    var itemProvider: NSItemProvider {
        switch content {
        case .text(let text): NSItemProvider(object: text as NSString)
        case .image(let image): NSItemProvider(item: image.pngData as NSData, typeIdentifier: UTType.png.identifier)
        }
    }

    /// 고정/고정 해제 버튼 이름
    var pinActionTitle: LocalizedStringKey {
        isPinned ? "Unpin" : "Pin"
    }

    var pinActionSymbol: String {
        isPinned ? "pin.slash" : "pin"
    }
}
