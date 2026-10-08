package dev.elpian.core.render.paint

import dev.elpian.core.canvas.CanvasContext
import dev.elpian.core.css.EdgeInsets
import dev.elpian.core.render.Constraints
import dev.elpian.core.render.ControlMeasureSpec
import dev.elpian.core.render.INF
import dev.elpian.core.render.RenderObject
import dev.elpian.core.render.RenderProxy
import dev.elpian.core.render.Size
import dev.elpian.core.render.TextStyleSpec
import dev.elpian.core.render.Vec
import dev.elpian.core.render.ViewEvent
import dev.elpian.core.render.ViewKinds
import dev.elpian.core.render.ViewProps
import dev.elpian.core.render.biggest
import dev.elpian.core.render.constrain
import dev.elpian.core.render.d
import dev.elpian.core.render.enforce
import dev.elpian.core.render.layout.preserveAspect
import dev.elpian.core.render.s
import dev.elpian.core.render.smallest
import dev.elpian.core.render.tightFor
import dev.elpian.core.util.Json
import dev.elpian.core.util.jsString
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max

/**
 * Leaf render objects backed by native elements (render/paint/leaves.ts):
 * images, native controls, canvases, Godot surfaces, media players and
 * embedded web content, plus the transparent gesture region every
 * event-bearing element is wrapped in.
 */

private val UNBOUNDED = Constraints(0.0, INF, 0.0, INF)

/** A `[top, right, bottom, left]` padding given as a list, array or [EdgeInsets]. */
private fun padding4(v: Any?, fallback: DoubleArray): DoubleArray = when (v) {
    is DoubleArray -> v
    is EdgeInsets -> doubleArrayOf(v.top, v.right, v.bottom, v.left)
    is List<*> -> DoubleArray(4) { i -> (v.getOrNull(i) as? Number)?.toDouble() ?: 0.0 }
    else -> fallback
}

// ----------------------------------------------------------------------------
// Image
// ----------------------------------------------------------------------------

/** props: { src, fit, alignment, width, height, alt, repeat, tint, semanticsLabel, onEvent } */
open class RenderImage : RenderObject() {
    fun naturalSize(): Size? {
        val src = props.s("src")
        val o = owner
        if (src.isNullOrEmpty() || o == null) return null
        return o.imageSize(src)
    }

    override fun performLayout(c: Constraints) {
        val inner = enforce(tightFor(UNBOUNDED, props.d("width"), props.d("height")), c)
        val natural = naturalSize()
        if (natural == null) {
            size = smallest(inner)
            return
        }
        size = preserveAspect(inner, natural)
    }

    override fun computeMaxIntrinsicWidth(height: Double): Double {
        props.d("width")?.let { return it }
        val n = naturalSize() ?: return 0.0
        return if (height.isFinite() && n.height > 0) height * n.width / n.height else n.width
    }
    override fun computeMinIntrinsicWidth(height: Double): Double = computeMaxIntrinsicWidth(height)
    override fun computeMaxIntrinsicHeight(width: Double): Double {
        props.d("height")?.let { return it }
        val n = naturalSize() ?: return 0.0
        return if (width.isFinite() && n.width > 0) width * n.height / n.width else n.height
    }
    override fun computeMinIntrinsicHeight(width: Double): Double = computeMaxIntrinsicHeight(width)

    override fun viewKind(): String? = ViewKinds.IMAGE
    override fun viewProps(): ViewProps {
        val repeat = props.s("repeat")
        return linkedMapOf(
            "src" to props["src"],
            "fit" to (props["fit"] ?: "contain"),
            "alignment" to props["alignment"],
            "alt" to props["alt"],
            "tint" to props["tint"],
            "semanticsLabel" to (props["semanticsLabel"] ?: props["alt"]),
            "backgroundImage" to (if (!repeat.isNullOrEmpty() && repeat != "no-repeat") DecorationImage(props.s("src") ?: "", null, null, repeat) else null),
        )
    }
    override fun handleViewEvent(event: ViewEvent) {
        callHandler(props["onEvent"], event)
    }
}

// ----------------------------------------------------------------------------
// Native controls
// ----------------------------------------------------------------------------

/**
 * props: {
 *   kind: 'checkbox'|'radio'|'switch'|'slider'|'progress'|'textInput'|'select',
 *   view: Map (partial view props: value, checked, options, colors, textStyle …),
 *   width?, height?, lines?, lineHeight?, padding?: [t,r,b,l], onEvent
 * }
 */
open class RenderControl : RenderObject() {
    private fun kind(): String? = props.s("kind")

