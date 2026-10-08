package dev.elpian.android.render

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RadialGradient
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.os.Build
import android.util.Base64
import android.view.MotionEvent
import android.view.View
import dev.elpian.core.render.ViewEvent
import dev.elpian.core.render.resolveFontFamily
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.atan2
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan

/** Host hooks for `custom` canvas commands: name → painter (canvas in logical px). */
fun interface CustomCanvasPainter {
    fun paint(canvas: Canvas, params: Map<String, Any?>)
}

/**
 * Executes Elpian canvas commands with android.graphics — every command of
 * the web painter (native/web/src/canvas.ts) with the same semantics: HTML
 * canvas paths (arc, arcTo, ellipse, roundRect…), fill and stroke styles
 * (colours, gradients, patterns), line dashes, caps, joins, shadows, global
 * alpha and composite operations, clipping, the state stack, transforms,
 * text with CSS fonts, alignment and baselines, images and pixel data.
 * Coordinates are logical px; the bitmap is device px.
 */
class CanvasPainter(private val images: ImageSource, private val onImageReady: () -> Unit) {
    companion object {
        private val customPainters = HashMap<String, CustomCanvasPainter>()

        fun registerCanvasPainter(name: String, painter: CustomCanvasPainter) {
            customPainters[name] = painter
        }

        private val imageCache = HashMap<String, Bitmap?>()

        fun num(p: Map<String, Any?>, k: String, d: Double = 0.0): Double {
            val v = p[k]
            if (v is Number) {
                val x = v.toDouble()
                return if (x.isFinite()) x else d
            }
            if (v is String) return dev.elpian.core.util.parseFloatPrefix(v)?.takeIf { it.isFinite() } ?: d
            return d
        }

        fun color(v: Any?): Int = when (v) {
            is Number -> v.toDouble().let { if (it.isFinite()) it.toLong().toInt() else 0 }
            is String -> dev.elpian.core.css.parseColor(v) ?: Color.BLACK
            else -> Color.BLACK
        }

        /** Points as `[[x,y],…]`, `[{x,y},…]` or a flat `[x0,y0,x1,y1,…]`. */
        fun pointsOf(v: Any?): List<FloatArray> {
            val l = v as? List<*> ?: return emptyList()
            if (l.isNotEmpty() && l[0] is Number) {
                val out = ArrayList<FloatArray>()
                var i = 0
                while (i + 1 < l.size) {
                    out.add(floatArrayOf((l[i] as Number).toFloat(), ((l[i + 1] as? Number) ?: 0).toFloat()))
                    i += 2
                }
                return out
            }
            return l.map { p ->
                when (p) {
                    is List<*> -> floatArrayOf(P.num(p.getOrNull(0))?.toFloat() ?: 0f, P.num(p.getOrNull(1))?.toFloat() ?: 0f)
                    is Map<*, *> -> floatArrayOf(P.num(p["x"])?.toFloat() ?: 0f, P.num(p["y"])?.toFloat() ?: 0f)
                    else -> floatArrayOf(0f, 0f)
                }
            }
        }
    }

    private class Grad(val kind: String, val colors: MutableList<Int>, val stops: MutableList<Float>, val x0: Float, val y0: Float, val x1: Float, val y1: Float, val r0: Float, val r1: Float)
    private class Pattern(val src: String, val repetition: String)
    /** Non-premultiplied ARGB pixels in device px. */
    class ImageData(val width: Int, val height: Int, val pixels: IntArray)

    private sealed class Style {
        data class Solid(val color: Int) : Style()
        data class Gradient(val id: String) : Style()
        data class Pat(val id: String) : Style()
    }

    private data class Font(val typeface: Typeface, val size: Float)

    private data class State(
        var fill: Style = Style.Solid(Color.BLACK),
        var stroke: Style = Style.Solid(Color.BLACK),
        var alpha: Float = 1f,
        var composite: String = "source-over",
        var lineWidth: Float = 1f,
        var cap: Paint.Cap = Paint.Cap.BUTT,
        var join: Paint.Join = Paint.Join.MITER,
        var miter: Float = 10f,
        var dash: FloatArray? = null,
        var dashOffset: Float = 0f,
        var shadowBlur: Float = 0f,
        var shadowColor: Int = 0,
        var shadowX: Float = 0f,
        var shadowY: Float = 0f,
        var font: Font = Font(Typeface.DEFAULT, 10f),
        var align: String = "start",
        var baseline: String = "alphabetic",
    ) {
        fun copyAll(): State = copy(dash = dash?.copyOf())
    }

    private val gradients = HashMap<String, Grad>()
    private val patterns = HashMap<String, Pattern>()
    private val imageData = HashMap<String, ImageData>()
    private var path = Path()
    private var cur = floatArrayOf(0f, 0f)
    private var hasCurrent = false
    private var state = State()
    private val stack = ArrayList<State>()
    private var dpr = 1f
    private val pending = HashSet<String>()

    var bitmap: Bitmap? = null
        private set
    private var canvas: Canvas? = null

