package dev.elpian.core.render.layout

import dev.elpian.core.css.CSSParser.splitTopLevel
import dev.elpian.core.render.*
import dev.elpian.core.util.jsString
import dev.elpian.core.util.parseFloatPrefix
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

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
class RenderGridItem : RenderObject() {
    override fun performLayout(c: Constraints) {
        val ch = child
        if (ch != null) {
            ch.layout(c)
            ch.offset = Vec(0.0, 0.0)
            size = ch.size.copy()
        } else size = constrain(c, Size(0.0, 0.0))
    }
}

sealed class Track {
    data class Px(val value: Double) : Track()
    data class Pct(val value: Double) : Track()
    data class Fr(val value: Double) : Track()
    object Auto : Track()
    data class MinMax(val min: Track, val max: Track) : Track()
}

class AutoRepeat(val tracks: List<Track>, val fit: Boolean)

class ParsedTemplate(
    val tracks: List<Track>,
    /** `repeat(auto-fill|auto-fit, …)` */
    val autoRepeat: AutoRepeat?,
    /** Insertion index of the auto-repeat block within [tracks]. */
    val autoIndex: Int,
)

/** JavaScript `parseFloat(x) || fallback` (NaN and 0 fall back). */
private fun parseFloatOr(t: String, fallback: Double): Double {
    val v = parseFloatPrefix(t)
    return if (v == null || v.isNaN() || v == 0.0) fallback else v
}

/** JavaScript `String.prototype.substring`: clamps both ends to the string and swaps them when reversed. */
private fun jsSubstring(s: String, start: Int, end: Int): String {
    val a = start.coerceIn(0, s.length)
    val b = end.coerceIn(0, s.length)
    return if (a <= b) s.substring(a, b) else s.substring(b, a)
}

/** JavaScript `Number.parseInt(s, 10)`: the leading integer, or null (NaN). */
private fun jsParseInt(s: String): Int? {
    val m = Regex("^[+-]?\\d+").find(s.trimStart()) ?: return null
    return m.value.toBigInteger().let { big ->
        when {
            big > Int.MAX_VALUE.toBigInteger() -> Int.MAX_VALUE
            big < Int.MIN_VALUE.toBigInteger() -> Int.MIN_VALUE
            else -> big.toInt()
        }
    }
}

fun parseTrack(token: String): Track {
    val t = token.trim().lowercase()
    if (t.startsWith("minmax(")) {
        val inner = jsSubstring(t, 7, t.length - 1)
        val parts = splitTopLevel(inner, ",").map { it.trim() }
        return Track.MinMax(parseTrack(parts.getOrNull(0) ?: "auto"), parseTrack(parts.getOrNull(1) ?: "auto"))
    }
    if (t.startsWith("fit-content(")) return Track.MinMax(Track.Auto, parseTrack(jsSubstring(t, 12, t.length - 1)))
    if (t.endsWith("fr")) return Track.Fr(parseFloatOr(t, 1.0))
    if (t.endsWith("%")) return Track.Pct(parseFloatOr(t, 0.0))
    if (t == "auto" || t == "min-content" || t == "max-content") return Track.Auto
    val n = parseFloatPrefix(t)
    if (n != null && n.isFinite()) {
        if (t.endsWith("rem") || t.endsWith("em")) return Track.Px(n * 16)
        return Track.Px(n)
    }
    return Track.Auto
}

fun parseTemplate(template: String?): ParsedTemplate? {
    if (template.isNullOrEmpty()) return null
    val value = template.trim()
    if (value == "" || value == "none") return null
    val tracks = ArrayList<Track>()
    var autoRepeat: AutoRepeat? = null
    var autoIndex = 0
    for (token in splitTopLevel(value, " ")) {
        val t = token.trim()
        if (t.startsWith("[")) continue // line names
        if (t.lowercase().startsWith("repeat(")) {
            val inner = jsSubstring(t, 7, t.length - 1)
            val comma = inner.indexOf(',')
            val count = jsSubstring(inner, 0, comma).trim().lowercase()
            val body = splitTopLevel(inner.substring(comma + 1).trim(), " ").map(::parseTrack)
            if (count == "auto-fill" || count == "auto-fit") {
                autoRepeat = AutoRepeat(body, count == "auto-fit")
                autoIndex = tracks.size
            } else {
                val parsed = jsParseInt(count)
                val n = max(1, if (parsed == null || parsed == 0) 1 else parsed)
                for (i in 0 until n) tracks.addAll(body)
            }
        } else tracks.add(parseTrack(t))
    }
    if (tracks.isEmpty() && autoRepeat == null) return null
    return ParsedTemplate(tracks, autoRepeat, autoIndex)
}

