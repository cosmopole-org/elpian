package dev.elpian.core.a2ui

import dev.elpian.core.events.ElpianEvent
import dev.elpian.core.session.encodeURIComponent
import dev.elpian.core.util.JsonMap
import dev.elpian.core.util.jsString
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt

/**
 * Lowering (a2ui/lowering.ts): an A2UI surface → an Elpian node tree (the same
 * JSON a mini app renders), built from Elpian's existing widgets with
 * Material 3 visuals, so agent UI and static Elpian UI mix freely.
 *
 * | A2UI           | Elpian nodes                                                   |
 * |----------------|----------------------------------------------------------------|
 * | Text           | `Text` (typography per variant); Markdown → `p` + inline spans  |
 * | Image          | `Image` sized per variant (`ClipRRect` for avatars)             |
 * | Icon           | `Icon` (Material name) or an SVG-path `Image`                  |
 * | Video / Audio  | `video` / `audio` with controls                                |
 * | Row / Column   | `Row` / `Column` (justify → justifyContent, align → alignItems; `weight` → `Expanded`) |
 * | List           | `ListView` (vertical or horizontal scroll)                     |
 * | Card           | `Card`                                                         |
 * | Tabs           | tab header row + the selected child (state kept per surface)    |
 * | Modal          | the trigger; when open, a barrier + dialog over the surface     |
 * | Divider        | `Divider` / a vertical rule                                    |
 * | Button         | `Button` (default / primary / borderless; disabled by checks)   |
 * | TextField      | label + `TextField` (+ check error text)                       |
 * | CheckBox       | `Checkbox` + label                                              |
 * | ChoicePicker   | radio / checkbox list or chips, optional filter field          |
 * | Slider         | label + value + `Slider`                                        |
 * | DateTimeInput  | label + date / time / datetime `TextField`                     |
 *
 * Interactions are closures `(ElpianEvent) -> Unit` in the nodes' `events`
 * (Elpian calls function handlers directly); they write the data model
 * (two-way binding), dispatch actions, or change UI-local state through
 * [LoweringHooks]. The output is plain node JSON for any Elpian engine.
 */
interface LoweringHooks {
    /** Two-way binding: write [value] at the absolute [path]. */
    fun write(surfaceId: String, path: String, value: Any?)

    /** An interactive component fired its `action` (resolved in [scope]). */
    fun action(surfaceId: String, componentId: String, action: Any?, scope: String)

    /** UI-local state changed (tab, modal, filter…): render again. */
    fun invalidate()

    /** Evaluation problems (unknown function, bad template…). */
    fun error(error: A2UIError) {}
}

/** UI-local state that survives re-lowering (selected tab, open modal, filter text, touched fields). */
class A2UIUiState {
    private val values = LinkedHashMap<String, Any?>()

    @Suppress("UNCHECKED_CAST")
    fun <T> get(key: String, fallback: T): T = if (values.containsKey(key)) values[key] as T else fallback

    fun set(key: String, value: Any?) {
        values[key] = value
    }

    /** Drop the state of one surface (after `deleteSurface`). */
    fun clearSurface(prefix: String) {
        for (k in values.keys.toList()) if (k.startsWith(prefix)) values.remove(k)
    }
}

class LoweringOptions(
    val hooks: LoweringHooks,
    val state: A2UIUiState,
    /** Prefix for node keys (element ids) — unique per embedding widget. */
    val keyPrefix: String? = null,
    /** Show `agentDisplayName` / `iconUrl` above the surface (default true). */
    val showAttribution: Boolean = true,
    /** Lower every deferred subtree too — closed modals, hidden tabs (previews, tests). */
    val expandAll: Boolean = false,
)

class LoweringPlaceholder(val id: String, val reason: String)

class LoweringResult(
    val node: JsonMap,
    /** `componentId@scope` of every component lowered. */
    val lowered: List<String>,
    /** Components rendered as an error placeholder (unknown type, cycle, depth). */
    val placeholders: List<LoweringPlaceholder>,
)

/** The surface palette: Material 3 baseline with the theme's primary color. */
data class A2UIPalette(
    val primary: String,
    val onPrimary: String,
    val primaryContainer: String,
    val onSurface: String,
    val onSurfaceVariant: String,
    val outline: String,
    val outlineVariant: String,
    val surfaceContainer: String,
    val surfaceContainerHigh: String,
    val error: String,
)

private val HEX6 = Regex("^#[0-9a-fA-F]{6}$")

fun paletteFor(theme: Map<String, Any?>): A2UIPalette {
    val pc = theme["primaryColor"]
    val primary = if (pc is String && HEX6.matches(pc)) pc.uppercase() else "#6750A4"
    return A2UIPalette(
        primary = primary,
        onPrimary = if (luminance(primary) > 0.5) "#1D1B20" else "#FFFFFF",
        primaryContainer = mix(primary, "#FFFFFF", 0.82),
        onSurface = "#1D1B20",
        onSurfaceVariant = "#49454F",
        outline = "#79747E",
        outlineVariant = "#CAC4D0",
        surfaceContainer = "#F7F2FA",
        surfaceContainerHigh = "#ECE6F0",
        error = "#B3261E",
    )
}

private fun rgb(hex: String): IntArray {
    val n = hex.substring(1).toInt(16)
    return intArrayOf((n shr 16) and 255, (n shr 8) and 255, n and 255)
}

private fun luminance(hex: String): Double {
    val c = rgb(hex).map {
        val s = it / 255.0
        if (s <= 0.03928) s / 12.92 else ((s + 0.055) / 1.055).pow(2.4)
    }
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
}

/** JavaScript `Math.round`. */
private fun jsRound(x: Double): Long = Math.floor(x + 0.5).toLong()

private fun mix(a: String, b: String, t: Double): String {
    val x = rgb(a)
    val y = rgb(b)
    return "#" + (0..2).joinToString("") { i -> jsRound(x[i] + (y[i] - x[i]) * t).toString(16).padStart(2, '0') }.uppercase()
}

/** Leaf-margin strategy: visual leaves carry the spacing, containers none. */
private const val LEAF_MARGIN = 4.0
private const val MAX_DEPTH = 64

