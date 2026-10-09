package dev.elpian.core.widgets

import dev.elpian.core.css.Border
import dev.elpian.core.css.BorderRadius
import dev.elpian.core.css.BorderSide
import dev.elpian.core.css.BorderStyleName
import dev.elpian.core.css.CSSParser
import dev.elpian.core.css.CSSStyle
import dev.elpian.core.css.Color
import dev.elpian.core.css.EdgeInsets
import dev.elpian.core.css.Alignment
import dev.elpian.core.css.scaleAlpha
import dev.elpian.core.css.withOpacity
import dev.elpian.core.godot.launchDetached
import dev.elpian.core.model.ElpianNode
import dev.elpian.core.render.TextStyle
import dev.elpian.core.render.ViewEvent
import dev.elpian.core.render.W
import dev.elpian.core.render.layout.crossAxisAlignmentFromCss
import dev.elpian.core.render.layout.mainAxisAlignmentFromCss
import dev.elpian.core.render.paint.Decoration
import dev.elpian.core.render.toSpec
import dev.elpian.core.render.w
import dev.elpian.core.util.jsString
import dev.elpian.core.util.toNumber
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToLong

/**
 * Server-driven navigation widgets (widgets/nextjs.ts) — ports of
 * `NextjsBridge`'s `NextjsLink` (`next-link`) and `NextjsForm`
 * (`nextjs-form`) builders (flutter/lib/src/integrations/nextjs_bridge.dart).
 * Navigation and form submission go through the engine host
 * (`EngineHost.navigate` / `EngineHost.submitForm`), which the Next.js session
 * implements.
 */

private const val GOLD: Color = 0xffd6b36a.toInt()
private const val FIELD_FILL: Color = 0xff0a1626.toInt()
private const val FIELD_BORDER: Color = 0xff1c3450.toInt()
private const val TEXT: Color = 0xfff7eedc.toInt()
private const val HINT: Color = 0xff6e8394.toInt()
private const val INK: Color = 0xff06122a.toInt()
private const val ERROR: Color = 0xffc0492f.toInt()

// ============================================================================
// NextjsLink
// ============================================================================

@Suppress("UNCHECKED_CAST")
private fun linkChildStyle(child: ElpianNode): CSSStyle? {
    child.style?.let { return it }
    val inline = child.props["style"]
    if (inline is Map<*, *>) return CSSParser.parse(inline as Map<String, Any?>)
    return null
}

private fun withGaps(children: List<W>, gap: Double, horizontal: Boolean): List<W> {
    if (gap <= 0 || children.size <= 1) return children
    val out = ArrayList<W>()
    children.forEachIndexed { i, c ->
        out.add(c)
        if (i < children.size - 1) out.add(sizedBox(if (horizontal) gap else 0.0, if (horizontal) 0.0 else gap))
    }
    return out
}

private fun linkFlow(node: ElpianNode, flow: List<W>): W {
    val s = node.style
    val isColumn = s?.flexDirection == "column" || s?.flexDirection == "column-reverse"
    val children = withGaps(flow, s?.gap ?: 0.0, !isColumn)
    val opts = mapOf(
        "mainAxisSize" to "min",
        "mainAxisAlignment" to mainAxisAlignmentFromCss(s?.justifyContent),
        "crossAxisAlignment" to (if (s?.alignItems == null) "center" else crossAxisAlignmentFromCss(s.alignItems)),
    )
    return if (isColumn) column(children, opts) else row(children, opts)
}

private fun layoutLinkChildren(node: ElpianNode, children: List<W>): W {
    val aligned = node.children.size == children.size
    val flow = ArrayList<W>()
    val overlays = ArrayList<W>()
    children.forEachIndexed { i, child ->
        val cs = if (aligned) linkChildStyle(node.children[i]) else null
        if (cs != null && (cs.position == "absolute" || cs.position == "fixed")) {
            overlays.add(w("positioned", mapOf("top" to cs.top, "left" to cs.left, "right" to cs.right, "bottom" to cs.bottom), child))
        } else flow.add(child)
    }
    val base = if (flow.isEmpty()) SHRINK else if (flow.size == 1) flow[0] else linkFlow(node, flow)
    if (overlays.isEmpty()) return base
    // Clip.none: badges poke past the button's rounded corners.
    return w("stack", mapOf("fit" to "loose", "clip" to false), listOf(base) + overlays)
}

