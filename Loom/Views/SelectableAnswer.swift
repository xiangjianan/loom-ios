import SwiftUI
import UIKit

/// UITextView supplies native selection handles; SwiftUI owns persistence and layout.
struct SelectableAnswer: UIViewRepresentable {
    var content: String
    var highlights: [Highlight]
    var onSelection: (NSRange, String) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        let signature = "\(content)|\(highlights)|\(dynamicTypeSize)|\(colorScheme)"
        guard context.coordinator.signature != signature else { return }
        context.coordinator.signature = signature
        let selected = view.selectedRange
        context.coordinator.updating = true
        let text = AnswerRenderer.render(content)
        for saved in highlights {
            guard let mark = HighlightResolver.resolve(saved, in: text.string) else { continue }
            text.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.3), range: mark.range)
        }
        view.attributedText = text
        if NSMaxRange(selected) <= text.length { view.selectedRange = selected }
        context.coordinator.updating = false
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return CGSize(width: width, height: ceil(uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height))
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    static func dismantleUIView(_ uiView: UITextView, coordinator: Coordinator) { coordinator.work?.cancel(); uiView.delegate = nil }

    @MainActor final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SelectableAnswer
        var signature = ""
        var updating = false
        var work: Task<Void, Never>?
        init(_ parent: SelectableAnswer) { self.parent = parent }
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !updating else { return }
            work?.cancel()
            let range = textView.selectedRange
            guard range.length > 0, NSMaxRange(range) <= textView.attributedText.length else { return }
            let selected = (textView.attributedText.string as NSString).substring(with: range)
            work = Task { [weak self, weak textView] in
                try? await Task.sleep(for: .milliseconds(650))
                guard !Task.isCancelled, let self, let textView, textView.selectedRange == range else { return }
                self.parent.onSelection(range, selected)
            }
        }
    }
}
