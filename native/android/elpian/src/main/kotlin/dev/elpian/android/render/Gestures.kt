package dev.elpian.android.render

import android.animation.ValueAnimator
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.animation.DecelerateInterpolator
import android.widget.PopupWindow
import android.widget.TextView
import dev.elpian.core.render.ViewEvent
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sign

/**
 * Per-pointer-down arena flags shared by the nested recognizers that see the
 * same down event (the DOM version marks the event object itself). The
 * innermost view's recognizer runs first, so outer ones see its claims.
 */
internal object GestureArena {
    private var key = Long.MIN_VALUE
    var tapClaimed = false
    var panClaimed = false

    fun enter(k: Long) {
        if (k != key) {
            key = k
            tapClaimed = false
            panClaimed = false
        }
    }
}

/**
 * Gesture recognition on Elpian views with Flutter's arena semantics where it
 * matters (native/web/src/gestures.ts): the innermost tap recognizer wins a
 * tap, a pan beats a tap once the pointer moves past the touch slop, a
 * double-tap delays the single tap, long-press fires after 500 ms without
 * movement, and a fast pan end is also reported as a swipe. Dismissible and
 * Draggable gestures move the view (or a floating copy of it) natively while
 * they run.
 */
class GestureRecognizer(private val view: ElpianView) {
    companion object {
        const val SLOP = 18.0 // kTouchSlop
        const val DOUBLE_TAP_TIMEOUT = 300L // kDoubleTapTimeout
        const val LONG_PRESS_TIMEOUT = 500L // kLongPressTimeout
        const val SWIPE_VELOCITY = 600.0 // px/s (Dismissible's fling threshold is 700)
        private val TAP_KINDS = listOf("tap", "doubletap", "longpress", "tapdown", "tapup", "tapcancel")
    }

    var kinds: Set<String> = emptySet()
        private set
    var dismissDirection = "horizontal"
    var dragData: Any? = null
    var tooltip: String? = null
    var ripple: Int? = null

    /** Positions in logical px relative to the surface. */
    private class Tracked(val id: Int, var x: Double, var y: Double, val startX: Double, val startY: Double, val t: Long)
    private class Sample(val t: Long, val x: Double, val y: Double)
    private data class C(val x: Double, val y: Double, val localX: Double, val localY: Double)

    private val pointers = LinkedHashMap<Int, Tracked>()
    private var mayPan = false
    private var panning = false
    private var claimed = false
    private var longPressTimer: Runnable? = null
    private var longPressed = false
    private var lastTapTime = 0L
    private var pendingTap: Runnable? = null
    private val velocity = ArrayList<Sample>()
    private var scaleStart: Pair<Double, Double>? = null
    private var dismissOffset = 0.0
    private var dismissAnim: ValueAnimator? = null
    private var feedback: BitmapDrawable? = null
    private var feedbackGrab = floatArrayOf(0f, 0f)
    private var feedbackAlpha = 1f
    private var tooltipPopup: PopupWindow? = null
    private var tooltipTimer: Runnable? = null
    private var tooltipHide: Runnable? = null
    private val handler = Handler(Looper.getMainLooper())

    private val density: Float get() = view.density

    fun configure(list: List<String>) {
        kinds = list.toSet()
        if (has("key") || has("focus")) {
            view.isFocusable = true
            view.isFocusableInTouchMode = true
        }
    }

    fun has(k: String): Boolean = k in kinds

    private fun emit(type: String, c: C? = null, dx: Double? = null, dy: Double? = null, vx: Double? = null, vy: Double? = null, scale: Double? = null, rotation: Double? = null, buttons: Int? = null, pressure: Double? = null, pointerId: Int? = null, direction: String? = null, data: Any? = null, x: Double? = null, y: Double? = null) {
        view.host.emit(ViewEvent(id = view.viewId, type = type, x = x ?: c?.x, y = y ?: c?.y, localX = c?.localX, localY = c?.localY, dx = dx, dy = dy, vx = vx, vy = vy, scale = scale, rotation = rotation, buttons = buttons, pressure = pressure, pointerId = pointerId, direction = direction, data = data))
    }

