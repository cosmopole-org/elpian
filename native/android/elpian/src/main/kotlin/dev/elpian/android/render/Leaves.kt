package dev.elpian.android.render

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.RectF
import android.graphics.SurfaceTexture
import android.media.MediaPlayer
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.MediaController
import android.widget.TextView
import dev.elpian.core.css.Alignment
import dev.elpian.core.render.Size
import dev.elpian.core.render.ViewEvent
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

// ---------------------------------------------------------------------------
// Native islands and the Godot surface
// ---------------------------------------------------------------------------

/** A live host-registered component (`native` views / server-component islands). */
interface NativeComponentInstance {
    val view: View
    fun update(props: Map<String, Any?>) {}
    fun dispose() {}
}

/** Creates a native component; [emit] reports `(type, value)` events for the view. */
fun interface NativeComponentFactory {
    fun create(context: Context, props: Map<String, Any?>, emit: (type: String, value: Any?) -> Unit): NativeComponentInstance
}

/** Intrinsic size (logical px) of a native component, or null for the core default. */
fun interface NativeComponentMeasurer {
    fun measure(props: Map<String, Any?>, maxWidth: Double): Size?
}

object NativeComponents {
    private val factories = HashMap<String, NativeComponentFactory>()
    private val measurers = HashMap<String, NativeComponentMeasurer>()

    fun register(name: String, factory: NativeComponentFactory, measurer: NativeComponentMeasurer? = null) {
        factories[name] = factory
        if (measurer != null) measurers[name] = measurer else measurers.remove(name)
    }

    fun factory(name: String): NativeComponentFactory? = factories[name]
    fun measurer(name: String): NativeComponentMeasurer? = measurers[name]
}

/** Register a native island component (`ServerComponent` native islands, `native` views). */
fun registerNativeComponent(name: String, factory: NativeComponentFactory, measurer: NativeComponentMeasurer? = null) =
    NativeComponents.register(name, factory, measurer)

/**
 * Hands out the view a Godot engine renders surface [surfaceId] into; the
 * Godot binding implements it and the `scene3d` view hosts the result.
 */
interface GodotSurfaceProvider {
    fun surfaceView(surfaceId: Int, context: Context): View?
    fun releaseSurface(surfaceId: Int, view: View) {}
}

/** The `scene3d` view kind: a host the Godot binding attaches its surface view to. */
@SuppressLint("ViewConstructor")
class Scene3dLeaf(context: Context, private val owner: ElpianView, private val provider: () -> GodotSurfaceProvider?) : FrameLayout(context) {
    /** The Godot surface this view shows (the binding's `GodotSurfaceHost` finds it by id). */
    var surfaceId: Int? = null
        private set
    private var surface: View? = null

    fun setSurface(id: Int?) {
        if (id == surfaceId && surface != null) return
        release()
        surfaceId = id
        if (id == null) return
        val v = provider()?.surfaceView(id, context) ?: return
        (v.parent as? ViewGroup)?.removeView(v)
        addView(v, 0, LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        surface = v
    }

    fun release() {
        val v = surface ?: return
        removeView(v)
        surfaceId?.let { provider()?.releaseSurface(it, v) }
        surface = null
    }
}

// ---------------------------------------------------------------------------
// Images
// ---------------------------------------------------------------------------

/** Flutter `applyBoxFit` + `Alignment.inscribe`: where an image of [iw]×[ih] (device px) lands in a [bw]×[bh] box. */
internal fun fitRect(fit: String?, iw: Float, ih: Float, bw: Float, bh: Float, a: Alignment, density: Float): RectF {
    var dw: Float
    var dh: Float
    when (fit) {
        "fill" -> { dw = bw; dh = bh }
        "cover" -> { val s = max(bw / iw, bh / ih); dw = iw * s; dh = ih * s }
        "fitWidth" -> { dw = bw; dh = ih * bw / iw }
        "fitHeight" -> { dh = bh; dw = iw * bh / ih }
        "none" -> { dw = iw * density; dh = ih * density }
        "scaleDown" -> { val s = min(1f * density, min(bw / iw, bh / ih)); dw = iw * s; dh = ih * s }
        else -> { val s = min(bw / iw, bh / ih); dw = iw * s; dh = ih * s }
    }
    val x = ((bw - dw) * (a.x + 1) / 2).toFloat()
    val y = ((bh - dh) * (a.y + 1) / 2).toFloat()
    return RectF(x, y, x + dw, y + dh)
}

/** The `image` view kind: a bitmap with BoxFit, alignment and an srcIn tint. */
@SuppressLint("ViewConstructor")
class ImageLeafView(context: Context, private val owner: ElpianView, private val onResult: (String, Bitmap?) -> Unit) : View(context) {
    private var src: String? = null
    private var bitmap: Bitmap? = null
    var fit: String? = "contain"
        set(v) { field = v; invalidate() }
    var alignment: Alignment = Alignment.center
        set(v) { field = v; invalidate() }
    var tint: Int? = null
        set(v) {
            field = v
            paint.colorFilter = v?.let { PorterDuffColorFilter(it, PorterDuff.Mode.SRC_IN) }
            invalidate()
        }
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)

