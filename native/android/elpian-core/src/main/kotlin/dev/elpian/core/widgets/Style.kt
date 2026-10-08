package dev.elpian.core.widgets

import dev.elpian.core.css.Alignment
import dev.elpian.core.css.Border
import dev.elpian.core.css.BorderSide
import dev.elpian.core.css.BorderStyleName
import dev.elpian.core.css.BoxShadow
import dev.elpian.core.css.CSSStyle
import dev.elpian.core.css.EdgeInsets
import dev.elpian.core.css.Gradient
import dev.elpian.core.css.Matrix
import dev.elpian.core.css.Matrix4
import dev.elpian.core.css.borderInsets
import dev.elpian.core.render.TextStyle
import dev.elpian.core.render.W
import dev.elpian.core.render.paint.Decoration
import dev.elpian.core.render.paint.DecorationImage
import dev.elpian.core.render.paint.Outline
import dev.elpian.core.render.textStyleFromCss
import dev.elpian.core.render.w
import kotlin.math.PI
import kotlin.math.abs

/**
 * Lowering helpers (widgets/style.ts) — the Kotlin twin of
 * `CSSProperties.applyStyle` and of Flutter's `Container` composition. They
 * wrap a widget descriptor in the same sequence of layout/paint objects the
 * Flutter engine wraps its widgets in, so the box model, stacking and
 * clipping come out identical.
 */

val SHRINK: W get() = w("constrained", mapOf("width" to 0.0, "height" to 0.0))

fun sizedBox(width: Double?, height: Double?, child: W? = null): W = w("constrained", mapOf("width" to width, "height" to height), child)

fun padding(insets: EdgeInsets, child: W?, percent: Any? = null): W = w("padding", mapOf("padding" to insets, "percent" to percent), child)

fun align(alignment: Alignment, child: W?, widthFactor: Double? = null, heightFactor: Double? = null): W =
    w("align", mapOf("alignment" to alignment, "widthFactor" to widthFactor, "heightFactor" to heightFactor), child)

fun center(child: W?): W = align(Alignment(0.0, 0.0), child)

fun column(children: List<W>, opts: Map<String, Any?> = emptyMap()): W =
    w("flex", linkedMapOf<String, Any?>("direction" to "column", "mainAxisAlignment" to "start", "crossAxisAlignment" to "center", "mainAxisSize" to "max").also { it.putAll(opts) }, children)

fun row(children: List<W>, opts: Map<String, Any?> = emptyMap()): W =
    w("flex", linkedMapOf<String, Any?>("direction" to "row", "mainAxisAlignment" to "start", "crossAxisAlignment" to "center", "mainAxisSize" to "max").also { it.putAll(opts) }, children)

fun expanded(child: W, flex: Double = 1.0): W = w("flexible", mapOf("flex" to flex, "fit" to "tight"), child)

fun flexible(child: W, flex: Double = 1.0, fit: String = "loose"): W = w("flexible", mapOf("flex" to flex, "fit" to fit), child)

fun text(value: String, style: TextStyle? = null, opts: Map<String, Any?> = emptyMap()): W =
    w("text", linkedMapOf<String, Any?>("text" to value, "style" to style).also { it.putAll(opts) })

fun decorated(decoration: Decoration, child: W?): W = w("decorated", mapOf("decoration" to decoration), child)

private fun sh(dx: Double, dy: Double, blur: Double, spread: Double, color: Long) = BoxShadow(color.toInt(), dx, dy, blur, spread)

