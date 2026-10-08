package dev.elpian.core.render.layout

import dev.elpian.core.css.Alignment
import dev.elpian.core.css.EdgeInsets
import dev.elpian.core.css.Matrix
import dev.elpian.core.css.Matrix4
import dev.elpian.core.css.SidePercents
import dev.elpian.core.render.*
import kotlin.math.PI
import kotlin.math.max
import kotlin.math.min

/**
 * Single-child layout objects (render/layout/basic.ts): RenderPadding,
 * RenderConstrainedBox, Align, AspectRatio, FractionallySizedBox, LimitedBox,
 * OverflowBox, FittedBox, Baseline, RotatedBox, IntrinsicWidth/Height,
 * Offstage, IndexedStack, SafeArea and the fill-axis helper.
 */
fun alignOffset(alignment: Alignment, outer: Size, inner: Size) = Vec(
    (outer.width - inner.width) / 2 * (1 + alignment.x),
    (outer.height - inner.height) / 2 * (1 + alignment.y),
)

fun Map<String, Any?>.alignment(key: String = "alignment", fallback: Alignment = Alignment.center): Alignment = this[key] as? Alignment ?: fallback

open class RenderPadding : RenderObject() {
    /** Padding with percentage sides resolved against the incoming max width (CSS). */
    open fun resolvedPadding(c: Constraints?): EdgeInsets {
        val p = props["padding"] as? EdgeInsets ?: EdgeInsets.ZERO
        val pct = props["percent"] as? SidePercents ?: return p
        val basis = if (c != null && c.maxWidth.isFinite()) c.maxWidth else 0.0
        return EdgeInsets(
            pct.top?.let { it.pct / 100 * basis } ?: p.top,
            pct.right?.let { it.pct / 100 * basis } ?: p.right,
            pct.bottom?.let { it.pct / 100 * basis } ?: p.bottom,
            pct.left?.let { it.pct / 100 * basis } ?: p.left,
        )
    }

    override fun performLayout(c: Constraints) {
        val p = resolvedPadding(c)
        val h = max(0.0, p.left + p.right)
        val v = max(0.0, p.top + p.bottom)
        val ch = child
        if (ch == null) {
            size = constrain(c, Size(h, v))
            return
        }
        ch.layout(deflate(c, h, v))
        ch.offset = Vec(p.left, p.top)
        size = constrain(c, Size(ch.size.width + h, ch.size.height + v))
    }

    override fun computeMinIntrinsicWidth(height: Double): Double {
        val p = resolvedPadding(null)
        return (child?.minIntrinsicWidth(max(0.0, height - p.top - p.bottom)) ?: 0.0) + p.left + p.right
    }
    override fun computeMaxIntrinsicWidth(height: Double): Double {
        val p = resolvedPadding(null)
        return (child?.maxIntrinsicWidth(max(0.0, height - p.top - p.bottom)) ?: 0.0) + p.left + p.right
    }
    override fun computeMinIntrinsicHeight(width: Double): Double {
        val p = resolvedPadding(null)
        return (child?.minIntrinsicHeight(max(0.0, width - p.left - p.right)) ?: 0.0) + p.top + p.bottom
    }
    override fun computeMaxIntrinsicHeight(width: Double): Double {
        val p = resolvedPadding(null)
        return (child?.maxIntrinsicHeight(max(0.0, width - p.left - p.right)) ?: 0.0) + p.top + p.bottom
    }
}

/**
 * props: minWidth, maxWidth, minHeight, maxHeight, width, height — `width` /
 * `height` tighten that axis (SizedBox); min/max add constraints.
 */
open class RenderConstrainedBox : RenderObject() {
    fun additional(): Constraints {
        val p = props
        var minW = p.d("minWidth") ?: 0.0
        var maxW = p.d("maxWidth") ?: INF
        var minH = p.d("minHeight") ?: 0.0
        var maxH = p.d("maxHeight") ?: INF
        p.d("width")?.let { minW = it; maxW = it }
        p.d("height")?.let { minH = it; maxH = it }
        if (maxW < minW) maxW = minW
        if (maxH < minH) maxH = minH
        return Constraints(minW, maxW, minH, maxH)
    }

