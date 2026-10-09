package dev.elpian.core.session

import dev.elpian.core.platform.FetchRequest
import dev.elpian.core.platform.StreamHandlers
import dev.elpian.core.platform.platform
import dev.elpian.core.render.w
import dev.elpian.core.util.Json
import dev.elpian.core.util.JsonMap
import dev.elpian.core.util.asMap
import dev.elpian.core.util.deepMerge
import dev.elpian.core.util.isMap
import dev.elpian.core.util.jsString

/**
 * A view driven by a stream of commands — the port of `ElpianStreamWidget`
 * (flutter/lib/src/stream/elpian_stream_widget.dart; session/stream.ts).
 * Commands are pushed in (`push`), or read from a streaming HTTP response
 * (`connect`, NDJSON or server-sent events) through the platform.
 */
data class ElpianStreamCommand(
    val action: String,
    val view: JsonMap? = null,
    val patch: JsonMap? = null,
    val stylesheet: JsonMap? = null,
    val animate: Boolean? = null,
    val animationDurationMs: Double? = null,
    val animationCurve: String? = null,
) {
    fun toJson(): JsonMap = linkedMapOf(
        "action" to action,
        "view" to view,
        "patch" to patch,
        "stylesheet" to stylesheet,
        "animate" to animate,
        "animationDurationMs" to animationDurationMs,
        "animationCurve" to animationCurve,
    )
}

class StreamCommandException(message: String) : Exception(message)

/** JavaScript's `typeof` for a JSON value. */
internal fun jsTypeOf(v: Any?): String = when (v) {
    null -> "object"
    is String -> "string"
    is Number -> "number"
    is Boolean -> "boolean"
    is Function<*> -> "function"
    else -> "object"
}

/** JavaScript's `parseInt(v, 10)`: NaN → null. */
internal fun jsParseInt(v: String): Double? {
    val m = Regex("^\\s*([+-]?\\d+)").find(v) ?: return null
    return m.groupValues[1].toBigInteger().toDouble()
}

fun streamCommandFromDynamic(data: Any?): ElpianStreamCommand {
    if (data is String) return streamCommandFromDynamic(Json.parse(data))
    if (!isMap(data)) throw StreamCommandException("Unsupported stream payload type: ${if (data == null) "null" else jsTypeOf(data)}.")
    val m = data.asMap()!!
    if (m.containsKey("type") && !m.containsKey("action")) return ElpianStreamCommand(action = "setView", view = m)
    val action = if (m["action"] != null) jsString(m["action"]) else ""
    if (action.isEmpty()) throw StreamCommandException("Stream command must contain a non-empty \"action\".")
    fun map(v: Any?): JsonMap? {
        if (v == null) return null
        if (isMap(v)) return v.asMap()
        throw StreamCommandException("Expected a JSON object, got ${jsTypeOf(v)}.")
    }
    fun bool(v: Any?): Boolean? {
        if (v == null) return null
        if (v is Boolean) return v
        if (v is String && v.trim().lowercase() in listOf("true", "false")) return v.trim().lowercase() == "true"
        throw StreamCommandException("Expected a bool, got ${jsTypeOf(v)}.")
    }
    fun int(v: Any?): Double? {
        if (v == null) return null
        if (v is Number) return v.toDouble().let { if (it.isNaN() || it.isInfinite()) it else if (it < 0) Math.ceil(it) else Math.floor(it) }
        if (v is String) return jsParseInt(v)
        throw StreamCommandException("Expected an int, got ${jsTypeOf(v)}.")
    }
    return ElpianStreamCommand(
        action = action,
        view = map(m["view"]),
        patch = map(m["patch"]),
        stylesheet = map(m["stylesheet"]),
        animate = bool(m["animate"]),
        animationDurationMs = int(m["animationDurationMs"]),
        animationCurve = if (m["animationCurve"] != null) jsString(m["animationCurve"]) else null,
    )
}

private val CURVES = setOf("linear", "easeIn", "easeOut", "easeInOut", "fastOutSlowIn", "bounceIn", "bounceOut")

class StreamSessionOptions(
    val initialStylesheet: JsonMap? = null,
    val onCommand: ((command: ElpianStreamCommand) -> Unit)? = null,
    val onStreamDone: (() -> Unit)? = null,
    val onError: ((message: String) -> Unit)? = null,
    val defaultAnimationDurationMs: Double? = null,
    val defaultAnimationCurve: String? = null,
    val surface: SurfaceOptions? = null,
)

open class StreamSession(surfaceId: String, val options: StreamSessionOptions = StreamSessionOptions()) {
    val surface: ElpianSurface = ElpianSurface(surfaceId, options.surface ?: SurfaceOptions())
    private var currentView: JsonMap? = null
    private var errorMessage: String? = null
    private var version = 0
    private var activeDuration = 0.0
    private var activeCurve = "linear"
    private var cancel: (() -> Unit)? = null

