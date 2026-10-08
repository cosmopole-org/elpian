package dev.elpian.android.render

import android.graphics.BlendMode
import android.graphics.ColorMatrix
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RadialGradient
import android.graphics.Shader
import android.graphics.SweepGradient
import android.os.Build
import android.view.PointerIcon
import android.view.View
import dev.elpian.core.css.Alignment
import dev.elpian.core.css.Filter
import dev.elpian.core.css.Gradient
import dev.elpian.core.css.GradientKind
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Flutter painting values → android.graphics, with Flutter's geometry (the
 * counterpart of the web host's css.ts): linear gradients run exactly from
 * `begin` to `end` within the box, radial radii are fractions of the shortest
 * side, sweeps start at 3 o'clock, and blur radii follow Flutter's
 * `convertRadiusToSigma` (blurRadius·0.57735 + 0.5).
 */
object Paints {
    /** Flutter's `convertRadiusToSigma`, in logical px. */
    fun sigma(blurRadius: Double): Double = if (blurRadius > 0) blurRadius * 0.57735 + 0.5 else 0.0

    /**
     * The radius to hand android's `BlurMaskFilter` / `setShadowLayer` (which
     * apply the same conversion internally) so the device-pixel sigma equals
     * Flutter's logical sigma × [density].
     */
    fun androidBlurRadius(blurRadius: Double, density: Float): Float {
        val s = sigma(blurRadius) * density
        if (s <= 0) return 0f
        return max(0.01, (s - 0.5) / 0.57735).toFloat()
    }

    private fun point(a: Alignment?, fallback: Alignment, w: Float, h: Float): FloatArray {
        val al = a ?: fallback
        return floatArrayOf(((al.x + 1) / 2 * w).toFloat(), ((al.y + 1) / 2 * h).toFloat())
    }

    private fun colorsAndStops(g: Gradient): Pair<IntArray, FloatArray> {
        val stops = g.resolvedStops()
        var colors = g.colors.toIntArray()
        var pos = FloatArray(stops.size) { stops[it].toFloat().coerceIn(0f, 1f) }
        // Positions must be non-decreasing; android needs at least two colours.
        for (i in 1 until pos.size) if (pos[i] < pos[i - 1]) pos[i] = pos[i - 1]
        if (colors.size == 1) {
            colors = intArrayOf(colors[0], colors[0])
            pos = floatArrayOf(0f, 1f)
        }
        return colors to pos
    }

    /** A shader for [g] over a box of [w]×[h] (in the canvas's units). */
    fun gradientShader(g: Gradient, w: Float, h: Float): Shader? {
        if (g.colors.isEmpty()) return null
        val (colors, stops) = colorsAndStops(g)
        val tile = if (g.repeat) Shader.TileMode.REPEAT else Shader.TileMode.CLAMP
        val W = max(w, 0.0001f)
        val H = max(h, 0.0001f)
        return when (g.kind) {
            GradientKind.linear -> {
                val p0 = point(g.begin, Alignment.centerLeft, W, H)
                val p1 = point(g.end, Alignment.centerRight, W, H)
                var x1 = p1[0]
                if (p0[0] == p1[0] && p0[1] == p1[1]) x1 += 0.0001f
                LinearGradient(p0[0], p0[1], x1, p1[1], colors, stops, tile)
            }
            GradientKind.radial -> {
                val c = point(g.center, Alignment.center, W, H)
                val r = max(0.0001f, ((g.radius ?: 0.5) * min(W, H)).toFloat())
                RadialGradient(c[0], c[1], r, colors, stops, tile)
            }
            GradientKind.sweep -> {
                val c = point(g.center, Alignment.center, W, H)
                val start = g.startAngle ?: 0.0
                val end = g.endAngle ?: (PI * 2)
                val span = (end - start).takeIf { it > 0 } ?: (PI * 2)
                val frac = (span / (PI * 2)).toFloat()
                val outColors = ArrayList<Int>()
                val outStops = ArrayList<Float>()
                if (g.repeat && frac < 1f) {
                    var base = 0f
                    while (base < 1f) {
                        for (i in colors.indices) {
                            val p = base + stops[i] * frac
                            if (p > 1f) break
                            outColors.add(colors[i]); outStops.add(p)
                        }
                        base += frac
                    }
                } else {
                    for (i in colors.indices) {
                        outColors.add(colors[i]); outStops.add(min(1f, stops[i] * frac))
                    }
                }
                if (outStops.last() < 1f) {
                    outColors.add(colors.last()); outStops.add(1f)
                }
                for (i in 1 until outStops.size) if (outStops[i] < outStops[i - 1]) outStops[i] = outStops[i - 1]
                val shader = SweepGradient(c[0], c[1], outColors.toIntArray(), outStops.toFloatArray())
                val m = Matrix()
                m.setRotate(Math.toDegrees(start).toFloat(), c[0], c[1])
                shader.setLocalMatrix(m)
                shader
            }
        }
    }

