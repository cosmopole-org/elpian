package dev.elpian.core.widgets

import dev.elpian.core.canvas.commandFromJson
import dev.elpian.core.canvas.normalizeCommand
import dev.elpian.core.css.Alignment
import dev.elpian.core.css.Border
import dev.elpian.core.css.BorderRadius
import dev.elpian.core.css.BorderSide
import dev.elpian.core.css.BorderStyleName
import dev.elpian.core.css.BoxShadow
import dev.elpian.core.css.CSSStyle
import dev.elpian.core.css.Color
import dev.elpian.core.css.Colors
import dev.elpian.core.css.CssEnvironment
import dev.elpian.core.css.EdgeInsets
import dev.elpian.core.css.M3
import dev.elpian.core.css.TextDecoration
import dev.elpian.core.css.mediaMatches
import dev.elpian.core.css.parseColor
import dev.elpian.core.css.scaleAlpha
import dev.elpian.core.model.ElpianNode
import dev.elpian.core.render.RenderObject
import dev.elpian.core.render.TextDecorationBits
import dev.elpian.core.render.TextStyle
import dev.elpian.core.render.ViewEvent
import dev.elpian.core.render.W
import dev.elpian.core.render.layout.AreaSpec
import dev.elpian.core.render.layout.RenderImageMap
import dev.elpian.core.render.layout.areaContains
import dev.elpian.core.render.mergeTextStyle
import dev.elpian.core.render.paint.Decoration
import dev.elpian.core.render.paint.SpanInput
import dev.elpian.core.render.paint.isTruthy
import dev.elpian.core.render.toSpec
import dev.elpian.core.render.w
import dev.elpian.core.util.jsString
import dev.elpian.core.util.parseFloatPrefix
import dev.elpian.core.util.toNumber
import java.net.URLEncoder
import kotlin.math.max
import kotlin.math.min

/**
 * The HTML elements (widgets/html.ts) — one builder per file in
 * flutter/lib/src/html_widgets, lowered to the same composition (default
 * margins, sizes and colours are the Flutter engine's), with the elements
 * Flutter leaves as placeholders made real: tables lay out rows and cells,
 * forms collect and submit their fields, `details` expands, `picture` honours
 * its `source` media queries, image maps are clickable, `datalist` feeds input
 * suggestions, `sub`/`sup` shift the baseline.
 *
 * Inline content — a `p`/`span`/heading/`li`/`a` whose children are text-level
 * elements — becomes one paragraph of styled spans that wraps across element
 * boundaries, as HTML does.
 */

private fun num(v: Any?): Double? = toNumber(v)

/** A [CSSStyle] literal. */
internal fun css(init: CSSStyle.() -> Unit): CSSStyle = CSSStyle().apply(init)

private val STYLE_FIELDS: List<java.lang.reflect.Field> by lazy {
    CSSStyle::class.java.declaredFields.filter { !java.lang.reflect.Modifier.isStatic(it.modifiers) }.onEach { it.isAccessible = true }
}

/** `{...defaults, ...style}` keeping only the author's non-null fields. */
internal fun withDefaults(style: CSSStyle?, defaults: CSSStyle): CSSStyle {
    val out = defaults.copy()
    if (style == null) return out
    for (f in STYLE_FIELDS) {
        val v = f.get(style)
        if (v != null) f.set(out, v)
    }
    return out
}

private fun underline() = TextDecoration(underline = true, overline = false, lineThrough = false)
private fun lineThrough() = TextDecoration(underline = false, overline = false, lineThrough = true)

// ============================================================================
// Inline formatting
// ============================================================================

/** Default text styles of text-level elements. */
private val INLINE_DEFAULTS: Map<String, TextStyle> = linkedMapOf(
    "span" to TextStyle(),
    "strong" to TextStyle(fontWeight = 700),
    "b" to TextStyle(fontWeight = 700),
    "em" to TextStyle(italic = true),
    "i" to TextStyle(italic = true),
    "cite" to TextStyle(italic = true),
    "var" to TextStyle(italic = true),
    "dfn" to TextStyle(italic = true),
    "u" to TextStyle(decoration = TextDecorationBits.underline),
    "ins" to TextStyle(decoration = TextDecorationBits.underline),
    "s" to TextStyle(decoration = TextDecorationBits.lineThrough),
    "del" to TextStyle(decoration = TextDecorationBits.lineThrough),
    "strike" to TextStyle(decoration = TextDecorationBits.lineThrough),
    "code" to TextStyle(fontFamily = "monospace", background = 0xfff5f5f5.toInt()),
    "kbd" to TextStyle(fontFamily = "monospace", background = 0xffeeeeee.toInt()),
    "samp" to TextStyle(fontFamily = "monospace"),
    "tt" to TextStyle(fontFamily = "monospace"),
    "mark" to TextStyle(background = 0xffffff00.toInt()),
    "small" to TextStyle(fontSize = 12.0),
    "sub" to TextStyle(fontSize = 10.0, baselineShift = 3.0),
    "sup" to TextStyle(fontSize = 10.0, baselineShift = -6.0),
    "abbr" to TextStyle(decoration = TextDecorationBits.underline),
    "a" to TextStyle(color = Colors.blue, decoration = TextDecorationBits.underline),
    "q" to TextStyle(),
    "time" to TextStyle(),
    "data" to TextStyle(),
    "label" to TextStyle(fontWeight = 500),
)

private val INLINE_TAGS: Set<String> = INLINE_DEFAULTS.keys + setOf("br", "#text")

/**
 * The spans of an inline subtree, or null when it contains something that is
 * not text-level (a box, an image, a control, an element with its own events
 * other than a link).
 */
private fun inlineSpans(node: ElpianNode, inherited: TextStyle, ctx: BuildContext, depth: Int = 0): List<SpanInput>? {
    if (depth > 12) return null
    if (node.type == "#text") return listOf(SpanInput(jsString(node.props["text"] ?: ""), inherited))
    if (node.type == "br") return listOf(SpanInput("\n", inherited))
    if (node.type !in INLINE_TAGS) return null
    val s = node.style
    if (s != null && (s.display == "block" || s.display == "flex" || s.display == "grid" || s.position == "absolute" || s.position == "fixed")) return null
    if (s != null && (s.width != null || s.height != null || s.border != null || s.borderRadius != null || s.boxShadow != null || s.transform != null)) return null
    if (s?.display == "none") return emptyList()
    val events = node.events?.keys?.toList() ?: emptyList()
    val isLink = node.type == "a" && events.all { it == "click" || it == "tap" }
    if (events.isNotEmpty() && !isLink) return null
    var own = mergeTextStyle(mergeTextStyle(inherited, INLINE_DEFAULTS[node.type] ?: TextStyle()), createTextStyle(s))
    s?.backgroundColor?.let { own = own.copy(background = it) }
    val link = if (node.type == "a") jsString(node.props["href"] ?: "#") else null
    val out = ArrayList<SpanInput>()
    val t = node.text
    if (t.isNotEmpty()) out.add(SpanInput(if (node.type == "q") "“$t”" else t, own, link))
    for (child in node.children) {
        val childSpans = inlineSpans(child, own, ctx, depth + 1) ?: return null
        for (span in childSpans) out.add(if (link != null && span.link == null) span.copy(link = link) else span)
    }
    return out
}

/** A paragraph from an element's text and inline children, or null if not inline. */
private fun richText(node: ElpianNode, style: TextStyle, ctx: BuildContext, opts: Map<String, Any?> = emptyMap()): W? {
    if (node.children.isEmpty()) return null
    val spans = ArrayList<SpanInput>()
    val t = node.text
    if (t.isNotEmpty()) spans.add(SpanInput(t, TextStyle()))
    for (child in node.children) {
        val childSpans = inlineSpans(child, TextStyle(), ctx) ?: return null
        spans.addAll(childSpans)
    }
    val props = linkedMapOf<String, Any?>("spans" to spans, "style" to style)
    props.putAll(opts)
    props["onLink"] = { href: String -> openLink(ctx, href, null) }
    return w("text", props)
}

private val EXTERNAL_LINK = Regex("^(https?:|mailto:|tel:|sms:|geo:)", RegexOption.IGNORE_CASE)
private val HTTP_LINK = Regex("^https?:", RegexOption.IGNORE_CASE)

private fun openLink(ctx: BuildContext, href: String, node: ElpianNode?) {
    if (node?.events?.get("click") != null || node?.events?.get("tap") != null) {
        dispatchEvent(ctx, "click")
    }
    if (href.isEmpty() || href == "#") return
    val host = ctx.engine.host
    val navigate = host.navigate
    if (EXTERNAL_LINK.containsMatchIn(href) || navigate == null) {
        host.openUrl?.invoke(href)
    } else {
        navigate(href, false)
    }
}

// ============================================================================
// Layout: HtmlDiv
// ============================================================================

private fun childStyle(node: ElpianNode): CSSStyle? {
    var n = node
    while (n.type == "Scope" && n.children.size == 1) n = n.children[0]
    return n.style
}

