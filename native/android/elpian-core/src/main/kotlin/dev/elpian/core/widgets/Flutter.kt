package dev.elpian.core.widgets

import dev.elpian.core.canvas.commandFromJson
import dev.elpian.core.canvas.normalizeCommand
import dev.elpian.core.css.Alignment
import dev.elpian.core.css.Border
import dev.elpian.core.css.BorderRadius
import dev.elpian.core.css.BorderSide
import dev.elpian.core.css.BorderStyleName
import dev.elpian.core.css.CSSParser
import dev.elpian.core.css.CSSStyle
import dev.elpian.core.css.Color
import dev.elpian.core.css.Colors
import dev.elpian.core.css.EdgeInsets
import dev.elpian.core.css.Gradient
import dev.elpian.core.css.GradientKind
import dev.elpian.core.css.M3
import dev.elpian.core.css.Matrix
import dev.elpian.core.css.parseColor
import dev.elpian.core.css.scaleAlpha
import dev.elpian.core.css.withOpacity
import dev.elpian.core.events.Point
import dev.elpian.core.events.makeEvent
import dev.elpian.core.model.ElpianNode
import dev.elpian.core.render.TextStyle
import dev.elpian.core.render.ViewEvent
import dev.elpian.core.render.W
import dev.elpian.core.render.paint.Decoration
import dev.elpian.core.render.paint.isTruthy
import dev.elpian.core.render.toSpec
import dev.elpian.core.render.w
import dev.elpian.core.util.jsString
import dev.elpian.core.util.toNumber
import kotlin.math.PI
import kotlin.math.max
import kotlin.math.min

/**
 * The Flutter-DSL widgets (`Container`, `Text`, `Column`, `Card`, `Slider` …,
 * widgets/flutter.ts) — one builder per file in flutter/lib/src/widgets,
 * lowered to the same widget composition. Material visuals follow Flutter's
 * Material 3 defaults.
 *
 * Where the Flutter builder is a placeholder (Dismissible's no-op callback,
 * Draggable/DragTarget without events, Scaffold ignoring its AppBar,
 * GestureDetector/InkWell swallowing taps), the native builder implements the
 * behaviour the widget is named for and reports it to the guest as events.
 */

private fun first(children: List<W>): W? = children.firstOrNull()

private fun num(v: Any?): Double? = toNumber(v)

private val DISPATCH_TYPE_NAMES = mapOf(
    "tap" to "tap", "focus" to "focus", "blur" to "blur", "keydown" to "keyDown", "keyup" to "keyUp", "dismissed" to "custom", "drop" to "drop",
)

/** Dispatch an Elpian event from a builder-level interaction. */
@Suppress("UNCHECKED_CAST")
fun dispatchEvent(ctx: BuildContext, type: String, extra: Map<String, Any?> = emptyMap()) {
    val engine = ctx.engine
    val elementId = ctx.elementId
    val events = engine.services.events
    when (type) {
        "change" -> events.dispatchChange(elementId, extra["value"])
        "input" -> events.dispatchInput(elementId, extra["value"])
        "submit" -> events.dispatchSubmit(elementId, (extra["data"] as? Map<String, Any?>) ?: emptyMap())
        "click" -> events.dispatchClick(elementId, extra["position"] as? Point)
        else -> {
            val typeName = DISPATCH_TYPE_NAMES[type] ?: "custom"
            events.dispatchEvent(makeEvent(type, typeName, elementId) { applyExtra(extra) }, elementId)
        }
    }
}

// ----------------------------------------------------------------------------
// Material helpers
// ----------------------------------------------------------------------------

/** `elevated`, `filled`, `text` or `outlined`. */
class ButtonOptions(
    val child: W,
    val style: CSSStyle?,
    val onPressed: (() -> Unit)?,
    val variant: String = "elevated",
    val semanticsLabel: String? = null,
)

/** An `ElevatedButton` (Material 3): stadium shape, 40 px tall in a 48 px tap target. */
fun materialButton(opts: ButtonOptions): W {
    val s = opts.style ?: CSSStyle()
    val enabled = opts.onPressed != null
    val variant = opts.variant
    val hasBg = s.backgroundColor != null || s.gradient != null
    var bg: Color? = s.backgroundColor ?: when (variant) {
        "elevated" -> M3.surfaceContainerLow
        "filled" -> M3.primary
        else -> null
    }
    var fg: Color = s.color ?: (if (variant == "filled" || hasBg) Colors.white else M3.primary)
    if (!enabled) {
        bg = if (bg != null) withOpacity(M3.onSurface, 0.12) else null
        fg = withOpacity(M3.onSurface, 0.38)
    }
    val shadows = s.boxShadow
    val elevation = if (!shadows.isNullOrEmpty()) shadows[0].blur / 2 else if (variant == "elevated" && enabled) 1.0 else 0.0
    val decoration = Decoration(
        color = bg,
        gradients = s.gradient?.let { listOf(it) },
        radius = s.borderRadius,
        radiusPercent = if (s.borderRadius != null) null else BorderRadius.all(50.0),
        shadows = if (!shadows.isNullOrEmpty()) shadows else elevationShadows(elevation),
        border = if (variant == "outlined") Border(side(M3.outline), side(M3.outline), side(M3.outline), side(M3.outline)) else s.border,
    )
    val pad = s.padding ?: EdgeInsets.symmetric(0.0, 24.0)
    var content: W = w("defaultTextStyle", mapOf("style" to TextStyle.LABEL_LARGE.copy(color = fg)), align(Alignment(0.0, 0.0), opts.child, widthFactor = 1.0, heightFactor = 1.0))
    content = padding(pad, content)
    content = w("constrained", mapOf("minWidth" to 64.0, "minHeight" to 40.0), content)
    content = w("decorated", mapOf("decoration" to decoration), content)
    val onPressed = opts.onPressed
    content = w(
        "gesture",
        mapOf(
            "gestures" to (if (enabled) listOf("tap") else emptyList()),
            "ripple" to (if (enabled) scaleAlpha(fg, 0.12) else null),
            "cursor" to (if (enabled) "pointer" else "default"),
            "role" to "button",
            "semanticsLabel" to opts.semanticsLabel,
            "onEvent" to { e: ViewEvent -> if (e.type == "tap") onPressed?.invoke() },
        ),
        content,
    )
    // MaterialTapTargetSize.padded: 48 px tall interactive area.
    return padding(EdgeInsets(4.0, 0.0, 4.0, 0.0), content)
}