    fun setSrc(s: String?) {
        if (s == src) return
        src = s
        bitmap = null
        invalidate()
        if (s.isNullOrEmpty()) return
        owner.host.images.load(s) { bmp ->
            if (src != s) return@load
            bitmap = bmp
            invalidate()
            onResult(s, bmp)
        }
    }

    override fun onDraw(canvas: Canvas) {
        val bmp = bitmap ?: return
        if (bmp.width <= 0 || bmp.height <= 0 || width <= 0 || height <= 0) return
        val r = fitRect(fit, bmp.width.toFloat(), bmp.height.toFloat(), width.toFloat(), height.toFloat(), alignment, owner.density)
        val save = canvas.save()
        canvas.clipRect(0, 0, width, height)
        canvas.drawBitmap(bmp, null, r, paint)
        canvas.restoreToCount(save)
    }
}

// ---------------------------------------------------------------------------
// Video and audio
// ---------------------------------------------------------------------------

/**
 * The `video` / `audio` view kinds on MediaPlayer: a TextureView for video
 * (so transforms, opacity and clips apply), BoxFit, poster, loop, muted,
 * autoplay, native controls (MediaController), WebVTT/SRT text tracks and
 * load / play / pause / ended / error / volumechange / seeked / timeupdate events.
 */
@SuppressLint("ViewConstructor")
class MediaLeaf(context: Context, private val owner: ElpianView, private val video: Boolean) : FrameLayout(context) {
    private var player: MediaPlayer? = null
    private var prepared = false
    private var src: String? = null
    private val texture: TextureView? = if (video) TextureView(context) else null
    private var surface: Surface? = null
    private val poster = ImageLeafView(context, owner) { _, _ -> }
    private val caption = TextView(context)
    private var controller: MediaController? = null
    private val handler = Handler(Looper.getMainLooper())
    private var lastTime = 0L
    var autoplay = false
    var loop = false
        set(v) { field = v; player?.isLooping = v }
    var muted = false
        set(v) {
            val changed = field != v
            field = v
            player?.let { val vol = if (v) 0f else 1f; it.setVolume(vol, vol) }
            if (changed && prepared) emitState("volumechange")
        }
    var controls = true
    var fit: String = "contain"
        set(v) { field = v; updateTransform() }
    private var tracks: List<Map<String, Any?>> = emptyList()
    private var videoW = 0
    private var videoH = 0

    private val ticker = object : Runnable {
        override fun run() {
            val p = player ?: return
            if (prepared && p.isPlaying) {
                emit("timeupdate", mapOf("currentTime" to p.currentPosition / 1000.0, "duration" to duration()))
                handler.postDelayed(this, 250)
            }
        }
    }

    init {
        setBackgroundColor(if (video) Color.BLACK else Color.TRANSPARENT)
        texture?.let { tv ->
            addView(tv, LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
            tv.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                override fun onSurfaceTextureAvailable(st: SurfaceTexture, width: Int, height: Int) {
                    surface = Surface(st)
                    player?.setSurface(surface)
                    updateTransform()
                }
                override fun onSurfaceTextureSizeChanged(st: SurfaceTexture, width: Int, height: Int) = updateTransform()
                override fun onSurfaceTextureDestroyed(st: SurfaceTexture): Boolean {
                    player?.setSurface(null)
                    surface?.release()
                    surface = null
                    return true
                }
                override fun onSurfaceTextureUpdated(st: SurfaceTexture) {}
            }
        }
        if (video) addView(poster, LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        caption.setTextColor(Color.WHITE)
        caption.setBackgroundColor(0x99000000.toInt())
        caption.setTextSize(TypedValue.COMPLEX_UNIT_PX, 14 * owner.density)
        caption.gravity = Gravity.CENTER
        caption.visibility = GONE
        val lp = LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL)
        lp.bottomMargin = (24 * owner.density).roundToInt()
        addView(caption, lp)
    }

    private fun duration(): Double = player?.takeIf { prepared }?.duration?.let { if (it < 0) Double.NaN else it / 1000.0 } ?: Double.NaN

    private fun emit(type: String, value: Any?) {
        owner.host.emit(ViewEvent(id = owner.viewId, type = type, value = value))
    }

