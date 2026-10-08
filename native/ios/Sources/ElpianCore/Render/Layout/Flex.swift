import Foundation

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
open class RenderFlexible: RenderObject {
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

private struct FlexInfo {
    let flex: Double
    /** `tight` or `loose`. */
    let fit: String
    let shrink: Double
    let alignSelf: String?
    /** CSS flex-basis in px (when it differs from the content size). */
    let basis: Double?
}

private func flexInfo(_ child: RenderObject) -> FlexInfo {
    if child is RenderFlexible {
        let p = child.props
        let flex = p.d("flex")
        return FlexInfo(
            flex: flex != nil && flex! > 0 ? flex! : 0,
            fit: p.s("fit") == "loose" ? "loose" : "tight",
            shrink: p.d("shrink") ?? 1,
            alignSelf: p.s("alignSelf"),
            basis: p.d("basis")
        )
    }
    return FlexInfo(flex: 0, fit: "tight", shrink: 1, alignSelf: nil, basis: nil)
}

public func mainAxisAlignmentFromCss(_ value: String?) -> String {
    switch (value ?? "").lowercased() {
    case "center": return "center"
    case "flex-end", "end", "right": return "end"
    case "space-between": return "spaceBetween"
    case "space-around": return "spaceAround"
    case "space-evenly": return "spaceEvenly"
    default: return "start"
    }
}

public func crossAxisAlignmentFromCss(_ value: String?) -> String {
    switch (value ?? "").lowercased() {
    case "center": return "center"
    case "flex-end", "end": return "end"
    case "stretch": return "stretch"
    case "baseline", "first baseline": return "baseline"
    default: return "start"
    }
}

/**
 * props: {
 *   direction: 'row' | 'column', reverse?: boolean,
 *   mainAxisAlignment, crossAxisAlignment, mainAxisSize: 'max' | 'min',
 *   verticalDirection?: 'down' | 'up', gap?: number, shrink?: boolean
 * }
 */
open class RenderFlex: RenderObject {
    private var overflow = 0.0

    private var horizontal: Bool { props.s("direction") != "column" }

    private func main(_ s: Size) -> Double { horizontal ? s.width : s.height }
    private func cross(_ s: Size) -> Double { horizontal ? s.height : s.width }

    /** Constraints for a child with the given main extent bounds. */
    private func childConstraints(_ minMain: Double, _ maxMain: Double, _ c: Constraints, _ align: String) -> Constraints {
        let stretch = align == "stretch"
        if horizontal {
            let maxCross = c.maxHeight
            return Constraints(minWidth: minMain, maxWidth: maxMain, minHeight: stretch && maxCross.isFinite ? maxCross : 0, maxHeight: maxCross)
        }
        let maxCross = c.maxWidth
        return Constraints(minWidth: stretch && maxCross.isFinite ? maxCross : 0, maxWidth: maxCross, minHeight: minMain, maxHeight: maxMain)
    }

    open override func performLayout(_ c: Constraints) {
        let horizontal = self.horizontal
        let gap = props.d("gap") ?? 0
        let crossAlign = props.s("crossAxisAlignment") ?? "start"
        let maxMain = horizontal ? c.maxWidth : c.maxHeight
        let canFlex = maxMain.isFinite
        let children = self.children
        let infos = children.map(flexInfo)
        let gaps = Double(max(0, children.count - 1)) * gap

        var totalFlex = 0.0
        var allocated = 0.0
        let isFlex = infos.map { canFlex && $0.flex > 0 }
        for i in children.indices {
            let ch = children[i]
            let info = infos[i]
            if isFlex[i] {
                totalFlex += info.flex
                continue
            }
            let align = info.alignSelf ?? crossAlign
            if let basis = info.basis {
                ch.layout(childConstraints(basis, basis, c, align))
            } else {
                ch.layout(childConstraints(0, INF, c, align))
            }
            allocated += main(ch.size)
        }

        // CSS shrink: inflexible content overflowing a bounded main axis.
        if props.b("shrink") && canFlex && allocated + gaps > maxMain + 0.01 {
            shrinkChildren(c, infos, isFlex, maxMain - gaps)
            allocated = 0
            for i in children.indices where !isFlex[i] { allocated += main(children[i].size) }
        }

        let freeSpace = max(0, (canFlex ? maxMain : 0) - allocated - gaps)
        if totalFlex > 0 {
            let perFlex = freeSpace / totalFlex
            var lastFlexIndex = -1
            for i in children.indices where isFlex[i] { lastFlexIndex = i }
            var used = 0.0
            for i in children.indices {
                if !isFlex[i] { continue }
                let info = infos[i]
                let maxChild = i == lastFlexIndex ? max(0, freeSpace - used) : perFlex * info.flex
                let minChild = info.fit == "tight" ? maxChild : 0
                let align = info.alignSelf ?? crossAlign
                children[i].layout(childConstraints(minChild, maxChild, c, align))
                let extent = main(children[i].size)
                used += extent
                allocated += extent
            }
        }

        let mainSizeMax = (props.s("mainAxisSize") ?? "max") == "max"
        let allocatedWithGaps = allocated + gaps
        let idealMain = mainSizeMax && canFlex ? maxMain : allocatedWithGaps

        var crossSize = 0.0
        var maxBaseline = 0.0
        var maxBelowBaseline = 0.0
        var baselines: [Double?] = []
        for i in children.indices {
            let ch = children[i]
            let align = infos[i].alignSelf ?? crossAlign
            if align == "baseline" && horizontal {
                let b = ch.baseline() ?? ch.size.height
                baselines.append(b)
                maxBaseline = max(maxBaseline, b)
                maxBelowBaseline = max(maxBelowBaseline, ch.size.height - b)
            } else {
                baselines.append(nil)
                crossSize = max(crossSize, cross(ch.size))
            }
        }
        crossSize = max(crossSize, maxBaseline + maxBelowBaseline)
        if crossAlign == "stretch" {
            let maxCross = horizontal ? c.maxHeight : c.maxWidth
            if maxCross.isFinite { crossSize = max(crossSize, maxCross) }
        }

        let size = constrain(c, horizontal ? Size(width: idealMain, height: crossSize) : Size(width: crossSize, height: idealMain))
        self.size = size
        let actualMain = main(size)
        let actualCross = cross(size)
        overflow = max(0, allocatedWithGaps - actualMain)

        let remaining = max(0, actualMain - allocatedWithGaps)
        let n = children.count
        var leading = 0.0
        var between = 0.0
        switch props.s("mainAxisAlignment") ?? "start" {
        case "end":
            leading = remaining
        case "center":
            leading = remaining / 2
        case "spaceBetween":
            between = n > 1 ? remaining / Double(n - 1) : 0
        case "spaceAround":
            between = n > 0 ? remaining / Double(n) : 0
            leading = between / 2
        case "spaceEvenly":
            between = n > 0 ? remaining / Double(n + 1) : 0
            leading = between
        default:
            break
        }

        // Reverse order for row-reverse / column-reverse / verticalDirection up
        // (the cross position needs nothing extra: the order is flipped here).
        let flip = props.b("reverse") || (!horizontal && props.s("verticalDirection") == "up")
        var pos = leading
        for k in 0..<n {
            let i = flip ? n - 1 - k : k
            let ch = children[i]
            let align = infos[i].alignSelf ?? crossAlign
            let childCross = cross(ch.size)
            let crossPos: Double
            switch align {
            case "end": crossPos = actualCross - childCross
            case "center": crossPos = (actualCross - childCross) / 2
            case "baseline": crossPos = horizontal ? maxBaseline - (baselines[i] ?? 0) : 0
            default: crossPos = 0
            }
            ch.offset = horizontal ? Vec(x: pos, y: crossPos) : Vec(x: crossPos, y: pos)
            pos += main(ch.size) + gap + between
        }
    }

