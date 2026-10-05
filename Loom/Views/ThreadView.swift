import SwiftUI

struct ThreadView: View {
    let thread: ModelThread
    var store: LoomStore
    var readingInsets: EdgeInsets = EdgeInsets()
    @Binding var savedOffset: CGFloat
    var isActive: Bool
    private let contentTopPadding: CGFloat = 20
    @State private var position = ScrollPosition(idType: UUID.self)
    @State private var interaction = ReaderInteraction()
    @State private var roundPositionTask: Task<Void, Never>?
    @State private var railVisible = false
    @State private var scrubbing = false
    @State private var railHideTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reader = ReaderScrollController()

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if thread.messages.isEmpty { emptyState }
                    ForEach(thread.messages) { message in
                        MessageView(message: message, thread: thread, store: store).id(message.id)
                            .onGeometryChange(for: Bool.self) { geometry in
                                let rect = geometry.frame(in: .scrollView(axis: .vertical))
                                return rect.minY <= 100 && rect.maxY > 100
                            } action: { atReadingEdge in
                                if atReadingEdge, interaction.currentRound != message.round { interaction.currentRound = message.round }
                            }
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .scrollTargetLayout()
                .padding(.horizontal, 24).padding(.top, contentTopPadding).padding(.bottom, 24)
                .frame(width: min(760, viewport.size.width), alignment: .leading)
                .frame(width: viewport.size.width, alignment: .center)
                .background(VerticalReaderScrollLock(controller: reader).allowsHitTesting(false).accessibilityHidden(true))
            }
            .contentMargins(.top, readingInsets.top, for: .scrollContent)
            .contentMargins(.bottom, readingInsets.bottom, for: .scrollContent)
            .scrollPosition($position)
            .scrollIndicators(.visible, axes: .vertical)
            .task(id: isActive) {
                guard isActive else { return }
                if let id = store.takeRoundStart(for: thread.id) { revealRoundStart(id); return }
                let offset = savedOffset
                guard offset != 0 else { return }
                // Restore UIKit's raw offset, independent of SwiftUI content-margin coordinates.
                reader.restore(offset)
                // Paging and the reading bars resize together; restore after they settle.
                try? await Task.sleep(for: .milliseconds(360))
                guard !Task.isCancelled, interaction.phase == .idle else { return }
                reader.restore(offset)
            }
            .onScrollPhaseChange { _, phase in
                interaction.phase = phase
                if phase == .interacting || phase == .tracking {
                    roundPositionTask?.cancel()
                    revealRail()
                }
                if phase == .idle {
                    scheduleRailHide()
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                let maximum = max(0, geometry.contentSize.height - geometry.containerSize.height + geometry.contentInsets.bottom)
                return min(maximum, max(-geometry.contentInsets.top, geometry.contentOffset.y))
            } action: { old, new in
                if isActive, scrubbing || interaction.phase == .tracking || interaction.phase == .interacting || interaction.phase == .decelerating || interaction.phase == .animating {
                    savedOffset = new
                }
            }
            .scrollDismissesKeyboard(.never)
            .accessibilityIdentifier("thread-\(thread.configuration.name)")
            .overlay(alignment: .leading) {
                let rounds = Array(Set(thread.messages.map(\.round))).sorted()
                if rounds.count > 1, railVisible {
                    RoundScrubber(rounds: rounds, interaction: interaction) { round, dragging in
                        if let message = thread.messages.first(where: { $0.round == round }) {
                            interaction.currentRound = round
                            let jump = {
                                if round == rounds.first { position.scrollTo(edge: .top) }
                                else { position.scrollTo(id: message.id, anchor: UnitPoint(x: 0.5, y: 0.12)) }
                            }
                            if reduceMotion { jump() }
                            else { withAnimation(.smooth(duration: 0.25), jump) }
                        }
                        revealRail()
                        if !dragging { scheduleRailHide() }
                    } onScrubbingChanged: { active in
                        scrubbing = active
                        if active { revealRail() } else { scheduleRailHide() }
                    }
                    .padding(.leading, 12)
                    .zIndex(100)
                    .transition(.opacity)
                }
            }
            .onChange(of: store.pendingRoundStarts[thread.id]) { _, id in
                if id != nil, isActive, let target = store.takeRoundStart(for: thread.id) {
                    revealRoundStart(target)
                }
            }
            .onDisappear { railHideTask?.cancel(); roundPositionTask?.cancel() }

        }
    }
    private func revealRoundStart(_ messageID: UUID) {
        if let message = thread.messages.first(where: { $0.id == messageID }) { interaction.currentRound = message.round }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            position.scrollTo(id: messageID, anchor: .top)
        }
        roundPositionTask?.cancel()
        roundPositionTask = Task { @MainActor in
            // A newly activated pager and a long answer both need a layout pass.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, interaction.phase != .interacting else { return }
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                position.scrollTo(id: messageID, anchor: .top)
            }
        }
    }

    private func revealRail() {
        railHideTask?.cancel()
        guard !railVisible else { return }
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
                Text("开始前，请打开左上角会话侧栏中的模型设置，填写模型型号和 API Key。")
                    .font(.footnote).foregroundStyle(.secondary).padding(.top, 12)
            }
        }.padding(.bottom, 30).frame(maxWidth: .infinity, alignment: .leading)
    }
}


/// Scroll callbacks mutate this object without invalidating the reader's view hierarchy.
/// Only the rail observes the active round; content doesn't subscribe to it.
@Observable final class ReaderInteraction {
    var currentRound = 1
    var phase: ScrollPhase = .idle
}