    private fun rootOrigin(): IntArray {
        val loc = IntArray(2)
        view.host.surface.getLocationOnScreen(loc)
        return loc
    }

    private fun rawX(ev: MotionEvent, i: Int): Float = if (Build.VERSION.SDK_INT >= 29) ev.getRawX(i) else ev.rawX + (ev.getX(i) - ev.x)
    private fun rawY(ev: MotionEvent, i: Int): Float = if (Build.VERSION.SDK_INT >= 29) ev.getRawY(i) else ev.rawY + (ev.getY(i) - ev.y)

    private fun coords(ev: MotionEvent, i: Int): C {
        val o = rootOrigin()
        val d = density
        return C((rawX(ev, i) - o[0]) / d.toDouble(), (rawY(ev, i) - o[1]) / d.toDouble(), ev.getX(i) / d.toDouble(), ev.getY(i) / d.toDouble())
    }

    /** Surface-relative logical coordinates → C with local coordinates derived from the view's position. */
    private fun coordsAt(x: Double, y: Double): C {
        val o = rootOrigin()
        val loc = IntArray(2)
        view.getLocationOnScreen(loc)
        val d = density
        return C(x, y, x - (loc[0] - o[0]) / d, y - (loc[1] - o[1]) / d)
    }

    // ---------------------------------------------------------------------
    // Pointer stream
    // ---------------------------------------------------------------------

    /** Feed one motion event (already in the view's coordinates); true when this recognizer wants the stream. */
    fun onTouch(ev: MotionEvent): Boolean {
        if (kinds.isEmpty() && ripple == null) return false
        when (ev.actionMasked) {
            MotionEvent.ACTION_DOWN -> down(ev, 0, ev.downTime)
            MotionEvent.ACTION_POINTER_DOWN -> down(ev, ev.actionIndex, ev.eventTime * 64 + ev.getPointerId(ev.actionIndex))
            MotionEvent.ACTION_MOVE -> for (i in 0 until ev.pointerCount) if (pointers.containsKey(ev.getPointerId(i))) move(ev, i)
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> up(ev, ev.actionIndex, false)
            MotionEvent.ACTION_CANCEL -> for (i in 0 until ev.pointerCount) up(ev, i, true)
        }
        return true
    }

    private fun down(ev: MotionEvent, i: Int, arenaKey: Long) {
        val mouse = ev.getToolType(i) == MotionEvent.TOOL_TYPE_MOUSE
        if (mouse && ev.actionMasked == MotionEvent.ACTION_DOWN && Build.VERSION.SDK_INT >= 23 && ev.actionButton != 0 && ev.actionButton != MotionEvent.BUTTON_PRIMARY && !has("pointer")) return
        GestureArena.enter(arenaKey)
        val c = coords(ev, i)
        val id = ev.getPointerId(i)
        if (has("pointer")) emit("pointerdown", c, buttons = ev.buttonState.takeIf { mouse } ?: 1, pressure = ev.getPressure(i).toDouble(), pointerId = id)
        pointers[id] = Tracked(id, c.x, c.y, c.x, c.y, ev.eventTime)
        if (pointers.size == 2 && has("scale")) {
            beginScale()
            return
        }
        if (pointers.size > 1) return

        val inner = GestureArena.tapClaimed
        val tapping = TAP_KINDS.any { has(it) }
        claimed = tapping && !inner
        if (claimed) GestureArena.tapClaimed = true
        // Drags: the innermost recognizer that drags wins (Flutter's arena).
        val drags = has("pan") || has("swipe") || has("draggable") || has("dismiss")
        mayPan = drags && !GestureArena.panClaimed
        if (mayPan) GestureArena.panClaimed = true
        // Like `touch-action: none`: ancestors (scroll views) must not steal this drag.
        if ((mayPan && (has("pan") || has("draggable"))) || has("scale") || has("pointer")) view.parent?.requestDisallowInterceptTouchEvent(true)
        panning = false
        longPressed = false
        velocity.clear()
        velocity.add(Sample(ev.eventTime, c.x, c.y))
        if (claimed) {
            if (has("tapdown")) emit("tapdown", c)
            if (has("longpress") || tooltip != null) {
                val r = Runnable {
                    longPressTimer = null
                    longPressed = true
                    if (has("longpress")) emit("longpress", c)
                    if (tooltip != null) showTooltip()
                }
                longPressTimer = r
                handler.postDelayed(r, LONG_PRESS_TIMEOUT)
            }
        }
        if (ripple != null && !inner) startRipple(ev.getX(i), ev.getY(i))
    }