    override fun performLayout(c: Constraints) {
        val inner = enforce(additional(), c)
        val ch = child
        if (ch != null) {
            ch.layout(inner)
            ch.offset = Vec(0.0, 0.0)
            size = ch.size.copy()
        } else size = constrain(inner, Size(0.0, 0.0))
    }

    override fun computeMinIntrinsicWidth(height: Double): Double {
        val a = additional()
        if (a.minWidth >= a.maxWidth && a.minWidth.isFinite()) return a.minWidth
        return clampN(child?.minIntrinsicWidth(height) ?: 0.0, a.minWidth, a.maxWidth)
    }
    override fun computeMaxIntrinsicWidth(height: Double): Double {
        val a = additional()
        if (a.minWidth >= a.maxWidth && a.minWidth.isFinite()) return a.minWidth
        return clampN(child?.maxIntrinsicWidth(height) ?: 0.0, a.minWidth, a.maxWidth)
    }
    override fun computeMinIntrinsicHeight(width: Double): Double {
        val a = additional()
        if (a.minHeight >= a.maxHeight && a.minHeight.isFinite()) return a.minHeight
        return clampN(child?.minIntrinsicHeight(width) ?: 0.0, a.minHeight, a.maxHeight)
    }
    override fun computeMaxIntrinsicHeight(width: Double): Double {
        val a = additional()
        if (a.minHeight >= a.maxHeight && a.minHeight.isFinite()) return a.minHeight
        return clampN(child?.maxIntrinsicHeight(width) ?: 0.0, a.minHeight, a.maxHeight)
    }
}

/** props: alignment, widthFactor, heightFactor */
open class RenderAlign : RenderObject() {
    override fun performLayout(c: Constraints) {
        val alignment = props.alignment()
        val wf = props.d("widthFactor")
        val hf = props.d("heightFactor")
        val shrinkW = wf != null || !c.maxWidth.isFinite()
        val shrinkH = hf != null || !c.maxHeight.isFinite()
        val ch = child
        if (ch != null) {
            ch.layout(loose(c))
            size = constrain(c, Size(if (shrinkW) ch.size.width * (wf ?: 1.0) else INF, if (shrinkH) ch.size.height * (hf ?: 1.0) else INF))
            ch.offset = alignOffset(alignment, size, ch.size)
        } else size = constrain(c, Size(if (shrinkW) 0.0 else INF, if (shrinkH) 0.0 else INF))
    }

    override fun computeMinIntrinsicWidth(height: Double) = (child?.minIntrinsicWidth(height) ?: 0.0) * (props.d("widthFactor") ?: 1.0)
    override fun computeMaxIntrinsicWidth(height: Double) = (child?.maxIntrinsicWidth(height) ?: 0.0) * (props.d("widthFactor") ?: 1.0)
    override fun computeMinIntrinsicHeight(width: Double) = (child?.minIntrinsicHeight(width) ?: 0.0) * (props.d("heightFactor") ?: 1.0)
    override fun computeMaxIntrinsicHeight(width: Double) = (child?.maxIntrinsicHeight(width) ?: 0.0) * (props.d("heightFactor") ?: 1.0)
}

class RenderAspectRatio : RenderObject() {
    private val ratio: Double get() = props.d("aspectRatio")?.takeIf { it > 0 } ?: 1.0

    private fun apply(c: Constraints): Size {
        val ar = ratio
        if (c.isTight) return smallest(c)
        var width = c.maxWidth
        var height: Double
        if (width.isFinite()) height = width / ar else {
            height = c.maxHeight
            width = height * ar
        }
        if (width > c.maxWidth) { width = c.maxWidth; height = width / ar }
        if (height > c.maxHeight) { height = c.maxHeight; width = height * ar }
        if (width < c.minWidth) { width = c.minWidth; height = width / ar }
        if (height < c.minHeight) { height = c.minHeight; width = height * ar }
        if (!width.isFinite() || !height.isFinite()) return Size(0.0, 0.0)
        return constrain(c, Size(width, height))
    }