    /** Reset the bitmap to [w]×[h] logical px at [dpr] and the state to defaults. */
    fun reset(w: Double, h: Double, dpr: Float) {
        val cw = max(1, (w * dpr).roundToInt())
        val ch = max(1, (h * dpr).roundToInt())
        var bmp = bitmap
        if (bmp == null || bmp.width != cw || bmp.height != ch) {
            bmp?.recycle()
            bmp = try {
                Bitmap.createBitmap(cw, ch, Bitmap.Config.ARGB_8888)
            } catch (_: Throwable) {
                null
            }
            bitmap = bmp
            canvas = bmp?.let { Canvas(it) }
        } else {
            bmp.eraseColor(Color.TRANSPARENT)
        }
        val c = canvas ?: return
        while (c.saveCount > 1) c.restore()
        c.setMatrix(null)
        c.scale(dpr, dpr)
        c.save()
        this.dpr = dpr
        // Flutter's CanvasState / HTML defaults.
        state = State()
        stack.clear()
        path = Path()
        hasCurrent = false
        cur = floatArrayOf(0f, 0f)
        gradients.clear()
        patterns.clear()
    }

    fun run(commands: List<*>) {
        val c = canvas ?: return
        for (cmd in commands) {
            val m = cmd as? Map<*, *> ?: continue
            val type = m["type"] as? String ?: continue
            @Suppress("UNCHECKED_CAST")
            val params = (m["params"] as? Map<String, Any?>) ?: emptyMap()
            try {
                exec(c, type, params)
            } catch (e: Throwable) {
                android.util.Log.w("Elpian", "canvas: $type failed: $e")
            }
        }
    }

    fun release() {
        bitmap?.recycle()
        bitmap = null
        canvas = null
    }

    // ---------------------------------------------------------------------
    // Paths
    // ---------------------------------------------------------------------

    private fun moveTo(x: Float, y: Float) {
        path.moveTo(x, y)
        cur = floatArrayOf(x, y)
        hasCurrent = true
    }

    private fun lineTo(x: Float, y: Float) {
        if (!hasCurrent) moveTo(x, y) else path.lineTo(x, y)
        cur = floatArrayOf(x, y)
        hasCurrent = true
    }

    /** An elliptical arc as cubic Béziers (HTML `ellipse` / `arc` semantics, lineTo the start). */
    private fun arc(cx: Double, cy: Double, rx: Double, ry: Double, rot: Double, start: Double, end: Double, ccw: Boolean) {
        val tau = PI * 2
        val sweep = if (!ccw) {
            if (end - start >= tau) tau else ((end - start) % tau).let { if (it < 0) it + tau else it }
        } else {
            if (start - end >= tau) -tau else -(((start - end) % tau).let { if (it < 0) it + tau else it })
        }
        arcSweep(cx, cy, rx, ry, rot, start, sweep)
    }

    private fun arcSweep(cx: Double, cy: Double, rx: Double, ry: Double, rot: Double, start: Double, sweep: Double) {
        val cr = cos(rot)
        val sr = sin(rot)
        fun map(ux: Double, uy: Double): FloatArray = floatArrayOf((cx + rx * ux * cr - ry * uy * sr).toFloat(), (cy + rx * ux * sr + ry * uy * cr).toFloat())
        val p0 = map(cos(start), sin(start))
        if (hasCurrent) lineTo(p0[0], p0[1]) else moveTo(p0[0], p0[1])
        if (sweep == 0.0) return
        val n = max(1, ceil(abs(sweep) / (PI / 2) - 1e-9).toInt())
        val da = sweep / n
        val k = 4.0 / 3.0 * tan(da / 4)
        var a0 = start
        for (i in 0 until n) {
            val a1 = a0 + da
            val c0 = cos(a0); val s0 = sin(a0)
            val c1 = cos(a1); val s1 = sin(a1)
            val q1 = map(c0 - k * s0, s0 + k * c0)
            val q2 = map(c1 + k * s1, s1 - k * c1)
            val q3 = map(c1, s1)
            path.cubicTo(q1[0], q1[1], q2[0], q2[1], q3[0], q3[1])
            cur = q3
            a0 = a1
        }
    }