    private fun move(ev: MotionEvent, i: Int) {
        val id = ev.getPointerId(i)
        val p = pointers[id] ?: return
        val c = coords(ev, i)
        val dx = c.x - p.x
        val dy = c.y - p.y
        if (dx == 0.0 && dy == 0.0) return
        p.x = c.x
        p.y = c.y
        if (has("pointer")) emit("pointermove", c, dx = dx, dy = dy, buttons = 1, pressure = ev.getPressure(i).toDouble(), pointerId = id)
        if (scaleStart != null && pointers.size >= 2) {
            updateScale()
            return
        }
        if (pointers.keys.firstOrNull() != id) return
        velocity.add(Sample(ev.eventTime, c.x, c.y))
        if (velocity.size > 20) velocity.removeAt(0)
        val tx = c.x - p.startX
        val ty = c.y - p.startY
        val travelled = hypot(tx, ty)
        if (!panning && travelled > SLOP) {
            cancelLongPress()
            if (claimed && has("tapcancel")) emit("tapcancel")
            claimed = false
            stopRipple()
            if (mayPan) {
                panning = true
                if (has("dismiss")) {
                    val vertical = isVerticalDismiss()
                    if (vertical == (abs(ty) > abs(tx))) view.parent?.requestDisallowInterceptTouchEvent(true)
                } else {
                    view.parent?.requestDisallowInterceptTouchEvent(true)
                }
                if (has("pan")) emit("dragstart", c)
                if (has("draggable")) startFeedback(c)
            }
        }
        if (panning) {
            if (has("pan")) emit("drag", c, dx = dx, dy = dy)
            if (has("draggable")) moveFeedback(c)
            if (has("dismiss")) dragDismiss(tx, ty)
        }
    }

    private fun up(ev: MotionEvent, i: Int, cancelled: Boolean) {
        val id = ev.getPointerId(i)
        val p = pointers.remove(id) ?: return
        val c = coords(ev, i)
        if (has("pointer")) emit(if (cancelled) "pointercancel" else "pointerup", c, pointerId = id)
        if (scaleStart != null) {
            if (pointers.size < 2) {
                scaleStart = null
                emit("scaleend")
            }
            return
        }
        if (pointers.isNotEmpty() && !panning) return
        cancelLongPress()
        stopRipple()
        val v = flingVelocity()
        if (panning) {
            panning = false
            if (has("pan")) emit("dragend", c, vx = v.first, vy = v.second)
            if (has("swipe") && max(abs(v.first), abs(v.second)) > SWIPE_VELOCITY) {
                val direction = if (abs(v.first) > abs(v.second)) (if (v.first < 0) "left" else "right") else if (v.second < 0) "up" else "down"
                emit("swipe", vx = v.first, vy = v.second, direction = direction)
            }
            if (has("draggable")) endFeedback(c, cancelled)
            if (has("dismiss")) endDismiss(v)
            return
        }
        @Suppress("UNUSED_VARIABLE") val unused = p
        if (cancelled || !claimed || longPressed) {
            if (claimed && has("tapcancel") && cancelled) emit("tapcancel")
            return
        }
        if (has("tapup")) emit("tapup", c)
        val now = ev.eventTime
        if (has("doubletap")) {
            val pending = pendingTap
            if (pending != null && now - lastTapTime < DOUBLE_TAP_TIMEOUT) {
                handler.removeCallbacks(pending)
                pendingTap = null
                emit("doubletap", c)
                return
            }
            lastTapTime = now
            // The single tap waits for the double-tap window, as in Flutter.
            val r = Runnable {
                pendingTap = null
                if (has("tap")) emit("tap", c)
            }
            pendingTap = r
            handler.postDelayed(r, DOUBLE_TAP_TIMEOUT)
            return
        }
        if (has("tap")) emit("tap", c)
    }