    /** Run before the surface is disposed (e.g. `ElpianServerClient.mountStream` cancelling its stream). */
    var beforeDispose: (() -> Unit)? = null

    init {
        options.initialStylesheet?.let { surface.engine.loadStylesheet(it) }
        // AnimatedSwitcher(KeyedSubtree(ValueKey(version))) around the content.
        surface.decorate = { content ->
            w(
                "animatedSwitcher",
                mapOf("duration" to activeDuration, "curve" to activeCurve, "transitionType" to "fade"),
                listOf(w("proxy", emptyMap(), content, "v$version")),
            )
        }
        refresh()
    }

    val view: JsonMap? get() = currentView

    /** Deliver one stream message (a command object, a bare view, or JSON text). */
    fun push(data: Any?) {
        try {
            val command = streamCommandFromDynamic(data)
            options.onCommand?.invoke(command)
            apply(command)
            if (errorMessage != null) {
                errorMessage = null
                refresh()
            }
        } catch (e: Exception) {
            error(e)
        }
    }

    fun error(e: Any?) {
        val message = errorText(e)
        errorMessage = message
        options.onError?.invoke(message)
        refresh()
    }

    fun done() {
        options.onStreamDone?.invoke()
    }

    /**
     * Read commands from a streaming response: newline-delimited JSON, or
     * server-sent events (`data:` lines). Replaces any previous connection.
     * (Every Kotlin platform can stream, so the TS "cannot stream" branch has
     * no counterpart.)
     */
    fun connect(request: FetchRequest) {
        cancel?.invoke()
        val buffer = StringBuilder()
        var sse = ArrayList<String>()
        fun line(raw: String) {
            val l = raw.removeSuffix("\r")
            if (l.startsWith("data:")) {
                sse.add(l.substring(5).removePrefix(" "))
                return
            }
            if (l == "") {
                if (sse.isNotEmpty()) {
                    val payload = sse.joinToString("\n")
                    sse = ArrayList()
                    if (payload.isNotBlank()) push(payload)
                }
                return
            }
            if (l.startsWith(":") || SSE_FIELD.containsMatchIn(l)) return
            if (l.isNotBlank()) push(l)
        }
        cancel = platform().fetchStream(
            request,
            object : StreamHandlers {
                override fun onChunk(text: String) {
                    buffer.append(text)
                    while (true) {
                        val i = buffer.indexOf("\n")
                        if (i < 0) break
                        val l = buffer.substring(0, i)
                        buffer.delete(0, i + 1)
                        line(l)
                    }
                }

                override fun onDone() {
                    if (buffer.isNotEmpty()) line(buffer.toString())
                    line("")
                    buffer.setLength(0)
                    done()
                }

                override fun onError(message: String) {
                    error(message)
                }
            },
        )
    }

    private fun apply(c: ElpianStreamCommand) {
        val animate = c.animate ?: false
        val duration = c.animationDurationMs?.let { maxOf(0.0, minOf(30000.0, it)) } ?: options.defaultAnimationDurationMs ?: 240.0
        val ac = c.animationCurve
        val curve = if (!ac.isNullOrEmpty() && ac.trim() in CURVES) ac.trim() else options.defaultAnimationCurve ?: "easeInOut"
        fun setActive() {
            activeDuration = if (animate) duration else 0.0
            activeCurve = curve
        }
        when (c.action) {
            "setView" -> {
                val v = c.view ?: throw StreamCommandException("setView requires \"view\" object.")
                setActive()
                update(LinkedHashMap(v))
            }
            "patchView" -> {
                val p = c.patch ?: throw StreamCommandException("patchView requires \"patch\" object.")
                val cur = currentView ?: throw StreamCommandException("patchView received before any setView command.")
                setActive()
                update(deepMerge(cur, p))
            }
            "setStylesheet" -> {
                val s = c.stylesheet ?: throw StreamCommandException("setStylesheet requires \"stylesheet\" object.")
                surface.engine.loadStylesheet(s)
                setActive()
                refresh()
            }
            "renderWithStylesheet" -> {
                val s = c.stylesheet
                val v = c.view
                if (s == null || v == null) throw StreamCommandException("renderWithStylesheet requires both \"stylesheet\" and \"view\".")
                surface.engine.loadStylesheet(s)
                setActive()
                update(LinkedHashMap(v))
            }
            "clear" -> {
                currentView = null
                version++
                setActive()
                refresh()
            }
            else -> throw StreamCommandException("Unknown stream action: ${c.action}.")
        }
    }

    private fun update(view: JsonMap) {
        currentView = view
        version++
        refresh()
    }

    private fun refresh() {
        val err = errorMessage
        if (err != null) {
            surface.setOverlay(messageBox("Stream Error: $err", 0xfff44336.toInt()))
            return
        }
        surface.setContent(currentView)
    }

    open fun dispose() {
        beforeDispose?.invoke()
        beforeDispose = null
        cancel?.invoke()
        cancel = null
        surface.dispose()
    }
}

private val SSE_FIELD = Regex("^(event|id|retry):")