private fun side(color: Color) = BorderSide(1.0, color, BorderStyleName.solid)

/** Wrap a material button with the style parts Flutter applies outside it. */
fun buttonOuter(result: W, style: CSSStyle?): W {
    if (style == null) return result
    var out = result
    style.margin?.let { out = padding(it, out) }
    style.opacity?.let { if (it < 1) out = w("opacity", mapOf("opacity" to it), out) }
    if (style.width != null || style.height != null) out = sizedBox(style.width, style.height, out)
    if (style.flex != null || style.flexGrow != null) out = w("flexible", mapOf("flex" to (style.flex ?: style.flexGrow), "fit" to "tight"), out)
    return out
}

fun buttonPressed(ctx: BuildContext): () -> Unit = {
    // ElevatedButton.onPressed: click, then tap.
    dispatchEvent(ctx, "click")
    dispatchEvent(ctx, "tap")
}

private fun iconGlyph(name: String, size: Double, color: Color?): W {
    val glyph = String(Character.toChars(iconCodepoint(name)))
    return sizedBox(
        size,
        size,
        center(
            text(
                glyph,
                TextStyle(fontFamily = "icons", fontSize = size, color = color ?: M3.onSurfaceVariant, height = 1.0, letterSpacing = 0.0, wordSpacing = 0.0, decoration = 0),
                mapOf("softWrap" to false),
            ),
        ),
    )
}

fun icon(name: String, size: Double = 24.0, color: Color? = null): W = iconGlyph(name, size, color)

private fun parseAlignmentProp(v: Any?, fallback: Alignment): Alignment = CSSParser.parseAlignment(v) ?: fallback

private class TextValueState(var value: String, var lastProp: String? = null)
private class DismissState(var dismissed: Boolean)

// ----------------------------------------------------------------------------
// Builders
// ----------------------------------------------------------------------------

