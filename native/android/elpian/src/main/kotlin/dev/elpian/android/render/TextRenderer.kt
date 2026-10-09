package dev.elpian.android.render

import android.annotation.SuppressLint
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.text.Layout
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.StaticLayout
import android.text.TextDirectionHeuristic
import android.text.TextDirectionHeuristics
import android.text.TextPaint
import android.text.TextUtils
import android.text.style.LineHeightSpan
import android.text.style.MetricAffectingSpan
import android.util.LruCache
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.PopupWindow
import android.widget.TextView
import dev.elpian.core.render.TextMetrics
import dev.elpian.core.render.TextSpec
import dev.elpian.core.render.TextStyleSpec
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Typefaces: the platform families (Roboto, serif, monospace), the bundled
 * Material Icons font (`icons`, from `assets/fonts/MaterialIcons-Regular.ttf`)
 * and host-registered families.
 */
object ElpianFonts {
    const val ICON_ASSET = "fonts/MaterialIcons-Regular.ttf"
    private var context: Context? = null
    private val registered = ConcurrentHashMap<String, Typeface>()
    private val cache = ConcurrentHashMap<String, Typeface>()
    private var icons: Typeface? = null

    fun init(context: Context) {
        if (this.context == null) this.context = context.applicationContext
    }

    /** Register a font family by name (e.g. a font shipped by the host app). */
    fun register(family: String, typeface: Typeface) {
        registered[family.lowercase()] = typeface
        cache.clear()
    }

    private fun iconTypeface(): Typeface {
        icons?.let { return it }
        val ctx = context
        val tf = try {
            if (ctx != null) Typeface.createFromAsset(ctx.assets, ICON_ASSET) else Typeface.DEFAULT
        } catch (_: Throwable) {
            Typeface.DEFAULT
        }
        icons = tf
        return tf
    }

    private fun base(family: String?): Typeface = when (family) {
        null, "", "sans-serif" -> Typeface.DEFAULT
        "serif" -> Typeface.SERIF
        "monospace" -> Typeface.MONOSPACE
        "icons" -> iconTypeface()
        else -> registered[family.lowercase()] ?: assetFamily(family) ?: Typeface.create(family, Typeface.NORMAL)
    }

    /** `fonts/<Family>.ttf|otf` in the app's assets, when present. */
    private fun assetFamily(family: String): Typeface? {
        val ctx = context ?: return null
        for (ext in listOf("ttf", "otf")) {
            val path = "fonts/$family.$ext"
            try {
                ctx.assets.open(path).close()
                val tf = Typeface.createFromAsset(ctx.assets, path)
                registered[family.lowercase()] = tf
                return tf
            } catch (_: Throwable) {
            }
        }
        return null
    }

    fun typeface(family: String?, weight: Int, italic: Boolean): Typeface {
        val key = "$family|$weight|$italic"
        cache[key]?.let { return it }
        val b = base(family)
        val tf = if (Build.VERSION.SDK_INT >= 28) {
            Typeface.create(b, weight.coerceIn(1, 1000), italic)
        } else {
            val style = (if (weight >= 600) Typeface.BOLD else 0) or (if (italic) Typeface.ITALIC else 0)
            Typeface.create(b, style)
        }
        cache[key] = tf
        return tf
    }
}

/**
 * One text span's style. Metric-affecting (size, typeface, spacing) so the
 * measurer and the painter lay out identically; the draw state depends on
 * the paint pass (shadow passes paint each span's n-th shadow, the final
 * pass the text itself with its background).
 */
internal class ElpianSpan(val style: TextStyleSpec, val density: Float, val link: String?) : MetricAffectingSpan() {
    companion object {
        /** -1 = the text pass; n ≥ 0 = shadow n. UI thread only. */
        @JvmStatic var pass = -1
        /** Highlight colour for the selected (copied) text, 0 for none. */
        @JvmStatic var selection = 0
    }

