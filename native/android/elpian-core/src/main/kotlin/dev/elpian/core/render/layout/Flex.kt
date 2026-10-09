package dev.elpian.core.render.layout

import dev.elpian.core.render.*
import kotlin.math.abs
import kotlin.math.max

/**
 * RenderFlex (Row / Column) and Flexible / Expanded parent data — a port of
 * Flutter's flex algorithm (render/layout/flex.ts):
 *
 *   1. lay out inflexible children with an unbounded main axis;
 *   2. divide the remaining space between flexible children by flex factor
 *      (tight fit for Expanded / CSS `flex:n`, loose for Flexible);
 *   3. size the box (`mainAxisSize` max/min), then distribute leftover space
 *      with `mainAxisAlignment` and place children on the cross axis.
 *
 * One deliberate extension: when inflexible children overflow a bounded main
 * axis, a box declared with `shrink: true` (HTML/CSS flex containers) shrinks
 * them proportionally to their `flex-shrink` — what a browser does — instead
 * of letting content spill past the edge the way Flutter's debug overflow
 * stripe shows. Flutter-DSL Row/Column keep Flutter's no-shrink semantics.
 *
 * Main-axis alignments: start, end, center, spaceBetween, spaceAround, spaceEvenly.
 * Cross-axis alignments: start, end, center, stretch, baseline.
 */

/** Parent data for a flex child: props { flex, fit: 'tight'|'loose', shrink, alignSelf, basis } */
class RenderFlexible : RenderObject() {
    override fun performLayout(c: Constraints) {
        val ch = child
        if (ch != null) {
            ch.layout(c)
            ch.offset = Vec(0.0, 0.0)
            size = ch.size.copy()
        } else size = constrain(c, Size(0.0, 0.0))
    }
}

private class FlexInfo(
    val flex: Double,
    /** `tight` or `loose`. */
    val fit: String,
    val shrink: Double,
    val alignSelf: String?,
    /** CSS flex-basis in px (when it differs from the content size). */
    val basis: Double?,
)

private fun flexInfo(child: RenderObject): FlexInfo {
    if (child is RenderFlexible) {
        val p = child.props
        val flex = p.d("flex")
        return FlexInfo(
            if (flex != null && flex > 0) flex else 0.0,
            if (p["fit"] == "loose") "loose" else "tight",
            p.d("shrink") ?: 1.0,
            p.s("alignSelf"),
            p.d("basis"),
        )
    }
    return FlexInfo(0.0, "tight", 1.0, null, null)
}

fun mainAxisAlignmentFromCss(value: String?): String = when ((value ?: "").lowercase()) {
    "center" -> "center"
    "flex-end", "end", "right" -> "end"
    "space-between" -> "spaceBetween"
    "space-around" -> "spaceAround"
    "space-evenly" -> "spaceEvenly"
    else -> "start"
}

fun crossAxisAlignmentFromCss(value: String?): String = when ((value ?: "").lowercase()) {
    "center" -> "center"
    "flex-end", "end" -> "end"
    "stretch" -> "stretch"
    "baseline", "first baseline" -> "baseline"
    else -> "start"
}

/**
 * props: {
 *   direction: 'row' | 'column', reverse?: boolean,
 *   mainAxisAlignment, crossAxisAlignment, mainAxisSize: 'max' | 'min',
 *   verticalDirection?: 'down' | 'up', gap?: number, shrink?: boolean
 * }
 */
class RenderFlex : RenderObject() {
    private var overflow = 0.0

    private val horizontal: Boolean get() = props["direction"] != "column"

    private fun main(s: Size): Double = if (horizontal) s.width else s.height
    private fun cross(s: Size): Double = if (horizontal) s.height else s.width

    /** Constraints for a child with the given main extent bounds. */
    private fun childConstraints(minMain: Double, maxMain: Double, c: Constraints, align: String): Constraints {
        val stretch = align == "stretch"
        if (horizontal) {
            val maxCross = c.maxHeight
            return Constraints(minMain, maxMain, if (stretch && maxCross.isFinite()) maxCross else 0.0, maxCross)
        }
        val maxCross = c.maxWidth
        return Constraints(if (stretch && maxCross.isFinite()) maxCross else 0.0, maxCross, minMain, maxMain)
    }

