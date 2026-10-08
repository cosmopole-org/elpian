package dev.elpian.android.render

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.animation.LinearInterpolator
import android.view.animation.PathInterpolator
import dev.elpian.core.css.M3
import dev.elpian.core.render.ViewEvent
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Blend two ARGB colours. */
internal fun lerpColor(a: Int, b: Int, t: Float): Int {
    fun ch(s: Int) = (((a shr s) and 0xff) + (((b shr s) and 0xff) - ((a shr s) and 0xff)) * t).roundToInt() and 0xff
    return (ch(24) shl 24) or (ch(16) shl 16) or (ch(8) shl 8) or ch(0)
}

internal fun withAlpha(c: Int, a: Float): Int = ((((c ushr 24) * a).roundToInt().coerceIn(0, 255)) shl 24) or (c and 0xffffff)

/** Shared plumbing for the custom-drawn Material 3 controls. */
@SuppressLint("ViewConstructor")
abstract class MaterialControl(context: Context, protected val owner: ElpianView) : View(context) {
    protected val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    protected val d: Float get() = owner.density
    var colors: Map<String, Any?> = emptyMap()
        set(v) {
            field = v
            invalidate()
        }
    var enabledState = true
        set(v) {
            field = v
            alpha = if (v) 1f else 0.38f
            invalidate()
        }
    protected var pressedOverlay = false

    protected fun color(vararg keys: String, fallback: Int): Int {
        for (k in keys) P.color(colors[k])?.let { return it }
        return fallback
    }

    protected fun emit(type: String, value: Any?) {
        owner.host.emit(ViewEvent(id = owner.viewId, type = type, value = value))
    }

    protected fun drawOverlay(canvas: Canvas, cx: Float, cy: Float, color: Int) {
        if (!pressedOverlay) return
        paint.style = Paint.Style.FILL
        paint.color = withAlpha(color, 0.1f)
        canvas.drawCircle(cx, cy, 20 * d, paint)
    }

    /** Tap handling: press overlay, then [onTap] on release inside. */
    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!enabledState) return false
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> { pressedOverlay = true; invalidate() }
            MotionEvent.ACTION_UP -> {
                pressedOverlay = false
                invalidate()
                if (event.x >= 0 && event.y >= 0 && event.x <= width && event.y <= height) {
                    performClick()
                }
            }
            MotionEvent.ACTION_CANCEL -> { pressedOverlay = false; invalidate() }
        }
        return true
    }

    override fun performClick(): Boolean {
        super.performClick()
        onTap()
        return true
    }

    protected open fun onTap() {}
}

/** Material 3 checkbox: 18 px box, 2 px radius and stroke, animated check. */
@SuppressLint("ViewConstructor")
class CheckboxView(context: Context, owner: ElpianView) : MaterialControl(context, owner) {
    var checked = false
        set(v) {
            if (field != v) {
                field = v
                animateTo(if (v) 1f else 0f)
            }
        }
    private var t = 0f
    private var anim: ValueAnimator? = null

    private fun animateTo(target: Float) {
        anim?.cancel()
        if (!isAttachedToWindow) {
            t = target; invalidate(); return
        }
        anim = ValueAnimator.ofFloat(t, target).apply {
            duration = 150
            addUpdateListener { t = it.animatedValue as Float; invalidate() }
            start()
        }
    }

    override fun onTap() {
        checked = !checked
        emit("change", checked)
    }

