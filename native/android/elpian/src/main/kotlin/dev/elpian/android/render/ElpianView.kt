package dev.elpian.android.render

import android.annotation.SuppressLint
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorMatrixColorFilter
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.RenderEffect
import android.graphics.Shader
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Build
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.view.accessibility.AccessibilityNodeInfo
import dev.elpian.core.css.BorderRadius
import dev.elpian.core.css.Filter
import dev.elpian.core.css.Gradient
import dev.elpian.core.css.Matrix as CoreMatrix
import dev.elpian.core.css.Matrix4
import dev.elpian.core.render.ViewEvent
import kotlin.math.atan2
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Async bitmap loading (the platform's image cache). */
fun interface ImageSource {
    /** Load [src]; [callback] runs on the UI thread with the bitmap, or null on failure. */
    fun load(src: String, callback: (Bitmap?) -> Unit)
}

/** What views need from the renderer. */
interface ViewHost {
    val density: Float
    val surface: ElpianSurfaceView
    val images: ImageSource
    fun emit(event: ViewEvent)
}

/**
 * A ViewGroup whose children are positioned at absolute frames (device px)
 * and painted in z-index order. Children never get clipped to this group's
 * bounds (Flutter paints overflow and shadows), and a child with a transform
 * the View properties cannot express (skew / perspective) is drawn through
 * Canvas.concat.
 */
abstract class ElpianGroup(context: Context, attrs: android.util.AttributeSet? = null, defStyle: Int = 0) : ViewGroup(context, attrs, defStyle) {
    private var order: IntArray? = null

    init {
        clipChildren = false
        clipToPadding = false
        setWillNotDraw(false)
        isMotionEventSplittingEnabled = true
    }

    /** The size this group lays itself out at, when it is not measured by a parent's spec. */
    protected open fun ownSize(widthSpec: Int, heightSpec: Int): Pair<Int, Int> =
        MeasureSpec.getSize(widthSpec) to MeasureSpec.getSize(heightSpec)

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val (w, h) = ownSize(widthMeasureSpec, heightMeasureSpec)
        setMeasuredDimension(w, h)
        for (i in 0 until childCount) {
            val c = getChildAt(i)
            if (c is ElpianView) {
                c.measure(MeasureSpec.makeMeasureSpec(c.framePx.width(), MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(c.framePx.height(), MeasureSpec.EXACTLY))
            } else {
                c.measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(h, MeasureSpec.EXACTLY))
            }
        }
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        for (i in 0 until childCount) {
            val c = getChildAt(i)
            if (c is ElpianView) {
                val f = c.framePx
                c.layout(f.left, f.top, f.right, f.bottom)
            } else {
                c.layout(0, 0, r - l, b - t)
            }
        }
    }

    /** Recompute the z-order after a child's zIndex or the child list changed. */
    fun invalidateOrder() {
        var any = false
        for (i in 0 until childCount) if ((getChildAt(i) as? ElpianView)?.zIndex?.let { it != 0.0 } == true) any = true
        if (!any) {
            order = null
            isChildrenDrawingOrderEnabled = false
        } else {
            val idx = (0 until childCount).sortedWith(compareBy({ (getChildAt(it) as? ElpianView)?.zIndex ?: 0.0 }, { it }))
            order = idx.toIntArray()
            isChildrenDrawingOrderEnabled = true
        }
        invalidate()
    }

    override fun onViewAdded(child: View?) {
        super.onViewAdded(child)
        if (order != null || (child as? ElpianView)?.zIndex?.let { it != 0.0 } == true) invalidateOrder()
    }

    override fun onViewRemoved(child: View?) {
        super.onViewRemoved(child)
        if (order != null) invalidateOrder()
    }

    override fun getChildDrawingOrder(childCount: Int, drawingPosition: Int): Int {
        val o = order
        if (o == null || o.size != childCount) return drawingPosition
        return o[drawingPosition]
    }

    override fun drawChild(canvas: Canvas, child: View, drawingTime: Long): Boolean {
        val m = (child as? ElpianView)?.drawMatrix
        if (m == null) return super.drawChild(canvas, child, drawingTime)
        val save = canvas.save()
        canvas.translate(child.left.toFloat(), child.top.toFloat())
        canvas.concat(m)
        canvas.translate(-child.left.toFloat(), -child.top.toFloat())
        val r = super.drawChild(canvas, child, drawingTime)
        canvas.restoreToCount(save)
        return r
    }

    // ---------------------------------------------------------------------
    // Touches through skew / perspective transforms
    // ---------------------------------------------------------------------

    /** The matrix-transformed child that owns the current touch stream. */
    private var matrixTarget: ElpianView? = null
    private var disallowIntercept = false

    override fun requestDisallowInterceptTouchEvent(disallowIntercept: Boolean) {
        this.disallowIntercept = disallowIntercept
        super.requestDisallowInterceptTouchEvent(disallowIntercept)
    }

    private fun hasMatrixChild(): Boolean {
        for (i in 0 until childCount) if ((getChildAt(i) as? ElpianView)?.drawMatrix != null) return true
        return false
    }

    /**
     * This group's view coordinates → [child]'s local coordinates through the
     * inverse of what [drawChild] paints: p = T(-translation) · M⁻¹ · (q + scroll − origin).
     * The 3×3 projective inverse unprojects onto the z = 0 plane, as Flutter's
     * hit testing does through the inverse Matrix4.
     */
    private fun inverseFor(child: ElpianView): Matrix? {
        val m = child.drawMatrix ?: return null
        val inv = Matrix()
        if (!m.invert(inv)) return null
        val t = Matrix()
        t.setTranslate((scrollX - child.left).toFloat(), (scrollY - child.top).toFloat())
        t.postConcat(inv)
        t.postTranslate(-child.translationX, -child.translationY)
        return t
    }

    private fun isAffine(m: Matrix): Boolean {
        val v = FloatArray(9)
        m.getValues(v)
        return v[6] == 0f && v[7] == 0f && v[8] == 1f
    }

    /**
     * [ev] mapped into [child]. Affine maps (incl. skew) go through
     * MotionEvent.transform; perspective maps are applied exactly to the
     * action pointer (other pointers follow by the same offset). Raw screen
     * coordinates are preserved either way.
     */
    private fun mapInto(child: ElpianView, ev: MotionEvent, t: Matrix): MotionEvent {
        val copy = MotionEvent.obtain(ev)
        if (isAffine(t)) {
            copy.transform(t)
        } else {
            val i = if (ev.actionMasked == MotionEvent.ACTION_POINTER_DOWN || ev.actionMasked == MotionEvent.ACTION_POINTER_UP) ev.actionIndex else 0
            val pts = floatArrayOf(ev.getX(i), ev.getY(i))
            t.mapPoints(pts)
            copy.offsetLocation(pts[0] - ev.getX(i), pts[1] - ev.getY(i))
        }
        return copy
    }

    private fun route(child: ElpianView, ev: MotionEvent): Boolean {
        val t = inverseFor(child) ?: return false
        val copy = mapInto(child, ev, t)
        child.matrixRouted = true
        try {
            return child.dispatchTouchEvent(copy)
        } finally {
            child.matrixRouted = false
            copy.recycle()
        }
    }

    private fun hits(child: ElpianView, ev: MotionEvent): Boolean {
        val t = inverseFor(child) ?: return false
        val pts = floatArrayOf(ev.x, ev.y)
        t.mapPoints(pts)
        return pts[0] >= 0 && pts[1] >= 0 && pts[0] <= child.width && pts[1] <= child.height
    }

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        val action = ev.actionMasked
        if (action == MotionEvent.ACTION_DOWN) {
            matrixTarget = null
            disallowIntercept = false
        }
        val target = matrixTarget
        if (target != null) {
            if (!disallowIntercept && onInterceptTouchEvent(ev)) {
                // An ancestor gesture (e.g. this scroll view) takes the stream over.
                val cancel = MotionEvent.obtain(ev)
                cancel.action = MotionEvent.ACTION_CANCEL
                route(target, cancel)
                cancel.recycle()
                matrixTarget = null
                return onTouchEvent(ev)
            }
            val r = route(target, ev)
            if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) matrixTarget = null
            return r || true
        }
        if (action != MotionEvent.ACTION_DOWN || !hasMatrixChild()) return super.dispatchTouchEvent(ev)
        // Hit-test children top-down in paint order; transformed ones by their drawn shape.
        val hit = android.graphics.Rect()
        var superTried = false
        val n = childCount
        for (pos in n - 1 downTo 0) {
            val child = getChildAt(getChildDrawingOrder(n, pos)) ?: continue
            if (child.visibility != View.VISIBLE) continue
            if (child is ElpianView && child.drawMatrix != null) {
                if (!hits(child, ev)) continue
                if (onInterceptTouchEvent(ev)) return super.dispatchTouchEvent(ev)
                if (route(child, ev)) {
                    matrixTarget = child
                    return true
                }
            } else if (!superTried) {
                child.getHitRect(hit)
                if (hit.contains((ev.x + scrollX).toInt(), (ev.y + scrollY).toInt())) {
                    superTried = true
                    if (super.dispatchTouchEvent(ev)) return true
                }
            }
        }
        return if (superTried) false else super.dispatchTouchEvent(ev)
    }

    override fun dispatchSetPressed(pressed: Boolean) {
        // Pressed state (ripples) never propagates to child views.
    }

    override fun shouldDelayChildPressedState(): Boolean = false
}

