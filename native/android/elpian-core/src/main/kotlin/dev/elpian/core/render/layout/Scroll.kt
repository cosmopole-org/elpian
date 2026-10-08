package dev.elpian.core.render.layout

import dev.elpian.core.render.*
import kotlin.math.max
import kotlin.math.min

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
 *          fillViewport, reportScroll, onScroll: (ViewEvent) -> Unit }
 */
class RenderScroll : RenderObject(), ScrollOffsetHolder {
    override var scrollOffset = Vec(0.0, 0.0)
    private var contentWidth = 0.0
    private var contentHeight = 0.0

    private val axis: String get() = props.s("axis") ?: "vertical"

    override fun performLayout(c: Constraints) {
        val axis = this.axis
        val ch = child
        var inner: Constraints
        if (axis == "vertical") {
            inner = Constraints(
                if (truthy(props["stretchCross"])) c.maxWidth else c.minWidth,
                c.maxWidth,
                // A document root is at least as tall as the viewport (Flutter's
                // ConstrainedBox(minHeight: maxHeight) inside the scroll view).
                if (truthy(props["fillViewport"]) && c.maxHeight.isFinite()) c.maxHeight else 0.0,
                INF,
            )
            if (!inner.minWidth.isFinite()) inner = inner.copy(minWidth = 0.0)
        } else if (axis == "horizontal") {
            inner = Constraints(0.0, INF, if (truthy(props["stretchCross"])) c.maxHeight else c.minHeight, c.maxHeight)
            if (!inner.minHeight.isFinite()) inner = inner.copy(minHeight = 0.0)
        } else {
            inner = Constraints(0.0, INF, 0.0, INF)
        }
        if (ch != null) {
            ch.layout(inner)
            ch.offset = Vec(0.0, 0.0)
            contentWidth = ch.size.width
            contentHeight = ch.size.height
            size = constrain(c, ch.size)
        } else {
            contentWidth = 0.0
            contentHeight = 0.0
            size = constrain(c, Size(0.0, 0.0))
        }
        // Keep the restored offset within the new content.
        scrollOffset = Vec(
            max(0.0, min(scrollOffset.x, contentWidth - size.width)),
            max(0.0, min(scrollOffset.y, contentHeight - size.height)),
        )
    }

    override fun viewKind(): String = ViewKinds.SCROLL

    override fun viewProps(): ViewProps = linkedMapOf(
        "scrollAxis" to axis,
        "contentSize" to listOf(max(contentWidth, size.width), max(contentHeight, size.height)),
        "scrollEnabled" to (props["enabled"] != false),
        "showScrollbar" to (props["scrollbar"] != false),
        "clip" to true,
        "gestures" to (if (truthy(props["reportScroll"])) listOf("scroll") else null),
    )

    override fun handleViewEvent(event: ViewEvent) {
        if (event.type == "scroll") {
            scrollOffset = Vec(event.scrollX ?: scrollOffset.x, event.scrollY ?: scrollOffset.y)
            @Suppress("UNCHECKED_CAST")
            (props["onScroll"] as? (ViewEvent) -> Any?)?.invoke(event)
        }
    }

    override fun computeMinIntrinsicWidth(height: Double): Double = if (axis == "vertical") child?.minIntrinsicWidth(height) ?: 0.0 else 0.0
    override fun computeMaxIntrinsicWidth(height: Double): Double = child?.maxIntrinsicWidth(height) ?: 0.0
    override fun computeMinIntrinsicHeight(width: Double): Double = if (axis == "horizontal") child?.minIntrinsicHeight(width) ?: 0.0 else 0.0
    override fun computeMaxIntrinsicHeight(width: Double): Double = child?.maxIntrinsicHeight(width) ?: 0.0
}
