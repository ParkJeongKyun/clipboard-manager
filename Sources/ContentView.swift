import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var clipboardMonitor: ClipboardMonitor
    @State private var showDeleteConfirm = false
    @State private var itemToDelete: ClipboardManager.ClipboardItem?
    @State private var searchText = ""
    @State private var selectedTab: TabType = .recent
    
    enum TabType {
        case recent
        case pinned
    }
    
    var filteredItems: [ClipboardManager.ClipboardItem] {
        let items = clipboardMonitor.clipboardManager.clipboardHistory
        if searchText.isEmpty {
            return items
        }
        return items.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
    }
    
    var regularItems: [ClipboardManager.ClipboardItem] {
        filteredItems.filter { !$0.isPinned }.reversed()
    }
    
    var pinnedItems: [ClipboardManager.ClipboardItem] {
        filteredItems.filter { $0.isPinned }.reversed()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 18))
                        .foregroundColor(.cyan)
                    Text("Clipboard Manager")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    Image(systemName: clipboardMonitor.isMonitoring ? "circle.fill" : "circle")
                        .foregroundColor(clipboardMonitor.isMonitoring ? .green : .gray)
                    
                    Toggle("감시", isOn: $clipboardMonitor.isMonitoring)
                        .onChange(of: clipboardMonitor.isMonitoring) { newValue in
                            if newValue {
                                clipboardMonitor.startMonitoring()
                            } else {
                                clipboardMonitor.stopMonitoring()
                            }
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.1))
                .cornerRadius(6)
            }
            .padding()
            .background(Color(red: 0.11, green: 0.11, blue: 0.12))
            .borderBottom()
            
            // 검색창
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                
                TextField("검색...", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.08))
            .cornerRadius(8)
            .padding()
            
            // 탭 선택
            HStack(spacing: 0) {
                VStack {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                        Text("최근 항목 (\(regularItems.count))")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(selectedTab == .recent ? Color.cyan.opacity(0.2) : Color.clear)
                    .foregroundColor(selectedTab == .recent ? .cyan : .gray)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedTab = .recent
                }
                
                Divider()
                    .frame(height: 30)
                
                VStack {
                    HStack(spacing: 6) {
                        Image(systemName: "pin.fill")
                        Text("고정됨 (\(pinnedItems.count))")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(selectedTab == .pinned ? Color.orange.opacity(0.2) : Color.clear)
                    .foregroundColor(selectedTab == .pinned ? .orange : .gray)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedTab = .pinned
                }
            }
            .background(Color.white.opacity(0.04))
            .borderBottom()
            
            // 메인 콘텐츠
            if filteredItems.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 48))
                        .foregroundColor(.cyan)
                    
                    Text(searchText.isEmpty ? "저장된 항목이 없습니다" : "검색 결과가 없습니다")
                        .font(.headline)
                        .foregroundColor(.gray)
                    
                    if searchText.isEmpty {
                        Text("클립보드에 내용을 복사하면 자동으로 저장됩니다")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.11, green: 0.11, blue: 0.12))
            } else {
                List {
                    // 최근 항목 탭
                    if selectedTab == .recent {
                        if regularItems.isEmpty {
                            VStack {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.cyan)
                                Text("최근 항목이 없습니다")
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            ForEach(regularItems, id: \.timestamp) { item in
                                ClipboardItemRow(
                                    item: item,
                                    isSelected: false,
                                    onRestore: { restoreItem(item) },
                                    onDelete: {
                                        itemToDelete = item
                                        showDeleteConfirm = true
                                    },
                                    onTogglePin: {
                                        clipboardMonitor.togglePin(for: item)
                                        // 상단바 메뉴 즉시 업데이트
                                        NotificationCenter.default.post(name: Notification.Name("clipboardMonitorDidChange"), object: nil)
                                    }
                                )
                            }
                        }
                    }
                    
                    // 고정된 항목 탭
                    if selectedTab == .pinned {
                        if pinnedItems.isEmpty {
                            VStack {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.orange)
                                Text("고정된 항목이 없습니다")
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            ForEach(pinnedItems, id: \.timestamp) { item in
                                ClipboardItemRow(
                                    item: item,
                                    isSelected: false,
                                    onRestore: { restoreItem(item) },
                                    onDelete: {
                                        itemToDelete = item
                                        showDeleteConfirm = true
                                    },
                                    onTogglePin: {
                                        clipboardMonitor.togglePin(for: item)
                                        // 상단바 메뉴 즉시 업데이트
                                        NotificationCenter.default.post(name: Notification.Name("clipboardMonitorDidChange"), object: nil)
                                    }
                                )
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: false))
            }
            
            // 푸터
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard")
                        .foregroundColor(.cyan)
                    Text("총 \(clipboardMonitor.clipboardManager.clipboardHistory.count)개")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: { showStatistics() }) {
                    Label("통계", systemImage: "chart.bar")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                
                Button(action: { 
                    showDeleteConfirm = true
                    itemToDelete = nil
                }) {
                    Label("삭제", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(red: 0.11, green: 0.11, blue: 0.12))
            .borderTop()
        }
        .alert("삭제 확인", isPresented: $showDeleteConfirm) {
            if itemToDelete == nil {
                // 모두 삭제
                Button("삭제", role: .destructive) {
                    clipboardMonitor.clipboardManager.clearHistory()
                    // 상단바 메뉴 즉시 업데이트
                    NotificationCenter.default.post(name: Notification.Name("clipboardMonitorDidChange"), object: nil)
                }
                Button("취소", role: .cancel) { }
            } else {
                // 항목 삭제
                Button("삭제", role: .destructive) {
                    if let item = itemToDelete {
                        clipboardMonitor.removeItem(item)
                        // 상단바 메뉴 즉시 업데이트
                        NotificationCenter.default.post(name: Notification.Name("clipboardMonitorDidChange"), object: nil)
                    }
                }
                Button("취소", role: .cancel) { }
            }
        } message: {
            if itemToDelete == nil {
                Text("모든 클립보드 히스토리를 삭제하시겠습니까?")
            } else {
                Text("이 항목을 삭제하시겠습니까?")
            }
        }
        .onAppear {
            clipboardMonitor.startMonitoring()
        }
    }
    
    private func restoreItem(_ item: ClipboardManager.ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.content, forType: .string)
        
        // 사용자 피드백
        showNotification("복원됨", "클립보드에 복원되었습니다")
    }
    
    private func showStatistics() {
        let history = clipboardMonitor.clipboardManager.clipboardHistory
        
        var stats = "📊 클립보드 히스토리 통계\n\n"
        stats += "총 항목: \(history.count)/100\n"
        
        if !history.isEmpty {
            let totalLength = history.map { $0.content.count }.reduce(0, +)
            let avgLength = totalLength / history.count
            stats += "평균 길이: \(avgLength) 글자\n"
            
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            stats += "가장 오래된: \(formatter.string(from: history.first!.timestamp))\n"
            stats += "가장 최근: \(formatter.string(from: history.last!.timestamp))"
        }
        
        let alert = NSAlert()
        alert.messageText = "클립보드 통계"
        alert.informativeText = stats
        alert.addButton(withTitle: "확인")
        alert.runModal()
    }
    
    private func showNotification(_ title: String, _ message: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = message
        NSUserNotificationCenter.default.deliver(notification)
    }
}

