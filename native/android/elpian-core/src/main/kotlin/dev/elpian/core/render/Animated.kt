package dev.elpian.core.render

import dev.elpian.core.animation.AnimationController
import dev.elpian.core.animation.AnimationStatus
import dev.elpian.core.animation.Curve
import dev.elpian.core.animation.Curves
import dev.elpian.core.animation.ImplicitValue
import dev.elpian.core.animation.Lerp
import dev.elpian.core.animation.interval
import dev.elpian.core.animation.lerpNumber
import dev.elpian.core.css.Alignment
import dev.elpian.core.css.BorderRadius
import dev.elpian.core.css.CSSParser
import dev.elpian.core.css.Color
import dev.elpian.core.css.EdgeInsets
import dev.elpian.core.css.Gradient
import dev.elpian.core.css.GradientKind
import dev.elpian.core.css.Keyframe
import dev.elpian.core.css.Matrix
import dev.elpian.core.css.Matrix4
import dev.elpian.core.css.lerpColor
import dev.elpian.core.render.layout.RenderAlign
import dev.elpian.core.render.layout.RenderConstrainedBox
import dev.elpian.core.render.layout.RenderPadding
import dev.elpian.core.render.layout.RenderPositioned
import dev.elpian.core.render.paint.Decoration
import dev.elpian.core.render.paint.RenderDecoratedBox
import dev.elpian.core.render.paint.RenderDefaultTextStyle
import dev.elpian.core.render.paint.RenderOpacity
import dev.elpian.core.render.paint.RenderShaderMask
import dev.elpian.core.render.paint.RenderTransform
import dev.elpian.core.render.paint.decorationViewProps
import dev.elpian.core.render.paint.isTruthy
import dev.elpian.core.util.deepEqual
import kotlin.math.PI
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/**
 * Animated render objects (render/animated.ts).
 *
 * Implicit animations (Flutter `AnimatedContainer`, `AnimatedOpacity`,
 * `AnimatedPadding`, `AnimatedAlign`, `AnimatedPositioned`, `AnimatedScale`,
 * `AnimatedRotation`, `AnimatedSlide`, `AnimatedSize`,
 * `AnimatedDefaultTextStyle`, `AnimatedCrossFade`, `AnimatedSwitcher`, plus
 * CSS transitions) animate from the current value whenever a re-render
 * changes the target. Explicit animations (`FadeTransition`,
 * `SlideTransition`, `ScaleTransition`, `RotationTransition`,
 * `SizeTransition`, `TweenAnimationBuilder`, `StaggeredAnimation`, `Shimmer`,
 * `Pulse`, `AnimatedGradient`, CSS `@keyframes`) run their own controller from
 * the moment they mount.
 *
 * All of them tick on the owner's frame clock; only paint props change on
 * most frames (opacity / transform / colours), so the platform animates them
 * without relayout.
 */

/** The `curve` prop: a [Curve] function or a curve name. */
@Suppress("UNCHECKED_CAST")
internal fun curveOf(props: Map<String, Any?>, fallback: Curve = Curves.linear): Curve {
    val c = props["curve"]
    if (c is Function1<*, *>) return c as Curve
    return Curves.byName(c as? String, fallback)
}

private fun <T> eq(a: T, b: T): Boolean = deepEqual(a, b)

private fun lerpNullable(a: Double?, b: Double?, t: Double): Double? {
    if (a == null || b == null) return if (t < 0.5) a else b
    return a + (b - a) * t
}

/** JavaScript truthiness of a number (`0` and `NaN` are false). */
private fun truthy(v: Double): Boolean = v != 0.0 && !v.isNaN()

/** An `[x, y]` pair prop (list, array, [Pair] or [Vec]); null when absent. */
private fun pairOf(v: Any?): DoubleArray? = when (v) {
    null -> null
    is DoubleArray -> v
    is List<*> -> doubleArrayOf((v.getOrNull(0) as? Number)?.toDouble() ?: Double.NaN, (v.getOrNull(1) as? Number)?.toDouble() ?: Double.NaN)
    is Pair<*, *> -> doubleArrayOf((v.first as? Number)?.toDouble() ?: Double.NaN, (v.second as? Number)?.toDouble() ?: Double.NaN)
    is Vec -> doubleArrayOf(v.x, v.y)
    else -> null
}

/** `p?.[i] ?? fallback`: a missing pair or element falls back. */
private fun pairAt(v: Any?, i: Int, fallback: Double): Double = when (v) {
    is List<*> -> (v.getOrNull(i) as? Number)?.toDouble() ?: fallback
    else -> pairOf(v)?.getOrNull(i) ?: fallback
}

/** JavaScript `!==` for prop values: numbers by value, everything else by identity / primitive equality. */
private fun strictNotEqual(a: Any?, b: Any?): Boolean {
    if (a is Number && b is Number) return a.toDouble() != b.toDouble()
    if (a is String || a is Boolean || b is String || b is Boolean) return a != b
    return a !== b
}

private fun colorProp(v: Any?): Color? = (v as? Number)?.toInt()

// ============================================================================
// Implicit
// ============================================================================

/** props: padding, percent, duration, curve */
class RenderAnimatedPadding : RenderPadding() {
    private lateinit var value: ImplicitValue<EdgeInsets>

    override fun init(props: Props) {
        super.init(props)
        value = ImplicitValue(props["padding"] as? EdgeInsets ?: EdgeInsets(0.0, 0.0, 0.0, 0.0), EdgeInsets::lerp, ::eq) { markNeedsLayout() }
    }