/** `kElevationToShadow` from Flutter's material shadows. */
private val ELEVATION_SHADOWS: Map<Int, List<BoxShadow>> = linkedMapOf(
    0 to emptyList(),
    1 to listOf(sh(0.0, 2.0, 1.0, -1.0, 0x33000000), sh(0.0, 1.0, 1.0, 0.0, 0x24000000), sh(0.0, 1.0, 3.0, 0.0, 0x1f000000)),
    2 to listOf(sh(0.0, 3.0, 1.0, -2.0, 0x33000000), sh(0.0, 2.0, 2.0, 0.0, 0x24000000), sh(0.0, 1.0, 5.0, 0.0, 0x1f000000)),
    3 to listOf(sh(0.0, 3.0, 3.0, -2.0, 0x33000000), sh(0.0, 3.0, 4.0, 0.0, 0x24000000), sh(0.0, 1.0, 8.0, 0.0, 0x1f000000)),
    4 to listOf(sh(0.0, 2.0, 4.0, -1.0, 0x33000000), sh(0.0, 4.0, 5.0, 0.0, 0x24000000), sh(0.0, 1.0, 10.0, 0.0, 0x1f000000)),
    6 to listOf(sh(0.0, 3.0, 5.0, -1.0, 0x33000000), sh(0.0, 6.0, 10.0, 0.0, 0x24000000), sh(0.0, 1.0, 18.0, 0.0, 0x1f000000)),
    8 to listOf(sh(0.0, 5.0, 5.0, -3.0, 0x33000000), sh(0.0, 8.0, 10.0, 1.0, 0x24000000), sh(0.0, 3.0, 14.0, 2.0, 0x1f000000)),
    12 to listOf(sh(0.0, 7.0, 8.0, -4.0, 0x33000000), sh(0.0, 12.0, 17.0, 2.0, 0x24000000), sh(0.0, 5.0, 22.0, 4.0, 0x1f000000)),
    16 to listOf(sh(0.0, 8.0, 10.0, -5.0, 0x33000000), sh(0.0, 16.0, 24.0, 2.0, 0x24000000), sh(0.0, 6.0, 30.0, 5.0, 0x1f000000)),
    24 to listOf(sh(0.0, 11.0, 15.0, -7.0, 0x33000000), sh(0.0, 24.0, 38.0, 3.0, 0x24000000), sh(0.0, 9.0, 46.0, 8.0, 0x1f000000)),
)

fun elevationShadows(elevation: Double): List<BoxShadow> {
    if (elevation <= 0) return emptyList()
    val keys = ELEVATION_SHADOWS.keys.toList()
    var best = keys[0]
    for (k in keys) if (abs(k - elevation) < abs(best - elevation)) best = k
    return ELEVATION_SHADOWS[best]!!
}

/** A border style name as the enum (unknown names paint solid). */
internal fun borderStyleOf(name: String?): BorderStyleName = BorderStyleName.entries.firstOrNull { it.name == name } ?: BorderStyleName.solid

/** The `BoxDecoration` a Flutter `Container` would build from this style. */
fun decorationFromStyle(style: CSSStyle, ctx: BuildContext? = null): Decoration {
    val gradients = ArrayList<Gradient>()
    style.gradientLayers?.let { gradients.addAll(it.reversed()) }
    style.gradient?.let { gradients.add(it) }
    var border: Border? = style.border
    val borderStyle = style.borderStyle
    if (border == null && style.borderWidth != null && (style.borderColor != null || (!borderStyle.isNullOrEmpty() && borderStyle != "none"))) {
        border = Border.all(
            BorderSide(
                style.borderWidth!!,
                style.borderColor ?: style.color ?: 0xff000000.toInt(),
                if (!borderStyle.isNullOrEmpty() && borderStyle != "solid") borderStyleOf(borderStyle) else BorderStyleName.solid,
            ),
        )
    }
    val bgImage = style.backgroundImage
    val image = if (!bgImage.isNullOrEmpty()) {
        DecorationImage(
            src = ctx?.engine?.resolveUrl(bgImage) ?: bgImage,
            fit = style.backgroundSize,
            alignment = style.backgroundPosition,
            repeat = style.backgroundRepeat,
            size = style.backgroundSizePx,
        )
    } else null
    val outlineWidth = style.outlineWidth
    return Decoration(
        color = style.backgroundColor,
        gradients = if (gradients.isNotEmpty()) gradients else null,
        image = image,
        border = border,
        radius = style.borderRadius,
        radiusPercent = style.borderRadiusPercent,
        shape = style.shape,
        shadows = if (!style.boxShadow.isNullOrEmpty()) style.boxShadow else null,
        outline = if (outlineWidth != null && outlineWidth > 0 && style.outlineStyle != "none") {
            Outline(outlineWidth, style.outlineColor ?: style.color ?: 0xff000000.toInt(), style.outlineStyle ?: "solid", style.outlineOffset ?: 0.0)
        } else null,
    )
}

