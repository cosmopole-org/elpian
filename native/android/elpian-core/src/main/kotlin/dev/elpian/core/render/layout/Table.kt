package dev.elpian.core.render.layout

import dev.elpian.core.render.*
import kotlin.math.max
import kotlin.math.min
import kotlin.math.truncate

/**
 * HTML table layout (`table` / `thead` / `tbody` / `tfoot` / `tr` / `td` / `th`
 * / `caption`), the CSS "auto" table algorithm (render/layout/table.ts):
 *
 *   * every cell reports its min-content and max-content width;
 *   * column widths start at the max-content widths when they fit, otherwise
 *     the space above the min-content widths is shared in proportion;
 *   * `colspan` cells spread their excess over the columns they span;
 *   * `rowspan` cells occupy the following rows, row heights grow to fit.
 *
 * The Flutter engine renders an empty table here; this is the real thing.
 */

/** A row: props { decorated, background } — children are RenderTableCell. */
class RenderTableRow : RenderObject() {
    override fun performLayout(c: Constraints) {
        // Rows are positioned by the table; standalone they stack their cells.
        var x = 0.0
        var h = 0.0
        for (cell in children) {
            cell.layout(Constraints(0.0, INF, 0.0, c.maxHeight))
            cell.offset = Vec(x, 0.0)
            x += cell.size.width
            h = max(h, cell.size.height)
        }
        size = constrain(c, Size(x, h))
    }

    override fun viewKind(): String? = if (truthy(props["decorated"])) ViewKinds.VIEW else null

    override fun viewProps(): ViewProps = linkedMapOf("background" to props["background"])
}

/** A cell: props { colSpan, rowSpan, verticalAlign: 'top'|'middle'|'bottom', width } */
class RenderTableCell : RenderObject() {
    override fun performLayout(c: Constraints) {
        val ch = child
        if (ch != null) {
            ch.layout(Constraints(c.minWidth, c.maxWidth, 0.0, c.maxHeight))
            size = constrain(c, ch.size)
            val free = size.height - ch.size.height
            val va = props.s("verticalAlign") ?: "middle"
            ch.offset = Vec(0.0, if (va == "top") 0.0 else if (va == "bottom") free else free / 2)
        } else size = constrain(c, Size(0.0, 0.0))
    }
}

/**
 * props: { borderSpacing, collapse, caption?: 'top'|'bottom', fullWidth }
 * children: optional caption (any non-row RenderObject) then rows.
 */
class RenderTable : RenderObject() {
    private class Cell(val ro: RenderTableCell, val row: Int, val col: Int, val colSpan: Int, val rowSpan: Int)

    private var cells = ArrayList<Cell>()
    private var columns = 0

    private fun collect(): Pair<List<RenderTableRow>, RenderObject?> {
        val rows = ArrayList<RenderTableRow>()
        var caption: RenderObject? = null
        for (ch in children) {
            if (ch is RenderTableRow) rows.add(ch)
            else if (caption == null) caption = ch
        }
        return rows to caption
    }

    private fun place(rows: List<RenderTableRow>) {
        cells = ArrayList()
        val occupied = HashSet<String>()
        var columns = 0
        rows.forEachIndexed { r, row ->
            var col = 0
            for (cellRo in row.children) {
                if (cellRo !is RenderTableCell) continue
                while ("$r:$col" in occupied) col++
                val colSpan = max(1.0, truncate(cellRo.props.d("colSpan") ?: 1.0)).toInt()
                val rowSpan = max(1.0, min((rows.size - r).toDouble(), truncate(cellRo.props.d("rowSpan") ?: 1.0))).toInt()
                for (rr in r until r + rowSpan) for (cc in col until col + colSpan) occupied.add("$rr:$cc")
                cells.add(Cell(cellRo, r, col, colSpan, rowSpan))
                col += colSpan
                columns = max(columns, col)
            }
        }
        this.columns = columns
    }

