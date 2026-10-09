import SwiftUI

private enum WorkspaceSheet: String, Identifiable { case settings; var id: String { rawValue } }

struct WorkspaceView: View {
    @Bindable var store: LoomStore
    @State private var readingPositions = ReadingPositions()
    @FocusState private var composerFocused: Bool
    @State private var sheet: WorkspaceSheet?
    @State private var drawerVisible = false
    @State private var drawerMounted = false
    @State private var drawerAnimationGeneration = 0
    @State private var drawerProgress: CGFloat = 0
    @GestureState private var draggingDrawer = false
    @State private var pageSelection: UUID
    @State private var showNewConfirmation = false
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
                // Use the live window width so folding and rotation select the same layout.
                let parallel = geometry.size.width >= 700
                // The glass bars stay visible while content scrolls underneath.
                let readingInsets = EdgeInsets(top: geometry.safeAreaInsets.top + topBarHeight, leading: 0, bottom: geometry.safeAreaInsets.bottom + bottomBarHeight, trailing: 0)
                let drawerWidth = min(360, geometry.size.width * 0.82)
                let reveal = drawerWidth * drawerProgress
                let progress = reveal / drawerWidth
                ZStack(alignment: .leading) {
                    Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                    if drawerMounted || reveal > 0 {
                    ConversationDrawer(store: store, newConversation: {
                        closeDrawer()
                        if store.isWorking { showNewConfirmation = true } else { store.newConversation() }
                    }, close: closeDrawer, settings: { sheet = .settings })
                        .frame(width: drawerWidth)
                        .frame(maxHeight: .infinity)
                        .accessibilityAddTraits(drawerVisible && sheet == nil ? .isModal : [])
                    }
                ZStack {
                    Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                    Group {
                        if store.visibleThreads.isEmpty {
                            ContentUnavailableView {
                                Label("没有启用的模型", systemImage: "switch.2")
                            } description: {
                                Text("在设置中开启模型，即可显示对话并发送消息。")
                            } actions: {
                                Button("启用模型") { sheet = .settings }
                                    .accessibilityIdentifier("enable-models")
                            }
                        }
                        else if parallel { parallelBoard(width: geometry.size.width, readingInsets: readingInsets) }
                        else { phoneBoard(readingInsets: readingInsets) }
                    }
                    .opacity(1 - 0.55 * progress)
                }
                .ignoresSafeArea(.container, edges: .vertical)
                .overlay(alignment: .top) {
                    HStack(spacing: 0) {
                        Button {
                            setDrawer(true)
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
                    .padding(.vertical, 2)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topBarHeight = $0 }
                    .background { TopBarGlass(safeAreaHeight: geometry.safeAreaInsets.top + 4) }
                    .offset(y: -4)
                    .allowsHitTesting(!drawerVisible)
                    .accessibilityHidden(drawerVisible)
                }
                .overlay(alignment: .bottom) {
                    ComposerView(store: store, focus: $composerFocused)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomBarHeight = $0 }
                        .allowsHitTesting(!drawerVisible)
                        .accessibilityHidden(drawerVisible)
                }
                .allowsHitTesting(!drawerVisible)
                .accessibilityHidden(drawerVisible)
                .clipShape(DrawerPageShape(radius: 38 * progress, topInset: geometry.safeAreaInsets.top, bottomInset: geometry.safeAreaInsets.bottom))
                .shadow(color: .black.opacity(0.16 * progress), radius: 18, x: -6, y: 0)
                .offset(x: reveal)
                }
                .overlay(alignment: .trailing) {
                    if drawerVisible {
                        Color.clear.frame(width: geometry.size.width - drawerWidth)
                            .contentShape(.rect)
                            .onTapGesture { closeDrawer() }
                            .accessibilityLabel("关闭会话侧栏")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("drawer-backdrop")
                    }
                }
                .overlay(alignment: .leading) {
                    Color.clear.frame(width: 12).contentShape(.rect)
                        .gesture(drawerGesture(width: drawerWidth, opening: true))
                        .allowsHitTesting(!drawerVisible)
                        .accessibilityHidden(true)
                }
                .simultaneousGesture(
                    drawerGesture(width: drawerWidth, opening: false),
                    including: drawerVisible && sheet == nil ? .all : .none
                )
                .mask { Rectangle().ignoresSafeArea() }
                .onChange(of: parallel) { _, _ in
                    pageSelection = store.selectedModel
                }


            }
            // Search keeps the drawer and the revealed page pinned behind the keyboard.
            .ignoresSafeArea(.keyboard, edges: drawerMounted || drawerVisible ? .bottom : [])
            .onChange(of: draggingDrawer) { _, active in
                if !active, drawerProgress != 0, drawerProgress != 1 { setDrawer(drawerVisible) }
            }
            .onChange(of: store.selectedModel) { _, id in
                if pageSelection != id { pageSelection = id }
            }
            .onChange(of: pageSelection) { _, id in
                if store.selectedModel != id { store.selectedModel = id }
            }
            .sensoryFeedback(.selection, trigger: store.selectedModel)
            .sensoryFeedback(.selection, trigger: store.selectedConversation)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $sheet) { destination in
                switch destination {
                case .settings: SettingsView(store: store)
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

    private func closeDrawer() { setDrawer(false) }

    private func setDrawer(_ visible: Bool) {
        drawerAnimationGeneration += 1
        let generation = drawerAnimationGeneration
        if visible || drawerProgress > 0 { drawerMounted = true }
        withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86), completionCriteria: .removed) {
            drawerVisible = visible
            drawerProgress = visible ? 1 : 0
        } completion: {
            if generation == drawerAnimationGeneration, !drawerVisible, drawerProgress == 0 { drawerMounted = false }
        }
    }

    // A dedicated edge strip owns opening; the model pager owns swipes everywhere else.
    private func drawerGesture(width: CGFloat, opening: Bool) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($draggingDrawer) { _, active, _ in active = true }
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    drawerProgress = min(1, max(0, (opening ? 0 : 1) + value.translation.width / width))
                }
            }
            .onEnded { value in
                let horizontal = abs(value.translation.width) > abs(value.translation.height)
                let projected = (opening ? 0 : width) + value.predictedEndTranslation.width
                setDrawer(horizontal ? projected > width * 0.4 : !opening)
            }
    }

    private func readingOffset(for threadID: UUID) -> Binding<CGFloat> {
        let conversationID = store.selectedConversation
        return Binding(
            get: { readingPositions.offsets[conversationID]?[threadID] ?? 0 },
            set: { readingPositions.offsets[conversationID, default: [:]][threadID] = $0 }
        )
    }

    private var modelTabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    modelTabRow
                } else {
                    GlassEffectContainer(spacing: 10) { modelTabRow }
                }
            }
            .scrollIndicators(.hidden)
            .onAppear { proxy.scrollTo(store.selectedModel, anchor: .center) }
            .onChange(of: store.selectedModel) { _, id in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private var modelTabRow: some View {
        HStack(spacing: 10) {
            ForEach(store.visibleThreads) { thread in
                let selected = store.selectedModel == thread.id
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { store.selectedModel = thread.id }
                } label: {
                    HStack(spacing: 7) {
                        Circle().fill(selected ? Color.blue : Color.secondary.opacity(0.4)).frame(width: 6, height: 6)
                        Text(thread.configuration.name).font(.subheadline.weight(selected ? .semibold : .medium))
                        if store.busyModels.contains(thread.id) { ProgressView().controlSize(.mini) }
                    }
                    .padding(.horizontal, 17).frame(minHeight: 44)
                    .foregroundStyle(selected ? .blue : .primary)
                    .glassEffect(.regular.tint(selected ? .blue.opacity(0.08) : .clear).interactive(), in: .capsule)
                    .glassEffectID(thread.id, in: tabsNamespace)
                }
                .buttonStyle(.plain)
                .modifier(IPadGlassClip(shape: Capsule()))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityLabel("\(thread.configuration.name)，\(selected ? "已选择" : "切换模型")")
                .accessibilityIdentifier("model-tab-\(thread.configuration.name)")
                .accessibilityHidden(drawerVisible)
                .id(thread.id)
            }
        }.padding(.leading, 12).padding(.trailing, 4)
    }

    private func phoneBoard(readingInsets: EdgeInsets) -> some View {
        TabView(selection: $pageSelection) {
            ForEach(store.visibleThreads) { thread in
                ThreadView(thread: thread, store: store, readingInsets: readingInsets, savedOffset: readingOffset(for: thread.id), isActive: pageSelection == thread.id)
                    .tag(thread.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .scrollDismissesKeyboard(.never)
        .id(store.selectedConversation)
        .accessibilityIdentifier("model-pages")
    }

    private func parallelBoard(width: CGFloat, readingInsets: EdgeInsets) -> some View {
        let count = max(1, store.visibleThreads.count)
        let columnWidth = max(310, (width - 48 - CGFloat(count - 1) * 16) / CGFloat(count))
        return ScrollViewReader { proxy in
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(store.visibleThreads) { thread in
                    ThreadView(thread: thread, store: store, readingInsets: readingInsets, savedOffset: readingOffset(for: thread.id), isActive: true)
                        .frame(width: columnWidth).id(thread.id)
                }
            }.padding(.horizontal, 24).padding(.top, 12)
            }
        }.scrollIndicators(.hidden)
        .accessibilityIdentifier("parallel-board")
        .onAppear { proxy.scrollTo(store.selectedModel, anchor: .center) }
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
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(message.role == "user" ? "你" : thread.configuration.name).font(.caption.weight(.semibold))
                Text("第 \(message.round) 轮").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                if message.role == "user" {
                    Button {
                        UIPasteboard.general.string = message.display ?? message.content
                        copied = true
                    } label: {
                        Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.plain).font(.caption)
                    .accessibilityLabel("复制已发送消息")
                    .accessibilityIdentifier("copy-message-\(message.id)")
                    .task(id: copied) {
                        guard copied else { return }
                        try? await Task.sleep(for: .seconds(2))
                        if !Task.isCancelled { copied = false }
                    }
                }
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
                    .padding(16).background(.blue.opacity(0.07), in: .rect(cornerRadius: 18))
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


struct IPadGlassClip<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            // Clip after the button/container renders its native glass shadow.
            content.clipShape(shape)
        } else {
            content
        }
    }
}

/// Full-width bar background, with individual glass controls on iPad.
private struct TopBarGlass: View {
    let safeAreaHeight: CGFloat
    var body: some View {
        GeometryReader { geometry in
            Group {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    // Match the page across the full bar; only the controls use glass.
                    Rectangle().fill(Color(uiColor: .systemGroupedBackground))
                } else {
                    Rectangle()
                        .fill(.clear)
                        .glassEffect(.regular, in: .rect(cornerRadius: 0))
                        .opacity(0.82)
                }
            }
            .frame(height: geometry.size.height + safeAreaHeight + 4)
            .clipped()
            .offset(y: -safeAreaHeight)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Clip the whole page, including its status and home-indicator bands.
private struct DrawerPageShape: Shape {
    var radius: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }
    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius)
            .path(in: CGRect(x: rect.minX, y: rect.minY - topInset,
                             width: rect.width, height: rect.height + topInset + bottomInset))
    }
}

/// Updating per-model offsets must not invalidate the workspace on every scroll frame.
@Observable private final class ReadingPositions {
    var offsets: [UUID: [UUID: CGFloat]] = [:]
}