    // ---------------------------------------------------------------------
    // Filters
    // ---------------------------------------------------------------------

    /**
     * The colour part of a CSS filter list as one matrix, in the order the web
     * renderer emits them: brightness, contrast, grayscale, hue-rotate,
     * invert, saturate, sepia, opacity. Null when there is nothing to apply.
     */
    fun colorMatrix(f: Filter?): ColorMatrix? {
        if (f == null) return null
        var out: ColorMatrix? = null
        fun add(m: FloatArray) {
            val cm = ColorMatrix(m)
            if (out == null) out = cm else out!!.postConcat(cm)
        }
        f.brightness?.let { b -> val v = b.toFloat(); add(floatArrayOf(v, 0f, 0f, 0f, 0f, 0f, v, 0f, 0f, 0f, 0f, 0f, v, 0f, 0f, 0f, 0f, 0f, 1f, 0f)) }
        f.contrast?.let { c ->
            val v = c.toFloat()
            val t = 255f * (0.5f - 0.5f * v)
            add(floatArrayOf(v, 0f, 0f, 0f, t, 0f, v, 0f, 0f, t, 0f, 0f, v, 0f, t, 0f, 0f, 0f, 1f, 0f))
        }
        f.grayscale?.let { g ->
            val a = (1 - min(1.0, max(0.0, g))).toFloat()
            add(floatArrayOf(
                0.2126f + 0.7874f * a, 0.7152f - 0.7152f * a, 0.0722f - 0.0722f * a, 0f, 0f,
                0.2126f - 0.2126f * a, 0.7152f + 0.2848f * a, 0.0722f - 0.0722f * a, 0f, 0f,
                0.2126f - 0.2126f * a, 0.7152f - 0.7152f * a, 0.0722f + 0.9278f * a, 0f, 0f,
                0f, 0f, 0f, 1f, 0f,
            ))
        }
        f.hueRotate?.let { deg ->
            val r = Math.toRadians(deg)
            val c = cos(r).toFloat()
            val s = sin(r).toFloat()
            add(floatArrayOf(
                0.213f + c * 0.787f - s * 0.213f, 0.715f - c * 0.715f - s * 0.715f, 0.072f - c * 0.072f + s * 0.928f, 0f, 0f,
                0.213f - c * 0.213f + s * 0.143f, 0.715f + c * 0.285f + s * 0.140f, 0.072f - c * 0.072f - s * 0.283f, 0f, 0f,
                0.213f - c * 0.213f - s * 0.787f, 0.715f - c * 0.715f + s * 0.715f, 0.072f + c * 0.928f + s * 0.072f, 0f, 0f,
                0f, 0f, 0f, 1f, 0f,
            ))
        }
        f.invert?.let { i ->
            val a = min(1.0, max(0.0, i)).toFloat()
            val k = 1 - 2 * a
            val t = 255f * a
            add(floatArrayOf(k, 0f, 0f, 0f, t, 0f, k, 0f, 0f, t, 0f, 0f, k, 0f, t, 0f, 0f, 0f, 1f, 0f))
        }
        f.saturate?.let { sat ->
            val cm = ColorMatrix()
            cm.setSaturation(max(0.0, sat).toFloat())
            add(cm.array)
        }
        f.sepia?.let { sp ->
            val a = (1 - min(1.0, max(0.0, sp))).toFloat()
            add(floatArrayOf(
                0.393f + 0.607f * a, 0.769f - 0.769f * a, 0.189f - 0.189f * a, 0f, 0f,
                0.349f - 0.349f * a, 0.686f + 0.314f * a, 0.168f - 0.168f * a, 0f, 0f,
                0.272f - 0.272f * a, 0.534f - 0.534f * a, 0.131f + 0.869f * a, 0f, 0f,
                0f, 0f, 0f, 1f, 0f,
            ))
        }
        f.opacity?.let { o ->
            val v = min(1.0, max(0.0, o)).toFloat()
            add(floatArrayOf(1f, 0f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 0f, v, 0f))
        }
        return out
    }