    @Suppress("UNCHECKED_CAST")
    private fun view(): Map<String, Any?> = props["view"] as? Map<String, Any?> ?: emptyMap()

    private fun defaultSize(c: Constraints): Size {
        val view = view()
        fun fillW(fallback: Double) = if (c.maxWidth.isFinite()) c.maxWidth else fallback
        return when (kind()) {
            ViewKinds.CHECKBOX, ViewKinds.RADIO -> Size(48.0, 48.0)
            ViewKinds.SWITCH -> Size(60.0, 48.0)
            ViewKinds.SLIDER -> Size(fillW(200.0), 48.0)
            ViewKinds.PROGRESS ->
                if (view["variant"] == "circular") Size(36.0, 36.0)
                else Size(fillW(200.0), view.d("strokeWidth") ?: 4.0)
            ViewKinds.TEXT_INPUT -> {
                val ts = view["textStyle"] as? TextStyleSpec
                val fontSize = ts?.fontSize ?: 16.0
                val lineH = props.d("lineHeight") ?: (fontSize * (ts?.height ?: 1.5))
                val lines = max(1.0, props.d("lines") ?: 1.0)
                val pad = padding4(props["padding"], doubleArrayOf(12.0, 0.0, 12.0, 0.0))
                Size(fillW(280.0), ceil(lines * lineH + pad[0] + pad[2]))
            }
            ViewKinds.SELECT -> {
                val ts = view["textStyle"] as? TextStyleSpec
                val fontSize = ts?.fontSize ?: 14.0
                val lineH = max(24.0, fontSize * (ts?.height ?: 1.3))
                val pad = padding4(props["padding"], doubleArrayOf(0.0, 0.0, 0.0, 0.0))
                Size(fillW(200.0), ceil(lineH + pad[0] + pad[2]))
            }
            else -> Size(48.0, 48.0)
        }
    }

    override fun performLayout(c: Constraints) {
        var size = defaultSize(c)
        val measured = owner?.platform?.measureControl(ControlMeasureSpec(kind() ?: "", view()), c.maxWidth)
        if (measured != null) size = measured
        props.d("width")?.let { size = size.copy(width = it) }
        props.d("height")?.let { size = size.copy(height = it) }
        this.size = constrain(c, size)
    }

    override fun computeMinIntrinsicWidth(height: Double): Double = props.d("width") ?: defaultSize(UNBOUNDED).width
    override fun computeMaxIntrinsicWidth(height: Double): Double = computeMinIntrinsicWidth(height)
    override fun computeMinIntrinsicHeight(width: Double): Double = props.d("height") ?: defaultSize(UNBOUNDED).height
    override fun computeMaxIntrinsicHeight(width: Double): Double = computeMinIntrinsicHeight(width)

    override fun baseline(): Double? {
        val k = kind()
        if (k == ViewKinds.TEXT_INPUT || k == ViewKinds.SELECT) {
            val ts = view()["textStyle"] as? TextStyleSpec
            val pad = padding4(props["padding"], doubleArrayOf(12.0, 0.0, 12.0, 0.0))
            return pad[0] + (ts?.fontSize ?: 16.0) * 0.95
        }
        return null
    }

    override fun viewKind(): String? = kind()
    override fun viewProps(): ViewProps = LinkedHashMap(view())

    override fun handleViewEvent(event: ViewEvent) {
        callHandler(props["onEvent"], event)
        // Controlled controls (Flutter Checkbox/Switch/Slider/Radio) show the
        // guest's value, not the user's gesture, until the guest re-renders: make
        // the next frame re-assert the configured value on the native control.
        val id = viewId
        val o = owner
        if (isTruthy(props["controlled"]) && id != null && o != null) {
            o.compositor.invalidateProps(id, listOf("checked", "value"))
        }
    }
}

// ----------------------------------------------------------------------------
// Canvas
// ----------------------------------------------------------------------------

/**
 * props: {
 *   width?, height?, background?: Color,
 *   commands?: List            — inline command list (Canvas / canvas)
 *   commandsKey?: string       — identity of the inline list (defaults to its JSON)
 *   context?: CanvasContext    — cached context
 * }
 */
open class RenderCanvas : RenderObject() {
    private var sentGeneration = -1
    private var sentCount = 0
    private var sentInlineKey: String? = null

    override fun performLayout(c: Constraints) {
        val w = props.d("width")
        val h = props.d("height")
        val b = biggest(c)
        size = constrain(c, Size(w ?: (if (c.maxWidth.isFinite()) b.width else 0.0), h ?: (if (c.maxHeight.isFinite()) b.height else 0.0)))
    }