/**
 * The platform-owned root of one surface (view id 0). Hosts add it to their
 * layout; the renderer creates every top-level view inside it.
 */
class ElpianSurfaceView(context: Context) : ElpianGroup(context) {
    /** Called with the new size (px) whenever the surface is resized. */
    var onSizeChanged: ((Int, Int) -> Unit)? = null
    /** Called when the window insets (safe area) change. */
    var onInsetsChanged: (() -> Unit)? = null
    /** Safe-area insets in device px (top, right, bottom, left). */
    var safeInsets = IntArray(4)
        private set

    init {
        isFocusable = true
        isFocusableInTouchMode = false
        setOnApplyWindowInsetsListener { _, insets ->
            val next = if (Build.VERSION.SDK_INT >= 30) {
                val i = insets.getInsets(android.view.WindowInsets.Type.systemBars() or android.view.WindowInsets.Type.displayCutout())
                intArrayOf(i.top, i.right, i.bottom, i.left)
            } else {
                @Suppress("DEPRECATION")
                var arr = intArrayOf(insets.systemWindowInsetTop, insets.systemWindowInsetRight, insets.systemWindowInsetBottom, insets.systemWindowInsetLeft)
                if (Build.VERSION.SDK_INT >= 28) insets.displayCutout?.let { c ->
                    arr = intArrayOf(max(arr[0], c.safeInsetTop), max(arr[1], c.safeInsetRight), max(arr[2], c.safeInsetBottom), max(arr[3], c.safeInsetLeft))
                }
                arr
            }
            if (!next.contentEquals(safeInsets)) {
                safeInsets = next
                onInsetsChanged?.invoke()
            }
            insets
        }
    }

