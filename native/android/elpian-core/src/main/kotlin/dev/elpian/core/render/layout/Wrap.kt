package dev.elpian.core.render.layout

import dev.elpian.core.render.*
import kotlin.math.max

/**
 * RenderWrap — Flutter's `Wrap` (render/layout/wrap.ts): children flow along
 * the main axis and wrap into runs; `spacing` separates children in a run,
 * `runSpacing` separates runs; `alignment` places children within a run,
 * `runAlignment` places runs within the box, `crossAxisAlignment` aligns
 * children within their run.
 *
 * Wrap alignments: start, end, center, spaceBetween, spaceAround, spaceEvenly.
 */
fun wrapAlignmentFromCss(value: String?): String = when ((value ?: "").lowercase()) {
    "center" -> "center"
    "flex-end", "end" -> "end"
    "space-between" -> "spaceBetween"
    "space-around" -> "spaceAround"
    "space-evenly" -> "spaceEvenly"
    else -> "start"
}

/** Leading space and space between items for [alignment]: (leading, between). */
private fun distribute(alignment: String, free: Double, count: Int): Pair<Double, Double> = when (alignment) {
    "end" -> free to 0.0
    "center" -> free / 2 to 0.0
    "spaceBetween" -> 0.0 to (if (count > 1) free / (count - 1) else 0.0)
    "spaceAround" -> {
        val b = if (count > 0) free / count else 0.0
        b / 2 to b
    }
    "spaceEvenly" -> {
        val b = if (count > 0) free / (count + 1) else 0.0
        b to b
    }
    else -> 0.0 to 0.0
}

/**
 * props: { direction: 'horizontal'|'vertical', spacing, runSpacing, alignment,
 *          runAlignment, crossAxisAlignment: 'start'|'end'|'center',
 *          verticalDirection: 'down'|'up', reverse }
 */
class RenderWrap : RenderObject() {
    private class Run {
        val children = ArrayList<RenderObject>()
        var main = 0.0
        var cross = 0.0
    }

    override fun performLayout(c: Constraints) {
        val horizontal = props["direction"] != "vertical"
        val spacing = props.d("spacing") ?: 0.0
        val runSpacing = props.d("runSpacing") ?: 0.0
        val mainLimit = if (horizontal) c.maxWidth else c.maxHeight
        val childC = if (horizontal) Constraints(0.0, c.maxWidth, 0.0, INF) else Constraints(0.0, INF, 0.0, c.maxHeight)
        fun main(s: Size) = if (horizontal) s.width else s.height
        fun cross(s: Size) = if (horizontal) s.height else s.width

        val runs = ArrayList<Run>()
        var run = Run()
        for (ch in children) {
            ch.layout(childC)
            val cm = main(ch.size)
            val extra = if (run.children.isNotEmpty()) spacing else 0.0
            if (run.children.isNotEmpty() && run.main + extra + cm > mainLimit + 0.01) {
                runs.add(run)
                run = Run()
            }
            run.main += (if (run.children.isNotEmpty()) spacing else 0.0) + cm
            run.cross = max(run.cross, cross(ch.size))
            run.children.add(ch)
        }
        if (run.children.isNotEmpty()) runs.add(run)

        var contentMain = 0.0
        var contentCross = 0.0
        for (r in runs) {
            contentMain = max(contentMain, r.main)
            contentCross += r.cross
        }
        contentCross += max(0, runs.size - 1) * runSpacing

        size = constrain(c, if (horizontal) Size(contentMain, contentCross) else Size(contentCross, contentMain))
        val boxMain = main(size)
        val boxCross = cross(size)

        val (runLeading, runBetween) = distribute(props.s("runAlignment") ?: "start", max(0.0, boxCross - contentCross), runs.size)
        val flipCross = props["verticalDirection"] == "up"
        var crossPos = runLeading
        val runOrder = if (flipCross) runs.reversed() else runs
        for (r in runOrder) {
            val (leading, between) = distribute(props.s("alignment") ?: "start", max(0.0, boxMain - r.main), r.children.size)
            var mainPos = leading
            val ordered = if (props.b("reverse")) r.children.reversed() else r.children
            for (ch in ordered) {
                val childCross = when (props.s("crossAxisAlignment") ?: "start") {
                    "end" -> r.cross - cross(ch.size)
                    "center" -> (r.cross - cross(ch.size)) / 2
                    else -> 0.0
                }
                ch.offset = if (horizontal) Vec(mainPos, crossPos + childCross) else Vec(crossPos + childCross, mainPos)
                mainPos += main(ch.size) + spacing + between
            }
            crossPos += r.cross + runSpacing + runBetween
        }
    }

    override fun computeMinIntrinsicWidth(height: Double): Double {
        if (props["direction"] == "vertical") return sum(height)
        var m = 0.0
        for (ch in children) m = max(m, ch.minIntrinsicWidth(INF))
        return m
    }

    override fun computeMaxIntrinsicWidth(height: Double): Double {
        if (props["direction"] == "vertical") {
            var m = 0.0
            for (ch in children) m = max(m, ch.maxIntrinsicWidth(INF))
            return m
        }
        return sum(height)
    }

    override fun computeMinIntrinsicHeight(width: Double): Double {
        // Lay out at the given width to know the run structure.
        if (!width.isFinite()) return computeMaxIntrinsicHeight(width)
        val saved = size
        layout(Constraints(0.0, width, 0.0, INF))
        val h = size.height
        size = saved
        needsLayout = true
        return h
    }

    override fun computeMaxIntrinsicHeight(width: Double): Double =
        computeMinIntrinsicHeight(if (width.isFinite()) width else computeMaxIntrinsicWidth(INF))

    /** Sum of the children's max-intrinsic widths plus spacing. */
    private fun sum(extent: Double): Double {
        val spacing = props.d("spacing") ?: 0.0
        var total = 0.0
        for (ch in children) total += ch.maxIntrinsicWidth(extent)
        return total + max(0, children.size - 1) * spacing
    }
}
