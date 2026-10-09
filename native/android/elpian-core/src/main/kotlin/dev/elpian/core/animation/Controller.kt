package dev.elpian.core.animation

import dev.elpian.core.render.RenderOwner
import dev.elpian.core.render.Ticker
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

enum class AnimationStatus { dismissed, forward, reverse, completed }

/** A run's completion (the TypeScript engine (native/web)'s Promise). */
class Completion {
    private var done = false
    private val callbacks = ArrayList<() -> Unit>()
    fun then(fn: () -> Unit): Completion {
        if (done) fn() else callbacks.add(fn)
        return this
    }
    internal fun complete() {
        if (done) return
        done = true
        val cbs = callbacks.toList()
        callbacks.clear()
        cbs.forEach { it() }
    }
}

/** Flutter `AnimationController`: a 0..1 value driven over [duration] ms on the owner's frame clock. */
class AnimationController(var duration: Double, initial: Double = 0.0, var reverseDuration: Double? = null) : Ticker {
    var value: Double = initial
    var status = AnimationStatus.dismissed
        private set
    private var owner: RenderOwner? = null
    private var from = 0.0
    private var to = 1.0
    private var startTime: Double? = null
    private var running = false
    private var repeat = false
    private var reverseOnRepeat = false
    private var completer: Completion? = null
    private val listeners = LinkedHashSet<() -> Unit>()
    private val statusListeners = LinkedHashSet<(AnimationStatus) -> Unit>()

    fun attach(owner: RenderOwner) {
        this.owner = owner
        if (running) owner.addTicker(this)
    }

    fun detach() {
        owner?.removeTicker(this)
        owner = null
    }

    fun addListener(fn: () -> Unit) { listeners.add(fn) }
    fun removeListener(fn: () -> Unit) { listeners.remove(fn) }
    fun addStatusListener(fn: (AnimationStatus) -> Unit) { statusListeners.add(fn) }

    private fun setStatus(s: AnimationStatus) {
        if (status == s) return
        status = s
        statusListeners.toList().forEach { it(s) }
    }

    val isAnimating: Boolean get() = running

    private fun start(target: Double): Completion {
        from = value
        to = target
        startTime = null
        running = true
        setStatus(if (target >= from) AnimationStatus.forward else AnimationStatus.reverse)
        owner?.addTicker(this)
        completer?.complete()
        return Completion().also { completer = it }
    }

    fun forward(from: Double? = null): Completion {
        repeat = false
        if (from != null) value = from
        return start(1.0)
    }

    fun reverse(from: Double? = null): Completion {
        repeat = false
        if (from != null) value = from
        return start(0.0)
    }

    fun animateTo(target: Double): Completion {
        repeat = false
        return start(target)
    }

    /** Loop 0→1 forever (ping-pong when [reverse]). */
    fun repeatAnimation(reverse: Boolean = false) {
        repeat = true
        reverseOnRepeat = reverse
        from = if (value >= 1) 0.0 else value
        to = 1.0
        startTime = null
        running = true
        setStatus(AnimationStatus.forward)
        owner?.addTicker(this)
    }

    fun stop() {
        running = false
        repeat = false
        owner?.removeTicker(this)
        completer?.complete()
        completer = null
    }

    fun reset(value: Double = 0.0) {
        stop()
        this.value = value
        setStatus(AnimationStatus.dismissed)
        notifyListeners()
    }

    private fun notifyListeners() {
        listeners.toList().forEach { it() }
    }

    override fun tick(nowMs: Double): Boolean {
        if (!running) return false
        val st = startTime ?: nowMs.also { startTime = it }
        val goingBack = to < from
        val d = max(1.0, if (goingBack && reverseDuration != null) reverseDuration!! else duration)
        val total = d * abs(to - from)
        val elapsed = nowMs - st
        val t = if (total <= 0) 1.0 else min(1.0, elapsed / total)
        value = from + (to - from) * t
        notifyListeners()
        if (t < 1) return true
        if (repeat) {
            if (reverseOnRepeat) {
                val next = if (to >= 1) 0.0 else 1.0
                from = value
                to = next
                setStatus(if (next == 1.0) AnimationStatus.forward else AnimationStatus.reverse)
            } else {
                from = 0.0
                to = 1.0
                value = 0.0
            }
            startTime = nowMs
            return true
        }
        running = false
        setStatus(if (to >= 1) AnimationStatus.completed else AnimationStatus.dismissed)
        completer?.complete()
        completer = null
        return false
    }
}

typealias Lerp<T> = (T, T, Double) -> T

val lerpNumber: Lerp<Double> = { a, b, t -> a + (b - a) * t }

/**
 * An implicitly animated value (Flutter's `AnimatedFoo` engine): a new target
 * animates from the current value over the duration and curve; without a
 * duration it jumps.
 */
class ImplicitValue<T>(
    private var value: T,
    private val lerp: Lerp<T>,
    private val equals: (T, T) -> Boolean,
    private val onChange: () -> Unit,
) {
    private var controller: AnimationController? = null
    private var begin: T = value
    private var end: T = value
    private var curve: Curve = Curves.linear

    val current: T get() = value
    val target: T get() = end
    val animating: Boolean get() = controller?.isAnimating ?: false

    fun set(target: T, duration: Double?, curve: Curve?, owner: RenderOwner?) {
        if (equals(target, end)) return
        if (duration == null || duration <= 0 || owner == null) {
            controller?.stop()
            begin = target
            end = target
            value = target
            onChange()
            return
        }
        begin = value
        end = target
        this.curve = curve ?: Curves.linear
        val c = controller ?: AnimationController(duration).also { c ->
            controller = c
            c.addListener {
                value = lerp(begin, end, this.curve(c.value))
                onChange()
            }
        }
        c.duration = duration
        c.attach(owner)
        c.forward(0.0)
    }

    fun jump(v: T) {
        controller?.stop()
        begin = v
        end = v
        value = v
    }

    fun dispose() {
        controller?.detach()
        controller?.stop()
    }
}
