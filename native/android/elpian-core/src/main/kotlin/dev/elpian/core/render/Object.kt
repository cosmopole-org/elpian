package dev.elpian.core.render

import kotlin.math.max

/**
 * The render-object tree: a port of Flutter's box protocol (render/object.ts
 * in the TypeScript core). Lowering turns Elpian nodes into widget
 * descriptors ([W]); the reconciler keeps one [RenderObject] per descriptor
 * across renders; layout runs constraints-down / sizes-up; the compositor
 * turns painting objects into native views.
 */
data class Constraints(val minWidth: Double, val maxWidth: Double, val minHeight: Double, val maxHeight: Double) {
    val isTight: Boolean get() = minWidth >= maxWidth && minHeight >= maxHeight
}

data class Size(var width: Double, var height: Double)

data class Vec(var x: Double, var y: Double)

const val INF = Double.POSITIVE_INFINITY

fun tight(width: Double, height: Double) = Constraints(width, width, height, height)
fun loose(c: Constraints) = Constraints(0.0, c.maxWidth, 0.0, c.maxHeight)
fun clampN(v: Double, lo: Double, hi: Double): Double = if (v < lo) lo else if (v > hi) hi else v

fun tightFor(c: Constraints, width: Double?, height: Double?) = Constraints(
    if (width != null) clampN(width, c.minWidth, c.maxWidth) else c.minWidth,
    if (width != null) clampN(width, c.minWidth, c.maxWidth) else c.maxWidth,
    if (height != null) clampN(height, c.minHeight, c.maxHeight) else c.minHeight,
    if (height != null) clampN(height, c.minHeight, c.maxHeight) else c.maxHeight,
)

/** Flutter `BoxConstraints.enforce`. */
fun enforce(inner: Constraints, outer: Constraints) = Constraints(
    clampN(inner.minWidth, outer.minWidth, outer.maxWidth),
    clampN(inner.maxWidth, outer.minWidth, outer.maxWidth),
    clampN(inner.minHeight, outer.minHeight, outer.maxHeight),
    clampN(inner.maxHeight, outer.minHeight, outer.maxHeight),
)

fun deflate(c: Constraints, h: Double, v: Double): Constraints {
    val minW = max(0.0, c.minWidth - h)
    val minH = max(0.0, c.minHeight - v)
    return Constraints(minW, max(minW, c.maxWidth - h), minH, max(minH, c.maxHeight - v))
}

fun constrain(c: Constraints, s: Size) = Size(clampN(s.width, c.minWidth, c.maxWidth), clampN(s.height, c.minHeight, c.maxHeight))
fun biggest(c: Constraints) = Size(if (c.maxWidth.isFinite()) c.maxWidth else c.minWidth, if (c.maxHeight.isFinite()) c.maxHeight else c.minHeight)
fun smallest(c: Constraints) = Size(c.minWidth, c.minHeight)

/** A widget descriptor: what lowering produces and the reconciler consumes. */
class W(
    /** Render-object type (`padding`, `flex`, `text`, …). */
    val t: String,
    /** Configuration. */
    val p: MutableMap<String, Any?>,
    val c: List<W>? = null,
    /** Identity across renders (Flutter `Key`). */
    val k: String? = null,
)

fun w(t: String, p: Map<String, Any?> = emptyMap(), c: List<W>? = null, k: String? = null): W = W(t, LinkedHashMap(p), c, k)
fun w(t: String, p: Map<String, Any?>, child: W?, k: String? = null): W = W(t, LinkedHashMap(p), child?.let { listOf(it) }, k)

/** Property bag access with the TypeScript core's loose typing. */
typealias Props = MutableMap<String, Any?>

fun Map<String, Any?>.d(key: String): Double? = (this[key] as? Number)?.toDouble()
fun Map<String, Any?>.s(key: String): String? = this[key] as? String
fun Map<String, Any?>.b(key: String): Boolean = this[key] == true

/** View props: the map the compositor diffs and the renderer applies (keys of view.ts `ViewProps`). */
typealias ViewProps = MutableMap<String, Any?>

abstract class RenderObject {
    var type = ""
    var key: String? = null
    var props: Props = LinkedHashMap()
    var parent: RenderObject? = null
    var children: MutableList<RenderObject> = ArrayList()
    var owner: RenderOwner? = null

    var size = Size(0.0, 0.0)
    /** Offset of this object's top-left inside its parent's coordinate space. */
    var offset = Vec(0.0, 0.0)

