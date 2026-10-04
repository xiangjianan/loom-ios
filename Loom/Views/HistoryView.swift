import SwiftUI

struct HistoryView: View {
    var store: LoomStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var pendingSelection: UUID?
    @State private var pendingDeletion: UUID?
    @State private var selectionConfirmation = false
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("删除") { withAnimation(.easeInOut(duration: 0.18)) { pendingDeletion = conversation.id } }.tint(.red).accessibilityIdentifier("history-delete-\(conversation.id)")
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
        .accessibilityHidden(pendingDeletion != nil)
        .overlay {
            if let id = pendingDeletion {
                DeleteConversationConfirmation {
                    withAnimation(.easeInOut(duration: 0.18)) { pendingDeletion = nil }
                } delete: {
                    store.deleteConversation(id)
                    withAnimation(.easeInOut(duration: 0.18)) { pendingDeletion = nil }
                }.transition(.opacity).zIndex(1)
            }
        }
    }
}

private struct DeleteConversationConfirmation: View {
    var cancel: () -> Void
    var delete: () -> Void
    @AccessibilityFocusState private var focused: Bool
    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Text("删除这段对话？").font(.headline).accessibilityFocused($focused)
                    Text("这段对话及其高亮将一并删除。").font(.subheadline).foregroundStyle(.secondary)
                }.multilineTextAlignment(.center).padding(24)
                Divider()
                HStack(spacing: 0) {
                    Button("取消", role: .cancel, action: cancel).accessibilityIdentifier("cancel-delete").frame(maxWidth: .infinity, minHeight: 50)
                    Divider().frame(height: 50)
                    Button("删除", role: .destructive, action: delete).accessibilityIdentifier("confirm-delete").foregroundStyle(.red).frame(maxWidth: .infinity, minHeight: 50)
                }.buttonStyle(.plain)
            }
            .frame(maxWidth: 300)
            .background(.regularMaterial, in: .rect(cornerRadius: 24))
            .padding(24)
            .accessibilityAddTraits(.isModal)
        }.onAppear { focused = true }
    }
}
