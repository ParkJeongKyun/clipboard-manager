import SwiftUI

/// 전체 기록을 둘러보고 관리하는 메인 창
struct HistoryWindowView: View {
    @Bindable var store: ClipboardStore

    @State private var searchText = ""
    @State private var selection: ClipboardItem.ID?
    @State private var showClearConfirm = false
    @State private var copiedID: ClipboardItem.ID?

    var body: some View {
        let results = store.search(searchText)
        let pinned = results.filter(\.isPinned)
        let recent = results.filter { !$0.isPinned }

        NavigationSplitView {
            List(selection: $selection) {
                if !pinned.isEmpty {
                    Section("Pinned") {
                        ForEach(pinned) { HistoryRow(item: $0) }
                    }
                }
                Section("Recent") {
                    ForEach(recent) { HistoryRow(item: $0) }
                }
            }
            .contextMenu(forSelectionType: ClipboardItem.ID.self) { ids in
                if let item = item(in: ids) {
                    Button("Copy") { copy(item) }
                    Button(item.pinActionTitle) { store.togglePin(item.id) }
                    Divider()
                    Button("Delete", role: .destructive) { store.remove(item.id) }
                }
            } primaryAction: { ids in
                // 더블클릭 / 엔터 → 복사
                if let item = item(in: ids) { copy(item) }
            }
            .onDeleteCommand {
                if let item = selectedItem { store.remove(item.id) }
            }
            .onCopyCommand {
                guard let item = selectedItem else { return [] }
                markCopied(item)
                return [NSItemProvider(object: item.content as NSString)]
            }
            .overlay {
                if results.isEmpty {
                    HistoryEmptyView(isSearching: !searchText.isEmpty)
                }
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            if let item = selectedItem {
                HistoryDetailView(
                    item: item,
                    isCopied: copiedID == item.id,
                    onCopy: { copy(item) },
                    onTogglePin: { store.togglePin(item.id) },
                    onDelete: { store.remove(item.id) }
                )
            } else {
                ContentUnavailableView("Select an Item", systemImage: "text.cursor")
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
        .navigationTitle("Clipboard History")
        .navigationSubtitle("\(store.items.count) items · \(store.pinnedItems.count) pinned")
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $store.isMonitoring) {
                    Label(
                        store.isMonitoring ? LocalizedStringKey("Recording") : "Paused",
                        systemImage: store.isMonitoring ? "record.circle" : "pause.circle"
                    )
                }
                .help(store.isMonitoring ? LocalizedStringKey("Pause clipboard recording") : "Resume clipboard recording")

                Button {
                    showClearConfirm = true
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
                .help("Clear all unpinned history")
                .disabled(store.recentItems.isEmpty)
            }
        }
        .confirmationDialog("Clear all unpinned history?", isPresented: $showClearConfirm) {
            Button("Clear All", role: .destructive) { store.clearUnpinned() }
        } message: {
            Text("Pinned items will be kept.")
        }
        .frame(minWidth: 640, minHeight: 400)
    }

    private var selectedItem: ClipboardItem? {
        selection.flatMap(store.item(withID:))
    }

    private func item(in ids: Set<ClipboardItem.ID>) -> ClipboardItem? {
        ids.first.flatMap(store.item(withID:))
    }

    private func copy(_ item: ClipboardItem) {
        PasteService.copy(item.content)
        markCopied(item)
    }

    /// 상세 화면의 복사 버튼에 잠깐 "복사됨" 표시
    private func markCopied(_ item: ClipboardItem) {
        copiedID = item.id
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedID == item.id { copiedID = nil }
        }
    }
}

private struct HistoryRow: View {
    let item: ClipboardItem

    var body: some View {
        HStack(spacing: 10) {
            SourceAppIcon(bundleID: item.sourceBundleID)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview)
                    .lineLimit(2)
                Text(item.timestamp, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if item.isPinned {
                PinBadge()
            }
        }
        .padding(.vertical, 2)
    }
}

private struct HistoryDetailView: View {
    /// 상세 화면에 그릴 최대 글자 수 (2만 자 ≈ 0.1초)
    private static let displayLimit = 20_000

    let item: ClipboardItem
    let isCopied: Bool
    let onCopy: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Label {
                    AppIconProvider.appName(for: item.sourceBundleID).map(Text.init(verbatim:)) ?? Text("Unknown App")
                } icon: {
                    SourceAppIcon(bundleID: item.sourceBundleID, size: 16)
                }
                Text(item.timestamp, format: .dateTime.month().day().hour().minute())
                ItemStats(item: item)
                Spacer()
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // 1MB 텍스트를 통째로 그리면 2초 넘게 멈춘다 → 앞부분만 표시 (복사는 전체)
                    Text(item.content.prefix(Self.displayLimit))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    if item.characterCount > Self.displayLimit {
                        Text("Showing the first \(Self.displayLimit) characters. Copy to get the full text.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: onTogglePin) {
                    Label(item.pinActionTitle, systemImage: item.pinActionSymbol)
                }
                Button(action: onDelete) {
                    Label("Delete", systemImage: "xmark.bin")
                }
                Button(action: onCopy) {
                    Label(isCopied ? LocalizedStringKey("Copied") : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                }
                .help("Copy (⌘C)")
            }
        }
    }
}