    private fun columnWidths(available: Double, spacing: Double): DoubleArray {
        val n = columns
        val minW = DoubleArray(n)
        val maxW = DoubleArray(n)
        val spans = cells.sortedBy { it.colSpan }
        for (cell in spans) {
            val cmin = cell.ro.minIntrinsicWidth(INF)
            val cmax = cell.ro.maxIntrinsicWidth(INF)
            val fixed = cell.ro.props.d("width")
            if (cell.colSpan == 1) {
                minW[cell.col] = max(minW[cell.col], fixed ?: cmin)
                maxW[cell.col] = max(maxW[cell.col], fixed ?: cmax)
            } else {
                val cols = (0 until cell.colSpan).map { cell.col + it }.filter { it < n }
                val inner = (cell.colSpan - 1) * spacing
                val curMin = cols.sumOf { minW[it] } + inner
                val curMax = cols.sumOf { maxW[it] } + inner
                if (cmin > curMin) for (k in cols) minW[k] += (cmin - curMin) / cols.size
                if (cmax > curMax) for (k in cols) maxW[k] += (cmax - curMax) / cols.size
            }
        }
        for (k in 0 until n) maxW[k] = max(maxW[k], minW[k])
        val gaps = (n + 1) * spacing
        val sumMax = maxW.sum()
        val sumMin = minW.sum()
        val room = available - gaps
        if (!available.isFinite() || sumMax <= room) {
            if (truthy(props["fullWidth"]) && available.isFinite() && sumMax > 0 && sumMax < room) {
                return DoubleArray(n) { k -> maxW[k] + ((room - sumMax) * maxW[k]) / sumMax }
            }
            return maxW
        }
        if (sumMin >= room) return minW
        val extra = room - sumMin
        val flexTotal = sumMax - sumMin
        return DoubleArray(n) { k -> minW[k] + (if (flexTotal > 0) (extra * (maxW[k] - minW[k])) / flexTotal else extra / n) }
    }

    override fun performLayout(c: Constraints) {
        val spacing = if (props["collapse"] == false) props.d("borderSpacing") ?: 2.0 else 0.0
        val (rows, caption) = collect()
        place(rows)
        val widths = columnWidths(c.maxWidth, spacing)
        val colX = ArrayList<Double>()
        var x = spacing
        for (w in widths) {
            colX.add(x)
            x += w + spacing
        }
        val tableWidth = max(x, c.minWidth)
        fun spanW(col: Int, span: Int): Double {
            var s = 0.0
            var k = col
            while (k < col + span && k < widths.size) {
                s += widths[k]
                k++
            }
            return s + (span - 1) * spacing
        }

        val rowH = DoubleArray(rows.size)
        for (cell in cells) {
            val w = spanW(cell.col, cell.colSpan)
            cell.ro.layout(Constraints(w, w, 0.0, INF))
            if (cell.rowSpan == 1) rowH[cell.row] = max(rowH[cell.row], cell.ro.size.height)
        }
        for (cell in cells) {
            if (cell.rowSpan == 1) continue
            var h = 0.0
            for (r in cell.row until cell.row + cell.rowSpan) h += rowH[r]
            h += (cell.rowSpan - 1) * spacing
            if (cell.ro.size.height > h) rowH[cell.row + cell.rowSpan - 1] += cell.ro.size.height - h
        }

        var y = 0.0
        var captionHeight = 0.0
        val captionBottom = props["caption"] == "bottom"
        if (caption != null) {
            caption.layout(Constraints(tableWidth, tableWidth, 0.0, INF))
            captionHeight = caption.size.height
            if (!captionBottom) {
                caption.offset = Vec(0.0, 0.0)
                y = captionHeight
            }
        }
        val rowY = ArrayList<Double>()
        y += spacing
        for (r in rows.indices) {
            rowY.add(y)
            y += rowH[r] + spacing
        }
        // Each row spans the full table width; cells are positioned inside it.
        rows.forEachIndexed { r, row ->
            row.size = Size(tableWidth, rowH[r])
            row.offset = Vec(0.0, rowY[r])
            row.needsLayout = false
        }
        for (cell in cells) {
            var h = 0.0
            for (rr in cell.row until cell.row + cell.rowSpan) h += rowH[rr]
            h += (cell.rowSpan - 1) * spacing
            val w = spanW(cell.col, cell.colSpan)
            cell.ro.layout(Constraints(w, w, h, h))
            cell.ro.offset = Vec(colX[cell.col], 0.0)
            if (cell.rowSpan > 1) cell.ro.offset.y = 0.0
        }
        if (caption != null && captionBottom) {
            caption.offset = Vec(0.0, y)
            y += captionHeight
        }
        size = constrain(c, Size(tableWidth, y))
    }

    override fun computeMinIntrinsicWidth(height: Double): Double {
        place(collect().first)
        return columnWidths(0.0, 0.0).sum()
    }

    override fun computeMaxIntrinsicWidth(height: Double): Double {
        place(collect().first)
        return columnWidths(INF, 0.0).sum()
    }
}
