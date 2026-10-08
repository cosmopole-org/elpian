package dev.elpian.android.render

import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import dev.elpian.core.css.Alignment
import dev.elpian.core.css.Border
import dev.elpian.core.css.BorderRadius
import dev.elpian.core.css.BorderSide
import dev.elpian.core.css.BorderStyleName
import dev.elpian.core.css.BoxShadow
import dev.elpian.core.css.Gradient
import dev.elpian.core.render.paint.DecorationImage
import dev.elpian.core.render.paint.Outline
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/** Geometry helpers shared by decorations, clips and controls (all in device px). */
object Shapes {
    /** Eight radii (x,y per corner, clockwise from top-left), scaled down as CSS / Flutter do when they overlap. */
    fun radii(r: BorderRadius?, w: Float, h: Float, density: Float): FloatArray? {
        if (r == null || r.isZero) return null
        val tl = (r.topLeft * density).toFloat()
        val tr = (r.topRight * density).toFloat()
        val br = (r.bottomRight * density).toFloat()
        val bl = (r.bottomLeft * density).toFloat()
        return scaleRadii(floatArrayOf(tl, tl, tr, tr, br, br, bl, bl), w, h)
    }

    fun scaleRadii(a: FloatArray, w: Float, h: Float): FloatArray {
        var f = 1f
        fun lim(len: Float, s: Float) {
            if (s > 0 && len / s < f) f = len / s
        }
        lim(w, a[0] + a[2])
        lim(w, a[6] + a[4])
        lim(h, a[1] + a[7])
        lim(h, a[3] + a[5])
        if (f < 1f) for (i in a.indices) a[i] = a[i] * max(0f, f)
        return a
    }

    /** The outline of a box: a (rounded) rect or an inscribed oval. */
    fun path(rect: RectF, radii: FloatArray?, oval: Boolean, out: Path = Path()): Path {
        out.reset()
        when {
            oval -> out.addOval(rect, Path.Direction.CW)
            radii != null -> out.addRoundRect(rect, radii, Path.Direction.CW)
            else -> out.addRect(rect, Path.Direction.CW)
        }
        return out
    }

    /** Radii grown (or shrunk, for negative values) by [dx]/[dy] per axis, never below 0. */
    fun adjust(radii: FloatArray?, left: Float, top: Float, right: Float, bottom: Float): FloatArray? {
        if (radii == null) return null
        return floatArrayOf(
            max(0f, radii[0] + left), max(0f, radii[1] + top),
            max(0f, radii[2] + right), max(0f, radii[3] + top),
            max(0f, radii[4] + right), max(0f, radii[5] + bottom),
            max(0f, radii[6] + left), max(0f, radii[7] + bottom),
        )
    }
}

/**
 * Paints a view's decoration — Flutter's BoxDecoration plus the CSS extras the
 * core forwards (inset shadows, border styles, outline) — onto the view's own
 * canvas, so the view's frame stays the border box its children lay out in and
 * a clip on the children never clips the shadow.
 */
class DecorationPainter(private val host: android.view.View, private val images: ImageSource) {
    var background: Int? = null
    var gradients: List<Gradient>? = null
    var image: DecorationImage? = null
        set(v) {
            if (field?.src != v?.src) bitmap = null
            field = v
            v?.src?.let { src -> if (src.isNotEmpty()) loadImage(src) }
        }
    var border: Border? = null
    var radius: BorderRadius? = null
    var oval = false
    var shadows: List<BoxShadow>? = null
    var outline: Outline? = null

    private var bitmap: Bitmap? = null
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val path = Path()
    private val path2 = Path()
    private val rect = RectF()
    private val shadowCache = HashMap<ShadowKey, Bitmap>()

    private data class ShadowKey(val w: Int, val h: Int, val radii: List<Float>?, val oval: Boolean, val sigma: Float, val inset: Boolean, val hole: List<Float>?)

    val isEmpty: Boolean
        get() = background == null && gradients.isNullOrEmpty() && image == null && border == null && shadows.isNullOrEmpty() && outline == null

    private fun loadImage(src: String) {
        images.load(src) { bmp ->
            if (image?.src == src) {
                bitmap = bmp
                host.invalidate()
            }
        }
    }

    fun clearCaches() {
        shadowCache.clear()
    }

