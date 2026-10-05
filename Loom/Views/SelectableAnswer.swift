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
        view.keyboardDismissMode = .none
        view.alwaysBounceHorizontal = false
        view.contentInsetAdjustmentBehavior = .never
        view.textContainer.widthTracksTextView = true
        view.showsVerticalScrollIndicator = false
        view.showsHorizontalScrollIndicator = false
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
        let signature = RenderSignature(content: content, highlights: highlights, dynamicTypeSize: dynamicTypeSize, colorScheme: colorScheme)
        guard context.coordinator.signature != signature else { return }
        context.coordinator.signature = signature
        context.coordinator.measuredSize = nil
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
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        if let measured = context.coordinator.measuredSize, measured.width == width { return measured }
        uiView.prepareSVGLayout(width: width)
        let measured = CGSize(width: width, height: ceil(uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height))
        context.coordinator.measuredSize = measured
        return measured
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    static func dismantleUIView(_ uiView: ReadingTextView, coordinator: Coordinator) {
        uiView.selectionScroller?.stop()
        uiView.delegate = nil
    }

    struct RenderSignature: Equatable {
        let content: String
        let highlights: [Highlight]
        let dynamicTypeSize: DynamicTypeSize
        let colorScheme: ColorScheme
    }

    @MainActor final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: SelectableAnswer
        var signature: RenderSignature?
        var measuredSize: CGSize?
        var updating = false
        weak var tap: UITapGestureRecognizer?
        init(_ parent: SelectableAnswer) { self.parent = parent }

        func textView(_ textView: UITextView, editMenuForTextInRanges ranges: [NSValue], suggestedActions: [UIMenuElement]) -> UIMenu? {
            // Preserve every system action and its native presentation. Add one selection action.
            let range = ranges.first?.rangeValue ?? textView.selectedRange
            guard range.length > 0 else { return nil }
            let marked = parent.highlights.contains { HighlightResolver.resolve($0, in: textView.attributedText.string).map { NSIntersectionRange($0.range, range).length > 0 } == true }
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

    // This text view expands to its entire answer. Only the outer reader scrolls.
    // UIKit may request a horizontal caret offset while a page is being relaid out.
    override var contentOffset: CGPoint {
        get { super.contentOffset }
        set { super.contentOffset = CGPoint(x: 0, y: newValue.y) }
    }
    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        super.setContentOffset(CGPoint(x: 0, y: contentOffset.y), animated: animated)
    }

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

@MainActor final class ReaderScrollController {
    weak var scroll: UIScrollView?
    private var pendingOffset: CGFloat?
    func restore(_ offset: CGFloat) {
        guard let scroll else { pendingOffset = offset; return }
        scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
    }
    func attach(_ scroll: UIScrollView) {
        self.scroll = scroll
        if let pendingOffset { self.pendingOffset = nil; restore(pendingOffset) }

    }
}

/// Keep the vertical reader from acquiring a horizontal offset during native
/// selection, round jumps, or restoration inside the horizontal model pager.
struct VerticalReaderScrollLock: UIViewRepresentable {
    var controller: ReaderScrollController
    func makeUIView(context: Context) -> LockView { LockView() }
    func updateUIView(_ uiView: LockView, context: Context) { uiView.controller = controller; uiView.connect() }
    static func dismantleUIView(_ uiView: LockView, coordinator: ()) { uiView.disconnect() }

    final class LockView: UIView {
        weak var controller: ReaderScrollController?
        var observation: NSKeyValueObservation?
        weak var reader: UIScrollView?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { disconnect() }
            else { connect() }
        }
        func disconnect() {
            observation?.invalidate(); observation = nil
            reader?.panGestureRecognizer.removeTarget(self, action: #selector(readerPanned(_:)))
            reader = nil
        }
        @objc private func readerPanned(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .changed,
                  gesture.translation(in: self).y > 32,
                  gesture.velocity(in: self).y > 0 else { return }
            window?.endEditing(true)
        }
        func connect() {
            guard window != nil else { return }
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView, !scroll.isPagingEnabled, scroll.showsVerticalScrollIndicator {
                    guard reader !== scroll else { return }
                    disconnect()
                    reader = scroll
                    scroll.panGestureRecognizer.addTarget(self, action: #selector(readerPanned(_:)))
                    controller?.attach(scroll)
                    scroll.alwaysBounceHorizontal = false
                    scroll.isDirectionalLockEnabled = true
                    scroll.keyboardDismissMode = .none
                    observation = scroll.observe(\.contentOffset, options: [.initial, .new]) { [weak scroll] _, _ in
                        MainActor.assumeIsolated {
                            guard let scroll, abs(scroll.contentOffset.x) > 0.1 else { return }
                            scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentOffset.y), animated: false)
                        }
                    }
                    return
                }
                ancestor = view.superview
            }
        }
    }
}