    fun apply(tp: TextPaint) {
        val size = (style.fontSize * density).toFloat()
        tp.textSize = size
        tp.typeface = ElpianFonts.typeface(style.fontFamily, style.fontWeight, style.italic)
        tp.isFakeBoldText = false
        tp.letterSpacing = if (style.fontSize > 0) (style.letterSpacing / style.fontSize).toFloat() else 0f
        if (Build.VERSION.SDK_INT >= 29) tp.wordSpacing = (style.wordSpacing * density).toFloat()
        tp.baselineShift = -(style.baselineShift * density).roundToInt()
    }

    override fun updateMeasureState(tp: TextPaint) = apply(tp)

    override fun updateDrawState(tp: TextPaint) {
        apply(tp)
        val p = pass
        if (p < 0) {
            tp.color = style.color
            tp.bgColor = if (selection != 0) selection else style.background ?: 0
            tp.clearShadowLayer()
        } else {
            val s = style.shadows?.getOrNull(p)
            tp.bgColor = 0
            if (s == null) {
                tp.color = Color.TRANSPARENT
                tp.clearShadowLayer()
            } else {
                tp.color = style.color
                tp.setShadowLayer(max(0.01f, Paints.androidBlurRadius(s.blur, density)), (s.dx * density).toFloat(), (s.dy * density).toFloat(), s.color)
            }
        }
    }
}

/**
 * Flutter line heights: each line is as tall as its tallest run, where a run
 * with `height` takes height × fontSize split between ascent and descent in
 * the font's proportions, and the first span acts as the paragraph strut.
 */
internal class ParagraphLineHeight(private val runs: List<TextEngine.Run>, private val strut: TextEngine.Run?) : LineHeightSpan {
    override fun chooseHeight(text: CharSequence, start: Int, end: Int, spanstartv: Int, lineHeight: Int, fm: Paint.FontMetricsInt) {
        var asc = 0.0
        var desc = 0.0
        fun take(r: TextEngine.Run) {
            val (a, d) = r.lineMetrics()
            if (a > asc) asc = a
            if (d > desc) desc = d
        }
        strut?.let { take(it) }
        for (r in runs) if (r.end > start && r.start < max(end, start + 1)) take(r)
        val a = ceil(asc - 0.0001).toInt()
        val total = (asc + desc).roundToInt()
        fm.ascent = -a
        fm.top = -a
        fm.descent = max(0, total - a)
        fm.bottom = fm.descent
        fm.leading = 0
    }
}

/** Builds, measures and lays out paragraphs (the web host's text.ts). */
object TextEngine {
    internal class Run(val start: Int, val end: Int, val span: ElpianSpan) {
        private var metrics: Pair<Double, Double>? = null
        val style: TextStyleSpec get() = span.style

        /** (ascent, descent) in px this run asks of its line. */
        fun lineMetrics(): Pair<Double, Double> {
            metrics?.let { return it }
            val tp = TextPaint(Paint.ANTI_ALIAS_FLAG)
            span.apply(tp)
            val fm = tp.fontMetrics
            val a = -fm.ascent.toDouble()
            val d = fm.descent.toDouble()
            val h = style.height
            val out = if (h != null && h > 0 && a + d > 0) {
                val total = h * style.fontSize * span.density
                total * a / (a + d) to total * d / (a + d)
            } else a to d
            metrics = out
            return out
        }
    }

    internal class Built(val spec: TextSpec, val text: SpannableStringBuilder, val paint: TextPaint, val runs: List<Run>, val strut: Run?, val density: Float) {
        val desiredWidth: Float by lazy { if (text.isEmpty()) 0f else StaticLayout.getDesiredWidth(text, paint) }
    }

    private val measureCache = LruCache<Triple<TextSpec, Long, Float>, TextMetrics>(4000)

    /** Forget cached metrics (fonts or text scale changed). */
    fun clearCache() {
        measureCache.evictAll()
    }