private fun needsContainer(style: CSSStyle): Boolean =
    style.padding != null ||
        style.paddingPercent != null ||
        style.backgroundColor != null ||
        style.gradient != null ||
        style.border != null ||
        style.borderRadius != null ||
        style.borderRadiusPercent != null ||
        style.boxShadow != null ||
        style.borderColor != null ||
        style.backgroundImage != null ||
        style.shape == "circle" ||
        (style.outlineWidth != null && style.outlineWidth!! > 0)

private fun clips(o: String?): Boolean = o == "hidden" || o == "clip"

/** `_flexSingleChildAlignment`: centre a lone child inside a fixed-size flex box. */
private fun flexSingleChildAlignment(style: CSSStyle): Alignment {
    val isColumn = style.flexDirection == "column" || style.flexDirection == "column-reverse"
    fun factor(v: String?): Double = when ((v ?: "").lowercase()) {
        "center" -> 0.0
        "flex-end", "end" -> 1.0
        else -> -1.0
    }
    val main = factor(style.justifyContent)
    val cross = factor(style.alignItems)
    return if (isColumn) Alignment(cross, main) else Alignment(main, cross)
}

/** The transform `applyStyle` builds (rotate / scale replace the matrix, as in Flutter). */
fun styleTransform(style: CSSStyle): Matrix4? {
    if (style.transform == null && style.rotate == null && style.scale == null && style.translate == null && style.scaleX == null && style.scaleY == null) {
        return null
    }
    var m = style.transform ?: Matrix.identity()
    style.rotate?.let { m = Matrix.rotationZ(it * PI / 180) }
    style.scale?.let { m = Matrix.scaling(it, it, 1.0) }
    if (style.scaleX != null || style.scaleY != null) m = Matrix.multiply(m, Matrix.scaling(style.scaleX ?: 1.0, style.scaleY ?: 1.0, 1.0))
    style.translate?.let { m = Matrix.multiply(Matrix.translation(it.dx, it.dy), m) }
    return m
}

data class ApplyStyleOptions(val applyFlex: Boolean = true, val layoutHandled: Boolean = false)

/** JavaScript truthiness of a number (`0` and NaN are falsy). */
private fun nz(v: Double): Boolean = v != 0.0 && !v.isNaN()

/**
 * `CSSProperties.applyStyle` — wraps [child] with the style's effects, from
 * the innermost wrapper to the outermost, in Flutter's exact order:
 *
 *   flex-single-child Align → Opacity → Transform → Visibility → Align →
 *   scroll / clip → AspectRatio → ConstrainedBox+SizedBox → Container
 *   (padding + decoration) → margin → FractionallySizedBox → transitions →
 *   IgnorePointer → Flexible
 *
 * plus the properties Flutter parses but never applies (filters, outlines,
 * `visibility: hidden`, keyframe animations, `margin: auto`).
 */