    override fun performLayout(c: Constraints) {
        val horizontal = this.horizontal
        val gap = props.d("gap") ?: 0.0
        val crossAlign = props.s("crossAxisAlignment") ?: "start"
        val maxMain = if (horizontal) c.maxWidth else c.maxHeight
        val canFlex = maxMain.isFinite()
        val children = this.children
        val infos = children.map(::flexInfo)
        val gaps = max(0, children.size - 1) * gap

        var totalFlex = 0.0
        var allocated = 0.0
        val isFlex = infos.map { canFlex && it.flex > 0 }
        for (i in children.indices) {
            val ch = children[i]
            val info = infos[i]
            if (isFlex[i]) {
                totalFlex += info.flex
                continue
            }
            val align = info.alignSelf ?: crossAlign
            if (info.basis != null) ch.layout(childConstraints(info.basis, info.basis, c, align))
            else ch.layout(childConstraints(0.0, INF, c, align))
            allocated += main(ch.size)
        }

        // CSS shrink: inflexible content overflowing a bounded main axis.
        if (props.b("shrink") && canFlex && allocated + gaps > maxMain + 0.01) {
            shrinkChildren(c, infos, isFlex, maxMain - gaps)
            allocated = 0.0
            for (i in children.indices) if (!isFlex[i]) allocated += main(children[i].size)
        }

        val freeSpace = max(0.0, (if (canFlex) maxMain else 0.0) - allocated - gaps)
        if (totalFlex > 0) {
            val perFlex = freeSpace / totalFlex
            var lastFlexIndex = -1
            for (i in children.indices) if (isFlex[i]) lastFlexIndex = i
            var used = 0.0
            for (i in children.indices) {
                if (!isFlex[i]) continue
                val info = infos[i]
                val maxChild = if (i == lastFlexIndex) max(0.0, freeSpace - used) else perFlex * info.flex
                val minChild = if (info.fit == "tight") maxChild else 0.0
                val align = info.alignSelf ?: crossAlign
                children[i].layout(childConstraints(minChild, maxChild, c, align))
                val extent = main(children[i].size)
                used += extent
                allocated += extent
            }
        }

        val mainSizeMax = (props.s("mainAxisSize") ?: "max") == "max"
        val allocatedWithGaps = allocated + gaps
        val idealMain = if (mainSizeMax && canFlex) maxMain else allocatedWithGaps

        var crossSize = 0.0
        var maxBaseline = 0.0
        var maxBelowBaseline = 0.0
        val baselines = ArrayList<Double?>()
        for (i in children.indices) {
            val ch = children[i]
            val align = infos[i].alignSelf ?: crossAlign
            if (align == "baseline" && horizontal) {
                val b = ch.baseline() ?: ch.size.height
                baselines.add(b)
                maxBaseline = max(maxBaseline, b)
                maxBelowBaseline = max(maxBelowBaseline, ch.size.height - b)
            } else {
                baselines.add(null)
                crossSize = max(crossSize, cross(ch.size))
            }
        }
        crossSize = max(crossSize, maxBaseline + maxBelowBaseline)
        if (crossAlign == "stretch") {
            val maxCross = if (horizontal) c.maxHeight else c.maxWidth
            if (maxCross.isFinite()) crossSize = max(crossSize, maxCross)
        }

        val size = constrain(c, if (horizontal) Size(idealMain, crossSize) else Size(crossSize, idealMain))
        this.size = size
        val actualMain = main(size)
        val actualCross = cross(size)
        overflow = max(0.0, allocatedWithGaps - actualMain)

        val remaining = max(0.0, actualMain - allocatedWithGaps)
        val n = children.size
        var leading = 0.0
        var between = 0.0
        when (props.s("mainAxisAlignment") ?: "start") {
            "end" -> leading = remaining
            "center" -> leading = remaining / 2
            "spaceBetween" -> between = if (n > 1) remaining / (n - 1) else 0.0
            "spaceAround" -> {
                between = if (n > 0) remaining / n else 0.0
                leading = between / 2
            }
            "spaceEvenly" -> {
                between = if (n > 0) remaining / (n + 1) else 0.0
                leading = between
            }
        }

        // Reverse order for row-reverse / column-reverse / verticalDirection up
        // (the cross position needs nothing extra: the order is flipped here).
        val flip = props["reverse"] == true || (!horizontal && props["verticalDirection"] == "up")
        var pos = leading
        for (k in 0 until n) {
            val i = if (flip) n - 1 - k else k
            val ch = children[i]
            val align = infos[i].alignSelf ?: crossAlign
            val childCross = cross(ch.size)
            val crossPos = when (align) {
                "end" -> actualCross - childCross
                "center" -> (actualCross - childCross) / 2
                "baseline" -> if (horizontal) maxBaseline - (baselines[i] ?: 0.0) else 0.0
                else -> 0.0
            }
            ch.offset = if (horizontal) Vec(pos, crossPos) else Vec(crossPos, pos)
            pos += main(ch.size) + gap + between
        }
    }