private val TEXT_VARIANTS: Map<String, Map<String, Any?>> = mapOf(
    "h1" to mapOf("fontSize" to 40.0, "fontWeight" to 600.0, "lineHeight" to 1.2),
    "h2" to mapOf("fontSize" to 32.0, "fontWeight" to 600.0, "lineHeight" to 1.25),
    "h3" to mapOf("fontSize" to 28.0, "fontWeight" to 600.0, "lineHeight" to 1.28),
    "h4" to mapOf("fontSize" to 24.0, "fontWeight" to 600.0, "lineHeight" to 1.33),
    "h5" to mapOf("fontSize" to 20.0, "fontWeight" to 600.0, "lineHeight" to 1.4),
    "caption" to mapOf("fontSize" to 13.0, "lineHeight" to 1.35),
    "body" to mapOf("fontSize" to 16.0, "lineHeight" to 1.5),
)

/** A2UI icon names → Material icon names where the snake_case form differs. */
private val ICON_ALIASES: Map<String, String> = mapOf(
    "favoriteOff" to "favorite_border",
    "starOff" to "star_border",
    "play" to "play_arrow",
    "rewind" to "fast_rewind",
)

private val CAMEL = Regex("([a-z0-9])([A-Z])")

/** The Material icon name for an A2UI icon name (`accountCircle` → `account_circle`). */
fun materialIconName(name: String): String = ICON_ALIASES[name] ?: name.replace(CAMEL, "$1_$2").lowercase()

private val JUSTIFY: Map<String, String> = mapOf(
    "start" to "flex-start",
    "center" to "center",
    "end" to "flex-end",
    "spaceBetween" to "space-between",
    "spaceAround" to "space-around",
    "spaceEvenly" to "space-evenly",
    "stretch" to "flex-start",
)

private val ALIGN: Map<String, String> = mapOf("start" to "flex-start", "center" to "center", "end" to "flex-end", "stretch" to "stretch")

private val ROW_SHRINKS = setOf("Text", "Column", "Row", "List", "Card", "TextField", "ChoicePicker", "Slider", "DateTimeInput")

private data class LCtx(
    val dc: DataContext,
    val scope: String,
    val depth: Int,
    val stack: List<String>,
    /** The A2UI type of the parent (for `weight`). */
    val parent: String?,
    /** Inside a button: no leaf margins, icons take the button's content color. */
    val contentColor: String?,
    /** Modal trigger: a press opens the modal instead of firing the action. */
    val interceptPress: (() -> Unit)?,
)

typealias EventHandler = (ElpianEvent) -> Unit

private fun el(type: String, props: JsonMap = LinkedHashMap(), children: List<JsonMap> = emptyList(), key: String? = null, events: Map<String, EventHandler>? = null): JsonMap {
    val node: JsonMap = linkedMapOf("type" to type, "props" to props, "children" to children.toMutableList())
    if (!key.isNullOrEmpty()) node["key"] = key
    if (!events.isNullOrEmpty()) node["events"] = LinkedHashMap<String, Any?>(events)
    return node
}

private fun style(vararg pairs: Pair<String, Any?>): JsonMap = linkedMapOf(*pairs)

private fun props(vararg pairs: Pair<String, Any?>): JsonMap = linkedMapOf(*pairs)

private fun textNode(text: String, style: Map<String, Any?> = emptyMap(), key: String? = null): JsonMap =
    el("Text", props("text" to text, "style" to LinkedHashMap(style)), key = key)

/** Stop an internal event from bubbling into the embedding app's handlers. */
private fun handled(e: ElpianEvent?) {
    e?.propagationStopped = true
}

@Suppress("UNCHECKED_CAST")
private fun JsonMap.propsOf(): JsonMap = this["props"] as JsonMap

@Suppress("UNCHECKED_CAST")
private fun JsonMap.childrenOf(): List<JsonMap> = this["children"] as List<JsonMap>

/** The text of an input event's value (`String(e.value ?? '')`). */
private fun eventText(e: ElpianEvent?): String = e?.value?.let { if (it is String) it else jsString(it) } ?: ""

/** Lower [surface] to an Elpian node tree. */
fun lowerSurface(surface: A2UISurfaceModel, options: LoweringOptions): LoweringResult = Lowerer(surface, options).run()

private class Lowerer(val surface: A2UISurfaceModel, val options: LoweringOptions) {
    val palette: A2UIPalette = paletteFor(surface.theme)
    val prefix: String = "${options.keyPrefix ?: "a2ui"}:${surface.id}"
    val lowered = ArrayList<String>()
    val placeholders = ArrayList<LoweringPlaceholder>()
    val overlays = ArrayList<JsonMap>()

    val hooks: LoweringHooks get() = options.hooks

    private fun stateKey(key: String, what: String): String = "$key#$what"

    fun run(): LoweringResult {
        val parts = ArrayList<JsonMap>()
        val header = if (!options.showAttribution) null else attribution()
        if (header != null) parts.add(header)
        if (surface.isReady) {
            val ctx = LCtx(surface.context("/"), "/", 0, emptyList(), null, null, null)
            parts.add(child("root", ctx))
        }
        var node = el("Column", props("style" to style("alignItems" to "stretch", "justifyContent" to "flex-start", "color" to palette.onSurface)), parts, key = prefix)
        if (overlays.isNotEmpty()) {
            node = el("ConstrainedBox", props("style" to style("minHeight" to 420.0)), listOf(el("Stack", props("style" to style("alignment" to "top left")), listOf(node) + overlays)))
        }
        return LoweringResult(node, lowered, placeholders)
    }

    private fun attribution(): JsonMap? {
        val theme = surface.theme
        val name = theme["agentDisplayName"] as? String ?: ""
        val iconUrl = theme["iconUrl"]
        val icon = if (iconUrl is String && Regex("^https?:|^data:image/", RegexOption.IGNORE_CASE).containsMatchIn(iconUrl)) iconUrl else ""
        if (name.isEmpty() && icon.isEmpty()) return null
        val row = ArrayList<JsonMap>()
        if (icon.isNotEmpty()) {
            row.add(el("ClipRRect", props("style" to style("borderRadius" to 10.0)), listOf(el("Image", props("src" to icon, "fit" to "cover", "alt" to name, "style" to style("width" to 20.0, "height" to 20.0))))))
        }
        if (name.isNotEmpty()) row.add(textNode(name, style("fontSize" to 12.0, "fontWeight" to 500.0, "color" to palette.onSurfaceVariant, "margin" to "0 0 0 8")))
        return el("Row", props("style" to style("alignItems" to "center", "padding" to "4 4 8 4")), row, key = "$prefix/attribution")
    }

