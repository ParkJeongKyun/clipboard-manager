import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var clipboardMonitor: ClipboardMonitor
    @State private var selectedItemId: Date?
    @State private var showDeleteConfirm = false
    @State private var itemToDelete: ClipboardManager.ClipboardItem?
    @State private var searchText = ""
    @State private var autoSaveEnabled = true
    
    var filteredItems: [ClipboardManager.ClipboardItem] {
        let items = clipboardMonitor.clipboardManager.clipboardHistory
        if searchText.isEmpty {
            return items
        }
        return items.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack {
                Text("📋 Clipboard Manager")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                // 자동 저장 토글
                HStack(spacing: 8) {
                    Image(systemName: clipboardMonitor.isMonitoring ? "circle.fill" : "circle")
                        .foregroundColor(clipboardMonitor.isMonitoring ? .green : .gray)
                    
                    Toggle("자동 감시", isOn: $clipboardMonitor.isMonitoring)
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
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .borderBottom()
            
            // 검색창
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                
                TextField("검색...", text: $searchText)
                    .textFieldStyle(.plain)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            .padding()
            
            // 메인 콘텐츠
            if filteredItems.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clipboard")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    
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
                .background(Color(.controlBackgroundColor))
            } else {
                List {
                    ForEach(filteredItems.reversed(), id: \.timestamp) { item in
                        ClipboardItemRow(
                            item: item,
                            isSelected: selectedItemId == item.timestamp,
                            onRestore: { restoreItem(item) },
                            onDelete: {
                                itemToDelete = item
                                showDeleteConfirm = true
                            },
                            onTogglePin: {
                                clipboardMonitor.togglePin(for: item)
                            }
                        )
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
            
            // 푸터
            HStack(spacing: 12) {
                Text("총 \(clipboardMonitor.clipboardManager.clipboardHistory.count)개 항목")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: { showStatistics() }) {
                    Label("통계", systemImage: "chart.bar")
                }
                .buttonStyle(.bordered)
                
                Button(action: { 
                    showDeleteConfirm = true
                    itemToDelete = nil
                }) {
                    Label("모두 삭제", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .borderTop()
        }
        .alert("삭제 확인", isPresented: $showDeleteConfirm) {
            if itemToDelete == nil {
                // 모두 삭제
                Button("삭제", role: .destructive) {
                    clipboardMonitor.clipboardManager.clearHistory()
                }
                Button("취소", role: .cancel) { }
            } else {
                // 항목 삭제
                Button("삭제", role: .destructive) {
                    if let item = itemToDelete {
                        clipboardMonitor.removeItem(item)
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
                // 타임스탬프
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatDate(item.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // 콘텐츠 미리보기
                    Text(item.content.lineCount > 1 ? String(item.content.split(separator: "\n").first ?? "") : item.content)
                        .font(.body)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                // 크기 표시
                Text("\(item.content.count) 글자")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
            }
            
            // 액션 버튼
            HStack(spacing: 8) {
                Button(action: onTogglePin) {
                    Label(item.isPinned ? "고정 해제" : "고정", systemImage: item.isPinned ? "pin.fill" : "pin")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(action: onRestore) {
                    Label("복원", systemImage: "arrow.uturn.backward")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(action: onDelete) {
                    Label("삭제", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(action: { copyToClipboard(item.content) }) {
                    Label("복사", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Spacer()
            }
        }
        .padding(12)
        .background(isSelected ? Color.blue.opacity(0.1) : Color(.controlBackgroundColor))
        .cornerRadius(8)
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
        }
    }
}

struct BorderTop: ViewModifier {
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            Divider()
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
