package dev.elpian.core.css

/** Flutter painting value types (see css/types.ts in the TypeScript engine (native/web)). */

data class EdgeInsets(val top: Double = 0.0, val right: Double = 0.0, val bottom: Double = 0.0, val left: Double = 0.0) {
    val horizontal: Double get() = left + right
    val vertical: Double get() = top + bottom
    operator fun plus(o: EdgeInsets) = EdgeInsets(top + o.top, right + o.right, bottom + o.bottom, left + o.left)
    val isZero: Boolean get() = top == 0.0 && right == 0.0 && bottom == 0.0 && left == 0.0

    companion object {
        val ZERO = EdgeInsets()
        fun all(v: Double) = EdgeInsets(v, v, v, v)
        fun symmetric(vertical: Double = 0.0, horizontal: Double = 0.0) = EdgeInsets(vertical, horizontal, vertical, horizontal)
        fun lerp(a: EdgeInsets, b: EdgeInsets, t: Double): EdgeInsets {
            fun l(x: Double, y: Double) = x + (y - x) * t
            return EdgeInsets(l(a.top, b.top), l(a.right, b.right), l(a.bottom, b.bottom), l(a.left, b.left))
        }
    }
}

/** Flutter `Alignment`: x and y in -1..1, (0,0) is the centre. */
data class Alignment(val x: Double, val y: Double) {
    companion object {
        val topLeft = Alignment(-1.0, -1.0)
        val topCenter = Alignment(0.0, -1.0)
        val topRight = Alignment(1.0, -1.0)
        val centerLeft = Alignment(-1.0, 0.0)
        val center = Alignment(0.0, 0.0)
        val centerRight = Alignment(1.0, 0.0)
        val bottomLeft = Alignment(-1.0, 1.0)
        val bottomCenter = Alignment(0.0, 1.0)
        val bottomRight = Alignment(1.0, 1.0)
        fun lerp(a: Alignment, b: Alignment, t: Double) = Alignment(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
    }
}

data class Offset(val dx: Double, val dy: Double)

enum class BorderStyleName { solid, dashed, dotted, double, none }

data class BorderSide(val width: Double, val color: Color, val style: BorderStyleName = BorderStyleName.solid) {
    companion object {
        val NONE = BorderSide(0.0, Colors.black, BorderStyleName.none)
    }
}

data class Border(val top: BorderSide, val right: BorderSide, val bottom: BorderSide, val left: BorderSide) {
    val isUniform: Boolean get() = top == right && right == bottom && bottom == left

    /** The insets the border takes up (Container adds them to its padding). */
    val insets: EdgeInsets
        get() {
            fun w(s: BorderSide) = if (s.style == BorderStyleName.none) 0.0 else s.width
            return EdgeInsets(w(top), w(right), w(bottom), w(left))
        }

    companion object {
        fun all(side: BorderSide) = Border(side, side, side, side)
    }
}

fun borderInsets(b: Border?): EdgeInsets = b?.insets ?: EdgeInsets.ZERO

data class BorderRadius(val topLeft: Double, val topRight: Double, val bottomRight: Double, val bottomLeft: Double) {
    val isZero: Boolean get() = topLeft == 0.0 && topRight == 0.0 && bottomRight == 0.0 && bottomLeft == 0.0

    companion object {
        val ZERO = BorderRadius(0.0, 0.0, 0.0, 0.0)
        fun all(r: Double) = BorderRadius(r, r, r, r)
        fun lerp(a: BorderRadius, b: BorderRadius, t: Double): BorderRadius {
            fun l(x: Double, y: Double) = x + (y - x) * t
            return BorderRadius(l(a.topLeft, b.topLeft), l(a.topRight, b.topRight), l(a.bottomRight, b.bottomRight), l(a.bottomLeft, b.bottomLeft))
        }
    }
}

data class BoxShadow(val color: Color, val dx: Double, val dy: Double, val blur: Double, val spread: Double = 0.0, val inset: Boolean = false)

data class TextShadow(val color: Color, val dx: Double, val dy: Double, val blur: Double)

enum class GradientKind { linear, radial, sweep }

/**
 * Gradients in Flutter's vocabulary: linear from [begin] to [end] (alignments
 * within the box), radial on [center] with [radius] a fraction of the shortest
 * side, sweep around [center] from [startAngle] to [endAngle] radians.
 */
data class Gradient(
    val kind: GradientKind,
    val colors: List<Color>,
    val stops: List<Double>? = null,
    val begin: Alignment? = null,
    val end: Alignment? = null,
    val center: Alignment? = null,
    val radius: Double? = null,
    val startAngle: Double? = null,
    val endAngle: Double? = null,
    val repeat: Boolean = false,
) {
    /** Stops, evenly spread when absent or mismatched. */
    fun resolvedStops(): List<Double> {
        if (stops != null && stops.size == colors.size) return stops
        val n = colors.size
        return colors.indices.map { if (n > 1) it.toDouble() / (n - 1) else 0.0 }
    }
}

/** A 4x4 matrix in Flutter's column-major `Matrix4.storage` order. */
typealias Matrix4 = DoubleArray

enum class BoxFit { fill, contain, cover, fitWidth, fitHeight, none, scaleDown }

enum class TextOverflow { clip, ellipsis, fade, visible }

data class Filter(
    val blur: Double? = null,
    val brightness: Double? = null,
    val contrast: Double? = null,
    val grayscale: Double? = null,
    val hueRotate: Double? = null,
    val invert: Double? = null,
    val saturate: Double? = null,
    val sepia: Double? = null,
    val opacity: Double? = null,
    val dropShadow: TextShadow? = null,
) {
    val isEmpty: Boolean get() = this == Filter()
}

data class Keyframe(val offset: Double, val styles: Map<String, Any?>)

/** A percentage of the parent's size, kept symbolic until layout (CSS `%`). */
data class Percent(val pct: Double)

/** A CSS length: absolute px or a [Percent]. */
sealed interface Length {
    data class Px(val v: Double) : Length
    data class Pct(val pct: Double) : Length

    fun resolve(basis: Double): Double? = when (this) {
        is Px -> v
        is Pct -> if (basis.isFinite()) pct / 100 * basis else null
    }
}
