package dev.elpian.android

import android.content.Context
import android.content.res.Configuration
import android.util.AttributeSet
import android.widget.FrameLayout
import dev.elpian.android.render.ElpianSurfaceView
import dev.elpian.core.util.Json
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * A View that hosts one Elpian session: `json`, `miniapp`, `superapp`,
 * `stream`, `nextjs` or `server` (see the core's SessionRegistry for each
 * kind's options and methods — they are the same as the web host's
 * `mountElpian`).
 *
 * Session events (`ready`, `error`, `println`, `updateApp`, `routeChanged`,
 * `result`, …) reach [on] listeners; [onAnyEvent] receives all of them, with
 * payloads as JSON-compatible values (see [onAnyEventJson] for strings, which
 * bridges such as React Native use).
 */
class ElpianHostView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : FrameLayout(context, attrs) {

    /** The surface id the core addresses this view by. */
    val surfaceId: String

    /** The root the core's views are rendered into. */
    val surface = ElpianSurfaceView(context)

    /** Close the session when the view leaves the window (default true). */
    var closeOnDetach = true

    private val listeners = HashMap<String, MutableList<(Any?) -> Unit>>()
    private val anyListeners = ArrayList<(String, Any?) -> Unit>()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var opened = false
    private var attached = false

    init {
        val platform = Elpian.platform(context)
        surfaceId = Elpian.newSurfaceId()
        addView(surface, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        Elpian.register(surfaceId, this)
        platform.attachSurface(surfaceId, surface) { event -> Elpian.registry.dispatchViewEvent(surfaceId, event) }
        attached = true
        surface.onSizeChanged = { _, _ -> if (opened) Elpian.registry.viewportChanged(surfaceId) }
        surface.onInsetsChanged = { if (opened) Elpian.registry.viewportChanged(surfaceId) }
    }

    // ------------------------------------------------------------------
    // Sessions
    // ------------------------------------------------------------------

    /**
     * Open a session of [kind] with [options] (closing any open one first).
     * [done] receives null on success or the failure.
     */
    @JvmOverloads
    fun open(kind: String, options: Map<String, Any?> = emptyMap(), done: ((Throwable?) -> Unit)? = null) {
        ensureAttached()
        scope.launch {
            val error = try {
                if (opened) Elpian.registry.close(surfaceId)
                opened = true
                Elpian.registry.open(kind, surfaceId, options)
                null
            } catch (t: Throwable) {
                deliver("error", mapOf("message" to (t.message ?: t.toString())))
                t
            }
            done?.invoke(error)
        }
    }

    /** [open] with options as a JSON object string. */
    @JvmOverloads
    fun openJson(kind: String, optionsJson: String?, done: ((Throwable?) -> Unit)? = null) {
        @Suppress("UNCHECKED_CAST")
        val options = (Json.parseOrNull(optionsJson) as? Map<String, Any?>) ?: emptyMap()
        open(kind, options, done)
    }

    /** Call a session method (navigate, push, callFunction, usage, …). */
    suspend fun call(method: String, vararg args: Any?): Any? = Elpian.registry.call(surfaceId, method, args.toList())

    /** [call] with a callback, for Java and bridges. */
    fun call(method: String, args: List<Any?>, callback: (Result<Any?>) -> Unit) {
        scope.launch {
            callback(runCatching { Elpian.registry.call(surfaceId, method, args) })
        }
    }

    /** [call] with JSON arguments (an array) and a JSON result — the shape bridges use. */
    fun callJson(method: String, argsJson: String?, callback: (ok: Boolean, valueJson: String) -> Unit) {
        val args = when (val parsed = Json.parseOrNull(argsJson)) {
            null -> emptyList()
            is List<*> -> parsed.toList()
            else -> listOf(parsed)
        }
        call(method, args) { r ->
            r.fold(
                { callback(true, Json.stringify(it)) },
                { callback(false, Json.stringify(it.message ?: it.toString())) },
            )
        }
    }

    /** Close the session (the view stays usable for another [open]). */
    @JvmOverloads
    fun close(done: (() -> Unit)? = null) {
        if (!opened) {
            done?.invoke()
            return
        }
        opened = false
        scope.launch {
            runCatching { Elpian.registry.close(surfaceId) }
            done?.invoke()
        }
    }

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------

    /** Listen for session [event]; returns a remover. */
    fun on(event: String, listener: (Any?) -> Unit): () -> Unit {
        listeners.getOrPut(event) { ArrayList() }.add(listener)
        return { listeners[event]?.remove(listener) }
    }

    /** Listen for every session event; returns a remover. */
    fun onAnyEvent(listener: (event: String, payload: Any?) -> Unit): () -> Unit {
        anyListeners.add(listener)
        return { anyListeners.remove(listener) }
    }

    /** [onAnyEvent] with the payload serialized as JSON. */
    fun onAnyEventJson(listener: (event: String, payloadJson: String) -> Unit): () -> Unit =
        onAnyEvent { event, payload -> listener(event, Json.stringify(payload)) }

    internal fun deliver(event: String, payload: Any?) {
        listeners[event]?.toList()?.forEach { it(payload) }
        for (l in anyListeners.toList()) l(event, payload)
    }

    // ------------------------------------------------------------------
    // View lifecycle
    // ------------------------------------------------------------------

    private fun ensureAttached() {
        if (attached) return
        Elpian.register(surfaceId, this)
        Elpian.platform(context).attachSurface(surfaceId, surface) { event -> Elpian.registry.dispatchViewEvent(surfaceId, event) }
        attached = true
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        ensureAttached()
        if (opened) Elpian.registry.viewportChanged(surfaceId)
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        if (closeOnDetach) dispose()
    }

    override fun onConfigurationChanged(newConfig: Configuration?) {
        super.onConfigurationChanged(newConfig)
        if (opened) Elpian.registry.viewportChanged(surfaceId)
    }

    /** Close the session and release the surface (re-attaching the view or [open] re-creates it). */
    fun dispose() {
        val wasOpen = opened
        opened = false
        if (!attached) return
        attached = false
        val platform = Elpian.platform(context)
        if (wasOpen) {
            // The registry outlives this view; finish the close there, then release the surface.
            CoroutineScope(Dispatchers.Main.immediate).launch {
                runCatching { Elpian.registry.close(surfaceId) }
                platform.detachSurface(surfaceId)
                Elpian.unregister(surfaceId)
            }
        } else {
            platform.detachSurface(surfaceId)
            Elpian.unregister(surfaceId)
        }
        scope.coroutineContext[kotlinx.coroutines.Job]?.children?.forEach { it.cancel() }
    }
}