    /** HTML `arcTo(x1, y1, x2, y2, r)`. */
    private fun arcTo(x1: Double, y1: Double, x2: Double, y2: Double, r: Double) {
        if (!hasCurrent) moveTo(x1.toFloat(), y1.toFloat())
        val x0 = cur[0].toDouble()
        val y0 = cur[1].toDouble()
        if ((x0 == x1 && y0 == y1) || (x1 == x2 && y1 == y2) || r == 0.0) {
            lineTo(x1.toFloat(), y1.toFloat())
            return
        }
        val v1x = x0 - x1; val v1y = y0 - y1
        val v2x = x2 - x1; val v2y = y2 - y1
        val l1 = hypot(v1x, v1y); val l2 = hypot(v2x, v2y)
        val n1x = v1x / l1; val n1y = v1y / l1
        val n2x = v2x / l2; val n2y = v2y / l2
        val cross = n1x * n2y - n1y * n2x
        if (abs(cross) < 1e-9) {
            lineTo(x1.toFloat(), y1.toFloat())
            return
        }
        val angle = acos((n1x * n2x + n1y * n2y).coerceIn(-1.0, 1.0))
        val dist = r / tan(angle / 2)
        val t1x = x1 + n1x * dist; val t1y = y1 + n1y * dist
        val t2x = x1 + n2x * dist; val t2y = y1 + n2y * dist
        val bx = n1x + n2x; val by = n1y + n2y
        val bl = hypot(bx, by)
        val h = r / sin(angle / 2)
        val cx = x1 + bx / bl * h
        val cy = y1 + by / bl * h
        lineTo(t1x.toFloat(), t1y.toFloat())
        val a0 = atan2(t1y - cy, t1x - cx)
        val a1 = atan2(t2y - cy, t2x - cx)
        var sweep = a1 - a0
        while (sweep > PI) sweep -= 2 * PI
        while (sweep < -PI) sweep += 2 * PI
        arcSweep(cx, cy, r, r, 0.0, a0, sweep)
        cur = floatArrayOf(t2x.toFloat(), t2y.toFloat())
    }

    /**
     * Flutter `Path.arcToPoint`: a circular arc of [radius] from the current
     * point to (x, y) — clockwise by default, the shorter arc unless [largeArc].
     * A radius too small for the chord grows to half the chord (SVG rules).
     */
    private fun arcToPoint(x: Double, y: Double, radius: Double, clockwise: Boolean, largeArc: Boolean) {
        val x0 = cur[0].toDouble()
        val y0 = cur[1].toDouble()
        val dx = x - x0
        val dy = y - y0
        val d = hypot(dx, dy)
        if (d == 0.0) return
        if (radius <= 0) {
            lineTo(x.toFloat(), y.toFloat())
            return
        }
        val r = max(radius, d / 2)
        val h = sqrt(max(0.0, r * r - (d / 2) * (d / 2)))
        val sign = if (clockwise != largeArc) 1 else -1
        val cx = (x0 + x) / 2 - (sign * h * dy) / d
        val cy = (y0 + y) / 2 + (sign * h * dx) / d
        val a0 = atan2(y0 - cy, x0 - cx)
        val a1 = atan2(y - cy, x - cx)
        arc(cx, cy, r, r, 0.0, a0, a1, !clockwise)
        cur = floatArrayOf(x.toFloat(), y.toFloat())
    }

    private fun radiiOf(v: Any?, fallback: Double): FloatArray {
        fun one(x: Any?): FloatArray = when (x) {
            is Map<*, *> -> floatArrayOf(P.num(x["x"])?.toFloat() ?: 0f, P.num(x["y"])?.toFloat() ?: 0f)
            else -> (P.num(x) ?: 0.0).toFloat().let { floatArrayOf(it, it) }
        }
        val l = v as? List<*>
        val r: List<FloatArray> = if (l == null || l.isEmpty()) listOf(one(fallback)) else l.map { one(it) }
        val (tl, tr, br, bl) = when (r.size) {
            1 -> listOf(r[0], r[0], r[0], r[0])
            2 -> listOf(r[0], r[1], r[0], r[1])
            3 -> listOf(r[0], r[1], r[2], r[1])
            else -> listOf(r[0], r[1], r[2], r[3])
        }
        return floatArrayOf(tl[0], tl[1], tr[0], tr[1], br[0], br[1], bl[0], bl[1]).map { max(0f, it) }.toFloatArray()
    }

    // ---------------------------------------------------------------------
    // Paints
    // ---------------------------------------------------------------------