    /** Paint everything at a box of [w]×[h] device px. */
    fun draw(canvas: Canvas, w: Float, h: Float, density: Float) {
        if (w <= 0 && h <= 0) return
        val radii = if (oval) null else Shapes.radii(radius, w, h, density)
        rect.set(0f, 0f, w, h)
        // 1. Outer shadows (Flutter paints them in list order, under the box).
        shadows?.forEach { if (!it.inset) drawOuterShadow(canvas, it, w, h, radii, density) }
        val shape = Shapes.path(rect, radii, oval, path)
        // 2. Background colour.
        background?.let { c ->
            paint.reset(); paint.isAntiAlias = true
            paint.color = c
            canvas.drawPath(shape, paint)
        }
        // 3. Image (the bottom-most CSS layer), then gradients bottom-first.
        val img = image
        val bmp = bitmap
        if (img != null && bmp != null) drawImage(canvas, img, bmp, shape, w, h, density)
        gradients?.forEach { g ->
            val shader = Paints.gradientShader(g, w, h) ?: return@forEach
            paint.reset(); paint.isAntiAlias = true
            paint.shader = shader
            canvas.drawPath(shape, paint)
        }
        // 4. Inset shadows inside the padding box.
        shadows?.forEach { if (it.inset) drawInsetShadow(canvas, it, w, h, radii, density) }
        // 5. Border and outline.
        border?.let { drawBorder(canvas, it, w, h, radii, density) }
        outline?.let { drawOutline(canvas, it, w, h, radii, density) }
    }

    // ---------------------------------------------------------------------
    // Shadows
    // ---------------------------------------------------------------------

    private fun drawOuterShadow(canvas: Canvas, s: BoxShadow, w: Float, h: Float, radii: FloatArray?, density: Float) {
        if ((s.color ushr 24) == 0) return
        val spread = (s.spread * density).toFloat()
        val dx = (s.dx * density).toFloat()
        val dy = (s.dy * density).toFloat()
        val sw = w + 2 * spread
        val sh = h + 2 * spread
        if (sw <= 0 || sh <= 0) return
        val r = Shapes.adjust(radii, spread, spread, spread, spread)
        val sigma = (Paints.sigma(s.blur) * density).toFloat()
        paint.reset(); paint.isAntiAlias = true; paint.isFilterBitmap = true
        paint.color = s.color
        if (sigma <= 0f) {
            rect.set(-spread + dx, -spread + dy, w + spread + dx, h + spread + dy)
            canvas.drawPath(Shapes.path(rect, r, oval, path2), paint)
            return
        }
        val pad = ceil(3 * sigma)
        val key = ShadowKey(ceil(sw).toInt(), ceil(sh).toInt(), r?.toList(), oval, sigma, false, null)
        val bmp = shadowCache[key] ?: blurredMask(sw, sh, pad, sigma) { c, p -> c.drawPath(Shapes.path(RectF(0f, 0f, sw, sh), r, oval, Path()), p) }?.also { shadowCache[key] = it } ?: return
        rect.set(-spread - pad + dx, -spread - pad + dy, w + spread + pad + dx, h + spread + pad + dy)
        canvas.drawBitmap(bmp, null, rect, paint)
    }