    private fun keyFor(id: String, ctx: LCtx): String = if (ctx.scope == "/") "$prefix:$id" else "$prefix:$id@${ctx.scope}"

    private val report: (A2UIError) -> Unit = { e -> hooks.error(A2UIError(e.category, e.message, A2UIErrorDetails(surface.id, e.path))) }

    private fun <T> eval(ctx: LCtx, fallback: T, fn: () -> T): T = ctx.dc.safe(fallback, report, fn)

    private fun str(ctx: LCtx, v: Any?): String = if (v == null) "" else eval(ctx, "") { ctx.dc.string(v) }

    private fun placeholder(id: String, reason: String, key: String): JsonMap {
        placeholders.add(LoweringPlaceholder(id, reason))
        return el(
            "Container",
            props("style" to style("padding" to 8.0, "margin" to LEAF_MARGIN, "backgroundColor" to "#FDECEA", "borderRadius" to 8.0)),
            listOf(textNode(reason, style("fontSize" to 13.0, "color" to palette.error))),
            key = key,
        )
    }

    /** Lower the component [id] (a child reference) in [ctx]. */
    fun child(id: String, ctx: LCtx): JsonMap {
        val component = surface.components[id]
        val key = keyFor(id, ctx)
        if (component == null) return el("SizedBox", props("width" to 0.0, "height" to 0.0), key = key) // not arrived yet (progressive rendering)
        val marker = "$id@${ctx.scope}"
        if (marker in ctx.stack) return placeholder(id, "Circular reference to \"$id\"", key)
        if (ctx.depth >= MAX_DEPTH) return placeholder(id, "Component tree too deep", key)
        lowered.add(marker)
        val inner = ctx.copy(depth = ctx.depth + 1, stack = ctx.stack + marker)
        var node = component(component, key, inner)
        val weight = (component["weight"] as? Number)?.toDouble()
        if (weight != null && weight > 0 && (ctx.parent == "Row" || ctx.parent == "Column")) {
            node = el("Expanded", props("flex" to weight), listOf(node))
        } else if (ctx.parent == "Row" && component["component"] in ROW_SHRINKS) {
            // A row shrinks text and nested layouts to its width (CSS flex-shrink).
            node = el("Flexible", props("flex" to 1.0, "fit" to "loose"), listOf(node))
        }
        return node
    }

    private fun children(component: A2UIComponent, ctx: LCtx, parentType: String = component["component"].toString()): List<JsonMap> {
        val spec = component["children"]
        val out = ArrayList<JsonMap>()
        val childCtx = ctx.copy(parent = parentType, interceptPress = null)
        if (spec is List<*>) {
            for (id in spec) if (id is String) out.add(child(id, childCtx))
        } else if (spec is Map<*, *> && spec["componentId"] is String && spec["path"] is String) {
            val template = spec["componentId"] as String
            val base = ctx.dc.resolvePath(spec["path"] as String)
            val items = eval<Any?>(ctx, null) { ctx.dc.model.get(base) }
            fun join(k: String) = if (base == "/") "/$k" else "$base/$k"
            val keys: List<String> = when (items) {
                is List<*> -> items.indices.map { it.toString() }
                is Map<*, *> -> items.keys.map { it.toString() }
                else -> emptyList()
            }
            for (k in keys) {
                val scope = join(k)
                out.add(child(template, childCtx.copy(dc = ctx.dc.child(scope), scope = scope)))
            }
        }
        return out
    }

    private fun component(c: A2UIComponent, key: String, ctx: LCtx): JsonMap = when (c["component"]) {
        "Text" -> text(c, key, ctx)
        "Image" -> image(c, key, ctx)
        "Icon" -> icon(c, key, ctx)
        "Video" -> el("video", props("src" to str(ctx, c["url"]), "controls" to true, "style" to style("height" to 220.0, "margin" to LEAF_MARGIN, "objectFit" to "contain")), key = key)
        "AudioPlayer" -> {
            val description = str(ctx, c["description"])
            val parts = ArrayList<JsonMap>()
            if (description.isNotEmpty()) parts.add(textNode(description, style("fontSize" to 14.0, "color" to palette.onSurfaceVariant)))
            parts.add(el("audio", props("src" to str(ctx, c["url"]), "controls" to true, "style" to style("height" to 54.0)), key = "$key/audio"))
            el("Column", props("style" to style("alignItems" to "stretch", "margin" to LEAF_MARGIN)), parts, key = key)
        }
        "Row", "Column" -> flex(c, key, ctx)
        "List" -> list(c, key, ctx)
        "Card" -> el(
            "Card",
            props("elevation" to 1.0, "style" to style("padding" to 16.0, "margin" to LEAF_MARGIN, "borderRadius" to 12.0, "backgroundColor" to "#FFFFFF", "borderColor" to palette.outlineVariant, "borderWidth" to 1.0)),
            (c["child"] as? String)?.let { listOf(child(it, ctx.copy(parent = "Card", interceptPress = null))) } ?: emptyList(),
            key = key,
        )
        "Tabs" -> tabs(c, key, ctx)
        "Modal" -> modal(c, key, ctx)
        "Divider" -> if (c["axis"] == "vertical") {
            el("Container", props("style" to style("width" to 1.0, "minHeight" to 24.0, "margin" to "0 8", "backgroundColor" to palette.outlineVariant)), key = key)
        } else {
            el("Divider", props("style" to style("height" to 17.0, "borderColor" to palette.outlineVariant)), key = key)
        }
        "Button" -> button(c, key, ctx)
        "TextField" -> textField(c, key, ctx)
        "CheckBox" -> checkBox(c, key, ctx)
        "ChoicePicker" -> choicePicker(c, key, ctx)
        "Slider" -> slider(c, key, ctx)
        "DateTimeInput" -> dateTime(c, key, ctx)
        else -> placeholder(c["id"].toString(), "Unknown component: ${c["component"]}", key)
    }

