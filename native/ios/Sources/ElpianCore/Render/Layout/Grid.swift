import Foundation

/**
 * CSS grid layout (render/layout/grid.ts).
 *
 * Flutter's HtmlDiv resolves `display: grid` into a column count — from
 * `repeat(auto-fill|auto-fit, minmax(Npx, …))`, `repeat(N, …)` or the number
 * of listed tracks — and lays the children out in equal-width cells that wrap
 * row by row. That behaviour is kept for those templates. Templates Flutter
 * cannot express (mixed `px`/`fr`/`%`/`auto` tracks, `minmax`, spans,
 * explicit placement, explicit row tracks) are sized with the CSS track
 * algorithm instead of being flattened to equal columns.
 */

/** Parent data: props { column, row, justifySelf, alignSelf } (`column` / `row` are CSS `grid-column` / `grid-row`). */
open class RenderGridItem: RenderObject {
    open override func performLayout(_ c: Constraints) {
        if let child = child {
            child.layout(c)
            child.offset = .zero
            size = child.size
        } else {
            size = constrain(c, .zero)
        }
    }
}

public indirect enum Track: Equatable {
    case px(Double)
    case pct(Double)
    case fr(Double)
    case auto
    case minMax(Track, Track)

    var isFr: Bool { if case .fr = self { return true }; return false }
    var isAuto: Bool { if case .auto = self { return true }; return false }
    var isPx: Bool { if case .px = self { return true }; return false }
    var frValue: Double { if case .fr(let v) = self { return v }; return 0 }
    /** The `max` side of a minmax track, or the track itself. */
    var maxSide: Track { if case .minMax(_, let mx) = self { return mx }; return self }
}

public struct AutoRepeat {
    public let tracks: [Track]
    public let fit: Bool
}

public struct ParsedTemplate {
    public let tracks: [Track]
    /** `repeat(auto-fill|auto-fit, …)` */
    public let autoRepeat: AutoRepeat?
    /** Insertion index of the auto-repeat block within [tracks]. */
    public let autoIndex: Int
}

/** JavaScript `parseFloat(x) || fallback` (NaN and 0 fall back). */
private func parseFloatOr(_ t: String, _ fallback: Double) -> Double {
    let v = jsParseFloat(t)
    return v.isNaN || v == 0 ? fallback : v
}

public func parseTrack(_ token: String) -> Track {
    let t = jsTrim(token).lowercased()
    if t.hasPrefix("minmax(") {
        let inner = jsSubstring(t, 7, jsLength(t) - 1)
        let parts = splitTopLevel(inner, ",").map { jsTrim($0) }
        return .minMax(parseTrack(parts.count > 0 ? parts[0] : "auto"), parseTrack(parts.count > 1 ? parts[1] : "auto"))
    }
    if t.hasPrefix("fit-content(") { return .minMax(.auto, parseTrack(jsSubstring(t, 12, jsLength(t) - 1))) }
    if t.hasSuffix("fr") { return .fr(parseFloatOr(t, 1)) }
    if t.hasSuffix("%") { return .pct(parseFloatOr(t, 0)) }
    if t == "auto" || t == "min-content" || t == "max-content" { return .auto }
    let n = jsParseFloat(t)
    if n.isFinite {
        if t.hasSuffix("rem") || t.hasSuffix("em") { return .px(n * 16) }
        return .px(n)
    }
    return .auto
}

public func parseTemplate(_ template: String?) -> ParsedTemplate? {
    guard let template = template, !template.isEmpty else { return nil }
    let value = jsTrim(template)
    if value == "" || value == "none" { return nil }
    var tracks: [Track] = []
    var autoRepeat: AutoRepeat?
    var autoIndex = 0
    for token in splitTopLevel(value, " ") {
        let t = jsTrim(token)
        if t.hasPrefix("[") { continue } // line names
        if t.lowercased().hasPrefix("repeat(") {
            let inner = jsSubstring(t, 7, jsLength(t) - 1)
            let comma = jsIndexOf(inner, ",")
            let count = jsTrim(jsSubstring(inner, 0, comma)).lowercased()
            let body = splitTopLevel(jsTrim(jsSubstring(inner, comma + 1)), " ").map(parseTrack)
            if count == "auto-fill" || count == "auto-fit" {
                autoRepeat = AutoRepeat(tracks: body, fit: count == "auto-fit")
                autoIndex = tracks.count
            } else {
                let parsed = jsParseInt(count, 10)
                let n = max(1, parsed.isNaN || parsed == 0 ? 1 : parsed)
                let reps = n.isFinite ? Int(min(n, 1_000_000)) : 1
                for _ in 0..<reps { tracks.append(contentsOf: body) }
            }
        } else {
            tracks.append(parseTrack(t))
        }
    }
    if tracks.isEmpty && autoRepeat == nil { return nil }
    return ParsedTemplate(tracks: tracks, autoRepeat: autoRepeat, autoIndex: autoIndex)
}

