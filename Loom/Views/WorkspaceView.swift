import SwiftUI

private enum WorkspaceSheet: String, Identifiable { case settings, backup; var id: String { rawValue } }

struct WorkspaceView: View {
    @Bindable var store: LoomStore
    @State private var readingOffsets: [UUID: [UUID: CGFloat]] = [:]
    @State private var sheet: WorkspaceSheet?
    @State private var drawerVisible = false
    @State private var pageSelection: UUID
    @State private var showNewConfirmation = false
    @State private var readingChromeVisible = true
    @State private var topBarHeight: CGFloat = 60
    @State private var bottomBarHeight: CGFloat = 66
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var tabsNamespace

    init(store: LoomStore) {
        self.store = store
        _pageSelection = State(initialValue: store.selectedModel)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let parallel = geometry.size.width >= 700
                // Chrome only moves visually; it never resizes the reader or changes its content insets.
                let readingInsets = EdgeInsets(top: geometry.safeAreaInsets.top + topBarHeight, leading: 0, bottom: geometry.safeAreaInsets.bottom + bottomBarHeight, trailing: 0)
                ZStack {
                    Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                    if parallel { parallelBoard(width: geometry.size.width, readingInsets: readingInsets) }
                    else { phoneBoard(readingInsets: readingInsets) }
                }
                .ignoresSafeArea(.container, edges: .vertical)
                .overlay(alignment: .top) {
                    if !readingChromeVisible {
                        Rectangle()
                            .fill(.clear)
                            .frame(height: geometry.safeAreaInsets.top + 16)
                            .glassEffect(.regular.tint(Color(uiColor: .systemBackground).opacity(0.08)), in: .rect(cornerRadius: 0))
                            .opacity(0.88)
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
                .overlay(alignment: .top) {
                    HStack(spacing: 0) {
                        Button {
                            setReadingChrome(true)
                            withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) { drawerVisible = true }
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Capsule().frame(width: 22, height: 2)
                                Capsule().frame(width: 16, height: 2)
                            }.frame(width: 44, height: 44).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel("打开会话侧栏")
                        .accessibilityIdentifier("workspace-menu")
                        .padding(.leading, 12)
                        modelTabs
                    }
                    .padding(.vertical, 4)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topBarHeight = $0 }
                    .background { ReadingBarGlass(edge: .top, safeAreaHeight: geometry.safeAreaInsets.top) }
                    .offset(y: readingChromeVisible ? 0 : -(topBarHeight + geometry.safeAreaInsets.top + 20))
                    .opacity(readingChromeVisible ? 1 : 0)
                    .allowsHitTesting(readingChromeVisible && !drawerVisible)
                    .accessibilityHidden(!readingChromeVisible || drawerVisible)
                }
                .overlay(alignment: .bottom) {
                    ComposerView(store: store)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomBarHeight = $0 }
                        .background { ReadingBarGlass(edge: .bottom, safeAreaHeight: geometry.safeAreaInsets.bottom) }
                        .offset(y: readingChromeVisible ? 0 : bottomBarHeight + geometry.safeAreaInsets.bottom + 20)
                        .opacity(readingChromeVisible ? 1 : 0)
                        .allowsHitTesting(readingChromeVisible && !drawerVisible)
                        .accessibilityHidden(!readingChromeVisible || drawerVisible)
                }
                .overlay {
                    if drawerVisible {
                        ZStack(alignment: .leading) {
                            Color.black.opacity(0.2)
                                .ignoresSafeArea()
                                .onTapGesture { closeDrawer() }
                                .accessibilityLabel("关闭会话侧栏")
                                .accessibilityAddTraits(.isButton)
                                .accessibilityIdentifier("drawer-backdrop")
                            ConversationDrawer(store: store, newConversation: {
                                closeDrawer()
                                if store.isWorking { showNewConfirmation = true } else { store.newConversation() }
                            }, close: closeDrawer, settings: { closeDrawer(); sheet = .settings }, backup: { closeDrawer(); sheet = .backup })
                                .frame(width: min(360, geometry.size.width * 0.86))
                                .frame(maxHeight: .infinity)
                                .background(Color(uiColor: .systemGroupedBackground).opacity(0.65))
                                .glassEffect(.regular, in: .rect(cornerRadius: 0))
                                .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
                                .accessibilityAddTraits(.isModal)
                        }.transition(.opacity)
                        .zIndex(10)
                    }
                }

            }
            .onChange(of: store.selectedModel) { _, id in
                if pageSelection != id { pageSelection = id }
                setReadingChrome(true)
            }
            .onChange(of: pageSelection) { _, id in
                if store.selectedModel != id { store.selectedModel = id }
            }
            .sensoryFeedback(.selection, trigger: store.selectedModel)
            .onChange(of: store.selectedConversation) { _, _ in setReadingChrome(true) }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $sheet) { destination in
                switch destination {
                case .settings: SettingsView(store: store)
                case .backup: BackupView(store: store)
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

    private func closeDrawer() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) { drawerVisible = false }
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
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .smooth(duration: 0.32)) {
            readingChromeVisible = visible
        }
    }

    private func readingScrolled(_ forward: Bool) {
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
                                .glassEffect(.regular.tint(selected ? .indigo.opacity(0.08) : .clear).interactive(), in: .capsule)
                                .glassEffectID(thread.id, in: tabsNamespace)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .accessibilityLabel("\(thread.configuration.name)，\(selected ? "已选择" : "切换模型")")
                            .accessibilityIdentifier("model-tab-\(thread.configuration.name)")
                            .accessibilityHidden(!readingChromeVisible || drawerVisible)
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

    private func phoneBoard(readingInsets: EdgeInsets) -> some View {
        TabView(selection: $pageSelection) {
            ForEach(store.current.threads) { thread in
                ThreadView(thread: thread, store: store, readingInsets: readingInsets, savedOffset: readingOffset(for: thread.id), isActive: pageSelection == thread.id, onReadingScroll: readingScrolled)
                    .tag(thread.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .id(store.selectedConversation)
        .accessibilityIdentifier("model-pages")
    }

    private func parallelBoard(width: CGFloat, readingInsets: EdgeInsets) -> some View {
        let count = max(1, store.current.threads.count)
        let columnWidth = max(310, (width - 48 - CGFloat(count - 1) * 16) / CGFloat(count))
        return ScrollViewReader { proxy in
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(store.current.threads) { thread in
                    ThreadView(thread: thread, store: store, readingInsets: readingInsets, savedOffset: readingOffset(for: thread.id), isActive: true, onReadingScroll: readingScrolled)
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


/// Glass extends across the surrounding band and fades into the scrolling text.
private struct ReadingBarGlass: View {
    let edge: VerticalEdge
    let safeAreaHeight: CGFloat
    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.clear)
                .frame(height: geometry.size.height + safeAreaHeight + 16)
                .glassEffect(.regular.tint(Color(uiColor: .systemBackground).opacity(0.03)), in: .rect(cornerRadius: 0))
                .opacity(0.8)
                .mask {
                    LinearGradient(stops: edge == .top ? [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.7),
                        .init(color: .clear, location: 1)
                    ] : [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.3),
                        .init(color: .black, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
                .offset(y: edge == .top ? -safeAreaHeight : -16)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
