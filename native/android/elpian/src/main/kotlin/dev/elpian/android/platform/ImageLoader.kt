package dev.elpian.android.platform

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.LruCache
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLDecoder
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.max

/**
 * Decodes images off the UI thread and caches them: `http(s):` (HttpURLConnection),
 * `asset:` / `file:///android_asset/` (AssetManager), `file:` and absolute
 * paths, `content:` / `android.resource:` (ContentResolver) and `data:` URIs.
 * Relative paths resolve against the app's assets. Natural sizes are the
 * encoded image's pixel size, even when a huge image is decoded downsampled.
 */
class ImageLoader(context: Context, private val maxDimension: Int = 4096) {
    private val context = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newFixedThreadPool(4) { r -> Thread(r, "elpian-images").also { it.isDaemon = true } }
    private val cache = object : LruCache<String, Bitmap>(cacheBytes()) {
        override fun sizeOf(key: String, value: Bitmap): Int = value.allocationByteCount
    }
    private val sizes = HashMap<String, IntArray>()
    private val failed = HashSet<String>()
    private val waiting = HashMap<String, MutableList<(Bitmap?) -> Unit>>()
    private val listeners = LinkedHashSet<(String, Int, Int) -> Unit>()

    private fun cacheBytes(): Int = (Runtime.getRuntime().maxMemory() / 8).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()

    /** Listen for natural sizes (0×0 = failed); returns an unsubscriber. */
    fun onImageLoaded(listener: (src: String, width: Int, height: Int) -> Unit): () -> Unit {
        listeners.add(listener)
        return { listeners.remove(listener) }
    }

    /** The natural pixel size once known. */
    fun size(src: String): IntArray? = sizes[src]

    fun isFailed(src: String): Boolean = src in failed

    /** Report a size learned elsewhere (e.g. a view decoded it). */
    fun reportSize(src: String, width: Int, height: Int) {
        if (width > 0 && height > 0) {
            val prev = sizes[src]
            if (prev != null && prev[0] == width && prev[1] == height) return
            sizes[src] = intArrayOf(width, height)
            failed.remove(src)
        } else {
            if (src in failed) return
            failed.add(src)
        }
        for (l in listeners.toList()) l(src, width, height)
    }

    /** Load [src]; [callback] runs on the UI thread. */
    fun load(src: String, callback: (Bitmap?) -> Unit) {
        cache.get(src)?.let {
            callback(it)
            return
        }
        val list = waiting[src]
        if (list != null) {
            list.add(callback)
            return
        }
        waiting[src] = mutableListOf(callback)
        executor.execute {
            var natural = intArrayOf(0, 0)
            val bmp = try {
                decode(src) { w, h -> natural = intArrayOf(w, h) }
            } catch (_: Throwable) {
                null
            }
            main.post {
                if (bmp != null) cache.put(src, bmp)
                if (bmp != null) reportSize(src, if (natural[0] > 0) natural[0] else bmp.width, if (natural[1] > 0) natural[1] else bmp.height) else reportSize(src, 0, 0)
                val cbs = waiting.remove(src) ?: return@post
                for (cb in cbs) cb(bmp)
            }
        }
    }

    /** Start loading [src] (the core's preloadImage). */
    fun preload(src: String) {
        if (cache.get(src) != null || waiting.containsKey(src)) return
        load(src) {}
    }

    fun clear() {
        cache.evictAll()
    }

    private fun bytes(src: String): ByteArray? {
        val s = src.trim()
        return when {
            s.startsWith("data:") -> {
                val comma = s.indexOf(',')
                if (comma < 0) return null
                val meta = s.substring(5, comma)
                val payload = s.substring(comma + 1)
                if (meta.endsWith(";base64")) Base64.decode(payload, Base64.DEFAULT) else URLDecoder.decode(payload, "UTF-8").toByteArray()
            }
            s.startsWith("http://") || s.startsWith("https://") -> {
                val conn = URL(s).openConnection() as HttpURLConnection
                conn.connectTimeout = 15000
                conn.readTimeout = 30000
                conn.instanceFollowRedirects = true
                try {
                    if (conn.responseCode !in 200..299) return null
                    conn.inputStream.use { it.readBytes() }
                } finally {
                    conn.disconnect()
                }
            }
            s.startsWith("asset:") || s.startsWith("file:///android_asset/") -> {
                val path = s.removePrefix("file:///android_asset/").removePrefix("asset:").trimStart('/')
                context.assets.open(path).use { it.readBytes() }
            }
            s.startsWith("file://") -> File(Uri.parse(s).path ?: return null).readBytes()
            s.startsWith("/") -> File(s).readBytes()
            s.startsWith("content:") || s.startsWith("android.resource:") -> context.contentResolver.openInputStream(Uri.parse(s))?.use { it.readBytes() }
            else -> context.assets.open(s.trimStart('/')).use { it.readBytes() }
        }
    }

    private fun decode(src: String, natural: (Int, Int) -> Unit): Bitmap? {
        val data = bytes(src) ?: return null
        val bounds = BitmapFactory.Options()
        bounds.inJustDecodeBounds = true
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        natural(bounds.outWidth, bounds.outHeight)
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / sample > maxDimension) sample *= 2
        val opts = BitmapFactory.Options()
        opts.inSampleSize = sample
        opts.inPreferredConfig = Bitmap.Config.ARGB_8888
        return BitmapFactory.decodeByteArray(data, 0, data.size, opts)
    }
}
