import SwiftUI

private enum WorkspaceSheet: String, Identifiable { case settings, history; var id: String { rawValue } }

struct WorkspaceView: View {
    @Bindable var store: LoomStore
    @State private var readingOffsets: [UUID: [UUID: CGFloat]] = [:]
    @State private var sheet: WorkspaceSheet?
    @State private var showNewConfirmation = false
    @State private var readingChromeVisible = true
    @State private var chromeChangedAt = Date.distantPast
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
                .ignoresSafeArea(.container, edges: readingChromeVisible ? [] : .vertical)
                .overlay(alignment: .top) {
                    if !readingChromeVisible {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .frame(height: geometry.safeAreaInsets.top + 16)
                            .mask {
                                LinearGradient(stops: [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: 0.75),
                                    .init(color: .clear, location: 1)
                                ], startPoint: .top, endPoint: .bottom)
                            }
                            .offset(y: -geometry.safeAreaInsets.top)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                            .transition(.opacity)
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if readingChromeVisible {
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
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if readingChromeVisible {
                        ComposerView(store: store)
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .onChange(of: store.selectedModel) { _, _ in setReadingChrome(true) }
            .onChange(of: store.selectedConversation) { _, _ in setReadingChrome(true) }
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

    private func readingOffset(for threadID: UUID) -> Binding<CGFloat> {
        let conversationID = store.selectedConversation
        return Binding(
            get: { readingOffsets[conversationID]?[threadID] ?? 0 },
            set: { readingOffsets[conversationID, default: [:]][threadID] = $0 }
        )
    }

    private func setReadingChrome(_ visible: Bool) {
        guard readingChromeVisible != visible else { return }
        chromeChangedAt = Date()
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .smooth(duration: 0.32)) {
            readingChromeVisible = visible
        }
    }

    private func readingScrolled(_ forward: Bool) {
        // Ignore geometry changes caused by the bars' own transition.
        guard Date().timeIntervalSince(chromeChangedAt) > 0.4 else { return }
        setReadingChrome(!forward)
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
                ThreadView(thread: thread, store: store, savedOffset: readingOffset(for: thread.id), isActive: store.selectedModel == thread.id, onReadingScroll: readingScrolled)
                    .tag(thread.id)
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
                    ThreadView(thread: thread, store: store, savedOffset: readingOffset(for: thread.id), isActive: true, onReadingScroll: readingScrolled)
                        .frame(width: columnWidth).id(thread.id)
                }
            }.padding(.horizontal, 24).padding(.top, 12)
            }
        }.scrollIndicators(.hidden)
        .onScrollPhaseChange { _, phase in
            if phase == .interacting { setReadingChrome(true) }
        }
        .onChange(of: store.selectedModel) { _, id in
            withAnimation(reduceMotion ? nil : .snappy) { proxy.scrollTo(id, anchor: .center) }
        }
        }
    }
}

struct MessageView: View {
    let message: ChatMessage
    let thread: ModelThread
    var store: LoomStore
    @State private var referencesExpanded = false
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
                if let references = message.references, !references.isEmpty {
                    DisclosureGroup(isExpanded: $referencesExpanded) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(references) { quote in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\(quote.modelName) · 第 \(quote.round) 轮")
                                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                    Text(quote.text).font(.subheadline).textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12).background(.yellow.opacity(0.12), in: .rect(cornerRadius: 12))
                            }
                        }.padding(.top, 8)
                    } label: {
                        Label("高亮引用（\(references.count)）", systemImage: "highlighter")
                            .font(.subheadline)
                    }
                    .tint(.secondary)
                    .accessibilityIdentifier("message-references-\(message.round)")
                }

            } else {
                SelectableAnswer(content: message.content, highlights: message.highlights, singleTapHighlight: store.singleTapHighlight) { range, text, toggle in
                    if toggle { store.toggleHighlight(threadID: thread.id, messageID: message.id, range: range, text: text) }
                    else { store.highlight(threadID: thread.id, messageID: message.id, range: range, text: text) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