    // --------------------------------------------------------------------------
    // Display
    // --------------------------------------------------------------------------

    private fun textStyle(variant: String, ctx: LCtx): JsonMap {
        val base = LinkedHashMap(TEXT_VARIANTS[variant] ?: TEXT_VARIANTS.getValue("body"))
        if (variant == "caption") base["color"] = palette.onSurfaceVariant
        if (ctx.contentColor != null) base["color"] = ctx.contentColor
        return base
    }

    private fun text(c: A2UIComponent, key: String, ctx: LCtx): JsonMap {
        val value = str(ctx, c["text"])
        val v = c["variant"]
        val variant = if (v is String && TEXT_VARIANTS.containsKey(v)) v else "body"
        val margin = if (ctx.contentColor != null) 0.0 else LEAF_MARGIN
        val blocks = parseMarkdown(value)
        if (blocks.isEmpty()) return textNode("", textStyle(variant, ctx).also { it["margin"] = margin }, key)
        if (isPlainText(blocks)) return textNode(plainText(blocks), textStyle(variant, ctx).also { it["margin"] = margin }, key)
        val loweredBlocks = blocks.mapIndexed { i, b -> markdownBlock(b, variant, ctx, "$key/md$i") }
        if (loweredBlocks.size == 1) {
            val only = loweredBlocks[0]
            only["key"] = key
            @Suppress("UNCHECKED_CAST")
            (only.propsOf()["style"] as JsonMap)["margin"] = margin
            return only
        }
        return el("Column", props("style" to style("alignItems" to "flex-start", "margin" to margin)), loweredBlocks, key = key)
    }

    private fun markdownBlock(block: MarkdownBlock, variant: String, ctx: LCtx, key: String): JsonMap {
        var st = textStyle(variant, ctx)
        var prefix = ""
        if (block.type == "heading" && variant == "body") st = textStyle("h${min(5, block.level)}", ctx)
        if (block.type == "bullet") prefix = "•  "
        if (block.type == "ordered") prefix = "${block.number}.  "
        val inlines = if (prefix.isNotEmpty()) listOf(MarkdownInline(prefix)) + block.inlines else block.inlines
        val spans = inlines.map { inline(it) }
        st["margin"] = 0.0
        st["padding"] = if (block.type == "bullet" || block.type == "ordered") "0 0 0 8" else 0.0
        return el("p", props("style" to st), spans, key = key)
    }

    private fun inline(i: MarkdownInline): JsonMap {
        val st = LinkedHashMap<String, Any?>()
        if (i.bold) st["fontWeight"] = 700.0
        if (i.italic) st["fontStyle"] = "italic"
        if (i.strike) st["textDecoration"] = "line-through"
        if (i.code) {
            st["fontFamily"] = "monospace"
            st["backgroundColor"] = "#F1EDF4"
        }
        if (i.href != null && Regex("^https?://", RegexOption.IGNORE_CASE).containsMatchIn(i.href)) {
            st["color"] = palette.primary
            return el("a", props("href" to i.href, "target" to "_blank", "text" to i.text, "style" to st))
        }
        return el("span", props("text" to i.text, "style" to st))
    }

    private fun image(c: A2UIComponent, key: String, ctx: LCtx): JsonMap {
        val src = str(ctx, c["url"])
        val variant = c["variant"] as? String ?: "mediumFeature"
        val alt = accessibilityLabel(c, ctx) ?: str(ctx, c["description"])
        val fitProp = c["fit"] as? String ?: if (variant == "icon") "contain" else "cover"
        val sizes: Map<String, Map<String, Any?>> = mapOf(
            "icon" to mapOf("width" to 24.0, "height" to 24.0),
            "avatar" to mapOf("width" to 40.0, "height" to 40.0),
            "smallFeature" to mapOf("width" to 100.0, "height" to 100.0),
            "mediumFeature" to mapOf("height" to 200.0, "maxWidth" to 300.0),
            "largeFeature" to mapOf("height" to 320.0),
            "header" to mapOf("height" to 200.0),
        )
        val size = sizes[variant] ?: sizes.getValue("mediumFeature")
        val image = el("Image", props("src" to src, "fit" to fitProp, "alt" to alt, "style" to LinkedHashMap(size)), key = "$key/img")
        val radius = if (variant == "avatar") 20.0 else if (variant == "icon") 0.0 else 8.0
        return el(
            "Container",
            props("style" to style("margin" to (if (variant == "header") 0.0 else LEAF_MARGIN))),
            listOf(if (radius != 0.0) el("ClipRRect", props("style" to style("borderRadius" to radius)), listOf(image)) else image),
            key = key,
        )
    }

