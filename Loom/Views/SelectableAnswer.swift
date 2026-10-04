import SwiftUI
import UIKit

/// Native TextKit selection and edit menu, with a separate sentence tap shortcut.
struct SelectableAnswer: UIViewRepresentable {
    var content: String
    var highlights: [Highlight]
    var singleTapHighlight: Bool = true
    var onSelection: (NSRange, String, Bool) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> ReadingTextView {
        let view = ReadingTextView(frame: .zero, textContainer: nil)
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = true
        view.bounces = false
        view.showsVerticalScrollIndicator = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.highlightSentence(_:)))
        tap.numberOfTapsRequired = singleTapHighlight ? 1 : 2
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        context.coordinator.tap = tap
        view.selectionScroller = SelectionAutoScroller(textView: view)
        return view
    }
    func updateUIView(_ view: ReadingTextView, context: Context) {
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
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ReadingTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        uiView.prepareSVGLayout(width: width)
        return CGSize(width: width, height: ceil(uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height))
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    static func dismantleUIView(_ uiView: ReadingTextView, coordinator: Coordinator) {
        uiView.selectionScroller?.stop()
        uiView.delegate = nil
    }

    @MainActor final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: SelectableAnswer
        var signature = ""
        var updating = false
        weak var tap: UITapGestureRecognizer?
        init(_ parent: SelectableAnswer) { self.parent = parent }

        func textView(_ textView: UITextView, editMenuForTextInRanges ranges: [NSValue], suggestedActions: [UIMenuElement]) -> UIMenu? {
            // Preserve every system action and its native presentation. Add one selection action.
            let range = ranges.first?.rangeValue ?? textView.selectedRange
            guard range.length > 0 else { return nil }
            let marked = parent.highlights.contains { HighlightResolver.resolve($0, in: textView.attributedText.string)?.range == range }
            let highlight = UIAction(title: marked ? "取消高亮" : "高亮", image: UIImage(systemName: "highlighter")) { [weak self, weak textView] _ in
                guard let self, let textView else { return }
                self.commit(range, in: textView, toggle: marked)
            }
            return UIMenu(children: [highlight] + suggestedActions)
        }

        private func commit(_ range: NSRange, in view: UITextView, toggle: Bool) {
            guard range.length > 0, NSMaxRange(range) <= view.attributedText.length else { return }
            let text = (view.attributedText.string as NSString).substring(with: range)
            view.selectedRange = NSRange(location: range.location, length: 0)
            view.resignFirstResponder()
            parent.onSelection(range, text, toggle)
            UISelectionFeedbackGenerator().selectionChanged()
        }

        private func character(at point: CGPoint, in view: UITextView) -> Int? {
            guard let position = view.closestPosition(to: point) else { return nil }
            let offset = view.offset(from: view.beginningOfDocument, to: position)
            let text = view.attributedText.string as NSString
            // closestPosition returns a caret, which may be after the tapped glyph.
            // Check both neighbors and their complete composed characters (including emoji).
            for candidate in [offset, offset - 1] where candidate >= 0 && candidate < text.length {
                let glyph = text.rangeOfComposedCharacterSequence(at: candidate)
                guard let start = view.position(from: view.beginningOfDocument, offset: glyph.location),
                      let end = view.position(from: start, offset: glyph.length),
                      let range = view.textRange(from: start, to: end) else { continue }
                if view.firstRect(for: range).insetBy(dx: 0, dy: -3).contains(point) { return glyph.location }
            }
            return nil
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let view = gestureRecognizer.view as? UITextView,
                  let index = character(at: touch.location(in: view), in: view), view.selectedRange.length == 0 else { return false }
            let attributes = view.attributedText.attributes(at: index, effectiveRange: nil)
            return attributes[.link] == nil && attributes[.attachment] == nil && attributes[.loomCode] == nil
        }
        @objc func highlightSentence(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? UITextView,
                  let index = character(at: gesture.location(in: view), in: view),
                  let range = SentenceSelection.range(in: view.attributedText.string, at: index) else { return }
            commit(range, in: view, toggle: true)
        }
    }
}

final class ReadingTextView: UITextView {
    var selectionScroller: SelectionAutoScroller?
    private var svgViews: [Int: SVGImageView] = [:]
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    func prepareSVGLayout(width: CGFloat) {
        var changed = false
        attributedText.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributedText.length)) { value, _, _ in
            if let attachment = value as? SVGTextAttachment {
                let bounds = attachment.document.bounds(width: width)
                if attachment.bounds != bounds { attachment.bounds = bounds; changed = true }
            }
        }
        if changed {
            let selection = selectedRange
            attributedText = NSAttributedString(attributedString: attributedText)
            selectedRange = selection
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        selectionScroller?.attach()
        var active: Set<Int> = []
        attributedText.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributedText.length)) { value, range, _ in
            guard let attachment = value as? SVGTextAttachment,
                  let start = position(from: beginningOfDocument, offset: range.location),
                  let end = position(from: start, offset: 1), let textRange = self.textRange(from: start, to: end) else { return }
            active.insert(range.location)
            var imageView = svgViews[range.location]
            if imageView?.source != attachment.document.source {
                imageView?.removeFromSuperview()
                imageView = SVGImageView(document: attachment.document)
                svgViews[range.location] = imageView
                addSubview(imageView!)
            }
            let rect = firstRect(for: textRange)
            imageView?.frame = CGRect(origin: rect.origin, size: attachment.bounds.size)
            if let imageView { bringSubviewToFront(imageView) }
        }
        for location in Array(svgViews.keys) where !active.contains(location) {
            svgViews.removeValue(forKey: location)?.removeFromSuperview()
        }
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { selectionScroller?.stop() }
        else { selectionScroller?.attach() }
    }
}
