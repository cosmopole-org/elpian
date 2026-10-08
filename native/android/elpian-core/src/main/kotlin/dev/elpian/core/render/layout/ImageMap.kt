package dev.elpian.core.render.layout

import dev.elpian.core.render.*
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/**
 * Image maps (`<img usemap="#m">` + `<map name="m"><area …></map>`,
 * render/layout/imagemap.ts): the image is the first child; every following
 * child is a tappable area whose coordinates are in the image's natural
 * pixels and are scaled to the rendered size.
 */
data class AreaSpec(
    /** rect, circle, poly or default. */
    val shape: String,
    val coords: List<Double>,
)

/** Bounds of a rectangle in natural image pixels. */
data class AreaRect(val x: Double, val y: Double, val width: Double, val height: Double)

/** JavaScript array indexing: a missing coordinate reads as NaN (`undefined` in arithmetic). */
private fun List<Double>.at(i: Int): Double = getOrNull(i) ?: Double.NaN

/** JavaScript `Math.min(...xs)` / `Math.max(...xs)`: NaN-propagating, ±Infinity when empty. */
private fun jsMin(xs: List<Double>): Double {
    var m = Double.POSITIVE_INFINITY
    for (x in xs) {
        if (x.isNaN()) return Double.NaN
        if (x < m) m = x
    }
    return m
}

private fun jsMax(xs: List<Double>): Double {
    var m = Double.NEGATIVE_INFINITY
    for (x in xs) {
        if (x.isNaN()) return Double.NaN
        if (x > m) m = x
    }
    return m
}

fun areaBounds(area: AreaSpec, w: Double, h: Double): AreaRect {
    val c = area.coords
    return when (area.shape) {
        "rect" -> AreaRect(min(c.at(0), c.at(2)), min(c.at(1), c.at(3)), abs(c.at(2) - c.at(0)), abs(c.at(3) - c.at(1)))
        "circle" -> AreaRect(c.at(0) - c.at(2), c.at(1) - c.at(2), c.at(2) * 2, c.at(2) * 2)
        "poly" -> {
            val xs = c.filterIndexed { i, _ -> i % 2 == 0 }
            val ys = c.filterIndexed { i, _ -> i % 2 == 1 }
            val x = jsMin(xs)
            val y = jsMin(ys)
            AreaRect(x, y, jsMax(xs) - x, jsMax(ys) - y)
        }
        else -> AreaRect(0.0, 0.0, w, h)
    }
}

/** Whether a point in natural image pixels lies inside [area]. */
fun areaContains(area: AreaSpec, px: Double, py: Double): Boolean {
    val c = area.coords
    return when (area.shape) {
        "rect" -> px >= min(c.at(0), c.at(2)) && px <= max(c.at(0), c.at(2)) && py >= min(c.at(1), c.at(3)) && py <= max(c.at(1), c.at(3))
        "circle" -> (px - c.at(0)) * (px - c.at(0)) + (py - c.at(1)) * (py - c.at(1)) <= c.at(2) * c.at(2)
        "poly" -> {
            var inside = false
            val n = floor(c.size / 2.0).toInt()
            var j = n - 1
            for (i in 0 until n) {
                val xi = c.at(2 * i)
                val yi = c.at(2 * i + 1)
                val xj = c.at(2 * j)
                val yj = c.at(2 * j + 1)
                if ((yi > py) != (yj > py) && px < ((xj - xi) * (py - yi)) / (yj - yi) + xi) inside = !inside
                j = i
            }
            inside
        }
        else -> true
    }
}

/** props: { src, areas: List<AreaSpec> } */
class RenderImageMap : RenderObject() {
    var scale = Vec(1.0, 1.0)

    override fun performLayout(c: Constraints) {
        val image = children.firstOrNull()
        if (image == null) {
            size = constrain(c, Size(0.0, 0.0))
            return
        }
        val areas = children.drop(1)
        image.layout(c)
        image.offset = Vec(0.0, 0.0)
        size = image.size.copy()
        val natural = props.s("src")?.let { owner?.imageSize(it) }
        scale = if (natural != null && natural.width > 0 && natural.height > 0) Vec(size.width / natural.width, size.height / natural.height) else Vec(1.0, 1.0)
        @Suppress("UNCHECKED_CAST")
        val specs = (props["areas"] as? List<Any?>) ?: emptyList()
        areas.forEachIndexed { i, area ->
            val spec = specs.getOrNull(i) as? AreaSpec
            if (spec == null) {
                area.layout(Constraints(0.0, 0.0, 0.0, 0.0))
                return@forEachIndexed
            }
            val b = areaBounds(spec, natural?.width ?: size.width, natural?.height ?: size.height)
            val w = b.width * scale.x
            val h = b.height * scale.y
            area.layout(Constraints(w, w, h, h))
            area.offset = Vec(b.x * scale.x, b.y * scale.y)
        }
    }
}
