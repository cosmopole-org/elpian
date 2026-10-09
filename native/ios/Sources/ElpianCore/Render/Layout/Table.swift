import Foundation

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
open class RenderTableRow: RenderObject {
    open override func performLayout(_ c: Constraints) {
        // Rows are positioned by the table; standalone they stack their cells.
        var x = 0.0
        var h = 0.0
        for cell in children {
            cell.layout(Constraints(minWidth: 0, maxWidth: INF, minHeight: 0, maxHeight: c.maxHeight))
            cell.offset = Vec(x: x, y: 0)
            x += cell.size.width
            h = max(h, cell.size.height)
        }
        size = constrain(c, Size(width: x, height: h))
    }

    open override func viewKind() -> ViewKind? { jsTruthy(props["decorated"]) ? .view : nil }

    open override func viewProps() -> ViewProps { ViewProps([("background", props["background"])]) }
}

/** A cell: props { colSpan, rowSpan, verticalAlign: 'top'|'middle'|'bottom', width } */
open class RenderTableCell: RenderObject {
    open override func performLayout(_ c: Constraints) {
        if let child = child {
            child.layout(Constraints(minWidth: c.minWidth, maxWidth: c.maxWidth, minHeight: 0, maxHeight: c.maxHeight))
            size = constrain(c, child.size)
            let free = size.height - child.size.height
            let va = props.s("verticalAlign") ?? "middle"
            child.offset = Vec(x: 0, y: va == "top" ? 0 : va == "bottom" ? free : free / 2)
        } else {
            size = constrain(c, .zero)
        }
    }
}

/**
 * props: { borderSpacing, collapse, caption?: 'top'|'bottom', fullWidth }
 * children: optional caption (any non-row RenderObject) then rows.
 */
open class RenderTable: RenderObject {
    private struct Cell {
        let ro: RenderTableCell
        let row: Int
        let col: Int
        let colSpan: Int
        let rowSpan: Int
    }

    private var cells: [Cell] = []
    private var columns = 0

    private func collect() -> (rows: [RenderTableRow], caption: RenderObject?) {
        var rows: [RenderTableRow] = []
        var caption: RenderObject?
        for ch in children {
            if let row = ch as? RenderTableRow {
                rows.append(row)
            } else if caption == nil {
                caption = ch
            }
        }
        return (rows, caption)
    }

    /** A span count as an Int (spans are clamped to a sane maximum). */
    private static func spanCount(_ v: Double) -> Int {
        guard v.isFinite else { return v > 0 ? 1_000 : 1 }
        return Int(min(v, 1_000))
    }

    private func place(_ rows: [RenderTableRow]) {
        cells = []
        var occupied = Set<String>()
        var columns = 0
        for (r, row) in rows.enumerated() {
            var col = 0
            for child in row.children {
                guard let cellRo = child as? RenderTableCell else { continue }
                while occupied.contains("\(r):\(col)") { col += 1 }
                let colSpan = RenderTable.spanCount(max(1, jsTrunc(cellRo.props.d("colSpan") ?? 1)))
                let rowSpan = RenderTable.spanCount(max(1, min(Double(rows.count - r), jsTrunc(cellRo.props.d("rowSpan") ?? 1))))
                for rr in r..<(r + rowSpan) {
                    for cc in col..<(col + colSpan) { occupied.insert("\(rr):\(cc)") }
                }
                cells.append(Cell(ro: cellRo, row: r, col: col, colSpan: colSpan, rowSpan: rowSpan))
                col += colSpan
                columns = max(columns, col)
            }
        }
        self.columns = columns
    }

