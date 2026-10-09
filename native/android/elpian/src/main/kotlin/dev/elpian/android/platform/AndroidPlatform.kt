package dev.elpian.android.platform

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.Bitmap
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Choreographer
import dev.elpian.android.render.ElpianFonts
import dev.elpian.android.render.ElpianSurfaceView
import dev.elpian.android.render.GodotSurfaceProvider
import dev.elpian.android.render.NativeComponents
import dev.elpian.android.render.RendererHooks
import dev.elpian.android.render.TextEngine
import dev.elpian.android.render.ViewRenderer
import dev.elpian.core.css.EdgeInsets
import dev.elpian.core.platform.FetchRequest
import dev.elpian.core.platform.FetchResponse
import dev.elpian.core.platform.GodotPlatformBinding
import dev.elpian.core.platform.Platform
import dev.elpian.core.platform.StreamHandlers
import dev.elpian.core.platform.Viewport
import dev.elpian.core.render.ControlMeasureSpec
import dev.elpian.core.render.Size
import dev.elpian.core.render.TextMetrics
import dev.elpian.core.render.TextSpec
import dev.elpian.core.render.ViewEvent
import dev.elpian.core.render.ViewKinds
import dev.elpian.core.render.ViewOp
import dev.elpian.core.vm.ElpianVmBinding
import dev.elpian.core.vm.JsSandboxFactory
import dev.elpian.core.vm.WasmEngine
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.util.concurrent.Executors

/**
 * Android as an Elpian platform (the counterpart of the web host's
 * platform.ts): the main-thread dispatcher, Choreographer frames, Handler
 * timers, commits through a [ViewRenderer] per surface, StaticLayout text
 * measurement, viewports (size, density, safe area, locale, dark mode, font
 * scale), the image cache, HttpURLConnection networking (with streaming),
 * SharedPreferences storage and bundled assets. The engines (Godot, the
 * Elpian VM, the JS sandbox, wasm) are injected by the host.
 */