    /** CSS flex-shrink: reduce inflexible children so they fit [available]. */
    private func shrinkChildren(_ c: Constraints, _ infos: [FlexInfo], _ isFlex: [Bool], _ available: Double) {
        let crossAlign = props.s("crossAxisAlignment") ?? "start"
        let children = self.children
        let base = children.map { main($0.size) }
        let minContent: [Double] = children.enumerated().map { i, ch in
            if isFlex[i] { return 0 }
            return horizontal ? ch.minIntrinsicWidth(INF) : ch.minIntrinsicHeight(c.maxWidth)
        }
        var frozen = children.indices.map { isFlex[$0] || infos[$0].shrink <= 0 }
        var target = base
        // Iteratively shrink, freezing items that hit their min-content size.
        for _ in 0..<8 {
            var used = 0.0
            var weighted = 0.0
            for i in children.indices {
                if isFlex[i] { continue }
                used += target[i]
                if !frozen[i] { weighted += infos[i].shrink * base[i] }
            }
            let over = used - available
            if over <= 0.01 || weighted <= 0 { break }
            var clamped = false
            for i in children.indices {
                if frozen[i] { continue }
                let share = (over * infos[i].shrink * base[i]) / weighted
                let next = target[i] - share
                if next < minContent[i] {
                    target[i] = minContent[i]
                    frozen[i] = true
                    clamped = true
                } else {
                    target[i] = next
                }
            }
            if !clamped { break }
        }
        for i in children.indices {
            if isFlex[i] || abs(target[i] - base[i]) < 0.01 { continue }
            let align = infos[i].alignSelf ?? crossAlign
            let extent = max(0, target[i])
            children[i].layout(childConstraints(extent, extent, c, align))
        }
    }

    public var overflowExtent: Double { overflow }

    open override func baseline() -> Double? {
        // Flutter: a Row's baseline is that of its first child that has one.
        for ch in children {
            if let b = ch.baseline() { return b + ch.offset.y }
        }
        return nil
    }

    open override func computeMinIntrinsicWidth(_ height: Double) -> Double { intrinsicMain(true, true, height) }
    open override func computeMaxIntrinsicWidth(_ height: Double) -> Double { intrinsicMain(false, true, height) }
    open override func computeMinIntrinsicHeight(_ width: Double) -> Double { intrinsicMain(true, false, width) }
    open override func computeMaxIntrinsicHeight(_ width: Double) -> Double { intrinsicMain(false, false, width) }

    private func intrinsicMain(_ min: Bool, _ widthAxis: Bool, _ extent: Double) -> Double {
        let gap = props.d("gap") ?? 0
        let gaps = Double(max(0, children.count - 1)) * gap
        func get(_ ch: RenderObject) -> Double {
            if widthAxis { return min ? ch.minIntrinsicWidth(extent) : ch.maxIntrinsicWidth(extent) }
            return min ? ch.minIntrinsicHeight(extent) : ch.maxIntrinsicHeight(extent)
        }
        if horizontal == widthAxis {
            // Along the main axis: sum (flex children scaled to the largest per-flex).
            var inflexible = 0.0
            var maxPerFlex = 0.0
            var totalFlex = 0.0
            for ch in children {
                let info = flexInfo(ch)
                let v = get(ch)
                if info.flex > 0 {
                    totalFlex += info.flex
                    maxPerFlex = max(maxPerFlex, v / info.flex)
                } else {
                    inflexible += v
                }
            }
            return inflexible + maxPerFlex * totalFlex + gaps
        }
        // Across: the largest child.
        var m = 0.0
        for ch in children { m = max(m, get(ch)) }
        return m
    }
}