private fun trackMin(t: Track, basis: Double): Double = when (t) {
    is Track.Px -> t.value
    is Track.Pct -> if (basis.isFinite()) (t.value / 100) * basis else 0.0
    is Track.MinMax -> trackMin(t.min, basis)
    else -> 0.0
}

private class Placement(val start: Int?, val span: Int)

private val SPAN = Regex("span\\s+(\\d+)")
private val INT = Regex("^-?\\d+$")

private fun parsePlacement(raw: Any?): Placement {
    if (!truthy(raw)) return Placement(null, 1)
    val parts = jsString(raw).split("/").map { it.trim().lowercase() }
    var start: Int? = null
    var span = 1
    val first = parts.getOrNull(0) ?: ""
    val m1 = SPAN.find(first)
    if (m1 != null) span = max(1, jsParseInt(m1.groupValues[1]) ?: 1)
    else if (INT.matches(first)) start = jsParseInt(first)
    if (parts.size > 1) {
        val second = parts[1]
        val m2 = SPAN.find(second)
        if (m2 != null) span = max(1, jsParseInt(m2.groupValues[1]) ?: 1)
        else if (INT.matches(second) && start != null) span = max(1, (jsParseInt(second) ?: 0) - start)
    }
    return Placement(if (start != null && start > 0) start - 1 else null, span)
}

/**
 * props: { columns, rows, autoRows, columnGap, rowGap, alignItems, justifyItems }
 */
class RenderGrid : RenderObject() {
    private class Item(val ro: RenderObject, val col: Int, val row: Int, val colSpan: Int, val rowSpan: Int)
    private class FrTrack(val i: Int, val t: Track.MinMax?, val base: Track)

    private fun wrapFallback(c: Constraints, colGap: Double, rowGap: Double) {
        // Flutter: an unbounded grid becomes a plain Wrap.
        var x = 0.0
        var y = 0.0
        var rowH = 0.0
        var maxW = 0.0
        val limit = c.maxWidth
        for (ch in children) {
            ch.layout(Constraints(0.0, limit, 0.0, INF))
            if (x > 0 && x + ch.size.width > limit) {
                x = 0.0
                y += rowH + rowGap
                rowH = 0.0
            }
            ch.offset = Vec(x, y)
            x += ch.size.width + colGap
            rowH = max(rowH, ch.size.height)
            maxW = max(maxW, x - colGap)
        }
        size = constrain(c, Size(maxW, if (children.isNotEmpty()) y + rowH else 0.0))
    }