    override fun didUpdate(old: Props) {
        value.set(props["padding"] as? EdgeInsets ?: EdgeInsets(0.0, 0.0, 0.0, 0.0), props.d("duration"), curveOf(props), owner)
    }

    override fun resolvedPadding(c: Constraints?): EdgeInsets {
        val saved = props["padding"]
        props["padding"] = value.current
        val out = super.resolvedPadding(c)
        props["padding"] = saved
        return out
    }

    override fun onDetach() {
        value.dispose()
    }
}

/** props: alignment, widthFactor, heightFactor, duration, curve */
class RenderAnimatedAlign : RenderAlign() {
    private lateinit var value: ImplicitValue<Alignment>

    override fun init(props: Props) {
        super.init(props)
        value = ImplicitValue(props["alignment"] as? Alignment ?: Alignment(0.0, 0.0), Alignment::lerp, ::eq) { markNeedsLayout() }
    }

    override fun didUpdate(old: Props) {
        value.set(props["alignment"] as? Alignment ?: Alignment(0.0, 0.0), props.d("duration"), curveOf(props), owner)
    }

    override fun performLayout(c: Constraints) {
        val saved = props["alignment"]
        props["alignment"] = value.current
        super.performLayout(c)
        props["alignment"] = saved
    }

    override fun onDetach() {
        value.dispose()
    }
}

/** props: opacity, duration, curve */
class RenderAnimatedOpacity : RenderOpacity() {
    private lateinit var value: ImplicitValue<Double>

    override fun init(props: Props) {
        super.init(props)
        value = ImplicitValue(props.d("opacity") ?: 1.0, lerpNumber, { a, b -> a == b }) { markNeedsPaint() }
    }

    override fun didUpdate(old: Props) {
        value.set(props.d("opacity") ?: 1.0, props.d("duration"), curveOf(props), owner)
    }

    override fun viewProps(): ViewProps {
        val o = value.current
        return linkedMapOf("opacity" to (if (o >= 1) null else max(0.0, o)))
    }

    override fun onDetach() {
        value.dispose()
    }
}

/** The animated parts of an [RenderAnimatedTransform]. */
class TransformTarget(
    val scale: Double,
    val turns: Double,
    val slideX: Double,
    val slideY: Double,
    val tx: Double,
    val ty: Double,
    val base: Matrix4,
) {
    override fun equals(other: Any?): Boolean =
        other is TransformTarget && scale == other.scale && turns == other.turns && slideX == other.slideX && slideY == other.slideY &&
            tx == other.tx && ty == other.ty && base.contentEquals(other.base)

    override fun hashCode(): Int = listOf(scale, turns, slideX, slideY, tx, ty, base.contentHashCode()).hashCode()
}

val lerpTransformTarget: Lerp<TransformTarget> = { a, b, t ->
    TransformTarget(
        scale = lerpNumber(a.scale, b.scale, t),
        turns = lerpNumber(a.turns, b.turns, t),
        slideX = lerpNumber(a.slideX, b.slideX, t),
        slideY = lerpNumber(a.slideY, b.slideY, t),
        tx = lerpNumber(a.tx, b.tx, t),
        ty = lerpNumber(a.ty, b.ty, t),
        base = Matrix.lerp(a.base, b.base, t),
    )
}

/**
 * AnimatedScale / AnimatedRotation / AnimatedSlide / CSS transform transitions.
 * props: { scale, turns, slide: [x, y] (fractions of size), translate: [x, y] px,
 *          transform: Matrix4, alignment, duration, curve }
 */
class RenderAnimatedTransform : RenderTransform() {
    private lateinit var value: ImplicitValue<TransformTarget>

    private fun targetOf(p: Map<String, Any?>): TransformTarget = TransformTarget(
        scale = p.d("scale") ?: 1.0,
        turns = p.d("turns") ?: 0.0,
        slideX = pairAt(p["slide"], 0, 0.0),
        slideY = pairAt(p["slide"], 1, 0.0),
        tx = pairAt(p["translate"], 0, 0.0),
        ty = pairAt(p["translate"], 1, 0.0),
        base = p["transform"] as? Matrix4 ?: Matrix.identity(),
    )

    override fun init(props: Props) {
        super.init(props)
        value = ImplicitValue(targetOf(props), lerpTransformTarget, { a, b -> a == b }) { markNeedsPaint() }
    }

    override fun didUpdate(old: Props) {
        value.set(targetOf(props), props.d("duration"), curveOf(props), owner)
    }

    override fun effectiveMatrix(): Matrix4 {
        val v = value.current
        var m = v.base
        if (truthy(v.slideX) || truthy(v.slideY) || truthy(v.tx) || truthy(v.ty)) {
            m = Matrix.multiply(Matrix.translation(v.slideX * size.width + v.tx, v.slideY * size.height + v.ty), m)
        }
        if (truthy(v.turns)) m = Matrix.multiply(m, Matrix.rotationZ(v.turns * PI * 2))
        if (v.scale != 1.0) m = Matrix.multiply(m, Matrix.scaling(v.scale, v.scale, 1.0))
        return m
    }

    override fun onDetach() {
        value.dispose()
    }
}

data class BoxTarget(val width: Double?, val height: Double?)

/** AnimatedContainer's size: props minWidth…maxHeight, width, height, duration, curve */
class RenderAnimatedConstrained : RenderConstrainedBox() {
    private lateinit var value: ImplicitValue<BoxTarget>

    override fun init(props: Props) {
        super.init(props)
        value = ImplicitValue(
            BoxTarget(props.d("width"), props.d("height")),
            { a, b, t -> BoxTarget(lerpNullable(a.width, b.width, t), lerpNullable(a.height, b.height, t)) },
            ::eq,
        ) { markNeedsLayout() }
    }

