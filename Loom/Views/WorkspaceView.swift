import SwiftUI

private enum WorkspaceSheet: String, Identifiable { case settings, history; var id: String { rawValue } }

struct WorkspaceView: View {
    @Bindable var store: LoomStore
    @State private var sheet: WorkspaceSheet?
    @State private var showNewConfirmation = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var tabsNamespace

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let parallel = geometry.size.width >= 700
                ZStack {
                    Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                    if parallel { parallelBoard(width: geometry.size.width) }
                    else { phoneBoard }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    HStack(spacing: 8) {
                        modelTabs
                        Menu {
                            Button("新对话", systemImage: "square.and.pencil") {
                                if store.isWorking { showNewConfirmation = true } else { store.newConversation() }
                            }
                            Button("历史对话", systemImage: "clock") { sheet = .history }
                            Button("模型设置", systemImage: "slider.horizontal.3") { sheet = .settings }
                        } label: {
                            Image(systemName: "ellipsis").font(.headline).frame(width: 44, height: 44)
                                .glassEffect(.regular.interactive(), in: .circle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("更多操作").accessibilityIdentifier("workspace-menu")
                        .padding(.trailing, 12)
                    }.padding(.vertical, 4)

                }
                .safeAreaInset(edge: .bottom, spacing: 0) { ComposerView(store: store) }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $sheet) { destination in
                switch destination {
                case .settings: SettingsView(store: store)
                case .history: HistoryView(store: store)
                }
            }
            .confirmationDialog("停止当前生成并开启新对话？", isPresented: $showNewConfirmation, titleVisibility: .visible) {
                Button("停止并新建", role: .destructive) { store.newConversation() }
            }
            .alert("Loom", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
                Button("好", role: .cancel) { store.notice = nil }
            } message: { Text(store.notice ?? "") }
        }
    }

    private var modelTabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        ForEach(store.current.threads) { thread in
                            let selected = store.selectedModel == thread.id
                            Button {
                                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { store.selectedModel = thread.id }
                            } label: {
                                HStack(spacing: 7) {
                                    Circle().fill(selected ? Color.indigo : Color.secondary.opacity(0.4)).frame(width: 6, height: 6)
                                    Text(thread.configuration.name).font(.subheadline.weight(selected ? .semibold : .medium))
                                    if store.busyModels.contains(thread.id) { ProgressView().controlSize(.mini) }
                                }
                                .padding(.horizontal, 17).frame(minHeight: 44)
                                .foregroundStyle(selected ? .indigo : .primary)
                                .glassEffect(.regular.tint(selected ? .indigo.opacity(0.15) : .clear).interactive(), in: .capsule)
                                .glassEffectID(thread.id, in: tabsNamespace)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .accessibilityLabel("\(thread.configuration.name)，\(selected ? "已选择" : "切换模型")")
                            .accessibilityIdentifier("model-tab-\(thread.configuration.name)")
                            .id(thread.id)
                        }
                    }.padding(.leading, 12).padding(.trailing, 4)
                }.padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .onChange(of: store.selectedModel) { _, id in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private var phoneBoard: some View {
        TabView(selection: $store.selectedModel) {
            ForEach(store.current.threads) { thread in
                ThreadView(thread: thread, store: store).tag(thread.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .id(store.selectedConversation)
        .accessibilityIdentifier("model-pages")
    }

    private func parallelBoard(width: CGFloat) -> some View {
        let count = max(1, store.current.threads.count)
        let columnWidth = max(310, (width - 48 - CGFloat(count - 1) * 16) / CGFloat(count))
        return ScrollViewReader { proxy in
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(store.current.threads) { thread in
                    ThreadView(thread: thread, store: store)
                        .frame(width: columnWidth).id(thread.id)
                }
            }.padding(.horizontal, 24).padding(.top, 12)
            }
        }.scrollIndicators(.hidden)
        .onChange(of: store.selectedModel) { _, id in
            withAnimation(reduceMotion ? nil : .snappy) { proxy.scrollTo(id, anchor: .center) }
        }
        }
    }
}

struct ThreadView: View {
    let thread: ModelThread
    var store: LoomStore

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if thread.messages.isEmpty { emptyState }
                    ForEach(thread.messages) { message in
                        MessageView(message: message, thread: thread, store: store).id(message.id)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 24)
                .frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("thread-\(thread.configuration.name)")
            .overlay(alignment: .topTrailing) {
                if store.current.round > 1 {
                    Menu {
                        ForEach(1...store.current.round, id: \.self) { round in
                            Button("第 \(round) 轮") {
                                if let message = thread.messages.first(where: { $0.round == round }) {
                                    proxy.scrollTo(message.id, anchor: .top)
                                }
                            }
                        }
                        Button("最新回答") { proxy.scrollTo("end", anchor: .bottom) }
                    } label: { Image(systemName: "list.bullet").frame(width: 40, height: 40) }
                    .buttonStyle(.glass).padding(12).accessibilityLabel("轮次导航")
                }
            }
            .onChange(of: thread.messages.count) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
        }
    }
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "square.stack.3d.up").font(.system(size: 34, weight: .light)).foregroundStyle(.indigo)
                .padding(.top, 50)
            Text("让不同的观点\n在这里交织。")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
            Text("一次提问，同时听见多个模型的回答。\n选中有用的文字，带着它继续思考。")
                .font(.body).foregroundStyle(.secondary).lineSpacing(6)
            Label(thread.configuration.name, systemImage: "sparkle").font(.subheadline.weight(.medium)).foregroundStyle(.indigo)
            if thread.configuration.model.isEmpty {
                Text("开始前，请点右上角设置，填写模型型号和 API Key。")
                    .font(.footnote).foregroundStyle(.secondary).padding(.top, 12)
            }
        }.padding(.bottom, 30).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MessageView: View {
    let message: ChatMessage
    let thread: ModelThread
    var store: LoomStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(message.role == "user" ? "你" : thread.configuration.name).font(.caption.weight(.semibold))
                Text("第 \(message.round) 轮").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                if message.role == "assistant", !message.pending, !message.error {
                    ShareLink(item: message.content) { Image(systemName: "square.and.arrow.up") }
                        .font(.caption).foregroundStyle(.secondary).accessibilityLabel("分享回答")
                }
            }.foregroundStyle(.secondary)
            if message.pending {
                HStack(spacing: 10) { ProgressView(); Text("正在思考…").foregroundStyle(.secondary) }.padding(.vertical, 12)
            } else if message.error {
                VStack(alignment: .leading, spacing: 12) {
                    Label(message.content, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                    if thread.messages.last?.id == message.id {
                        Button("重试这个模型", systemImage: "arrow.clockwise") { store.retry(thread.id) }
                            .buttonStyle(.glass).disabled(store.isWorking)
                    }
                }
            } else if message.role == "user" {
                Text(message.display ?? message.content)
                    .font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16).background(.indigo.opacity(0.07), in: .rect(cornerRadius: 18))
            } else {
                SelectableAnswer(content: message.content, highlights: message.highlights) { range, text in
                    store.highlight(threadID: thread.id, messageID: message.id, range: range, text: text)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