@Suppress("UNCHECKED_CAST")
val flutterWidgets: Map<String, WidgetBuilder> = linkedMapOf(
    "Container" to { node, children, ctx ->
        var child: W? = null
        if (children.size == 1) child = children[0]
        else if (children.size > 1) child = column(children, mapOf("crossAxisAlignment" to "start", "mainAxisSize" to "min"))
        val p = node.props
        val decoration = (p["decoration"] as? Map<String, Any?>)?.let { decorationFromStyle(CSSParser.parse(it), ctx) }
        val result = container(
            child = child,
            width = num(p["width"]),
            height = num(p["height"]),
            padding = CSSParser.parseEdgeInsets(p["padding"]),
            margin = CSSParser.parseEdgeInsets(p["margin"]),
            alignment = CSSParser.parseAlignment(p["alignment"]),
            decoration = decoration,
        )
        applyStyle(result, node.style, ApplyStyleOptions(), ctx)
    },

    "Text" to { node, _, ctx ->
        val value = node.text
        val style = createTextStyle(node.style)
        val opts = textOptionsFromStyle(node.style)
        (node.props["textAlign"] as? String)?.let { opts["align"] = it }
        num(node.props["maxLines"])?.let { opts["maxLines"] = it }
        (node.props["overflow"] as? String)?.let { opts["overflow"] = it }
        (node.props["softWrap"] as? Boolean)?.let { opts["softWrap"] = it }
        if (node.props["selectable"] == true) opts["selectable"] = true
        applyStyle(text(value, style, opts), node.style, ApplyStyleOptions(), ctx)
    },

    "Button" to { node, children, ctx ->
        val label = jsString(node.props["text"] ?: "Button")
        val s = node.style
        val fg = s?.color ?: (if (s?.backgroundColor != null) Colors.white else M3.primary)
        val child = first(children) ?: text(label, TextStyle(color = fg))
        val enabled = node.props["disabled"] != true && node.props["enabled"] != false
        buttonOuter(materialButton(ButtonOptions(child, s, if (enabled) buttonPressed(ctx) else null, semanticsLabel = label)), s)
    },

    "Image" to { node, _, ctx ->
        val raw = jsString(node.props["src"] ?: "")
        val fit = node.props["fit"] as? String ?: "contain"
        val src = ctx.engine.resolveUrl(raw)
        val result = w(
            "image",
            mapOf(
                "src" to src,
                "fit" to fit,
                "width" to (node.style?.width ?: num(node.props["width"])),
                "height" to (node.style?.height ?: num(node.props["height"])),
                "alt" to node.props["alt"],
                "onEvent" to { e: ViewEvent -> if (e.type == "load" || e.type == "error") dispatchEvent(ctx, e.type, mapOf("value" to e.value)) },
            ),
        )
        applyStyle(result, node.style, ApplyStyleOptions(), ctx)
    },

    "Column" to { node, children, ctx -> applyStyle(flexOrWrap("column", node.style, children), node.style, ApplyStyleOptions(), ctx) },

    "Row" to { node, children, ctx -> applyStyle(flexOrWrap("row", node.style, children), node.style, ApplyStyleOptions(), ctx) },

    "Stack" to { node, children, ctx ->
        val alignment = node.style?.alignment ?: Alignment(0.0, 0.0)
        applyStyle(w("stack", mapOf("alignment" to alignment, "fit" to "loose"), children), node.style, ApplyStyleOptions(), ctx)
    },

    "Positioned" to { node, children, _ ->
        val s = node.style ?: CSSStyle()
        w(
            "positioned",
            mapOf("top" to s.top, "right" to s.right, "bottom" to s.bottom, "left" to s.left, "width" to s.width, "height" to s.height),
            first(children) ?: container(),
        )
    },

    "Expanded" to { node, children, _ ->
        w("flexible", mapOf("flex" to (num(node.props["flex"]) ?: 1.0), "fit" to "tight"), first(children) ?: container())
    },

    "Flexible" to { node, children, _ ->
        w("flexible", mapOf("flex" to (num(node.props["flex"]) ?: 1.0), "fit" to (if (node.props["fit"] == "tight") "tight" else "loose")), first(children) ?: container())
    },

    "Center" to { node, children, ctx -> applyStyle(center(first(children) ?: container()), node.style, ApplyStyleOptions(), ctx) },

    "Padding" to { node, children, _ ->
        padding(node.style?.padding ?: EdgeInsets.all(8.0), first(children) ?: container(), node.style?.paddingPercent)
    },

    "Align" to { node, children, _ -> align(node.style?.alignment ?: Alignment(0.0, 0.0), first(children) ?: container()) },

    "SizedBox" to { node, children, _ ->
        sizedBox(node.style?.width ?: num(node.props["width"]), node.style?.height ?: num(node.props["height"]), first(children))
    },

    "ListView" to { node, children, ctx ->
        val scrollable = node.props["scrollable"] != false
        val horizontal = node.props["scrollDirection"] == "horizontal"
        val list = w("flex", mapOf("direction" to (if (horizontal) "row" else "column"), "crossAxisAlignment" to (if (horizontal) "start" else "stretch"), "mainAxisSize" to "min"), children)
        val result = w("scroll", mapOf("axis" to (if (horizontal) "horizontal" else "vertical"), "enabled" to scrollable), list)
        applyStyle(result, node.style, ApplyStyleOptions(), ctx)
    },

    "GridView" to { node, children, ctx ->
        val count = max(1.0, num(node.props["crossAxisCount"]) ?: 2.0)
        val spacing = num(node.props["crossAxisSpacing"]) ?: 0.0
        val mainSpacing = num(node.props["mainAxisSpacing"]) ?: 0.0
        val ratio = num(node.props["childAspectRatio"]) ?: 1.0
        val grid = w(
            "grid",
            mapOf("columns" to "repeat(${jsString(count)}, 1fr)", "columnGap" to spacing, "rowGap" to mainSpacing, "alignItems" to "stretch"),
            children.map { w("aspectRatio", mapOf("aspectRatio" to ratio), it) },
        )
        applyStyle(w("scroll", mapOf("axis" to "vertical", "enabled" to (node.props["scrollable"] != false)), grid), node.style, ApplyStyleOptions(), ctx)
    },

    "TextField" to { node, _, ctx ->
        val incoming = node.props["value"]?.let { jsString(it) }
        val state = ctx.engine.stateFor(ctx.elementId) { TextValueState(incoming ?: "", incoming) }
        // didUpdateWidget: a changed `value` prop (e.g. a bound model update) wins.
        if (incoming != state.lastProp) {
            if (incoming != null) state.value = incoming
            state.lastProp = incoming
        }
        val s = node.style
        val textStyle = TextStyle.BODY_LARGE.merge(createTextStyle(s))
        val lines = max(1.0, num(node.props["maxLines"]) ?: 1.0)
        val result = w(
            "control",
            mapOf(
                "kind" to "textInput",
                "lines" to (if (isTruthy(node.props["multiline"])) max(lines, 3.0) else lines),
                "padding" to listOf(12.0, 0.0, 12.0, 0.0),
                "view" to linkedMapOf(
                    "value" to state.value,
                    "placeholder" to jsString(node.props["hint"] ?: node.props["placeholder"] ?: ""),
                    "inputType" to (if (isTruthy(node.props["obscureText"])) "password" else node.props["keyboardType"] ?: "text"),
                    "multiline" to (lines > 1 || isTruthy(node.props["multiline"])),
                    "maxLines" to lines,
                    "maxLength" to num(node.props["maxLength"]),
                    "enabled" to (node.props["enabled"] != false),
                    "readOnly" to (node.props["readOnly"] == true),
                    "autofocus" to (node.props["autofocus"] == true),
                    "min" to node.props["min"],
                    "max" to node.props["max"],
                    "variant" to "underline",
                    "textStyle" to textStyle.toSpec(),
                    "hintStyle" to textStyle.copy(color = M3.onSurfaceVariant).toSpec(),
                    "contentPadding" to listOf(12.0, 0.0, 12.0, 0.0),
                    "colors" to linkedMapOf(
                        "text" to (textStyle.color ?: M3.onSurface),
                        "hint" to M3.onSurfaceVariant,
                        "border" to M3.onSurfaceVariant,
                        "focusedBorder" to M3.primary,
                        "cursor" to M3.primary,
                        "fill" to null,
                    ),
                ),
                "onEvent" to { e: ViewEvent ->
                    if (e.type == "input" || e.type == "change") {
                        state.value = if (e.value == null) "" else jsString(e.value)
                        dispatchEvent(ctx, "input", mapOf("value" to state.value))
                    } else if (e.type == "submit") dispatchEvent(ctx, "submit")
                    else if (e.type == "focus" || e.type == "blur") dispatchEvent(ctx, e.type)
                },
            ),
        )
        applyStyle(result, s, ApplyStyleOptions(), ctx)
    },

    "Checkbox" to { node, _, ctx ->
        val value = node.props["value"] == true
        w(
            "control",
            mapOf(
                "kind" to "checkbox",
                "view" to linkedMapOf(
                    "checked" to value,
                    "enabled" to (node.props["enabled"] != false),
                    "colors" to linkedMapOf("fill" to (node.style?.color ?: M3.primary), "check" to M3.onPrimary, "border" to M3.onSurfaceVariant),
                ),
                "controlled" to true,
                "onEvent" to { e: ViewEvent -> if (e.type == "change") dispatchEvent(ctx, "change", mapOf("value" to isTruthy(e.value))) },
            ),
        )
    },

    "Radio" to { node, _, ctx ->
        val value = node.props["value"]
        val group = node.props["groupValue"]
        w(
            "control",
            mapOf(
                "kind" to "radio",
                "view" to linkedMapOf(
                    "checked" to (value == group && node.props.containsKey("value")),
                    "value" to value,
                    "colors" to linkedMapOf("fill" to (node.style?.color ?: M3.primary), "border" to M3.onSurfaceVariant),
                ),
                "controlled" to true,
                "onEvent" to { e: ViewEvent -> if (e.type == "change") dispatchEvent(ctx, "change", mapOf("value" to value)) },
            ),
        )
    },

    "Switch" to { node, _, ctx ->
        val value = node.props["value"] == true
        w(
            "control",
            mapOf(
                "kind" to "switch",
                "view" to linkedMapOf(
                    "checked" to value,
                    "enabled" to (node.props["enabled"] != false),
                    "colors" to linkedMapOf(
                        "trackOn" to (node.style?.color ?: M3.primary),
                        "thumbOn" to M3.onPrimary,
                        "trackOff" to M3.surfaceContainerHighest,
                        "thumbOff" to M3.outline,
                        "outline" to M3.outline,
                    ),
                ),
                "controlled" to true,
                "onEvent" to { e: ViewEvent -> if (e.type == "change") dispatchEvent(ctx, "change", mapOf("value" to isTruthy(e.value))) },
            ),
        )
    },

    "Slider" to { node, _, ctx ->
        val minV = num(node.props["min"]) ?: 0.0
        val maxV = num(node.props["max"]) ?: 1.0
        val value = max(minV, min(maxV, num(node.props["value"]) ?: 0.5))
        val divisions = num(node.props["divisions"])
        w(
            "control",
            mapOf(
                "kind" to "slider",
                "view" to linkedMapOf(
                    "value" to value,
                    "min" to minV,
                    "max" to maxV,
                    "step" to (if (divisions != null && divisions > 0) (maxV - minV) / divisions else null),
                    "enabled" to (node.props["enabled"] != false),
                    "colors" to linkedMapOf("active" to (node.style?.color ?: M3.primary), "inactive" to M3.secondaryContainer, "thumb" to (node.style?.color ?: M3.primary)),
                ),
                "controlled" to true,
                "onEvent" to { e: ViewEvent -> if (e.type == "change" || e.type == "input") dispatchEvent(ctx, "change", mapOf("value" to jsNumber(e.value))) },
            ),
        )
    },

    "Icon" to { node, _, ctx ->
        val name = jsString(node.props["icon"] ?: "star")
        val size = node.style?.fontSize ?: num(node.props["size"]) ?: 24.0
        applyStyle(icon(name, size, node.style?.color), node.style, ApplyStyleOptions(), ctx)
    },

    "Card" to { node, children, ctx ->
        val s = node.style ?: CSSStyle()
        var child: W = if (children.isEmpty()) SHRINK else if (children.size == 1) children[0] else column(children)
        val shadows = s.boxShadow
        val elevation = if (!shadows.isNullOrEmpty()) shadows[0].blur / 2 else num(node.props["elevation"]) ?: 1.0
        s.padding?.let { child = padding(it, child) }
        val border = s.borderColor?.let { BorderSide(s.borderWidth ?: 1.0, it, BorderStyleName.solid) }
        val radius = s.borderRadius ?: BorderRadius.all(12.0)
        var result: W = w("clip", mapOf("radius" to radius), child)
        result = decorated(
            Decoration(
                color = s.backgroundColor ?: M3.surfaceContainerLow,
                radius = radius,
                shadows = elevationShadows(elevation),
                border = border?.let { Border(it, it, it, it) },
            ),
            result,
        )
        result = padding(EdgeInsets.all(4.0), result)
        val external = CSSStyle().also {
            it.width = s.width
            it.height = s.height
            it.minWidth = s.minWidth
            it.maxWidth = s.maxWidth
            it.minHeight = s.minHeight
            it.maxHeight = s.maxHeight
            it.margin = s.margin
            it.opacity = s.opacity
            it.flex = s.flex
            it.transform = s.transform
            it.rotate = s.rotate
            it.scale = s.scale
            it.alignment = s.alignment
            it.visible = s.visible
        }
        applyStyle(result, external, ApplyStyleOptions(), ctx)
    },

    "Scaffold" to { node, children, _ ->
        var appBar: W? = null
        var fab: W? = null
        var bottom: W? = null
        val body = ArrayList<W>()
        node.children.forEachIndexed { i, child ->
            val slot = child.props["slot"]
            if (child.type == "AppBar" || slot == "appBar") appBar = children[i]
            else if (slot == "floatingActionButton" || child.type == "FloatingActionButton") fab = children[i]
            else if (slot == "bottomNavigationBar" || slot == "bottomBar") bottom = children[i]
            else body.add(children[i])
        }
        val bodyW = if (body.isNotEmpty()) body[body.size - 1] else SHRINK
        val columnChildren = ArrayList<W>()
        appBar?.let { columnChildren.add(it) }
        columnChildren.add(expanded(w("align", mapOf("alignment" to Alignment(-1.0, -1.0)), bodyW)))
        bottom?.let { columnChildren.add(it) }
        var result: W = w("flex", mapOf("direction" to "column", "crossAxisAlignment" to "stretch", "mainAxisSize" to "max"), columnChildren)
        fab?.let { f ->
            result = w(
                "stack",
                mapOf("alignment" to Alignment(-1.0, -1.0), "fit" to "expand"),
                listOf(result, w("positioned", mapOf("right" to 16.0, "bottom" to 16.0 + (if (bottom != null) 80.0 else 0.0)), f)),
            )
        }
        decorated(Decoration(color = node.style?.backgroundColor ?: M3.surface), w("defaultTextStyle", mapOf("style" to TextStyle()), result))
    },

    "AppBar" to { node, children, _ ->
        val title = jsString(node.props["title"] ?: "")
        val s = node.style ?: CSSStyle()
        val fg = s.color ?: M3.onSurface
        val row1 = ArrayList<W>()
        val leading = node.children.indexOfFirst { it.props["slot"] == "leading" }
        if (leading >= 0) row1.add(padding(EdgeInsets(0.0, 0.0, 0.0, 4.0), sizedBox(48.0, 48.0, center(children[leading]))))
        row1.add(
            expanded(
                padding(
                    EdgeInsets(0.0, 16.0, 0.0, 16.0),
                    text(title, TextStyle.TITLE_LARGE.copy(color = fg), mapOf("maxLines" to 1.0, "overflow" to "ellipsis", "softWrap" to false)),
                ),
            ),
        )
        node.children.forEachIndexed { i, c -> if (i != leading && c.props["slot"] != "title") row1.add(children[i]) }
        var bar: W = sizedBox(null, s.height ?: 64.0, w("flex", mapOf("direction" to "row", "crossAxisAlignment" to "center", "mainAxisSize" to "max"), row1))
        // A primary AppBar extends under the status bar (MediaQuery padding top).
        if (node.props["primary"] != false) bar = w("safeArea", mapOf("top" to true), bar)
        val elevation = num(node.props["elevation"])
        decorated(
            Decoration(color = s.backgroundColor ?: M3.surface, shadows = if (elevation != null && elevation != 0.0) elevationShadows(elevation) else null),
            w("defaultTextStyle", mapOf("style" to TextStyle(color = fg)), bar),
        )
    },

    "Wrap" to { node, children, ctx ->
        val s = node.style
        val result = w("wrap", mapOf("direction" to "horizontal", "spacing" to (s?.gap ?: 8.0), "runSpacing" to (s?.rowGap ?: 8.0), "alignment" to "start"), children)
        applyStyle(result, s, ApplyStyleOptions(), ctx)
    },

    "InkWell" to { node, children, ctx ->
        val child = first(children) ?: container()
        val result = w(
            "gesture",
            mapOf("gestures" to listOf("tap"), "ripple" to scaleAlpha(node.style?.color ?: M3.onSurface, 0.12), "cursor" to "pointer", "onEvent" to { _: ViewEvent -> }),
            child,
        )
        applyStyle(result, node.style, ApplyStyleOptions(), ctx)
    },

    "GestureDetector" to { _, children, _ ->
        // Events on the node are recognised by the engine's gesture region.
        w("proxy", emptyMap(), first(children) ?: container())
    },

    "Opacity" to { node, children, _ ->
        val opacity = node.style?.opacity ?: num(node.props["opacity"]) ?: 1.0
        w("opacity", mapOf("opacity" to opacity), first(children) ?: container())
    },

    "Transform" to { node, children, _ ->
        var m = node.style?.transform ?: Matrix.identity()
        node.style?.rotate?.let { m = Matrix.rotationZ(it * PI / 180) }
        node.style?.scale?.let { m = Matrix.scaling(it, it, 1.0) }
        w("transform", mapOf("transform" to m, "alignment" to Alignment(0.0, 0.0)), first(children) ?: container())
    },

    "ClipRRect" to { node, children, _ ->
        w("clip", mapOf("radius" to (node.style?.borderRadius ?: BorderRadius.all(8.0))), first(children) ?: container())
    },

    "ConstrainedBox" to { node, children, _ ->
        val s = node.style ?: CSSStyle()
        w(
            "constrained",
            mapOf("minWidth" to (s.minWidth ?: 0.0), "maxWidth" to s.maxWidth, "minHeight" to (s.minHeight ?: 0.0), "maxHeight" to s.maxHeight),
            first(children) ?: container(),
        )
    },

    "AspectRatio" to { node, children, _ ->
        w("aspectRatio", mapOf("aspectRatio" to (num(node.props["aspectRatio"]) ?: node.style?.aspectRatio ?: 1.0)), first(children) ?: container())
    },

    "FractionallySizedBox" to { node, children, _ ->
        w(
            "fractional",
            mapOf(
                "widthFactor" to num(node.props["widthFactor"]),
                "heightFactor" to num(node.props["heightFactor"]),
                "alignment" to (node.style?.alignment ?: Alignment(0.0, 0.0)),
            ),
            first(children),
        )
    },

    "FittedBox" to { node, children, _ ->
        val fit = node.props["fit"] as? String ?: "contain"
        w("fitted", mapOf("fit" to fit, "alignment" to (node.style?.alignment ?: Alignment(0.0, 0.0))), w("fittedContent", emptyMap(), first(children) ?: container()))
    },

    "LimitedBox" to { node, children, _ ->
        w("limited", mapOf("maxWidth" to node.style?.maxWidth, "maxHeight" to node.style?.maxHeight), first(children) ?: container())
    },

    "OverflowBox" to { node, children, _ ->
        val s = node.style ?: CSSStyle()
        w(
            "overflowBox",
            mapOf(
                "alignment" to (s.alignment ?: Alignment(0.0, 0.0)),
                "minWidth" to s.minWidth,
                "maxWidth" to s.maxWidth,
                "minHeight" to s.minHeight,
                "maxHeight" to s.maxHeight,
            ),
            first(children) ?: container(),
        )
    },

    "Baseline" to { node, children, _ -> w("baseline", mapOf("baseline" to (num(node.props["baseline"]) ?: 0.0)), first(children) ?: container()) },

    "Spacer" to { node, _, _ -> w("flexible", mapOf("flex" to (num(node.props["flex"]) ?: 1.0), "fit" to "tight"), SHRINK) },

    "Divider" to { node, _, _ ->
        val s = node.style ?: CSSStyle()
        val thickness = s.borderWidth ?: 1.0
        val height = s.height ?: 16.0
        val indent = num(node.props["indent"]) ?: 0.0
        val endIndent = num(node.props["endIndent"]) ?: 0.0
        sizedBox(
            null,
            height,
            center(padding(EdgeInsets(0.0, endIndent, 0.0, indent), container(height = thickness, decoration = Decoration(color = s.borderColor ?: s.color ?: M3.outlineVariant)))),
        )
    },

    "VerticalDivider" to { node, _, _ ->
        val s = node.style ?: CSSStyle()
        val thickness = s.borderWidth ?: 1.0
        val width = s.width ?: 16.0
        sizedBox(width, null, center(container(width = thickness, decoration = Decoration(color = s.borderColor ?: s.color ?: M3.outlineVariant))))
    },

    "CircularProgressIndicator" to { node, _, _ ->
        val value = num(node.props["value"])
        w(
            "control",
            mapOf(
                "kind" to "progress",
                "view" to linkedMapOf(
                    "variant" to "circular",
                    "value" to value,
                    "strokeWidth" to (node.style?.borderWidth ?: 4.0),
                    "colors" to linkedMapOf("indicator" to (node.style?.color ?: M3.primary), "track" to node.style?.backgroundColor),
                ),
            ),
        )
    },

    "LinearProgressIndicator" to { node, _, _ ->
        val value = num(node.props["value"])
        w(
            "control",
            mapOf(
                "kind" to "progress",
                "view" to linkedMapOf(
                    "variant" to "linear",
                    "value" to value,
                    "strokeWidth" to (num(node.props["minHeight"]) ?: 4.0),
                    "colors" to linkedMapOf("indicator" to (node.style?.color ?: M3.primary), "track" to (node.style?.backgroundColor ?: M3.secondaryContainer)),
                ),
            ),
        )
    },

    "Tooltip" to { node, children, _ ->
        w(
            "gesture",
            mapOf("gestures" to listOf("longpress", "hover"), "tooltip" to jsString(node.props["message"] ?: ""), "onEvent" to { _: ViewEvent -> }),
            first(children) ?: container(),
        )
    },

    "Badge" to { node, children, _ ->
        val label = node.props["label"]?.let { jsString(it) } ?: ""
        val child = first(children) ?: container()
        val s = node.style ?: CSSStyle()
        val pill: W = if (label == "") {
            container(width = 6.0, height = 6.0, decoration = Decoration(color = s.backgroundColor ?: M3.error, shape = "circle"))
        } else {
            container(
                minWidth = 16.0,
                height = 16.0,
                padding = EdgeInsets.symmetric(0.0, 4.0),
                alignment = Alignment(0.0, 0.0),
                decoration = Decoration(color = s.backgroundColor ?: M3.error, radius = BorderRadius.all(8.0)),
                child = text(label, TextStyle(fontSize = 11.0, fontWeight = 500, letterSpacing = 0.5, height = 16.0 / 11, color = s.color ?: Colors.white), mapOf("softWrap" to false)),
            )
        }
        val off = if (label == "") 0.0 else -4.0
        w("stack", mapOf("alignment" to Alignment(-1.0, -1.0), "fit" to "loose"), listOf(child, w("positioned", mapOf("top" to off, "right" to off), pill)))
    },

    "Chip" to { node, children, _ ->
        val label = jsString(node.props["label"] ?: "")
        val s = node.style ?: CSSStyle()
        val content = ArrayList<W>()
        val avatar = node.children.indexOfFirst { it.props["slot"] == "avatar" }
        if (avatar >= 0) content.add(padding(EdgeInsets(0.0, 8.0, 0.0, 0.0), sizedBox(18.0, 18.0, children[avatar])))
        content.add(text(label, TextStyle.LABEL_LARGE.copy(color = s.color ?: M3.onSurfaceVariant), mapOf("softWrap" to false)))
        padding(
            EdgeInsets.symmetric(8.0, 0.0),
            container(
                minHeight = 32.0,
                padding = EdgeInsets.symmetric(6.0, 16.0),
                alignment = null,
                decoration = Decoration(
                    color = s.backgroundColor,
                    radius = s.borderRadius ?: BorderRadius.all(8.0),
                    border = Border(side(M3.outlineVariant), side(M3.outlineVariant), side(M3.outlineVariant), side(M3.outlineVariant)),
                ),
                child = w("flex", mapOf("direction" to "row", "crossAxisAlignment" to "center", "mainAxisSize" to "min"), content),
            ),
        )
    },

    "Dismissible" to { node, children, ctx ->
        val state = ctx.engine.stateFor(ctx.elementId) { DismissState(false) }
        val child = first(children) ?: container()
        if (state.dismissed) {
            SHRINK
        } else {
            w(
                "gesture",
                mapOf(
                    "gestures" to listOf("dismiss"),
                    "dismissDirection" to jsString(node.props["direction"] ?: "horizontal"),
                    "onEvent" to { e: ViewEvent ->
                        if (e.type == "dismissed") {
                            state.dismissed = true
                            dispatchEvent(ctx, "dismissed", mapOf("data" to mapOf("direction" to e.direction)))
                            if (node.events?.get("dismiss") != null) dispatchEvent(ctx, "dismiss", mapOf("data" to mapOf("direction" to e.direction)))
                            ctx.engine.host.invalidate?.invoke()
                        }
                    },
                ),
                child,
            )
        }
    },

    "Draggable" to { node, children, ctx ->
        val child = first(children) ?: container()
        val data = node.props["data"]
        w(
            "gesture",
            mapOf(
                "gestures" to listOf("draggable"),
                "dragData" to data,
                "onEvent" to { e: ViewEvent ->
                    when (e.type) {
                        "dragstart" -> dispatchEvent(ctx, "dragstart", mapOf("data" to mapOf("data" to data)))
                        "dragupdate" -> ctx.engine.dragOver(ctx.elementId, e, data)
                        "dragend", "drop" -> ctx.engine.dropAt(ctx.elementId, e, data)
                    }
                },
            ),
            child,
        )
    },

    "DragTarget" to { _, children, ctx ->
        val child = first(children) ?: container()
        w("gesture", mapOf("gestures" to emptyList<String>(), "dragTargetId" to ctx.elementId, "onEvent" to { _: ViewEvent -> }), child, "dt:${ctx.elementId}")
    },

    "Hero" to { node, children, _ -> w("hero", mapOf("tag" to (node.props["tag"] ?: "hero")), first(children) ?: container()) },

    "IndexedStack" to { node, children, _ ->
        w("indexedStack", mapOf("index" to (num(node.props["index"]) ?: 0.0), "alignment" to parseAlignmentProp(node.props["alignment"], Alignment(-1.0, -1.0))), children)
    },

    "RotatedBox" to { node, children, _ ->
        w("rotatedBox", mapOf("quarterTurns" to (num(node.props["quarterTurns"]) ?: 0.0)), first(children) ?: container())
    },

    "DecoratedBox" to { node, children, ctx ->
        val s = node.style ?: CSSStyle()
        val d = decorationFromStyle(s, ctx)
        decorated(d, first(children) ?: container())
    },

    "Scope" to { _, children, _ ->
        if (children.isEmpty()) SHRINK else if (children.size == 1) children[0] else column(children)
    },

    "Canvas" to { node, _, ctx ->
        val raw = node.props["commands"] as? List<Any?> ?: emptyList()
        val commands = raw.filter { it is Map<*, *> }.map { normalizeCommand(commandFromJson(it)) }
        val bg = parseColor(node.props["backgroundColor"]) ?: node.style?.backgroundColor
        w(
            "canvas",
            mapOf(
                "width" to (num(node.props["width"]) ?: node.style?.width),
                "height" to (num(node.props["height"]) ?: node.style?.height),
                "background" to bg,
                "commands" to commands,
                "onEvent" to { e: ViewEvent -> ctx.engine.handleGesture(ctx.elementId, node, e) },
            ),
        )
    },

    "CachedCanvas" to { node, _, ctx -> cachedCanvas(node, ctx) },

    "Scene3D" to { node, children, ctx -> scene3d(node, children, ctx) },
    "scene3d" to { node, children, ctx -> scene3d(node, children, ctx) },

    "MathExpression" to { node, _, ctx -> mathExpression(node, ctx) },
    "Math" to { node, _, ctx -> mathExpression(node, ctx) },
)