    private fun icon(c: A2UIComponent, key: String, ctx: LCtx): JsonMap {
        val name = eval<Any?>(ctx, null) { ctx.dc.evaluate(c["name"]) }
        val color = ctx.contentColor ?: palette.onSurfaceVariant
        val margin = if (ctx.contentColor != null) 0.0 else LEAF_MARGIN
        if (name is Map<*, *> && name["svgPath"] is String) {
            val svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\"><path fill=\"$color\" d=\"${(name["svgPath"] as String).replace("\"", "")}\"/></svg>"
            return el(
                "Image",
                props("src" to "data:image/svg+xml;utf8,${encodeURIComponent(svg)}", "fit" to "contain", "alt" to (accessibilityLabel(c, ctx) ?: ""), "style" to style("width" to 24.0, "height" to 24.0, "margin" to margin)),
                key = key,
            )
        }
        return el("Icon", props("icon" to materialIconName(stringifyValue(name).ifEmpty { "help" }), "size" to 24.0, "style" to style("color" to color, "margin" to margin)), key = key)
    }

    // --------------------------------------------------------------------------
    // Layout
    // --------------------------------------------------------------------------

    private fun flex(c: A2UIComponent, key: String, ctx: LCtx): JsonMap {
        val justify = c["justify"] as? String ?: "start"
        val align = c["align"] as? String ?: "stretch"
        var kids = children(c, ctx)
        if (justify == "stretch") kids = kids.map { n -> if (n["type"] == "Expanded" || n["type"] == "Flexible") n else el("Expanded", props("flex" to 1.0), listOf(n)) }
        return el(c["component"].toString(), props("style" to style("justifyContent" to (JUSTIFY[justify] ?: "flex-start"), "alignItems" to (ALIGN[align] ?: "stretch"))), kids, key = key)
    }

    private fun list(c: A2UIComponent, key: String, ctx: LCtx): JsonMap {
        val horizontal = c["direction"] == "horizontal"
        val align = c["align"] as? String ?: "stretch"
        var kids = children(c, ctx, if (horizontal) "Row" else "Column").map { n -> if (n["type"] == "Flexible") n.childrenOf()[0] else n }
        if (horizontal) kids = kids.map { n -> el("ConstrainedBox", props("style" to style("maxWidth" to 320.0)), listOf(n)) }
        val inner = el(if (horizontal) "Row" else "Column", props("style" to style("alignItems" to (ALIGN[align] ?: "stretch"))), kids)
        return el("ListView", props("scrollDirection" to (if (horizontal) "horizontal" else "vertical")), if (horizontal) kids else listOf(inner), key = key)
    }

    private fun tabs(c: A2UIComponent, key: String, ctx: LCtx): JsonMap {
        val tabs = (c["tabs"] as? List<*>)?.filterIsInstance<Map<*, *>>() ?: emptyList()
        val sk = stateKey(key, "tab")
        val selected = min((options.state.get<Any?>(sk, 0.0) as? Number)?.toInt() ?: 0, max(0, tabs.size - 1))
        val p = palette
        val headers = tabs.mapIndexed { i, t ->
            val active = i == selected
            el(
                "Container",
                props("style" to style("padding" to "12 16 0 16", "cursor" to "pointer")),
                listOf(
                    el(
                        "Column",
                        props("style" to style("alignItems" to "stretch")),
                        listOf(
                            textNode(str(ctx, t["title"]), style("fontSize" to 14.0, "fontWeight" to 600.0, "color" to (if (active) p.primary else p.onSurfaceVariant), "textAlign" to "center")),
                            el("Container", props("style" to style("height" to 3.0, "margin" to "10 0 0 0", "backgroundColor" to (if (active) p.primary else "transparent"), "borderRadius" to "3 3 0 0"))),
                        ),
                    ),
                ),
                key = "$key/tab$i",
                events = mapOf(
                    "click" to { e: ElpianEvent ->
                        handled(e)
                        options.state.set(sk, i.toDouble())
                        hooks.invalidate()
                    },
                ),
            )
        }
        val childCtx = ctx.copy(parent = "Tabs", interceptPress = null)
        val bodies = ArrayList<JsonMap>()
        tabs.forEachIndexed { i, t ->
            val childId = t["child"] as? String ?: return@forEachIndexed
            if (i == selected) bodies.add(child(childId, childCtx))
            else if (options.expandAll) child(childId, childCtx)
        }
        return el(
            "Column",
            props("style" to style("alignItems" to "stretch")),
            listOf(
                el("Row", props("style" to style("alignItems" to "flex-end", "justifyContent" to "flex-start")), headers),
                el("Divider", props("style" to style("height" to 1.0, "borderColor" to p.outlineVariant))),
            ) + bodies,
            key = key,
        )
    }

    private fun modal(c: A2UIComponent, key: String, ctx: LCtx): JsonMap {
        val sk = stateKey(key, "open")
        val open = options.state.get(sk, false)
        val setOpen = { v: Boolean ->
            options.state.set(sk, v)
            hooks.invalidate()
        }
        var trigger: JsonMap = el("SizedBox", props("width" to 0.0, "height" to 0.0))
        val triggerId = c["trigger"] as? String
        if (triggerId != null) {
            val target = surface.components[triggerId]
            trigger = child(triggerId, ctx.copy(parent = "Modal", interceptPress = { setOpen(true) }))
            if (target != null && target["component"] != "Button") {
                trigger = el(
                    "GestureDetector",
                    LinkedHashMap(),
                    listOf(trigger),
                    key = "$key/trigger",
                    events = mapOf(
                        "click" to { e: ElpianEvent ->
                            handled(e)
                            setOpen(true)
                        },
                    ),
                )
            }
        }
        val contentId = c["content"] as? String
        if ((open || options.expandAll) && contentId != null) {
            val content = child(contentId, ctx.copy(parent = "Modal", interceptPress = null))
            if (open) overlays.add(dialog(key, content) { setOpen(false) })
        }
        return el("Column", props("style" to style("alignItems" to "flex-start")), listOf(trigger), key = key)
    }

    private fun dialog(key: String, content: JsonMap, close: () -> Unit): JsonMap {
        val p = palette
        val closeButton = el(
            "Container",
            props("style" to style("padding" to 8.0, "borderRadius" to 20.0, "cursor" to "pointer")),
            listOf(el("Icon", props("icon" to "close", "size" to 24.0, "style" to style("color" to p.onSurfaceVariant)))),
            key = "$key/close",
            events = mapOf(
                "click" to { e: ElpianEvent ->
                    handled(e)
                    close()
                },
            ),
        )
        val panel = el(
            "Container",
            props("style" to style("backgroundColor" to p.surfaceContainerHigh, "borderRadius" to 28.0, "padding" to "8 16 24 24", "maxWidth" to 560.0, "margin" to 24.0, "boxShadow" to "0 8px 24px rgba(0,0,0,0.25)")),
            listOf(el("Column", props("style" to style("alignItems" to "stretch")), listOf(el("Row", props("style" to style("justifyContent" to "flex-end")), listOf(closeButton)), content))),
            key = "$key/dialog",
            // Taps inside the dialog stay inside (the barrier closes on outside taps).
            events = mapOf("click" to { e: ElpianEvent -> handled(e) }),
        )
        val barrier = el(
            "Container",
            props("style" to style("backgroundColor" to "rgba(0,0,0,0.4)")),
            listOf(el("Center", LinkedHashMap(), listOf(panel))),
            key = "$key/barrier",
            events = mapOf(
                "click" to { e: ElpianEvent ->
                    handled(e)
                    close()
                },
            ),
        )
        return el("Positioned", props("style" to style("top" to 0.0, "left" to 0.0, "right" to 0.0, "bottom" to 0.0)), listOf(barrier))
    }

    // --------------------------------------------------------------------------
    // Inputs
    // --------------------------------------------------------------------------

    private fun accessibilityLabel(c: A2UIComponent, ctx: LCtx): String? {
        val a = c["accessibility"] as? Map<*, *>
        if (a != null && a["label"] != null) {
            val s = str(ctx, a["label"])
            if (s.isNotEmpty()) return s
        }
        return null
    }

    /** Bind an input: the absolute path its value writes to, or a UI-state slot for literals. */
    private inner class Binding(value: Any?, val ctx: LCtx, key: String) {
        val path: String? = if (isBinding(value)) ctx.dc.resolvePath((value as Map<*, *>)["path"] as String) else null
        val local = stateKey(key, "value")

        fun read(fallback: Any?): Any? = if (path != null) eval<Any?>(ctx, null) { ctx.dc.model.get(path) } else options.state.get(local, fallback)

        fun write(v: Any?) {
            if (path != null) hooks.write(surface.id, path, v)
            else {
                options.state.set(local, v)
                hooks.invalidate()
            }
        }
    }

    private fun checks(c: A2UIComponent, ctx: LCtx): List<String> = evaluateChecks(c["checks"], ctx.dc, report)

    private fun label(text: String, color: String? = null): JsonMap =
        textNode(text, style("fontSize" to 12.0, "fontWeight" to 500.0, "color" to (color ?: palette.onSurfaceVariant), "margin" to "0 0 2 0"))

    private fun errorText(messages: List<String>): List<JsonMap> =
        if (messages.isNotEmpty()) listOf(textNode(messages[0], style("fontSize" to 12.0, "color" to palette.error, "margin" to "4 0 0 0"))) else emptyList()

    private fun touched(key: String): Boolean = options.state.get(stateKey(key, "touched"), false)

    private fun touch(key: String) {
        options.state.set(stateKey(key, "touched"), true)
    }

    private fun button(c: A2UIComponent, key: String, ctx: LCtx): JsonMap {
        val variant = c["variant"] as? String ?: "default"
        val p = palette
        val failures = checks(c, ctx)
        val press = ctx.interceptPress
        val enabled = press != null || failures.isEmpty()
        val contentColor = if (variant == "primary") p.onPrimary else p.primary
        val childId = c["child"] as? String
        val childNode = if (childId != null) child(childId, ctx.copy(parent = "Button", contentColor = contentColor, interceptPress = null)) else textNode("")
        val childComponent = childId?.let { surface.components[it] }
        val label = accessibilityLabel(c, ctx) ?: (if (childComponent?.get("component") == "Text") plainText(parseMarkdown(str(ctx, childComponent["text"]))) else "")
        val st: JsonMap = when (variant) {
            "primary" -> style("backgroundColor" to p.primary, "color" to p.onPrimary, "margin" to LEAF_MARGIN)
            "borderless" -> style("backgroundColor" to "transparent", "color" to p.primary, "boxShadow" to "0 0 0 0 rgba(0,0,0,0)", "padding" to "0 12", "margin" to LEAF_MARGIN)
            else -> style("backgroundColor" to p.surfaceContainer, "color" to p.primary, "border" to "1px solid ${p.outlineVariant}", "margin" to LEAF_MARGIN)
        }
        val componentId = c["id"].toString()
        val action = c["action"]
        val events: Map<String, EventHandler>? = if (enabled) {
            mapOf(
                "click" to { e: ElpianEvent ->
                    handled(e)
                    if (press != null) press() else hooks.action(surface.id, componentId, action, ctx.scope)
                },
            )
        } else null
        return el("Button", props("text" to label.ifEmpty { "Button" }, "disabled" to !enabled, "style" to st), listOf(childNode), key = key, events = events)
    }

    private fun textField(c: A2UIComponent, key: String, ctx: LCtx): JsonMap {
        val variant = c["variant"] as? String ?: "shortText"
        val label = str(ctx, c["label"])
        val bind = Binding(c["value"], ctx, key)
        val raw = bind.read(if (isBinding(c["value"])) null else str(ctx, c["value"]))
        val value = stringifyValue(raw)
        var failures = checks(c, ctx)
        val re = c["validationRegexp"]
        if (re is String && value != "") {
            val ok = try {
                Regex(re).containsMatchIn(value)
            } catch (_: Exception) {
                true
            }
            if (!ok) failures = failures + "Invalid format"
        }
        val showErrors = failures.isNotEmpty() && (touched(key) || value != "")
        val p = palette
        val a11y = accessibilityLabel(c, ctx)
        val field = el(
            "TextField",
            props(
                "value" to value,
                "hint" to (if (a11y != null && label.isEmpty()) a11y else ""),
                "obscureText" to (variant == "obscured"),
                "multiline" to (variant == "longText"),
                "maxLines" to (if (variant == "longText") 4.0 else 1.0),
                "keyboardType" to (if (variant == "number") "number" else "text"),
                "style" to style("color" to p.onSurface),
            ),
            key = "$key/input",
            events = mapOf(
                "input" to { e: ElpianEvent ->
                    handled(e)
                    touch(key)
                    bind.write(eventText(e))
                },
            ),
        )
        val parts = ArrayList<JsonMap>()
        if (label.isNotEmpty()) parts.add(label(label, if (showErrors) p.error else null))
        parts.add(field)
        parts.addAll(errorText(if (showErrors) failures else emptyList()))
        return el("Column", props("style" to style("alignItems" to "stretch", "margin" to LEAF_MARGIN)), parts, key = key)
    }

    private fun checkBox(c: A2UIComponent, key: String, ctx: LCtx): JsonMap {
        val bind = Binding(c["value"], ctx, key)
        val checked = if (isBinding(c["value"])) bind.read(false) == true else bind.read(eval(ctx, false) { ctx.dc.boolean(c["value"]) }) == true
        val toggle = { v: Boolean ->
            touch(key)
            bind.write(v)
        }
        val failures = checks(c, ctx)
        val showErrors = failures.isNotEmpty() && touched(key)
        val box = el(
            "Checkbox",
            props("value" to checked, "style" to style("color" to palette.primary)),
            key = "$key/box",
            events = mapOf(
                "change" to { e: ElpianEvent ->
                    handled(e)
                    toggle(jsTruthy(e.value))
                },
            ),
        )
        val labelNode = el(
            "Container",
            props("style" to style("cursor" to "pointer", "padding" to "0 4")),
            listOf(textNode(str(ctx, c["label"]), style("fontSize" to 16.0))),
            key = "$key/label",
            events = mapOf(
                "click" to { e: ElpianEvent ->
                    handled(e)
                    toggle(!checked)
                },
            ),
        )
        val row = el("Row", props("style" to style("alignItems" to "center")), listOf(box, el("Flexible", props("flex" to 1.0, "fit" to "loose"), listOf(labelNode))))
        return el("Column", props("style" to style("alignItems" to "stretch", "margin" to LEAF_MARGIN)), listOf(row) + errorText(if (showErrors) failures else emptyList()), key = key)
    }

    private fun choicePicker(c: A2UIComponent, key: String, ctx: LCtx): JsonMap {
        val p = palette
        val multiple = c["variant"] == "multipleSelection"
        val chips = c["displayStyle"] == "chips"
        val bind = Binding(c["value"], ctx, key)
        val current = bind.read(if (isBinding(c["value"])) null else eval(ctx, emptyList<String>()) { ctx.dc.stringList(c["value"]) })
        val selected: List<String> = when {
            current is List<*> -> current.map { stringifyValue(it) }
            current is String && current.isNotEmpty() -> listOf(current)
            else -> emptyList()
        }
        val opts = ((c["options"] as? List<*>) ?: emptyList<Any?>())
            .filterIsInstance<Map<*, *>>()
            .filter { it["value"] is String }
            .map { o -> (o["value"] as String) to str(ctx, o["label"]).ifEmpty { o["value"] as String } }
        val filterKey = stateKey(key, "filter")
        val filter = if (c["filterable"] == true) options.state.get(filterKey, "") else ""
        val visible = if (filter.isNotEmpty()) opts.filter { it.second.lowercase().contains(filter.lowercase()) } else opts
        val choose = { value: String ->
            touch(key)
            if (multiple) bind.write(if (value in selected) selected.filter { it != value } else selected + value)
            else bind.write(listOf(value))
        }
        val parts = ArrayList<JsonMap>()
        val label = str(ctx, c["label"])
        if (label.isNotEmpty()) parts.add(label(label))
        if (c["filterable"] == true) {
            parts.add(
                el(
                    "TextField",
                    props("value" to filter, "hint" to "Filter options", "style" to style("color" to p.onSurface)),
                    key = "$key/filter",
                    events = mapOf(
                        "input" to { e: ElpianEvent ->
                            handled(e)
                            options.state.set(filterKey, eventText(e))
                            hooks.invalidate()
                        },
                    ),
                ),
            )
        }
        if (chips) {
            val items = visible.map { (value, text) ->
                val on = value in selected
                val content = ArrayList<JsonMap>()
                if (on) content.add(el("Icon", props("icon" to "check", "size" to 18.0, "style" to style("color" to p.primary, "margin" to "0 6 0 0"))))
                content.add(textNode(text, style("fontSize" to 14.0, "fontWeight" to 500.0, "color" to (if (on) p.onSurface else p.onSurfaceVariant))))
                el(
                    "Container",
                    props("style" to style("padding" to "6 14", "margin" to 4.0, "borderRadius" to 8.0, "border" to "1px solid ${if (on) p.primary else p.outline}", "backgroundColor" to (if (on) p.primaryContainer else "transparent"), "cursor" to "pointer")),
                    listOf(el("Row", props("style" to style("alignItems" to "center")), content)),
                    key = "$key/opt/$value",
                    events = mapOf(
                        "click" to { e: ElpianEvent ->
                            handled(e)
                            choose(value)
                        },
                    ),
                )
            }
            parts.add(el("Wrap", props("style" to style("gap" to 0.0)), items))
        } else {
            for ((value, text) in visible) {
                val on = value in selected
                val onChange: EventHandler = { e ->
                    handled(e)
                    choose(value)
                }
                val control = if (multiple) {
                    el("Checkbox", props("value" to on, "style" to style("color" to p.primary)), key = "$key/opt/$value", events = mapOf("change" to onChange))
                } else {
                    el("Radio", props("value" to value, "groupValue" to selected.firstOrNull(), "style" to style("color" to p.primary)), key = "$key/opt/$value", events = mapOf("change" to onChange))
                }
                val textEl = el(
                    "Container",
                    props("style" to style("cursor" to "pointer", "padding" to "0 4")),
                    listOf(textNode(text, style("fontSize" to 16.0))),
                    key = "$key/optlabel/$value",
                    events = mapOf(
                        "click" to { e: ElpianEvent ->
                            handled(e)
                            choose(value)
                        },
                    ),
                )
                parts.add(el("Row", props("style" to style("alignItems" to "center")), listOf(control, el("Flexible", props("flex" to 1.0, "fit" to "loose"), listOf(textEl)))))
            }
        }
        val failures = checks(c, ctx)
        parts.addAll(errorText(if (failures.isNotEmpty() && touched(key)) failures else emptyList()))
        return el("Column", props("style" to style("alignItems" to "stretch", "margin" to LEAF_MARGIN)), parts, key = key)
    }

    private fun slider(c: A2UIComponent, key: String, ctx: LCtx): JsonMap {
        val p = palette
        val min = (c["min"] as? Number)?.toDouble() ?: 0.0
        val cmax = (c["max"] as? Number)?.toDouble()
        val max = if (cmax != null && cmax > min) cmax else min + 100
        val bind = Binding(c["value"], ctx, key)
        val raw = bind.read(if (isBinding(c["value"])) null else eval<Double?>(ctx, min) { ctx.dc.number(c["value"]) })
        val n = when {
            raw is Number -> raw.toDouble()
            raw is String && raw.trim().isNotEmpty() && jsNumberOfString(raw).isFinite() -> jsNumberOfString(raw)
            else -> min
        }
        val value = max(min, min(max, n))
        val label = str(ctx, c["label"])
        val shown = if (value == Math.rint(value)) dev.elpian.core.util.Json.formatNumber(value) else toFixed(value, if (abs(max - min) <= 1) 2 else 1)
        val header = el(
            "Row",
            props("style" to style("alignItems" to "center", "justifyContent" to "space-between")),
            listOf(
                el("Flexible", props("flex" to 1.0, "fit" to "loose"), listOf(textNode(label, style("fontSize" to 14.0, "color" to p.onSurfaceVariant)))),
                textNode(shown, style("fontSize" to 14.0, "fontWeight" to 600.0, "color" to p.onSurface)),
            ),
        )
        val sliderNode = el(
            "Slider",
            props("min" to min, "max" to max, "value" to value, "style" to style("color" to p.primary)),
            key = "$key/slider",
            events = mapOf(
                "change" to { e: ElpianEvent ->
                    handled(e)
                    val v = jsNumberValue(e.value)
                    if (v.isFinite()) bind.write(v)
                },
            ),
        )
        val failures = checks(c, ctx)
        return el("Column", props("style" to style("alignItems" to "stretch", "margin" to LEAF_MARGIN)), listOf(header, sliderNode) + errorText(failures), key = key)
    }

    private fun dateTime(c: A2UIComponent, key: String, ctx: LCtx): JsonMap {
        val p = palette
        val enableDate = c["enableDate"] == true
        val enableTime = c["enableTime"] == true
        val mode = if (enableDate && enableTime) "datetime-local" else if (enableTime) "time" else if (enableDate) "date" else "datetime-local"
        val bind = Binding(c["value"], ctx, key)
        val iso = stringifyValue(bind.read(if (isBinding(c["value"])) null else str(ctx, c["value"])))
        val label = str(ctx, c["label"])
        val field = el(
            "TextField",
            props(
                "value" to isoToInput(iso, mode),
                "keyboardType" to mode,
                "min" to (if (c.containsKey("min")) isoToInput(str(ctx, c["min"]), mode).ifEmpty { null } else null),
                "max" to (if (c.containsKey("max")) isoToInput(str(ctx, c["max"]), mode).ifEmpty { null } else null),
                "style" to style("color" to p.onSurface),
            ),
            key = "$key/input",
            events = mapOf(
                "input" to { e: ElpianEvent ->
                    handled(e)
                    touch(key)
                    bind.write(inputToIso(eventText(e), mode))
                },
            ),
        )
        val failures = checks(c, ctx)
        val parts = ArrayList<JsonMap>()
        if (label.isNotEmpty()) parts.add(label(label))
        parts.add(field)
        parts.addAll(errorText(if (failures.isNotEmpty() && touched(key)) failures else emptyList()))
        return el("Column", props("style" to style("alignItems" to "stretch", "margin" to LEAF_MARGIN)), parts, key = key)
    }
}