    internal fun build(spec: TextSpec, density: Float): Built {
        val sb = SpannableStringBuilder()
        val runs = ArrayList<Run>()
        for (s in spec.spans) {
            val start = sb.length
            sb.append(s.text)
            val span = ElpianSpan(s.style, density, s.link)
            if (sb.length > start) {
                sb.setSpan(span, start, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                runs.add(Run(start, sb.length, span))
            }
        }
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG)
        paint.density = density
        val first = spec.spans.firstOrNull()
        val strut = first?.let { Run(0, 0, ElpianSpan(it.style, density, null)) }
        strut?.span?.apply(paint)
        if (sb.isNotEmpty()) sb.setSpan(ParagraphLineHeight(runs, strut), 0, sb.length, Spanned.SPAN_INCLUSIVE_INCLUSIVE)
        return Built(spec, sb, paint, runs, strut, density)
    }

    private fun direction(spec: TextSpec): TextDirectionHeuristic = if (spec.direction == "rtl") TextDirectionHeuristics.RTL else TextDirectionHeuristics.LTR

    private fun alignment(spec: TextSpec): Layout.Alignment {
        val rtl = spec.direction == "rtl"
        return when (spec.align) {
            "center" -> Layout.Alignment.ALIGN_CENTER
            "right" -> if (rtl) Layout.Alignment.ALIGN_NORMAL else Layout.Alignment.ALIGN_OPPOSITE
            "left" -> if (rtl) Layout.Alignment.ALIGN_OPPOSITE else Layout.Alignment.ALIGN_NORMAL
            "end" -> Layout.Alignment.ALIGN_OPPOSITE
            else -> Layout.Alignment.ALIGN_NORMAL
        }
    }

    internal fun layout(b: Built, text: CharSequence, width: Int, maxLines: Int?, ellipsize: Boolean): StaticLayout {
        val builder = StaticLayout.Builder.obtain(text, 0, text.length, b.paint, max(1, width))
            .setAlignment(alignment(b.spec))
            .setTextDirection(direction(b.spec))
            .setIncludePad(false)
            .setLineSpacing(0f, 1f)
            .setBreakStrategy(Layout.BREAK_STRATEGY_SIMPLE)
            .setHyphenationFrequency(Layout.HYPHENATION_FREQUENCY_NONE)
        if (maxLines != null && maxLines > 0) builder.setMaxLines(maxLines)
        if (ellipsize) builder.setEllipsize(TextUtils.TruncateAt.END)
        if (Build.VERSION.SDK_INT >= 26 && b.spec.align == "justify") builder.setJustificationMode(Layout.JUSTIFICATION_MODE_INTER_WORD)
        if (Build.VERSION.SDK_INT >= 28) builder.setUseLineSpacingFromFallbacks(false)
        return builder.build()
    }

    /** Metrics for an empty paragraph: one strut line. */
    private fun emptyMetrics(b: Built): TextMetrics {
        val (a, d) = b.strut?.lineMetrics() ?: (0.0 to 0.0)
        return TextMetrics(0.0, ceil((a + d) / b.density * 100) / 100, a / b.density, 1, false)
    }

    /**
     * Flutter's TextPainter contract: width is the max intrinsic width clamped
     * to the constraint, height the laid-out height, baseline the first line's
     * alphabetic baseline.
     */
    fun measure(spec: TextSpec, maxWidth: Double, density: Float): TextMetrics {
        val bounded = maxWidth.isFinite() && maxWidth >= 0
        val key = Triple(spec, if (bounded) Math.round(maxWidth * 1000) else -1L, density)
        measureCache.get(key)?.let { return it }
        val b = build(spec, density)
        if (b.text.isEmpty()) return emptyMetrics(b).also { measureCache.put(key, it) }
        val d = density.toDouble()
        val intrinsic = b.desiredWidth / d
        val maxLines = spec.maxLines?.takeIf { it > 0 }
        var width = intrinsic
        val wraps = bounded && intrinsic > maxWidth + 0.01
        val layoutWidthPx = if (wraps && spec.softWrap) (maxWidth * d).toFloat() else ceil(b.desiredWidth) + 1f
        if (wraps) width = maxWidth
        val lay = layout(b, b.text, floorWidth(layoutWidthPx), maxLines, false)
        var exceeded = false
        if (maxLines != null) {
            val unclamped = layout(b, b.text, floorWidth(layoutWidthPx), null, false)
            exceeded = unclamped.lineCount > maxLines
        } else if (!spec.softWrap && wraps) {
            exceeded = spec.overflow != "visible"
        }
        val lines = if (maxLines != null) min(lay.lineCount, maxLines) else lay.lineCount
        val height = lay.getLineBottom(lines - 1) / d
        val result = TextMetrics(
            width = ceil(width * 100) / 100,
            height = ceil(height * 100) / 100,
            baseline = Math.round(lay.getLineBaseline(0) / d * 1000) / 1000.0,
            lineCount = lines,
            didExceedMaxLines = exceeded,
        )
        measureCache.put(key, result)
        return result
    }

