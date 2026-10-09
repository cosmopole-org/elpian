package dev.elpian.core.platform

import dev.elpian.core.css.EdgeInsets
import dev.elpian.core.render.ControlMeasureSpec
import dev.elpian.core.render.Size
import dev.elpian.core.render.TextMetrics
import dev.elpian.core.render.TextSpec
import dev.elpian.core.render.ViewOp
import dev.elpian.core.vm.ElpianVmBinding
import dev.elpian.core.vm.JsSandboxFactory
import dev.elpian.core.vm.WasmEngine
import kotlinx.coroutines.CoroutineDispatcher

/**
 * What the core needs from the platform it runs on (platform/platform.ts).
 * The Android library implements it with Views, StaticLayout, the Choreographer
 * and OkHttp-free `HttpURLConnection`; the JVM tests implement it with fakes.
 * Every callback is invoked on [dispatcher] (the UI thread on Android).
 */
data class Viewport(
    val width: Double,
    val height: Double,
    val devicePixelRatio: Double,
    val safeArea: EdgeInsets,
    /** e.g. `en-US`. */
    val locale: String,
    /** `android`, `ios`, `web` (Flutter's `defaultTargetPlatform`). */
    val platform: String,
    val isWeb: Boolean,
    val darkMode: Boolean,
    /** System text scale (accessibility). */
    val textScale: Double,
    /** The deep link / app URL. */
    val href: String? = null,
)

data class FetchRequest(
    val url: String,
    val method: String = "GET",
    val headers: Map<String, String> = emptyMap(),
    val body: String? = null,
    val timeoutMs: Long? = null,
)

data class FetchResponse(val status: Int, val headers: Map<String, String>, val body: String)

interface StreamHandlers {
    fun onChunk(text: String)
    fun onDone()
    fun onError(message: String)
}

/** The Godot transport (Android: the embedded engine's op queue). */
interface GodotPlatformBinding {
    val isLive: Boolean
    fun post(opsJson: String)
    suspend fun send(opsJson: String): String
    fun mountSurface(surfaceId: Int, mountHandle: Long)
    fun releaseSurface(surfaceId: Int)
    fun setSignalHandler(handler: ((callbackId: Long, argsJson: String) -> Unit)?)
    suspend fun stats(): Map<String, Any?>? = null
}

interface Platform {
    val name: String

    /** Where the core runs (the UI thread on Android). */
    val dispatcher: CoroutineDispatcher

    // ---- time and scheduling ----
    fun now(): Double
    fun setTimeout(ms: Double, callback: () -> Unit): Int
    fun clearTimeout(handle: Int)
    /** [callback] on the next display frame (vsync), with the frame time in ms. */
    fun requestFrame(callback: (Double) -> Unit)

    // ---- rendering ----
    fun commit(surface: String, ops: List<ViewOp>)
    fun measureText(spec: TextSpec, maxWidth: Double): TextMetrics
    /** Intrinsic size of a native control; null = the core's Material defaults. */
    fun measureControl(spec: ControlMeasureSpec, maxWidth: Double): Size? = null
    /** Natural pixel size of an image once known. */
    fun imageSize(src: String): Size? = null
    /** Start loading [src]; the platform reports back through the session's `imageLoaded`. */
    fun preloadImage(src: String) {}
    fun viewport(surface: String): Viewport

    // ---- services ----
    fun log(level: String, message: String)
    fun openUrl(url: String) {}
    suspend fun fetch(request: FetchRequest): FetchResponse
    /** Stream a response body; returns a canceller. */
    fun fetchStream(request: FetchRequest, handlers: StreamHandlers): () -> Unit
    fun storageGet(key: String): String? = null
    fun storageSet(key: String, value: String?) {}
    /** A bundled asset's bytes (`asset:` URIs / app assets). */
    suspend fun loadAsset(path: String): ByteArray

    // ---- engines ----
    val godot: GodotPlatformBinding? get() = null
    val elpianVm: ElpianVmBinding? get() = null
    val jsSandbox: JsSandboxFactory? get() = null
    val wasm: WasmEngine? get() = null
}

/** The installed platform (one per process, as in the TypeScript core). */
object Platforms {
    @Volatile private var current: Platform? = null

    fun install(platform: Platform) {
        current = platform
    }

    val isInstalled: Boolean get() = current != null

    val current_: Platform get() = current ?: error("Elpian core: no platform installed (call Platforms.install first)")
}

/** The installed platform. */
fun platform(): Platform = Platforms.current_