    /** CSS flex-shrink: reduce inflexible children so they fit [available]. */
    private fun shrinkChildren(c: Constraints, infos: List<FlexInfo>, isFlex: List<Boolean>, available: Double) {
        val crossAlign = props.s("crossAxisAlignment") ?: "start"
        val children = this.children
        val base = children.map { main(it.size) }
        val minContent = children.mapIndexed { i, ch ->
            if (isFlex[i]) 0.0 else if (horizontal) ch.minIntrinsicWidth(INF) else ch.minIntrinsicHeight(c.maxWidth)
        }
        val frozen = BooleanArray(children.size) { i -> isFlex[i] || infos[i].shrink <= 0 }
        val target = base.toDoubleArray()
        // Iteratively shrink, freezing items that hit their min-content size.
        for (iter in 0 until 8) {
            var used = 0.0
            var weighted = 0.0
            for (i in children.indices) {
                if (isFlex[i]) continue
                used += target[i]
                if (!frozen[i]) weighted += infos[i].shrink * base[i]
            }
            val over = used - available
            if (over <= 0.01 || weighted <= 0) break
            var clamped = false
            for (i in children.indices) {
                if (frozen[i]) continue
                val share = (over * infos[i].shrink * base[i]) / weighted
                val next = target[i] - share
                if (next < minContent[i]) {
                    target[i] = minContent[i]
                    frozen[i] = true
                    clamped = true
                } else target[i] = next
            }
            if (!clamped) break
        }
        for (i in children.indices) {
            if (isFlex[i] || abs(target[i] - base[i]) < 0.01) continue
            val align = infos[i].alignSelf ?: crossAlign
            val extent = max(0.0, target[i])
            children[i].layout(childConstraints(extent, extent, c, align))
        }
    }

    val overflowExtent: Double get() = overflow

    override fun baseline(): Double? {
        // Flutter: a Row's baseline is that of its first child that has one.
        for (ch in children) {
            val b = ch.baseline()
            if (b != null) return b + ch.offset.y
        }
        return null
    }

    override fun computeMinIntrinsicWidth(height: Double) = intrinsicMain(true, true, height)
    override fun computeMaxIntrinsicWidth(height: Double) = intrinsicMain(false, true, height)
    override fun computeMinIntrinsicHeight(width: Double) = intrinsicMain(true, false, width)
    override fun computeMaxIntrinsicHeight(width: Double) = intrinsicMain(false, false, width)

    private fun intrinsicMain(min: Boolean, widthAxis: Boolean, extent: Double): Double {
        val gap = props.d("gap") ?: 0.0
        val gaps = max(0, children.size - 1) * gap
        fun get(ch: RenderObject): Double =
            if (widthAxis) {
                if (min) ch.minIntrinsicWidth(extent) else ch.maxIntrinsicWidth(extent)
            } else {
                if (min) ch.minIntrinsicHeight(extent) else ch.maxIntrinsicHeight(extent)
            }
        if (horizontal == widthAxis) {
            // Along the main axis: sum (flex children scaled to the largest per-flex).
            var inflexible = 0.0
            var maxPerFlex = 0.0
            var totalFlex = 0.0
            for (ch in children) {
                val info = flexInfo(ch)
                val v = get(ch)
                if (info.flex > 0) {
                    totalFlex += info.flex
                    maxPerFlex = max(maxPerFlex, v / info.flex)
                } else inflexible += v
            }
            return inflexible + maxPerFlex * totalFlex + gaps
        }
        // Across: the largest child.
        var m = 0.0
        for (ch in children) m = max(m, get(ch))
        return m
    }
}
