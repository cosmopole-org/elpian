import Foundation

/** A callback a render object reports platform view events to (`onScroll`, `onTap` …). */
public typealias ViewEventHandler = (ViewEvent) -> Void

/**
 * RenderScroll — `SingleChildScrollView` / `ListView` / overflow:auto
 * (render/layout/scroll.ts).
 *
 * The child is laid out unbounded along the scroll axis; the box itself takes
 * the incoming constraints. The platform owns the actual scrolling (native
 * scroll physics, momentum, scrollbars); it reports offsets back so hit
 * testing and drag targets account for them, and the core restores the
 * offset after a re-render.
 *
 * props: { axis: 'vertical'|'horizontal'|'both', enabled, scrollbar, stretchCross,
 *          fillViewport, reportScroll, onScroll: [ViewEventHandler] }
 */
open class RenderScroll: RenderObject, ScrollOffsetHolder {
    public var scrollOffset = Vec.zero
    private var contentWidth = 0.0
    private var contentHeight = 0.0

    private var axis: String { props.s("axis") ?? "vertical" }

    open override func performLayout(_ c: Constraints) {
        let axis = self.axis
        var inner: Constraints
        if axis == "vertical" {
            inner = Constraints(
                minWidth: jsTruthy(props["stretchCross"]) ? c.maxWidth : c.minWidth,
                maxWidth: c.maxWidth,
                // A document root is at least as tall as the viewport (Flutter's
                // ConstrainedBox(minHeight: maxHeight) inside the scroll view).
                minHeight: jsTruthy(props["fillViewport"]) && c.maxHeight.isFinite ? c.maxHeight : 0,
                maxHeight: INF
            )
            if !inner.minWidth.isFinite { inner.minWidth = 0 }
        } else if axis == "horizontal" {
            inner = Constraints(minWidth: 0, maxWidth: INF, minHeight: jsTruthy(props["stretchCross"]) ? c.maxHeight : c.minHeight, maxHeight: c.maxHeight)
            if !inner.minHeight.isFinite { inner.minHeight = 0 }
        } else {
            inner = Constraints(minWidth: 0, maxWidth: INF, minHeight: 0, maxHeight: INF)
        }
        if let child = child {
            child.layout(inner)
            child.offset = .zero
            contentWidth = child.size.width
            contentHeight = child.size.height
            size = constrain(c, child.size)
        } else {
            contentWidth = 0
            contentHeight = 0
            size = constrain(c, .zero)
        }
        // Keep the restored offset within the new content.
        scrollOffset = Vec(
            x: max(0, min(scrollOffset.x, contentWidth - size.width)),
            y: max(0, min(scrollOffset.y, contentHeight - size.height))
        )
    }

    open override func viewKind() -> ViewKind? { .scroll }

    open override func viewProps() -> ViewProps {
        ViewProps([
            ("scrollAxis", axis),
            ("contentSize", [max(contentWidth, size.width), max(contentHeight, size.height)] as [Any?]),
            ("scrollEnabled", !props.isFalse("enabled")),
            ("showScrollbar", !props.isFalse("scrollbar")),
            ("clip", true),
            ("gestures", jsTruthy(props["reportScroll"]) ? ["scroll"] as [Any?] : nil),
        ])
    }

    open override func handleViewEvent(_ event: ViewEvent) {
        if event.type == "scroll" {
            scrollOffset = Vec(x: event.scrollX ?? scrollOffset.x, y: event.scrollY ?? scrollOffset.y)
            (props["onScroll"] as? ViewEventHandler)?(event)
        }
    }

    open override func computeMinIntrinsicWidth(_ height: Double) -> Double { axis == "vertical" ? child?.minIntrinsicWidth(height) ?? 0 : 0 }
    open override func computeMaxIntrinsicWidth(_ height: Double) -> Double { child?.maxIntrinsicWidth(height) ?? 0 }
    open override func computeMinIntrinsicHeight(_ width: Double) -> Double { axis == "horizontal" ? child?.minIntrinsicHeight(width) ?? 0 : 0 }
    open override func computeMaxIntrinsicHeight(_ width: Double) -> Double { child?.maxIntrinsicHeight(width) ?? 0 }
}
