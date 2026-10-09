import Foundation

/**
 * RenderWrap — Flutter's `Wrap` (render/layout/wrap.ts): children flow along
 * the main axis and wrap into runs; `spacing` separates children in a run,
 * `runSpacing` separates runs; `alignment` places children within a run,
 * `runAlignment` places runs within the box, `crossAxisAlignment` aligns
 * children within their run.
 *
 * Wrap alignments: start, end, center, spaceBetween, spaceAround, spaceEvenly.
 */
public func wrapAlignmentFromCss(_ value: String?) -> String {
    switch (value ?? "").lowercased() {
    case "center": return "center"
    case "flex-end", "end": return "end"
    case "space-between": return "spaceBetween"
    case "space-around": return "spaceAround"
    case "space-evenly": return "spaceEvenly"
    default: return "start"
    }
}

/** Leading space and space between items for [alignment]: (leading, between). */
private func distribute(_ alignment: String, _ free: Double, _ count: Int) -> (Double, Double) {
    switch alignment {
    case "end": return (free, 0)
    case "center": return (free / 2, 0)
    case "spaceBetween": return (0, count > 1 ? free / Double(count - 1) : 0)
    case "spaceAround":
        let b = count > 0 ? free / Double(count) : 0
        return (b / 2, b)
    case "spaceEvenly":
        let b = count > 0 ? free / Double(count + 1) : 0
        return (b, b)
    default: return (0, 0)
    }
}

/**
 * props: { direction: 'horizontal'|'vertical', spacing, runSpacing, alignment,
 *          runAlignment, crossAxisAlignment: 'start'|'end'|'center',
 *          verticalDirection: 'down'|'up', reverse }
 */
open class RenderWrap: RenderObject {
    private final class Run {
        var children: [RenderObject] = []
        var main = 0.0
        var cross = 0.0
    }

    open override func performLayout(_ c: Constraints) {
        let horizontal = props.s("direction") != "vertical"
        let spacing = props.d("spacing") ?? 0
        let runSpacing = props.d("runSpacing") ?? 0
        let mainLimit = horizontal ? c.maxWidth : c.maxHeight
        let childC = horizontal
            ? Constraints(minWidth: 0, maxWidth: c.maxWidth, minHeight: 0, maxHeight: INF)
            : Constraints(minWidth: 0, maxWidth: INF, minHeight: 0, maxHeight: c.maxHeight)
        func main(_ s: Size) -> Double { horizontal ? s.width : s.height }
        func cross(_ s: Size) -> Double { horizontal ? s.height : s.width }

        var runs: [Run] = []
        var run = Run()
        for ch in children {
            ch.layout(childC)
            let cm = main(ch.size)
            let extra = !run.children.isEmpty ? spacing : 0
            if !run.children.isEmpty && run.main + extra + cm > mainLimit + 0.01 {
                runs.append(run)
                run = Run()
            }
            run.main += (!run.children.isEmpty ? spacing : 0) + cm
            run.cross = max(run.cross, cross(ch.size))
            run.children.append(ch)
        }
        if !run.children.isEmpty { runs.append(run) }

        var contentMain = 0.0
        var contentCross = 0.0
        for r in runs {
            contentMain = max(contentMain, r.main)
            contentCross += r.cross
        }
        contentCross += Double(max(0, runs.count - 1)) * runSpacing

        size = constrain(c, horizontal ? Size(width: contentMain, height: contentCross) : Size(width: contentCross, height: contentMain))
        let boxMain = main(size)
        let boxCross = cross(size)

        let (runLeading, runBetween) = distribute(props.s("runAlignment") ?? "start", max(0, boxCross - contentCross), runs.count)
        let flipCross = props.s("verticalDirection") == "up"
        var crossPos = runLeading
        let runOrder = flipCross ? runs.reversed() : runs
        for r in runOrder {
            let (leading, between) = distribute(props.s("alignment") ?? "start", max(0, boxMain - r.main), r.children.count)
            var mainPos = leading
            let ordered = props.b("reverse") ? r.children.reversed() : r.children
            for ch in ordered {
                let childCross: Double
                switch props.s("crossAxisAlignment") ?? "start" {
                case "end": childCross = r.cross - cross(ch.size)
                case "center": childCross = (r.cross - cross(ch.size)) / 2
                default: childCross = 0
                }
                ch.offset = horizontal ? Vec(x: mainPos, y: crossPos + childCross) : Vec(x: crossPos + childCross, y: mainPos)
                mainPos += main(ch.size) + spacing + between
            }
            crossPos += r.cross + runSpacing + runBetween
        }
    }

    open override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        if props.s("direction") == "vertical" { return sum(height) }
        var m = 0.0
        for ch in children { m = max(m, ch.minIntrinsicWidth(INF)) }
        return m
    }

    open override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        if props.s("direction") == "vertical" {
            var m = 0.0
            for ch in children { m = max(m, ch.maxIntrinsicWidth(INF)) }
            return m
        }
        return sum(height)
    }

    open override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        // Lay out at the given width to know the run structure.
        if !width.isFinite { return computeMaxIntrinsicHeight(width) }
        let saved = size
        layout(Constraints(minWidth: 0, maxWidth: width, minHeight: 0, maxHeight: INF))
        let h = size.height
        size = saved
        needsLayout = true
        return h
    }

    open override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        computeMinIntrinsicHeight(width.isFinite ? width : computeMaxIntrinsicWidth(INF))
    }

    /** Sum of the children's max-intrinsic widths plus spacing. */
    private func sum(_ extent: Double) -> Double {
        let spacing = props.d("spacing") ?? 0
        var total = 0.0
        for ch in children { total += ch.maxIntrinsicWidth(extent) }
        return total + Double(max(0, children.count - 1)) * spacing
    }
}