    override fun onDraw(canvas: Canvas) {
        val cx = width / 2f
        val cy = height / 2f
        val fill = color("fill", "active", fallback = M3.primary)
        val border = color("border", fallback = M3.onSurfaceVariant)
        drawOverlay(canvas, cx, cy, if (checked) fill else border)
        val s = 18 * d
        val r = RectF(cx - s / 2, cy - s / 2, cx + s / 2, cy + s / 2)
        if (t < 1f) {
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 2 * d
            paint.color = border
            val inset = RectF(r)
            inset.inset(d, d)
            canvas.drawRoundRect(inset, 2 * d, 2 * d, paint)
        }
        if (t > 0f) {
            paint.style = Paint.Style.FILL
            paint.color = withAlpha(fill, t * ((fill ushr 24) / 255f))
            canvas.drawRoundRect(r, 2 * d, 2 * d, paint)
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 2 * d
            paint.strokeCap = Paint.Cap.BUTT
            paint.strokeJoin = Paint.Join.MITER
            paint.color = color("check", fallback = M3.onPrimary)
            val p = Path()
            p.moveTo(r.left + s * 0.15f, r.top + s * 0.45f)
            p.lineTo(r.left + s * 0.4f, r.top + s * 0.7f)
            p.lineTo(r.left + s * 0.4f + (s * 0.45f) * t, r.top + s * 0.7f - (s * 0.45f) * t)
            canvas.drawPath(p, paint)
        }
    }
}

/** Material 3 radio: 20 px ring, 2 px stroke, 10 px dot. */
@SuppressLint("ViewConstructor")
class RadioView(context: Context, owner: ElpianView) : MaterialControl(context, owner) {
    var checked = false
        set(v) {
            field = v
            invalidate()
        }
    var value: Any? = null

    override fun onTap() {
        checked = true
        emit("change", value ?: true)
    }

    override fun onDraw(canvas: Canvas) {
        val cx = width / 2f
        val cy = height / 2f
        val fill = color("fill", "active", fallback = M3.primary)
        val border = color("border", fallback = M3.onSurfaceVariant)
        val c = if (checked) fill else border
        drawOverlay(canvas, cx, cy, c)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 2 * d
        paint.color = c
        canvas.drawCircle(cx, cy, 9 * d, paint)
        if (checked) {
            paint.style = Paint.Style.FILL
            canvas.drawCircle(cx, cy, 5 * d, paint)
        }
    }
}

/** Material 3 switch: 52×32 track, 16 px thumb off / 24 px on (28 px pressed). */
@SuppressLint("ViewConstructor")
class SwitchView(context: Context, owner: ElpianView) : MaterialControl(context, owner) {
    var checked = false
        set(v) {
            if (field != v) {
                field = v
                animateTo(if (v) 1f else 0f)
            }
        }
    private var t = 0f
    private var anim: ValueAnimator? = null

    private fun animateTo(target: Float) {
        anim?.cancel()
        if (!isAttachedToWindow) {
            t = target; invalidate(); return
        }
        anim = ValueAnimator.ofFloat(t, target).apply {
            duration = 150
            addUpdateListener { t = it.animatedValue as Float; invalidate() }
            start()
        }
    }

    override fun onTap() {
        checked = !checked
        emit("change", checked)
    }

    override fun onDraw(canvas: Canvas) {
        val cx = width / 2f
        val cy = height / 2f
        val tw = 52 * d
        val th = 32 * d
        val left = cx - tw / 2
        val top = cy - th / 2
        val active = color("active", "fill", "trackOn", fallback = M3.primary)
        val thumbOn = color("thumb", "thumbOn", fallback = M3.onPrimary)
        val trackOff = color("inactiveTrack", "trackOff", fallback = M3.surfaceContainerHighest)
        val outline = color("border", "outline", fallback = M3.outline)
        val thumbOff = color("inactiveThumb", "thumbOff", fallback = outline)
        val track = RectF(left, top, left + tw, top + th)
        paint.style = Paint.Style.FILL
        paint.color = lerpColor(trackOff, active, t)
        canvas.drawRoundRect(track, th / 2, th / 2, paint)
        if (t < 1f) {
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 2 * d
            paint.color = withAlpha(outline, (1 - t) * ((outline ushr 24) / 255f))
            val inner = RectF(track)
            inner.inset(d, d)
            canvas.drawRoundRect(inner, th / 2 - d, th / 2 - d, paint)
        }
        val size = (if (pressedOverlay) 28f else 16f + 8f * t) * d
        val offX = 14 * d
        val onX = (52 - 4 - 12 - 2 + 0) * d
        val tx = left + offX + (onX - offX) * t
        drawOverlay(canvas, tx, cy, if (checked) active else outline)
        paint.style = Paint.Style.FILL
        paint.color = lerpColor(thumbOff, thumbOn, t)
        canvas.drawCircle(tx, cy, size / 2, paint)
    }
}