    override fun viewKind(): String? = ViewKinds.CANVAS

    override fun viewProps(): ViewProps {
        val out: ViewProps = linkedMapOf("background" to props["background"])
        val ctx = props["context"] as? CanvasContext
        if (ctx != null) {
            if (ctx.generation != sentGeneration) {
                out["commands"] = ctx.commands.toList()
                sentGeneration = ctx.generation
                sentCount = ctx.commands.size
            } else if (ctx.commands.size > sentCount) {
                out["appendCommands"] = ctx.commands.subList(sentCount, ctx.commands.size).toList()
                sentCount = ctx.commands.size
            }
            out["canvasVersion"] = ctx.version
            return out
        }
        val commands = props["commands"] as? List<*> ?: emptyList<Any?>()
        val key = props["commandsKey"]?.let { it as? String ?: jsString(it) } ?: Json.stringify(commands)
        if (key != sentInlineKey) {
            out["commands"] = commands
            sentInlineKey = key
        }
        return out
    }

    /** Force the next frame to resend the full command list (e.g. after re-mount). */
    fun resetSent() {
        sentGeneration = -1
        sentCount = 0
        sentInlineKey = null
    }

    override fun handleViewEvent(event: ViewEvent) {
        callHandler(props["onEvent"], event)
    }
}

// ----------------------------------------------------------------------------
// Scene3D (embedded Godot)
// ----------------------------------------------------------------------------

/** props: { surfaceId, width, height, clickable, live, placeholder?, onEvent } */
open class RenderScene3D : RenderObject() {
    override fun performLayout(c: Constraints) {
        val w = props.d("width")
        val h = props.d("height")
        val width = w ?: (if (c.maxWidth.isFinite()) c.maxWidth else 300.0)
        val height = h ?: (if (c.maxHeight.isFinite()) c.maxHeight else width * 9 / 16)
        size = constrain(c, Size(width, height))
        for (ch in children) {
            ch.layout(Constraints(size.width, size.width, size.height, size.height))
            ch.offset = Vec(0.0, 0.0)
        }
    }

    override fun viewKind(): String? = ViewKinds.SCENE3D

    /** The placeholder child paints only when no engine is live. */
    override fun paintsChild(child: RenderObject): Boolean = !isTruthy(props["live"])

    override fun viewProps(): ViewProps {
        val clickable = isTruthy(props["clickable"])
        return linkedMapOf(
            "surfaceId" to props["surfaceId"],
            "clickable" to clickable,
            "gestures" to (if (clickable) listOf("tap") else null),
            "clip" to true,
        )
    }

    override fun handleViewEvent(event: ViewEvent) {
        callHandler(props["onEvent"], event)
    }
}

// ----------------------------------------------------------------------------
// Media (video / audio)
// ----------------------------------------------------------------------------

/** JavaScript `Number(v)` for an event payload field. */
private fun jsNumber(v: Any?): Double = when (v) {
    null -> Double.NaN
    is Number -> v.toDouble()
    is Boolean -> if (v) 1.0 else 0.0
    is String -> v.trim().let { if (it.isEmpty()) 0.0 else it.toDoubleOrNull() ?: Double.NaN }
    else -> Double.NaN
}

/** props: { kind: 'video'|'audio', src, autoplay, loop, muted, controls, poster, tracks, fit, width, height, onEvent } */
open class RenderMedia : RenderObject() {
    private var aspect: Double? = null

    override fun performLayout(c: Constraints) {
        val kind = if (props["kind"] == "audio") "audio" else "video"
        val w = props.d("width")
        val h = props.d("height")
        if (kind == "audio") {
            size = constrain(c, Size(w ?: (if (c.maxWidth.isFinite()) c.maxWidth else 300.0), h ?: 54.0))
            return
        }
        val aspect = this.aspect ?: (16.0 / 9)
        val width = w ?: (if (c.maxWidth.isFinite()) c.maxWidth else 300.0)
        val height = h ?: (width / aspect)
        size = constrain(c, Size(width, height))
    }

    override fun viewKind(): String? = if (props["kind"] == "audio") ViewKinds.AUDIO else ViewKinds.VIDEO

    override fun viewProps(): ViewProps = linkedMapOf(
        "src" to props["src"],
        "autoplay" to isTruthy(props["autoplay"]),
        "loop" to isTruthy(props["loop"]),
        "muted" to isTruthy(props["muted"]),
        "controls" to (props["controls"] != false),
        "poster" to props["poster"],
        "tracks" to props["tracks"],
        "fit" to (props["fit"] ?: "contain"),
    )

