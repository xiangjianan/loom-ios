import SwiftUI

struct ConversationDrawer: View {
    var store: LoomStore
    var newConversation: () -> Void
    var close: () -> Void
    var settings: () -> Void
    var backup: () -> Void
    @State private var search = ""
    @State private var pendingSelection: UUID?
    @State private var pendingDeletion: UUID?
    @State private var confirmSelection = false
    @State private var confirmDeletion = false

    private var conversations: [Conversation] {
        store.conversations.filter {
            search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) ||
            $0.threads.contains { $0.messages.contains { $0.content.localizedCaseInsensitiveContains(search) } }
        }.sorted { $0.updated > $1.updated }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("会话").font(.title2.bold())
                Spacer()
                Button(action: close) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                    .accessibilityLabel("关闭会话侧栏")
                    .accessibilityIdentifier("drawer-close")
            }.padding(.horizontal, 20)
            Button(action: newConversation) {
                Label("创建新会话", systemImage: "square.and.pencil")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent).tint(.indigo)
            .accessibilityIdentifier("drawer-new-conversation")
            .padding(.horizontal, 20)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索会话", text: $search)
                    .accessibilityIdentifier("drawer-search")
            }.padding(12).background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
                .padding(.horizontal, 20)
            Text("历史会话").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
            List {
                ForEach(conversations) { conversation in
                    Button {
                        if store.isWorking, conversation.id != store.selectedConversation {
                            pendingSelection = conversation.id; confirmSelection = true
                        } else { store.selectConversation(conversation.id); close() }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: conversation.id == store.selectedConversation ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                                .foregroundStyle(.indigo)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(conversation.title).foregroundStyle(.primary).lineLimit(2)
                                Text("\(conversation.threads.count) 个模型 · \(conversation.round) 轮")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityIdentifier("history-row-\(conversation.id)")
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("删除") { pendingDeletion = conversation.id; confirmDeletion = true }
                            .tint(.red).accessibilityIdentifier("history-delete-\(conversation.id)")
                    }
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            .overlay { if conversations.isEmpty { ContentUnavailableView.search(text: search) } }
            Divider().padding(.horizontal, 20)
            HStack(spacing: 12) {
                Button(action: settings) { Label("模型设置", systemImage: "gearshape").frame(maxWidth: .infinity, minHeight: 44) }
                    .accessibilityIdentifier("drawer-settings")
                Button(action: backup) { Label("备份", systemImage: "externaldrive").frame(maxWidth: .infinity, minHeight: 44) }
                    .accessibilityIdentifier("drawer-backup")
            }.buttonStyle(.glass).padding(.horizontal, 20)
        }
        .padding(.top, 8).padding(.bottom, 16)
        .accessibilityAction(.escape, close)
        .confirmationDialog("停止当前生成并打开这段对话？", isPresented: $confirmSelection, titleVisibility: .visible) {
            Button("停止并打开", role: .destructive) {
                if let id = pendingSelection { store.selectConversation(id); close() }
            }
        }
        .alert("删除这段对话？", isPresented: $confirmDeletion) {
            Button("取消", role: .cancel) { pendingDeletion = nil }
            Button("删除", role: .destructive) {
                if let id = pendingDeletion { store.deleteConversation(id) }
                pendingDeletion = nil
            }
        } message: { Text("这段对话及其高亮将一并删除。") }
    }
}