    private fun drawInsetShadow(canvas: Canvas, s: BoxShadow, w: Float, h: Float, radii: FloatArray?, density: Float) {
        if ((s.color ushr 24) == 0) return
        val ins = border?.insets
        val l = ((ins?.left ?: 0.0) * density).toFloat()
        val t = ((ins?.top ?: 0.0) * density).toFloat()
        val rr = ((ins?.right ?: 0.0) * density).toFloat()
        val b = ((ins?.bottom ?: 0.0) * density).toFloat()
        val iw = w - l - rr
        val ih = h - t - b
        if (iw <= 0 || ih <= 0) return
        val innerRadii = Shapes.adjust(radii, -l, -t, -rr, -b)
        val spread = (s.spread * density).toFloat()
        val dx = (s.dx * density).toFloat()
        val dy = (s.dy * density).toFloat()
        val sigma = (Paints.sigma(s.blur) * density).toFloat()
        val holeRadii = Shapes.adjust(innerRadii, -spread, -spread, -spread, -spread)
        val hole = RectF(spread + dx, spread + dy, iw - spread + dx, ih - spread + dy)
        canvas.save()
        canvas.translate(l, t)
        rect.set(0f, 0f, iw, ih)
        canvas.clipPath(Shapes.path(rect, innerRadii, oval, path2))
        paint.reset(); paint.isAntiAlias = true; paint.isFilterBitmap = true
        paint.color = s.color
        val far = 3 * sigma + abs(dx) + abs(dy) + abs(spread) + 1
        val shape: (Canvas, Paint) -> Unit = { c, p ->
            val ring = Path()
            ring.fillType = Path.FillType.EVEN_ODD
            ring.addRect(-far, -far, iw + far, ih + far, Path.Direction.CW)
            if (hole.width() > 0 && hole.height() > 0) Shapes.path(hole, holeRadii, oval, Path()).let { ring.addPath(it) }
            c.drawPath(ring, p)
        }
        if (sigma <= 0f) {
            shape(canvas, paint)
        } else {
            val key = ShadowKey(ceil(iw).toInt(), ceil(ih).toInt(), innerRadii?.toList(), oval, sigma, true, listOf(hole.left, hole.top, hole.right, hole.bottom) + (holeRadii?.toList() ?: emptyList()))
            val bmp = shadowCache[key] ?: blurredMask(iw, ih, 0f, sigma, shape)?.also { shadowCache[key] = it }
            if (bmp != null) {
                rect.set(0f, 0f, iw, ih)
                canvas.drawBitmap(bmp, null, rect, paint)
            }
        }
        canvas.restore()
    }

    /**
     * Rasterise [draw] blurred with a Gaussian of [sigma] device px into an
     * alpha mask of ([w] + 2·[pad]) × ([h] + 2·[pad]), downsampled for wide blurs.
     */
    private fun blurredMask(w: Float, h: Float, pad: Float, sigma: Float, draw: (Canvas, Paint) -> Unit): Bitmap? {
        val scale = if (sigma <= 8f) 1f else max(0.125f, 8f / sigma)
        val bw = max(1, ceil((w + 2 * pad) * scale).toInt())
        val bh = max(1, ceil((h + 2 * pad) * scale).toInt())
        if (bw.toLong() * bh > 16_000_000L) return null
        val bmp = try {
            Bitmap.createBitmap(bw, bh, Bitmap.Config.ALPHA_8)
        } catch (_: OutOfMemoryError) {
            return null
        }
        val c = Canvas(bmp)
        c.scale(bw / (w + 2 * pad), bh / (h + 2 * pad))
        c.translate(pad, pad)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        p.color = 0xff000000.toInt()
        val s = sigma * scale
        // BlurMaskFilter converts its radius with the same formula as Flutter.
        val radius = if (s > 0.5f) (s - 0.5f) / 0.57735f else 0.01f
        p.maskFilter = BlurMaskFilter(max(0.01f, radius / scale), BlurMaskFilter.Blur.NORMAL)
        draw(c, p)
        return bmp
    }

    // ---------------------------------------------------------------------
    // Background image (CSS background-size / position / repeat)
    // ---------------------------------------------------------------------