    override fun performLayout(c: Constraints) {
        size = apply(c)
        child?.let {
            it.layout(tight(size.width, size.height))
            it.offset = Vec(0.0, 0.0)
        }
    }

    override fun computeMinIntrinsicWidth(height: Double) = if (height.isFinite()) height * ratio else child?.minIntrinsicWidth(height) ?: 0.0
    override fun computeMaxIntrinsicWidth(height: Double) = if (height.isFinite()) height * ratio else child?.maxIntrinsicWidth(height) ?: 0.0
    override fun computeMinIntrinsicHeight(width: Double) = if (width.isFinite()) width / ratio else child?.minIntrinsicHeight(width) ?: 0.0
    override fun computeMaxIntrinsicHeight(width: Double) = if (width.isFinite()) width / ratio else child?.maxIntrinsicHeight(width) ?: 0.0
}

/** props: widthFactor, heightFactor, alignment, fallbackWidth, fallbackHeight */
class RenderFractional : RenderObject() {
    override fun performLayout(c: Constraints) {
        var inner = c
        props.d("widthFactor")?.let { wf ->
            if (c.maxWidth.isFinite()) {
                val w = c.maxWidth * wf
                inner = inner.copy(minWidth = w, maxWidth = w)
            } else props.d("fallbackWidth")?.let { inner = inner.copy(minWidth = it, maxWidth = it) }
        }
        props.d("heightFactor")?.let { hf ->
            if (c.maxHeight.isFinite()) {
                val h = c.maxHeight * hf
                inner = inner.copy(minHeight = h, maxHeight = h)
            } else props.d("fallbackHeight")?.let { inner = inner.copy(minHeight = it, maxHeight = it) }
        }
        val ch = child
        if (ch != null) {
            ch.layout(inner)
            size = constrain(c, ch.size)
            ch.offset = alignOffset(props.alignment(), size, ch.size)
        } else size = constrain(c, Size(inner.minWidth, inner.minHeight))
    }
}

class RenderLimitedBox : RenderObject() {
    override fun performLayout(c: Constraints) {
        fun limit(min: Double, l: Double?) = if (l == null) INF else max(min, l)
        val limited = Constraints(
            c.minWidth,
            if (c.maxWidth.isFinite()) c.maxWidth else limit(c.minWidth, props.d("maxWidth")),
            c.minHeight,
            if (c.maxHeight.isFinite()) c.maxHeight else limit(c.minHeight, props.d("maxHeight")),
        )
        val ch = child
        if (ch != null) {
            ch.layout(limited)
            ch.offset = Vec(0.0, 0.0)
            size = constrain(c, ch.size)
        } else size = constrain(limited, Size(0.0, 0.0))
    }
}

/** props: alignment, minWidth, maxWidth, minHeight, maxHeight (null = the parent's). */
class RenderOverflowBox : RenderObject() {
    override fun performLayout(c: Constraints) {
        val inner = Constraints(props.d("minWidth") ?: c.minWidth, props.d("maxWidth") ?: c.maxWidth, props.d("minHeight") ?: c.minHeight, props.d("maxHeight") ?: c.maxHeight)
        size = biggest(c)
        child?.let {
            it.layout(inner)
            it.offset = alignOffset(props.alignment(), size, it.size)
        }
    }
}

/** FittedBox: scales its child (the child sits in a [RenderFittedContent] transform view). */
class RenderFittedBox : RenderObject() {
    private var scaleX = 1.0
    private var scaleY = 1.0
    private var childOffset = Vec(0.0, 0.0)

    override fun performLayout(c: Constraints) {
        val ch = child
        if (ch == null) {
            size = smallest(c)
            return
        }
        ch.layout(Constraints(0.0, INF, 0.0, INF))
        val cs = ch.size
        size = preserveAspect(c, cs)
        val (sx, sy) = fitScale(props.s("fit") ?: "contain", cs, size)
        scaleX = sx
        scaleY = sy
        childOffset = alignOffset(props.alignment(), size, Size(cs.width * sx, cs.height * sy))
        ch.offset = Vec(0.0, 0.0)
    }