    private fun floorWidth(px: Float): Int = max(1, (px + 0.001f).toInt())

    /** The layout a [TextLeafView] paints for a frame [frameWidthPx] wide. */
    internal fun paintLayout(b: Built, frameWidthPx: Int): StaticLayout {
        val spec = b.spec
        val maxLines = spec.maxLines?.takeIf { it > 0 }
        val desired = ceil(b.desiredWidth).toInt()
        if (spec.softWrap) {
            // The measured width was rounded up; never wrap a line the measurement kept whole.
            var w = frameWidthPx
            if (desired > w && desired - w <= 2) w = desired
            return layout(b, b.text, w, maxLines, spec.overflow == "ellipsis" && maxLines != null)
        }
        if (spec.overflow == "ellipsis" && desired > frameWidthPx + 1) {
            // Ellipsize each hard line on its own (CSS text-overflow on pre text).
            val out = SpannableStringBuilder()
            var start = 0
            val t = b.text
            while (start <= t.length) {
                var nl = TextUtils.indexOf(t, '\n', start)
                if (nl < 0) nl = t.length
                val line = t.subSequence(start, nl)
                out.append(TextUtils.ellipsize(line, b.paint, frameWidthPx.toFloat(), TextUtils.TruncateAt.END))
                if (nl < t.length) out.append('\n')
                start = nl + 1
            }
            if (out.isNotEmpty()) out.setSpan(ParagraphLineHeight(b.runs, b.strut), 0, out.length, Spanned.SPAN_INCLUSIVE_INCLUSIVE)
            return layout(b, out, max(frameWidthPx, ceil(StaticLayout.getDesiredWidth(out, b.paint)).toInt() + 1), maxLines, false)
        }
        return layout(b, b.text, max(frameWidthPx, desired + 1), maxLines, false)
    }
}

/**
 * Paints a [TextSpec] exactly as [TextEngine.measure] laid it out: spans,
 * multiple shadows, decorations with style / colour / thickness, fade
 * overflow, tappable links and (when selectable) long-press copy.
 */
@SuppressLint("ViewConstructor")
class TextLeafView(context: Context, private val owner: ElpianView) : View(context) {
    private var spec: TextSpec? = null
    private var built: TextEngine.Built? = null
    private var layout: StaticLayout? = null
    private var layoutWidth = -1
    private val decoPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val fadePaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var pressedLink: String? = null
    private var selected = false
    private var copyPopup: PopupWindow? = null
    private val handler = Handler(Looper.getMainLooper())
    private var longPress: Runnable? = null
    private var downX = 0f
    private var downY = 0f

    fun setSpec(s: TextSpec?) {
        spec = s
        built = s?.let { TextEngine.build(it, owner.density) }
        layout = null
        contentDescription = s?.spans?.joinToString("") { it.text }
        invalidate()
    }

    private fun ensureLayout(): StaticLayout? {
        val b = built ?: return null
        if (layout == null || layoutWidth != width) {
            layoutWidth = width
            layout = TextEngine.paintLayout(b, width)
        }
        return layout
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        layout = null
    }

