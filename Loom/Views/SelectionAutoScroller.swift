import UIKit

/// Observes touches without taking ownership from TextKit's native selection gestures.
@MainActor final class SelectionAutoScroller {
    private weak var textView: UITextView?
    private weak var scrollView: UIScrollView?
    private var observer: SelectionTouchObserver?
    private var timer: Timer?
    private var origin: CGPoint?
    private var point: CGPoint?
    private var anchor: Int?
    private var eligible = false

    init(textView: UITextView) { self.textView = textView }
    func attach() {
        guard observer == nil, let textView else { return }
        var ancestor = textView.superview
        while let view = ancestor {
            if let scroll = view as? UIScrollView, !(scroll is UITextView), scroll.contentSize.height > scroll.bounds.height + 1 {
                scrollView = scroll
                let observer = SelectionTouchObserver()
                observer.onTouch = { [weak self] phase, point in self?.touch(phase, point: point) }
                scroll.addGestureRecognizer(observer)
                self.observer = observer
                return
            }
            ancestor = view.superview
        }
        // Layout may not have established the scroll content size at didMoveToWindow.
        DispatchQueue.main.async { [weak self] in self?.attachAfterLayout() }
    }
    private func attachAfterLayout() {
        guard observer == nil, let textView else { return }
        var ancestor = textView.superview
        while let view = ancestor {
            if let scroll = view as? UIScrollView, !(scroll is UITextView), scroll.contentSize.height > scroll.bounds.height + 1 {
                scrollView = scroll
                let observer = SelectionTouchObserver()
                observer.onTouch = { [weak self] phase, point in self?.touch(phase, point: point) }
                scroll.addGestureRecognizer(observer); self.observer = observer
                return
            }
            ancestor = view.superview
        }
    }
    func touch(_ phase: UITouch.Phase, point: CGPoint) {
        guard let view = textView, let window = view.window else { return }
        switch phase {
        case .began:
            origin = point; self.point = point; anchor = nil
            let local = view.convert(point, from: window)
            if let selection = view.selectedTextRange, !selection.isEmpty {
                let start = view.caretRect(for: selection.start).insetBy(dx: -30, dy: -30)
                let end = view.caretRect(for: selection.end).insetBy(dx: -30, dy: -30)
                eligible = start.contains(local) || end.contains(local)
                if eligible {
                    anchor = start.contains(local) ? NSMaxRange(view.selectedRange) : view.selectedRange.location
                }
            } else { eligible = view.bounds.contains(local) }
        case .moved:
            self.point = point
            guard eligible, let origin, hypot(point.x - origin.x, point.y - origin.y) > 8, view.selectedRange.length > 0 else { return }
            if anchor == nil { anchor = view.selectedRange.location }
            if timer == nil {
                let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.step() }
                }
                self.timer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        default: endTouch()
        }
    }
    func step() {
        guard let view = textView, let window = view.window, let scroll = scrollView,
              let point, let anchor, view.selectedRange.length > 0 else { endTouch(); return }
        let viewport = scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: window)
        let band: CGFloat = 52
        let speed: CGFloat
        if point.y > viewport.maxY - band { speed = min(12, max(0, (point.y - viewport.maxY + band) / band * 12)) }
        else if point.y < viewport.minY + band { speed = -min(12, max(0, (viewport.minY + band - point.y) / band * 12)) }
        else { return }
        let minimum = -scroll.adjustedContentInset.top
        let maximum = max(minimum, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        let offset = min(maximum, max(minimum, scroll.contentOffset.y + speed))
        guard abs(offset - scroll.contentOffset.y) > 0.1 else { return }
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: offset), animated: false)
        if let position = view.closestPosition(to: view.convert(point, from: window)) {
            let cursor = view.offset(from: view.beginningOfDocument, to: position)
            view.selectedRange = NSRange(location: min(anchor, cursor), length: abs(cursor - anchor))
        }
    }
    private func endTouch() {
        timer?.invalidate(); timer = nil; origin = nil; point = nil; anchor = nil; eligible = false
    }
    func stop() {
        endTouch()
        if let observer { observer.view?.removeGestureRecognizer(observer) }
        observer = nil; scrollView = nil
    }
}

private final class SelectionTouchObserver: UIGestureRecognizer {
    var onTouch: ((UITouch.Phase, CGPoint) -> Void)?
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { report(touches, phase: .began) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { report(touches, phase: .moved) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { report(touches, phase: .ended); state = .failed }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { report(touches, phase: .cancelled); state = .failed }
    private func report(_ touches: Set<UITouch>, phase: UITouch.Phase) {
        if let touch = touches.first { onTouch?(phase, touch.location(in: view?.window)) }
    }
}
