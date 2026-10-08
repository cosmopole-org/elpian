package dev.elpian.core.render.paint

import dev.elpian.core.css.Alignment
import dev.elpian.core.css.Border
import dev.elpian.core.css.BorderRadius
import dev.elpian.core.css.BoxFit
import dev.elpian.core.css.BoxShadow
import dev.elpian.core.css.Color
import dev.elpian.core.css.Filter
import dev.elpian.core.css.Gradient
import dev.elpian.core.css.Matrix
import dev.elpian.core.css.Matrix4
import dev.elpian.core.css.SizePx
import dev.elpian.core.render.Constraints
import dev.elpian.core.render.RenderObject
import dev.elpian.core.render.RenderProxy
import dev.elpian.core.render.TextStyle
import dev.elpian.core.render.Vec
import dev.elpian.core.render.ViewKinds
import dev.elpian.core.render.ViewProps
import dev.elpian.core.render.smallest
import kotlin.math.max
import kotlin.math.min

/**
 * Painting objects that own a plain `view` (render/paint/box.ts):
 * DecoratedBox, Opacity, Transform, ClipRRect/ClipOval, IgnorePointer,
 * Visibility, filters and ShaderMask — plus DefaultTextStyle, which paints
 * nothing but provides the inherited text style its descendants resolve
 * against.
 */

/** A background image (view prop `backgroundImage`). */
data class DecorationImage(
    val src: String,
    val fit: BoxFit?,
    val alignment: Alignment?,
    val repeat: String?,
    val size: SizePx? = null,
)

/** An outline (view prop `outline`). */
data class Outline(val width: Double, val color: Color, val style: String, val offset: Double)

data class Decoration(
    val color: Color? = null,
    val gradients: List<Gradient>? = null,
    val image: DecorationImage? = null,
    val border: Border? = null,
    val radius: BorderRadius? = null,
    /** Corner radii in percent of the box (CSS `border-radius: 50%`). */
    val radiusPercent: BorderRadius? = null,
    /** `rectangle` or `circle`. */
    val shape: String? = null,
    val shadows: List<BoxShadow>? = null,
    val outline: Outline? = null,
)

fun decorationIsEmpty(d: Decoration?): Boolean {
    if (d == null) return true
    return d.color == null &&
        d.gradients.isNullOrEmpty() &&
        d.image == null &&
        d.border == null &&
        d.radius == null &&
        d.radiusPercent == null &&
        d.shadows.isNullOrEmpty() &&
        d.outline == null &&
        d.shape != "circle"
}

fun resolveRadius(d: Decoration, width: Double, height: Double): BorderRadius? {
    val px = d.radius
    val pct = d.radiusPercent ?: return clampRadius(px, width, height)
    val basis = min(width, height)
    fun r(p: Double, x: Double?) = (if (p != 0.0 && !p.isNaN()) p / 100 * basis else 0.0) + (x ?: 0.0)
    return clampRadius(
        BorderRadius(
            r(pct.topLeft, px?.topLeft),
            r(pct.topRight, px?.topRight),
            r(pct.bottomRight, px?.bottomRight),
            r(pct.bottomLeft, px?.bottomLeft),
        ),
        width,
        height,
    )
}

/** Corners can never exceed half the shortest side (as Flutter/CSS scale them). */
private fun clampRadius(r: BorderRadius?, width: Double, height: Double): BorderRadius? {
    if (r == null) return null
    val mx = min(width, height) / 2
    fun c(v: Double) = max(0.0, min(v, mx))
    val out = BorderRadius(c(r.topLeft), c(r.topRight), c(r.bottomRight), c(r.bottomLeft))
    if (out.isZero) return null
    return out
}

fun decorationViewProps(d: Decoration, width: Double, height: Double): ViewProps = linkedMapOf(
    "background" to d.color,
    "gradients" to (if (!d.gradients.isNullOrEmpty()) d.gradients else null),
    "backgroundImage" to d.image,
    "border" to d.border,
    "radius" to (if (d.shape == "circle") null else resolveRadius(d, width, height)),
    "oval" to (if (d.shape == "circle") true else null),
    "shadows" to (if (!d.shadows.isNullOrEmpty()) d.shadows else null),
    "outline" to d.outline,
)

/** JavaScript truthiness of a loosely typed prop value. */
internal fun isTruthy(v: Any?): Boolean = when (v) {
    null -> false
    is Boolean -> v
    is Number -> v.toDouble().let { it != 0.0 && !it.isNaN() }
    is String -> v.isNotEmpty()
    else -> true
}

/**
 * Call a prop callback with the arguments it accepts (JavaScript ignores extra
 * arguments): a two-argument function receives both, a one-argument function
 * the first, a no-argument function none.
 */
@Suppress("UNCHECKED_CAST")
fun callHandler(fn: Any?, vararg args: Any?) {
    when {
        fn is Function2<*, *, *> -> (fn as (Any?, Any?) -> Any?)(args.getOrNull(0), args.getOrNull(1))
        fn is Function1<*, *> -> (fn as (Any?) -> Any?)(args.getOrNull(0))
        fn is Function0<*> -> (fn as () -> Any?)()
    }
}