    private fun emitState(type: String) {
        val p = player
        emit(type, mapOf("currentTime" to (if (prepared && p != null) p.currentPosition / 1000.0 else 0.0), "duration" to duration(), "volume" to (if (muted) 0.0 else 1.0), "muted" to muted))
    }

    fun setPoster(url: String?) {
        poster.fit = fit
        poster.setSrc(url)
    }

    fun setTracks(list: List<Map<String, Any?>>) {
        tracks = list
        if (prepared) loadTracks()
    }

    fun setSrc(s: String?) {
        if (s == src) return
        src = s
        release()
        if (s.isNullOrEmpty()) return
        val p = MediaPlayer()
        player = p
        prepared = false
        try {
            when {
                s.startsWith("asset:") || s.startsWith("file:///android_asset/") -> {
                    val path = s.removePrefix("file:///android_asset/").removePrefix("asset:").trimStart('/')
                    val fd = context.assets.openFd(path)
                    p.setDataSource(fd.fileDescriptor, fd.startOffset, fd.length)
                    fd.close()
                }
                s.startsWith("/") -> p.setDataSource(s)
                else -> p.setDataSource(context, Uri.parse(s))
            }
        } catch (e: Throwable) {
            emit("error", mapOf("message" to (e.message ?: e.toString())))
            return
        }
        p.isLooping = loop
        if (muted) p.setVolume(0f, 0f)
        surface?.let { p.setSurface(it) }
        p.setOnPreparedListener {
            prepared = true
            videoW = it.videoWidth
            videoH = it.videoHeight
            updateTransform()
            emit("load", mapOf("width" to videoW.toDouble(), "height" to videoH.toDouble(), "duration" to duration()))
            loadTracks()
            if (autoplay) play()
        }
        p.setOnVideoSizeChangedListener { _, w, h ->
            videoW = w
            videoH = h
            updateTransform()
        }
        p.setOnCompletionListener {
            emitState("ended")
            if (!loop) emitState("pause")
        }
        p.setOnErrorListener { _, what, extra ->
            emit("error", mapOf("code" to what.toDouble(), "extra" to extra.toDouble()))
            true
        }
        p.setOnSeekCompleteListener { emitState("seeked") }
        p.setOnInfoListener { _, what, _ ->
            if (what == MediaPlayer.MEDIA_INFO_VIDEO_RENDERING_START) poster.visibility = GONE
            false
        }
        p.setOnTimedTextListener { _, text ->
            val t = text?.text
            caption.text = t ?: ""
            caption.visibility = if (t.isNullOrEmpty()) GONE else VISIBLE
        }
        try {
            p.prepareAsync()
        } catch (e: Throwable) {
            emit("error", mapOf("message" to (e.message ?: e.toString())))
        }
    }

    private fun updateTransform() {
        val tv = texture ?: return
        val w = tv.width.toFloat()
        val h = tv.height.toFloat()
        if (w <= 0 || h <= 0 || videoW <= 0 || videoH <= 0) return
        val r = fitRect(fit, videoW.toFloat(), videoH.toFloat(), w, h, Alignment.center, owner.density)
        val m = Matrix()
        m.setScale(r.width() / w, r.height() / h)
        m.postTranslate(r.left, r.top)
        tv.setTransform(m)
        tv.invalidate()
    }

    private fun loadTracks() {
        val p = player ?: return
        val list = tracks.filter { (P.str(it["kind"]) ?: "subtitles") in listOf("subtitles", "captions") }
        if (list.isEmpty()) return
        val chosen = list.firstOrNull { it["default"] == true } ?: return
        val url = P.str(chosen["src"]) ?: return
        IO.execute {
            try {
                val raw = if (url.startsWith("asset:")) context.assets.open(url.removePrefix("asset:").trimStart('/')).use { it.readBytes().toString(Charsets.UTF_8) }
                else (URL(url).openConnection() as HttpURLConnection).run { connectTimeout = 15000; inputStream.use { it.readBytes().toString(Charsets.UTF_8) } }
                val srt = vttToSrt(raw)
                val f = File.createTempFile("elpian-track", ".srt", context.cacheDir)
                f.writeText(srt)
                handler.post {
                    if (player !== p) return@post
                    try {
                        p.addTimedTextSource(f.absolutePath, MediaPlayer.MEDIA_MIMETYPE_TEXT_SUBRIP)
                        val idx = p.trackInfo.indexOfLast { it.trackType == MediaPlayer.TrackInfo.MEDIA_TRACK_TYPE_TIMEDTEXT }
                        if (idx >= 0) p.selectTrack(idx)
                    } catch (_: Throwable) {
                    }
                }
            } catch (_: Throwable) {
            }
        }
    }