struct ClipboardItemRow: View {
    let item: ClipboardManager.ClipboardItem
    let isSelected: Bool
    let onRestore: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // 아이콘
                Image(systemName: item.isPinned ? "pin.fill" : "doc.on.clipboard")
                    .foregroundColor(item.isPinned ? .orange : .cyan)
                    .frame(width: 20)
                
                // 타임스탬프와 콘텐츠
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatDate(item.timestamp))
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    // 콘텐츠 미리보기
                    Text(item.content.lineCount > 1 ? String(item.content.split(separator: "\n").first ?? "") : item.content)
                        .font(.body)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                // 크기 표시
                Text("\(item.content.count)")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(4)
            }
            
            // 액션 버튼
            HStack(spacing: 6) {
                Button(action: onTogglePin) {
                    Image(systemName: item.isPinned ? "pin.slash.fill" : "pin")
                        .font(.caption)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(action: onRestore) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(action: { copyToClipboard(item.content) }) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Spacer()
            }
        }
        .padding(12)
        .background(isSelected ? Color.cyan.opacity(0.15) : Color.white.opacity(0.04))
        .cornerRadius(8)
        .listRowSeparator(.hidden)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm:ss"
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "어제 HH:mm"
        } else {
            formatter.dateFormat = "MM-dd HH:mm"
        }
        
        return formatter.string(from: date)
    }
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

// 확장
extension String {
    var lineCount: Int {
        self.split(separator: "\n").count
    }
}

// 뷰 수정자
struct BorderBottom: ViewModifier {
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
            Divider()
                .background(Color.white.opacity(0.1))
        }
    }
}

struct BorderTop: ViewModifier {
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.1))
            content
        }
    }
}

extension View {
    func borderBottom() -> some View {
        modifier(BorderBottom())
    }
    
    func borderTop() -> some View {
        modifier(BorderTop())
    }
}

#Preview {
    ContentView()
        .environmentObject(ClipboardMonitor.shared)
}
