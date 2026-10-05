import SwiftUI

struct ConversationDrawer: View {
    var store: LoomStore
    var newConversation: () -> Void
    var close: () -> Void
    var settings: () -> Void
    @State private var search = ""
    @State private var searching = false
    @FocusState private var searchFocused: Bool
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
        GlassEffectContainer(spacing: 16) {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Text("Loom").font(.title2.bold())
                Spacer()
                Button {
                    withAnimation(.smooth(duration: 0.2)) { searching = true }
                    searchFocused = true
                } label: {
                    Image(systemName: "magnifyingglass").font(.system(size: 19))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.glass).buttonBorderShape(.circle).foregroundStyle(.primary)
                .accessibilityLabel("搜索聊天")
                .accessibilityIdentifier("drawer-search-button")
            }.padding(.horizontal, 20)
            if searching {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("搜索会话", text: $search)
                        .focused($searchFocused)
                        .submitLabel(.search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("drawer-search")
                }
                .padding(12)
                .glassEffect(.regular.interactive(), in: .capsule)
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Text("历史会话").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
            List {
                ForEach(conversations) { conversation in
                    Button {
                        if store.isWorking, conversation.id != store.selectedConversation {
                            pendingSelection = conversation.id; confirmSelection = true
                        } else { store.selectConversation(conversation.id); close() }
                    } label: {
                        Text(conversation.title)
                            .font(.body).foregroundStyle(.primary).lineLimit(2)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .accessibilityIdentifier("history-row-\(conversation.id)")
                    .listRowSeparator(.hidden)
                    .listRowBackground(conversation.id == store.selectedConversation ? Color.primary.opacity(0.06) : Color.clear)
                    .accessibilityAddTraits(conversation.id == store.selectedConversation ? .isSelected : [])
                    .contextMenu {
                        Button("删除会话", systemImage: "trash", role: .destructive) {
                            pendingDeletion = conversation.id; confirmDeletion = true
                        }
                        .accessibilityIdentifier("history-delete-\(conversation.id)")
                    }
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.never)
            .overlay { if conversations.isEmpty { if search.isEmpty { ContentUnavailableView("暂无聊天记录", systemImage: "bubble.left.and.bubble.right", description: Text("点击左下角开始新聊天")) } else { ContentUnavailableView.search(text: search) } } }
            Divider().padding(.horizontal, 20)
            HStack {
                Button(action: newConversation) {
                    Label("聊天", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.semibold)).padding(.horizontal, 12).frame(minHeight: 32)
                }
                .buttonStyle(.glassProminent).tint(.blue)
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier("drawer-new-conversation")
                Spacer()
                Button(action: settings) {
                    Image(systemName: "gearshape").font(.system(size: 20)).frame(width: 32, height: 32)
                }
                .buttonStyle(.glass).buttonBorderShape(.circle)
                .accessibilityLabel("设置")
                .accessibilityIdentifier("drawer-settings")
            }.padding(.horizontal, 20)

        }
        .padding(.top, 8).padding(.bottom, 16)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    guard searchFocused,
                          value.translation.height > 32,
                          value.translation.height > abs(value.translation.width) else { return }
                    searchFocused = false
                }
        )
        .onChange(of: searchFocused) { _, focused in
            if !focused {
                withAnimation(.smooth(duration: 0.2)) { searching = false }
                search = ""
            }
        }
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