    private func columnWidths(_ available: Double, _ spacing: Double) -> [Double] {
        let n = columns
        var minW = [Double](repeating: 0, count: n)
        var maxW = [Double](repeating: 0, count: n)
        // A stable sort by span (Array.prototype.sort is stable).
        let spans = cells.enumerated().sorted { a, b in
            a.element.colSpan != b.element.colSpan ? a.element.colSpan < b.element.colSpan : a.offset < b.offset
        }.map { $0.element }
        for cell in spans {
            let cmin = cell.ro.minIntrinsicWidth(INF)
            let cmax = cell.ro.maxIntrinsicWidth(INF)
            let fixed = cell.ro.props.d("width")
            if cell.colSpan == 1 {
                minW[cell.col] = max(minW[cell.col], fixed ?? cmin)
                maxW[cell.col] = max(maxW[cell.col], fixed ?? cmax)
            } else {
                let cols = (0..<cell.colSpan).map { cell.col + $0 }.filter { $0 < n }
                let inner = Double(cell.colSpan - 1) * spacing
                let curMin = cols.reduce(0.0) { $0 + minW[$1] } + inner
                let curMax = cols.reduce(0.0) { $0 + maxW[$1] } + inner
                if cmin > curMin { for k in cols { minW[k] += (cmin - curMin) / Double(cols.count) } }
                if cmax > curMax { for k in cols { maxW[k] += (cmax - curMax) / Double(cols.count) } }
            }
        }
        for k in 0..<n { maxW[k] = max(maxW[k], minW[k]) }
        let gaps = Double(n + 1) * spacing
        let sumMax = maxW.reduce(0, +)
        let sumMin = minW.reduce(0, +)
        let room = available - gaps
        if !available.isFinite || sumMax <= room {
            if jsTruthy(props["fullWidth"]) && available.isFinite && sumMax > 0 && sumMax < room {
                return (0..<n).map { k in maxW[k] + ((room - sumMax) * maxW[k]) / sumMax }
            }
            return maxW
        }
        if sumMin >= room { return minW }
        let extra = room - sumMin
        let flexTotal = sumMax - sumMin
        return (0..<n).map { (k: Int) -> Double in
            let share: Double = flexTotal > 0 ? (extra * (maxW[k] - minW[k])) / flexTotal : extra / Double(n)
            return minW[k] + share
        }
    }

    open override func performLayout(_ c: Constraints) {
        let spacing = props.isFalse("collapse") ? props.d("borderSpacing") ?? 2 : 0
        let (rows, caption) = collect()
        place(rows)
        let widths = columnWidths(c.maxWidth, spacing)
        var colX: [Double] = []
        var x = spacing
        for w in widths {
            colX.append(x)
            x += w + spacing
        }
        let tableWidth = max(x, c.minWidth)
        func spanW(_ col: Int, _ span: Int) -> Double {
            var s = 0.0
            var k = col
            while k < col + span && k < widths.count {
                s += widths[k]
                k += 1
            }
            return s + Double(span - 1) * spacing
        }

        var rowH = [Double](repeating: 0, count: rows.count)
        for cell in cells {
            let w = spanW(cell.col, cell.colSpan)
            cell.ro.layout(Constraints(minWidth: w, maxWidth: w, minHeight: 0, maxHeight: INF))
            if cell.rowSpan == 1 { rowH[cell.row] = max(rowH[cell.row], cell.ro.size.height) }
        }
        for cell in cells {
            if cell.rowSpan == 1 { continue }
            var h = 0.0
            for r in cell.row..<(cell.row + cell.rowSpan) { h += rowH[r] }
            h += Double(cell.rowSpan - 1) * spacing
            if cell.ro.size.height > h { rowH[cell.row + cell.rowSpan - 1] += cell.ro.size.height - h }
        }

        var y = 0.0
        var captionHeight = 0.0
        let captionBottom = props.s("caption") == "bottom"
        if let caption = caption {
            caption.layout(Constraints(minWidth: tableWidth, maxWidth: tableWidth, minHeight: 0, maxHeight: INF))
            captionHeight = caption.size.height
            if !captionBottom {
                caption.offset = .zero
                y = captionHeight
            }
        }
        var rowY: [Double] = []
        y += spacing
        for r in rows.indices {
            rowY.append(y)
            y += rowH[r] + spacing
        }
        // Each row spans the full table width; cells are positioned inside it.
        for (r, row) in rows.enumerated() {
            row.size = Size(width: tableWidth, height: rowH[r])
            row.offset = Vec(x: 0, y: rowY[r])
            row.needsLayout = false
        }
        for cell in cells {
            var h = 0.0
            for rr in cell.row..<(cell.row + cell.rowSpan) { h += rowH[rr] }
            h += Double(cell.rowSpan - 1) * spacing
            let w = spanW(cell.col, cell.colSpan)
            cell.ro.layout(Constraints(minWidth: w, maxWidth: w, minHeight: h, maxHeight: h))
            cell.ro.offset = Vec(x: colX[cell.col], y: 0)
        }
        if let caption = caption, captionBottom {
            caption.offset = Vec(x: 0, y: y)
            y += captionHeight
        }
        size = constrain(c, Size(width: tableWidth, height: y))
    }

    open override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        place(collect().rows)
        return columnWidths(0, 0).reduce(0, +)
    }

    open override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        place(collect().rows)
        return columnWidths(INF, 0).reduce(0, +)
    }
}
