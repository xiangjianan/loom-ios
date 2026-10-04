import SwiftUI

/// A scroll-time rail: tap a tick or scrub vertically without opening a menu.
struct RoundScrubber: View {
    let rounds: [Int]
    let currentRound: Int
    var onSelect: (Int, Bool) -> Void
    var onScrubbingChanged: (Bool) -> Void
    @State private var draggedRound: Int?

    var body: some View {
        GeometryReader { geometry in
            let height = min(geometry.size.height * 0.7, CGFloat(rounds.count) * 44)
            let step = height / CGFloat(max(1, rounds.count))
            VStack(spacing: 0) {
                ForEach(rounds, id: \.self) { round in
                    Button {
                        onSelect(round, false)
                    } label: {
                        Text("—")
                            .font(.system(size: round == (draggedRound ?? currentRound) ? 24 : 16, weight: .bold))
                            .foregroundStyle(round == (draggedRound ?? currentRound) ? Color.indigo : Color.secondary.opacity(0.6))
                            .frame(width: 44, height: step)
                            .contentShape(.rect)
                            .accessibilityLabel("跳到第 \(round) 轮")
                            .accessibilityIdentifier("round-tick-\(round)")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("跳到第 \(round) 轮")
                    .accessibilityIdentifier("round-tick-\(round)")
                    .accessibilityAddTraits(round == currentRound ? .isSelected : [])
                }
            }
            .background(alignment: .trailing) {
                Capsule().fill(.secondary.opacity(0.15)).frame(width: 2).padding(.vertical, step / 2).padding(.trailing, 7)
            }
            .frame(width: 44, height: height)
            .contentShape(.rect)
            .highPriorityGesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        let index = min(rounds.count - 1, max(0, Int(value.location.y / step)))
                        let round = rounds[index]
                        if draggedRound == nil { onScrubbingChanged(true) }
                        if draggedRound != round {
                            draggedRound = round
                            onSelect(round, true)
                        }
                    }
                    .onEnded { _ in
                        draggedRound = nil
                        onScrubbingChanged(false)
                    }
            )
            .overlay(alignment: .leading) {
                if let round = draggedRound {
                    Text("第 \(round) 轮")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                        .fixedSize().offset(x: -80)
                        .allowsHitTesting(false)
                }
            }
            .sensoryFeedback(.selection, trigger: draggedRound)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .frame(width: 44)
    }
}