/** Material 3 slider: 4 px track, 20 px thumb, optional division ticks. */
@SuppressLint("ViewConstructor")
class SliderView(context: Context, owner: ElpianView) : MaterialControl(context, owner) {
    var min = 0.0
    var max = 1.0
    var step: Double? = null
    var value = 0.0
        set(v) {
            field = v
            invalidate()
        }
    private var dragging = false
    private var downX = 0f
    private var downY = 0f
    private val slop = ViewConfiguration.get(context).scaledTouchSlop

    private val pad: Float get() = 24 * d

    private fun valueAt(x: Float): Double {
        val w = width - 2 * pad
        val f = if (w > 0) ((x - pad) / w).coerceIn(0f, 1f) else 0f
        var v = min + (max - min) * f
        val s = step
        if (s != null && s > 0) v = (min + Math.round((v - min) / s) * s).coerceIn(kotlin.math.min(min, max), kotlin.math.max(min, max))
        return v
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!enabledState) return false
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.x; downY = event.y
                dragging = false
                pressedOverlay = true
                invalidate()
            }
            MotionEvent.ACTION_MOVE -> {
                if (!dragging && abs(event.x - downX) > slop && abs(event.x - downX) > abs(event.y - downY)) {
                    dragging = true
                    parent?.requestDisallowInterceptTouchEvent(true)
                }
                if (dragging) {
                    val v = valueAt(event.x)
                    if (v != value) {
                        value = v
                        emit("input", v)
                    }
                }
            }
            MotionEvent.ACTION_UP -> {
                val v = valueAt(event.x)
                if (v != value || !dragging) {
                    value = v
                    emit("input", v)
                }
                emit("change", value)
                dragging = false
                pressedOverlay = false
                invalidate()
            }
            MotionEvent.ACTION_CANCEL -> {
                if (dragging) emit("change", value)
                dragging = false
                pressedOverlay = false
                invalidate()
            }
        }
        return true
    }

    override fun onDraw(canvas: Canvas) {
        val cy = height / 2f
        val active = color("active", "fill", fallback = M3.primary)
        val inactive = color("inactive", "inactiveTrack", fallback = M3.secondaryContainer)
        val thumb = color("thumb", fallback = active)
        val x0 = pad
        val x1 = width - pad
        val range = max - min
        val f = if (range != 0.0) ((value - min) / range).coerceIn(0.0, 1.0).toFloat() else 0f
        val tx = x0 + (x1 - x0) * f
        val h = 4 * d
        paint.style = Paint.Style.FILL
        paint.color = inactive
        canvas.drawRoundRect(RectF(x0, cy - h / 2, x1, cy + h / 2), h / 2, h / 2, paint)
        paint.color = active
        canvas.drawRoundRect(RectF(x0, cy - h / 2, tx, cy + h / 2), h / 2, h / 2, paint)
        val s = step
        if (s != null && s > 0 && range / s in 1.0..100.0) {
            val n = (range / s).roundToInt()
            for (i in 0..n) {
                val x = x0 + (x1 - x0) * i / n
                paint.color = if (x <= tx) withAlpha(color("activeTick", fallback = M3.onPrimary), 0.38f) else withAlpha(color("inactiveTick", fallback = M3.onSurfaceVariant), 0.38f)
                canvas.drawCircle(x, cy, d, paint)
            }
        }
        if (pressedOverlay) {
            paint.color = P.color(colors["overlay"]) ?: withAlpha(active, 0.12f)
            canvas.drawCircle(tx, cy, 24 * d, paint)
        }
        paint.color = thumb
        canvas.drawCircle(tx, cy, 10 * d, paint)
    }
}