    private fun drawImage(canvas: Canvas, img: DecorationImage, bmp: Bitmap, shape: Path, w: Float, h: Float, density: Float) {
        val nw = bmp.width * density
        val nh = bmp.height * density
        var tw: Float
        var th: Float
        val size = img.size
        if (size != null && (size.width != null || size.height != null)) {
            val sw = size.width?.let { (it * density).toFloat() }
            val sh = size.height?.let { (it * density).toFloat() }
            tw = sw ?: if (sh != null) sh * nw / nh else nw
            th = sh ?: if (sw != null) sw * nh / nw else nh
        } else {
            when (P.fit(img.fit)) {
                "cover" -> { val s = max(w / nw, h / nh); tw = nw * s; th = nh * s }
                "contain", "scaleDown" -> { val s = min(w / nw, h / nh); tw = nw * s; th = nh * s }
                "fill" -> { tw = w; th = h }
                "fitWidth" -> { tw = w; th = w * nh / nw }
                "fitHeight" -> { th = h; tw = h * nw / nh }
                else -> { tw = nw; th = nh }
            }
        }
        if (tw <= 0 || th <= 0) return
        val a = img.alignment ?: Alignment.center
        val x = ((w - tw) * (a.x + 1) / 2).toFloat()
        val y = ((h - th) * (a.y + 1) / 2).toFloat()
        val repeat = img.repeat ?: "no-repeat"
        val rx = repeat == "repeat" || repeat == "repeat-x" || repeat == "space" || repeat == "round"
        val ry = repeat == "repeat" || repeat == "repeat-y" || repeat == "space" || repeat == "round"
        canvas.save()
        canvas.clipPath(shape)
        paint.reset(); paint.isAntiAlias = true; paint.isFilterBitmap = true
        if (!rx && !ry) {
            rect.set(x, y, x + tw, y + th)
            canvas.drawBitmap(bmp, null, rect, paint)
        } else {
            val shader = BitmapShader(bmp, if (rx) Shader.TileMode.REPEAT else Shader.TileMode.CLAMP, if (ry) Shader.TileMode.REPEAT else Shader.TileMode.CLAMP)
            val m = Matrix()
            m.setScale(tw / bmp.width, th / bmp.height)
            m.postTranslate(x, y)
            shader.setLocalMatrix(m)
            paint.shader = shader
            rect.set(if (rx) 0f else x, if (ry) 0f else y, if (rx) w else x + tw, if (ry) h else y + th)
            canvas.drawRect(rect, paint)
        }
        canvas.restore()
    }

    // ---------------------------------------------------------------------
    // Borders
    // ---------------------------------------------------------------------

    private fun sideWidth(s: BorderSide, density: Float): Float = if (s.style == BorderStyleName.none || s.width <= 0) 0f else (s.width * density).toFloat()

    private fun drawBorder(canvas: Canvas, b: Border, w: Float, h: Float, radii: FloatArray?, density: Float) {
        val t = sideWidth(b.top, density)
        val r = sideWidth(b.right, density)
        val bo = sideWidth(b.bottom, density)
        val l = sideWidth(b.left, density)
        if (t == 0f && r == 0f && bo == 0f && l == 0f) return
        val sides = listOf(b.top to t, b.right to r, b.bottom to bo, b.left to l)
        val visible = sides.filter { it.second > 0f }
        val uniform = visible.all { it.first.color == visible[0].first.color && it.first.style == visible[0].first.style } && visible.size == 4
        val uniformWidth = uniform && t == r && r == bo && bo == l
        if (uniform) {
            val style = visible[0].first.style
            paintBorderRegion(canvas, style, visible[0].first.color, w, h, radii, t, r, bo, l, uniformWidth)
            return
        }
        // Per side: clip to the side's trapezoid (outer corner → inner corner), like CSS.
        sides.forEachIndexed { i, (side, width) ->
            if (width <= 0f || (side.color ushr 24) == 0) return@forEachIndexed
            // Extend the trapezoid outward so antialiased edges are not cut.
            canvas.save()
            canvas.clipPath(extendTrapezoid(i, w, h, t, r, bo, l))
            paintBorderRegion(canvas, side.style, side.color, w, h, radii, t, r, bo, l, false, i)
            canvas.restore()
        }
    }

    private fun extendTrapezoid(i: Int, w: Float, h: Float, t: Float, r: Float, b: Float, l: Float): Path {
        val e = 2f
        val p = Path()
        when (i) {
            0 -> { p.moveTo(-e, -e); p.lineTo(w + e, -e); p.lineTo(w - r, t); p.lineTo(l, t) }
            1 -> { p.moveTo(w + e, -e); p.lineTo(w + e, h + e); p.lineTo(w - r, h - b); p.lineTo(w - r, t) }
            2 -> { p.moveTo(w + e, h + e); p.lineTo(-e, h + e); p.lineTo(l, h - b); p.lineTo(w - r, h - b) }
            else -> { p.moveTo(-e, h + e); p.lineTo(-e, -e); p.lineTo(l, t); p.lineTo(l, h - b) }
        }
        p.close()
        return p
    }