    private fun shaderFor(style: Style): Shader? = when (style) {
        is Style.Solid -> null
        is Style.Gradient -> gradients[style.id]?.let { g ->
            var colors = g.colors.toIntArray()
            var stops = g.stops.map { it.coerceIn(0f, 1f) }.toFloatArray()
            if (colors.isEmpty()) return null
            if (colors.size == 1) {
                colors = intArrayOf(colors[0], colors[0]); stops = floatArrayOf(0f, 1f)
            }
            if (g.kind == "linear") {
                LinearGradient(g.x0, g.y0, if (g.x0 == g.x1 && g.y0 == g.y1) g.x1 + 0.0001f else g.x1, g.y1, colors, stops, Shader.TileMode.CLAMP)
            } else if (Build.VERSION.SDK_INT >= 31) {
                RadialGradient(g.x0, g.y0, max(0f, g.r0), g.x1, g.y1, max(0.0001f, g.r1), LongArray(colors.size) { Color.pack(colors[it]) }, stops, Shader.TileMode.CLAMP)
            } else {
                // Single-circle approximation: the inner circle's radius offsets the stops.
                val r1 = max(0.0001f, g.r1)
                val f = (g.r0 / r1).coerceIn(0f, 1f)
                RadialGradient(g.x1, g.y1, r1, colors, FloatArray(stops.size) { f + stops[it] * (1 - f) }, Shader.TileMode.CLAMP)
            }
        }
        is Style.Pat -> patterns[style.id]?.let { pat ->
            val bmp = image(pat.src) ?: return null
            val rx = pat.repetition == "repeat" || pat.repetition == "repeat-x" || pat.repetition.isEmpty()
            val ry = pat.repetition == "repeat" || pat.repetition == "repeat-y" || pat.repetition.isEmpty()
            if (Build.VERSION.SDK_INT >= 31) {
                BitmapShader(bmp, if (rx) Shader.TileMode.REPEAT else Shader.TileMode.DECAL, if (ry) Shader.TileMode.REPEAT else Shader.TileMode.DECAL)
            } else if (rx && ry) {
                BitmapShader(bmp, Shader.TileMode.REPEAT, Shader.TileMode.REPEAT)
            } else {
                // Pad with a transparent pixel so CLAMP extends transparency.
                val padded = Bitmap.createBitmap(bmp.width + (if (rx) 0 else 2), bmp.height + (if (ry) 0 else 2), Bitmap.Config.ARGB_8888)
                Canvas(padded).drawBitmap(bmp, if (rx) 0f else 1f, if (ry) 0f else 1f, null)
                val s = BitmapShader(padded, if (rx) Shader.TileMode.REPEAT else Shader.TileMode.CLAMP, if (ry) Shader.TileMode.REPEAT else Shader.TileMode.CLAMP)
                val m = Matrix()
                m.setTranslate(if (rx) 0f else -1f, if (ry) 0f else -1f)
                s.setLocalMatrix(m)
                s
            }
        }
    }

    private fun paintFor(fill: Boolean, style: Style? = null): Paint {
        val st = state
        val p = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        val s = style ?: if (fill) st.fill else st.stroke
        if (s is Style.Solid) {
            p.color = s.color
            p.alpha = ((s.color ushr 24) * st.alpha).roundToInt().coerceIn(0, 255)
        } else {
            p.color = Color.BLACK
            p.alpha = (255 * st.alpha).roundToInt().coerceIn(0, 255)
            p.shader = shaderFor(s)
            if (p.shader == null) p.color = Color.TRANSPARENT
        }
        p.style = if (fill) Paint.Style.FILL else Paint.Style.STROKE
        p.strokeWidth = st.lineWidth
        p.strokeCap = st.cap
        p.strokeJoin = st.join
        p.strokeMiter = st.miter
        st.dash?.let { if (it.isNotEmpty() && it.any { v -> v > 0 }) p.pathEffect = DashPathEffect(it, st.dashOffset) }
        applyShadow(p)
        p.typeface = st.font.typeface
        p.textSize = st.font.size
        return p
    }

    private fun applyShadow(p: Paint) {
        val st = state
        if ((st.shadowColor ushr 24) == 0 || (st.shadowBlur <= 0f && st.shadowX == 0f && st.shadowY == 0f)) return
        // HTML shadowBlur is 2σ; android's radius goes through radius→sigma.
        val sigma = st.shadowBlur / 2 * dpr
        val r = if (sigma > 0.5f) (sigma - 0.5f) / 0.57735f / dpr else 0.01f
        val c = st.shadowColor
        val a = ((c ushr 24) * st.alpha).roundToInt().coerceIn(0, 255)
        p.setShadowLayer(max(0.01f, r), st.shadowX, st.shadowY, (a shl 24) or (c and 0xffffff))
    }

    /** Draw with the current composite operation (source-over draws directly; others through a full-canvas layer). */
    private inline fun composite(c: Canvas, block: () -> Unit) {
        val op = state.composite
        if (op == "source-over" || op.isEmpty()) {
            block()
            return
        }
        val lp = Paint()
        if (!Paints.applyBlend(lp, op)) {
            block()
            return
        }
        val save = c.saveLayer(null, lp)
        block()
        c.restoreToCount(save)
    }

    private fun parseFont(font: String): Font {
        var italic = false
        var weight = 400
        var size = 10f
        var family: String? = "sans-serif"
        val parts = font.trim().split(Regex("\\s+"))
        var i = 0
        while (i < parts.size) {
            val t = parts[i]
            val lower = t.lowercase()
            when {
                lower == "italic" || lower == "oblique" -> italic = true
                lower == "bold" || lower == "bolder" -> weight = 700
                lower == "lighter" -> weight = 300
                lower == "normal" || lower == "small-caps" -> {}
                Regex("^[1-9]00$").matches(lower) -> weight = lower.toInt()
                Regex("^[\\d.]+(px|pt|em|rem|%)(/.*)?$").matches(lower) -> {
                    val m = Regex("^([\\d.]+)(px|pt|em|rem|%)").find(lower)!!
                    val v = m.groupValues[1].toFloatOrNull() ?: 10f
                    size = when (m.groupValues[2]) {
                        "pt" -> v * 4f / 3f
                        "em", "rem" -> v * 16f
                        "%" -> v / 100f * 10f
                        else -> v
                    }
                    family = parts.subList(i + 1, parts.size).joinToString(" ").ifBlank { "sans-serif" }
                    i = parts.size
                    continue
                }
            }
            i++
        }
        val resolved = resolveFontFamily(family)
        return Font(ElpianFonts.typeface(resolved, weight, italic), if (size > 0) size else 10f)
    }