    override fun viewKind() = ViewKinds.VIEW
    override fun viewProps(): ViewProps = linkedMapOf("clip" to (props["clip"] != false))

    val contentTransform: Matrix4 get() = Matrix.multiply(Matrix.translation(childOffset.x, childOffset.y), Matrix.scaling(scaleX, scaleY, 1.0))
}

fun fitScale(fit: String, child: Size, box: Size): Pair<Double, Double> {
    if (child.width <= 0 || child.height <= 0) return 1.0 to 1.0
    val rw = box.width / child.width
    val rh = box.height / child.height
    return when (fit) {
        "fill" -> rw to rh
        "cover" -> max(rw, rh).let { it to it }
        "fitWidth" -> rw to rw
        "fitHeight" -> rh to rh
        "none" -> 1.0 to 1.0
        "scaleDown" -> min(1.0, min(rw, rh)).let { it to it }
        else -> min(rw, rh).let { it to it }
    }
}

fun preserveAspect(c: Constraints, s: Size): Size {
    if (c.isTight) return smallest(c)
    var width = s.width
    var height = s.height
    if (width <= 0 || height <= 0) return constrain(c, s)
    val ar = width / height
    if (width > c.maxWidth) { width = c.maxWidth; height = width / ar }
    if (height > c.maxHeight) { height = c.maxHeight; width = height * ar }
    if (width < c.minWidth) { width = c.minWidth; height = width / ar }
    if (height < c.minHeight) { height = c.minHeight; width = height * ar }
    return constrain(c, Size(width, height))
}

/** The scaled content of a FittedBox: a transform view holding the child at its natural size. */
class RenderFittedContent : RenderProxy() {
    override fun viewKind() = ViewKinds.VIEW
    override fun viewProps(): ViewProps {
        val fitted = parent as? RenderFittedBox
        return linkedMapOf("transform" to (fitted?.contentTransform ?: Matrix.identity()), "transformOrigin" to listOf(0.0, 0.0))
    }
}

class RenderBaseline : RenderObject() {
    override fun performLayout(c: Constraints) {
        val ch = child
        if (ch == null) {
            size = smallest(c)
            return
        }
        ch.layout(loose(c))
        val top = (props.d("baseline") ?: 0.0) - (ch.baseline() ?: ch.size.height)
        ch.offset = Vec(0.0, top)
        size = constrain(c, Size(ch.size.width, top + ch.size.height))
    }
}

/** RotatedBox: quarter turns, swapping the axes. */
class RenderRotatedBox : RenderObject() {
    private val turns: Int get() = (((props.d("quarterTurns") ?: 0.0).toInt() % 4) + 4) % 4

    override fun performLayout(c: Constraints) {
        val odd = turns % 2 == 1
        val ch = child
        if (ch == null) {
            size = smallest(c)
            return
        }
        ch.layout(if (odd) Constraints(c.minHeight, c.maxHeight, c.minWidth, c.maxWidth) else c)
        size = if (odd) Size(ch.size.height, ch.size.width) else ch.size.copy()
        ch.offset = Vec(0.0, 0.0)
    }

    override fun viewKind() = ViewKinds.VIEW
    override fun viewProps(): ViewProps {
        val ch = child ?: return LinkedHashMap()
        val m = Matrix.multiply(
            Matrix.translation(size.width / 2, size.height / 2),
            Matrix.multiply(Matrix.rotationZ(turns * PI / 2), Matrix.translation(-ch.size.width / 2, -ch.size.height / 2)),
        )
        return linkedMapOf("transform" to m, "transformOrigin" to listOf(0.0, 0.0))
    }

    override fun computeMinIntrinsicWidth(height: Double) = if (turns % 2 == 1) child?.minIntrinsicHeight(height) ?: 0.0 else child?.minIntrinsicWidth(height) ?: 0.0
    override fun computeMaxIntrinsicWidth(height: Double) = if (turns % 2 == 1) child?.maxIntrinsicHeight(height) ?: 0.0 else child?.maxIntrinsicWidth(height) ?: 0.0
}