fun applyStyle(child: W, style: CSSStyle?, opts: ApplyStyleOptions = ApplyStyleOptions(), ctx: BuildContext? = null): W {
    if (style == null) return child
    val applyFlex = opts.applyFlex
    val dur = style.transitionDuration ?: 0.0
    val animated = style.transitionDuration != null && dur > 0
    val curve = style.transitionCurve
    var result = child

    if (!opts.layoutHandled && (style.display == "flex" || style.display == "inline-flex") && style.width != null && style.height != null) {
        val a = flexSingleChildAlignment(style)
        if (a.x != -1.0 || a.y != -1.0) result = align(a, result)
    }

    // Opacity (animated when the style transitions).
    val opacity = style.opacity
    if (opacity != null && (opacity < 1 || animated)) {
        result = if (animated) {
            w("animatedOpacity", mapOf("opacity" to opacity, "duration" to dur, "curve" to curve), result)
        } else {
            w("opacity", mapOf("opacity" to opacity), result)
        }
    }

    // Transform.
    val matrix = styleTransform(style)
    if (matrix != null) {
        val origin = style.transformOrigin ?: Alignment(0.0, 0.0)
        result = if (animated) {
            w("animatedTransform", mapOf("transform" to matrix, "alignment" to origin, "duration" to dur, "curve" to curve), result)
        } else {
            w("transform", mapOf("transform" to matrix, "alignment" to origin), result)
        }
    }

    // Filters (blur, brightness, drop-shadow …) and blend modes.
    if (style.filter != null || style.backdropFilter != null || !style.mixBlendMode.isNullOrEmpty()) {
        result = w("filter", mapOf("filter" to style.filter, "backdrop" to style.backdropFilter, "blendMode" to style.mixBlendMode), result)
    }

    // Visibility.
    if (style.visible == false) result = w("visibility", mapOf("mode" to "gone"), result)
    else if (style.visibility == "hidden" || style.visibility == "collapse") result = w("visibility", mapOf("mode" to "hidden"), result)

    // Alignment.
    style.alignment?.let { a ->
        result = if (animated) w("animatedAlign", mapOf("alignment" to a, "duration" to dur, "curve" to curve), result) else align(a, result)
    }

    // Overflow: scroll when the axis is bounded by this node, else clip.
    val overflowX = style.overflowX ?: style.overflow
    val overflowY = style.overflowY ?: style.overflow
    val boundedW = style.width != null || style.maxWidth != null || style.widthFactor != null
    val boundedH = style.height != null || style.maxHeight != null || style.heightFactor != null
    val scrollY = overflowY == "scroll" && boundedH
    val scrollX = overflowX == "scroll" && boundedW
    if (scrollY || scrollX) {
        result = w("scroll", mapOf("axis" to (if (scrollY && scrollX) "both" else if (scrollY) "vertical" else "horizontal")), result)
    } else if (clips(overflowX) || clips(overflowY) || overflowX == "scroll" || overflowY == "scroll") {
        result = w("clip", mapOf("radius" to style.borderRadius, "oval" to (style.shape == "circle")), result)
    }

    // Aspect ratio.
    if (style.aspectRatio != null && !(style.width != null && style.height != null)) {
        result = w("aspectRatio", mapOf("aspectRatio" to style.aspectRatio), result)
    }

    // Size constraints (percentage axes are handled by the fractional wrapper below).
    val wf = style.widthFactor
    val hf = style.heightFactor
    val fixedWidth = if (wf == null) style.width else null
    val fixedHeight = if (hf == null) style.height else null
    if (fixedWidth != null || fixedHeight != null || style.minWidth != null || style.maxWidth != null || style.minHeight != null || style.maxHeight != null) {
        val inner = if (fixedWidth != null || fixedHeight != null) {
            if (animated) {
                w("animatedConstrained", mapOf("width" to fixedWidth, "height" to fixedHeight, "duration" to dur, "curve" to curve), result)
            } else {
                w("constrained", mapOf("width" to fixedWidth, "height" to fixedHeight), result)
            }
        } else result
        result = w(
            "constrained",
            mapOf("minWidth" to (style.minWidth ?: 0.0), "maxWidth" to style.maxWidth, "minHeight" to (style.minHeight ?: 0.0), "maxHeight" to style.maxHeight),
            inner,
        )
    }

    // Container: padding (+ border insets) and decoration.
    if (needsContainer(style)) {
        val decoration = decorationFromStyle(style, ctx)
        val insets = borderInsets(decoration.border)
        val pad = style.padding ?: EdgeInsets.ZERO
        val effective = EdgeInsets(pad.top + insets.top, pad.right + insets.right, pad.bottom + insets.bottom, pad.left + insets.left)
        if (nz(effective.top) || nz(effective.right) || nz(effective.bottom) || nz(effective.left) || style.paddingPercent != null) {
            result = if (animated) {
                w("animatedPadding", mapOf("padding" to effective, "percent" to style.paddingPercent, "duration" to dur, "curve" to curve), result)
            } else {
                padding(effective, result, style.paddingPercent)
            }
        }
        val hasPaint = decoration.color != null ||
            decoration.gradients != null ||
            decoration.image != null ||
            decoration.border != null ||
            decoration.shadows != null ||
            decoration.outline != null ||
            decoration.radius != null ||
            decoration.radiusPercent != null ||
            decoration.shape == "circle"
        if (hasPaint) {
            result = if (animated) w("animatedDecorated", mapOf("decoration" to decoration, "duration" to dur, "curve" to curve), result) else decorated(decoration, result)
        }
    }

    // Keyframe animation (`animation-name` resolved against the stylesheet).
    val animationName = style.animationName
    if (!animationName.isNullOrEmpty() && ctx != null) {
        val frames = style.keyframes ?: ctx.engine.services.stylesheets.keyframes(animationName)
        if (!frames.isNullOrEmpty()) {
            result = w(
                "keyframes",
                mapOf(
                    "frames" to frames,
                    "duration" to (style.animationDuration ?: 1000.0),
                    "delay" to (style.animationDelay ?: 0.0),
                    "iterations" to (style.animationIterationCount ?: 1.0),
                    "direction" to (style.animationDirection ?: "normal"),
                    "fillMode" to (style.animationFillMode ?: "none"),
                    "timing" to (style.animationTimingFunction ?: "ease"),
                    "playState" to (style.animationPlayState ?: "running"),
                ),
                result,
            )
        }
    }

    // Margin (with `auto` margins centring the box).
    if (style.margin != null || style.marginPercent != null) {
        val m = style.margin ?: EdgeInsets.ZERO
        if (nz(m.top) || nz(m.right) || nz(m.bottom) || nz(m.left) || style.marginPercent != null) result = padding(m, result, style.marginPercent)
    }
    val auto = style.marginAuto
    if (auto != null && (auto.left || auto.right)) {
        val ax = if (auto.left && auto.right) 0.0 else if (auto.left) 1.0 else -1.0
        // Expands horizontally within a bounded parent and places the box there.
        result = w("align", mapOf("alignment" to Alignment(ax, -1.0), "heightFactor" to 1.0), result)
    }

    // Percentage width/height relative to the parent.
    if (wf != null || hf != null) {
        result = w(
            "fractional",
            mapOf(
                "widthFactor" to wf,
                "heightFactor" to hf,
                "alignment" to Alignment(-1.0, 0.0),
                "fallbackWidth" to (if (wf != null) style.width else null),
                "fallbackHeight" to (if (hf != null) style.height else null),
            ),
            result,
        )
    }

    // pointer-events: none.
    if (style.pointerEvents == "none") result = w("ignorePointer", mapOf("ignoring" to true), result)

    // Flex (outermost, so it is a direct child of the flex box).
    if (applyFlex) result = wrapFlex(result, style)
    return result
}