    override fun ownSize(widthSpec: Int, heightSpec: Int): Pair<Int, Int> {
        val w = if (MeasureSpec.getMode(widthSpec) == MeasureSpec.UNSPECIFIED) suggestedMinimumWidth else MeasureSpec.getSize(widthSpec)
        val h = if (MeasureSpec.getMode(heightSpec) == MeasureSpec.UNSPECIFIED) suggestedMinimumHeight else MeasureSpec.getSize(heightSpec)
        return w to h
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w != oldw || h != oldh) onSizeChanged?.invoke(w, h)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        requestApplyInsets()
    }

    override fun dispatchDraw(canvas: Canvas) {
        // The surface clips like the web host's root (overflow: hidden).
        val save = canvas.save()
        canvas.clipRect(0, 0, width, height)
        super.dispatchDraw(canvas)
        canvas.restoreToCount(save)
    }
}

/**
 * One Elpian view: an absolutely positioned box that paints its decoration
 * itself, hosts its leaf content (paragraph, image, control…) at index 0 and
 * its child views above it, clipping the children (not its own shadow) when
 * asked — Flutter's Container + ClipRRect.
 */
@SuppressLint("ViewConstructor")
class ElpianView(context: Context, val viewId: Int, val kind: String, internal val host: ViewHost) : ElpianGroup(context) {
    /** The frame in logical px relative to the parent view. */
    var frame = DoubleArray(4)
        private set
    /** The frame in device px. */
    val framePx = Rect()