/** `CachedCanvas`: a canvas drawing a guest-managed (`canvas.ctx.*`) command context. */
internal fun cachedCanvas(node: ElpianNode, ctx: BuildContext): W {
    val id = jsString(node.props["contextId"] ?: node.props["id"] ?: "")
    if (id == "") return SHRINK
    val store = ctx.engine.services.canvasContexts
    val c = store[ctx.engine.services.scopeId(id)] ?: store[id]
    val width = num(node.props["width"]) ?: node.style?.width
    val height = num(node.props["height"]) ?: node.style?.height
    if (c == null) return SHRINK
    if (width != null && height != null) c.setSize(width, height)
    val bg = parseColor(node.props["backgroundColor"]) ?: node.style?.backgroundColor
    return w(
        "canvas",
        mapOf(
            "width" to (width ?: c.width),
            "height" to (height ?: c.height),
            "background" to bg,
            "context" to c,
            // The TypeScript props carry a `{id, version, generation, commands}` snapshot so a
            // changed context reconfigures the render object; the live context is passed here,
            // with its version and generation alongside for the same change detection.
            "contextVersion" to c.version.toDouble(),
            "contextGeneration" to c.generation.toDouble(),
        ),
    )
}

private fun flexOrWrap(direction: String, style: CSSStyle?, children: List<W>): W {
    val gap = style?.gap ?: 0.0
    val wraps = style?.flexWrap == "wrap" || style?.flexWrap == "wrap-reverse"
    val main = style?.justifyContent
    val cross = style?.alignItems
    fun mainMap(v: String?) = when ((v ?: "").lowercase()) {
        "center" -> "center"
        "flex-end", "end" -> "end"
        "space-between" -> "spaceBetween"
        "space-around" -> "spaceAround"
        "space-evenly" -> "spaceEvenly"
        else -> "start"
    }
    fun crossMap(v: String?) = when ((v ?: "").lowercase()) {
        "center" -> "center"
        "flex-end", "end" -> "end"
        "stretch" -> "stretch"
        "baseline" -> "baseline"
        else -> "start"
    }
    if (wraps) {
        return w(
            "wrap",
            mapOf(
                "direction" to (if (direction == "row") "horizontal" else "vertical"),
                "spacing" to gap,
                "runSpacing" to gap,
                "alignment" to mainMap(main),
                "crossAxisAlignment" to (if (crossMap(cross) == "stretch" || crossMap(cross) == "baseline") "start" else crossMap(cross)),
                "verticalDirection" to (if (style?.flexWrap == "wrap-reverse") "up" else "down"),
            ),
            children,
        )
    }
    return w("flex", mapOf("direction" to direction, "mainAxisAlignment" to mainMap(main), "crossAxisAlignment" to crossMap(cross), "mainAxisSize" to "max", "gap" to gap), children)
}

