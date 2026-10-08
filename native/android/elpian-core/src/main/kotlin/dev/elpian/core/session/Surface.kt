package dev.elpian.core.session

import dev.elpian.core.css.Alignment
import dev.elpian.core.css.Color
import dev.elpian.core.css.CssEnvironment
import dev.elpian.core.css.EdgeInsets
import dev.elpian.core.css.M3
import dev.elpian.core.engine.ElpianEngine
import dev.elpian.core.engine.ElpianServices
import dev.elpian.core.engine.EngineHost
import dev.elpian.core.platform.platform
import dev.elpian.core.render.RenderObject
import dev.elpian.core.render.RenderOwner
import dev.elpian.core.render.TextStyle
import dev.elpian.core.render.ViewEvent
import dev.elpian.core.render.W
import dev.elpian.core.render.paint.Decoration
import dev.elpian.core.render.reconcileRoot
import dev.elpian.core.render.w
import dev.elpian.core.util.JsonMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.util.concurrent.ConcurrentHashMap

/**
 * A surface: one engine rendering into one platform container
 * (session/surface.ts).
 *
 * It is the native counterpart of a mounted Flutter widget subtree. It
 * re-renders Elpian JSON through the engine, reconciles the widget
 * descriptors into the render tree, and lets the render owner lay out,
 * animate and commit view operations. Sessions (mini apps, streams, Next.js
 * pages) put content on a surface; the platform delivers viewport changes,
 * image loads and view events back to it.
 */
class SurfaceOptions(
    /** Share services (stylesheets, events, canvas contexts) with another engine. */
    val services: ElpianServices? = null,
    /** An existing engine (e.g. one with custom widgets registered). */
    val engine: ElpianEngine? = null,
    /** Render the content as a scrolling document (`wrapAsDocument`). */
    val document: Boolean = false,
    /** Hooks the content can call back into (navigation, forms…); null fields are not offered. */
    val host: EngineHost? = null,
) {
    fun copy(
        services: ElpianServices? = this.services,
        engine: ElpianEngine? = this.engine,
        document: Boolean = this.document,
        host: EngineHost? = this.host,
    ): SurfaceOptions = SurfaceOptions(services, engine, document, host)
}

/** `{ ...a, ...b }` for engine hosts: every hook [b] offers overrides [a]'s. */
fun mergeEngineHost(a: EngineHost?, b: EngineHost?): EngineHost {
    val out = copyEngineHost(a)
    if (b == null) return out
    b.navigate?.let { out.navigate = it }
    b.openUrl?.let { out.openUrl = it }
    b.sceneTap?.let { out.sceneTap = it }
    b.submitForm?.let { out.submitForm = it }
    b.godotBinding?.let { out.godotBinding = it }
    b.baseUrl?.let { out.baseUrl = it }
    b.hitTestDragTarget?.let { out.hitTestDragTarget = it }
    b.invalidate?.let { out.invalidate = it }
    b.focus?.let { out.focus = it }
    b.log?.let { out.log = it }
    return out
}

/** A shallow copy (`{ ...host }`). */
fun copyEngineHost(h: EngineHost?): EngineHost = EngineHost(
    navigate = h?.navigate,
    openUrl = h?.openUrl,
    sceneTap = h?.sceneTap,
    submitForm = h?.submitForm,
    godotBinding = h?.godotBinding,
    baseUrl = h?.baseUrl,
    hitTestDragTarget = h?.hitTestDragTarget,
    invalidate = h?.invalidate,
    focus = h?.focus,
    log = h?.log,
)

private val surfaces = ConcurrentHashMap<String, ElpianSurface>()

/** The surface registered under [id] (platform events are routed by it). */
fun surfaceById(id: String): ElpianSurface? = surfaces[id]

class ElpianSurface(val id: String, options: SurfaceOptions = SurfaceOptions()) {
    val engine: ElpianEngine
    val owner: RenderOwner
    private var content: JsonMap? = null
    private var overlay: W? = null
    private var renderScheduled = false
    private var disposed = false
    private val document: Boolean = options.document
    private val hostHooks: EngineHost = copyEngineHost(options.host)
    private var lastViewport = ""

    /** Where the surface's deferred work runs (the platform dispatcher); cancelled on dispose. */
    val scope: CoroutineScope = CoroutineScope(SupervisorJob() + platform().dispatcher)

    /** Wraps the lowered content each render (e.g. the stream's AnimatedSwitcher). */
    var decorate: ((content: W) -> W)? = null

    init {
        val host = copyEngineHost(hostHooks)
        host.invalidate = {
            hostHooks.invalidate?.invoke()
            scheduleRender()
        }
        host.focus = { htmlId ->
            val f = hostHooks.focus
            if (f != null) f(htmlId) else focus(htmlId)
        }
        host.hitTestDragTarget = { x, y -> hostHooks.hitTestDragTarget?.invoke(x, y) ?: hitTestDragTarget(x, y) }
        host.log = { level, message ->
            val l = hostHooks.log
            if (l != null) l(level, message) else platform().log(level, message)
        }
        val given = options.engine
        if (given != null) {
            engine = given
            engine.host = mergeEngineHost(engine.host, host)
        } else {
            engine = ElpianEngine(options.services ?: ElpianServices(id), host)
        }
        owner = RenderOwner(id, platform())
        surfaces[id] = this
        syncEnvironment()
    }

    val isDisposed: Boolean get() = disposed

    val currentContent: JsonMap? get() = content

    /** Replace the rendered Elpian JSON (null clears the surface). */
    fun setContent(json: JsonMap?) {
        content = json
        overlay = null
        scheduleRender()
    }

