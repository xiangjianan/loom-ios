import SwiftUI

struct ThreadView: View {
    let thread: ModelThread
    var store: LoomStore
    var readingInsets: EdgeInsets = EdgeInsets()
    @Binding var savedOffset: CGFloat
    var isActive: Bool
    @State private var position = ScrollPosition(idType: UUID.self)
    @State private var currentRound = 1
    @State private var railVisible = false
    @State private var scrubbing = false
    @State private var railHideTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onReadingScroll: (Bool) -> Void = { _ in }
    @State private var scrollPhase: ScrollPhase = .idle
    @State private var scrollTravel: CGFloat = 0

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if thread.messages.isEmpty { emptyState }
                    ForEach(thread.messages) { message in
                        MessageView(message: message, thread: thread, store: store).id(message.id)
                            .onGeometryChange(for: Bool.self) { geometry in
                                let rect = geometry.frame(in: .scrollView(axis: .vertical))
                                return rect.minY <= 100 && rect.maxY > 100
                            } action: { atReadingEdge in
                                if atReadingEdge { currentRound = message.round }
                            }
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .scrollTargetLayout()
                .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 24)
                .frame(width: min(760, viewport.size.width), alignment: .leading)
                .frame(width: viewport.size.width, alignment: .center)
                .background(VerticalReaderScrollLock().allowsHitTesting(false).accessibilityHidden(true))
            }
            .contentMargins(.top, readingInsets.top, for: .scrollContent)
            .contentMargins(.bottom, readingInsets.bottom, for: .scrollContent)
            .scrollPosition($position)
            .scrollIndicators(.hidden)
            .task(id: isActive) {
                guard isActive else { return }
                let offset = savedOffset
                guard offset > 0 else { return }
                position.scrollTo(y: offset)
                // Paging and the reading bars resize together; restore after they settle.
                try? await Task.sleep(for: .milliseconds(360))
                guard !Task.isCancelled, scrollPhase == .idle else { return }
                position.scrollTo(y: offset)
            }
            .onScrollPhaseChange { _, phase in
                scrollPhase = phase
                if phase == .interacting {
                    scrollTravel = 0
                    revealRail()
                }
                if phase == .idle { scheduleRailHide() }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                let maximum = max(0, geometry.contentSize.height - geometry.containerSize.height + geometry.contentInsets.bottom)
                return min(maximum, max(0, geometry.contentOffset.y))
            } action: { old, new in
                if isActive, scrubbing || scrollPhase == .interacting || scrollPhase == .decelerating || scrollPhase == .animating {
                    savedOffset = new
                }
                guard scrollPhase == .interacting else { return }
                let delta = new - old
                guard abs(delta) > 0.5 else { return }
                if delta * scrollTravel < 0 { scrollTravel = 0 }
                scrollTravel += delta
                if abs(scrollTravel) > 24 {
                    onReadingScroll(scrollTravel > 0)
                    scrollTravel = 0
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("thread-\(thread.configuration.name)")
            .overlay(alignment: .trailing) {
                let rounds = Array(Set(thread.messages.map(\.round))).sorted()
                if rounds.count > 1, railVisible {
                    RoundScrubber(rounds: rounds, currentRound: currentRound) { round, dragging in
                        if let message = thread.messages.first(where: { $0.round == round }) {
                            currentRound = round
                            let jump = {
                                if round == rounds.first { position.scrollTo(edge: .top) }
                                else { position.scrollTo(id: message.id, anchor: UnitPoint(x: 0.5, y: 0.12)) }
                            }
                            if dragging || reduceMotion { jump() }
                            else { withAnimation(.smooth(duration: 0.25), jump) }
                        }
                        revealRail()
                        if !dragging { scheduleRailHide() }
                    } onScrubbingChanged: { active in
                        scrubbing = active
                        if active { revealRail() } else { scheduleRailHide() }
                    }
                    .padding(.trailing, 2)
                    .transition(.opacity)
                }
            }
            .onChange(of: thread.messages.count) { old, new in
                if new > old, isActive { position.scrollTo(edge: .bottom) }
            }
            .onDisappear { railHideTask?.cancel() }

        }
    }
    private func revealRail() {
        railHideTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { railVisible = true }
    }

    private func scheduleRailHide() {
        railHideTask?.cancel()
        railHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, !scrubbing else { return }
            withAnimation(.easeInOut(duration: 0.3)) { railVisible = false }
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