@Suppress("UNCHECKED_CAST")
private fun scene3d(node: ElpianNode, children: List<W>, ctx: BuildContext): W {
    val p = node.props
    val raw = p["initialScene"] ?: p["scene"] ?: p["world"]
    val json: Map<String, Any?>? = when (raw) {
        is Map<*, *> -> raw as Map<String, Any?>
        is List<*> -> linkedMapOf("nodes" to raw)
        else -> null
    }
    val controller = ctx.engine.sceneFor(ctx.elementId, json)
    val placeholder = first(children) ?: scenePlaceholder()
    val clickable = p["clickable"] == true
    return w(
        "scene3d",
        mapOf(
            "surfaceId" to controller.godot.surfaceId,
            "live" to controller.isLive,
            "width" to (num(p["width"]) ?: node.style?.width),
            "height" to (num(p["height"]) ?: node.style?.height),
            "clickable" to clickable,
            "onEvent" to { e: ViewEvent -> if (e.type == "tap" && clickable) ctx.engine.host.sceneTap?.invoke(LinkedHashMap(p)) },
        ),
        placeholder,
    )
}

/** `_Scene3DPlaceholder`: a quiet gradient panel with an AR icon and a caption. */
private fun scenePlaceholder(): W = decorated(
    Decoration(gradients = listOf(Gradient(GradientKind.linear, listOf(0xff10141d.toInt(), 0xff1a2233.toInt()), begin = Alignment(-1.0, -1.0), end = Alignment(1.0, 1.0)))),
    center(
        column(
            listOf(icon("view_in_ar", 36.0, Colors.white24), sizedBox(null, 8.0), text("3D unavailable on this platform", TextStyle(color = Colors.white38, fontSize = 12.0))),
            mapOf("mainAxisSize" to "min", "crossAxisAlignment" to "center"),
        ),
    ),
)