    // ---------------------------------------------------------------------
    // Blend modes
    // ---------------------------------------------------------------------

    private fun normalize(mode: String): String = mode.replace(Regex("([A-Z])"), "-$1").lowercase()

    /** A Flutter / CSS blend-mode or composite-operation name on [paint]; false when unknown (source-over). */
    fun applyBlend(paint: Paint, mode: String?): Boolean {
        paint.xfermode = null
        if (Build.VERSION.SDK_INT >= 29) paint.blendMode = null
        if (mode.isNullOrEmpty()) return false
        val m = normalize(mode)
        if (Build.VERSION.SDK_INT >= 29) {
            val bm = blendMode29(m) ?: return false
            if (bm == BlendMode.SRC_OVER) return false
            paint.blendMode = bm
            return true
        }
        val pd = porterDuff(m) ?: return false
        if (pd == PorterDuff.Mode.SRC_OVER) return false
        paint.xfermode = PorterDuffXfermode(pd)
        return true
    }

    private fun blendMode29(m: String): BlendMode? = if (Build.VERSION.SDK_INT < 29) null else when (m) {
        "normal", "src-over", "source-over" -> BlendMode.SRC_OVER
        "multiply" -> BlendMode.MULTIPLY
        "screen" -> BlendMode.SCREEN
        "overlay" -> BlendMode.OVERLAY
        "darken" -> BlendMode.DARKEN
        "lighten" -> BlendMode.LIGHTEN
        "color-dodge" -> BlendMode.COLOR_DODGE
        "color-burn" -> BlendMode.COLOR_BURN
        "hard-light" -> BlendMode.HARD_LIGHT
        "soft-light" -> BlendMode.SOFT_LIGHT
        "difference" -> BlendMode.DIFFERENCE
        "exclusion" -> BlendMode.EXCLUSION
        "hue" -> BlendMode.HUE
        "saturation" -> BlendMode.SATURATION
        "color" -> BlendMode.COLOR
        "luminosity" -> BlendMode.LUMINOSITY
        "plus", "lighter", "plus-lighter" -> BlendMode.PLUS
        "modulate" -> BlendMode.MODULATE
        "clear" -> BlendMode.CLEAR
        "src", "copy" -> BlendMode.SRC
        "dst", "destination" -> BlendMode.DST
        "src-in", "source-in" -> BlendMode.SRC_IN
        "src-out", "source-out" -> BlendMode.SRC_OUT
        "src-atop", "source-atop" -> BlendMode.SRC_ATOP
        "dst-over", "destination-over" -> BlendMode.DST_OVER
        "dst-in", "destination-in" -> BlendMode.DST_IN
        "dst-out", "destination-out" -> BlendMode.DST_OUT
        "dst-atop", "destination-atop" -> BlendMode.DST_ATOP
        "xor" -> BlendMode.XOR
        else -> null
    }

