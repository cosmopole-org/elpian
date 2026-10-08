package dev.elpian.android.render

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.ViewConfiguration
import android.widget.EdgeEffect
import android.widget.OverScroller
import dev.elpian.core.render.ViewEvent
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * The `scroll` view kind: a native scroller over a content space of
 * `contentSize` (vertical, horizontal or both) whose children are positioned
 * relative to the content origin. Flings with the platform's physics, shows
 * the platform overscroll effect and scrollbars, and reports offsets back to
 * the core once per frame.
 */
@SuppressLint("ViewConstructor")
class ScrollContainer(context: Context, private val owner: ElpianView) : ElpianGroup(context, null, android.R.attr.scrollViewStyle) {
    var axis = "vertical"
        set(v) {
            field = v
            isVerticalScrollBarEnabled = showScrollbar && v != "horizontal"
            isHorizontalScrollBarEnabled = showScrollbar && v != "vertical"
        }
    var scrollEnabled = true
    var showScrollbar = true
        set(v) {
            field = v
            axis = axis
        }
    /** Content size in device px. */
    var contentWidth = 0
    var contentHeight = 0

    private val scroller = OverScroller(context)
    private val config = ViewConfiguration.get(context)
    private val touchSlop = config.scaledTouchSlop
    private val minFling = config.scaledMinimumFlingVelocity
    private val maxFling = config.scaledMaximumFlingVelocity
    private var tracker: VelocityTracker? = null
    private var dragging = false
    private var lastX = 0f
    private var lastY = 0f
    private var downX = 0f
    private var downY = 0f
    private var activePointer = -1
    private val edgeTop = EdgeEffect(context)
    private val edgeBottom = EdgeEffect(context)
    private val edgeLeft = EdgeEffect(context)
    private val edgeRight = EdgeEffect(context)
    private var reportPosted = false

    init {
        isFocusable = false
        overScrollMode = OVER_SCROLL_IF_CONTENT_SCROLLS
        isScrollbarFadingEnabled = true
        setWillNotDraw(false)
    }

    private val vertical get() = axis != "horizontal"
    private val horizontal get() = axis != "vertical"
    private val maxX get() = max(0, contentWidth - width)
    private val maxY get() = max(0, contentHeight - height)

    fun setContentSize(w: Int, h: Int) {
        contentWidth = w
        contentHeight = h
        val nx = min(scrollX, maxX)
        val ny = min(scrollY, maxY)
        if (nx != scrollX || ny != scrollY) super.scrollTo(nx, ny)
        awakenScrollBars()
    }

    override fun scrollTo(x: Int, y: Int) {
        val nx = if (horizontal) x.coerceIn(0, maxX) else 0
        val ny = if (vertical) y.coerceIn(0, maxY) else 0
        if (nx != scrollX || ny != scrollY) super.scrollTo(nx, ny)
    }

    /** Scroll to logical (x, y), animated when [smooth]. */
    fun scrollToLogical(x: Double, y: Double, smooth: Boolean) {
        val d = owner.density
        val tx = (x * d).roundToInt().coerceIn(0, maxX)
        val ty = (y * d).roundToInt().coerceIn(0, maxY)
        if (smooth) {
            scroller.forceFinished(true)
            scroller.startScroll(scrollX, scrollY, tx - scrollX, ty - scrollY, 300)
            postInvalidateOnAnimation()
        } else {
            scroller.forceFinished(true)
            scrollTo(tx, ty)
        }
    }

    override fun onScrollChanged(l: Int, t: Int, oldl: Int, oldt: Int) {
        super.onScrollChanged(l, t, oldl, oldt)
        if (reportPosted) return
        reportPosted = true
        postOnAnimation {
            reportPosted = false
            val d = owner.density
            owner.host.emit(ViewEvent(id = owner.viewId, type = "scroll", scrollX = scrollX / d.toDouble(), scrollY = scrollY / d.toDouble()))
        }
    }