// ----------------------------------------------------------------------------
// MathExpression
// ----------------------------------------------------------------------------

private val MATH_SYMBOLS: List<Pair<Regex, String>> = listOf(
    "alpha" to "α", "beta" to "β", "gamma" to "γ", "delta" to "δ", "theta" to "θ", "lambda" to "λ", "mu" to "μ",
    "pi" to "π", "sigma" to "σ", "phi" to "φ", "omega" to "ω", "sum" to "∑", "prod" to "∏", "int" to "∫",
    "infty" to "∞", "sqrt" to "√", "neq" to "≠", "leq" to "≤", "geq" to "≥", "approx" to "≈", "times" to "×",
    "cdot" to "·", "pm" to "±", "to" to "→", "leftarrow" to "←", "Rightarrow" to "⇒", "forall" to "∀",
    "exists" to "∃", "in" to "∈", "notin" to "∉", "subset" to "⊂", "subseteq" to "⊆", "cup" to "∪", "cap" to "∩",
).map { (name, sym) -> Regex("\\\\" + name) to sym }

private val SUPER = mapOf(
    "0" to "⁰", "1" to "¹", "2" to "²", "3" to "³", "4" to "⁴", "5" to "⁵", "6" to "⁶", "7" to "⁷", "8" to "⁸", "9" to "⁹",
    "+" to "⁺", "-" to "⁻", "=" to "⁼", "(" to "⁽", ")" to "⁾", "n" to "ⁿ", "i" to "ⁱ",
)
private val SUB = mapOf(
    "0" to "₀", "1" to "₁", "2" to "₂", "3" to "₃", "4" to "₄", "5" to "₅", "6" to "₆", "7" to "₇", "8" to "₈", "9" to "₉",
    "+" to "₊", "-" to "₋", "=" to "₌", "(" to "₍", ")" to "₎",
)
private val BLOCKED = listOf("write", "input", "include", "openout", "read", "catcode", "usepackage", "newcommand", "renewcommand", "def", "csname", "every", "special")
private val CONTROL_CHARS = Regex("[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F\\x7F]")