    override fun didUpdate(old: Props) {
        value.set(BoxTarget(props.d("width"), props.d("height")), props.d("duration"), curveOf(props), owner)
    }

    override fun additional(): Constraints {
        val savedW = props["width"]
        val savedH = props["height"]
        props["width"] = value.current.width
        props["height"] = value.current.height
        val out = super.additional()
        props["width"] = savedW
        props["height"] = savedH
        return out
    }

    override fun onDetach() {
        value.dispose()
    }
}

data class DecorationTarget(
    val color: Color?,
    val radius: BorderRadius?,
    val borderColor: Color?,
    val borderWidth: Double,
)

/** AnimatedContainer's decoration: colour, radius and uniform border animate. */
class RenderAnimatedDecorated : RenderDecoratedBox() {
    private lateinit var value: ImplicitValue<DecorationTarget>

    private fun targetOf(d: Decoration?): DecorationTarget = DecorationTarget(
        color = d?.color,
        radius = d?.radius,
        borderColor = d?.border?.top?.color,
        borderWidth = d?.border?.top?.width ?: 0.0,
    )

    override fun init(props: Props) {
        super.init(props)
        value = ImplicitValue(
            targetOf(props["decoration"] as? Decoration),
            { a, b, t ->
                DecorationTarget(
                    color = if (a.color == null || b.color == null) (if (t < 0.5) a.color else b.color) else lerpColor(a.color, b.color, t),
                    radius = if (a.radius != null && b.radius != null) BorderRadius.lerp(a.radius, b.radius, t) else if (t < 0.5) a.radius else b.radius,
                    borderColor = if (a.borderColor == null || b.borderColor == null) (if (t < 0.5) a.borderColor else b.borderColor) else lerpColor(a.borderColor, b.borderColor, t),
                    borderWidth = lerpNumber(a.borderWidth, b.borderWidth, t),
                )
            },
            ::eq,
        ) { markNeedsPaint() }
    }

    override fun didUpdate(old: Props) {
        value.set(targetOf(props["decoration"] as? Decoration), props.d("duration"), curveOf(props), owner)
    }

    override fun viewProps(): ViewProps {
        var d = (props["decoration"] as? Decoration ?: Decoration())
        val v = value.current
        d = d.copy(color = v.color, radius = v.radius)
        val border = d.border
        val bc = v.borderColor
        if (border != null && bc != null) {
            fun side(s: dev.elpian.core.css.BorderSide) =
                s.copy(color = bc, width = if (s.style == dev.elpian.core.css.BorderStyleName.none) s.width else v.borderWidth)
            d = d.copy(border = dev.elpian.core.css.Border(side(border.top), side(border.right), side(border.bottom), side(border.left)))
        }
        return decorationViewProps(d, size.width, size.height)
    }

    override fun onDetach() {
        value.dispose()
    }
}

data class PosTarget(
    val top: Double?,
    val right: Double?,
    val bottom: Double?,
    val left: Double?,
    val width: Double?,
    val height: Double?,
)

/**
 * AnimatedPositioned. The current animated values are written into the props
 * (the parent stack reads them) whenever they change and before layout.
 */
class RenderAnimatedPositioned : RenderPositioned() {
    private var value: ImplicitValue<PosTarget>? = null

    private fun targetOf(p: Map<String, Any?>) = PosTarget(p.d("top"), p.d("right"), p.d("bottom"), p.d("left"), p.d("width"), p.d("height"))

    private fun assignCurrent() {
        val v = value?.current ?: return
        props["top"] = v.top
        props["right"] = v.right
        props["bottom"] = v.bottom
        props["left"] = v.left
        props["width"] = v.width
        props["height"] = v.height
    }

    override fun init(props: Props) {
        super.init(props)
        value = ImplicitValue(
            targetOf(props),
            { a, b, t ->
                PosTarget(
                    top = lerpNullable(a.top, b.top, t),
                    right = lerpNullable(a.right, b.right, t),
                    bottom = lerpNullable(a.bottom, b.bottom, t),
                    left = lerpNullable(a.left, b.left, t),
                    width = lerpNullable(a.width, b.width, t),
                    height = lerpNullable(a.height, b.height, t),
                )
            },
            ::eq,
        ) {
            // TS overrides markNeedsLayout to sync props first; same effect.
            assignCurrent()
            markNeedsLayout()
        }
        assignCurrent()
    }

    override fun didUpdate(old: Props) {
        val target = targetOf(props)
        value?.set(target, props.d("duration"), curveOf(props), owner)
        assignCurrent()
    }

    override fun performLayout(c: Constraints) {
        assignCurrent()
        super.performLayout(c)
    }

    override fun onDetach() {
        value?.dispose()
    }
}

val lerpTextStyle: Lerp<TextStyle> = { a, b, t ->
    var out = if (t < 0.5) a else b
    if (a.color != null && b.color != null) out = out.copy(color = lerpColor(a.color, b.color, t))
    if (a.fontSize != null && b.fontSize != null) out = out.copy(fontSize = a.fontSize + (b.fontSize - a.fontSize) * t)
    if (a.letterSpacing != null && b.letterSpacing != null) out = out.copy(letterSpacing = a.letterSpacing + (b.letterSpacing - a.letterSpacing) * t)
    if (a.wordSpacing != null && b.wordSpacing != null) out = out.copy(wordSpacing = a.wordSpacing + (b.wordSpacing - a.wordSpacing) * t)
    if (a.height != null && b.height != null) out = out.copy(height = a.height + (b.height - a.height) * t)
    if (a.fontWeight != null && b.fontWeight != null) {
        out = out.copy(fontWeight = (floor((a.fontWeight + (b.fontWeight - a.fontWeight) * t) / 100 + 0.5) * 100).toInt())
    }
    out
}