    override fun computeScroll() {
        if (scroller.computeScrollOffset()) {
            val ox = scrollX
            val oy = scrollY
            scrollTo(scroller.currX, scroller.currY)
            if (overScrollMode != OVER_SCROLL_NEVER) {
                val v = scroller.currVelocity.toInt()
                if (vertical && scroller.currY < 0 && oy >= 0) edgeTop.onAbsorb(v)
                if (vertical && scroller.currY > maxY && oy <= maxY) edgeBottom.onAbsorb(v)
                if (horizontal && scroller.currX < 0 && ox >= 0) edgeLeft.onAbsorb(v)
                if (horizontal && scroller.currX > maxX && ox <= maxX) edgeRight.onAbsorb(v)
            }
            postInvalidateOnAnimation()
        }
    }

    override fun computeVerticalScrollRange(): Int = max(contentHeight, height)
    override fun computeVerticalScrollExtent(): Int = height
    override fun computeVerticalScrollOffset(): Int = scrollY
    override fun computeHorizontalScrollRange(): Int = max(contentWidth, width)
    override fun computeHorizontalScrollExtent(): Int = width
    override fun computeHorizontalScrollOffset(): Int = scrollX

    override fun canScrollVertically(direction: Int): Boolean = scrollEnabled && vertical && if (direction < 0) scrollY > 0 else scrollY < maxY
    override fun canScrollHorizontally(direction: Int): Boolean = scrollEnabled && horizontal && if (direction < 0) scrollX > 0 else scrollX < maxX

