package dev.elpian.core.canvas

import dev.elpian.core.css.Color
import dev.elpian.core.css.parseColor
import dev.elpian.core.util.JsonMap
import dev.elpian.core.util.jsString
import dev.elpian.core.util.parseFloatPrefix

/**
 * Canvas command model and the per-mini-app context store (canvas/store.ts) —
 * a port of `CanvasCommand`, `CanvasAPIExecutor`'s command list and
 * `CanvasContextStore`.
 *
 * The core never rasterises: it normalises commands (colours to ARGB,
 * defaults filled in, fonts parsed) and hands the list to the platform
 * painter (Canvas2D on the web, android.graphics.Canvas, CoreGraphics), which
 * implements the full HTML-canvas-like semantics — including the commands
 * the Flutter executor leaves unhandled (drawImage, polygons, setTransform,
 * patterns, pixel data, arcTo with tangents).
 */
val CANVAS_COMMAND_TYPES: List<String> = listOf(
    "moveTo", "lineTo", "quadraticCurveTo", "bezierCurveTo", "arc", "arcTo", "ellipse", "rect", "roundRect",
    "circle", "fillRect", "strokeRect", "clearRect", "fillCircle", "strokeCircle", "fillPolygon", "strokePolygon",
    "fillText", "strokeText", "drawImage", "drawImageRect",
    "beginPath", "closePath", "fill", "stroke", "clip",
    "save", "restore", "translate", "rotate", "scale", "transform", "setTransform", "resetTransform",
    "setFillStyle", "setStrokeStyle", "setLineWidth", "setLineCap", "setLineJoin", "setMiterLimit", "setLineDash",
    "setLineDashOffset", "setShadowBlur", "setShadowColor", "setShadowOffsetX", "setShadowOffsetY", "setGlobalAlpha",
    "setGlobalCompositeOperation", "setFont", "setTextAlign", "setTextBaseline",
    "createLinearGradient", "createRadialGradient", "addColorStop", "createPattern",
    "putImageData", "getImageData", "createImageData", "custom",
)

/** A canvas command: [type] is one of [CANVAS_COMMAND_TYPES]. */
data class CanvasCommand(val type: String, val params: MutableMap<String, Any?>, val id: String? = null)

private val TYPES: Set<String> = CANVAS_COMMAND_TYPES.toHashSet()

fun isCanvasCommandType(name: String): Boolean = name in TYPES

/** `CanvasCommand.fromJson` (unknown types become `custom`). */
fun commandFromJson(json: Any?): CanvasCommand {
    val m = json as? Map<*, *>
    val rawType = m?.get("type")
    val t = if (rawType is String && rawType in TYPES) rawType else "custom"
    val params = LinkedHashMap<String, Any?>()
    when (val raw = m?.get("params")) {
        is Map<*, *> -> for ((k, v) in raw) params[k.toString()] = v
        // `{ ...array }` spreads indices as keys.
        is List<*> -> raw.forEachIndexed { i, v -> params[i.toString()] = v }
    }
    val id = m?.get("id")?.let { it as? String ?: jsString(it) }
    return CanvasCommand(t, params, id)
}

private val COLOR_KEYS = listOf("color", "shadowColor")
private val NUMERIC = Regex("^-?\\d+(\\.\\d+)?$")
private val NON_NUMERIC_KEYS = listOf("text", "font", "id", "gradientId", "patternId", "src", "imageId", "data")

/**
 * Normalise a command for the platform painter: colours to ARGB ints (the
 * Flutter parser's rules), gradient colour lists, numeric strings to numbers.
 * The result is a JSON-shaped map `{type, params, id?}`, the same shape as
 * inline command lists.
 */
fun normalizeCommand(cmd: CanvasCommand): JsonMap {
    val p = LinkedHashMap<String, Any?>()
    for ((k, v) in cmd.params) {
        p[k] = when {
            k in COLOR_KEYS -> canvasColor(v)
            k == "colors" && v is List<*> -> v.map { canvasColor(it) }
            v is String && NUMERIC.matches(v.trim()) && k !in NON_NUMERIC_KEYS -> parseFloatPrefix(v) ?: Double.NaN
            else -> v
        }
    }
    val out: JsonMap = linkedMapOf("type" to cmd.type, "params" to p)
    if (!cmd.id.isNullOrEmpty()) out["id"] = cmd.id
    return out
}