private func trackMin(_ t: Track, _ basis: Double) -> Double {
    switch t {
    case .px(let v): return v
    case .pct(let v): return basis.isFinite ? (v / 100) * basis : 0
    case .minMax(let mn, _): return trackMin(mn, basis)
    default: return 0
    }
}

private struct GridPlacement {
    let start: Int?
    let span: Int
}

private let SPAN = JSRegex("span\\s+(\\d+)")
private let INT = JSRegex("^-?\\d+$")

private func intOf(_ d: Double) -> Int? {
    guard d.isFinite else { return nil }
    return Int(max(-1_000_000, min(1_000_000, d)))
}

private func parsePlacement(_ raw: Any?) -> GridPlacement {
    if !jsTruthy(raw) { return GridPlacement(start: nil, span: 1) }
    let parts = jsSplit(jsString(raw), "/").map { jsTrim($0).lowercased() }
    var start: Int?
    var span = 1
    let first = parts.count > 0 ? parts[0] : ""
    if let m1 = SPAN.exec(first) {
        span = max(1, intOf(jsParseInt(m1[1] ?? "", 10)).flatMap { $0 == 0 ? nil : $0 } ?? 1)
    } else if INT.test(first) {
        start = intOf(jsParseInt(first, 10))
    }
    if parts.count > 1 {
        let second = parts[1]
        if let m2 = SPAN.exec(second) {
            span = max(1, intOf(jsParseInt(m2[1] ?? "", 10)).flatMap { $0 == 0 ? nil : $0 } ?? 1)
        } else if INT.test(second), let s = start {
            span = max(1, (intOf(jsParseInt(second, 10)) ?? 0) - s)
        }
    }
    return GridPlacement(start: start != nil && start! > 0 ? start! - 1 : nil, span: span)
}

/**
 * props: { columns, rows, autoRows, columnGap, rowGap, alignItems, justifyItems }
 */
open class RenderGrid: RenderObject {
    private struct Item {
        let ro: RenderObject
        let col: Int
        let row: Int
        let colSpan: Int
        let rowSpan: Int
    }

    private struct FrTrack {
        let i: Int
        let minTrack: Track?
        let base: Track
    }

    private func wrapFallback(_ c: Constraints, _ colGap: Double, _ rowGap: Double) {
        // Flutter: an unbounded grid becomes a plain Wrap.
        var x = 0.0
        var y = 0.0
        var rowH = 0.0
        var maxW = 0.0
        let limit = c.maxWidth
        for ch in children {
            ch.layout(Constraints(minWidth: 0, maxWidth: limit, minHeight: 0, maxHeight: INF))
            if x > 0 && x + ch.size.width > limit {
                x = 0
                y += rowH + rowGap
                rowH = 0
            }
            ch.offset = Vec(x: x, y: y)
            x += ch.size.width + colGap
            rowH = max(rowH, ch.size.height)
            maxW = max(maxW, x - colGap)
        }
        size = constrain(c, Size(width: maxW, height: !children.isEmpty ? y + rowH : 0))
    }

