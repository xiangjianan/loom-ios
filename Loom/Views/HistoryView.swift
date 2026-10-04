import SwiftUI

struct HistoryView: View {
    var store: LoomStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var pendingSelection: UUID?
    @State private var pendingDeletion: UUID?
    @State private var selectionConfirmation = false
    @State private var deletionConfirmation = false
    private var results: [Conversation] {
        store.conversations.filter {
            search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) ||
            $0.threads.contains { $0.messages.contains { $0.content.localizedCaseInsensitiveContains(search) } }
        }.sorted { $0.updated > $1.updated }
    }
    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { conversation in
                    Button {
                        if store.isWorking, conversation.id != store.selectedConversation {
                            pendingSelection = conversation.id; selectionConfirmation = true
                        } else { store.selectConversation(conversation.id); dismiss() }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: conversation.id == store.selectedConversation ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                                .foregroundStyle(.indigo).padding(.top, 3)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(conversation.title).foregroundStyle(.primary).lineLimit(2)
                                Text("\(conversation.threads.count) 个模型 · \(conversation.round) 轮").font(.caption).foregroundStyle(.secondary)
                                Text(conversation.updated, style: .date).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }.padding(.vertical, 7)
                    }
                    .accessibilityIdentifier("history-row-\(conversation.id)")
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("删除") {
                            pendingDeletion = conversation.id
                            deletionConfirmation = true
                        }.tint(.red).accessibilityIdentifier("history-delete-\(conversation.id)")
                    }
                }
            }
            .overlay { if results.isEmpty { ContentUnavailableView.search(text: search) } }
            .searchable(text: $search, prompt: "搜索对话和回答")
            .navigationTitle("历史对话").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .confirmationDialog("停止当前生成并打开这段对话？", isPresented: $selectionConfirmation, titleVisibility: .visible) {
                Button("停止并打开", role: .destructive) {
                    if let id = pendingSelection { store.selectConversation(id); dismiss() }
                }
            }
        }
        .alert("删除这段对话？", isPresented: $deletionConfirmation) {
            Button("取消", role: .cancel) { pendingDeletion = nil }
            Button("删除", role: .destructive) {
                if let id = pendingDeletion { store.deleteConversation(id) }
                pendingDeletion = nil
            }
        } message: {
            Text("这段对话及其高亮将一并删除。")
        }
    }
}