/** Canvas colours: the canvas executor's own parser (hex, rgb/rgba, ints), falling back to CSS. */
fun canvasColor(value: Any?): Color {
    if (value is Number) {
        val d = value.toDouble()
        // JavaScript `>>> 0`: non-finite values become 0, others wrap to 32 bits.
        return if (!d.isFinite()) 0 else d.toLong().toInt()
    }
    return parseColor(value) ?: 0xff000000.toInt()
}

/** A cached drawing context (`canvas.ctx.*`), rendered by `CachedCanvas`. */
class CanvasContext(val id: String, var width: Double, var height: Double) {
    /** Every command ever added since the last clear (normalised, see [normalizeCommand]). */
    var commands: MutableList<JsonMap> = ArrayList()
    /** Bumped on every change (Flutter's `version` notifier). */
    var version = 0
    /** Bumped when the command list is reset (clear / resize) — painters redraw from scratch. */
    var generation = 0
    private val listeners = LinkedHashSet<() -> Unit>()

    fun setSize(w: Double, h: Double) {
        if (w == width && h == height) return
        width = w
        height = h
        generation++
        changed()
    }

    fun addCommand(cmd: CanvasCommand) {
        commands.add(normalizeCommand(cmd))
        changed()
    }

    fun addCommands(cmds: List<CanvasCommand>) {
        for (c in cmds) commands.add(normalizeCommand(c))
        changed()
    }

    fun clear() {
        commands = ArrayList()
        generation++
        changed()
    }

    /** Listen for changes; returns the unsubscriber. */
    fun onChange(fn: () -> Unit): () -> Unit {
        listeners.add(fn)
        return { listeners.remove(fn) }
    }

    private fun changed() {
        version++
        for (l in listeners.toList()) l()
    }

    fun dispose() {
        listeners.clear()
        commands = ArrayList()
    }
}

class CanvasContextStore {
    private val contexts = LinkedHashMap<String, CanvasContext>()
    private var nextId = 1

    fun create(id: String? = null, width: Double? = null, height: Double? = null): CanvasContext {
        val key = if (!id.isNullOrEmpty()) id else "ctx_${nextId++}"
        contexts[key]?.let { return it }
        val ctx = CanvasContext(key, width ?: 0.0, height ?: 0.0)
        contexts[key] = ctx
        return ctx
    }

    operator fun get(id: String): CanvasContext? = contexts[id]

    fun dispose(id: String) {
        val ctx = contexts.remove(id)
        ctx?.dispose()
    }

    fun clearAll() {
        for (ctx in contexts.values) ctx.dispose()
        contexts.clear()
    }
}

/** The single, context-less command list of the `canvas.*` host APIs (`CanvasAPIExecutor`). */
class CanvasExecutor {
    var commands: MutableList<CanvasCommand> = ArrayList()

    fun addCommand(cmd: CanvasCommand) {
        commands.add(cmd)
    }

    fun addCommands(cmds: List<CanvasCommand>) {
        commands.addAll(cmds)
    }

    fun clear() {
        commands = ArrayList()
    }
}

data class ParsedCanvasFont(val size: Double, val family: String, val bold: Boolean, val italic: Boolean)

private val THREE_DIGITS = Regex("^\\d{3}$")
private val BOLD = Regex("bold|[6-9]00")

/** Parse a CSS-ish canvas font (`bold italic 16px Arial`), as `_ParsedFont.parse` does. */
fun parseCanvasFont(font: String): ParsedCanvasFont {
    var size = 10.0
    var family = "sans-serif"
    val parts = font.split(" ")
    for (i in parts.indices) {
        val part = parts[i]
        if (part.endsWith("px")) {
            size = parseFloatPrefix(part)?.takeIf { it != 0.0 && !it.isNaN() } ?: 10.0
        } else if (!part.contains("bold") && !part.contains("italic") && part.trim() != "" && !THREE_DIGITS.matches(part)) {
            family = parts.subList(i, parts.size).joinToString(" ")
            break
        }
    }
    return ParsedCanvasFont(size, family, BOLD.containsMatchIn(font), font.contains("italic"))
}