/** AnimatedDefaultTextStyle: props style, duration, curve. */
class RenderAnimatedDefaultTextStyle : RenderDefaultTextStyle() {
    private lateinit var value: ImplicitValue<TextStyle>

    override fun init(props: Props) {
        super.init(props)
        value = ImplicitValue(props["style"] as? TextStyle ?: TextStyle(), lerpTextStyle, ::eq) { markDescendantsDirty() }
    }

    override fun didUpdate(old: Props) {
        value.set(props["style"] as? TextStyle ?: TextStyle(), props.d("duration"), curveOf(props), owner)
    }

    override val textStyle: TextStyle get() = value.current

    private fun markDescendantsDirty() {
        visit { ro -> if (ro.type == "text") ro.markNeedsLayout() }
    }

    override fun performLayout(c: Constraints) {
        val saved = props["style"]
        props["style"] = value.current
        super.performLayout(c)
        props["style"] = saved
    }

    override fun onDetach() {
        value.dispose()
    }
}

/** AnimatedSize: animates its own size towards the child's. props duration, curve, alignment */
class RenderAnimatedSize : RenderObject() {
    private var controller: AnimationController? = null
    private var fromSize = Size(0.0, 0.0)
    private var toSize: Size? = null
    private var hasLaidOut = false

    override fun performLayout(c: Constraints) {
        val ch = child
        if (ch == null) {
            size = constrain(c, Size(0.0, 0.0))
            return
        }
        ch.layout(c)
        val target = ch.size.copy()
        val duration = props.d("duration")
        val to0 = toSize
        if (!hasLaidOut || duration == null || !truthy(duration)) {
            hasLaidOut = true
            toSize = target
            fromSize = target
            size = constrain(c, target)
        } else if (to0 != null && (target.width != to0.width || target.height != to0.height)) {
            fromSize = size.copy()
            toSize = target
            val ctl = controller ?: AnimationController(duration).also { ctl ->
                controller = ctl
                ctl.addListener { markNeedsLayout() }
            }
            ctl.duration = duration
            owner?.let { ctl.attach(it) }
            ctl.forward(0.0)
        }
        val ctl = controller
        val t = if (ctl != null && ctl.isAnimating) curveOf(props)(ctl.value) else 1.0
        val to = toSize ?: target
        size = constrain(
            c,
            Size(
                fromSize.width + (to.width - fromSize.width) * t,
                fromSize.height + (to.height - fromSize.height) * t,
            ),
        )
        val a = props["alignment"] as? Alignment ?: Alignment(0.0, 0.0)
        ch.offset = Vec((size.width - ch.size.width) / 2 * (1 + a.x), (size.height - ch.size.height) / 2 * (1 + a.y))
    }

    override fun viewKind(): String? = ViewKinds.VIEW
    override fun viewProps(): ViewProps = linkedMapOf("clip" to true)

    override fun onDetach() {
        controller?.detach()
        controller?.stop()
    }
}

/**
 * AnimatedCrossFade: props { showFirst, duration, curve } with exactly two
 * children (each an opacity holder created by lowering).
 */
class RenderAnimatedCrossFade : RenderObject() {
    private var controller: AnimationController? = null

    override fun onAttach() {
        val ctl = controller ?: AnimationController(props.d("duration") ?: 300.0, if (props["showFirst"] == false) 1.0 else 0.0).also { ctl ->
            controller = ctl
            ctl.addListener { markNeedsLayout() }
        }
        ctl.attach(owner!!)
    }

    override fun didUpdate(old: Props) {
        val ctl = controller ?: return
        ctl.duration = props.d("duration") ?: 300.0
        if ((old["showFirst"] != false) != (props["showFirst"] != false)) {
            if (props["showFirst"] == false) ctl.forward() else ctl.reverse()
        }
    }

    private val t: Double
        get() {
            val v = controller?.value ?: (if (props["showFirst"] == false) 1.0 else 0.0)
            return curveOf(props)(v)
        }

    override fun performLayout(c: Constraints) {
        val first = children.getOrNull(0)
        val second = children.getOrNull(1)
        val inner = Constraints(0.0, c.maxWidth, 0.0, c.maxHeight)
        first?.layout(inner)
        second?.layout(inner)
        val t = this.t
        val a = first?.size ?: Size(0.0, 0.0)
        val b = second?.size ?: Size(0.0, 0.0)
        size = constrain(c, Size(a.width + (b.width - a.width) * t, a.height + (b.height - a.height) * t))
        if (first != null) {
            first.offset = Vec(0.0, 0.0)
            first.props["opacity"] = 1 - t
            first.markNeedsPaint()
        }
        if (second != null) {
            second.offset = Vec(0.0, 0.0)
            second.props["opacity"] = t
            second.markNeedsPaint()
        }
    }

    override fun viewKind(): String? = ViewKinds.VIEW
    override fun viewProps(): ViewProps = linkedMapOf("clip" to true)

    override fun paintsChild(child: RenderObject): Boolean {
        val t = this.t
        if (child === children.getOrNull(0)) return t < 1
        return t > 0
    }

    override fun onDetach() {
        controller?.detach()
        controller?.stop()
    }
}

/**
 * AnimatedSwitcher: when the child's identity changes, the old child stays
 * mounted and transitions out while the new one transitions in.
 * props { duration, transitionType: 'fade'|'scale'|'rotation'|'slide', curve }
 */