    /** Accessibility "click" (TalkBack double-tap): a plain tap at the centre. */
    fun accessibilityTap() {
        if (!has("tap")) return
        val d = density
        val loc = IntArray(2)
        view.getLocationOnScreen(loc)
        val o = rootOrigin()
        val lx = view.width / 2.0 / d
        val ly = view.height / 2.0 / d
        emit("tap", C((loc[0] - o[0]) / d + lx, (loc[1] - o[1]) / d + ly, lx, ly))
    }

    private fun flingVelocity(): Pair<Double, Double> {
        val s = velocity
        if (s.size < 2) return 0.0 to 0.0
        val last = s.last()
        var first = s[0]
        for (p in s) if (last.t - p.t <= 100) {
            first = p
            break
        }
        val dt = (last.t - first.t) / 1000.0
        if (dt <= 0) return 0.0 to 0.0
        return (last.x - first.x) / dt to (last.y - first.y) / dt
    }

    private fun cancelLongPress() {
        longPressTimer?.let { handler.removeCallbacks(it) }
        longPressTimer = null
    }

    // ---------------------------------------------------------------------
    // Hover, keys, focus
    // ---------------------------------------------------------------------

    fun onHover(ev: MotionEvent): Boolean {
        if (!ev.isFromSource(InputDevice.SOURCE_MOUSE)) return false
        val c = coords(ev, 0)
        when (ev.actionMasked) {
            MotionEvent.ACTION_HOVER_ENTER -> {
                if (has("hover")) emit("pointerenter", c)
                if (tooltip != null) {
                    val r = Runnable { showTooltip() }
                    tooltipTimer = r
                    handler.postDelayed(r, LONG_PRESS_TIMEOUT)
                }
            }
            MotionEvent.ACTION_HOVER_EXIT -> {
                if (has("hover")) emit("pointerexit", c)
                if (tooltip != null) hideTooltip()
            }
            MotionEvent.ACTION_HOVER_MOVE -> if (has("hover")) emit("pointerhover", c)
        }
        return has("hover") || tooltip != null
    }

    fun onKey(type: String, e: KeyEvent): Boolean {
        if (!has("key")) return false
        val key = Keys.name(e)
        val code = Keys.domKeyCode(e)
        view.host.emit(ViewEvent(id = view.viewId, type = type, key = key, keyCode = code, altKey = e.isAltPressed, ctrlKey = e.isCtrlPressed, shiftKey = e.isShiftPressed, metaKey = e.isMetaPressed))
        if (type == "keydown" && key.length == 1) {
            view.host.emit(ViewEvent(id = view.viewId, type = "keypress", key = key, keyCode = code, altKey = e.isAltPressed, ctrlKey = e.isCtrlPressed, shiftKey = e.isShiftPressed, metaKey = e.isMetaPressed))
        }
        return true
    }

    fun onFocus(gained: Boolean) {
        if (has("focus")) emit(if (gained) "focus" else "blur")
    }

    // ---------------------------------------------------------------------
    // Scale (pinch / rotate)
    // ---------------------------------------------------------------------

    private fun pair(): Pair<Tracked, Tracked> {
        val it = pointers.values.iterator()
        return it.next() to it.next()
    }

