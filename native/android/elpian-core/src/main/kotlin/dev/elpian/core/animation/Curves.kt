package dev.elpian.core.animation

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/**
 * Easing curves — an exact port of Flutter's `Curves` (cubic bisection with
 * the 0.001 error bound, Penner's bounce, Flutter's elastic curves) plus CSS
 * `cubic-bezier()` and `steps()`.
 */
typealias Curve = (Double) -> Double

private const val CUBIC_ERROR_BOUND = 0.001

private fun evaluateCubic(a: Double, b: Double, m: Double) = 3 * a * (1 - m) * (1 - m) * m + 3 * b * (1 - m) * m * m + m * m * m

fun cubic(a: Double, b: Double, c: Double, d: Double): Curve = { t ->
    if (t <= 0) 0.0 else if (t >= 1) 1.0 else {
        var start = 0.0
        var end = 1.0
        var result: Double? = null
        for (i in 0 until 64) {
            val mid = (start + end) / 2
            val estimate = evaluateCubic(a, c, mid)
            if (abs(t - estimate) < CUBIC_ERROR_BOUND) {
                result = evaluateCubic(b, d, mid)
                break
            }
            if (estimate < t) start = mid else end = mid
        }
        result ?: evaluateCubic(b, d, (start + end) / 2)
    }
}

private fun bounce(t0: Double): Double {
    var t = t0
    if (t < 1 / 2.75) return 7.5625 * t * t
    if (t < 2 / 2.75) {
        t -= 1.5 / 2.75
        return 7.5625 * t * t + 0.75
    }
    if (t < 2.5 / 2.75) {
        t -= 2.25 / 2.75
        return 7.5625 * t * t + 0.9375
    }
    t -= 2.625 / 2.75
    return 7.5625 * t * t + 0.984375
}

fun elasticIn(period: Double = 0.4): Curve = { t0 ->
    if (t0 <= 0 || t0 >= 1) (if (t0 <= 0) 0.0 else 1.0) else {
        val s = period / 4
        val t = t0 - 1
        -2.0.pow(10 * t) * sin((t - s) * (PI * 2) / period)
    }
}

fun elasticOut(period: Double = 0.4): Curve = { t ->
    if (t <= 0 || t >= 1) (if (t <= 0) 0.0 else 1.0) else {
        val s = period / 4
        2.0.pow(-10 * t) * sin((t - s) * (PI * 2) / period) + 1
    }
}

fun elasticInOut(period: Double = 0.4): Curve = { t0 ->
    if (t0 <= 0 || t0 >= 1) (if (t0 <= 0) 0.0 else 1.0) else {
        val s = period / 4
        val t = 2 * t0 - 1
        if (t < 0) -0.5 * 2.0.pow(10 * t) * sin((t - s) * (PI * 2) / period)
        else 2.0.pow(-10 * t) * sin((t - s) * (PI * 2) / period) * 0.5 + 1
    }
}

fun interval(begin: Double, end: Double, curve: Curve = Curves.linear): Curve = { t ->
    if (end <= begin) (if (t >= end) 1.0 else 0.0) else {
        val local = ((t - begin) / (end - begin)).coerceIn(0.0, 1.0)
        if (local == 0.0 || local == 1.0) local else curve(local)
    }
}

fun steps(count: Int, position: String = "end"): Curve {
    val n = max(1, count)
    return { t ->
        if (t >= 1) 1.0 else {
            var step = floor(t * n)
            if (position == "start" || position == "both") step += 1
            val jumps = if (position == "both") n + 1 else if (position == "none") n - 1 else n
            (step / max(1, jumps)).coerceIn(0.0, 1.0)
        }
    }
}