private val nextjsLink: WidgetBuilder = { node, children, ctx ->
    val href = node.props["href"]?.let { jsString(it) }
    val replace = node.props["replace"] == true
    val label = node.props["text"]?.let { jsString(it) } ?: href ?: "Navigate"
    val s = node.style
    val ariaLabel = node.props["ariaLabel"]?.let { jsString(it) }
    val isButtonLike = s != null && (s.backgroundColor != null || s.gradient != null || s.border != null || s.borderColor != null || s.padding != null)

    val content = if (children.isNotEmpty()) {
        layoutLinkChildren(node, children)
    } else {
        text(
            label,
            TextStyle(
                color = s?.color ?: GOLD,
                fontSize = s?.fontSize,
                fontWeight = s?.fontWeight ?: (if (isButtonLike) 700 else null),
                letterSpacing = s?.letterSpacing,
            ),
            mapOf("align" to (s?.textAlign ?: (if (isButtonLike) "center" else "start"))),
        )
    }

    val styled = applyStyle(content, s, ApplyStyleOptions(applyFlex = false), ctx)
    var tappable = w(
        "gesture",
        mapOf(
            "gestures" to (if (href != null) listOf("tap") else emptyList()),
            "opaque" to true,
            "cursor" to (if (href != null) "pointer" else "default"),
            "role" to (if (!ariaLabel.isNullOrEmpty()) "button" else "link"),
            "semanticsLabel" to ariaLabel,
            "onEvent" to { e: ViewEvent -> if (e.type == "tap" && href != null) ctx.engine.host.navigate?.invoke(href, replace) },
        ),
        styled,
    )
    val flex = s?.flex ?: s?.flexGrow
    if (flex != null) tappable = w("flexible", mapOf("flex" to flex, "fit" to "tight"), sizedBox(Double.POSITIVE_INFINITY, null, tappable))
    tappable
}

// ============================================================================
// NextjsForm
// ============================================================================

private data class FieldOption(val value: String, val label: String)

private fun optionsOf(f: Map<String, Any?>): List<FieldOption> {
    val out = ArrayList<FieldOption>()
    val options = f["options"]
    if (options is List<*>) {
        for (o in options) {
            if (o is Map<*, *>) {
                val v = jsString(o["value"] ?: o["label"] ?: "")
                out.add(FieldOption(v, jsString(o["label"] ?: v)))
            } else if (o != null) out.add(FieldOption(jsString(o), jsString(o)))
        }
    }
    if (out.isEmpty()) {
        for (part in jsString(f["placeholder"] ?: "").split(',')) {
            val v = part.trim()
            if (v.isNotEmpty()) out.add(FieldOption(v, v))
        }
    }
    return out
}

private fun numProp(f: Map<String, Any?>, key: String, fallback: Double): Double = toNumber(f[key]) ?: fallback

/** `Math.round` (half up) then `String`, or the number as JavaScript prints it. */
private fun fmtRange(v: Double): String {
    val r = Math.floor(v + 0.5)
    return if (v == r) jsString(r) else jsString(v)
}

private class FormState(var values: Map<String, String>, var busy: Boolean, var error: String?)

private fun fieldBox(child: W, pad: EdgeInsets = EdgeInsets.symmetric(4.0, 8.0)): W =
    container(
        child = child,
        padding = pad,
        decoration = Decoration(color = FIELD_FILL, radius = BorderRadius.all(10.0), border = Border.all(BorderSide(1.0, FIELD_BORDER, BorderStyleName.solid))),
    )