/** props: { decoration: Decoration, clip?: boolean } */
open class RenderDecoratedBox : RenderProxy() {
    override fun viewKind(): String? = ViewKinds.VIEW
    override fun viewProps(): ViewProps {
        val d = props["decoration"] as? Decoration ?: Decoration()
        return decorationViewProps(d, size.width, size.height).also { it["clip"] = if (isTruthy(props["clip"])) true else null }
    }
}

/** props: { opacity } */
open class RenderOpacity : RenderProxy() {
    override fun viewKind(): String? = ViewKinds.VIEW
    override fun viewProps(): ViewProps {
        val o = (props["opacity"] as? Number)?.toDouble() ?: 1.0
        return linkedMapOf("opacity" to (if (o >= 1) null else max(0.0, o)))
    }
}

/**
 * props: { transform: Matrix4, alignment?: Alignment, origin?: [x, y] (px) }
 * The matrix is applied about the alignment point (Flutter `Transform` with
 * `alignment`), expressed to the platform as a transform + origin.
 */
open class RenderTransform : RenderProxy() {
    override fun viewKind(): String? = ViewKinds.VIEW

    open fun effectiveMatrix(): Matrix4 = props["transform"] as? Matrix4 ?: Matrix.identity()

    fun origin(): Pair<Double, Double> {
        when (val o = props["origin"]) {
            is Pair<*, *> -> return Pair((o.first as Number).toDouble(), (o.second as Number).toDouble())
            is DoubleArray -> return Pair(o[0], o[1])
            is List<*> -> return Pair((o[0] as Number).toDouble(), (o[1] as Number).toDouble())
            is Vec -> return Pair(o.x, o.y)
        }
        val a = props["alignment"] as? Alignment ?: Alignment(0.0, 0.0)
        return Pair(size.width / 2 * (1 + a.x), size.height / 2 * (1 + a.y))
    }

    override fun viewProps(): ViewProps {
        val m = effectiveMatrix()
        if (Matrix.isIdentity(m)) return linkedMapOf("transform" to null)
        val (ox, oy) = origin()
        return linkedMapOf("transform" to m, "transformOrigin" to listOf(ox, oy))
    }

    /** The full matrix in this view's coordinate space (used for hit testing). */
    fun matrixInSpace(): Matrix4 {
        val (ox, oy) = origin()
        return Matrix.aboutOrigin(effectiveMatrix(), ox, oy)
    }
}

/** props: { radius?: BorderRadius, oval?: boolean, enabled?: boolean } */
open class RenderClip : RenderProxy() {
    override fun viewKind(): String? = ViewKinds.VIEW
    override fun viewProps(): ViewProps {
        if (props["enabled"] == false) return LinkedHashMap()
        val r = props["radius"] as? BorderRadius
        return linkedMapOf(
            "clip" to true,
            "radius" to (if (r != null) resolveRadius(Decoration(radius = r), size.width, size.height) else null),
            "oval" to (if (isTruthy(props["oval"])) true else null),
        )
    }
}

/** props: { ignoring: boolean } */
open class RenderIgnorePointer : RenderProxy() {
    override fun viewKind(): String? = ViewKinds.VIEW
    override fun viewProps(): ViewProps = linkedMapOf("pointerEvents" to (if (props["ignoring"] == false) "auto" else "none"))
}

/**
 * props: { mode: 'gone' | 'hidden' | 'visible' }
 * `gone` (Flutter `Visibility(visible: false)`) takes no space and paints
 * nothing; `hidden` (CSS `visibility: hidden`) keeps its space.
 */
open class RenderVisibility : RenderObject() {
    override fun performLayout(c: Constraints) {
        val ch = child
        if (props["mode"] == "gone") {
            ch?.layout(c)
            size = smallest(c)
            return
        }
        if (ch != null) {
            ch.layout(c)
            ch.offset = Vec(0.0, 0.0)
            size = ch.size.copy()
        } else size = smallest(c)
    }

    override fun paintsChild(child: RenderObject): Boolean = props["mode"] != "gone"
    override fun viewKind(): String? = if (props["mode"] == "hidden") ViewKinds.VIEW else null
    override fun viewProps(): ViewProps = linkedMapOf("hidden" to true)
}

/** props: { filter?: Filter, backdrop?: Filter, blendMode?: string, zIndex?: number } */
open class RenderFilter : RenderProxy() {
    override fun viewKind(): String? = ViewKinds.VIEW
    override fun viewProps(): ViewProps = linkedMapOf(
        "filter" to (props["filter"] as? Filter),
        "backdropFilter" to (props["backdrop"] as? Filter),
        "blendMode" to props["blendMode"],
    )
}

/** props: { gradient: Gradient } — ShaderMask(srcATop) as Shimmer uses it. */
open class RenderShaderMask : RenderProxy() {
    override fun viewKind(): String? = ViewKinds.VIEW
    override fun viewProps(): ViewProps = linkedMapOf("shaderMask" to (props["gradient"] as? Gradient))
}

/**
 * props: { style: TextStyle, textAlign?, maxLines?, overflow?, softWrap? }
 * Provides the inherited text style (Flutter `DefaultTextStyle`).
 */
open class RenderDefaultTextStyle : RenderProxy() {
    val textStyle: TextStyle get() = props["style"] as? TextStyle ?: TextStyle()
}
