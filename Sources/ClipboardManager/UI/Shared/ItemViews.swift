import SwiftUI

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

/// "3 lines  120 chars" (한 줄짜리는 줄 수 생략)
struct ItemStats: View {
    let item: ClipboardItem

    var body: some View {
        if item.lineCount > 1 {
            Text("\(item.lineCount) lines")
        }
        Text("\(item.characterCount) chars")
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
                description: Text("Copied text will appear here.")
            )
        }
    }
}

extension ClipboardItem {
    /// 고정/고정 해제 버튼 이름
    var pinActionTitle: LocalizedStringKey {
        isPinned ? "Unpin" : "Pin"
    }

    var pinActionSymbol: String {
        isPinned ? "pin.slash" : "pin"
    }
}
