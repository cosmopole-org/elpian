package dev.elpian.core.render.layout

import dev.elpian.core.css.Alignment
import dev.elpian.core.render.*
import kotlin.math.max

/**
 * RenderStack + Positioned parent data — Flutter's `Stack`
 * (render/layout/stack.ts).
 *
 * Non-positioned children are laid out with loose (or expanded) constraints
 * and the stack sizes to the largest; positioned children are placed by their
 * top/right/bottom/left/width/height against the stack's box. Children paint
 * in order, so z-order is the child order (lowering sorts by `z-index`).
 */

/** props: { top, right, bottom, left, width, height } */
class RenderPositioned : RenderObject() {
    val isPositioned: Boolean
        get() {
            val p = props
            return p["top"] != null || p["right"] != null || p["bottom"] != null || p["left"] != null || p["width"] != null || p["height"] != null
        }

    override fun performLayout(c: Constraints) {
        val ch = child
        if (ch != null) {
            ch.layout(c)
            ch.offset = Vec(0.0, 0.0)
            size = ch.size.copy()
        } else size = constrain(c, Size(props.d("width") ?: 0.0, props.d("height") ?: 0.0))
    }
}

private fun isPositionedChild(ch: RenderObject) = ch is RenderPositioned && ch.isPositioned

/** props: { alignment, fit: 'loose'|'expand'|'passthrough', clip } */
class RenderStack : RenderObject() {
    override fun performLayout(c: Constraints) {
        val alignment = props.alignment(fallback = Alignment(-1.0, -1.0))
        val fit = props.s("fit") ?: "loose"
        val nonPositioned = when (fit) {
            "expand" -> {
                val b = biggest(c)
                Constraints(b.width, b.width, b.height, b.height)
            }
            "passthrough" -> c
            else -> loose(c)
        }
        var hasNonPositioned = false
        var width = c.minWidth
        var height = c.minHeight
        for (ch in children) {
            if (isPositionedChild(ch)) continue
            hasNonPositioned = true
            ch.layout(nonPositioned)
            width = max(width, ch.size.width)
            height = max(height, ch.size.height)
        }
        size = if (hasNonPositioned) constrain(c, Size(width, height)) else biggest(c)
        if (!size.width.isFinite() || !size.height.isFinite()) size = constrain(c, smallest(c))
        for (ch in children) {
            if (ch is RenderPositioned && ch.isPositioned) layoutPositioned(ch, alignment)
            else ch.offset = alignOffset(alignment, size, ch.size)
        }
    }

    private fun layoutPositioned(child: RenderPositioned, alignment: Alignment) {
        val p = child.props
        val left = p.d("left")
        val right = p.d("right")
        val top = p.d("top")
        val bottom = p.d("bottom")
        val pw = p.d("width")
        val ph = p.d("height")
        val W = size.width
        val H = size.height
        var c = Constraints(0.0, INF, 0.0, INF)
        if (left != null && right != null) {
            val w = max(0.0, W - right - left)
            c = c.copy(minWidth = w, maxWidth = w)
        } else if (pw != null) c = c.copy(minWidth = pw, maxWidth = pw)
        if (top != null && bottom != null) {
            val h = max(0.0, H - bottom - top)
            c = c.copy(minHeight = h, maxHeight = h)
        } else if (ph != null) c = c.copy(minHeight = ph, maxHeight = ph)
        child.layout(c)
        val x = when {
            left != null -> left
            right != null -> W - right - child.size.width
            else -> ((W - child.size.width) / 2) * (1 + alignment.x)
        }
        val y = when {
            top != null -> top
            bottom != null -> H - bottom - child.size.height
            else -> ((H - child.size.height) / 2) * (1 + alignment.y)
        }
        child.offset = Vec(x, y)
    }

    /** A stack that clips needs its own view; otherwise it is layout-only. */
    override fun viewKind(): String? = if (truthy(props["clip"])) ViewKinds.VIEW else null

    override fun viewProps(): ViewProps = linkedMapOf("clip" to truthy(props["clip"]))

    override fun computeMinIntrinsicWidth(height: Double): Double {
        var m = 0.0
        for (ch in children) if (!isPositionedChild(ch)) m = max(m, ch.minIntrinsicWidth(height))
        return m
    }
    override fun computeMaxIntrinsicWidth(height: Double): Double {
        var m = 0.0
        for (ch in children) if (!isPositionedChild(ch)) m = max(m, ch.maxIntrinsicWidth(height))
        return m
    }
    override fun computeMinIntrinsicHeight(width: Double): Double {
        var m = 0.0
        for (ch in children) if (!isPositionedChild(ch)) m = max(m, ch.minIntrinsicHeight(width))
        return m
    }
    override fun computeMaxIntrinsicHeight(width: Double): Double {
        var m = 0.0
        for (ch in children) if (!isPositionedChild(ch)) m = max(m, ch.maxIntrinsicHeight(width))
        return m
    }
}

/** JavaScript truthiness of a props value. */
internal fun truthy(v: Any?): Boolean = when (v) {
    null -> false
    is Boolean -> v
    is Number -> v.toDouble().let { it != 0.0 && !it.isNaN() }
    is String -> v.isNotEmpty()
    else -> true
}