    // ---------------------------------------------------------------------
    // Images
    // ---------------------------------------------------------------------

    /** A decoded image, or null while it loads (the painter re-runs on load). */
    private fun image(src: String): Bitmap? {
        if (src.isEmpty()) return null
        if (imageCache.containsKey(src)) return imageCache[src]
        if (pending.add(src)) {
            images.load(src) { bmp ->
                pending.remove(src)
                imageCache[src] = bmp
                if (imageCache.size > 64) imageCache.keys.firstOrNull()?.let { if (it != src) imageCache.remove(it) }
                if (bmp != null) onImageReady()
            }
        }
        return null
    }

    // ---------------------------------------------------------------------
    // Commands
    // ---------------------------------------------------------------------

    private fun exec(c: Canvas, type: String, p: Map<String, Any?>) {
        fun n(k: String, d: Double = 0.0) = num(p, k, d)
        fun f(k: String, d: Double = 0.0) = num(p, k, d).toFloat()
        when (type) {
            // ---- path building ----
            "beginPath" -> {
                path = Path(); hasCurrent = false; cur = floatArrayOf(0f, 0f)
            }
            "closePath" -> path.close()
            "moveTo" -> moveTo(f("x"), f("y"))
            "lineTo" -> lineTo(f("x"), f("y"))
            "quadraticCurveTo" -> {
                if (!hasCurrent) moveTo(f("cpx"), f("cpy"))
                path.quadTo(f("cpx"), f("cpy"), f("x"), f("y")); cur = floatArrayOf(f("x"), f("y"))
            }
            "bezierCurveTo" -> {
                if (!hasCurrent) moveTo(f("cp1x"), f("cp1y"))
                path.cubicTo(f("cp1x"), f("cp1y"), f("cp2x"), f("cp2y"), f("x"), f("y")); cur = floatArrayOf(f("x"), f("y"))
            }
            "arc" -> {
                val r = max(0.0, n("radius"))
                arc(n("x"), n("y"), r, r, 0.0, n("startAngle"), n("endAngle"), p["counterclockwise"] == true)
            }
            "arcTo" -> {
                // HTML arcTo(x1, y1, x2, y2, r); the Flutter-only shape {x, y, radius} (an arc to a point) too.
                if (p["x1"] != null || p["x2"] != null) arcTo(n("x1"), n("y1"), n("x2"), n("y2"), max(0.0, n("radius")))
                else arcToPoint(n("x"), n("y"), n("radius"), p["clockwise"] != false, p["largeArc"] == true)
            }
            "ellipse" -> arc(n("x"), n("y"), abs(n("radiusX")), abs(n("radiusY")), n("rotation"), n("startAngle", 0.0), n("endAngle", PI * 2), p["counterclockwise"] == true)
            "rect" -> {
                path.addRect(RectF(f("x"), f("y"), f("x") + f("width"), f("y") + f("height")).also { it.sort() }, Path.Direction.CW)
                moveTo(f("x"), f("y"))
            }
            "roundRect" -> {
                val rect = RectF(f("x"), f("y"), f("x") + f("width"), f("y") + f("height"))
                rect.sort()
                val radii = Shapes.scaleRadii(radiiOf(p["radii"], n("radius")), rect.width(), rect.height())
                path.addRoundRect(rect, radii, Path.Direction.CW)
                moveTo(f("x"), f("y"))
            }
            "circle" -> {
                val r = max(0.0, n("radius"))
                moveTo((n("x") + r).toFloat(), f("y"))
                arc(n("x"), n("y"), r, r, 0.0, 0.0, PI * 2, false)
            }

            // ---- painting the path ----
            "fill" -> composite(c) {
                val fp = Path(path)
                fp.fillType = if (p["fillRule"] == "evenodd") Path.FillType.EVEN_ODD else Path.FillType.WINDING
                c.drawPath(fp, paintFor(true))
            }
            "stroke" -> composite(c) { c.drawPath(path, paintFor(false)) }
            "clip" -> {
                val cp = Path(path)
                cp.fillType = if (p["fillRule"] == "evenodd") Path.FillType.EVEN_ODD else Path.FillType.WINDING
                c.clipPath(cp)
            }

            // ---- shapes ----
            "fillRect" -> composite(c) { c.drawRect(RectF(f("x"), f("y"), f("x") + f("width"), f("y") + f("height")).also { it.sort() }, paintFor(true)) }
            "strokeRect" -> composite(c) { c.drawRect(RectF(f("x"), f("y"), f("x") + f("width"), f("y") + f("height")).also { it.sort() }, paintFor(false)) }
            "clearRect" -> {
                val cp = Paint()
                cp.xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR)
                c.drawRect(RectF(f("x"), f("y"), f("x") + f("width"), f("y") + f("height")).also { it.sort() }, cp)
            }
            "fillCircle", "strokeCircle" -> composite(c) { c.drawCircle(f("x"), f("y"), max(0f, f("radius")), paintFor(type == "fillCircle")) }
            "fillPolygon", "strokePolygon" -> {
                val pts = pointsOf(p["points"])
                if (pts.size < 2) return
                val poly = Path()
                poly.moveTo(pts[0][0], pts[0][1])
                for (i in 1 until pts.size) poly.lineTo(pts[i][0], pts[i][1])
                if (p["closed"] != false) poly.close()
                composite(c) { c.drawPath(poly, paintFor(type == "fillPolygon")) }
            }

            // ---- text ----
            "fillText", "strokeText" -> drawText(c, P.str(p["text"]) ?: "", f("x"), f("y"), p["maxWidth"]?.let { f("maxWidth") }, type == "fillText")

            // ---- images ----
            "drawImage", "drawImageRect" -> {
                val img = image(P.str(p["src"] ?: p["imageId"]) ?: "") ?: return
                val nw = img.width.toDouble()
                val nh = img.height.toDouble()
                val paint = paintFor(true, Style.Solid(Color.BLACK))
                val src: Rect?
                val dst: RectF
                if (type == "drawImageRect" || p["sx"] != null) {
                    src = Rect(n("sx").roundToInt(), n("sy").roundToInt(), (n("sx") + n("sw", nw)).roundToInt(), (n("sy") + n("sh", nh)).roundToInt())
                    val dx = n("dx", n("x")); val dy = n("dy", n("y"))
                    dst = RectF(dx.toFloat(), dy.toFloat(), (dx + n("dw", n("width", nw))).toFloat(), (dy + n("dh", n("height", nh))).toFloat())
                } else if (p["width"] != null || p["height"] != null) {
                    src = null
                    dst = RectF(f("x"), f("y"), (n("x") + n("width", nw)).toFloat(), (n("y") + n("height", nh)).toFloat())
                } else {
                    src = null
                    dst = RectF(f("x"), f("y"), (n("x") + nw).toFloat(), (n("y") + nh).toFloat())
                }
                composite(c) { c.drawBitmap(img, src, dst, paint) }
            }

            // ---- state and transforms ----
            "save" -> {
                stack.add(state.copyAll())
                c.save()
            }
            "restore" -> {
                if (stack.isNotEmpty()) {
                    state = stack.removeAt(stack.size - 1)
                    c.restore()
                }
            }
            "translate" -> c.translate(f("x"), f("y"))
            "rotate" -> c.rotate(Math.toDegrees(n("angle")).toFloat())
            "scale" -> c.scale(f("x", 1.0), num(p, "y", n("x", 1.0)).toFloat())
            "transform" -> c.concat(affine(p))
            "setTransform" -> {
                // Relative to the device-pixel base, like an HTML canvas of CSS size.
                val m = affine(p)
                m.postScale(dpr, dpr)
                c.setMatrix(m)
            }
            "resetTransform" -> {
                val m = Matrix()
                m.setScale(dpr, dpr)
                c.setMatrix(m)
            }

            // ---- styles ----
            "setFillStyle" -> style(p)?.let { state.fill = it }
            "setStrokeStyle" -> style(p)?.let { state.stroke = it }
            "setLineWidth" -> state.lineWidth = f("width", 1.0)
            "setLineCap" -> state.cap = when (p["cap"]) { "round" -> Paint.Cap.ROUND; "square" -> Paint.Cap.SQUARE; else -> Paint.Cap.BUTT }
            "setLineJoin" -> state.join = when (p["join"]) { "round" -> Paint.Join.ROUND; "bevel" -> Paint.Join.BEVEL; else -> Paint.Join.MITER }
            "setMiterLimit" -> state.miter = f("limit", 10.0)
            "setLineDash" -> {
                val segs = (p["segments"] as? List<*>)?.mapNotNull { P.num(it)?.toFloat() }?.filter { it >= 0 } ?: emptyList()
                state.dash = if (segs.isEmpty()) null else (if (segs.size % 2 == 1) segs + segs else segs).toFloatArray()
            }
            "setLineDashOffset" -> state.dashOffset = f("offset")
            "setShadowBlur" -> state.shadowBlur = f("blur")
            "setShadowColor" -> state.shadowColor = color(p["color"])
            "setShadowOffsetX" -> state.shadowX = num(p, "offset", n("x")).toFloat()
            "setShadowOffsetY" -> state.shadowY = num(p, "offset", n("y")).toFloat()
            "setGlobalAlpha" -> state.alpha = n("alpha", 1.0).coerceIn(0.0, 1.0).toFloat()
            "setGlobalCompositeOperation" -> state.composite = P.str(p["operation"]) ?: "source-over"
            "setFont" -> state.font = parseFont(P.str(p["font"]) ?: "10px sans-serif")
            "setTextAlign" -> state.align = (p["align"] as? String)?.takeIf { it in listOf("left", "right", "center", "start", "end") } ?: "start"
            "setTextBaseline" -> state.baseline = (p["baseline"] as? String)?.takeIf { it in listOf("top", "hanging", "middle", "alphabetic", "ideographic", "bottom") } ?: "alphabetic"

            // ---- gradients and patterns ----
            "createLinearGradient" -> gradients[P.str(p["id"]) ?: ""] = Grad("linear", colorsOf(p), stopsOf(p), f("x0"), f("y0"), f("x1"), f("y1"), 0f, 0f)
            "createRadialGradient" -> gradients[P.str(p["id"]) ?: ""] = Grad(
                "radial", colorsOf(p), stopsOf(p),
                num(p, "x0", n("x")).toFloat(), num(p, "y0", n("y")).toFloat(),
                num(p, "x1", n("x")).toFloat(), num(p, "y1", n("y")).toFloat(),
                f("r0"), num(p, "r1", n("r")).toFloat(),
            )
            "addColorStop" -> {
                val g = gradients[P.str(p["gradientId"] ?: p["id"]) ?: ""] ?: return
                val offset = n("offset").coerceIn(0.0, 1.0).toFloat()
                val col = (p["color"] as? Number)?.let { color(it) } ?: 0xff000000.toInt()
                // Keep stops sorted, as CanvasGradient does.
                var i = g.stops.indexOfFirst { it > offset }
                if (i < 0) i = g.stops.size
                g.stops.add(i, offset)
                g.colors.add(i, col)
            }
            "createPattern" -> patterns[P.str(p["id"]) ?: ""] = Pattern(P.str(p["src"] ?: p["imageId"]) ?: "", P.str(p["repetition"]) ?: "repeat")

            // ---- pixels ----
            "createImageData" -> {
                val w = max(1, n("width", 1.0).roundToInt())
                val h = max(1, n("height", 1.0).roundToInt())
                imageData[P.str(p["id"]) ?: ""] = ImageData(w, h, IntArray(w * h))
            }
            "getImageData" -> {
                val bmp = bitmap ?: return
                val x = (n("x") * dpr).roundToInt()
                val y = (n("y") * dpr).roundToInt()
                val w = max(1, (n("width", 1.0) * dpr).roundToInt())
                val h = max(1, (n("height", 1.0) * dpr).roundToInt())
                val px = IntArray(w * h)
                val ix0 = max(0, x); val iy0 = max(0, y)
                val ix1 = min(bmp.width, x + w); val iy1 = min(bmp.height, y + h)
                if (ix1 > ix0 && iy1 > iy0) bmp.getPixels(px, (iy0 - y) * w + (ix0 - x), w, ix0, iy0, ix1 - ix0, iy1 - iy0)
                imageData[P.str(p["id"]) ?: ""] = ImageData(w, h, px)
            }
            "putImageData" -> {
                var data: ImageData? = p["id"]?.let { imageData[P.str(it) ?: ""] }
                val bytes = pixelsOf(p["data"])
                if (bytes != null) {
                    val w = max(1, n("width", (data?.width ?: 1).toDouble()).roundToInt())
                    val h = max(1, n("height", (data?.height ?: ceil(bytes.size / 4.0 / w).toInt()).toDouble()).roundToInt())
                    val px = IntArray(w * h)
                    for (i in 0 until min(w * h, bytes.size / 4)) {
                        val o = i * 4
                        px[i] = ((bytes[o + 3].toInt() and 0xff) shl 24) or ((bytes[o].toInt() and 0xff) shl 16) or ((bytes[o + 1].toInt() and 0xff) shl 8) or (bytes[o + 2].toInt() and 0xff)
                    }
                    data = ImageData(w, h, px)
                    p["id"]?.let { imageData[P.str(it) ?: ""] = data }
                }
                val d = data ?: return
                val bmp = bitmap ?: return
                val x = (n("x") * dpr).roundToInt()
                val y = (n("y") * dpr).roundToInt()
                val ix0 = max(0, x); val iy0 = max(0, y)
                val ix1 = min(bmp.width, x + d.width); val iy1 = min(bmp.height, y + d.height)
                if (ix1 > ix0 && iy1 > iy0) bmp.setPixels(d.pixels, (iy0 - y) * d.width + (ix0 - x), d.width, ix0, iy0, ix1 - ix0, iy1 - iy0)
            }

            "custom" -> {
                val painter = customPainters[P.str(p["name"]) ?: ""] ?: return
                val s = c.save()
                painter.paint(c, p)
                c.restoreToCount(s)
            }
            else -> {}
        }
    }

    private fun affine(p: Map<String, Any?>): Matrix {
        val m = Matrix()
        m.setValues(floatArrayOf(num(p, "a", 1.0).toFloat(), num(p, "c").toFloat(), num(p, "e").toFloat(), num(p, "b").toFloat(), num(p, "d", 1.0).toFloat(), num(p, "f").toFloat(), 0f, 0f, 1f))
        return m
    }

    private fun style(p: Map<String, Any?>): Style? {
        if (p["color"] != null) return Style.Solid(color(p["color"]))
        p["gradientId"]?.let { id -> return if (gradients.containsKey(P.str(id))) Style.Gradient(P.str(id)!!) else null }
        p["patternId"]?.let { id -> return if (patterns.containsKey(P.str(id))) Style.Pat(P.str(id)!!) else null }
        return null
    }

    private fun colorsOf(p: Map<String, Any?>): MutableList<Int> = ((p["colors"] as? List<*>) ?: emptyList<Any?>()).map { color(it) }.toMutableList()

    private fun stopsOf(p: Map<String, Any?>): MutableList<Float> {
        val colors = (p["colors"] as? List<*>) ?: emptyList<Any?>()
        val stops = p["stops"] as? List<*>
        if (stops != null && stops.size == colors.size) return stops.map { (P.num(it) ?: 0.0).toFloat() }.toMutableList()
        return colors.indices.map { if (colors.size > 1) it.toFloat() / (colors.size - 1) else 0f }.toMutableList()
    }

    /** RGBA bytes from an array of numbers or a base64 string. */
    private fun pixelsOf(data: Any?): ByteArray? = when (data) {
        is List<*> -> ByteArray(data.size) { (P.num(data[it]) ?: 0.0).coerceIn(0.0, 255.0).roundToInt().toByte() }
        is String -> if (data.isEmpty()) null else try {
            Base64.decode(data, Base64.DEFAULT)
        } catch (_: Throwable) {
            null
        }
        is ByteArray -> data
        else -> null
    }

    private fun drawText(c: Canvas, text: String, x: Float, y: Float, maxWidth: Float?, fill: Boolean) {
        val paint = paintFor(fill)
        val st = state
        paint.textAlign = when (st.align) {
            "center" -> Paint.Align.CENTER
            "right", "end" -> Paint.Align.RIGHT
            else -> Paint.Align.LEFT
        }
        val fm = paint.fontMetrics
        val dy = when (st.baseline) {
            "top" -> -fm.ascent
            "hanging" -> -fm.ascent * 0.8f
            "middle" -> -(fm.ascent + fm.descent) / 2
            "ideographic", "bottom" -> -fm.descent
            else -> 0f
        }
        composite(c) {
            val w = paint.measureText(text)
            if (maxWidth != null && maxWidth >= 0 && w > maxWidth) {
                val s = c.save()
                c.translate(x, y + dy)
                c.scale(if (w > 0) maxWidth / w else 1f, 1f)
                c.drawText(text, 0f, 0f, paint)
                c.restoreToCount(s)
            } else {
                c.drawText(text, x, y + dy, paint)
            }
        }
    }
}