    private fun ring(outer: RectF, outerRadii: FloatArray?, l: Float, t: Float, r: Float, b: Float): Path {
        val p = Path()
        p.fillType = Path.FillType.EVEN_ODD
        p.addPath(Shapes.path(outer, outerRadii, oval, Path()))
        val inner = RectF(outer.left + l, outer.top + t, outer.right - r, outer.bottom - b)
        if (inner.width() > 0 && inner.height() > 0) p.addPath(Shapes.path(inner, Shapes.adjust(outerRadii, -l, -t, -r, -b), oval, Path()))
        return p
    }

    /** Fill (solid / double) or stroke (dashed / dotted) the border ring; [only] limits a stroked side to one edge. */
    private fun paintBorderRegion(canvas: Canvas, style: BorderStyleName, color: Int, w: Float, h: Float, radii: FloatArray?, t: Float, r: Float, b: Float, l: Float, uniformWidth: Boolean, only: Int = -1) {
        paint.reset(); paint.isAntiAlias = true
        paint.color = color
        val outer = RectF(0f, 0f, w, h)
        when (style) {
            BorderStyleName.none -> return
            BorderStyleName.solid -> canvas.drawPath(ring(outer, radii, l, t, r, b), paint)
            BorderStyleName.double -> {
                canvas.drawPath(ring(outer, radii, l / 3, t / 3, r / 3, b / 3), paint)
                val mid = RectF(l * 2 / 3, t * 2 / 3, w - r * 2 / 3, h - b * 2 / 3)
                canvas.drawPath(ring(mid, Shapes.adjust(radii, -l * 2 / 3, -t * 2 / 3, -r * 2 / 3, -b * 2 / 3), l / 3, t / 3, r / 3, b / 3), paint)
            }
            BorderStyleName.dashed, BorderStyleName.dotted -> {
                paint.style = Paint.Style.STROKE
                val dotted = style == BorderStyleName.dotted
                fun effect(width: Float) {
                    paint.strokeWidth = width
                    if (dotted) {
                        paint.strokeCap = Paint.Cap.ROUND
                        paint.pathEffect = DashPathEffect(floatArrayOf(0.001f, width * 2), 0f)
                    } else {
                        paint.strokeCap = Paint.Cap.BUTT
                        val dash = max(3 * width, 2f)
                        paint.pathEffect = DashPathEffect(floatArrayOf(dash, dash), 0f)
                    }
                }
                if (uniformWidth && only < 0) {
                    effect(t)
                    val inset = RectF(t / 2, t / 2, w - t / 2, h - t / 2)
                    canvas.drawPath(Shapes.path(inset, Shapes.adjust(radii, -t / 2, -t / 2, -t / 2, -t / 2), oval, Path()), paint)
                    return
                }
                val edges = if (only >= 0) listOf(only) else listOf(0, 1, 2, 3)
                for (e in edges) {
                    val p = Path()
                    when (e) {
                        0 -> if (t > 0) { effect(t); p.moveTo(0f, t / 2); p.lineTo(w, t / 2) }
                        1 -> if (r > 0) { effect(r); p.moveTo(w - r / 2, 0f); p.lineTo(w - r / 2, h) }
                        2 -> if (b > 0) { effect(b); p.moveTo(w, h - b / 2); p.lineTo(0f, h - b / 2) }
                        else -> if (l > 0) { effect(l); p.moveTo(l / 2, h); p.lineTo(l / 2, 0f) }
                    }
                    canvas.drawPath(p, paint)
                }
            }
        }
    }

    private fun drawOutline(canvas: Canvas, o: Outline, w: Float, h: Float, radii: FloatArray?, density: Float) {
        if (o.width <= 0 || o.style == "none") return
        val ow = (o.width * density).toFloat()
        val off = (o.offset * density).toFloat()
        val grow = off + ow / 2
        paint.reset(); paint.isAntiAlias = true
        paint.color = o.color
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = ow
        when (o.style) {
            "dashed" -> paint.pathEffect = DashPathEffect(floatArrayOf(max(3 * ow, 2f), max(3 * ow, 2f)), 0f)
            "dotted" -> {
                paint.strokeCap = Paint.Cap.ROUND
                paint.pathEffect = DashPathEffect(floatArrayOf(0.001f, ow * 2), 0f)
            }
        }
        val rr = RectF(-grow, -grow, w + grow, h + grow)
        canvas.drawPath(Shapes.path(rr, Shapes.adjust(radii, grow, grow, grow, grow), oval, path2), paint)
    }
}