    private fun beginScale() {
        cancelLongPress()
        claimed = false
        stopRipple()
        val (a, b) = pair()
        scaleStart = (hypot(b.x - a.x, b.y - a.y).takeIf { it != 0.0 } ?: 1.0) to atan2(b.y - a.y, b.x - a.x)
        emit("scalestart", x = (a.x + b.x) / 2, y = (a.y + b.y) / 2, scale = 1.0, rotation = 0.0)
    }

    private fun updateScale() {
        val (a, b) = pair()
        val s = scaleStart ?: return
        emit("scaleupdate", x = (a.x + b.x) / 2, y = (a.y + b.y) / 2, scale = hypot(b.x - a.x, b.y - a.y) / s.first, rotation = atan2(b.y - a.y, b.x - a.x) - s.second)
    }

    // ---------------------------------------------------------------------
    // Dismissible
    // ---------------------------------------------------------------------

    private fun isVerticalDismiss(): Boolean = Regex("vertical|up|down").containsMatchIn(dismissDirection)

    private fun dragDismiss(dx: Double, dy: Double) {
        val dir = dismissDirection
        val vertical = isVerticalDismiss()
        var d = if (vertical) dy else dx
        if (dir == "endToStart" && d > 0) d = 0.0
        if (dir == "startToEnd" && d < 0) d = 0.0
        if (dir == "up" && d > 0) d = 0.0
        if (dir == "down" && d < 0) d = 0.0
        dismissOffset = d
        dismissAnim?.cancel()
        setDismiss(d, vertical)
    }

    private fun setDismiss(d: Double, vertical: Boolean) {
        val px = (d * density).toFloat()
        view.gestureDx = if (vertical) 0f else px
        view.gestureDy = if (vertical) px else 0f
        view.applyTransform()
    }

    private fun endDismiss(v: Pair<Double, Double>) {
        val vertical = isVerticalDismiss()
        val extent = (if (vertical) view.height else view.width) / density.toDouble()
        val fling = if (vertical) v.second else v.first
        val d = dismissOffset
        val passes = abs(d) > extent * 0.4 || (abs(fling) > 700 && sign(fling) == sign(d) && d != 0.0)
        val target = if (!passes) 0.0 else (sign(d).takeIf { it != 0.0 } ?: 1.0) * extent
        val anim = ValueAnimator.ofFloat(d.toFloat(), target.toFloat())
        anim.duration = 200
        anim.interpolator = DecelerateInterpolator()
        anim.addUpdateListener { setDismiss((it.animatedValue as Float).toDouble(), vertical) }
        dismissAnim = anim
        anim.start()
        if (!passes) {
            dismissOffset = 0.0
            return
        }
        val sgn = sign(d).takeIf { it != 0.0 } ?: 1.0
        val direction = if (vertical) (if (sgn < 0) "up" else "down") else if (sgn < 0) "endToStart" else "startToEnd"
        handler.postDelayed({ emit("dismissed", direction = direction) }, 200)
    }

    // ---------------------------------------------------------------------
    // Draggable
    // ---------------------------------------------------------------------

    private fun startFeedback(c: C) {
        val w = view.width
        val h = view.height
        if (w > 0 && h > 0) {
            try {
                val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                view.draw(Canvas(bmp))
                val dr = BitmapDrawable(view.resources, bmp)
                dr.alpha = (0.7f * 255).roundToInt()
                val root = view.host.surface
                val o = rootOrigin()
                val loc = IntArray(2)
                view.getLocationOnScreen(loc)
                val left = loc[0] - o[0]
                val top = loc[1] - o[1]
                dr.setBounds(left, top, left + w, top + h)
                feedbackGrab = floatArrayOf((c.x * density - left).toFloat(), (c.y * density - top).toFloat())
                root.overlay.add(dr)
                feedback = dr
            } catch (_: Throwable) {
            }
        }
        feedbackAlpha = view.alpha
        view.alpha = 0.3f
        emit("dragstart", c, data = dragData)
    }