/** The `canvas` view kind: a bitmap the [CanvasPainter] draws, reporting pointer events. */
@SuppressLint("ViewConstructor")
class CanvasLeafView(context: Context, private val owner: ElpianView) : View(context) {
    var commands: MutableList<Any?>? = null
    val painter = CanvasPainter(owner.host.images) { post { repaint() } }
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG)
    var backgroundColorValue: Int? = null
        set(v) {
            field = v
            invalidate()
        }

    /** Re-run the whole command list at the current size. */
    fun repaint() {
        val cmds = commands ?: return
        painter.reset(owner.frame[2], owner.frame[3], owner.density)
        painter.run(cmds)
        invalidate()
    }

    fun replace(cmds: List<*>) {
        commands = ArrayList(cmds)
        repaint()
    }

    fun append(cmds: List<*>) {
        val list = commands ?: ArrayList<Any?>().also { commands = it }
        list.addAll(cmds)
        if (painter.bitmap == null) painter.reset(owner.frame[2], owner.frame[3], owner.density)
        painter.run(cmds)
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        backgroundColorValue?.let { canvas.drawColor(it) }
        val bmp = painter.bitmap ?: return
        canvas.drawBitmap(bmp, null, Rect(0, 0, width, height), paint)
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        val type = when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> "pointerdown"
            MotionEvent.ACTION_MOVE -> "pointermove"
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> "pointerup"
            MotionEvent.ACTION_CANCEL -> "pointerup"
            else -> return true
        }
        val d = owner.density
        val root = IntArray(2)
        owner.host.surface.getLocationOnScreen(root)
        val idx = if (e.actionMasked == MotionEvent.ACTION_POINTER_DOWN || e.actionMasked == MotionEvent.ACTION_POINTER_UP) e.actionIndex else 0
        val rawX = if (Build.VERSION.SDK_INT >= 29) e.getRawX(idx) else e.rawX
        val rawY = if (Build.VERSION.SDK_INT >= 29) e.getRawY(idx) else e.rawY
        owner.host.emit(
            ViewEvent(
                id = owner.viewId, type = type,
                localX = e.getX(idx) / d.toDouble(), localY = e.getY(idx) / d.toDouble(),
                x = (rawX - root[0]) / d.toDouble(), y = (rawY - root[1]) / d.toDouble(),
                pointerId = e.getPointerId(idx), buttons = if (type == "pointerup") 0 else 1,
            ),
        )
        return true
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
    }

    fun release() {
        painter.release()
    }
}
