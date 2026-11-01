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
                    Section("고정됨") {
                        ForEach(pinned) { HistoryRow(item: $0) }
                    }
                }
                Section("최근") {
                    ForEach(recent) { HistoryRow(item: $0) }
                }
            }
            .contextMenu(forSelectionType: ClipboardItem.ID.self) { ids in
                if let id = ids.first, let item = store.item(withID: id) {
                    Button("복사") { copy(item) }
                    Button(item.isPinned ? "고정 해제" : "고정") { store.togglePin(id) }
                    Divider()
                    Button("삭제", role: .destructive) { store.remove(id) }
                }
            } primaryAction: { ids in
                // 더블클릭 / 엔터 → 복사
                if let id = ids.first, let item = store.item(withID: id) { copy(item) }
            }
            .onDeleteCommand {
                if let selection { store.remove(selection) }
            }
            .onCopyCommand {
                guard let selection, let item = store.item(withID: selection) else { return [] }
                markCopied(item)
                return [NSItemProvider(object: item.content as NSString)]
            }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "기록이 없습니다" : "검색 결과 없음",
                        systemImage: "doc.on.clipboard"
                    )
                }
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            if let selection, let item = store.item(withID: selection) {
                HistoryDetailView(
                    item: item,
                    isCopied: copiedID == item.id,
                    onCopy: { copy(item) },
                    onTogglePin: { store.togglePin(item.id) },
                    onDelete: { store.remove(item.id) }
                )
            } else {
                ContentUnavailableView("항목을 선택하세요", systemImage: "text.cursor")
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "검색")
        .navigationTitle("클립보드 기록")
        .navigationSubtitle("\(store.items.count)개 · 고정 \(store.pinnedItems.count)개")
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $store.isMonitoring) {
                    Label(
                        store.isMonitoring ? "기록 중" : "일시정지됨",
                        systemImage: store.isMonitoring ? "record.circle" : "pause.circle"
                    )
                }
                .help(store.isMonitoring ? "클립보드 기록 일시정지" : "클립보드 기록 다시 시작")

                Button {
                    showClearConfirm = true
                } label: {
                    Label("모두 지우기", systemImage: "trash")
                }
                .help("고정되지 않은 기록 모두 지우기")
                .disabled(store.recentItems.isEmpty)
            }
        }
        .confirmationDialog("고정되지 않은 기록을 모두 지울까요?", isPresented: $showClearConfirm) {
            Button("모두 지우기", role: .destructive) { store.clearUnpinned() }
        } message: {
            Text("고정된 항목은 유지됩니다.")
        }
        .frame(minWidth: 640, minHeight: 400)
        // 창이 열려 있는 동안만 Dock 아이콘과 앱 메뉴를 보여준다
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
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
            Image(nsImage: AppIconProvider.icon(for: item.sourceBundleID))
                .resizable()
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview)
                    .lineLimit(2)
                Text(item.timestamp, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct HistoryDetailView: View {
    let item: ClipboardItem
    let isCopied: Bool
    let onCopy: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Label {
                    Text(AppIconProvider.appName(for: item.sourceBundleID) ?? "알 수 없는 앱")
                } icon: {
                    Image(nsImage: AppIconProvider.icon(for: item.sourceBundleID))
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                Text(item.timestamp, format: .dateTime.month().day().hour().minute())
                Text("\(item.content.count)자 · \(item.lineCount)줄")
                Spacer()
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding()

            Divider()

            ScrollView {
                Text(item.content)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: onTogglePin) {
                    Label(item.isPinned ? "고정 해제" : "고정", systemImage: item.isPinned ? "pin.slash" : "pin")
                }
                Button(action: onDelete) {
                    Label("삭제", systemImage: "xmark.bin")
                }
                Button(action: onCopy) {
                    Label(isCopied ? "복사됨" : "복사", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                }
                .help("복사 (⌘C)")
            }
        }
    }
}