@Suppress("UNCHECKED_CAST")
private val nextjsForm: WidgetBuilder = { node, _, ctx ->
    val action = jsString(node.props["action"] ?: "")
    val submitLabel = jsString(node.props["submitLabel"] ?: "Submit")
    val fields: List<Map<String, Any?>> = (node.props["fields"] as? List<*>)?.filterIsInstance<Map<*, *>>()?.map { it as Map<String, Any?> } ?: emptyList()

    val state = ctx.engine.stateFor(ctx.elementId) {
        val values = LinkedHashMap<String, String>()
        for (f in fields) {
            val name = jsString(f["name"] ?: "")
            if (name.isEmpty()) continue
            val type = jsString(f["type"] ?: "")
            val value = f["value"]?.let { jsString(it) } ?: ""
            when (type) {
                "select" -> {
                    val options = optionsOf(f)
                    values[name] = if (options.any { it.value == value }) value else options.firstOrNull()?.value ?: value
                }
                "checkbox" -> values[name] = if (value == "true" || value == "on") "true" else "false"
                "range" -> {
                    val minV = numProp(f, "min", 0.0)
                    val maxV = numProp(f, "max", 100.0)
                    val parsed = toNumber(value)
                    values[name] = fmtRange(if (maxV > minV) min(maxV, max(minV, parsed ?: minV)) else minV)
                }
                else -> values[name] = value // text-like and hidden
            }
        }
        FormState(values, false, null)
    }

    fun update(values: Map<String, String>? = null, busy: Boolean? = null, error: Any? = Unit) {
        if (values != null) state.values = values
        if (busy != null) state.busy = busy
        if (error != Unit) state.error = error as String?
        ctx.engine.host.invalidate?.invoke()
    }

    val submit: () -> Unit = submit@{
        val handler = ctx.engine.host.submitForm
        if (handler == null || state.busy) return@submit
        update(busy = true, error = null)
        launchDetached {
            val error: String? = try {
                handler(action, LinkedHashMap<String, Any?>(state.values))
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Throwable) {
                "Request failed: $e"
            }
            update(busy = false, error = error)
        }
    }

    fun labelOf(label: String) = padding(EdgeInsets(bottom = 4.0), text(label, TextStyle(color = HINT, fontSize = 11.0, fontWeight = 600)))
    val items = ArrayList<W>()

    for (f in fields) {
        val name = jsString(f["name"] ?: "")
        if (name.isEmpty()) continue
        val type = jsString(f["type"] ?: "")
        if (type == "hidden") continue
        val label = f["label"]?.let { jsString(it) }
        val control: W

        if (type == "select") {
            val options = optionsOf(f)
            val current = if (options.any { it.value == state.values[name] }) state.values[name] else options.firstOrNull()?.value
            val ts = TextStyle(color = TEXT, fontSize = 14.0)
            control = container(
                padding = EdgeInsets.symmetric(4.0, 10.0),
                decoration = Decoration(color = FIELD_FILL, radius = BorderRadius.all(10.0), border = Border.all(BorderSide(1.0, FIELD_BORDER, BorderStyleName.solid))),
                child = w(
                    "control",
                    mapOf(
                        "kind" to "select",
                        "view" to linkedMapOf(
                            "value" to current,
                            "options" to options.map { linkedMapOf("value" to it.value, "label" to it.label, "group" to null, "disabled" to false) },
                            "placeholder" to jsString(f["placeholder"] ?: name),
                            "enabled" to !state.busy,
                            "textStyle" to ts.toSpec(),
                            "hintStyle" to ts.copy(color = HINT).toSpec(),
                            "colors" to linkedMapOf("text" to TEXT, "fill" to FIELD_FILL, "icon" to GOLD, "menu" to FIELD_FILL, "hint" to HINT),
                        ),
                        "onEvent" to { e: ViewEvent ->
                            if (e.type == "change") update(values = state.values + (name to (e.value?.let { jsString(it) } ?: current ?: "")))
                        },
                    ),
                ),
            )
        } else if (type == "checkbox") {
            val checked = state.values[name] == "true"
            val toggle = { v: Boolean -> update(values = state.values + (name to (if (v) "true" else "false"))) }
            control = w(
                "gesture",
                mapOf(
                    "gestures" to (if (state.busy) emptyList() else listOf("tap")),
                    "ripple" to scaleAlpha(GOLD, 0.12),
                    "rippleRadius" to 10.0,
                    "cursor" to (if (state.busy) "default" else "pointer"),
                    "onEvent" to { e: ViewEvent -> if (e.type == "tap") toggle(!checked) },
                ),
                fieldBox(
                    row(
                        listOf(
                            w(
                                "control",
                                mapOf(
                                    "kind" to "checkbox",
                                    "view" to linkedMapOf("checked" to checked, "enabled" to !state.busy, "colors" to linkedMapOf("fill" to GOLD, "check" to INK, "border" to HINT)),
                                    "controlled" to true,
                                    "onEvent" to { e: ViewEvent -> if (e.type == "change") toggle(e.value == true) },
                                ),
                            ),
                            w("flexible", mapOf("flex" to 1.0, "fit" to "loose"), text(jsString(f["placeholder"] ?: label ?: name), TextStyle(color = TEXT, fontSize = 13.0))),
                        ),
                        mapOf("mainAxisSize" to "min"),
                    ),
                ),
            )
        } else if (type == "range") {
            val minV = numProp(f, "min", 0.0)
            val maxV = numProp(f, "max", 100.0)
            val step = numProp(f, "step", 1.0)
            val hasRoom = maxV > minV
            val current = if (hasRoom) min(maxV, max(minV, toNumber(state.values[name]) ?: minV)) else minV
            val slider = if (hasRoom) {
                w(
                    "control",
                    mapOf(
                        "kind" to "slider",
                        "view" to linkedMapOf(
                            "value" to current,
                            "min" to minV,
                            "max" to maxV,
                            "step" to (if (step > 0) step else null),
                            "enabled" to !state.busy,
                            "trackHeight" to 3.0,
                            "colors" to linkedMapOf("active" to GOLD, "inactive" to FIELD_BORDER, "thumb" to GOLD, "overlay" to withOpacity(GOLD, 0.15)),
                        ),
                        "controlled" to true,
                        "onEvent" to { e: ViewEvent ->
                            if (e.type == "change" || e.type == "input") update(values = state.values + (name to fmtRange(jsNumber(e.value))))
                        },
                    ),
                )
            } else {
                padding(EdgeInsets.symmetric(8.0, 0.0), text(jsString(f["placeholder"] ?: "No range available"), TextStyle(color = HINT, fontSize = 13.0)))
            }
            control = fieldBox(
                row(listOf(expanded(slider), sizedBox(6.0, null), text(state.values[name] ?: fmtRange(current), TextStyle(color = GOLD, fontSize = 13.0, fontWeight = 700)))),
                EdgeInsets.symmetric(6.0, 10.0),
            )
        } else {
            val multiline = type == "textarea"
            val ts = TextStyle(color = TEXT, fontSize = 14.0, height = 1.3)
            val view = linkedMapOf<String, Any?>(
                "value" to (state.values[name] ?: ""),
                "placeholder" to jsString(f["placeholder"] ?: name),
                "inputType" to (if (type == "password") "password" else if (type == "number") "number" else "text"),
            )
            if (type == "number") view["allowedPattern"] = "[0-9.\\-]"
            view["multiline"] = multiline
            view["enabled"] = true
            view["variant"] = "outline"
            view["textStyle"] = ts.toSpec()
            view["hintStyle"] = ts.copy(color = HINT).toSpec()
            view["contentPadding"] = listOf(12.0, 12.0, 12.0, 12.0)
            view["colors"] = linkedMapOf(
                "text" to TEXT,
                "hint" to HINT,
                "fill" to FIELD_FILL,
                "border" to FIELD_BORDER,
                "focusedBorder" to GOLD,
                "focusedBorderWidth" to 1.5,
                "cursor" to GOLD,
                "radius" to 10.0,
            )
            control = w(
                "control",
                mapOf(
                    "kind" to "textInput",
                    "lines" to (if (multiline) 3.0 else 1.0),
                    "maxLines" to (if (multiline) 4.0 else 1.0),
                    "padding" to listOf(12.0, 12.0, 12.0, 12.0),
                    "lineHeight" to 14 * 1.3,
                    "view" to view,
                    "onEvent" to { e: ViewEvent ->
                        if (e.type == "input" || e.type == "change") state.values = state.values + (name to (e.value?.let { jsString(it) } ?: ""))
                        else if (e.type == "submit" && !multiline && !state.busy) submit()
                    },
                ),
            )
        }

        val col = ArrayList<W>()
        if (!label.isNullOrEmpty()) col.add(labelOf(label))
        col.add(control)
        items.add(padding(EdgeInsets(bottom = 12.0), column(col, mapOf("crossAxisAlignment" to "start", "mainAxisSize" to "min"))))
    }

    state.error?.let { if (it.isNotEmpty()) items.add(padding(EdgeInsets(bottom = 8.0), text(it, TextStyle(color = ERROR, fontSize = 13.0)))) }

    val buttonChild = if (state.busy) {
        sizedBox(
            16.0,
            16.0,
            w("control", mapOf("kind" to "progress", "view" to linkedMapOf("variant" to "circular", "value" to null, "strokeWidth" to 2.0, "colors" to linkedMapOf("indicator" to INK, "track" to null)))),
        )
    } else {
        text(submitLabel, TextStyle(fontWeight = 700, letterSpacing = 0.3, color = INK, fontSize = 14.0))
    }
    val button = w(
        "gesture",
        mapOf(
            "gestures" to (if (state.busy) emptyList() else listOf("tap")),
            "ripple" to scaleAlpha(INK, 0.12),
            "cursor" to (if (state.busy) "default" else "pointer"),
            "role" to "button",
            "semanticsLabel" to submitLabel,
            "onEvent" to { e: ViewEvent -> if (e.type == "tap") submit() },
        ),
        container(
            padding = EdgeInsets.symmetric(14.0, 16.0),
            alignment = Alignment(0.0, 0.0),
            decoration = Decoration(color = if (state.busy) withOpacity(GOLD, 0.5) else GOLD, radius = BorderRadius.all(10.0), shadows = emptyList()),
            child = buttonChild,
        ),
    )
    items.add(sizedBox(Double.POSITIVE_INFINITY, null, w("constrained", mapOf("minHeight" to 40.0), button)))
    column(items, mapOf("mainAxisSize" to "min"))
}

val nextjsWidgets: Map<String, WidgetBuilder> = linkedMapOf(
    "NextjsLink" to nextjsLink,
    "next-link" to nextjsLink,
    "NextjsForm" to nextjsForm,
    "nextjs-form" to nextjsForm,
)