object Curves {
    val linear: Curve = { t -> t }
    val decelerate: Curve = { t0 -> val t = 1 - t0; 1 - t * t }
    val fastLinearToSlowEaseIn: Curve = cubic(0.18, 1.0, 0.04, 1.0)
    val ease: Curve = cubic(0.25, 0.1, 0.25, 1.0)
    val easeIn: Curve = cubic(0.42, 0.0, 1.0, 1.0)
    val easeInToLinear: Curve = cubic(0.67, 0.03, 0.65, 0.09)
    val easeInSine: Curve = cubic(0.47, 0.0, 0.745, 0.715)
    val easeInQuad: Curve = cubic(0.55, 0.085, 0.68, 0.53)
    val easeInCubic: Curve = cubic(0.55, 0.055, 0.675, 0.19)
    val easeInQuart: Curve = cubic(0.895, 0.03, 0.685, 0.22)
    val easeInQuint: Curve = cubic(0.755, 0.05, 0.855, 0.06)
    val easeInExpo: Curve = cubic(0.95, 0.05, 0.795, 0.035)
    val easeInCirc: Curve = cubic(0.6, 0.04, 0.98, 0.335)
    val easeInBack: Curve = cubic(0.6, -0.28, 0.735, 0.045)
    val easeOut: Curve = cubic(0.0, 0.0, 0.58, 1.0)
    val linearToEaseOut: Curve = cubic(0.35, 0.91, 0.33, 0.97)
    val easeOutSine: Curve = cubic(0.39, 0.575, 0.565, 1.0)
    val easeOutQuad: Curve = cubic(0.25, 0.46, 0.45, 0.94)
    val easeOutCubic: Curve = cubic(0.215, 0.61, 0.355, 1.0)
    val easeOutQuart: Curve = cubic(0.165, 0.84, 0.44, 1.0)
    val easeOutQuint: Curve = cubic(0.23, 1.0, 0.32, 1.0)
    val easeOutExpo: Curve = cubic(0.19, 1.0, 0.22, 1.0)
    val easeOutCirc: Curve = cubic(0.075, 0.82, 0.165, 1.0)
    val easeOutBack: Curve = cubic(0.175, 0.885, 0.32, 1.275)
    val easeInOut: Curve = cubic(0.42, 0.0, 0.58, 1.0)
    val easeInOutSine: Curve = cubic(0.445, 0.05, 0.55, 0.95)
    val easeInOutQuad: Curve = cubic(0.455, 0.03, 0.515, 0.955)
    val easeInOutCubic: Curve = cubic(0.645, 0.045, 0.355, 1.0)
    val easeInOutQuart: Curve = cubic(0.77, 0.0, 0.175, 1.0)
    val easeInOutQuint: Curve = cubic(0.86, 0.0, 0.07, 1.0)
    val easeInOutExpo: Curve = cubic(1.0, 0.0, 0.0, 1.0)
    val easeInOutCirc: Curve = cubic(0.785, 0.135, 0.15, 0.86)
    val easeInOutBack: Curve = cubic(0.68, -0.55, 0.265, 1.55)
    val fastOutSlowIn: Curve = cubic(0.4, 0.0, 0.2, 1.0)
    val slowMiddle: Curve = cubic(0.15, 0.85, 0.85, 0.15)
    val bounceIn: Curve = { t -> 1 - bounce(1 - t) }
    val bounceOut: Curve = { t -> bounce(t) }
    val bounceInOut: Curve = { t -> if (t < 0.5) (1 - bounce(1 - t * 2)) * 0.5 else bounce(t * 2 - 1) * 0.5 + 0.5 }
    val elasticIn: Curve = dev.elpian.core.animation.elasticIn(0.4)
    val elasticOut: Curve = dev.elpian.core.animation.elasticOut(0.4)
    val elasticInOut: Curve = dev.elpian.core.animation.elasticInOut(0.4)

    private val byName: Map<String, Curve> by lazy {
        mapOf(
            "linear" to linear,
            "ease" to ease,
            "easein" to easeIn,
            "easeout" to easeOut,
            "easeinout" to easeInOut,
            "bounce" to bounceIn,
            "bouncein" to bounceIn,
            "bounceout" to bounceOut,
            "bounceinout" to bounceInOut,
            "elastic" to elasticIn,
            "elasticin" to elasticIn,
            "elasticout" to elasticOut,
            "elasticinout" to elasticInOut,
            "decelerate" to decelerate,
            "fastoutslowin" to fastOutSlowIn,
            "slowmiddle" to slowMiddle,
            "fastlineartosloweasein" to fastLinearToSlowEaseIn,
            "easeintolinear" to easeInToLinear,
            "lineartoeaseout" to linearToEaseOut,
            "easeinsine" to easeInSine,
            "easeinquad" to easeInQuad,
            "easeincubic" to easeInCubic,
            "easeinquart" to easeInQuart,
            "easeinquint" to easeInQuint,
            "easeinexpo" to easeInExpo,
            "easeincirc" to easeInCirc,
            "easeinback" to easeInBack,
            "easeoutsine" to easeOutSine,
            "easeoutquad" to easeOutQuad,
            "easeoutcubic" to easeOutCubic,
            "easeoutquart" to easeOutQuart,
            "easeoutquint" to easeOutQuint,
            "easeoutexpo" to easeOutExpo,
            "easeoutcirc" to easeOutCirc,
            "easeoutback" to easeOutBack,
            "easeinoutsine" to easeInOutSine,
            "easeinoutquad" to easeInOutQuad,
            "easeinoutcubic" to easeInOutCubic,
            "easeinoutquart" to easeInOutQuart,
            "easeinoutquint" to easeInOutQuint,
            "easeinoutexpo" to easeInOutExpo,
            "easeinoutcirc" to easeInOutCirc,
            "easeinoutback" to easeInOutBack,
            "stepstart" to steps(1, "start"),
            "stepend" to steps(1, "end"),
        )
    }

    private val BEZIER = Regex("^cubic-bezier\\(\\s*([-\\d.]+)\\s*,\\s*([-\\d.]+)\\s*,\\s*([-\\d.]+)\\s*,\\s*([-\\d.]+)\\s*\\)$")
    private val STEPS = Regex("^steps\\(\\s*(\\d+)\\s*(?:,\\s*([a-z-]+))?\\s*\\)$")

    /** Resolve a curve name (`ease-in-out`, `easeInOut`, `cubic-bezier(…)`, `steps(4, end)`). */
    fun byName(name: String?, fallback: Curve = linear): Curve {
        if (name.isNullOrBlank()) return fallback
        val raw = name.trim().lowercase()
        BEZIER.find(raw)?.let { m -> return cubic(m.groupValues[1].toDouble(), m.groupValues[2].toDouble(), m.groupValues[3].toDouble(), m.groupValues[4].toDouble()) }
        STEPS.find(raw)?.let { m ->
            val pos = m.groupValues[2].ifEmpty { "end" }
            val position = when (pos) {
                "start", "jump-start" -> "start"
                "jump-both" -> "both"
                "jump-none" -> "none"
                else -> "end"
            }
            return steps(m.groupValues[1].toInt(), position)
        }
        return byName[raw.replace(Regex("[-_\\s]"), "")] ?: fallback
    }
}