    private fun moveFeedback(c: C) {
        feedback?.let { f ->
            val left = (c.x * density - feedbackGrab[0]).roundToInt()
            val top = (c.y * density - feedbackGrab[1]).roundToInt()
            f.setBounds(left, top, left + f.bounds.width(), top + f.bounds.height())
            view.host.surface.invalidate()
        }
        emit("dragupdate", x = c.x, y = c.y, data = dragData)
    }

    private fun endFeedback(c: C, cancelled: Boolean) {
        removeFeedback()
        view.alpha = feedbackAlpha
        emit(if (cancelled) "dragend" else "drop", x = c.x, y = c.y, data = dragData)
    }

    private fun removeFeedback() {
        feedback?.let {
            view.host.surface.overlay.remove(it)
            it.bitmap?.recycle()
        }
        feedback = null
    }

    // ---------------------------------------------------------------------
    // Ripple and tooltip
    // ---------------------------------------------------------------------

    private fun startRipple(x: Float, y: Float) {
        view.drawableHotspotChanged(x, y)
        view.isPressed = true
    }

    private fun stopRipple() {
        if (view.isPressed) view.isPressed = false
    }

    private fun showTooltip() {
        val text = tooltip ?: return
        if (tooltipPopup != null) return
        val ctx = view.context
        val d = density
        // Material Tooltip: grey 700 @ 90%, 4 px radius, 12 px white text, 24 px below.
        val tv = TextView(ctx)
        tv.text = text
        tv.setTextColor(Color.WHITE)
        tv.setTextSize(TypedValue.COMPLEX_UNIT_PX, 12 * d)
        tv.gravity = Gravity.CENTER_VERTICAL
        tv.minHeight = (24 * d).roundToInt()
        tv.setPadding((8 * d).roundToInt(), (4 * d).roundToInt(), (8 * d).roundToInt(), (4 * d).roundToInt())
        val bg = GradientDrawable()
        bg.setColor(0xe6616161.toInt())
        bg.cornerRadius = 4 * d
        tv.background = bg
        tv.measure(View.MeasureSpec.UNSPECIFIED, View.MeasureSpec.UNSPECIFIED)
        val popup = PopupWindow(tv, ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, false)
        popup.isTouchable = false
        val loc = IntArray(2)
        view.getLocationInWindow(loc)
        val x = loc[0] + view.width / 2 - tv.measuredWidth / 2
        val y = loc[1] + view.height + (24 * d).roundToInt() - tv.measuredHeight / 2
        try {
            popup.showAtLocation(view, Gravity.NO_GRAVITY, x, y)
            tooltipPopup = popup
            val r = Runnable { hideTooltip() }
            tooltipHide = r
            handler.postDelayed(r, 1500)
        } catch (_: Throwable) {
        }
    }

    private fun hideTooltip() {
        tooltipTimer?.let { handler.removeCallbacks(it) }
        tooltipTimer = null
        tooltipHide?.let { handler.removeCallbacks(it) }
        tooltipHide = null
        try {
            tooltipPopup?.dismiss()
        } catch (_: Throwable) {
        }
        tooltipPopup = null
    }

    /** The view left the window: drop timers and floating feedback. */
    fun detached() {
        cancelLongPress()
        pendingTap?.let { handler.removeCallbacks(it) }
        pendingTap = null
        hideTooltip()
        removeFeedback()
    }

    fun dispose() {
        detached()
        dismissAnim?.cancel()
        pointers.clear()
        stopRipple()
    }
}