    /** Show a lowered widget instead of content (loading / error states). */
    fun setOverlay(widget: W?) {
        overlay = widget
        scheduleRender()
    }

    /** Re-render on the next dispatch (coalesces bursts of state changes). */
    fun scheduleRender() {
        if (renderScheduled || disposed) return
        renderScheduled = true
        scope.launch {
            renderScheduled = false
            renderNow()
        }
    }

    /** Lower and reconcile now; the owner commits on the next frame. */
    fun renderNow() {
        if (disposed) return
        syncEnvironment()
        var widget: W? = overlay
        val c = content
        if (widget == null && c != null) {
            widget = try {
                val rendered = engine.renderFromJson(c)
                var out = if (document) engine.wrapAsDocument(rendered, c) else rendered
                decorate?.let { out = it(out) }
                out
            } catch (e: Exception) {
                platform().log("error", "Elpian render error: ${jsErrorString(e)}")
                messageBox("Render Error: ${jsErrorString(e)}", 0xffff9800.toInt())
            }
        }
        if (widget == null) {
            val root = owner.root
            if (root != null) {
                root.detach()
                owner.root = null
            }
            owner.requestVisualUpdate()
            return
        }
        owner.root = reconcileRoot(owner.root, widget, owner)
        owner.requestVisualUpdate()
    }

    /** The platform reports a new size, safe area, text scale or theme. */
    fun viewportChanged() {
        if (syncEnvironment()) renderNow() else owner.requestVisualUpdate()
    }

    private fun syncEnvironment(): Boolean {
        val vp = platform().viewport(id)
        val key = listOf(vp.width, vp.height, vp.safeArea, vp.devicePixelRatio, vp.textScale, vp.darkMode).toString()
        if (key == lastViewport) return false
        lastViewport = key
        CssEnvironment.update(
            viewportWidth = vp.width,
            viewportHeight = vp.height,
            safeArea = vp.safeArea,
            devicePixelRatio = vp.devicePixelRatio,
        )
        engine.services.stylesheets.darkMode = vp.darkMode
        if (owner.textScale != vp.textScale) {
            owner.textScale = vp.textScale
            owner.invalidateMeasurements()
        }
        return true
    }

    /** A native view reported an event (tap, change, scroll, load…). */
    fun dispatchViewEvent(event: ViewEvent) {
        if (disposed) return
        owner.dispatchViewEvent(event)
    }

    /** An image finished loading (or failed with 0×0). */
    fun imageLoaded(src: String, width: Double, height: Double) {
        owner.imageLoaded(src, width, height)
    }

    /** Fonts changed or text metrics are otherwise stale. */
    fun invalidateText() {
        owner.invalidateMeasurements()
    }

    /** Focus the control rendered for the element with HTML id [htmlId] (`<label for>`). */
    fun focus(htmlId: String): Boolean {
        var target: RenderObject? = null
        owner.root?.visit { ro ->
            if (target == null && ro.props["focusId"] == htmlId && ro.viewId != null) target = ro
        }
        val found = target
        val viewId = found?.viewId ?: return false
        owner.compositor.command(viewId, "focus")
        return true
    }

    /** The DragTarget element under a point in surface coordinates. */
    fun hitTestDragTarget(x: Double, y: Double): String? {
        var hit: String? = null
        owner.root?.visit { ro ->
            val id = ro.props["dragTargetId"] ?: return@visit
            if (id == "" || id == false) return@visit
            val f = owner.compositor.globalFrame(ro)
            // globalFrame is [x, y, width, height].
            if (x >= f[0] && y >= f[1] && x <= f[0] + f[2] && y <= f[1] + f[3]) hit = id.toString()
        }
        return hit
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        surfaces.remove(id, this)
        scope.cancel()
        owner.dispose()
        engine.dispose()
    }
}

/** The red/orange diagnostic box Flutter shows for VM and render errors. */
fun messageBox(message: String, color: Color): W {
    val tint = (0x1a shl 24) or (color and 0xffffff)
    // Container(padding: 16, color: color @ 10%, child: Text(message, color)).
    return w(
        "decorated",
        mapOf("decoration" to Decoration(color = tint)),
        w("padding", mapOf("padding" to EdgeInsets(16.0, 16.0, 16.0, 16.0)), w("text", mapOf("text" to message, "style" to TextStyle(color = color)))),
    )
}

/** `Center(CircularProgressIndicator())`. */
fun loadingIndicator(): W = w(
    "align",
    mapOf("alignment" to Alignment(0.0, 0.0)),
    w(
        "control",
        mapOf(
            "kind" to "progress",
            "view" to linkedMapOf<String, Any?>(
                "variant" to "circular",
                "value" to null,
                "strokeWidth" to 4.0,
                "colors" to linkedMapOf<String, Any?>("indicator" to M3.primary, "track" to null),
            ),
        ),
    ),
)

/** JavaScript's `String(e)` for an `Error`: `Error: message`. */
internal fun jsErrorString(e: Throwable): String = "Error: ${e.message ?: e.toString()}"

/** `e instanceof Error ? e.message : String(e)`. */
internal fun errorText(e: Any?): String = when (e) {
    is Throwable -> e.message ?: e.toString()
    null -> "null"
    else -> e.toString()
}

/** JavaScript's `encodeURIComponent`. */
internal fun encodeURIComponent(s: String): String =
    java.net.URLEncoder.encode(s, Charsets.UTF_8)
        .replace("+", "%20")
        .replace("%21", "!")
        .replace("%27", "'")
        .replace("%28", "(")
        .replace("%29", ")")
        .replace("%7E", "~")