/** JavaScript truthiness of an event value (`!!v`). */
private fun jsTruthy(v: Any?): Boolean = when (v) {
    null -> false
    is Boolean -> v
    is Number -> v.toDouble() != 0.0 && !v.toDouble().isNaN()
    is String -> v.isNotEmpty()
    else -> true
}

/** JavaScript `Number(v)` for an event value. */
private fun jsNumberValue(v: Any?): Double = when (v) {
    null -> Double.NaN
    is Number -> v.toDouble()
    is Boolean -> if (v) 1.0 else 0.0
    is String -> jsNumberOfString(v)
    else -> Double.NaN
}

/** `Number.prototype.toFixed`. */
private fun toFixed(v: Double, digits: Int): String = java.math.BigDecimal(v.toString()).setScale(digits, java.math.RoundingMode.HALF_UP).toPlainString()

private fun pad2(n: Int): String = n.toString().padStart(2, '0')

private val TIME_PREFIX = Regex("^(\\d{2}):(\\d{2})")
private val DATE_ONLY_ISO = Regex("^(\\d{4}-\\d{2}-\\d{2})$")
private val LOCAL_DATE_TIME = Regex("^(\\d{4}-\\d{2}-\\d{2})T(\\d{2}):(\\d{2})(?::\\d{2}(?:\\.\\d+)?)?$")
private val HH_MM = Regex("^\\d{2}:\\d{2}$")
private val LOCAL_MINUTES = Regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}$")