/** Linear or circular progress, determinate or indeterminate (Material timings). */
@SuppressLint("ViewConstructor")
class ProgressView(context: Context, owner: ElpianView) : MaterialControl(context, owner) {
    var circular = false
    var value: Double? = null
        set(v) {
            field = v
            updateAnimation()
            invalidate()
        }
    var strokeWidth: Double? = null
    private var phase = 0f
    private var anim: ValueAnimator? = null

    override fun onTouchEvent(event: MotionEvent): Boolean = false

    private fun updateAnimation() {
        val needs = value == null && isAttachedToWindow
        if (needs && anim == null) {
            anim = ValueAnimator.ofFloat(0f, 1f).apply {
                duration = if (circular) 1400 else 1800
                repeatCount = ValueAnimator.INFINITE
                interpolator = LinearInterpolator()
                addUpdateListener { phase = it.animatedValue as Float; invalidate() }
                start()
            }
        } else if (!needs) {
            anim?.cancel()
            anim = null
        }
    }

    fun setVariant(circular: Boolean) {
        if (this.circular != circular) {
            this.circular = circular
            anim?.cancel()
            anim = null
            updateAnimation()
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        updateAnimation()
    }

    override fun onDetachedFromWindow() {
        anim?.cancel()
        anim = null
        super.onDetachedFromWindow()
    }

    private val ease = PathInterpolator(0.4f, 0f, 0.2f, 1f)
    private val easeInOut = PathInterpolator(0.42f, 0f, 0.58f, 1f)

    override fun onDraw(canvas: Canvas) {
        val indicator = color("indicator", fallback = M3.primary)
        val track = P.color(colors["track"]) ?: Color.TRANSPARENT
        val v = value?.coerceIn(0.0, 1.0)?.toFloat()
        if (circular) {
            val stroke = ((strokeWidth ?: 4.0) * d).toFloat()
            val size = min(width, height).toFloat().takeIf { it > 0 } ?: (36 * d)
            val r = size / 2 - stroke / 2
            val cx = width / 2f
            val cy = height / 2f
            val oval = RectF(cx - r, cy - r, cx + r, cy + r)
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = stroke
            paint.strokeCap = Paint.Cap.BUTT
            if ((track ushr 24) != 0) {
                paint.color = track
                canvas.drawCircle(cx, cy, r, paint)
            }
            paint.color = indicator
            if (v != null) {
                canvas.drawArc(oval, -90f, 360f * v, false, paint)
            } else {
                // elpian-spin (rotate 360° / 1.4 s) with elpian-dash (1 → 60 → 60 of 200, offset 0 → -10 → -80).
                val circ = (2 * Math.PI * 18).toFloat()
                val t = phase
                val half = if (t < 0.5f) easeInOut.getInterpolation(t * 2) else easeInOut.getInterpolation((t - 0.5f) * 2)
                val dash = if (t < 0.5f) 1f + 59f * half else 60f
                val offset = if (t < 0.5f) -10f * half else -10f - 70f * half
                val start = -90f + 360f * t + (-offset / circ) * 360f
                canvas.drawArc(oval, start, 360f * dash / circ, false, paint)
            }
        } else {
            paint.style = Paint.Style.FILL
            if ((track ushr 24) != 0) {
                paint.color = track
                canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
            }
            paint.color = indicator
            if (v != null) {
                canvas.drawRect(0f, 0f, width * v, height.toFloat(), paint)
            } else {
                // elpian-indeterminate: a 40 % bar from -40 % to 100 %.
                val p = ease.getInterpolation(phase)
                val l = width * (-0.4f + 1.4f * p)
                canvas.save()
                canvas.clipRect(0, 0, width, height)
                canvas.drawRect(l, 0f, l + width * 0.4f, height.toFloat(), paint)
                canvas.restore()
            }
        }
    }
}