    internal var decoration: DecorationPainter? = null
    internal var clip = false
    internal var radius: BorderRadius? = null
    internal var oval = false
    var zIndex = 0.0
        internal set
    internal var pointerEventsNone = false
    internal var hitOpaque = false
    internal var gestures: GestureRecognizer? = null
    internal var shaderMask: Gradient? = null
    internal var backdropFilter: Filter? = null
    internal var role: String? = null

    /** A transform that View properties cannot express, drawn by the parent. */
    internal var drawMatrix: Matrix? = null
    /** True while the parent dispatches a touch mapped through [drawMatrix]'s inverse. */
    internal var matrixRouted = false
    private var transform: Matrix4? = null
    private var transformOrigin: DoubleArray? = null
    /** Gesture-driven offsets (Dismissible), in device px. */
    internal var gestureDx = 0f
    internal var gestureDy = 0f

    /** The leaf content (index 0), if this kind has one. */
    internal var leaf: View? = null
    /** Where child views are inserted: this view, or a scroll container's content. */
    internal var childHost: ElpianGroup = this

    private val clipPath = Path()
    private val rectF = RectF()
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private var preDraw: ViewTreeObserver.OnPreDrawListener? = null

    init {
        isFocusable = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_AUTO
    }

    val density: Float get() = host.density

    override fun ownSize(widthSpec: Int, heightSpec: Int): Pair<Int, Int> = framePx.width() to framePx.height()

    // ---------------------------------------------------------------------
    // Frame and transform
    // ---------------------------------------------------------------------