    override fun handleViewEvent(event: ViewEvent) {
        val value = event.value
        if (event.type == "load" && value is Map<*, *>) {
            val vw = jsNumber(value["width"])
            val vh = jsNumber(value["height"])
            if (vw > 0 && vh > 0) {
                val next = vw / vh
                val current = aspect
                if (current == null || abs(current - next) > 0.001) {
                    aspect = next
                    markNeedsLayout()
                }
            }
        }
        callHandler(props["onEvent"], event)
    }
}

// ----------------------------------------------------------------------------
// Web content (iframe / embed / object)
// ----------------------------------------------------------------------------

/** props: { src, html, width, height, javascript, onEvent } */
open class RenderWeb : RenderObject() {
    override fun performLayout(c: Constraints) {
        val w = props.d("width")
        val h = props.d("height")
        size = constrain(c, Size(w ?: (if (c.maxWidth.isFinite()) c.maxWidth else 300.0), h ?: (if (c.maxHeight.isFinite()) c.maxHeight else 150.0)))
    }

    override fun viewKind(): String? = ViewKinds.WEB

    override fun viewProps(): ViewProps = linkedMapOf(
        "src" to props["src"],
        "html" to props["html"],
        "javascript" to (props["javascript"] != false),
        "clip" to true,
    )

    override fun handleViewEvent(event: ViewEvent) {
        callHandler(props["onEvent"], event)
    }
}

/**
 * A host-registered native component (an island). props { component,
 * componentProps, width?, height?, onEvent }. Fills bounded constraints, else
 * the platform's measured size, else its explicit size; Elpian children are
 * laid over it (server-rendered content the native component wraps).
 */
open class RenderNative : RenderObject() {
    override fun performLayout(c: Constraints) {
        val measured = owner?.platform?.measureControl(
            ControlMeasureSpec("native", linkedMapOf("component" to props["component"], "componentProps" to (props["componentProps"] ?: emptyMap<String, Any?>()))),
            c.maxWidth,
        )
        val w = props.d("width") ?: measured?.width ?: (if (c.maxWidth.isFinite()) c.maxWidth else 0.0)
        val h = props.d("height") ?: measured?.height ?: (if (c.maxHeight.isFinite()) c.maxHeight else 0.0)
        size = constrain(c, Size(w, h))
        for (ch in children) {
            ch.layout(Constraints(0.0, size.width, 0.0, size.height))
            ch.offset = Vec(0.0, 0.0)
        }
    }

    override fun viewKind(): String? = ViewKinds.NATIVE

    override fun viewProps(): ViewProps = linkedMapOf(
        "component" to props["component"],
        "componentProps" to (props["componentProps"] ?: emptyMap<String, Any?>()),
    )

    override fun handleViewEvent(event: ViewEvent) {
        callHandler(props["onEvent"], event)
    }
}

// ----------------------------------------------------------------------------
// Gesture region
// ----------------------------------------------------------------------------

/**
 * props: {
 *   gestures: List<String>, ripple?, cursor?, tooltip?, focusable?, semanticsLabel?,
 *   role?, dragData?, dismissDirection?, onEvent(ViewEvent, RenderGesture)
 * }
 * Sizes to its child (HitTestBehavior.opaque) and owns a transparent view.
 */
open class RenderGesture : RenderProxy() {
    /** A Dismissible that was swiped away collapses to nothing. */
    var dismissed = false
    var collapse = 1.0

    override fun performLayout(c: Constraints) {
        super.performLayout(c)
        if (dismissed) {
            size = Size(size.width, size.height * collapse)
        }
    }

    override fun viewKind(): String? = ViewKinds.VIEW

    override fun viewProps(): ViewProps {
        val gestures = props["gestures"] as? List<*> ?: emptyList<Any?>()
        return linkedMapOf(
            "gestures" to (if (gestures.isNotEmpty()) gestures else null),
            "ripple" to props["ripple"],
            "cursor" to props["cursor"],
            "tooltip" to props["tooltip"],
            "focusable" to (if (isTruthy(props["focusable"])) true else null),
            "semanticsLabel" to props["semanticsLabel"],
            "role" to props["role"],
            "dragData" to props["dragData"],
            "dismissDirection" to props["dismissDirection"],
            "hidden" to (if (dismissed && collapse <= 0) true else null),
            "clip" to (if (dismissed) true else null),
        )
    }

    override fun handleViewEvent(event: ViewEvent) {
        callHandler(props["onEvent"], event, this)
    }
}