class RenderAnimatedSwitcher : RenderObject() {
    /** Children leaving, with their remaining progress controllers. */
    val outgoing = LinkedHashMap<RenderObject, AnimationController>()
    val incoming = LinkedHashMap<RenderObject, AnimationController>()
    private var mounted = false

    /** Called by the reconciler when the current child is replaced. */
    fun childReplaced(oldChild: RenderObject, newChild: RenderObject) {
        childRemoved(oldChild)
        startIncoming(newChild)
    }

    /** Transition [oldChild] out, then detach it. */
    fun childRemoved(oldChild: RenderObject) {
        val duration = props.d("duration") ?: 300.0
        val o = owner
        if (o == null || duration <= 0) {
            oldChild.detach()
            children = children.filter { it !== oldChild }.toMutableList()
            return
        }
        val out = AnimationController(duration, 1.0)
        out.attach(o)
        out.addListener { markNeedsLayout() }
        outgoing[oldChild] = out
        // Keep the old child mounted (painted beneath the new one) while it leaves.
        if (children.none { it === oldChild }) children.add(0, oldChild)
        oldChild.parent = this
        out.reverse().then {
            outgoing.remove(oldChild)
            oldChild.detach()
            children = children.filter { it !== oldChild }.toMutableList()
            markNeedsLayout()
        }
    }

    private fun startIncoming(child: RenderObject) {
        val o = owner ?: return
        val c = AnimationController(props.d("duration") ?: 300.0, 0.0)
        c.attach(o)
        c.addListener { markNeedsLayout() }
        incoming[child] = c
        c.forward().then { incoming.remove(child) }
    }

    override fun onAttach() {
        mounted = true
    }

    fun progressOf(child: RenderObject): Double {
        val curve = curveOf(props)
        outgoing[child]?.let { return curve(it.value) }
        incoming[child]?.let { return curve(it.value) }
        return 1.0
    }

    override fun performLayout(c: Constraints) {
        var w = 0.0
        var h = 0.0
        for (ch in children) {
            ch.layout(Constraints(0.0, c.maxWidth, 0.0, c.maxHeight))
            w = max(w, ch.size.width)
            h = max(h, ch.size.height)
        }
        size = constrain(c, Size(w, h))
        for (ch in children) {
            ch.offset = Vec((size.width - ch.size.width) / 2, (size.height - ch.size.height) / 2)
            // Transition applied through the child's wrapper (a RenderSwitcherSlot).
            if (ch is RenderSwitcherSlot) {
                ch.progress = progressOf(ch)
                ch.kind = props.s("transitionType") ?: "fade"
                ch.markNeedsPaint()
            }
        }
    }

    override fun onDetach() {
        for (c in outgoing.values) c.stop()
        for (c in incoming.values) c.stop()
        mounted = false
    }

    val isMounted: Boolean get() = mounted
}

/** One child slot of an AnimatedSwitcher; paints the transition. */
class RenderSwitcherSlot : RenderProxy() {
    var progress = 1.0
    var kind = "fade"

    override fun viewKind(): String? = ViewKinds.VIEW

    override fun viewProps(): ViewProps {
        val p = progress
        val w = size.width
        val h = size.height
        return when (kind) {
            "scale" -> linkedMapOf("transform" to Matrix.scaling(p, p, 1.0), "transformOrigin" to listOf(w / 2, h / 2))
            "rotation" -> linkedMapOf("transform" to Matrix.rotationZ(p * PI * 2), "transformOrigin" to listOf(w / 2, h / 2))
            "slide" -> linkedMapOf("transform" to Matrix.translation((1 - p) * w, 0.0), "transformOrigin" to listOf(0.0, 0.0))
            else -> linkedMapOf("opacity" to (if (p >= 1) null else p))
        }
    }
}

// ============================================================================
// Explicit transitions
// ============================================================================

/**
 * One class for Fade/Slide/Scale/Rotation/Size transitions, Pulse and
 * TweenAnimationBuilder.
 *
 * props {
 *   kind: 'fade'|'slide'|'scale'|'rotation'|'size'|'pulse'|'tween',
 *   begin, end (numbers; slide uses [x, y] pairs), duration, curve,
 *   repeat, autoReverse, axis ('vertical'|'horizontal'), tweenType, alignment
 * }
 */
class RenderTransition : RenderObject() {
    private var controller: AnimationController? = null
    /** TweenAnimationBuilder: begin of the current run (animates to new ends). */
    private var tweenFrom: Double? = null

    private val kind: String? get() = props.s("kind")

    override fun onAttach() {
        val ctl = controller ?: AnimationController(props.d("duration") ?: 300.0).also { ctl ->
            controller = ctl
            ctl.addListener { if (kind == "size") markNeedsLayout() else markNeedsPaint() }
        }
        ctl.attach(owner!!)
        start()
    }

    private fun start() {
        val c = controller!!
        if (kind == "pulse") {
            c.repeatAnimation(true)
            return
        }
        if (isTruthy(props["repeat"])) {
            c.repeatAnimation(isTruthy(props["autoReverse"]))
        } else if (isTruthy(props["autoReverse"])) {
            c.forward(0.0).then { c.reverse() }
        } else {
            c.forward(0.0)
        }
    }

    override fun didUpdate(old: Props) {
        val ctl = controller ?: return
        ctl.duration = props.d("duration") ?: 300.0
        if (kind == "tween" && strictNotEqual(old["end"], props["end"])) {
            // TweenAnimationBuilder animates from the current value to the new end.
            tweenFrom = value()
            ctl.forward(0.0)
        }
    }