    fun setFrame(f: DoubleArray) {
        frame = f.copyOf(4)
        val d = density
        val l = (f[0] * d).roundToInt()
        val t = (f[1] * d).roundToInt()
        val r = ((f[0] + f[2]) * d).roundToInt()
        val b = ((f[1] + f[3]) * d).roundToInt()
        val sizeChanged = r - l != framePx.width() || b - t != framePx.height()
        framePx.set(l, t, r, b)
        // Position immediately (no layout traversal) and re-place children on resize.
        if (sizeChanged || isLayoutRequested) {
            measure(MeasureSpec.makeMeasureSpec(r - l, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(b - t, MeasureSpec.EXACTLY))
        }
        layout(l, t, r, b)
        if (sizeChanged) {
            decoration?.clearCaches()
            updateRippleMask()
        }
        invalidate()
    }

    fun setTransform(m: Matrix4?, origin: DoubleArray?) {
        transform = m
        transformOrigin = origin
        applyTransform()
    }

    internal fun applyTransform() {
        val d = density
        val m = transform
        pivotX = 0f
        pivotY = 0f
        val old = drawMatrix
        drawMatrix = null
        if (m == null || CoreMatrix.isIdentity(m)) {
            rotation = 0f; scaleX = 1f; scaleY = 1f
            translationX = gestureDx; translationY = gestureDy
        } else {
            val o = transformOrigin
            val mm = if (o != null && o.size >= 2) CoreMatrix.aboutOrigin(m, o[0], o[1]) else m
            val a = mm[0]; val b = mm[1]; val c = mm[4]; val dd = mm[5]
            val tx = mm[12]; val ty = mm[13]
            val affine = abs(mm[3]) < 1e-9 && abs(mm[7]) < 1e-9 && abs(mm[15] - 1) < 1e-9
            val sx = hypot(a, b)
            val orthogonal = sx > 1e-9 && abs(a * c + b * dd) < 1e-6 * max(1.0, sx * hypot(c, dd))
            if (affine && orthogonal) {
                val sy = (a * dd - b * c) / sx
                rotation = Math.toDegrees(atan2(b, a)).toFloat()
                scaleX = sx.toFloat()
                scaleY = sy.toFloat()
                translationX = (tx * d).toFloat() + gestureDx
                translationY = (ty * d).toFloat() + gestureDy
            } else {
                rotation = 0f; scaleX = 1f; scaleY = 1f
                translationX = gestureDx; translationY = gestureDy
                val mx = Matrix()
                mx.setValues(floatArrayOf(
                    a.toFloat(), c.toFloat(), (tx * d).toFloat(),
                    b.toFloat(), dd.toFloat(), (ty * d).toFloat(),
                    (mm[3] / d).toFloat(), (mm[7] / d).toFloat(), mm[15].toFloat(),
                ))
                drawMatrix = mx
            }
        }
        if (old != null || drawMatrix != null) (parent as? View)?.invalidate()
    }

    // ---------------------------------------------------------------------
    // Effects: filters, blend modes
    // ---------------------------------------------------------------------

    private var filter: Filter? = null
    private var blendMode: String? = null

    fun setEffects(filter: Filter?, blendMode: String?) {
        this.filter = filter
        this.blendMode = blendMode
        val d = density
        val cm = Paints.colorMatrix(filter)
        val layerPaint = Paint()
        var needsLayer = Paints.applyBlend(layerPaint, blendMode)
        if (Build.VERSION.SDK_INT >= 31) {
            var effect: RenderEffect? = null
            val blur = filter?.blur ?: 0.0
            if (blur > 0) {
                val r = blurRadius(blur * d)
                effect = RenderEffect.createBlurEffect(r, r, Shader.TileMode.DECAL)
            }
            if (cm != null) {
                val cf = ColorMatrixColorFilter(cm)
                effect = if (effect != null) RenderEffect.createColorFilterEffect(cf, effect) else RenderEffect.createColorFilterEffect(cf)
            }
            filter?.dropShadow?.let { s ->
                val source = effect ?: RenderEffect.createOffsetEffect(0f, 0f)
                var shadow = RenderEffect.createColorFilterEffect(PorterDuffColorFilter(s.color, PorterDuff.Mode.SRC_IN), source)
                if (s.blur > 0) {
                    val r = blurRadius(Paints.sigma(s.blur) * d)
                    shadow = RenderEffect.createBlurEffect(r, r, shadow, Shader.TileMode.DECAL)
                }
                shadow = RenderEffect.createOffsetEffect((s.dx * d).toFloat(), (s.dy * d).toFloat(), shadow)
                effect = RenderEffect.createBlendModeEffect(shadow, source, android.graphics.BlendMode.SRC_OVER)
            }
            setRenderEffect(effect)
        } else if (cm != null) {
            layerPaint.colorFilter = ColorMatrixColorFilter(cm)
            needsLayer = true
        }
        if (needsLayer) setLayerType(LAYER_TYPE_HARDWARE, layerPaint) else setLayerType(LAYER_TYPE_NONE, null)
    }

    /** RenderEffect blur radii go through Skia's radius→sigma conversion. */
    private fun blurRadius(sigmaPx: Double): Float = if (sigmaPx <= 0.5) 0.01f else ((sigmaPx - 0.5) / 0.57735).toFloat()

    fun setBackdrop(f: Filter?) {
        backdropFilter = f
        if (f != null && preDraw == null && isAttachedToWindow) attachPreDraw()
        if (f == null) detachPreDraw()
        invalidate()
    }

    private fun attachPreDraw() {
        val l = ViewTreeObserver.OnPreDrawListener {
            if (backdropFilter != null) invalidate()
            true
        }
        viewTreeObserver.addOnPreDrawListener(l)
        preDraw = l
    }

    private fun detachPreDraw() {
        preDraw?.let { if (viewTreeObserver.isAlive) viewTreeObserver.removeOnPreDrawListener(it) }
        preDraw = null
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (backdropFilter != null && preDraw == null) attachPreDraw()
    }

    override fun onDetachedFromWindow() {
        detachPreDraw()
        gestures?.detached()
        super.onDetachedFromWindow()
    }

    // ---------------------------------------------------------------------
    // Ripple (Material ink) as the view's foreground
    // ---------------------------------------------------------------------

    internal var rippleColor: Int? = null
        set(v) {
            val changed = field != v
            field = v
            if (changed) updateRippleMask()
        }

    internal fun updateRippleMask() {
        val color = rippleColor
        if (color == null) {
            if (foreground is RippleDrawable) foreground = null
            return
        }
        val mask = GradientDrawable()
        mask.setColor(Color.WHITE)
        if (oval) mask.shape = GradientDrawable.OVAL
        else Shapes.radii(radius, framePx.width().toFloat(), framePx.height().toFloat(), density)?.let { mask.cornerRadii = it }
        val wasPressed = isPressed
        foreground = RippleDrawable(ColorStateList.valueOf(color), null, mask)
        if (wasPressed) foreground?.state = drawableState
    }

    // ---------------------------------------------------------------------
    // Drawing
    // ---------------------------------------------------------------------

    internal fun shapePath(): Path {
        val w = width.toFloat()
        val h = height.toFloat()
        rectF.set(0f, 0f, w, h)
        return Shapes.path(rectF, if (oval) null else Shapes.radii(radius, w, h, density), oval, clipPath)
    }

    override fun draw(canvas: Canvas) {
        if (Backdrop.skip(this)) return
        backdropFilter?.let { Backdrop.paint(this, canvas, it) }
        val mask = shaderMask
        if (mask == null) {
            super.draw(canvas)
            return
        }
        val w = width.toFloat()
        val h = height.toFloat()
        val save = canvas.saveLayer(0f, 0f, w, h, null)
        super.draw(canvas)
        paint.reset()
        paint.isAntiAlias = true
        paint.shader = Paints.gradientShader(mask, w, h)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_ATOP)
        canvas.drawRect(0f, 0f, w, h, paint)
        canvas.restoreToCount(save)
    }

