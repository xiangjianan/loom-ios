import SwiftUI
import UIKit

/// UITextView supplies native selection handles; SwiftUI owns persistence and layout.
struct SelectableAnswer: UIViewRepresentable {
    var content: String
    var highlights: [Highlight]
    var singleTapHighlight: Bool = false
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
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.highlightParagraph(_:)))
        tap.numberOfTapsRequired = singleTapHighlight ? 1 : 2
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        context.coordinator.tap = tap
        view.addInteraction(UIContextMenuInteraction(delegate: context.coordinator))
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.tap?.numberOfTapsRequired = singleTapHighlight ? 1 : 2
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
    static func dismantleUIView(_ uiView: UITextView, coordinator: Coordinator) { uiView.delegate = nil }

    @MainActor final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate, UIContextMenuInteractionDelegate {
        var parent: SelectableAnswer
        var signature = ""
        var updating = false
        weak var tap: UITapGestureRecognizer?
        init(_ parent: SelectableAnswer) { self.parent = parent }

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            let highlight = UIAction(title: "高亮", image: UIImage(systemName: "highlighter")) { [weak self, weak textView] _ in
                guard let self, let textView else { return }
                self.commit(range, in: textView)
            }
            return UIMenu(children: [highlight] + suggestedActions)
        }

        func textView(_ textView: UITextView, editMenuForTextInRanges ranges: [NSValue], suggestedActions: [UIMenuElement]) -> UIMenu? {
            self.textView(textView, editMenuForTextIn: ranges.first?.rangeValue ?? textView.selectedRange, suggestedActions: suggestedActions)
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            guard let view = interaction.view as? UITextView,
                  let index = character(at: location, in: view),
                  let position = view.position(from: view.beginningOfDocument, offset: index) else { return nil }
            view.becomeFirstResponder()
            if view.selectedRange.length == 0 || !NSLocationInRange(index, view.selectedRange) {
                if let word = view.tokenizer.rangeEnclosingPosition(position, with: .word, inDirection: UITextDirection(rawValue: UITextStorageDirection.forward.rawValue)) {
                    view.selectedTextRange = word
                } else {
                    view.selectedRange = (view.attributedText.string as NSString).rangeOfComposedCharacterSequence(at: index)
                }
            }
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self, weak view] _ in
                guard let self, let view else { return nil }
                let copy = UIAction(title: "拷贝", image: UIImage(systemName: "doc.on.doc")) { [weak view] _ in
                    guard let view, view.selectedRange.length > 0 else { return }
                    UIPasteboard.general.string = (view.attributedText.string as NSString).substring(with: view.selectedRange)
                }
                return self.textView(view, editMenuForTextIn: view.selectedRange, suggestedActions: [copy])
            }
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
            selectionPreview(interaction)
        }
        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
            selectionPreview(interaction)
        }
        private func selectionPreview(_ interaction: UIContextMenuInteraction) -> UITargetedPreview? {
            guard let view = interaction.view as? UITextView, let range = view.selectedTextRange else { return nil }
            let rect = view.firstRect(for: range).intersection(view.bounds)
            guard !rect.isEmpty, let snapshot = view.resizableSnapshotView(from: rect, afterScreenUpdates: false, withCapInsets: .zero) else { return nil }
            let parameters = UIPreviewParameters()
            parameters.backgroundColor = .clear
            return UITargetedPreview(view: snapshot, parameters: parameters,
                                     target: UIPreviewTarget(container: view, center: CGPoint(x: rect.midX, y: rect.midY)))
        }

        private func commit(_ range: NSRange, in view: UITextView) {
            guard range.length > 0, NSMaxRange(range) <= view.attributedText.length else { return }
            let text = (view.attributedText.string as NSString).substring(with: range)
            view.selectedRange = NSRange(location: range.location, length: 0)
            view.resignFirstResponder()
            parent.onSelection(range, text)
            UISelectionFeedbackGenerator().selectionChanged()
        }

        private func character(at point: CGPoint, in view: UITextView) -> Int? {
            guard let position = view.closestPosition(to: point) else { return nil }
            let index = view.offset(from: view.beginningOfDocument, to: position)
            guard index < view.attributedText.length,
                  let end = view.position(from: position, offset: 1),
                  let range = view.textRange(from: position, to: end),
                  view.firstRect(for: range).insetBy(dx: -8, dy: -4).contains(point) else { return nil }
            return index
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let view = gestureRecognizer.view as? UITextView,
                  let index = character(at: touch.location(in: view), in: view) else { return false }
            return view.attributedText.attribute(.link, at: index, effectiveRange: nil) == nil
        }

        @objc func highlightParagraph(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? UITextView,
                  let index = character(at: gesture.location(in: view), in: view) else { return }
            let text = view.attributedText.string as NSString
            var range = text.paragraphRange(for: NSRange(location: index, length: 0))
            let whitespace = CharacterSet.whitespacesAndNewlines
            while range.length > 0, let scalar = UnicodeScalar(text.character(at: range.location)), whitespace.contains(scalar) {
                range.location += 1; range.length -= 1
            }
            while range.length > 0, let scalar = UnicodeScalar(text.character(at: NSMaxRange(range) - 1)), whitespace.contains(scalar) {
                range.length -= 1
            }
            commit(range, in: view)
        }
    }
}