private fun stretchChild(child: W): W {
    val inner = child.c?.firstOrNull()
    if (child.t == "flexible" && inner != null) {
        return W(child.t, child.p, listOf(w("fill", mapOf("width" to true), inner)), child.k)
    }
    return w("fill", mapOf("width" to true), child)
}

private fun unflex(child: W): W {
    val inner = child.c?.firstOrNull()
    return if (child.t == "flexible" && inner != null) inner else child
}

/** `_buildColumn`: stretch children without an explicit width (CSS block flow). */
private fun buildColumn(node: ElpianNode, children: List<W>, gap: Double, mainAxisAlignment: String, mainAxisSize: String, flowNodes: List<ElpianNode>): W {
    val alignItems = node.style?.alignItems
    val canStretch = alignItems == null && flowNodes.size == children.size
    val reverse = node.style?.flexDirection == "column-reverse"
    if (!canStretch) {
        return w(
            "flex",
            mapOf("direction" to "column", "mainAxisAlignment" to mainAxisAlignment, "crossAxisAlignment" to crossOf(alignItems), "mainAxisSize" to mainAxisSize, "gap" to gap, "reverse" to reverse),
            children,
        )
    }
    val laid = children.mapIndexed { i, child ->
        val cs = childStyle(flowNodes[i])
        if (cs?.width == null && cs?.widthFactor == null) stretchChild(child) else child
    }
    return w(
        "flex",
        mapOf("direction" to "column", "mainAxisAlignment" to mainAxisAlignment, "crossAxisAlignment" to "start", "mainAxisSize" to mainAxisSize, "gap" to gap, "reverse" to reverse),
        laid,
    )
}

private fun mainOf(v: String?): String = when ((v ?: "").lowercase()) {
    "center" -> "center"
    "flex-end", "end", "right" -> "end"
    "space-between" -> "spaceBetween"
    "space-around" -> "spaceAround"
    "space-evenly" -> "spaceEvenly"
    else -> "start"
}

private fun crossOf(v: String?): String = when ((v ?: "").lowercase()) {
    "center" -> "center"
    "flex-end", "end" -> "end"
    "stretch" -> "stretch"
    "baseline" -> "baseline"
    else -> "start"
}

private fun wrapCrossOf(v: String?): String {
    val c = crossOf(v)
    return if (c == "center" || c == "end") c else "start"
}

private fun buildFlow(node: ElpianNode, children: List<W>, flowNodes: List<ElpianNode>): W {
    val s = node.style
    val display = s?.display
    if (display == "grid" || display == "inline-grid") return buildGrid(node, children, flowNodes)
    val gap = s?.gap ?: s?.columnGap ?: 0.0
    if (display == "flex" || display == "inline-flex") {
        val dir = s?.flexDirection ?: "row"
        val isRow = dir == "row" || dir == "row-reverse"
        val wraps = s?.flexWrap == "wrap" || s?.flexWrap == "wrap-reverse"
        if (wraps) {
            return w(
                "wrap",
                mapOf(
                    "direction" to (if (isRow) "horizontal" else "vertical"),
                    "spacing" to (if (isRow) s?.columnGap ?: gap else s?.rowGap ?: gap),
                    "runSpacing" to (if (isRow) s?.rowGap ?: gap else s?.columnGap ?: gap),
                    "alignment" to mainOf(s?.justifyContent),
                    "runAlignment" to mainOf(s?.alignContent),
                    "crossAxisAlignment" to wrapCrossOf(s?.alignItems),
                    "verticalDirection" to (if (s?.flexWrap == "wrap-reverse") "up" else "down"),
                    "reverse" to dir.endsWith("reverse"),
                ),
                children,
            )
        }
        if (isRow) {
            val flex = w(
                "flex",
                mapOf(
                    "direction" to "row",
                    "mainAxisAlignment" to mainOf(s?.justifyContent),
                    "crossAxisAlignment" to crossOf(s?.alignItems),
                    "mainAxisSize" to "max",
                    "gap" to (s?.columnGap ?: gap),
                    "reverse" to (dir == "row-reverse"),
                    "shrink" to true,
                ),
                children,
            )
            val hasFlex = flowNodes.any { c -> (childStyle(c)?.flex ?: childStyle(c)?.flexGrow) != null }
            // `_flexSafe`: an unbounded row with flex children takes its intrinsic width.
            return if (hasFlex) w("intrinsicWidth", mapOf("onlyWhenUnbounded" to true), listOf(flex)) else flex
        }
        return buildColumn(node, children, s?.rowGap ?: gap, mainOf(s?.justifyContent), "max", flowNodes)
    }
    if (children.size == 1) return unflex(children[0])
    return buildColumn(node, children, s?.rowGap ?: gap, "start", "min", flowNodes)
}

private fun buildGrid(node: ElpianNode, children: List<W>, flowNodes: List<ElpianNode>): W {
    val s = node.style ?: CSSStyle()
    val base = s.gridGap ?: s.gap ?: 0.0
    val items = children.mapIndexed { i, child ->
        val cs = childStyle(flowNodes[i])
        val area = cs?.gridArea
        val parts = if (!area.isNullOrEmpty() && area.contains('/')) area.split('/') else null
        w(
            "gridItem",
            mapOf(
                "column" to (cs?.gridColumn ?: parts?.getOrNull(1)),
                "row" to (cs?.gridRow ?: parts?.getOrNull(0)),
                "alignSelf" to cs?.alignSelf,
            ),
            unflex(child),
        )
    }
    return w(
        "grid",
        mapOf(
            "columns" to s.gridTemplateColumns,
            "rows" to s.gridTemplateRows,
            "autoRows" to s.gridAutoRows,
            "columnGap" to (s.gridColumnGap ?: s.columnGap ?: base),
            "rowGap" to (s.gridRowGap ?: s.rowGap ?: base),
            "alignItems" to s.alignItems,
        ),
        items,
    )
}

private fun buildPositioned(node: ElpianNode, children: List<W>): W? {
    val nodes = node.children
    if (nodes.size != children.size) return null
    val styles = nodes.map { childStyle(it) }
    fun isAbs(st: CSSStyle?) = st?.position == "absolute" || st?.position == "fixed"
    if (styles.none { isAbs(it) }) return null
    val flow = ArrayList<W>()
    val flowNodes = ArrayList<ElpianNode>()
    val positioned = ArrayList<Int>()
    styles.forEachIndexed { i, st ->
        if (isAbs(st)) positioned.add(i)
        else {
            flow.add(children[i])
            flowNodes.add(nodes[i])
        }
    }
    val order = positioned.sortedWith(compareBy<Int>({ styles[it]?.zIndex ?: 0.0 }, { it }))
    val stackChildren = ArrayList<W>()
    if (flow.isNotEmpty()) stackChildren.add(w("fill", mapOf("width" to true), buildFlow(node, flow, flowNodes)))
    for (i in order) {
        val st = styles[i]!!
        val lr = st.left != null && st.right != null
        val tb = st.top != null && st.bottom != null
        stackChildren.add(
            w(
                "positioned",
                mapOf("top" to st.top, "left" to st.left, "right" to st.right, "bottom" to st.bottom, "width" to (if (lr) null else st.width), "height" to (if (tb) null else st.height)),
                unflex(children[i]),
            ),
        )
    }
    return w("stack", mapOf("alignment" to Alignment(-1.0, -1.0), "fit" to "loose", "clip" to true), stackChildren)
}

/** `HtmlDiv.build` — the CSS box: block, flex, grid and positioned layouts. */
fun htmlDiv(node: ElpianNode, children: List<W>, ctx: BuildContext, fullWidth: Boolean = false): W {
    if (children.isEmpty()) {
        var empty: W = SHRINK
        if (fullWidth) empty = w("fill", mapOf("width" to true), empty)
        return applyStyle(empty, node.style, ApplyStyleOptions(layoutHandled = true), ctx)
    }
    val positioned = buildPositioned(node, children)
    var body = positioned ?: buildFlow(node, children, node.children)
    if (fullWidth) body = w("fill", mapOf("width" to true), body)
    return applyStyle(body, node.style, ApplyStyleOptions(layoutHandled = true), ctx)
}

// ============================================================================
// Text-bearing elements
// ============================================================================

private fun textElement(node: ElpianNode, ctx: BuildContext, defaults: CSSStyle, baseText: TextStyle = TextStyle()): W {
    val style = withDefaults(node.style, defaults)
    val ts = mergeTextStyle(baseText, createTextStyle(style))
    val opts = textOptionsFromStyle(style)
    val rich = richText(node, ts, ctx, opts)
    if (rich != null) return applyStyle(rich, style, ApplyStyleOptions(), ctx)
    return applyStyle(text(node.text, ts, opts), style, ApplyStyleOptions(), ctx)
}