    override fun onDraw(canvas: Canvas) {
        decoration?.let { if (!it.isEmpty) it.draw(canvas, width.toFloat(), height.toFloat(), density) }
    }

    override fun dispatchDraw(canvas: Canvas) {
        if (!clip) {
            super.dispatchDraw(canvas)
            return
        }
        val save = canvas.save()
        canvas.clipPath(shapePath())
        super.dispatchDraw(canvas)
        canvas.restoreToCount(save)
    }

    // ---------------------------------------------------------------------
    // Input
    // ---------------------------------------------------------------------

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        if (pointerEventsNone) return false
        // A skew / perspective transform is hit-tested by the parent through its inverse.
        if (drawMatrix != null && !matrixRouted) return false
        val handled = super.dispatchTouchEvent(ev)
        val g = gestures
        val wants = g != null && g.onTouch(ev)
        return if (ev.actionMasked == MotionEvent.ACTION_DOWN) handled || wants || hitOpaque else true
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        if (pointerEventsNone) return false
        return super.dispatchGenericMotionEvent(event)
    }

    override fun onHoverEvent(event: MotionEvent): Boolean {
        val g = gestures ?: return super.onHoverEvent(event)
        return g.onHover(event) || super.onHoverEvent(event)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean = gestures?.onKey("keydown", event) == true || super.onKeyDown(keyCode, event)

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean = gestures?.onKey("keyup", event) == true || super.onKeyUp(keyCode, event)

    override fun onFocusChanged(gainFocus: Boolean, direction: Int, previouslyFocusedRect: Rect?) {
        super.onFocusChanged(gainFocus, direction, previouslyFocusedRect)
        gestures?.onFocus(gainFocus)
    }

    override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
        super.onInitializeAccessibilityNodeInfo(info)
        when (role) {
            "button", "link", "menuitem", "tab" -> info.className = "android.widget.Button"
            "image", "img" -> info.className = "android.widget.ImageView"
            "heading", "header" -> { info.className = "android.widget.TextView"; if (Build.VERSION.SDK_INT >= 28) info.isHeading = true }
            "checkbox" -> info.className = "android.widget.CheckBox"
            "switch" -> info.className = "android.widget.Switch"
            "slider" -> info.className = "android.widget.SeekBar"
            "textbox", "textfield" -> info.className = "android.widget.EditText"
            "list" -> info.className = "android.widget.ListView"
            null -> {}
            else -> {}
        }
        if (gestures?.has("tap") == true) info.isClickable = true
        if (gestures?.has("longpress") == true) info.isLongClickable = true
    }

    override fun performClick(): Boolean {
        super.performClick()
        gestures?.accessibilityTap()
        return true
    }
}

