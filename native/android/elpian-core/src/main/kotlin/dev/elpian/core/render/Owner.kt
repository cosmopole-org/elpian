package dev.elpian.core.render

import dev.elpian.core.platform.Platform
import dev.elpian.core.util.stableKey

/** An animation clock client. */
interface Ticker {
    /** Advance to [nowMs]; return false once finished (it is then removed). */
    fun tick(nowMs: Double): Boolean
}

/**
 * One per mounted surface: owns the root render object, schedules frames,
 * drives tickers, runs layout and hands view operations to the platform
 * (render/owner.ts).
 */
class RenderOwner(val surface: String, val platform: Platform) {
    var root: RenderObject? = null
    val compositor = Compositor(this)
    private val tickers = LinkedHashSet<Ticker>()
    private var frameRequested = false
    private val dirtyPaint = HashSet<RenderObject>()
    private var needsFrame = false
    var isDisposed = false
        private set
    private val textCache = HashMap<String, TextMetrics>()
    private var nextViewId = 1
    /** When set, the root lays out with these constraints instead of the tight viewport. */
    var rootConstraints: Constraints? = null
    /** Monotonic frame clock (ms) as of the last tick. */
    var frameTime = 0.0
    /** Accessibility text scale. */
    var textScale = 1.0
    /** Called after each committed frame with the op count. */
    var onFrameCommitted: ((Int) -> Unit)? = null

    fun allocateViewId(): Int = nextViewId++

    fun requestVisualUpdate() {
        if (isDisposed) return
        needsFrame = true
        if (frameRequested) return
        frameRequested = true
        platform.requestFrame { t ->
            frameRequested = false
            flush(t)
        }
    }

    fun markPaintDirty(ro: RenderObject) {
        dirtyPaint.add(ro)
        requestVisualUpdate()
    }

    fun addTicker(t: Ticker) {
        tickers.add(t)
        requestVisualUpdate()
    }

    fun removeTicker(t: Ticker) {
        tickers.remove(t)
    }

    val hasActiveTickers: Boolean get() = tickers.isNotEmpty()

    /** Run a frame now: tick animations, lay out, composite and commit. */
    fun flush(timeMs: Double = platform.now()): List<ViewOp> {
        if (isDisposed) return emptyList()
        frameTime = timeMs
        needsFrame = false
        for (t in tickers.toList()) {
            val alive = try {
                t.tick(timeMs)
            } catch (e: Exception) {
                platform.log("error", "Elpian animation tick failed: $e")
                false
            }
            if (!alive) tickers.remove(t)
        }
        val r = root
        val ops = if (r != null) {
            val vp = platform.viewport(surface)
            r.layout(rootConstraints ?: tight(vp.width, vp.height))
            updateHeroes(r)
            compositor.composite(r)
        } else compositor.clear()
        dirtyPaint.clear()
        if (ops.isNotEmpty()) platform.commit(surface, ops)
        onFrameCommitted?.invoke(ops.size)
        if (tickers.isNotEmpty() || needsFrame) requestVisualUpdate()
        return ops
    }

    private var heroes = HashMap<String, Pair<RenderObject, DoubleArray>>()

    /** A hero whose tag now belongs to a different object flies from the old rect. */
    private fun updateHeroes(root: RenderObject) {
        val next = HashMap<String, Pair<RenderObject, DoubleArray>>()
        root.visit { ro ->
            val tag = ro.props["tag"]
            if (ro.type == "hero" && tag != null) next[tag.toString()] = ro to compositor.globalFrame(ro)
        }
        for ((tag, entry) in next) {
            val prev = heroes[tag]
            if (prev != null && prev.first !== entry.first) (entry.first as? HeroFlight)?.flyFrom(prev.second, this)
        }
        if (next.isNotEmpty() || heroes.isNotEmpty()) heroes = next
    }

    fun measureText(spec: TextSpec, maxWidth: Double): TextMetrics {
        val width = if (maxWidth.isFinite()) maxOf(0.0, Math.round(maxWidth * 100) / 100.0) else INF
        val key = "$width|${stableKey(spec.toString())}"
        textCache[key]?.let { return it }
        val metrics = platform.measureText(spec, width)
        if (textCache.size > 4000) textCache.clear()
        textCache[key] = metrics
        return metrics
    }

    /** Fonts or the text scale changed: everything is re-measured. */
    fun invalidateMeasurements() {
        textCache.clear()
        root?.visit { it.needsLayout = true }
        requestVisualUpdate()
    }

    private val imageSizes = HashMap<String, Any>()

    /** Natural size of [src], or null while unknown (a load is requested). */
    fun imageSize(src: String): Size? {
        when (val known = imageSizes[src]) {
            is Size -> return known
            null -> {
                val direct = platform.imageSize(src)
                if (direct != null) {
                    imageSizes[src] = direct
                    return direct
                }
                imageSizes[src] = "pending"
                platform.preloadImage(src)
            }
        }
        return null
    }

    fun imageLoaded(src: String, width: Double, height: Double) {
        imageSizes[src] = if (width > 0 && height > 0) Size(width, height) else "error"
        root?.visit { ro -> if (ro.type == "image" && ro.props["src"] == src) ro.markNeedsLayout() }
    }

    /** Route a platform event to the render object owning [event]'s view. */
    fun dispatchViewEvent(event: ViewEvent) {
        compositor.objectFor(event.id)?.handleViewEvent(event)
    }

    fun dispose() {
        if (isDisposed) return
        tickers.clear()
        val ops = compositor.clear()
        if (ops.isNotEmpty()) platform.commit(surface, ops)
        root?.detach()
        root = null
        isDisposed = true
    }
}

/** Render objects that animate in from another object's rect (Hero). */
interface HeroFlight {
    fun flyFrom(rect: DoubleArray, owner: RenderOwner)
}