    fun porterDuff(m: String): PorterDuff.Mode? = when (normalize(m)) {
        "normal", "src-over", "source-over" -> PorterDuff.Mode.SRC_OVER
        "multiply", "modulate" -> PorterDuff.Mode.MULTIPLY
        "screen" -> PorterDuff.Mode.SCREEN
        "overlay" -> PorterDuff.Mode.OVERLAY
        "darken" -> PorterDuff.Mode.DARKEN
        "lighten" -> PorterDuff.Mode.LIGHTEN
        "plus", "lighter", "plus-lighter" -> PorterDuff.Mode.ADD
        "clear" -> PorterDuff.Mode.CLEAR
        "src", "copy" -> PorterDuff.Mode.SRC
        "dst", "destination" -> PorterDuff.Mode.DST
        "src-in", "source-in" -> PorterDuff.Mode.SRC_IN
        "src-out", "source-out" -> PorterDuff.Mode.SRC_OUT
        "src-atop", "source-atop" -> PorterDuff.Mode.SRC_ATOP
        "dst-over", "destination-over" -> PorterDuff.Mode.DST_OVER
        "dst-in", "destination-in" -> PorterDuff.Mode.DST_IN
        "dst-out", "destination-out" -> PorterDuff.Mode.DST_OUT
        "dst-atop", "destination-atop" -> PorterDuff.Mode.DST_ATOP
        "xor" -> PorterDuff.Mode.XOR
        else -> null
    }

    // ---------------------------------------------------------------------
    // Cursors
    // ---------------------------------------------------------------------

    /** CSS cursor names → system pointer icons (mouse / stylus hover). */
    fun applyCursor(view: View, cursor: String?) {
        if (cursor.isNullOrEmpty()) {
            view.pointerIcon = null
            return
        }
        val type = when (cursor) {
            "pointer", "click" -> PointerIcon.TYPE_HAND
            "text", "vertical-text" -> PointerIcon.TYPE_TEXT
            "grab" -> PointerIcon.TYPE_GRAB
            "grabbing" -> PointerIcon.TYPE_GRABBING
            "move", "all-scroll" -> PointerIcon.TYPE_ALL_SCROLL
            "crosshair" -> PointerIcon.TYPE_CROSSHAIR
            "not-allowed", "no-drop", "forbidden" -> PointerIcon.TYPE_NO_DROP
            "help" -> PointerIcon.TYPE_HELP
            "wait", "progress" -> PointerIcon.TYPE_WAIT
            "zoom-in" -> PointerIcon.TYPE_ZOOM_IN
            "zoom-out" -> PointerIcon.TYPE_ZOOM_OUT
            "copy" -> PointerIcon.TYPE_COPY
            "alias" -> PointerIcon.TYPE_ALIAS
            "context-menu" -> PointerIcon.TYPE_CONTEXT_MENU
            "cell" -> PointerIcon.TYPE_CELL
            "none" -> PointerIcon.TYPE_NULL
            "ew-resize", "e-resize", "w-resize", "col-resize", "resizeLeftRight", "resizeColumn" -> PointerIcon.TYPE_HORIZONTAL_DOUBLE_ARROW
            "ns-resize", "n-resize", "s-resize", "row-resize", "resizeUpDown", "resizeRow" -> PointerIcon.TYPE_VERTICAL_DOUBLE_ARROW
            "nwse-resize", "nw-resize", "se-resize" -> PointerIcon.TYPE_TOP_LEFT_DIAGONAL_DOUBLE_ARROW
            "nesw-resize", "ne-resize", "sw-resize" -> PointerIcon.TYPE_TOP_RIGHT_DIAGONAL_DOUBLE_ARROW
            else -> PointerIcon.TYPE_ARROW
        }
        view.pointerIcon = PointerIcon.getSystemIcon(view.context, type)
    }
}