    override fun onDraw(canvas: Canvas) {
        val lay = ensureLayout() ?: return
        val s = spec ?: return
        val fade = s.overflow == "fade" && !s.softWrap && lay.width > width
        val save = if (fade) canvas.saveLayer(0f, 0f, width.toFloat(), height.toFloat(), null) else canvas.save()
        // Shadow passes, last shadow first (CSS paints the first one on top).
        val maxShadows = built?.runs?.maxOfOrNull { it.style.shadows?.size ?: 0 } ?: 0
        for (p in maxShadows - 1 downTo 0) {
            ElpianSpan.pass = p
            lay.draw(canvas)
        }
        ElpianSpan.pass = -1
        ElpianSpan.selection = if (selected) 0x6633b5e5 else 0
        lay.draw(canvas)
        ElpianSpan.selection = 0
        drawDecorations(canvas, lay)
        if (fade) {
            val w = width.toFloat()
            fadePaint.shader = LinearGradient(w * 0.85f, 0f, w, 0f, Color.BLACK, Color.TRANSPARENT, Shader.TileMode.CLAMP)
            fadePaint.xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN)
            canvas.drawRect(0f, 0f, w, height.toFloat(), fadePaint)
        }
        canvas.restoreToCount(save)
    }

    private fun drawDecorations(canvas: Canvas, lay: StaticLayout) {
        val b = built ?: return
        val text = lay.text
        val d = owner.density
        for (run in b.runs) {
            val st = run.style
            if (st.decoration == 0) continue
            val tp = TextPaint(b.paint)
            run.span.apply(tp)
            val fm = tp.fontMetrics
            val size = (st.fontSize * d).toFloat()
            val baseThick = if (Build.VERSION.SDK_INT >= 29) tp.underlineThickness else size * 0.0488f
            val thick = max(1f, baseThick * (st.decorationThickness ?: 1.0).toFloat())
            val underPos = if (Build.VERSION.SDK_INT >= 29) tp.underlinePosition else size * 0.0733f
            val strikePos = if (Build.VERSION.SDK_INT >= 29) tp.strikeThruPosition else -size * 0.258f
            decoPaint.reset()
            decoPaint.isAntiAlias = true
            decoPaint.color = st.decorationColor ?: st.color
            decoPaint.strokeWidth = thick
            decoPaint.style = Paint.Style.STROKE
            when (st.decorationStyle) {
                "dotted" -> { decoPaint.pathEffect = DashPathEffect(floatArrayOf(thick, thick), 0f) }
                "dashed" -> { decoPaint.pathEffect = DashPathEffect(floatArrayOf(thick * 4, thick * 2), 0f) }
            }
            val shift = (st.baselineShift * d).toFloat()
            // The run may not map 1:1 onto [text] when lines were ellipsized; clamp to it.
            val rs = min(run.start, text.length)
            val re = min(run.end, text.length)
            for (line in 0 until lay.lineCount) {
                val ls = lay.getLineStart(line)
                var le = lay.getLineVisibleEnd(line)
                val ell = lay.getEllipsisCount(line)
                if (ell > 0) le = min(le, ls + lay.getEllipsisStart(line))
                val s0 = max(rs, ls)
                val e0 = min(re, le)
                if (e0 <= s0) continue
                val xa = lay.getPrimaryHorizontal(s0)
                val xb = if (e0 >= le) (if (lay.getParagraphDirection(line) < 0) lay.getLineLeft(line) else lay.getLineRight(line)) else lay.getPrimaryHorizontal(e0)
                val x0 = min(xa, xb)
                val x1 = max(xa, xb)
                val base = lay.getLineBaseline(line) + shift
                if (st.decoration and 1 != 0) decoLine(canvas, x0, x1, base + underPos + thick / 2, thick, st.decorationStyle)
                if (st.decoration and 2 != 0) decoLine(canvas, x0, x1, base + fm.ascent + thick / 2, thick, st.decorationStyle)
                if (st.decoration and 4 != 0) decoLine(canvas, x0, x1, base + strikePos, thick, st.decorationStyle)
            }
        }
    }

    private fun decoLine(canvas: Canvas, x0: Float, x1: Float, y: Float, thick: Float, style: String?) {
        when (style) {
            "double" -> {
                canvas.drawLine(x0, y - thick, x1, y - thick, decoPaint)
                canvas.drawLine(x0, y + thick, x1, y + thick, decoPaint)
            }
            "wavy" -> {
                val p = Path()
                val amp = thick * 1.5f
                val wl = thick * 4
                var x = x0
                p.moveTo(x, y)
                var up = true
                while (x < x1) {
                    val nx = min(x1, x + wl / 2)
                    p.quadTo((x + nx) / 2, if (up) y - amp else y + amp, nx, y)
                    up = !up
                    x = nx
                }
                canvas.drawPath(p, decoPaint)
            }
            else -> canvas.drawLine(x0, y, x1, y, decoPaint)
        }
    }

    // ---------------------------------------------------------------------
    // Links and selection
    // ---------------------------------------------------------------------

    private fun linkAt(x: Float, y: Float): String? {
        val lay = ensureLayout() ?: return null
        val b = built ?: return null
        if (y < 0 || y > lay.height) return null
        val line = lay.getLineForVertical(y.toInt())
        if (x < lay.getLineLeft(line) || x > lay.getLineRight(line)) return null
        val off = lay.getOffsetForHorizontal(line, x)
        val sp = (lay.text as? Spanned)?.getSpans(max(0, off - 1), min(lay.text.length, off + 1), ElpianSpan::class.java)
        val hit = sp?.firstOrNull { it.link != null && (lay.text as Spanned).getSpanStart(it) <= off && off < (lay.text as Spanned).getSpanEnd(it) }
            ?: b.runs.firstOrNull { it.span.link != null && it.start <= off && off < it.end }?.span
        return hit?.link
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        val s = spec ?: return false
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                pressedLink = linkAt(event.x, event.y)
                downX = event.x
                downY = event.y
                if (s.selectable) {
                    val r = Runnable { showCopy() }
                    longPress = r
                    handler.postDelayed(r, GestureRecognizer.LONG_PRESS_TIMEOUT)
                }
                return pressedLink != null || s.selectable
            }
            MotionEvent.ACTION_MOVE -> {
                if (pressedLink != null && linkAt(event.x, event.y) != pressedLink) pressedLink = null
                if (abs(event.x - downX) > 30 || abs(event.y - downY) > 30) cancelCopyTimer()
            }
            MotionEvent.ACTION_UP -> {
                cancelCopyTimer()
                val link = pressedLink
                pressedLink = null
                if (link != null && linkAt(event.x, event.y) == link) {
                    owner.host.emit(dev.elpian.core.render.ViewEvent(id = owner.viewId, type = "link", value = link))
                    return true
                }
            }
            MotionEvent.ACTION_CANCEL -> {
                cancelCopyTimer()
                pressedLink = null
            }
        }
        return pressedLink != null || s.selectable
    }

    private fun cancelCopyTimer() {
        longPress?.let { handler.removeCallbacks(it) }
        longPress = null
    }

    private fun showCopy() {
        val text = spec?.spans?.joinToString("") { it.text } ?: return
        selected = true
        invalidate()
        val d = owner.density
        val tv = TextView(context)
        tv.text = context.getString(android.R.string.copy)
        tv.setTextColor(Color.WHITE)
        tv.textSize = 14f
        tv.setPadding((16 * d).roundToInt(), (8 * d).roundToInt(), (16 * d).roundToInt(), (8 * d).roundToInt())
        val bg = GradientDrawable()
        bg.setColor(0xf0323232.toInt())
        bg.cornerRadius = 8 * d
        tv.background = bg
        val popup = PopupWindow(tv, ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, true)
        popup.isOutsideTouchable = true
        tv.setOnClickListener {
            (context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager)?.setPrimaryClip(ClipData.newPlainText("text", text))
            popup.dismiss()
        }
        popup.setOnDismissListener {
            selected = false
            copyPopup = null
            invalidate()
        }
        val loc = IntArray(2)
        getLocationInWindow(loc)
        try {
            tv.measure(MeasureSpec.UNSPECIFIED, MeasureSpec.UNSPECIFIED)
            popup.showAtLocation(this, Gravity.NO_GRAVITY, loc[0] + width / 2 - tv.measuredWidth / 2, max(0, loc[1] - tv.measuredHeight - (8 * d).roundToInt()))
            copyPopup = popup
        } catch (_: Throwable) {
            selected = false
        }
    }

    override fun onDetachedFromWindow() {
        cancelCopyTimer()
        copyPopup?.dismiss()
        super.onDetachedFromWindow()
    }
}