    /** Current animated value in the begin..end range. */
    fun value(): Double {
        val raw = controller?.value ?: 0.0
        val t = curveOf(props, if (kind == "pulse") Curves.easeInOut else Curves.linear)(raw)
        val begin = tweenFrom ?: numberOr(props["begin"], defaultBegin(kind))
        val end = numberOr(props["end"], defaultEnd(kind))
        return begin + (end - begin) * t
    }

    private fun slideValue(): Pair<Double, Double> {
        val raw = controller?.value ?: 0.0
        val t = curveOf(props)(raw)
        val b = pairOf(props["begin"]) ?: doubleArrayOf(-1.0, 0.0)
        val e = pairOf(props["end"]) ?: doubleArrayOf(0.0, 0.0)
        return Pair(b[0] + (e[0] - b[0]) * t, b[1] + (e[1] - b[1]) * t)
    }

    override fun performLayout(c: Constraints) {
        val ch = child
        if (ch == null) {
            size = constrain(c, Size(0.0, 0.0))
            return
        }
        if (kind == "size") {
            val factor = max(0.0, value())
            val horizontal = props["axis"] == "horizontal"
            ch.layout(if (horizontal) c.copy(minWidth = 0.0, maxWidth = INF) else c.copy(minHeight = 0.0, maxHeight = INF))
            val s = if (horizontal) Size(ch.size.width * factor, ch.size.height) else Size(ch.size.width, ch.size.height * factor)
            size = constrain(c, s)
            // SizeTransition aligns the child at the centre of the axis (axisAlignment 0).
            ch.offset = if (horizontal) Vec((size.width - ch.size.width) / 2, 0.0) else Vec(0.0, (size.height - ch.size.height) / 2)
            return
        }
        ch.layout(c)
        ch.offset = Vec(0.0, 0.0)
        size = ch.size.copy()
    }

    override fun viewKind(): String? = ViewKinds.VIEW

    override fun viewProps(): ViewProps {
        val w = size.width
        val h = size.height
        val center = listOf(w / 2, h / 2)
        when (kind) {
            "fade" -> {
                val o = max(0.0, min(1.0, value()))
                return linkedMapOf("opacity" to (if (o >= 1) null else o))
            }
            "slide" -> {
                val (x, y) = slideValue()
                return linkedMapOf("transform" to Matrix.translation(x * w, y * h), "transformOrigin" to listOf(0.0, 0.0))
            }
            "scale", "pulse" -> {
                val s = value()
                return linkedMapOf("transform" to Matrix.scaling(s, s, 1.0), "transformOrigin" to center)
            }
            "rotation" -> return linkedMapOf("transform" to Matrix.rotationZ(value() * PI * 2), "transformOrigin" to center)
            "size" -> return linkedMapOf("clip" to true)
            "tween" -> {
                val v = value()
                return when (props.s("tweenType") ?: "opacity") {
                    "scale" -> linkedMapOf("transform" to Matrix.scaling(v, v, 1.0), "transformOrigin" to center)
                    "rotation" -> linkedMapOf("transform" to Matrix.rotationZ(v * PI * 2), "transformOrigin" to center)
                    "translateX" -> linkedMapOf("transform" to Matrix.translation(v, 0.0), "transformOrigin" to listOf(0.0, 0.0))
                    "translateY" -> linkedMapOf("transform" to Matrix.translation(0.0, v), "transformOrigin" to listOf(0.0, 0.0))
                    else -> {
                        val o = max(0.0, min(1.0, v))
                        linkedMapOf("opacity" to (if (o >= 1) null else o))
                    }
                }
            }
            else -> return LinkedHashMap()
        }
    }

    override fun onDetach() {
        controller?.detach()
        controller?.stop()
    }
}

private fun numberOr(v: Any?, fallback: Double): Double =
    if (v is Number && v.toDouble().isFinite()) v.toDouble() else fallback

private fun defaultBegin(kind: String?): Double = if (kind == "pulse") 1.0 else 0.0
private fun defaultEnd(kind: String?): Double = if (kind == "pulse") 1.05 else 1.0

/**
 * StaggeredAnimation: a column whose children fade and rise in one after
 * another. props { duration (total), staggerDelay, curve }
 */
class RenderStaggered : RenderObject() {
    private var controller: AnimationController? = null

    override fun onAttach() {
        val ctl = controller ?: AnimationController(props.d("duration") ?: 1000.0).also { ctl ->
            controller = ctl
            ctl.addListener { for (c in children) c.markNeedsPaint() }
        }
        ctl.attach(owner!!)
        ctl.forward(0.0)
    }

    fun itemProgress(index: Int): Double {
        val count = children.size
        val total = props.d("duration") ?: 1000.0
        val delay = props.d("staggerDelay") ?: 100.0
        val totalDelay = delay * (count - 1)
        val start = max(0.0, min(1.0, (delay * index) / total))
        val end = max(0.0, min(1.0, (delay * index + (total - totalDelay)) / total))
        val curve = interval(start, end, curveOf(props, Curves.easeOut))
        return curve(controller?.value ?: 0.0)
    }

    override fun performLayout(c: Constraints) {
        var y = 0.0
        var w = 0.0
        for (ch in children) {
            ch.layout(Constraints(0.0, c.maxWidth, 0.0, INF))
            ch.offset = Vec(0.0, y)
            y += ch.size.height
            w = max(w, ch.size.width)
        }
        size = constrain(c, Size(w, y))
    }

    override fun onDetach() {
        controller?.detach()
        controller?.stop()
    }
}

