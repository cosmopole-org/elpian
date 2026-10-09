#if canImport(UIKit)
import UIKit
#if !ELPIAN_SINGLE_MODULE
import ElpianCore
#endif

/**
 * The `scroll` view kind (ScrollContainer.kt): a UIScrollView over a content
 * space of `contentSize` (vertical, horizontal or both) whose children are
 * positioned relative to the content origin. Flings and bounces with the
 * platform's physics, shows scroll indicators and reports offsets back to the
 * core once per frame. A drag only starts along the scroll axis, never when a
 * gesture inside claimed the touch (a pan / draggable / scale / pointer
 * recognizer), and cancels the touch for the views inside when it does.
 */
final class ScrollContainer: UIScrollView, UIScrollViewDelegate {
    private weak var owner: ElpianView?

    var axis = "vertical" {
        didSet { applyAxis() }
    }
    var scrollingEnabled = true {
        didSet { isScrollEnabled = scrollingEnabled }
    }
    var showScrollbar = true {
        didSet { applyAxis() }
    }
    /** Content size in points. */
    private var content: CGSize = .zero
    private var reportPosted = false

    init(owner: ElpianView) {
        self.owner = owner
        super.init(frame: .zero)
        delegate = self
        delaysContentTouches = false
        canCancelContentTouches = true
        isDirectionalLockEnabled = true
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        clipsToBounds = true
        isMultipleTouchEnabled = true
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        applyAxis()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var vertical: Bool { axis != "horizontal" }
    private var horizontal: Bool { axis != "vertical" }

    private func applyAxis() {
        showsVerticalScrollIndicator = showScrollbar && vertical
        showsHorizontalScrollIndicator = showScrollbar && horizontal
        alwaysBounceVertical = vertical && !horizontal
        alwaysBounceHorizontal = horizontal && !vertical
        updateContentSize()
    }

    func setContentSize(_ w: Double, _ h: Double) {
        content = CGSize(width: w, height: h)
        updateContentSize()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateContentSize()
    }

    /** The scrollable size: the content along the scroll axes, the viewport across. */
    private func updateContentSize() {
        let w = horizontal ? max(content.width, bounds.width) : bounds.width
        let h = vertical ? max(content.height, bounds.height) : bounds.height
        let size = CGSize(width: w, height: h)
        if contentSize != size { contentSize = size }
        let maxX = max(0, w - bounds.width)
        let maxY = max(0, h - bounds.height)
        if contentOffset.x > maxX || contentOffset.y > maxY {
            if !isDragging && !isDecelerating { contentOffset = CGPoint(x: min(contentOffset.x, maxX), y: min(contentOffset.y, maxY)) }
        }
    }

    private var maxX: CGFloat { max(0, contentSize.width - bounds.width) }
    private var maxY: CGFloat { max(0, contentSize.height - bounds.height) }

    private func canScrollAny() -> Bool { scrollingEnabled && ((vertical && maxY > 0) || (horizontal && maxX > 0)) }

    /** Scroll to logical (x, y), animated when [smooth]. */
    func scrollToLogical(_ x: Double, _ y: Double, smooth: Bool) {
        let tx = horizontal ? min(maxX, max(0, CGFloat(x))) : 0
        let ty = vertical ? min(maxY, max(0, CGFloat(y))) : 0
        setContentOffset(CGPoint(x: tx, y: ty), animated: smooth)
    }

    // ---------------------------------------------------------------------
    // Touches
    // ---------------------------------------------------------------------

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if isHidden || !isUserInteractionEnabled || alpha < 0.01 { return nil }
        guard self.point(inside: point, with: event) || bounds.contains(point) else { return nil }
        if let hit = ElpianHitTest.children(of: self, point, event) { return hit }
        return canScrollAny() ? self : nil
    }

    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard g === panGestureRecognizer else { return super.gestureRecognizerShouldBegin(g) }
        if !scrollingEnabled { return false }
        if let router = owner?.host?.surface.router, !router.allowsIntercept(by: self) { return false }
        let v = panGestureRecognizer.velocity(in: self)
        let dx = abs(v.x)
        let dy = abs(v.y)
        // Along the axis only, so a cross-axis drag (Dismissible, a horizontal list) is left to it.
        if vertical && !horizontal { return maxY > 0 || alwaysBounceVertical ? dy >= dx * 0.5 && dy > 0 : false }
        if horizontal && !vertical { return maxX > 0 || alwaysBounceHorizontal ? dx >= dy * 0.5 && dx > 0 : false }
        return super.gestureRecognizerShouldBegin(g)
    }

    override func touchesShouldCancel(in view: UIView) -> Bool { true }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // The scroll took the gesture over: the views inside lose the touch.
        owner?.host?.surface.router.cancelTouches(within: self)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if reportPosted { return }
        reportPosted = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let o = self.owner else { return }
            self.reportPosted = false
            o.host?.emit(ViewEvent(id: o.viewId, type: "scroll", scrollX: Double(self.contentOffset.x), scrollY: Double(self.contentOffset.y)))
        }
    }
}
#endif