/**
 * CSS `backdrop-filter`: what is painted behind the view is snapshotted in
 * software at reduced resolution (everything drawn before the view in paint
 * order), filtered (blur, colour matrix) and painted clipped to the view.
 */
internal object Backdrop {
    private var capturing: ElpianView? = null
    private var reached = false

    /** During a capture: the capturing view and everything painted after it are skipped. */
    fun skip(v: ElpianView): Boolean {
        val c = capturing ?: return false
        if (v === c) reached = true
        return reached
    }

    fun paint(v: ElpianView, canvas: Canvas, f: Filter) {
        if (capturing != null) return
        val root = v.host.surface
        val w = v.width
        val h = v.height
        if (w <= 0 || h <= 0) return
        val d = v.density
        val sigma = ((f.blur ?: 0.0) * d).toFloat()
        val scale = if (sigma > 2f) max(0.125f, min(0.5f, 4f / sigma)) else 1f
        val bw = max(1, ceil(w * scale).toInt())
        val bh = max(1, ceil(h * scale).toInt())
        val bmp = try {
            Bitmap.createBitmap(bw, bh, Bitmap.Config.ARGB_8888)
        } catch (_: OutOfMemoryError) {
            return
        }
        val loc = IntArray(2)
        val rootLoc = IntArray(2)
        v.getLocationInWindow(loc)
        root.getLocationInWindow(rootLoc)
        val c = Canvas(bmp)
        c.scale(scale, scale)
        c.translate((rootLoc[0] - loc[0]).toFloat(), (rootLoc[1] - loc[1]).toFloat())
        capturing = v
        reached = false
        try {
            root.draw(c)
        } catch (_: Throwable) {
        } finally {
            capturing = null
            reached = false
        }
        if (sigma > 0) Blur.gaussian(bmp, sigma * scale)
        val p = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        Paints.colorMatrix(f)?.let { p.colorFilter = ColorMatrixColorFilter(it) }
        val save = canvas.save()
        canvas.clipPath(v.shapePath())
        canvas.drawBitmap(bmp, null, RectF(0f, 0f, w.toFloat(), h.toFloat()), p)
        canvas.restoreToCount(save)
        bmp.recycle()
    }
}