    override fun performLayout(c: Constraints) {
        val colGap = props.d("columnGap") ?: 0.0
        val rowGap = props.d("rowGap") ?: 0.0
        val template = parseTemplate(props.s("columns"))
        val children = this.children
        val W = c.maxWidth
        if (template == null || !W.isFinite()) {
            wrapFallback(c, colGap, rowGap)
            return
        }

        // ---- column tracks ----
        val tracks: List<Track>
        val auto = template.autoRepeat
        if (auto != null) {
            val fixed = template.tracks.sumOf { trackMin(it, W) } + template.tracks.size * colGap
            val unit = auto.tracks
            val unitMin = unit.sumOf { t -> max(trackMin(t, W), if (t is Track.Fr || t is Track.Auto) 1.0 else 0.0) }
            val unitGaps = unit.size * colGap
            var reps = max(1.0, floor((W - fixed + colGap) / (unitMin + unitGaps))).toInt()
            // Flutter caps the count at the number of items (so few items stretch).
            if (template.tracks.isEmpty() && unit.size == 1) reps = min(reps, max(1, children.size))
            val out = ArrayList(template.tracks.subList(0, min(template.autoIndex, template.tracks.size)))
            for (i in 0 until reps) {
                // An auto-fill `minmax(min, X)` behaves like `minmax(min, 1fr)` once the count is fixed.
                out.addAll(unit.map { t -> if (t is Track.MinMax) Track.MinMax(t.min, Track.Fr(1.0)) else t })
            }
            out.addAll(template.tracks.subList(min(template.autoIndex, template.tracks.size), template.tracks.size))
            tracks = out
        } else tracks = template.tracks
        val colCount = max(1, tracks.size)

        // ---- placement ----
        val items = ArrayList<Item>()
        val occupied = HashSet<String>()
        fun isFree(row: Int, col: Int, colSpan: Int, rowSpan: Int): Boolean {
            if (col + colSpan > colCount) return false
            for (r in row until row + rowSpan) for (k in col until col + colSpan) if ("$r:$k" in occupied) return false
            return true
        }
        fun occupy(row: Int, col: Int, colSpan: Int, rowSpan: Int) {
            for (r in row until row + rowSpan) for (k in col until col + colSpan) occupied.add("$r:$k")
        }
        var cursorRow = 0
        var cursorCol = 0
        for (ch in children) {
            val pd: Map<String, Any?> = if (ch is RenderGridItem) ch.props else emptyMap()
            val colP = parsePlacement(pd["column"])
            val rowP = parsePlacement(pd["row"])
            val colSpan = min(colCount, colP.span)
            val rowSpan = rowP.span
            var row = rowP.start ?: -1
            var col = colP.start ?: -1
            if (col >= colCount) col = colCount - colSpan
            if (row >= 0 && col >= 0) {
                // fully explicit
            } else if (row >= 0) {
                col = 0
                while (!isFree(row, col, colSpan, rowSpan)) {
                    col++
                    if (col + colSpan > colCount) {
                        col = 0
                        row++
                    }
                }
            } else if (col >= 0) {
                row = 0
                while (!isFree(row, col, colSpan, rowSpan)) row++
            } else {
                row = cursorRow
                col = cursorCol
                while (!isFree(row, col, colSpan, rowSpan)) {
                    col++
                    if (col + colSpan > colCount) {
                        col = 0
                        row++
                    }
                }
                cursorRow = row
                cursorCol = col + colSpan
                if (cursorCol >= colCount) {
                    cursorCol = 0
                    cursorRow++
                }
            }
            occupy(row, col, colSpan, rowSpan)
            items.add(Item(ch, col, row, colSpan, rowSpan))
        }

        // ---- column sizing ----
        val widths = DoubleArray(colCount)
        var fixedTotal = 0.0
        var frTotal = 0.0
        for (i in 0 until colCount) {
            val t = tracks.getOrNull(i) ?: Track.Fr(1.0)
            val base = if (t is Track.MinMax) t.max else t
            if (base is Track.Fr) frTotal += base.value
            else if (base is Track.Auto) {
                var m = trackMin(t, W)
                for (it in items) if (it.col == i && it.colSpan == 1) m = max(m, it.ro.maxIntrinsicWidth(INF))
                widths[i] = m
                fixedTotal += m
            } else {
                widths[i] = max(trackMin(t, W), trackMin(base, W))
                fixedTotal += widths[i]
            }
        }
        val gaps = (colCount - 1) * colGap
        var free = W - fixedTotal - gaps
        if (frTotal > 0) {
            // Distribute free space to fr tracks, respecting minmax minimums.
            val frTracks = tracks.mapIndexed { i, t -> FrTrack(i, t as? Track.MinMax, if (t is Track.MinMax) t.max else t) }.filter { it.base is Track.Fr }
            var remaining = max(0.0, free)
            var pool = frTracks.toList()
            var iter = 0
            while (iter < 4 && pool.isNotEmpty()) {
                val totalFr = pool.sumOf { (it.base as Track.Fr).value }
                val perFr = remaining / totalFr
                val stuck = pool.filter { x -> x.t != null && trackMin(x.t.min, W) > perFr * (x.base as Track.Fr).value }
                if (stuck.isEmpty()) {
                    for (x in pool) widths[x.i] = perFr * (x.base as Track.Fr).value
                    pool = emptyList()
                    break
                }
                for (x in stuck) {
                    widths[x.i] = trackMin(x.t!!.min, W)
                    remaining -= widths[x.i]
                }
                pool = pool.filter { x -> stuck.none { it === x } }
                iter++
            }
            free = 0.0
        } else if (free < 0) {
            // Over-constrained auto columns shrink proportionally (never below 0).
            val autoIdx = tracks.indices.filter { tracks[it] is Track.Auto }
            val autoSum = autoIdx.sumOf { widths[it] }
            if (autoSum > 0) for (i in autoIdx) widths[i] = max(0.0, widths[i] + (free * widths[i]) / autoSum)
        }

        val colX = DoubleArray(colCount)
        var acc = 0.0
        for (i in 0 until colCount) {
            colX[i] = acc
            acc += widths[i] + colGap
        }
        fun spanWidth(col: Int, span: Int): Double {
            var s = 0.0
            for (k in col until min(colCount, col + span)) s += widths[k]
            return s + (min(span, colCount - col) - 1) * colGap
        }

        // ---- rows ----
        val rowCount = items.fold(0) { m, it -> max(m, it.row + it.rowSpan) }
        val rowTemplate = parseTemplate(props.s("rows"))
        val autoRowTrack = if (truthy(props["autoRows"])) parseTrack(jsString(props["autoRows"])) else null
        val heights = DoubleArray(rowCount)
        val rowFixed = BooleanArray(rowCount)
        for (r in 0 until rowCount) {
            val t = rowTemplate?.tracks?.getOrNull(r) ?: autoRowTrack
            if (t != null && (t is Track.Px || (t is Track.MinMax && t.min is Track.Px))) {
                heights[r] = trackMin(t, c.maxHeight)
                rowFixed[r] = t is Track.Px
            }
        }
        val stretch = (props.s("alignItems") ?: "start") == "stretch"
        for (it in items) {
            val width = spanWidth(it.col, it.colSpan)
            it.ro.layout(Constraints(width, width, 0.0, INF))
            if (it.rowSpan == 1 && !rowFixed[it.row]) heights[it.row] = max(heights[it.row], it.ro.size.height)
        }
        // Spanning items grow their last row if needed.
        for (it in items) {
            if (it.rowSpan == 1) continue
            var h = 0.0
            for (r in it.row until it.row + it.rowSpan) h += heights[r]
            h += (it.rowSpan - 1) * rowGap
            val last = it.row + it.rowSpan - 1
            if (it.ro.size.height > h && !rowFixed[last]) heights[last] += it.ro.size.height - h
        }
        val rowY = DoubleArray(rowCount)
        var y = 0.0
        for (r in 0 until rowCount) {
            rowY[r] = y
            y += heights[r] + rowGap
        }
        val totalH = if (rowCount > 0) y - rowGap else 0.0

        for (it in items) {
            var cellH = 0.0
            for (r in it.row until it.row + it.rowSpan) cellH += heights[r]
            cellH += (it.rowSpan - 1) * rowGap
            if (stretch || rowFixed[it.row]) {
                val width = spanWidth(it.col, it.colSpan)
                it.ro.layout(Constraints(width, width, if (stretch) cellH else 0.0, if (stretch) cellH else max(cellH, 0.0)))
            }
            var dy = 0.0
            val align = it.ro.props.s("alignSelf") ?: props.s("alignItems")
            if (align == "center") dy = (cellH - it.ro.size.height) / 2
            else if (align == "end" || align == "flex-end") dy = cellH - it.ro.size.height
            it.ro.offset = Vec(colX[it.col], rowY[it.row] + dy)
        }
        size = constrain(c, Size(W, totalH))
    }

    override fun computeMaxIntrinsicWidth(height: Double): Double {
        var m = 0.0
        for (ch in children) m = max(m, ch.maxIntrinsicWidth(height))
        val template = parseTemplate(props.s("columns"))
        val cols = template?.tracks?.size?.takeIf { it != 0 } ?: 1
        return m * cols + (cols - 1) * (props.d("columnGap") ?: 0.0)
    }

    override fun computeMinIntrinsicWidth(height: Double): Double {
        var m = 0.0
        for (ch in children) m = max(m, ch.minIntrinsicWidth(height))
        return m
    }
}