/** DOM `KeyboardEvent.key` / `keyCode` for Android key events. */
object Keys {
    fun name(e: KeyEvent): String = when (e.keyCode) {
        KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> "Enter"
        KeyEvent.KEYCODE_ESCAPE -> "Escape"
        KeyEvent.KEYCODE_DEL -> "Backspace"
        KeyEvent.KEYCODE_FORWARD_DEL -> "Delete"
        KeyEvent.KEYCODE_TAB -> "Tab"
        KeyEvent.KEYCODE_SPACE -> " "
        KeyEvent.KEYCODE_DPAD_UP -> "ArrowUp"
        KeyEvent.KEYCODE_DPAD_DOWN -> "ArrowDown"
        KeyEvent.KEYCODE_DPAD_LEFT -> "ArrowLeft"
        KeyEvent.KEYCODE_DPAD_RIGHT -> "ArrowRight"
        KeyEvent.KEYCODE_DPAD_CENTER -> "Enter"
        KeyEvent.KEYCODE_MOVE_HOME -> "Home"
        KeyEvent.KEYCODE_MOVE_END -> "End"
        KeyEvent.KEYCODE_PAGE_UP -> "PageUp"
        KeyEvent.KEYCODE_PAGE_DOWN -> "PageDown"
        KeyEvent.KEYCODE_SHIFT_LEFT, KeyEvent.KEYCODE_SHIFT_RIGHT -> "Shift"
        KeyEvent.KEYCODE_CTRL_LEFT, KeyEvent.KEYCODE_CTRL_RIGHT -> "Control"
        KeyEvent.KEYCODE_ALT_LEFT, KeyEvent.KEYCODE_ALT_RIGHT -> "Alt"
        KeyEvent.KEYCODE_META_LEFT, KeyEvent.KEYCODE_META_RIGHT -> "Meta"
        KeyEvent.KEYCODE_CAPS_LOCK -> "CapsLock"
        KeyEvent.KEYCODE_INSERT -> "Insert"
        KeyEvent.KEYCODE_BACK -> "GoBack"
        in KeyEvent.KEYCODE_F1..KeyEvent.KEYCODE_F12 -> "F${e.keyCode - KeyEvent.KEYCODE_F1 + 1}"
        else -> {
            val u = e.unicodeChar
            if (u != 0 && !Character.isISOControl(u)) String(Character.toChars(u)) else "Unidentified"
        }
    }

    fun domKeyCode(e: KeyEvent): Int = when (val k = e.keyCode) {
        KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER, KeyEvent.KEYCODE_DPAD_CENTER -> 13
        KeyEvent.KEYCODE_DEL -> 8
        KeyEvent.KEYCODE_TAB -> 9
        KeyEvent.KEYCODE_ESCAPE -> 27
        KeyEvent.KEYCODE_SPACE -> 32
        KeyEvent.KEYCODE_PAGE_UP -> 33
        KeyEvent.KEYCODE_PAGE_DOWN -> 34
        KeyEvent.KEYCODE_MOVE_END -> 35
        KeyEvent.KEYCODE_MOVE_HOME -> 36
        KeyEvent.KEYCODE_DPAD_LEFT -> 37
        KeyEvent.KEYCODE_DPAD_UP -> 38
        KeyEvent.KEYCODE_DPAD_RIGHT -> 39
        KeyEvent.KEYCODE_DPAD_DOWN -> 40
        KeyEvent.KEYCODE_INSERT -> 45
        KeyEvent.KEYCODE_FORWARD_DEL -> 46
        KeyEvent.KEYCODE_SHIFT_LEFT, KeyEvent.KEYCODE_SHIFT_RIGHT -> 16
        KeyEvent.KEYCODE_CTRL_LEFT, KeyEvent.KEYCODE_CTRL_RIGHT -> 17
        KeyEvent.KEYCODE_ALT_LEFT, KeyEvent.KEYCODE_ALT_RIGHT -> 18
        in KeyEvent.KEYCODE_0..KeyEvent.KEYCODE_9 -> 48 + (k - KeyEvent.KEYCODE_0)
        in KeyEvent.KEYCODE_A..KeyEvent.KEYCODE_Z -> 65 + (k - KeyEvent.KEYCODE_A)
        in KeyEvent.KEYCODE_F1..KeyEvent.KEYCODE_F12 -> 112 + (k - KeyEvent.KEYCODE_F1)
        else -> k
    }
}