    private fun vttToSrt(raw: String): String {
        if (!raw.trimStart().startsWith("WEBVTT")) return raw
        val out = StringBuilder()
        var n = 1
        val blocks = raw.replace("\r\n", "\n").split(Regex("\n\n+"))
        val time = Regex("((?:\\d+:)?\\d{2}:\\d{2})\\.(\\d{3})")
        for (b in blocks) {
            val lines = b.split('\n').toMutableList()
            val ti = lines.indexOfFirst { it.contains("-->") }
            if (ti < 0) continue
            val timing = lines[ti].split(Regex("\\s+-->\\s+")).let { parts ->
                parts.take(2).joinToString(" --> ") { part ->
                    val t = part.trim().split(' ')[0]
                    val full = if (t.count { it == ':' } == 1) "00:$t" else t
                    time.replace(full) { "${it.groupValues[1]},${it.groupValues[2]}" }
                }
            }
            out.append(n++).append('\n').append(timing).append('\n')
            out.append(lines.drop(ti + 1).joinToString("\n")).append("\n\n")
        }
        return out.toString()
    }

    fun play() {
        val p = player ?: return
        if (!prepared) {
            autoplay = true
            return
        }
        if (!p.isPlaying) {
            p.start()
            poster.visibility = GONE
            emitState("play")
            handler.removeCallbacks(ticker)
            handler.post(ticker)
        }
    }

    fun pause() {
        val p = player ?: return
        if (prepared && p.isPlaying) {
            p.pause()
            emitState("pause")
        }
    }

    fun seek(seconds: Double) {
        val p = player ?: return
        if (prepared) p.seekTo((seconds * 1000).roundToInt())
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!controls) return false
        if (event.actionMasked == MotionEvent.ACTION_UP) showControls()
        return true
    }

    private fun showControls() {
        val c = controller ?: MediaController(context).also { mc ->
            mc.setMediaPlayer(object : MediaController.MediaPlayerControl {
                override fun start() = play()
                override fun pause() = this@MediaLeaf.pause()
                override fun getDuration(): Int = if (prepared) player?.duration ?: 0 else 0
                override fun getCurrentPosition(): Int = if (prepared) player?.currentPosition ?: 0 else 0
                override fun seekTo(pos: Int) = seek(pos / 1000.0)
                override fun isPlaying(): Boolean = prepared && player?.isPlaying == true
                override fun getBufferPercentage(): Int = 0
                override fun canPause(): Boolean = true
                override fun canSeekBackward(): Boolean = true
                override fun canSeekForward(): Boolean = true
                override fun getAudioSessionId(): Int = player?.audioSessionId ?: 0
            })
            mc.setAnchorView(this)
            controller = mc
        }
        try {
            c.show()
        } catch (_: Throwable) {
        }
    }

    fun release() {
        handler.removeCallbacks(ticker)
        try {
            controller?.hide()
        } catch (_: Throwable) {
        }
        player?.let {
            try {
                it.release()
            } catch (_: Throwable) {
            }
        }
        player = null
        prepared = false
        if (video) poster.visibility = VISIBLE
    }

    override fun onDetachedFromWindow() {
        try {
            controller?.hide()
        } catch (_: Throwable) {
        }
        super.onDetachedFromWindow()
    }

    companion object {
        private val IO = Executors.newSingleThreadExecutor()
    }
}

// ---------------------------------------------------------------------------
// Web
// ---------------------------------------------------------------------------

/** The `web` view kind: a WebView showing `src` or inline `html`. */
@SuppressLint("ViewConstructor", "SetJavaScriptEnabled")
class WebLeaf(context: Context, private val owner: ElpianView) : FrameLayout(context) {
    private val web: WebView? = try {
        WebView(context)
    } catch (e: Throwable) {
        null
    }
    private var loaded: String? = null

    init {
        web?.let { w ->
            w.settings.javaScriptEnabled = true
            w.settings.domStorageEnabled = true
            w.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView?, url: String?) {
                    owner.host.emit(ViewEvent(id = owner.viewId, type = "load"))
                }
            }
            addView(w, LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        }
    }

    fun apply(all: Map<String, Any?>, patch: Map<String, Any?>) {
        val w = web ?: return
        if (patch.containsKey("javascript")) w.settings.javaScriptEnabled = all["javascript"] != false
        val html = P.str(all["html"])
        if (patch.containsKey("html") && html != null) {
            loaded = null
            w.loadDataWithBaseURL(null, html, "text/html", "utf-8", null)
        } else if (patch.containsKey("src")) {
            val src = P.str(all["src"])
            if (!src.isNullOrEmpty() && src != loaded) {
                loaded = src
                w.loadUrl(if (src.startsWith("asset:")) "file:///android_asset/" + src.removePrefix("asset:").trimStart('/') else src)
            }
        }
    }

    fun release() {
        web?.let {
            it.stopLoading()
            it.destroy()
        }
    }
}