data class SanitizedMath(val value: String, val sanitized: Boolean)

fun sanitizeMath(input: String): SanitizedMath {
    var expression = input.replace(CONTROL_CHARS, " ").trim()
    if (expression.length > 4096) expression = expression.substring(0, 4096)
    var sanitized = false
    for (cmd in BLOCKED) {
        val re = Regex("\\\\" + cmd, RegexOption.IGNORE_CASE)
        if (re.containsMatchIn(expression)) sanitized = true
        expression = re.replace(expression) { "\\text{blocked}" }
    }
    return SanitizedMath(expression, sanitized)
}

private val FRAC = Regex("\\\\frac\\s*\\{([^{}]*)\\}\\s*\\{([^{}]*)\\}")
private val SUPER_RE = Regex("\\^\\{([^{}]+)\\}|\\^([A-Za-z0-9+\\-=()])")
private val SUB_RE = Regex("_\\{([^{}]+)\\}|_([A-Za-z0-9+\\-=()])")
private val LEFT_RIGHT = Regex("\\\\left|\\\\right")
private val TEXT_CMD = Regex("\\\\text\\{([^{}]*)\\}")
private val BRACES = Regex("[{}]")

private fun mapScript(value: String, map: Map<String, String>): String {
    val sb = StringBuilder()
    var i = 0
    while (i < value.length) {
        val cp = value.codePointAt(i)
        val ch = String(Character.toChars(cp))
        sb.append(map[ch] ?: ch)
        i += Character.charCount(cp)
    }
    return sb.toString()
}