/** ISO 8601 (model) → the value a native date / time / datetime-local input shows. */
fun isoToInput(iso: String, mode: String): String {
    if (iso.isEmpty()) return ""
    val s = iso.trim()
    val time = TIME_PREFIX.find(s)
    if (mode == "time" && time != null) return "${time.groupValues[1]}:${time.groupValues[2]}"
    DATE_ONLY_ISO.matchEntire(s)?.let { m ->
        val d = m.groupValues[1]
        return if (mode == "time") "" else if (mode == "date") d else "${d}T00:00"
    }
    LOCAL_DATE_TIME.matchEntire(s)?.let { m ->
        val (d, h, mi) = m.destructured
        return when (mode) {
            "date" -> d
            "time" -> "$h:$mi"
            else -> "${d}T$h:$mi"
        }
    }
    val parsed = parseDate(s) ?: return ""
    val date = "${parsed.year.toString().padStart(4, '0')}-${pad2(parsed.monthValue)}-${pad2(parsed.dayOfMonth)}"
    val t = "${pad2(parsed.hour)}:${pad2(parsed.minute)}"
    return if (mode == "date") date else if (mode == "time") t else "${date}T$t"
}

/** A native input's value → ISO 8601 for the data model. */
fun inputToIso(value: String, mode: String): String {
    val v = value.trim()
    if (v.isEmpty()) return ""
    if (mode == "time") return if (HH_MM.matches(v)) "$v:00" else v
    if (mode == "datetime-local") return if (LOCAL_MINUTES.matches(v)) "$v:00" else v
    return v
}
