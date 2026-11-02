import SwiftUI

struct QuickPickerView: View {
    @Bindable var model: QuickPickerModel
    let onPaste: (ClipboardItem) -> Void

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        let results = model.results

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search Clipboard", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($isSearchFocused)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            if results.isEmpty {
                HistoryEmptyView(isSearching: !model.query.isEmpty)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                QuickPickerRow(item: item, index: index, isSelected: index == model.selectedIndex)
                                    .id(item.id)
                                    .onTapGesture { onPaste(item) }
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: model.selectedIndex) { _, index in
                        guard results.indices.contains(index) else { return }
                        proxy.scrollTo(results[index].id)
                    }
                }
            }

            Divider()

            Text("↩ Paste   ⌘↩ Copy Only   ⌘1–9 Quick Paste   ⌘P Pin   ⌘⌫ Delete")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
        }
        .frame(width: QuickPanelController.panelSize.width, height: QuickPanelController.panelSize.height)
        .onChange(of: model.focusRequest, initial: true) {
            isSearchFocused = true
        }
    }
}

private struct QuickPickerRow: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SourceAppIcon(bundleID: item.sourceBundleID)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.preview)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    Text(item.timestamp, format: .relative(presentation: .named))
                    ItemStats(item: item)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                if index < 9 {
                    Text(verbatim: "⌘\(index + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                if item.isPinned {
                    PinBadge()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : .clear)
        )
        .contentShape(Rectangle())
    }
}