open class AndroidPlatform(
    context: Context,
    override val godot: GodotPlatformBinding? = null,
    override val elpianVm: ElpianVmBinding? = null,
    override val jsSandbox: JsSandboxFactory? = null,
    override val wasm: WasmEngine? = null,
    /** Prefix for storage keys. */
    private val storagePrefix: String = "",
    /** The deep link / app URL reported in viewports. */
    var href: String? = null,
) : Platform {
    val context: Context = context.applicationContext
    override val name: String = "android"
    override val dispatcher: CoroutineDispatcher = Dispatchers.Main

    /** The Godot binding's surface provider for `scene3d` views. */
    var godotSurfaceProvider: GodotSurfaceProvider? = null

    val images = ImageLoader(this.context)
    private val main = Handler(Looper.getMainLooper())
    private val timers = HashMap<Int, Runnable>()
    private var nextTimer = 1
    private val io = Executors.newCachedThreadPool { r -> Thread(r, "elpian-io").also { it.isDaemon = true } }
    private val prefs: SharedPreferences by lazy { this.context.getSharedPreferences("elpian", Context.MODE_PRIVATE) }

    private class SurfaceEntry(val root: ElpianSurfaceView, val renderer: ViewRenderer)
    private val surfaces = HashMap<String, SurfaceEntry>()

    init {
        ElpianFonts.init(this.context)
    }

    // ---------------------------------------------------------------------
    // Surfaces
    // ---------------------------------------------------------------------

    /** Render surface [id] into [root]; [emit] receives the view events (→ the session). */
    fun attachSurface(id: String, root: ElpianSurfaceView, emit: (ViewEvent) -> Unit): ViewRenderer {
        detachSurface(id)
        val renderer = ViewRenderer(root, object : RendererHooks {
            override fun emit(event: ViewEvent) = emit(event)
            override fun imageLoaded(src: String, width: Int, height: Int) {
                val natural = images.size(src)
                if (natural != null && width > 0) images.reportSize(src, natural[0], natural[1]) else images.reportSize(src, width, height)
            }
            override fun loadImage(src: String, callback: (Bitmap?) -> Unit) = images.load(src, callback)
            override fun godotSurfaces(): GodotSurfaceProvider? = godotSurfaceProvider
        })
        surfaces[id] = SurfaceEntry(root, renderer)
        return renderer
    }

    fun detachSurface(id: String) {
        val s = surfaces.remove(id) ?: return
        s.renderer.clear()
    }

    fun renderer(id: String): ViewRenderer? = surfaces[id]?.renderer

    /**
     * The view group hosting Godot surface [surfaceId] on any attached surface —
     * pass `GodotSurfaceHost { platform.godotSurfaceContainer(it) }` to `AndroidGodotBinding`.
     */
    fun godotSurfaceContainer(surfaceId: Int): android.view.ViewGroup? =
        surfaces.values.firstNotNullOfOrNull { it.renderer.scene3dContainer(surfaceId) }

    /** Listen for image natural sizes (→ the session's `imageLoaded`). */
    fun onImageLoaded(listener: (src: String, width: Int, height: Int) -> Unit): () -> Unit = images.onImageLoaded(listener)

    /** Fonts or text scale changed: drop cached metrics. */
    fun invalidateText() = TextEngine.clearCache()

    // ---------------------------------------------------------------------
    // Time and scheduling
    // ---------------------------------------------------------------------

    override fun now(): Double = System.nanoTime() / 1_000_000.0

    override fun setTimeout(ms: Double, callback: () -> Unit): Int {
        val handle = nextTimer++
        val r = Runnable {
            timers.remove(handle)
            callback()
        }
        timers[handle] = r
        main.postDelayed(r, if (ms.isFinite() && ms > 0) ms.toLong() else 0L)
        return handle
    }

    override fun clearTimeout(handle: Int) {
        timers.remove(handle)?.let { main.removeCallbacks(it) }
    }

    override fun requestFrame(callback: (Double) -> Unit) {
        val post = { Choreographer.getInstance().postFrameCallback { nanos -> callback(nanos / 1_000_000.0) } }
        if (Looper.myLooper() == Looper.getMainLooper()) post() else main.post(post)
    }

    // ---------------------------------------------------------------------
    // Rendering
    // ---------------------------------------------------------------------

    override fun commit(surface: String, ops: List<ViewOp>) {
        val s = surfaces[surface] ?: return
        s.renderer.apply(ops, density())
    }

    private fun density(): Float = context.resources.displayMetrics.density

    override fun measureText(spec: TextSpec, maxWidth: Double): TextMetrics = TextEngine.measure(spec, maxWidth, density())

    override fun measureControl(spec: ControlMeasureSpec, maxWidth: Double): Size? {
        if (spec.kind == ViewKinds.NATIVE) {
            val name = spec.props["component"] as? String ?: return null
            @Suppress("UNCHECKED_CAST")
            val props = spec.props["componentProps"] as? Map<String, Any?> ?: emptyMap()
            return NativeComponents.measurer(name)?.measure(props, maxWidth)
        }
        // The core's sizes are the Material defaults the custom-drawn controls use.
        return null
    }

    override fun imageSize(src: String): Size? = images.size(src)?.let { Size(it[0].toDouble(), it[1].toDouble()) }

    override fun preloadImage(src: String) = images.preload(src)

    override fun viewport(surface: String): Viewport {
        val root = surfaces[surface]?.root
        val dm = context.resources.displayMetrics
        val d = dm.density.toDouble()
        val cfg: Configuration = (root?.resources ?: context.resources).configuration
        val w = if (root != null && root.width > 0) root.width else dm.widthPixels
        val h = if (root != null && root.height > 0) root.height else dm.heightPixels
        val insets = root?.safeInsets ?: IntArray(4)
        val locale = if (cfg.locales.isEmpty) "en-US" else cfg.locales[0].toLanguageTag()
        return Viewport(
            width = w / d,
            height = h / d,
            devicePixelRatio = d,
            safeArea = EdgeInsets(insets[0] / d, insets[1] / d, insets[2] / d, insets[3] / d),
            locale = locale,
            platform = "android",
            isWeb = false,
            darkMode = (cfg.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES,
            textScale = cfg.fontScale.toDouble(),
            href = href,
        )
    }

    // ---------------------------------------------------------------------
    // Services
    // ---------------------------------------------------------------------

    override fun log(level: String, message: String) {
        val msg = "[elpian] $message"
        when (level) {
            "debug" -> Log.d("Elpian", msg)
            "warn" -> Log.w("Elpian", msg)
            "error" -> Log.e("Elpian", msg)
            else -> Log.i("Elpian", msg)
        }
    }

    override fun openUrl(url: String) {
        try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        } catch (e: Throwable) {
            log("warn", "openUrl($url) failed: $e")
        }
    }

    private fun open(request: FetchRequest): HttpURLConnection {
        val conn = URL(request.url).openConnection() as HttpURLConnection
        conn.requestMethod = request.method.uppercase()
        conn.instanceFollowRedirects = true
        request.timeoutMs?.let {
            conn.connectTimeout = it.toInt()
            conn.readTimeout = it.toInt()
        }
        for ((k, v) in request.headers) conn.setRequestProperty(k, v)
        val body = request.body
        if (body != null && conn.requestMethod != "GET" && conn.requestMethod != "HEAD") {
            conn.doOutput = true
            conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
        }
        return conn
    }

    private fun headersOf(conn: HttpURLConnection): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        for ((k, v) in conn.headerFields) if (k != null) out[k.lowercase()] = v.joinToString(", ")
        return out
    }

    override suspend fun fetch(request: FetchRequest): FetchResponse = withContext(Dispatchers.IO) {
        val conn = try {
            open(request)
        } catch (e: Throwable) {
            throw RuntimeException("network error reaching ${request.url}: $e")
        }
        try {
            val status = conn.responseCode
            val stream = if (status >= 400) conn.errorStream else conn.inputStream
            val bytes = stream?.use { s ->
                val out = ByteArrayOutputStream()
                s.copyTo(out)
                out.toByteArray()
            } ?: ByteArray(0)
            FetchResponse(status, headersOf(conn), bytes.toString(Charsets.UTF_8))
        } catch (e: SocketTimeoutException) {
            throw RuntimeException("request to ${request.url} timed out")
        } catch (e: Throwable) {
            throw RuntimeException("network error reaching ${request.url}: $e")
        } finally {
            conn.disconnect()
        }
    }

    override fun fetchStream(request: FetchRequest, handlers: StreamHandlers): () -> Unit {
        val cancelledFlag = java.util.concurrent.atomic.AtomicBoolean(false)
        val connRef = java.util.concurrent.atomic.AtomicReference<HttpURLConnection?>(null)
        io.execute {
            try {
                val conn = open(request)
                connRef.set(conn)
                val status = conn.responseCode
                if (status !in 200..299) throw RuntimeException("HTTP status $status")
                InputStreamReader(conn.inputStream, Charsets.UTF_8).use { reader ->
                    val buf = CharArray(8192)
                    while (!cancelledFlag.get()) {
                        val n = reader.read(buf)
                        if (n < 0) break
                        if (n == 0) continue
                        val chunk = String(buf, 0, n)
                        main.post { if (!cancelledFlag.get()) handlers.onChunk(chunk) }
                    }
                }
                main.post { if (!cancelledFlag.get()) handlers.onDone() }
            } catch (e: Throwable) {
                if (!cancelledFlag.get()) main.post { handlers.onError(e.message ?: e.toString()) }
            } finally {
                connRef.get()?.disconnect()
            }
        }
        return {
            cancelledFlag.set(true)
            io.execute { connRef.get()?.disconnect() }
        }
    }

    override fun storageGet(key: String): String? = try {
        prefs.getString(storagePrefix + key, null)
    } catch (_: Throwable) {
        null
    }

    override fun storageSet(key: String, value: String?) {
        try {
            val e = prefs.edit()
            if (value == null) e.remove(storagePrefix + key) else e.putString(storagePrefix + key, value)
            e.apply()
        } catch (_: Throwable) {
        }
    }

    override suspend fun loadAsset(path: String): ByteArray = withContext(Dispatchers.IO) {
        val p = path.removePrefix("asset:").removePrefix("file:///android_asset/").trimStart('/')
        try {
            context.assets.open(p).use { it.readBytes() }
        } catch (e: Throwable) {
            throw RuntimeException("asset $path: ${e.message ?: e}")
        }
    }
}