    open override func performLayout(_ c: Constraints) {
        let colGap = props.d("columnGap") ?? 0
        let rowGap = props.d("rowGap") ?? 0
        let template = parseTemplate(props.s("columns"))
        let children = self.children
        let W = c.maxWidth
        guard let tpl = template, W.isFinite else {
            wrapFallback(c, colGap, rowGap)
            return
        }

        // ---- column tracks ----
        let tracks: [Track]
        if let auto = tpl.autoRepeat {
            let fixed = tpl.tracks.reduce(0.0) { $0 + trackMin($1, W) } + Double(tpl.tracks.count) * colGap
            let unit = auto.tracks
            let unitMin = unit.reduce(0.0) { acc, t in acc + max(trackMin(t, W), t.isFr || t.isAuto ? 1 : 0) }
            let unitGaps = Double(unit.count) * colGap
            let rawReps = max(1, ((W - fixed + colGap) / (unitMin + unitGaps)).rounded(.down))
            var reps = rawReps.isFinite ? Int(min(rawReps, 100_000)) : 1
            // Flutter caps the count at the number of items (so few items stretch).
            if tpl.tracks.isEmpty && unit.count == 1 { reps = min(reps, max(1, children.count)) }
            let split = min(tpl.autoIndex, tpl.tracks.count)
            var out = Array(tpl.tracks[0..<split])
            for _ in 0..<reps {
                // An auto-fill `minmax(min, X)` behaves like `minmax(min, 1fr)` once the count is fixed.
                out.append(contentsOf: unit.map { t -> Track in
                    if case .minMax(let mn, _) = t { return .minMax(mn, .fr(1)) }
                    return t
                })
            }
            out.append(contentsOf: tpl.tracks[split...])
            tracks = out
        } else {
            tracks = tpl.tracks
        }
        let colCount = max(1, tracks.count)

        // ---- placement ----
        var items: [Item] = []
        var occupied = Set<String>()
        func isFree(_ row: Int, _ col: Int, _ colSpan: Int, _ rowSpan: Int) -> Bool {
            if col + colSpan > colCount { return false }
            for r in row..<(row + rowSpan) {
                for k in col..<(col + colSpan) where occupied.contains("\(r):\(k)") { return false }
            }
            return true
        }
        func occupy(_ row: Int, _ col: Int, _ colSpan: Int, _ rowSpan: Int) {
            for r in row..<(row + rowSpan) {
                for k in col..<(col + colSpan) { occupied.insert("\(r):\(k)") }
            }
        }
        var cursorRow = 0
        var cursorCol = 0
        for ch in children {
            let pd: JSONObject = ch is RenderGridItem ? ch.props : JSONObject()
            let colP = parsePlacement(pd["column"])
            let rowP = parsePlacement(pd["row"])
            let colSpan = min(colCount, colP.span)
            let rowSpan = rowP.span
            var row = rowP.start ?? -1
            var col = colP.start ?? -1
            if col >= colCount { col = colCount - colSpan }
            if row >= 0 && col >= 0 {
                // fully explicit
            } else if row >= 0 {
                col = 0
                while !isFree(row, col, colSpan, rowSpan) {
                    col += 1
                    if col + colSpan > colCount {
                        col = 0
                        row += 1
                    }
                }
            } else if col >= 0 {
                row = 0
                while !isFree(row, col, colSpan, rowSpan) { row += 1 }
            } else {
                row = cursorRow
                col = cursorCol
                while !isFree(row, col, colSpan, rowSpan) {
                    col += 1
                    if col + colSpan > colCount {
                        col = 0
                        row += 1
                    }
                }
                cursorRow = row
                cursorCol = col + colSpan
                if cursorCol >= colCount {
                    cursorCol = 0
                    cursorRow += 1
                }
            }
            occupy(row, col, colSpan, rowSpan)
            items.append(Item(ro: ch, col: col, row: row, colSpan: colSpan, rowSpan: rowSpan))
        }

        // ---- column sizing ----
        var widths = [Double](repeating: 0, count: colCount)
        var fixedTotal = 0.0
        var frTotal = 0.0
        for i in 0..<colCount {
            let t = i < tracks.count ? tracks[i] : .fr(1)
            let base = t.maxSide
            if base.isFr {
                frTotal += base.frValue
            } else if base.isAuto {
                var m = trackMin(t, W)
                for it in items where it.col == i && it.colSpan == 1 { m = max(m, it.ro.maxIntrinsicWidth(INF)) }
                widths[i] = m
                fixedTotal += m
            } else {
                widths[i] = max(trackMin(t, W), trackMin(base, W))
                fixedTotal += widths[i]
            }
        }
        let gaps = Double(colCount - 1) * colGap
        var free = W - fixedTotal - gaps
        if frTotal > 0 {
            // Distribute free space to fr tracks, respecting minmax minimums.
            let frTracks: [FrTrack] = tracks.enumerated().compactMap { i, t in
                var minTrack: Track?
                if case .minMax(let mn, _) = t { minTrack = mn }
                let base = t.maxSide
                return base.isFr ? FrTrack(i: i, minTrack: minTrack, base: base) : nil
            }
            var remaining = max(0, free)
            var pool = frTracks
            var iter = 0
            while iter < 4 && !pool.isEmpty {
                let totalFr = pool.reduce(0.0) { $0 + $1.base.frValue }
                let perFr = remaining / totalFr
                let stuck = pool.filter { x in x.minTrack != nil && trackMin(x.minTrack!, W) > perFr * x.base.frValue }
                if stuck.isEmpty {
                    for x in pool { widths[x.i] = perFr * x.base.frValue }
                    pool = []
                    break
                }
                for x in stuck {
                    widths[x.i] = trackMin(x.minTrack!, W)
                    remaining -= widths[x.i]
                }
                let stuckIdx = Set(stuck.map { $0.i })
                pool = pool.filter { !stuckIdx.contains($0.i) }
                iter += 1
            }
            free = 0
        } else if free < 0 {
            // Over-constrained auto columns shrink proportionally (never below 0).
            let autoIdx = tracks.indices.filter { tracks[$0].isAuto }
            let autoSum = autoIdx.reduce(0.0) { $0 + widths[$1] }
            if autoSum > 0 {
                for i in autoIdx { widths[i] = max(0, widths[i] + (free * widths[i]) / autoSum) }
            }
        }

        var colX = [Double](repeating: 0, count: colCount)
        var acc = 0.0
        for i in 0..<colCount {
            colX[i] = acc
            acc += widths[i] + colGap
        }
        func spanWidth(_ col: Int, _ span: Int) -> Double {
            var s = 0.0
            var k = col
            while k < min(colCount, col + span) {
                s += widths[k]
                k += 1
            }
            return s + Double(min(span, colCount - col) - 1) * colGap
        }

        // ---- rows ----
        let rowCount = items.reduce(0) { max($0, $1.row + $1.rowSpan) }
        let rowTemplate = parseTemplate(props.s("rows"))
        let autoRowTrack: Track? = jsTruthy(props["autoRows"]) ? parseTrack(jsString(props["autoRows"])) : nil
        var heights = [Double](repeating: 0, count: rowCount)
        var rowFixed = [Bool](repeating: false, count: rowCount)
        for r in 0..<rowCount {
            let fromTemplate: Track? = rowTemplate.flatMap { r < $0.tracks.count ? $0.tracks[r] : nil }
            let t = fromTemplate ?? autoRowTrack
            if let t = t {
                var minIsPx = false
                if case .minMax(let mn, _) = t { minIsPx = mn.isPx }
                if t.isPx || minIsPx {
                    heights[r] = trackMin(t, c.maxHeight)
                    rowFixed[r] = t.isPx
                }
            }
        }
        let stretch = (props.s("alignItems") ?? "start") == "stretch"
        for it in items {
            let width = spanWidth(it.col, it.colSpan)
            it.ro.layout(Constraints(minWidth: width, maxWidth: width, minHeight: 0, maxHeight: INF))
            if it.rowSpan == 1 && !rowFixed[it.row] { heights[it.row] = max(heights[it.row], it.ro.size.height) }
        }
        // Spanning items grow their last row if needed.
        for it in items {
            if it.rowSpan == 1 { continue }
            var h = 0.0
            for r in it.row..<(it.row + it.rowSpan) { h += heights[r] }
            h += Double(it.rowSpan - 1) * rowGap
            let last = it.row + it.rowSpan - 1
            if it.ro.size.height > h && !rowFixed[last] { heights[last] += it.ro.size.height - h }
        }
        var rowY = [Double](repeating: 0, count: rowCount)
        var y = 0.0
        for r in 0..<rowCount {
            rowY[r] = y
            y += heights[r] + rowGap
        }
        let totalH = rowCount > 0 ? y - rowGap : 0

        for it in items {
            var cellH = 0.0
            for r in it.row..<(it.row + it.rowSpan) { cellH += heights[r] }
            cellH += Double(it.rowSpan - 1) * rowGap
            if stretch || rowFixed[it.row] {
                let width = spanWidth(it.col, it.colSpan)
                it.ro.layout(Constraints(minWidth: width, maxWidth: width, minHeight: stretch ? cellH : 0, maxHeight: stretch ? cellH : max(cellH, 0)))
            }
            var dy = 0.0
            let align = it.ro.props.s("alignSelf") ?? props.s("alignItems")
            if align == "center" {
                dy = (cellH - it.ro.size.height) / 2
            } else if align == "end" || align == "flex-end" {
                dy = cellH - it.ro.size.height
            }
            it.ro.offset = Vec(x: colX[it.col], y: rowY[it.row] + dy)
        }
        size = constrain(c, Size(width: W, height: totalH))
    }

    open override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        var m = 0.0
        for ch in children { m = max(m, ch.maxIntrinsicWidth(height)) }
        let template = parseTemplate(props.s("columns"))
        let n = template?.tracks.count ?? 0
        let cols = n != 0 ? n : 1
        return m * Double(cols) + Double(cols - 1) * (props.d("columnGap") ?? 0)
    }

    open override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        var m = 0.0
        for ch in children { m = max(m, ch.minIntrinsicWidth(height)) }
        return m
    }
}