/** A text element that may also hold block children (Column of text + children). */
private fun textWithChildren(node: ElpianNode, children: List<W>, ctx: BuildContext, defaults: CSSStyle, layout: String): W {
    val style = withDefaults(node.style, defaults)
    val ts = createTextStyle(style) ?: TextStyle()
    val opts = textOptionsFromStyle(style)
    if (children.isEmpty()) return applyStyle(text(node.text, ts, opts), style, ApplyStyleOptions(), ctx)
    val rich = richText(node, ts, ctx, opts)
    if (rich != null) return applyStyle(rich, style, ApplyStyleOptions(), ctx)
    val parts = ArrayList<W>()
    val t = node.text
    if (t.isNotEmpty()) parts.add(text(t, ts, opts))
    parts.addAll(children)
    val body = if (layout == "column") {
        column(parts, mapOf("crossAxisAlignment" to "start", "mainAxisSize" to "min"))
    } else {
        w("wrap", mapOf("direction" to "horizontal", "crossAxisAlignment" to "center"), parts)
    }
    return applyStyle(w("defaultTextStyle", mapOf("style" to ts), body), style, ApplyStyleOptions(layoutHandled = true), ctx)
}

private fun heading(size: Double, marginV: Double): WidgetBuilder = { node, children, ctx ->
    textWithChildren(node, children, ctx, css { fontSize = size; fontWeight = 700; margin = EdgeInsets.symmetric(marginV, 0.0) }, "column")
}

private fun monoStyle(bg: Color, pad: EdgeInsets, extra: CSSStyle.() -> Unit = {}): CSSStyle = css {
    fontFamily = "monospace"
    backgroundColor = bg
    padding = pad
    extra()
}

/**
 * Flutter's text-level elements use `node.style ?? defaultStyle` (an author
 * style replaces the defaults wholesale) — kept for fidelity.
 */
private fun replaceDefaults(node: ElpianNode, ctx: BuildContext, defaults: CSSStyle, inline: TextStyle): W {
    val style = node.style ?: defaults
    val ts = mergeTextStyle(if (node.style != null) INLINE_DEFAULTS[node.type] ?: TextStyle() else inline, createTextStyle(style))
    val rich = richText(node, ts, ctx)
    return applyStyle(rich ?: text(node.text, ts, textOptionsFromStyle(style)), style, ApplyStyleOptions(), ctx)
}

// ============================================================================
// Form controls
// ============================================================================

private object DARK {
    const val text: Color = 0xfff7eedc.toInt()
    const val fill: Color = 0xff0a1626.toInt()
    const val border: Color = 0xff1c3450.toInt()
    const val focus: Color = 0xffd6b36a.toInt()
    const val hint: Color = 0xff6b7e92.toInt()
}

private class CheckedState(var checked: Boolean)
private class NumberState(var value: Double)
private class StringState(var value: String)
private class SelectState(var value: String?, var lastProp: String?)
private class OpenState(var open: Boolean)

private fun datalistOptions(ctx: BuildContext, listId: String?): List<String>? {
    if (listId.isNullOrEmpty()) return null
    val list = ctx.engine.datalists[listId]
    return if (!list.isNullOrEmpty()) list.toList() else null
}

private fun idOf(node: ElpianNode): String? = node.props["id"]?.let { jsString(it) }

private fun htmlInput(node: ElpianNode, children: List<W>, ctx: BuildContext): W {
    val type = jsString(node.props["type"] ?: "text").lowercase()
    val name = node.props["name"]?.let { jsString(it) }
    val disabled = node.props["disabled"] == true || node.props["disabled"] == "disabled"

    if (type == "hidden") {
        ctx.engine.registerFormField(ctx.formId, name) { node.props["value"] ?: "" }
        return SHRINK
    }

    if (type == "checkbox") {
        val state = ctx.engine.stateFor(ctx.elementId) { CheckedState(node.props["checked"] == true || node.props["checked"] == "checked") }
        ctx.engine.registerFormField(ctx.formId, name) { if (state.checked) node.props["value"] ?: "on" else null }
        val result = w(
            "control",
            mapOf(
                "kind" to "checkbox",
                "focusId" to idOf(node),
                "view" to linkedMapOf(
                    "checked" to state.checked,
                    "enabled" to !disabled,
                    "colors" to linkedMapOf("fill" to (node.style?.color ?: M3.primary), "check" to M3.onPrimary, "border" to M3.onSurfaceVariant),
                ),
                "onEvent" to { e: ViewEvent ->
                    if (e.type == "change") {
                        state.checked = isTruthy(e.value)
                        dispatchEvent(ctx, "change", mapOf("value" to state.checked))
                    }
                },
            ),
        )
        return applyStyle(result, node.style, ApplyStyleOptions(), ctx)
    }

    if (type == "radio") {
        val value = node.props["value"]
        val group = node.props["groupValue"]
        val checked = if (node.props.containsKey("groupValue")) value == group else node.props["checked"] == true || node.props["checked"] == "checked"
        ctx.engine.registerFormField(ctx.formId, name) { if (checked) value else null }
        val result = w(
            "control",
            mapOf(
                "kind" to "radio",
                "focusId" to idOf(node),
                "view" to linkedMapOf(
                    "checked" to checked,
                    "value" to value,
                    "enabled" to !disabled,
                    "colors" to linkedMapOf("fill" to (node.style?.color ?: M3.primary), "border" to M3.onSurfaceVariant),
                ),
                "controlled" to true,
                "onEvent" to { e: ViewEvent -> if (e.type == "change") dispatchEvent(ctx, "change", mapOf("value" to value)) },
            ),
        )
        return applyStyle(result, node.style, ApplyStyleOptions(), ctx)
    }

    if (type == "range") {
        val minV = num(node.props["min"]) ?: 0.0
        val maxV = num(node.props["max"]) ?: 100.0
        val state = ctx.engine.stateFor(ctx.elementId) { NumberState(max(minV, min(maxV, num(node.props["value"]) ?: ((minV + maxV) / 2)))) }
        ctx.engine.registerFormField(ctx.formId, name) { state.value }
        val step = num(node.props["step"]) ?: 1.0
        val result = w(
            "control",
            mapOf(
                "kind" to "slider",
                "focusId" to idOf(node),
                "view" to linkedMapOf(
                    "value" to state.value,
                    "min" to minV,
                    "max" to maxV,
                    "step" to step,
                    "enabled" to !disabled,
                    "colors" to linkedMapOf("active" to DARK.focus, "inactive" to DARK.border, "thumb" to DARK.focus),
                ),
                "onEvent" to { e: ViewEvent ->
                    if (e.type == "input" || e.type == "change") {
                        state.value = jsNumber(e.value)
                        dispatchEvent(ctx, if (e.type == "input") "input" else "change", mapOf("value" to state.value))
                    }
                },
            ),
        )
        return applyStyle(result, node.style, ApplyStyleOptions(), ctx)
    }

    if (type == "submit" || type == "button" || type == "reset") {
        val label = jsString(node.props["value"] ?: node.props["text"] ?: (if (type == "submit") "Submit" else if (type == "reset") "Reset" else "Button"))
        val fg = node.style?.color ?: (if (node.style?.backgroundColor != null) Colors.white else M3.primary)
        return htmlButtonLike(node, listOf(text(label, TextStyle(color = fg))), ctx, type)
    }

    // Text-like inputs.
    val state = ctx.engine.stateFor(ctx.elementId) { StringState(node.props["value"]?.let { jsString(it) } ?: "") }
    ctx.engine.registerFormField(ctx.formId, name) { if (type == "number") (if (state.value == "") null else jsNumber(state.value)) else state.value }
    val s = node.style
    val textColor = s?.color ?: DARK.text
    val fontSize = s?.fontSize ?: 13.0
    val ts = TextStyle(color = textColor, fontSize = fontSize, height = 1.3, letterSpacing = 0.0)
    val view = linkedMapOf<String, Any?>(
        "value" to state.value,
        "placeholder" to jsString(node.props["placeholder"] ?: ""),
        "inputType" to type,
        "multiline" to false,
        "maxLength" to num(node.props["maxLength"] ?: node.props["maxlength"]),
        "enabled" to !disabled,
        "readOnly" to (node.props["readOnly"] == true || node.props["readonly"] != null),
        "autofocus" to (node.props["autofocus"] == true || node.props["autofocus"] == "autofocus"),
    )
    num(node.props["min"])?.let { view["min"] = it }
    num(node.props["max"])?.let { view["max"] = it }
    view["suggestions"] = datalistOptions(ctx, node.props["list"]?.let { jsString(it) })
    view["variant"] = "outline"
    view["textStyle"] = ts.toSpec()
    view["hintStyle"] = ts.copy(color = DARK.hint).toSpec()
    view["contentPadding"] = listOf(10.0, 10.0, 10.0, 10.0)
    view["colors"] = linkedMapOf(
        "text" to textColor,
        "hint" to DARK.hint,
        "fill" to (s?.backgroundColor ?: DARK.fill),
        "border" to DARK.border,
        "focusedBorder" to DARK.focus,
        "cursor" to DARK.focus,
        "radius" to 8.0,
    )
    val result = w(
        "control",
        mapOf(
            "kind" to "textInput",
            "focusId" to idOf(node),
            "lines" to 1.0,
            "padding" to listOf(10.0, 10.0, 10.0, 10.0),
            "lineHeight" to fontSize * 1.3,
            "view" to view,
            "onEvent" to { e: ViewEvent ->
                if (e.type == "input" || e.type == "change") {
                    state.value = if (e.value == null) "" else jsString(e.value)
                    dispatchEvent(ctx, "input", mapOf("value" to state.value))
                } else if (e.type == "submit") {
                    dispatchEvent(ctx, "submit")
                    ctx.formId?.let { ctx.engine.submitForm(it) }
                } else if (e.type == "focus" || e.type == "blur") {
                    dispatchEvent(ctx, e.type)
                    if (e.type == "blur" && node.events?.get("change") != null) dispatchEvent(ctx, "change", mapOf("value" to state.value))
                }
            },
        ),
    )
    return applyStyle(result, s, ApplyStyleOptions(), ctx)
}