fun renderMathToUnicode(expression: String): String {
    var out = expression
    var i = 0
    while (i < 24 && FRAC.containsMatchIn(out)) {
        out = FRAC.replace(out) { m -> "(${m.groupValues[1]})/(${m.groupValues[2]})" }
        i++
    }
    for ((re, sym) in MATH_SYMBOLS) out = re.replace(out) { sym }
    out = SUPER_RE.replace(out) { m -> mapScript(m.groups[1]?.value ?: m.groups[2]?.value ?: "", SUPER) }
    out = SUB_RE.replace(out) { m -> mapScript(m.groups[1]?.value ?: m.groups[2]?.value ?: "", SUB) }
    out = LEFT_RIGHT.replace(out, "")
    out = TEXT_CMD.replace(out) { m -> m.groupValues[1] }
    out = BRACES.replace(out, "")
    return out.trim()
}

private fun mathExpression(node: ElpianNode, ctx: BuildContext): W {
    val raw = jsString(node.props["expression"] ?: node.props["latex"] ?: node.props["text"] ?: node.props["data"] ?: "")
    val sanitized = sanitizeMath(raw)
    val rendered = renderMathToUnicode(sanitized.value)
    val style: TextStyle = if (node.style != null) createTextStyle(node.style) ?: TextStyle() else TextStyle(fontSize = 18.0)
    val result: W = if (rendered.trim() == "") {
        text("Math expression is required", style)
    } else {
        val parts = arrayListOf(w("scroll", mapOf("axis" to "horizontal"), text(rendered, style, mapOf("selectable" to true, "softWrap" to false))))
        if (sanitized.sanitized) {
            parts.add(padding(EdgeInsets(4.0, 0.0, 0.0, 0.0), text("Unsafe commands were sanitized from the expression.", TextStyle(fontSize = 11.0, color = Colors.orange))))
        }
        column(parts, mapOf("crossAxisAlignment" to "start", "mainAxisSize" to "min"))
    }
    return applyStyle(result, node.style, ApplyStyleOptions(), ctx)
}