/** One staggered child: fades in and slides up 20px. */
class RenderStaggerItem : RenderProxy() {
    override fun viewKind(): String? = ViewKinds.VIEW

    override fun viewProps(): ViewProps {
        val parent = this.parent
        val index = parent?.children?.indexOfFirst { it === this } ?: 0
        val v = if (parent is RenderStaggered) parent.itemProgress(index) else 1.0
        val o = max(0.0, min(1.0, v))
        return linkedMapOf(
            "opacity" to (if (o >= 1) null else o),
            "transform" to (if (v >= 1) null else Matrix.translation(0.0, 20 * (1 - v))),
            "transformOrigin" to listOf(0.0, 0.0),
        )
    }
}

/** Shimmer: a sweeping highlight gradient masked onto the child (srcATop). */
class RenderShimmer : RenderShaderMask() {
    private var controller: AnimationController? = null

    override fun onAttach() {
        val ctl = controller ?: AnimationController(props.d("duration") ?: 1500.0).also { ctl ->
            controller = ctl
            ctl.addListener { markNeedsPaint() }
        }
        ctl.attach(owner!!)
        ctl.repeatAnimation(false)
    }

    override fun viewProps(): ViewProps {
        val v = -1 + 3 * (controller?.value ?: 0.0) // Tween(-1, 2)
        val base: Color = colorProp(props["baseColor"]) ?: 0xffe0e0e0.toInt()
        val highlight: Color = colorProp(props["highlightColor"]) ?: 0xfff5f5f5.toInt()
        fun clamp(x: Double) = max(0.0, min(1.0, x))
        val gradient = Gradient(
            kind = GradientKind.linear,
            colors = listOf(base, highlight, base),
            stops = listOf(clamp(v - 0.3), clamp(v), clamp(v + 0.3)),
            begin = Alignment(-1.0, 0.0),
            end = Alignment(1.0, 0.0),
        )
        return linkedMapOf("shaderMask" to gradient)
    }

    override fun onDetach() {
        controller?.detach()
        controller?.stop()
    }
}

/** AnimatedGradient: a decorated box whose gradient stops rotate continuously. */
class RenderAnimatedGradient : RenderDecoratedBox() {
    private var controller: AnimationController? = null

    override fun onAttach() {
        val ctl = controller ?: AnimationController(props.d("duration") ?: 2000.0).also { ctl ->
            controller = ctl
            ctl.addListener { markNeedsPaint() }
        }
        ctl.attach(owner!!)
        ctl.repeatAnimation(false)
    }

    override fun viewProps(): ViewProps {
        val colors: List<Color> = (props["colors"] as? List<*>)?.map { (it as Number).toInt() }
            ?: listOf(0xff2196f3.toInt(), 0xff9c27b0.toInt(), 0xffe91e63.toInt(), 0xff2196f3.toInt())
        val shift = controller?.value ?: 0.0
        val stops = colors.indices.map { i -> ((if (colors.size > 1) i.toDouble() / (colors.size - 1) else 0.0) + shift) % 1 }.sorted()
        val d = (props["decoration"] as? Decoration ?: Decoration()).copy(
            gradients = listOf(Gradient(kind = GradientKind.linear, colors = colors, stops = stops, begin = Alignment(-1.0, -1.0), end = Alignment(1.0, 1.0))),
        )
        return decorationViewProps(d, size.width, size.height)
    }

    override fun onDetach() {
        controller?.detach()
        controller?.stop()
    }
}

// ============================================================================
// CSS @keyframes
// ============================================================================

class ParsedFrame(
    val offset: Double,
    val opacity: Double? = null,
    val transform: Matrix4? = null,
    val background: Color? = null,
)

/**
 * CSS keyframe animation on an element: animates opacity, transform and
 * background colour between the stylesheet's `@keyframes` frames.
 * props { frames: Keyframe[], duration, delay, iterations (-1 = infinite),
 *         direction, fillMode, timing, playState }
 */
class RenderKeyframes : RenderProxy() {
    private var controller: AnimationController? = null
    private var frames: List<ParsedFrame> = emptyList()
    private var iteration = 0
    private var delayTimer: Int? = null

    override fun init(props: Props) {
        super.init(props)
        frames = parseFrames(keyframesOf(props["frames"]))
    }

    override fun didUpdate(old: Props) {
        if (!deepEqual(old["frames"], props["frames"])) frames = parseFrames(keyframesOf(props["frames"]))
        val ctl = controller
        if (old["playState"] != props["playState"] && ctl != null) {
            if (props["playState"] == "paused") ctl.stop() else run()
        }
    }

    override fun onAttach() {
        val ctl = controller ?: AnimationController(props.d("duration") ?: 1000.0).also { ctl ->
            controller = ctl
            ctl.addListener { markNeedsPaint() }
            ctl.addStatusListener { s ->
                if (s == AnimationStatus.completed || s == AnimationStatus.dismissed) onIterationEnd()
            }
        }
        ctl.attach(owner!!)
        val delay = props.d("delay") ?: 0.0
        val o = owner
        if (delay > 0 && o != null) {
            delayTimer = o.platform.setTimeout(delay) {
                delayTimer = null
                run()
            }
        } else run()
    }

    private fun direction(iteration: Int): String = when (props["direction"]) {
        "reverse" -> "reverse"
        "alternate" -> if (iteration % 2 == 0) "forward" else "reverse"
        "alternate-reverse" -> if (iteration % 2 == 0) "reverse" else "forward"
        else -> "forward"
    }