private fun htmlTextarea(node: ElpianNode, @Suppress("UNUSED_PARAMETER") children: List<W>, ctx: BuildContext): W {
    val state = ctx.engine.stateFor(ctx.elementId) { StringState(jsString(node.props["value"] ?: node.props["text"] ?: "")) }
    ctx.engine.registerFormField(ctx.formId, node.props["name"]?.let { jsString(it) }) { state.value }
    val lines = max(1.0, num(node.props["rows"]) ?: 5.0)
    val ts = TextStyle(fontSize = 16.0, height = 1.5, letterSpacing = 0.5, color = node.style?.color ?: M3.onSurface)
    val result = w(
        "control",
        mapOf(
            "kind" to "textInput",
            "focusId" to idOf(node),
            "lines" to lines,
            "padding" to listOf(16.0, 12.0, 16.0, 12.0),
            "lineHeight" to 24.0,
            "view" to linkedMapOf(
                "value" to state.value,
                "placeholder" to jsString(node.props["placeholder"] ?: ""),
                "inputType" to "multiline",
                "multiline" to true,
                "maxLines" to lines,
                "minLines" to lines,
                "enabled" to (node.props["disabled"] == null),
                "readOnly" to (node.props["readOnly"] == true || node.props["readonly"] != null),
                "variant" to "outline",
                "textStyle" to ts.toSpec(),
                "hintStyle" to ts.copy(color = M3.onSurfaceVariant).toSpec(),
                "contentPadding" to listOf(16.0, 12.0, 16.0, 12.0),
                "colors" to linkedMapOf(
                    "text" to (ts.color ?: M3.onSurface),
                    "hint" to M3.onSurfaceVariant,
                    "border" to M3.outline,
                    "focusedBorder" to M3.primary,
                    "cursor" to M3.primary,
                    "fill" to null,
                    "radius" to 4.0,
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
    return applyStyle(result, node.style, ApplyStyleOptions(), ctx)
}

/** A select option: `{value, label}` plus `group` / `disabled` when known. */
private fun selectOptions(node: ElpianNode): List<Map<String, Any?>> {
    val out = ArrayList<Map<String, Any?>>()
    val raw = node.props["options"]
    if (raw is List<*>) {
        for (o in raw) {
            if (o is Map<*, *>) {
                val v = jsString(o["value"] ?: o["label"] ?: "")
                out.add(linkedMapOf("value" to v, "label" to jsString(o["label"] ?: v), "group" to o["group"], "disabled" to (o["disabled"] == true)))
            } else if (o != null) out.add(linkedMapOf("value" to jsString(o), "label" to jsString(o)))
        }
    }
    if (out.isEmpty()) {
        fun visit(n: ElpianNode, group: String?) {
            for (c in n.children) {
                if (c.type == "option") {
                    val v = jsString(c.props["value"] ?: c.props["text"] ?: "")
                    out.add(
                        linkedMapOf(
                            "value" to v,
                            "label" to jsString(c.props["text"] ?: c.props["label"] ?: v),
                            "group" to group,
                            "disabled" to (c.props["disabled"] != null && c.props["disabled"] != false),
                        ),
                    )
                } else if (c.type == "optgroup") visit(c, jsString(c.props["label"] ?: ""))
            }
        }
        visit(node, null)
    }
    return out
}

private fun htmlSelect(node: ElpianNode, @Suppress("UNUSED_PARAMETER") children: List<W>, ctx: BuildContext): W {
    val options = selectOptions(node)
    val selectedChild = node.children.firstOrNull { it.type == "option" && (it.props["selected"] == true || it.props["selected"] == "selected") }
    val incoming = node.props["value"]?.let { jsString(it) }
    val state = ctx.engine.stateFor(ctx.elementId) {
        SelectState(
            incoming ?: selectedChild?.let { jsString(it.props["value"] ?: it.props["text"] ?: "") },
            incoming,
        )
    }
    // didUpdateWidget: an incoming prop value change wins.
    if (incoming != null && incoming != state.lastProp) {
        state.value = incoming
        state.lastProp = incoming
    }
    val value = if (options.any { it["value"] == state.value }) state.value else options.firstOrNull()?.get("value") as String?
    ctx.engine.registerFormField(ctx.formId, node.props["name"]?.let { jsString(it) }) { value }
    val s = node.style
    val ts = TextStyle(color = s?.color ?: DARK.text, fontSize = s?.fontSize ?: 13.0, height = 1.3)
    var result: W = w(
        "control",
        mapOf(
            "kind" to "select",
            "focusId" to idOf(node),
            "padding" to listOf(0.0, 10.0, 0.0, 10.0),
            "view" to linkedMapOf(
                "value" to value,
                "options" to options,
                "enabled" to (node.props["disabled"] == null),
                "textStyle" to ts.toSpec(),
                "colors" to linkedMapOf("text" to (ts.color ?: DARK.text), "fill" to DARK.fill, "icon" to DARK.focus, "menu" to DARK.fill),
            ),
            "onEvent" to { e: ViewEvent ->
                if (e.type == "change" && e.value != null) {
                    state.value = jsString(e.value)
                    dispatchEvent(ctx, "change", mapOf("value" to state.value))
                    ctx.engine.host.invalidate?.invoke()
                }
            },
        ),
    )
    result = container(
        child = result,
        padding = EdgeInsets.symmetric(0.0, 10.0),
        decoration = Decoration(color = DARK.fill, radius = BorderRadius.all(8.0), border = Border.all(BorderSide(1.0, DARK.border, BorderStyleName.solid))),
    )
    return applyStyle(result, s, ApplyStyleOptions(), ctx)
}

private fun htmlButtonLike(node: ElpianNode, children: List<W>, ctx: BuildContext, type: String? = null): W {
    val s = node.style
    val label = jsString(node.props["text"] ?: "Button")
    val fg = s?.color ?: (if (s?.backgroundColor != null) Colors.white else M3.primary)
    val child = children.firstOrNull() ?: text(label, TextStyle(color = fg))
    val kind = type ?: jsString(node.props["type"] ?: (if (ctx.formId != null) "submit" else "button")).lowercase()
    val disabled = node.props["disabled"] == true || node.props["disabled"] == "disabled"
    val press = buttonPressed(ctx)
    val onPressed: (() -> Unit)? = if (disabled) null else {
        {
            press()
            if (kind == "submit" && ctx.formId != null) ctx.engine.submitForm(ctx.formId)
            if (kind == "reset" && ctx.formId != null) dispatchEvent(ctx, "reset")
        }
    }
    return buttonOuter(materialButton(ButtonOptions(child, s, onPressed, semanticsLabel = label)), s)
}

// ============================================================================
// Media
// ============================================================================

private fun mediaSource(node: ElpianNode, ctx: BuildContext): String {
    val direct = node.props["src"]
    if (isTruthy(direct)) return ctx.engine.resolveUrl(jsString(direct))
    for (c in node.children) if (c.type == "source" && isTruthy(c.props["src"])) return ctx.engine.resolveUrl(jsString(c.props["src"]))
    return ""
}

private val MEDIA_EVENTS = setOf("play", "pause", "ended", "timeupdate", "load", "error", "volumechange", "seeked")

private fun mediaElement(kind: String): WidgetBuilder = { node, _, ctx ->
    val src = mediaSource(node, ctx)
    val tracks = node.children
        .filter { it.type == "track" && isTruthy(it.props["src"]) }
        .map { c ->
            linkedMapOf(
                "src" to ctx.engine.resolveUrl(jsString(c.props["src"])),
                "kind" to jsString(c.props["kind"] ?: "subtitles"),
                "srclang" to c.props["srclang"]?.let { jsString(it) },
                "label" to c.props["label"]?.let { jsString(it) },
                "default" to (c.props["default"] == true || c.props["default"] == "default"),
            )
        }
    if (src.isEmpty()) {
        val msg = if (kind == "video") "video src is required" else "audio src is required"
        applyStyle(
            if (kind == "video") {
                decorated(Decoration(color = Colors.black), center(text(msg, TextStyle(color = Colors.white70))))
            } else {
                row(listOf(padding(EdgeInsets.all(16.0), icon("audiotrack", 24.0)), text(msg)), mapOf("mainAxisSize" to "min"))
            },
            node.style,
            ApplyStyleOptions(),
            ctx,
        )
    } else {
        val result = w(
            "media",
            mapOf(
                "kind" to kind,
                "src" to src,
                "autoplay" to (node.props["autoplay"] == true || node.props["autoplay"] == "autoplay"),
                "loop" to (node.props["loop"] == true || node.props["loop"] == "loop"),
                "muted" to (node.props["muted"] == true || node.props["muted"] == "muted"),
                "controls" to (node.props["controls"] != false),
                "poster" to (if (isTruthy(node.props["poster"])) ctx.engine.resolveUrl(jsString(node.props["poster"])) else null),
                "tracks" to (if (tracks.isNotEmpty()) tracks else null),
                "width" to (if (kind == "video") node.style?.width ?: num(node.props["width"]) else node.style?.width),
                "height" to (if (kind == "video") node.style?.height ?: num(node.props["height"]) else null),
                "fit" to (node.style?.objectFit?.name ?: "contain"),
                "onEvent" to { e: ViewEvent ->
                    if (e.type in MEDIA_EVENTS) {
                        dispatchEvent(ctx, if (e.type == "load") "loadedmetadata" else e.type, mapOf("value" to e.value))
                        if (e.type == "load") dispatchEvent(ctx, "load", mapOf("value" to e.value))
                    }
                },
            ),
        )
        applyStyle(result, node.style, ApplyStyleOptions(), ctx)
    }
}

private val IMAGE_EXT = Regex("\\.(png|jpe?g|gif|webp|svg|bmp|avif)$")
private val VIDEO_EXT = Regex("\\.(mp4|webm|mov|m3u8|mkv|ogv)$")
private val AUDIO_EXT = Regex("\\.(mp3|wav|ogg|aac|m4a|flac|opus)$")

private fun looksLike(kind: String, type: String, src: String): Boolean {
    val s = src.lowercase().split('?')[0]
    return when (kind) {
        "image" -> type.startsWith("image/") || IMAGE_EXT.containsMatchIn(s)
        "video" -> type.startsWith("video/") || VIDEO_EXT.containsMatchIn(s)
        else -> type.startsWith("audio/") || AUDIO_EXT.containsMatchIn(s)
    }
}

private fun webContent(node: ElpianNode, ctx: BuildContext, src: String, label: String): W {
    if (src.isEmpty() && !isTruthy(node.props["srcdoc"])) {
        return applyStyle(center(text("$label source is required")), node.style, ApplyStyleOptions(), ctx)
    }
    val result = w(
        "web",
        mapOf(
            "src" to (if (src.isNotEmpty()) ctx.engine.resolveUrl(src) else null),
            "html" to (if (isTruthy(node.props["srcdoc"])) jsString(node.props["srcdoc"]) else null),
            "width" to (node.style?.width ?: num(node.props["width"])),
            "height" to (node.style?.height ?: num(node.props["height"])),
            "onEvent" to { e: ViewEvent -> if (e.type == "load" || e.type == "error") dispatchEvent(ctx, e.type, mapOf("value" to e.value)) },
        ),
    )
    return applyStyle(result, node.style, ApplyStyleOptions(), ctx)
}

private fun embedTyped(node: ElpianNode, children: List<W>, ctx: BuildContext, src: String): W {
    val type = jsString(node.props["type"] ?: "").lowercase()
    val withSrc = ElpianNode(node.type, LinkedHashMap(node.props).also { it["src"] = src }, node.children, node.key, node.events, node.style)
    if (looksLike("image", type, src)) return htmlImg(withSrc, children, ctx)
    if (looksLike("video", type, src)) return mediaElement("video")(withSrc, children, ctx)
    if (looksLike("audio", type, src)) return mediaElement("audio")(withSrc, children, ctx)
    return webContent(withSrc, ctx, src, node.type)
}

private fun htmlImg(node: ElpianNode, @Suppress("UNUSED_PARAMETER") children: List<W>, ctx: BuildContext): W {
    val rawSrc = jsString(node.props["src"] ?: "")
    val src = ctx.engine.resolveUrl(chooseSrcset(node, rawSrc))
    val s = node.style
    val img = w(
        "image",
        mapOf(
            "src" to src,
            "fit" to (s?.objectFit?.name ?: (if (s?.width != null && s.height != null) "fill" else "contain")),
            "alignment" to s?.objectPosition,
            "width" to (s?.width ?: num(node.props["width"])),
            "height" to (s?.height ?: num(node.props["height"])),
            "alt" to node.props["alt"]?.let { jsString(it) },
            "onEvent" to { e: ViewEvent -> if (e.type == "load" || e.type == "error") dispatchEvent(ctx, e.type, mapOf("value" to e.value)) },
        ),
    )
    var result: W = img
    val usemap = (node.props["usemap"] as? String)?.removePrefix("#")
    val areas = if (!usemap.isNullOrEmpty()) ctx.engine.imageMaps[usemap] else null
    if (!areas.isNullOrEmpty()) {
        val specs = ArrayList<AreaSpec>()
        val regions = ArrayList<W>()
        areas.forEachIndexed { i, area ->
            val shape = jsString(area.props["shape"] ?: "rect").lowercase()
            val coords = jsString(area.props["coords"] ?: "").split(',').mapNotNull { parseFloatPrefix(it) }.filter { it.isFinite() }
            val spec = AreaSpec(
                when (shape) {
                    "circ", "circle" -> "circle"
                    "poly", "polygon" -> "poly"
                    "default" -> "default"
                    else -> "rect"
                },
                coords,
            )
            specs.add(spec)
            val href = area.props["href"]?.let { jsString(it) }
            val areaId = area.key ?: "${ctx.elementId}/area$i"
            regions.add(
                w(
                    "gesture",
                    mapOf(
                        "gestures" to listOf("tap"),
                        "cursor" to "pointer",
                        "tooltip" to (area.props["title"] ?: area.props["alt"]),
                        "semanticsLabel" to area.props["alt"],
                        "onEvent" to { e: ViewEvent, ro: Any? ->
                            if (e.type == "tap") {
                                // Precise hit test in natural image pixels.
                                val gesture = ro as? RenderObject
                                val map = gesture?.parent as? RenderImageMap
                                val sx = map?.scale?.x ?: 1.0
                                val sy = map?.scale?.y ?: 1.0
                                val px = ((e.localX ?: 0.0) + (gesture?.offset?.x ?: 0.0)) / sx
                                val py = ((e.localY ?: 0.0) + (gesture?.offset?.y ?: 0.0)) / sy
                                if (areaContains(spec, px, py)) {
                                    if (area.events != null) {
                                        ctx.engine.services.events.registerNode(areaId, area, ctx.elementId)
                                        ctx.engine.handleGesture(areaId, area, e.copy(type = "tap"))
                                    }
                                    if (href != null) openLink(ctx, href, null)
                                }
                            }
                        },
                    ),
                ),
            )
        }
        result = w("imageMap", mapOf("src" to src, "areas" to specs), listOf(img) + regions)
    }
    return applyStyle(result, s, ApplyStyleOptions(), ctx)
}

private val WS = Regex("\\s+")

/** `srcset` with `w` descriptors: the smallest candidate covering the viewport × dpr. */
private fun chooseSrcset(node: ElpianNode, fallback: String): String {
    val srcset = node.props["srcset"] ?: node.props["srcSet"]
    if (srcset !is String || srcset.trim() == "") return fallback
    val dpr = CssEnvironment.devicePixelRatio
    val target = CssEnvironment.viewportWidth * dpr
    class Candidate(val url: String, val w: Double?, val x: Double?)
    val candidates = srcset.split(',')
        .map { it.trim().split(WS) }
        .filter { it[0].isNotEmpty() }
        .map { p ->
            val d = p.getOrNull(1) ?: "1x"
            Candidate(p[0], if (d.endsWith("w")) parseFloatPrefix(d) ?: Double.NaN else null, if (d.endsWith("x")) parseFloatPrefix(d) ?: Double.NaN else null)
        }
    val byWidth = candidates.filter { it.w != null }.sortedBy { it.w!! }
    if (byWidth.isNotEmpty()) return (byWidth.firstOrNull { it.w!! >= target } ?: byWidth.last()).url
    val byDensity = candidates.filter { it.x != null }.sortedBy { it.x!! }
    if (byDensity.isNotEmpty()) return (byDensity.firstOrNull { it.x!! >= dpr } ?: byDensity.last()).url
    return fallback
}

// ============================================================================
// Tables
// ============================================================================

private fun tableCell(node: ElpianNode, children: List<W>, ctx: BuildContext, header: Boolean): W {
    val t = node.text
    val base = if (header) TextStyle(fontWeight = 700) else TextStyle()
    var child: W = when {
        children.size == 1 -> children[0]
        children.size > 1 -> richText(node, mergeTextStyle(base, createTextStyle(node.style)), ctx)
            ?: column(children, mapOf("crossAxisAlignment" to "start", "mainAxisSize" to "min"))
        else -> text(t, mergeTextStyle(base, createTextStyle(node.style)), textOptionsFromStyle(node.style))
    }
    if (header && node.style?.textAlign == null) child = center(child)
    val style = withDefaults(node.style, css { padding = EdgeInsets.all(8.0) })
    val boxed = applyStyle(child, style, ApplyStyleOptions(), ctx)
    val va = jsString(node.style?.verticalAlign ?: node.props["valign"] ?: "middle")
    return w(
        "tableCell",
        mapOf(
            "colSpan" to (num(node.props["colspan"] ?: node.props["colSpan"]) ?: 1.0),
            "rowSpan" to (num(node.props["rowspan"] ?: node.props["rowSpan"]) ?: 1.0),
            "verticalAlign" to (if (va == "top") "top" else if (va == "bottom") "bottom" else "middle"),
            "width" to num(node.props["width"]),
        ),
        boxed,
    )
}

private fun tableRow(node: ElpianNode, children: List<W>): W {
    val cells = children.map { if (it.t == "tableCell") it else w("tableCell", emptyMap(), it) }
    return w("tableRow", mapOf("decorated" to (node.style?.backgroundColor != null), "background" to node.style?.backgroundColor), cells)
}

private fun htmlTable(node: ElpianNode, children: List<W>, ctx: BuildContext): W {
    val rows = ArrayList<W>()
    var caption: W? = null
    node.children.forEachIndexed { i, child ->
        val wc = children[i]
        when (child.type) {
            "caption" -> caption = wc
            // Row groups are flattened; their rows were lowered as the group's children.
            "thead", "tbody", "tfoot" -> for (r in wc.c ?: emptyList()) rows.add(r)
            "tr" -> rows.add(wc)
            // Column hints are read through cell widths.
            "colgroup", "col" -> {}
            else -> rows.add(w("tableRow", emptyMap(), listOf(w("tableCell", emptyMap(), wc))))
        }
    }
    val collapse = node.style?.borderCollapse == "collapse"
    val cap = caption
    val table = w(
        "table",
        mapOf(
            "collapse" to collapse,
            "borderSpacing" to (if (collapse) 0.0 else node.style?.borderSpacing ?: num(node.props["cellspacing"]) ?: 2.0),
            "caption" to "top",
            "fullWidth" to (node.style?.width != null || node.style?.widthFactor != null),
        ),
        if (cap != null) listOf(cap) + rows else rows,
    )
    // Flutter's Table(border: TableBorder.all()) draws grid lines; a bordered table keeps them.
    val bordered = node.props["border"] != null && node.props["border"] != "0"
    val result = if (bordered) decorated(Decoration(border = Border.all(BorderSide(1.0, Colors.black, BorderStyleName.solid))), table) else table
    return applyStyle(result, node.style, ApplyStyleOptions(), ctx)
}

// ============================================================================
// Lists, details, dialog, misc
// ============================================================================

private fun listItem(node: ElpianNode, children: List<W>, ctx: BuildContext, marker: String): W {
    val ts = createTextStyle(node.style)
    val rich = richText(node, ts ?: TextStyle(), ctx)
    val content = rich ?: when {
        children.size == 1 -> children[0]
        children.size > 1 -> column(children, mapOf("crossAxisAlignment" to "start", "mainAxisSize" to "min"))
        else -> text(node.text, ts)
    }
    val result = w("flex", mapOf("direction" to "row", "crossAxisAlignment" to "start", "mainAxisSize" to "max"), listOf(text(marker, ts), expanded(content)))
    return applyStyle(result, node.style, ApplyStyleOptions(), ctx)
}

private fun detailsElement(node: ElpianNode, children: List<W>, ctx: BuildContext): W {
    val state = ctx.engine.stateFor(ctx.elementId) { OpenState(node.props["open"] == true || node.props["open"] == "open") }
    val summaryIndex = node.children.indexOfFirst { it.type == "summary" }
    val summary = if (summaryIndex >= 0) children[summaryIndex] else text("Details", TextStyle(fontWeight = 600))
    val body = children.filterIndexed { i, _ -> i != summaryIndex }
    val header = w(
        "gesture",
        mapOf(
            "gestures" to listOf("tap"),
            "ripple" to scaleAlpha(M3.onSurface, 0.08),
            "cursor" to "pointer",
            "role" to "button",
            "onEvent" to { e: ViewEvent ->
                if (e.type == "tap") {
                    state.open = !state.open
                    dispatchEvent(ctx, "toggle", mapOf("data" to mapOf("open" to state.open)))
                    ctx.engine.host.invalidate?.invoke()
                }
            },
        ),
        padding(
            EdgeInsets.symmetric(8.0, 0.0),
            row(
                listOf(
                    expanded(summary),
                    w(
                        "animatedTransform",
                        mapOf("turns" to (if (state.open) 0.5 else 0.0), "duration" to 200.0, "curve" to "easeInOut", "alignment" to Alignment(0.0, 0.0)),
                        icon("expand_more", 24.0),
                    ),
                ),
                mapOf("mainAxisSize" to "max"),
            ),
        ),
    )
    val content = w(
        "animatedSize",
        mapOf("duration" to 200.0, "curve" to "easeInOut", "alignment" to Alignment(-1.0, -1.0)),
        if (state.open) column(body, mapOf("crossAxisAlignment" to "start", "mainAxisSize" to "min")) else SHRINK,
    )
    return applyStyle(column(listOf(header, content), mapOf("crossAxisAlignment" to "stretch", "mainAxisSize" to "min")), node.style, ApplyStyleOptions(), ctx)
}

private fun dialogElement(node: ElpianNode, children: List<W>, ctx: BuildContext): W {
    if (node.props["open"] == false || node.props["open"] == "false") return SHRINK
    val content = padding(EdgeInsets.all(24.0), column(children, mapOf("crossAxisAlignment" to "start", "mainAxisSize" to "min")))
    val card = decorated(
        Decoration(
            color = node.style?.backgroundColor ?: 0xffece6f0.toInt(),
            radius = node.style?.borderRadius ?: BorderRadius.all(28.0),
            shadows = listOf(
                BoxShadow(0x33000000, 0.0, 3.0, 5.0, -1.0),
                BoxShadow(0x24000000, 0.0, 6.0, 10.0, 0.0),
                BoxShadow(0x1f000000, 0.0, 1.0, 18.0, 0.0),
            ),
        ),
        w("constrained", mapOf("minWidth" to 280.0, "maxWidth" to 560.0), content),
    )
    val inset = padding(EdgeInsets(24.0, 40.0, 24.0, 40.0), card)
    return applyStyle(center(inset), withDefaults(node.style, CSSStyle()), ApplyStyleOptions(), ctx)
}

private fun progressElement(node: ElpianNode, meter: Boolean): W {
    val value = num(node.props["value"])
    val minV = num(node.props["min"]) ?: 0.0
    val maxV = num(node.props["max"]) ?: 1.0
    fun orOne(v: Double) = if (v == 0.0 || v.isNaN()) 1.0 else v
    val fraction: Double? = if (meter) ((value ?: 0.5) - minV) / orOne(maxV - minV) else value?.let { it / orOne(maxV) }
    var indicator: Color = node.style?.color ?: (if (meter) Colors.green else M3.primary)
    if (meter) {
        val low = num(node.props["low"])
        val high = num(node.props["high"])
        val v = value ?: 0.5
        if ((low != null && v < low) || (high != null && v > high)) indicator = node.style?.color ?: Colors.amber
    }
    return w(
        "control",
        mapOf(
            "kind" to "progress",
            "focusId" to idOf(node),
            "width" to node.style?.width,
            "view" to linkedMapOf(
                "variant" to "linear",
                "value" to fraction?.let { max(0.0, min(1.0, it)) },
                "strokeWidth" to (node.style?.height ?: 4.0),
                "colors" to linkedMapOf("indicator" to indicator, "track" to (node.style?.backgroundColor ?: 0xffeeeeee.toInt())),
            ),
        ),
    )
}

/** `<picture>`: the first `<source>` whose media matches, applied to the inner `<img>`. */
private fun pictureElement(node: ElpianNode, children: List<W>, ctx: BuildContext): W {
    val source = node.children.firstOrNull { c ->
        c.type == "source" &&
            (isTruthy(c.props["srcset"]) || isTruthy(c.props["srcSet"]) || isTruthy(c.props["src"])) &&
            (!isTruthy(c.props["media"]) || mediaMatches(jsString(c.props["media"]), CssEnvironment.viewportWidth, CssEnvironment.viewportHeight))
    }
    val imgIndex = node.children.indexOfFirst { it.type == "img" }
    if (imgIndex >= 0) {
        val img = node.children[imgIndex]
        if (source != null) {
            val srcset = jsString(source.props["srcset"] ?: source.props["srcSet"] ?: source.props["src"])
            val first = srcset.split(',')[0].trim().split(WS)[0]
            val props = LinkedHashMap(img.props)
            props["src"] = first
            props["srcset"] = if (srcset.contains(',')) srcset else img.props["srcset"]
            val swapped = ElpianNode(img.type, props, img.children, img.key, img.events, img.style)
            return applyStyle(htmlImg(swapped, emptyList(), ctx.copy(elementId = "${ctx.elementId}/img")), node.style, ApplyStyleOptions(), ctx)
        }
        return applyStyle(children[imgIndex], node.style, ApplyStyleOptions(), ctx)
    }
    val fallback = children.firstOrNull { it.t != "constrained" } ?: children.firstOrNull() ?: SHRINK
    return applyStyle(fallback, node.style, ApplyStyleOptions(), ctx)
}

private val hidden: WidgetBuilder = { _, _, _ -> SHRINK }

/** JavaScript `encodeURIComponent`. */
internal fun encodeURIComponent(s: String): String =
    URLEncoder.encode(s, "UTF-8")
        .replace("+", "%20")
        .replace("%21", "!")
        .replace("%27", "'")
        .replace("%28", "(")
        .replace("%29", ")")
        .replace("%7E", "~")

private fun none() = BorderSide(0.0, Colors.black, BorderStyleName.none)

private fun listItemWrap(child: W, marker: String): W =
    w("flex", mapOf("direction" to "row", "crossAxisAlignment" to "start", "mainAxisSize" to "max"), listOf(text(marker), expanded(child)))

private fun simpleText(node: ElpianNode, ctx: BuildContext): W = applyStyle(text(node.text, createTextStyle(node.style)), node.style, ApplyStyleOptions(), ctx)

// ============================================================================
// Registry
// ============================================================================

@Suppress("UNCHECKED_CAST")
val htmlWidgets: Map<String, WidgetBuilder> = linkedMapOf(
    "div" to { node, children, ctx -> htmlDiv(node, children, ctx) },
    "section" to { node, children, ctx -> htmlDiv(node, children, ctx) },
    "article" to { node, children, ctx -> htmlDiv(node, children, ctx) },
    "aside" to { node, children, ctx -> htmlDiv(node, children, ctx) },
    "main" to { node, children, ctx -> htmlDiv(node, children, ctx) },
    "header" to { node, children, ctx -> htmlDiv(node, children, ctx, fullWidth = true) },
    "footer" to { node, children, ctx -> htmlDiv(node, children, ctx, fullWidth = true) },
    "body" to { node, children, ctx -> htmlDiv(node, children, ctx, fullWidth = true) },
    "html" to { node, children, ctx -> htmlDiv(node, children, ctx, fullWidth = true) },

    "span" to { node, children, ctx ->
        val s = node.style
        val ts = createTextStyle(s) ?: TextStyle()
        val opts = LinkedHashMap<String, Any?>()
        s?.textOverflow?.let { opts["overflow"] = it.name }
        if (s?.whiteSpace == "nowrap") {
            opts["maxLines"] = 1.0
            opts["softWrap"] = false
        }
        if (children.isEmpty()) {
            applyStyle(text(node.text, ts, opts), s, ApplyStyleOptions(), ctx)
        } else {
            val rich = richText(node, ts, ctx, opts)
            if (rich != null) {
                applyStyle(rich, s, ApplyStyleOptions(), ctx)
            } else {
                val parts = ArrayList<W>()
                val t = node.text
                if (t.isNotEmpty()) parts.add(text(t, ts, opts))
                parts.addAll(children)
                applyStyle(w("wrap", mapOf("direction" to "horizontal", "crossAxisAlignment" to "center"), parts), s, ApplyStyleOptions(layoutHandled = true), ctx)
            }
        }
    },

    "p" to { node, children, ctx -> textWithChildren(node, children, ctx, css { margin = EdgeInsets.symmetric(8.0, 0.0) }, "wrap") },
    "h1" to heading(32.0, 16.0),
    "h2" to heading(28.0, 14.0),
    "h3" to heading(24.0, 12.0),
    "h4" to heading(20.0, 10.0),
    "h5" to heading(16.0, 8.0),
    "h6" to heading(14.0, 6.0),

    "a" to { node, children, ctx ->
        val href = jsString(node.props["href"] ?: "#")
        val style = withDefaults(node.style, css { color = Colors.blue; textDecoration = underline() })
        val ts = createTextStyle(style) ?: TextStyle()
        val rich = richText(node, ts, ctx)
        val content: W = when {
            rich != null -> rich
            children.isNotEmpty() -> {
                val parts = ArrayList<W>()
                val t = node.text
                if (t.isNotEmpty()) parts.add(text(t, ts))
                parts.addAll(children)
                w("wrap", mapOf("direction" to "horizontal", "crossAxisAlignment" to "center"), parts)
            }
            else -> text(node.text, ts)
        }
        val link = w(
            "gesture",
            mapOf(
                "gestures" to listOf("tap"),
                "cursor" to "pointer",
                "role" to "link",
                "semanticsLabel" to node.props["title"],
                "onEvent" to { e: ViewEvent ->
                    if (e.type == "tap") {
                        val target = jsString(node.props["target"] ?: "")
                        if (target == "_blank" && HTTP_LINK.containsMatchIn(href)) ctx.engine.host.openUrl?.invoke(href)
                        else openLink(ctx, href, node)
                    }
                },
            ),
            content,
        )
        applyStyle(link, style, ApplyStyleOptions(), ctx)
    },

    "button" to { node, children, ctx -> htmlButtonLike(node, children, ctx) },
    "input" to ::htmlInput,
    "textarea" to ::htmlTextarea,
    "select" to ::htmlSelect,
    "option" to { node, _, _ -> text(jsString(node.props["text"] ?: node.props["label"] ?: "")) },
    "optgroup" to { node, children, ctx ->
        val label = jsString(node.props["label"] ?: "")
        applyStyle(column(listOf(text(label, TextStyle(fontWeight = 700))) + children, mapOf("crossAxisAlignment" to "start", "mainAxisSize" to "max")), node.style, ApplyStyleOptions(), ctx)
    },
    "datalist" to hidden,
    "label" to { node, children, ctx ->
        val ts = TextStyle(fontWeight = 500).merge(createTextStyle(node.style))
        val rich = richText(node, ts, ctx)
        var result = rich ?: if (children.isNotEmpty()) row(listOf(text(node.text, ts)) + children, mapOf("mainAxisSize" to "min")) else text(node.text, ts)
        val forId = node.props["for"] ?: node.props["htmlFor"]
        if (isTruthy(forId)) {
            result = w("gesture", mapOf("gestures" to listOf("tap"), "cursor" to "pointer", "onEvent" to { _: ViewEvent -> ctx.engine.focusElement(jsString(forId)) }), result)
        }
        applyStyle(result, node.style, ApplyStyleOptions(), ctx)
    },
    "form" to { node, children, ctx ->
        applyStyle(column(children, mapOf("crossAxisAlignment" to "start", "mainAxisSize" to "max")), node.style, ApplyStyleOptions(), ctx)
    },
    "fieldset" to { node, children, ctx ->
        val box = container(
            padding = EdgeInsets.all(16.0),
            decoration = Decoration(border = Border.all(BorderSide(1.0, Colors.grey, BorderStyleName.solid)), radius = BorderRadius.all(4.0)),
            child = column(children, mapOf("crossAxisAlignment" to "start", "mainAxisSize" to "max")),
        )
        applyStyle(box, node.style, ApplyStyleOptions(), ctx)
    },
    "legend" to { node, _, ctx -> applyStyle(text(node.text, TextStyle(fontWeight = 700)), node.style, ApplyStyleOptions(), ctx) },
    "output" to { node, _, ctx ->
        val box = container(
            padding = EdgeInsets.all(8.0),
            decoration = Decoration(border = Border.all(BorderSide(1.0, Colors.grey, BorderStyleName.solid)), radius = BorderRadius.all(4.0)),
            child = text(node.text, createTextStyle(node.style)),
        )
        applyStyle(box, node.style, ApplyStyleOptions(), ctx)
    },

    "img" to ::htmlImg,
    "picture" to ::pictureElement,
    "source" to hidden,
    "track" to hidden,
    "param" to hidden,
    "map" to hidden,
    "area" to hidden,
    "video" to mediaElement("video"),
    "audio" to mediaElement("audio"),
    "iframe" to { node, _, ctx -> webContent(node, ctx, jsString(node.props["src"] ?: ""), "iframe") },
    "embed" to { node, children, ctx -> embedTyped(node, children, ctx, jsString(node.props["src"] ?: "")) },
    "object" to { node, children, ctx ->
        val data = jsString(node.props["data"] ?: "")
        // `<param>` children become query parameters of the embedded content.
        val params = node.children.filter { it.type == "param" && isTruthy(it.props["name"]) }
        var src = data
        if (params.isNotEmpty() && data.isNotEmpty() && !looksLike("image", jsString(node.props["type"] ?: ""), data)) {
            val q = params.joinToString("&") { p -> "${encodeURIComponent(jsString(p.props["name"]))}=${encodeURIComponent(jsString(p.props["value"] ?: ""))}" }
            src = data + (if (data.contains('?')) "&" else "?") + q
        }
        embedTyped(node, children, ctx, src)
    },
    "canvas" to { node, _, ctx ->
        val raw = node.props["commands"] as? List<Any?> ?: emptyList()
        val commands = raw.filter { it is Map<*, *> }.map { normalizeCommand(commandFromJson(it)) }
        val contextId = node.props["contextId"]
        if (isTruthy(contextId)) {
            applyStyle(cachedCanvas(node, ctx), node.style, ApplyStyleOptions(), ctx)
        } else {
            val result = w(
                "canvas",
                mapOf(
                    "width" to (num(node.props["width"]) ?: node.style?.width),
                    "height" to (num(node.props["height"]) ?: node.style?.height),
                    "background" to (parseColor(node.props["backgroundColor"]) ?: node.style?.backgroundColor),
                    "commands" to commands,
                    "onEvent" to { e: ViewEvent -> ctx.engine.handleGesture(ctx.elementId, node, e) },
                ),
            )
            applyStyle(result, node.style, ApplyStyleOptions(), ctx)
        }
    },

    "ul" to { node, children, ctx ->
        val items = children.mapIndexed { i, c -> if (node.children[i].type == "li") c else listItemWrap(c, "• ") }
        applyStyle(column(items, mapOf("crossAxisAlignment" to "start", "mainAxisSize" to "max")), node.style, ApplyStyleOptions(), ctx)
    },
    "ol" to { node, children, ctx ->
        val start = num(node.props["start"]) ?: 1.0
        val items = children.mapIndexed { i, c ->
            val li = node.children[i]
            val marker = "${jsString(start + i)}. "
            // Flutter renders `ol` items as Row(Text('n. '), Expanded(li)); an li's own bullet is replaced.
            if (li.type == "li") listItem(li, c.c ?: emptyList(), ctx.copy(elementId = "${ctx.elementId}/$i"), marker) else listItemWrap(c, marker)
        }
        applyStyle(column(items, mapOf("crossAxisAlignment" to "start", "mainAxisSize" to "max")), node.style, ApplyStyleOptions(), ctx)
    },
    "li" to { node, children, ctx -> listItem(node, children, ctx, "• ") },

    "table" to ::htmlTable,
    "thead" to { _, children, _ -> w("proxy", emptyMap(), children) },
    "tbody" to { _, children, _ -> w("proxy", emptyMap(), children) },
    "tfoot" to { _, children, _ -> w("proxy", emptyMap(), children) },
    "caption" to { node, children, ctx -> textWithChildren(node, children, ctx, css { textAlign = "center"; padding = EdgeInsets.symmetric(4.0, 0.0) }, "column") },
    "colgroup" to hidden,
    "col" to hidden,
    "tr" to { node, children, _ -> tableRow(node, children) },
    "td" to { node, children, ctx -> tableCell(node, children, ctx, false) },
    "th" to { node, children, ctx -> tableCell(node, children, ctx, true) },

    "strong" to { node, _, ctx -> textElement(node, ctx, css { fontWeight = 700 }) },
    "b" to { node, _, ctx -> textElement(node, ctx, css { fontWeight = 700 }) },
    "em" to { node, _, ctx -> textElement(node, ctx, css { fontStyle = "italic" }) },
    "i" to { node, _, ctx -> textElement(node, ctx, css { fontStyle = "italic" }) },
    "u" to { node, _, ctx -> textElement(node, ctx, css { textDecoration = underline() }) },
    "s" to { node, _, ctx -> textElement(node, ctx, css { textDecoration = lineThrough() }) },
    "q" to { node, _, ctx -> applyStyle(text("“${node.text}”", createTextStyle(node.style)), node.style, ApplyStyleOptions(), ctx) },
    "code" to { node, _, ctx -> replaceDefaults(node, ctx, monoStyle(0xfff5f5f5.toInt(), EdgeInsets.symmetric(2.0, 4.0)), INLINE_DEFAULTS["code"]!!) },
    "pre" to { node, _, ctx ->
        val style = node.style ?: monoStyle(0xfff5f5f5.toInt(), EdgeInsets.all(8.0))
        val ts = createTextStyle(style) ?: TextStyle()
        val body = w("scroll", mapOf("axis" to "horizontal"), text(node.text, TextStyle(fontFamily = "monospace").merge(ts), mapOf("softWrap" to false)))
        applyStyle(body, style, ApplyStyleOptions(), ctx)
    },
    "kbd" to { node, _, ctx -> replaceDefaults(node, ctx, monoStyle(0xffeeeeee.toInt(), EdgeInsets.all(4.0)) { borderRadius = BorderRadius.all(3.0) }, INLINE_DEFAULTS["kbd"]!!) },
    "samp" to { node, _, ctx -> replaceDefaults(node, ctx, css { fontFamily = "monospace" }, INLINE_DEFAULTS["samp"]!!) },
    "var" to { node, _, ctx -> replaceDefaults(node, ctx, css { fontStyle = "italic" }, INLINE_DEFAULTS["var"]!!) },
    "cite" to { node, _, ctx -> replaceDefaults(node, ctx, css { fontStyle = "italic" }, INLINE_DEFAULTS["cite"]!!) },
    "mark" to { node, _, ctx -> replaceDefaults(node, ctx, css { backgroundColor = 0xffffff00.toInt(); padding = EdgeInsets.symmetric(2.0, 4.0) }, INLINE_DEFAULTS["mark"]!!) },
    "del" to { node, _, ctx -> replaceDefaults(node, ctx, css { textDecoration = lineThrough() }, INLINE_DEFAULTS["del"]!!) },
    "ins" to { node, _, ctx -> replaceDefaults(node, ctx, css { textDecoration = underline() }, INLINE_DEFAULTS["ins"]!!) },
    "small" to { node, _, ctx -> replaceDefaults(node, ctx, css { fontSize = 12.0 }, INLINE_DEFAULTS["small"]!!) },
    "sub" to { node, _, _ ->
        val style = node.style ?: css { fontSize = 10.0 }
        val ts = mergeTextStyle(TextStyle(baselineShift = 3.0), createTextStyle(style))
        w("padding", mapOf("padding" to EdgeInsets(4.0, 0.0, 0.0, 0.0)), text(node.text, ts))
    },
    "sup" to { node, _, _ ->
        val style = node.style ?: css { fontSize = 10.0 }
        val ts = mergeTextStyle(TextStyle(baselineShift = -6.0), createTextStyle(style))
        w("padding", mapOf("padding" to EdgeInsets(0.0, 0.0, 4.0, 0.0)), text(node.text, ts))
    },
    "abbr" to { node, _, ctx ->
        val result = w(
            "gesture",
            mapOf("gestures" to listOf("longpress", "hover"), "tooltip" to jsString(node.props["title"] ?: ""), "onEvent" to { _: ViewEvent -> }),
            text(node.text, TextStyle(decoration = TextDecorationBits.underline).merge(createTextStyle(node.style))),
        )
        applyStyle(result, node.style, ApplyStyleOptions(), ctx)
    },
    "time" to { node, _, ctx -> simpleText(node, ctx) },
    "data" to { node, _, ctx -> simpleText(node, ctx) },
    "blockquote" to { node, children, ctx ->
        val child = when {
            children.size == 1 -> children[0]
            children.size > 1 -> column(children, mapOf("crossAxisAlignment" to "start", "mainAxisSize" to "min"))
            else -> text(node.text, createTextStyle(node.style))
        }
        val box = container(
            padding = EdgeInsets.all(16.0),
            decoration = Decoration(border = Border(none(), none(), none(), BorderSide(4.0, Colors.grey, BorderStyleName.solid))),
            child = child,
        )
        val style = node.style ?: css { padding = EdgeInsets.all(16.0); margin = EdgeInsets.symmetric(8.0, 0.0); borderColor = Colors.grey; borderWidth = 4.0 }
        val outer = style.copy().also {
            it.padding = null
            it.border = null
            it.borderColor = null
            it.borderWidth = null
        }
        applyStyle(box, outer, ApplyStyleOptions(), ctx)
    },
    "hr" to { node, _, ctx -> applyStyle(flutterWidgets.getValue("Divider")(node.copy(style = null), emptyList(), ctx), node.style, ApplyStyleOptions(), ctx) },
    "br" to { _, _, _ -> sizedBox(null, 16.0) },
    "figure" to { node, children, ctx ->
        applyStyle(column(children, mapOf("crossAxisAlignment" to "start", "mainAxisSize" to "min")), node.style, ApplyStyleOptions(), ctx)
    },
    "figcaption" to { node, _, ctx ->
        replaceDefaults(node, ctx, css { fontStyle = "italic"; color = Colors.grey; fontSize = 14.0 }, TextStyle(italic = true, color = Colors.grey, fontSize = 14.0))
    },
    "details" to ::detailsElement,
    "summary" to { node, children, ctx -> textWithChildren(node, children, ctx, css { fontWeight = 700 }, "wrap") },
    "dialog" to ::dialogElement,
    "progress" to { node, _, _ -> progressElement(node, false) },
    "meter" to { node, _, _ -> progressElement(node, true) },
    "nav" to { node, children, ctx ->
        val s = node.style
        val result = w(
            "flex",
            mapOf(
                "direction" to "row",
                "mainAxisAlignment" to mainOf(s?.justifyContent ?: "space-around"),
                "crossAxisAlignment" to crossOf(s?.alignItems),
                "mainAxisSize" to "max",
                "gap" to (s?.gap ?: 0.0),
                "shrink" to true,
            ),
            children,
        )
        applyStyle(result, s, ApplyStyleOptions(layoutHandled = true), ctx)
    },
)