/** Wrap [child] in Flexible when the style declares a flex factor (CSS `flex:n` → tight). */
fun wrapFlex(child: W, style: CSSStyle?): W {
    if (style == null) return child
    val grow = style.flex ?: style.flexGrow
    val basis = parseBasis(style.flexBasis)
    if (grow != null && grow > 0) {
        return w("flexible", mapOf("flex" to grow, "fit" to "tight", "shrink" to (style.flexShrink ?: 1.0), "alignSelf" to alignSelfOf(style), "basis" to basis), child)
    }
    if (style.flexShrink != null || style.alignSelf != null || basis != null) {
        return w("flexible", mapOf("flex" to 0.0, "fit" to "loose", "shrink" to (style.flexShrink ?: 1.0), "alignSelf" to alignSelfOf(style), "basis" to basis), child)
    }
    return child
}

private fun parseBasis(basis: String?): Double? {
    if (basis.isNullOrEmpty() || basis == "auto" || basis == "content") return null
    val n = dev.elpian.core.util.parseFloatPrefix(basis)
    if (n == null || !n.isFinite() || basis.trim().endsWith("%")) return null
    return n
}

private fun alignSelfOf(style: CSSStyle): String? = when ((style.alignSelf ?: "").lowercase()) {
    "center" -> "center"
    "flex-end", "end" -> "end"
    "flex-start", "start" -> "start"
    "stretch" -> "stretch"
    "baseline" -> "baseline"
    else -> null
}