    private fun canScrollAny(): Boolean = scrollEnabled && ((vertical && maxY > 0) || (horizontal && maxX > 0))

    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
        if (!scrollEnabled) return false
        when (ev.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                activePointer = ev.getPointerId(0)
                downX = ev.x; downY = ev.y
                lastX = ev.x; lastY = ev.y
                // Catch a running fling: the touch stops it and owns the gesture.
                dragging = !scroller.isFinished
                if (dragging) {
                    scroller.forceFinished(true)
                    parent?.requestDisallowInterceptTouchEvent(true)
                }
                tracker = VelocityTracker.obtain().also { it.addMovement(ev) }
            }
            MotionEvent.ACTION_MOVE -> {
                val i = ev.findPointerIndex(activePointer)
                if (i < 0) return false
                val dx = abs(ev.getX(i) - downX)
                val dy = abs(ev.getY(i) - downY)
                tracker?.addMovement(ev)
                if (!dragging && canScrollAny() && ((vertical && dy > touchSlop && dy >= dx * (if (horizontal) 0f else 0.5f)) || (horizontal && dx > touchSlop && dx >= dy * (if (vertical) 0f else 0.5f)))) {
                    dragging = true
                    lastX = ev.getX(i); lastY = ev.getY(i)
                    parent?.requestDisallowInterceptTouchEvent(true)
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                dragging = false
                recycle()
            }
        }
        return dragging
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(ev: MotionEvent): Boolean {
        if (!scrollEnabled) return false
        if (tracker == null) tracker = VelocityTracker.obtain()
        tracker?.addMovement(ev)
        when (ev.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                scroller.forceFinished(true)
                activePointer = ev.getPointerId(0)
                downX = ev.x; downY = ev.y
                lastX = ev.x; lastY = ev.y
                return canScrollAny()
            }
            MotionEvent.ACTION_POINTER_DOWN -> {
                val i = ev.actionIndex
                activePointer = ev.getPointerId(i)
                lastX = ev.getX(i); lastY = ev.getY(i)
            }
            MotionEvent.ACTION_POINTER_UP -> {
                if (ev.getPointerId(ev.actionIndex) == activePointer) {
                    val ni = if (ev.actionIndex == 0) 1 else 0
                    activePointer = ev.getPointerId(ni)
                    lastX = ev.getX(ni); lastY = ev.getY(ni)
                }
            }
            MotionEvent.ACTION_MOVE -> {
                val i = ev.findPointerIndex(activePointer)
                if (i < 0) return true
                val x = ev.getX(i)
                val y = ev.getY(i)
                if (!dragging && (abs(x - downX) > touchSlop || abs(y - downY) > touchSlop)) {
                    dragging = true
                    parent?.requestDisallowInterceptTouchEvent(true)
                }
                if (dragging) {
                    val dx = if (horizontal) (lastX - x).roundToInt() else 0
                    val dy = if (vertical) (lastY - y).roundToInt() else 0
                    val nx = scrollX + dx
                    val ny = scrollY + dy
                    if (overScrollMode != OVER_SCROLL_NEVER) {
                        if (vertical && ny < 0) edgeTop.onPull(-ny.toFloat() / max(1, height), x / max(1, width))
                        if (vertical && ny > maxY) edgeBottom.onPull((ny - maxY).toFloat() / max(1, height), 1f - x / max(1, width))
                        if (horizontal && nx < 0) edgeLeft.onPull(-nx.toFloat() / max(1, width), 1f - y / max(1, height))
                        if (horizontal && nx > maxX) edgeRight.onPull((nx - maxX).toFloat() / max(1, width), y / max(1, height))
                        if (!edgeTop.isFinished || !edgeBottom.isFinished || !edgeLeft.isFinished || !edgeRight.isFinished) postInvalidateOnAnimation()
                    }
                    scrollTo(nx, ny)
                    awakenScrollBars()
                    lastX = x
                    lastY = y
                }
            }
            MotionEvent.ACTION_UP -> {
                if (dragging) {
                    val t = tracker
                    t?.computeCurrentVelocity(1000, maxFling.toFloat())
                    val vx = if (horizontal) -(t?.getXVelocity(activePointer) ?: 0f).toInt() else 0
                    val vy = if (vertical) -(t?.getYVelocity(activePointer) ?: 0f).toInt() else 0
                    if (abs(vx) > minFling || abs(vy) > minFling) {
                        scroller.fling(scrollX, scrollY, vx, vy, 0, maxX, 0, maxY, if (horizontal) width / 8 else 0, if (vertical) height / 8 else 0)
                        postInvalidateOnAnimation()
                    }
                }
                dragging = false
                releaseEdges()
                recycle()
            }
            MotionEvent.ACTION_CANCEL -> {
                dragging = false
                releaseEdges()
                recycle()
            }
        }
        return true
    }

    private fun releaseEdges() {
        edgeTop.onRelease(); edgeBottom.onRelease(); edgeLeft.onRelease(); edgeRight.onRelease()
        postInvalidateOnAnimation()
    }

    private fun recycle() {
        tracker?.recycle()
        tracker = null
    }

    override fun dispatchDraw(canvas: Canvas) {
        val save = canvas.save()
        canvas.clipRect(scrollX, scrollY, scrollX + width, scrollY + height)
        super.dispatchDraw(canvas)
        canvas.restoreToCount(save)
    }

    override fun draw(canvas: Canvas) {
        super.draw(canvas)
        var more = false
        fun edge(e: EdgeEffect, rotate: Float, tx: Float, ty: Float, w: Int, h: Int) {
            if (e.isFinished) return
            val s = canvas.save()
            canvas.translate(tx, ty)
            canvas.rotate(rotate)
            e.setSize(w, h)
            if (e.draw(canvas)) more = true
            canvas.restoreToCount(s)
        }
        edge(edgeTop, 0f, scrollX.toFloat(), scrollY.toFloat(), width, height)
        edge(edgeBottom, 180f, (scrollX + width).toFloat(), (scrollY + height).toFloat(), width, height)
        edge(edgeLeft, 270f, scrollX.toFloat(), (scrollY + height).toFloat(), height, width)
        edge(edgeRight, 90f, (scrollX + width).toFloat(), scrollY.toFloat(), height, width)
        if (more) postInvalidateOnAnimation()
    }
}