    var needsLayout = true
    private var lastConstraints: Constraints? = null
    private val intrinsicCache = HashMap<String, Double>()

    /** The native view this object owns, when it paints. */
    var viewId: Int? = null

    open fun init(props: Props) {
        this.props = props
    }

    open fun update(props: Props) {
        val old = this.props
        this.props = props
        didUpdate(old)
        markNeedsLayout()
    }

    protected open fun didUpdate(old: Props) {}

    fun attach(owner: RenderOwner) {
        this.owner = owner
        onAttach()
    }

    open fun detach() {
        onDetach()
        for (c in children) c.detach()
        owner = null
    }

    protected open fun onAttach() {}
    protected open fun onDetach() {}

    fun markNeedsLayout() {
        var node: RenderObject? = this
        while (node != null && !node.needsLayout) {
            node.needsLayout = true
            node.intrinsicCache.clear()
            node = node.parent
        }
        node?.intrinsicCache?.clear()
        owner?.requestVisualUpdate()
    }

    /** Paint-only change: re-emit this view's props without relayout. */
    fun markNeedsPaint() {
        owner?.markPaintDirty(this)
    }

    fun layout(c: Constraints) {
        if (!needsLayout && lastConstraints == c) return
        lastConstraints = c
        performLayout(c)
        if (!size.width.isFinite()) size.width = if (c.minWidth.isFinite()) c.minWidth else 0.0
        if (!size.height.isFinite()) size.height = if (c.minHeight.isFinite()) c.minHeight else 0.0
        needsLayout = false
        intrinsicCache.clear()
    }

    val constraints: Constraints? get() = lastConstraints

    protected abstract fun performLayout(c: Constraints)

    val child: RenderObject? get() = children.firstOrNull()

    fun minIntrinsicWidth(height: Double): Double = cached("minW", height) { computeMinIntrinsicWidth(height) }
    fun maxIntrinsicWidth(height: Double): Double = cached("maxW", height) { computeMaxIntrinsicWidth(height) }
    fun minIntrinsicHeight(width: Double): Double = cached("minH", width) { computeMinIntrinsicHeight(width) }
    fun maxIntrinsicHeight(width: Double): Double = cached("maxH", width) { computeMaxIntrinsicHeight(width) }

    private inline fun cached(kind: String, extent: Double, compute: () -> Double): Double {
        val key = "$kind:$extent"
        intrinsicCache[key]?.let { return it }
        return compute().also { intrinsicCache[key] = it }
    }

    protected open fun computeMinIntrinsicWidth(height: Double): Double = child?.minIntrinsicWidth(height) ?: 0.0
    protected open fun computeMaxIntrinsicWidth(height: Double): Double = child?.maxIntrinsicWidth(height) ?: 0.0
    protected open fun computeMinIntrinsicHeight(width: Double): Double = child?.minIntrinsicHeight(width) ?: 0.0
    protected open fun computeMaxIntrinsicHeight(width: Double): Double = child?.maxIntrinsicHeight(width) ?: 0.0

    /** Distance from the top to the first alphabetic baseline, if any. */
    open fun baseline(): Double? {
        val c = child ?: return null
        return c.baseline()?.let { it + c.offset.y }
    }

    /** The native view kind when this object owns a view, otherwise null. */
    open fun viewKind(): String? = null

    /** This object's view props (frame excluded — the compositor fills it). */
    open fun viewProps(): ViewProps = LinkedHashMap()

    /** Offset added to children inside this object's own view. */
    open fun childOriginInView(): Vec = Vec(0.0, 0.0)

    /** Whether [child] is painted (IndexedStack / Offstage hide some children). */
    open fun paintsChild(child: RenderObject): Boolean = true

    /** The platform reported an event on this object's view. */
    open fun handleViewEvent(event: ViewEvent) {}

    fun visit(fn: (RenderObject) -> Unit) {
        fn(this)
        for (c in children) c.visit(fn)
    }

    override fun toString(): String = "$type${key?.let { "#$it" } ?: ""}(${"%.1f".format(size.width)}x${"%.1f".format(size.height)})"
}

/** A single-child object that sizes to its child (or the smallest size without one). */
open class RenderProxy : RenderObject() {
    override fun performLayout(c: Constraints) {
        val ch = child
        if (ch != null) {
            ch.layout(c)
            ch.offset = Vec(0.0, 0.0)
            size = ch.size.copy()
        } else size = smallest(c)
    }
}