    private fun run() {
        val ctl = controller ?: return
        if (props["playState"] == "paused") return
        ctl.duration = max(1.0, props.d("duration") ?: 1000.0)
        if (direction(iteration) == "forward") ctl.forward(0.0) else ctl.reverse(1.0)
    }

    private fun onIterationEnd() {
        iteration++
        val total = props.d("iterations") ?: 1.0
        if (total == -1.0 || iteration < total) run() else markNeedsPaint()
    }

    private fun finished(): Boolean {
        val total = props.d("iterations") ?: 1.0
        return total != -1.0 && iteration >= total
    }

    override fun viewKind(): String? = ViewKinds.VIEW

    override fun viewProps(): ViewProps {
        if (frames.isEmpty()) return LinkedHashMap()
        val fill = props.s("fillMode") ?: "none"
        if (finished() && fill != "forwards" && fill != "both") return LinkedHashMap()
        val t = Curves.byName(props["timing"] as? String, Curves.ease)(controller?.value ?: 0.0)
        val sampled = sampleFrames(frames, t)
        val out: ViewProps = LinkedHashMap()
        if (sampled.opacity != null) out["opacity"] = sampled.opacity
        if (sampled.transform != null) {
            out["transform"] = sampled.transform
            out["transformOrigin"] = listOf(size.width / 2, size.height / 2)
        }
        if (sampled.background != null) out["background"] = sampled.background
        return out
    }

    override fun onDetach() {
        val timer = delayTimer
        val o = owner
        if (timer != null && o != null) o.platform.clearTimeout(timer)
        controller?.detach()
        controller?.stop()
    }
}

private fun keyframesOf(v: Any?): List<Keyframe> = (v as? List<*>)?.filterIsInstance<Keyframe>() ?: emptyList()

internal fun parseFrames(frames: List<Keyframe>): List<ParsedFrame> = frames
    .map { f ->
        val s = CSSParser.parse(f.styles)
        var m: Matrix4? = s.transform
        val tr = s.translate
        if (tr != null) m = Matrix.multiply(m ?: Matrix.identity(), Matrix.translation(tr.dx, tr.dy))
        val rot = s.rotate
        if (rot != null) m = Matrix.multiply(m ?: Matrix.identity(), Matrix.rotationZ(rot * PI / 180))
        val sc = s.scale
        if (sc != null) m = Matrix.multiply(m ?: Matrix.identity(), Matrix.scaling(sc, sc, 1.0))
        ParsedFrame(offset = f.offset, opacity = s.opacity, transform = m, background = s.backgroundColor)
    }
    .sortedBy { it.offset }

internal class SampledFrame(val opacity: Double?, val transform: Matrix4?, val background: Color?)

internal fun sampleFrames(frames: List<ParsedFrame>, t: Double): SampledFrame {
    fun <V : Any> pick(get: (ParsedFrame) -> V?, lerp: (V, V, Double) -> V): V? {
        val withKey = frames.filter { get(it) != null }
        if (withKey.isEmpty()) return null
        if (t <= withKey[0].offset) return get(withKey[0])
        for (i in 0 until withKey.size - 1) {
            val a = withKey[i]
            val b = withKey[i + 1]
            if (t >= a.offset && t <= b.offset) {
                val local = if (b.offset > a.offset) (t - a.offset) / (b.offset - a.offset) else 1.0
                return lerp(get(a)!!, get(b)!!, local)
            }
        }
        return get(withKey[withKey.size - 1])
    }
    return SampledFrame(
        opacity = pick({ it.opacity }) { a, b, l -> a + (b - a) * l },
        transform = pick({ it.transform }) { a, b, l -> Matrix.lerp(a, b, l) },
        background = pick({ it.background }) { a, b, l -> lerpColor(a, b, l) },
    )
}

// ============================================================================
// Hero
// ============================================================================

/**
 * Hero: when a hero with the same tag appears at a new place on screen (a
 * re-render moved it, or a new screen replaced the old one), it flies from
 * its previous global rect to the new one (fastOutSlowIn, 300 ms).
 */
class RenderHero : RenderProxy(), HeroFlight {
    private var controller: AnimationController? = null
    /** The previous global rect: x, y, width, height. */
    private var fromRect: DoubleArray? = null

    /** Called by the owner's hero registry after layout of a frame. */
    override fun flyFrom(rect: DoubleArray, owner: RenderOwner) {
        fromRect = rect
        val ctl = controller ?: AnimationController(300.0).also { ctl ->
            controller = ctl
            ctl.addListener { markNeedsPaint() }
        }
        ctl.attach(owner)
        ctl.forward(0.0).then {
            fromRect = null
            markNeedsPaint()
        }
    }

    override fun viewKind(): String? = ViewKinds.VIEW

    override fun viewProps(): ViewProps {
        val from = fromRect
        val o = owner
        val ctl = controller
        if (from == null || o == null || ctl == null) return linkedMapOf("transform" to null)
        val here = o.compositor.globalFrame(this)
        val t = Curves.fastOutSlowIn(ctl.value)
        val sx = if (size.width > 0) from[2] / size.width else 1.0
        val sy = if (size.height > 0) from[3] / size.height else 1.0
        val scaleX = sx + (1 - sx) * t
        val scaleY = sy + (1 - sy) * t
        val dx = (from[0] - here[0]) * (1 - t)
        val dy = (from[1] - here[1]) * (1 - t)
        return linkedMapOf("transform" to Matrix.multiply(Matrix.translation(dx, dy), Matrix.scaling(scaleX, scaleY, 1.0)), "transformOrigin" to listOf(0.0, 0.0))
    }

    override fun onDetach() {
        controller?.detach()
        controller?.stop()
    }
}