/** props: onlyWhenUnbounded (Flutter's `_flexSafe`). */
class RenderIntrinsicWidth : RenderObject() {
    override fun performLayout(c: Constraints) {
        val ch = child
        if (ch == null) {
            size = smallest(c)
            return
        }
        var inner = c
        val applies = !props.b("onlyWhenUnbounded") || !c.maxWidth.isFinite()
        if (applies && c.minWidth < c.maxWidth) {
            val w = clampN(ch.maxIntrinsicWidth(c.maxHeight), c.minWidth, c.maxWidth)
            inner = c.copy(minWidth = w, maxWidth = w)
        }
        ch.layout(inner)
        ch.offset = Vec(0.0, 0.0)
        size = ch.size.copy()
    }
}

class RenderIntrinsicHeight : RenderObject() {
    override fun performLayout(c: Constraints) {
        val ch = child
        if (ch == null) {
            size = smallest(c)
            return
        }
        var inner = c
        if (c.minHeight < c.maxHeight) {
            val h = clampN(ch.maxIntrinsicHeight(c.maxWidth), c.minHeight, c.maxHeight)
            inner = c.copy(minHeight = h, maxHeight = h)
        }
        ch.layout(inner)
        ch.offset = Vec(0.0, 0.0)
        size = ch.size.copy()
    }
}

/** Lays the child out but takes no space and paints nothing (`offstage: true`). */
class RenderOffstage : RenderProxy() {
    override fun performLayout(c: Constraints) {
        if (props["offstage"] == false) {
            super.performLayout(c)
            return
        }
        child?.layout(c)
        size = smallest(c)
    }

    override fun paintsChild(child: RenderObject) = props["offstage"] == false
}

/** props: index, alignment — every child keeps its state; one paints. */
class RenderIndexedStack : RenderObject() {
    override fun performLayout(c: Constraints) {
        val alignment = props.alignment(fallback = Alignment.topLeft)
        var w = 0.0
        var h = 0.0
        val inner = loose(c)
        for (ch in children) {
            ch.layout(inner)
            w = max(w, ch.size.width)
            h = max(h, ch.size.height)
        }
        size = if (children.isNotEmpty()) constrain(c, Size(w, h)) else biggest(c)
        for (ch in children) ch.offset = alignOffset(alignment, size, ch.size)
    }

    override fun paintsChild(child: RenderObject): Boolean {
        val index = (props.d("index") ?: 0.0).toInt().coerceIn(0, max(0, children.size - 1))
        return children.getOrNull(index) === child
    }
}

/** SafeArea: pads by the platform's safe-area insets. props: top/right/bottom/left booleans (default true). */
class RenderSafeArea : RenderPadding() {
    override fun resolvedPadding(c: Constraints?): EdgeInsets {
        val o = owner
        val inset = if (o != null) o.platform.viewport(o.surface).safeArea else EdgeInsets.ZERO
        return EdgeInsets(
            if (props["top"] != false) inset.top else 0.0,
            if (props["right"] != false) inset.right else 0.0,
            if (props["bottom"] != false) inset.bottom else 0.0,
            if (props["left"] != false) inset.left else 0.0,
        )
    }
}

/** `SizedBox(width: double.infinity)` only when the axis is bounded. props: width / height booleans. */
class RenderFillAxis : RenderObject() {
    override fun performLayout(c: Constraints) {
        val fillW = props.b("width") && c.maxWidth.isFinite()
        val fillH = props.b("height") && c.maxHeight.isFinite()
        val inner = Constraints(if (fillW) c.maxWidth else c.minWidth, c.maxWidth, if (fillH) c.maxHeight else c.minHeight, c.maxHeight)
        val ch = child
        if (ch != null) {
            ch.layout(inner)
            ch.offset = Vec(0.0, 0.0)
            size = ch.size.copy()
        } else size = constrain(inner, Size(0.0, 0.0))
    }
}