/** `CSSProperties.createTextStyle`. */
fun createTextStyle(style: CSSStyle?): TextStyle? = textStyleFromCss(style)

/** Text widget props from a style (`textAlign`, `textOverflow`, `white-space`, line clamp). */
fun textOptionsFromStyle(style: CSSStyle?): MutableMap<String, Any?> {
    val out = LinkedHashMap<String, Any?>()
    if (style == null) return out
    if (!style.textAlign.isNullOrEmpty()) out["align"] = style.textAlign
    style.textOverflow?.let { out["overflow"] = it.name }
    if (style.whiteSpace == "nowrap" || style.whiteSpace == "pre") {
        out["softWrap"] = false
        if (style.whiteSpace == "nowrap") out["maxLines"] = 1.0
    }
    val clamp = style.lineClamp
    if (clamp != null && clamp > 0) {
        out["maxLines"] = clamp
        if (out["overflow"] == null) out["overflow"] = "ellipsis"
    }
    return out
}

/** Flutter `Container(width, height, padding, margin, alignment, decoration, child)`. */
fun container(
    child: W? = null,
    width: Double? = null,
    height: Double? = null,
    padding: EdgeInsets? = null,
    margin: EdgeInsets? = null,
    alignment: Alignment? = null,
    decoration: Decoration? = null,
    minWidth: Double? = null,
    minHeight: Double? = null,
): W {
    var current: W? = child
    val tightW = width != null
    val tightH = height != null
    if (current == null && !(tightW && tightH)) {
        // Container with no child expands (LimitedBox(0,0) around an expanded box).
        current = w(
            "limited",
            mapOf("maxWidth" to 0.0, "maxHeight" to 0.0),
            w("constrained", mapOf("minWidth" to Double.POSITIVE_INFINITY, "minHeight" to Double.POSITIVE_INFINITY)),
        )
    }
    if (alignment != null) current = align(alignment, current)
    val borderPad = borderInsets(decoration?.border)
    val p = padding ?: EdgeInsets.ZERO
    val eff = EdgeInsets(p.top + borderPad.top, p.right + borderPad.right, p.bottom + borderPad.bottom, p.left + borderPad.left)
    if (nz(eff.top) || nz(eff.right) || nz(eff.bottom) || nz(eff.left)) current = padding(eff, current)
    if (decoration != null) current = decorated(decoration, current)
    if (width != null || height != null || minWidth != null || minHeight != null) {
        current = w("constrained", mapOf("width" to width, "height" to height, "minWidth" to (minWidth ?: 0.0), "minHeight" to (minHeight ?: 0.0)), current)
    }
    if (margin != null) current = padding(margin, current)
    // Without a child either the expanding box or the tight constrained box exists.
    return current!!
}
