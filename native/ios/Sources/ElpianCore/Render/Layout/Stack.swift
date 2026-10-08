import Foundation

/**
 * RenderStack + Positioned parent data — Flutter's `Stack`
 * (render/layout/stack.ts).
 *
 * Non-positioned children are laid out with loose (or expanded) constraints
 * and the stack sizes to the largest; positioned children are placed by their
 * top/right/bottom/left/width/height against the stack's box. Children paint
 * in order, so z-order is the child order (lowering sorts by `z-index`).
 */

/** props: { top, right, bottom, left, width, height } */
open class RenderPositioned: RenderObject {
    public var isPositioned: Bool {
        let p = props
        return p["top"] != nil || p["right"] != nil || p["bottom"] != nil || p["left"] != nil || p["width"] != nil || p["height"] != nil
    }

    open override func performLayout(_ c: Constraints) {
        if let child = child {
            child.layout(c)
            child.offset = .zero
            size = child.size
        } else {
            size = constrain(c, Size(width: props.d("width") ?? 0, height: props.d("height") ?? 0))
        }
    }
}

private func isPositionedChild(_ ch: RenderObject) -> Bool {
    (ch as? RenderPositioned)?.isPositioned == true
}

/** props: { alignment, fit: 'loose'|'expand'|'passthrough', clip } */
open class RenderStack: RenderObject {
    open override func performLayout(_ c: Constraints) {
        let alignment = props.alignment("alignment", .topLeft)
        let fit = props.s("fit") ?? "loose"
        let nonPositioned: Constraints
        switch fit {
        case "expand":
            let b = biggest(c)
            nonPositioned = tight(b.width, b.height)
        case "passthrough":
            nonPositioned = c
        default:
            nonPositioned = loose(c)
        }
        var hasNonPositioned = false
        var width = c.minWidth
        var height = c.minHeight
        for ch in children {
            if isPositionedChild(ch) { continue }
            hasNonPositioned = true
            ch.layout(nonPositioned)
            width = max(width, ch.size.width)
            height = max(height, ch.size.height)
        }
        size = hasNonPositioned ? constrain(c, Size(width: width, height: height)) : biggest(c)
        if !size.width.isFinite || !size.height.isFinite { size = constrain(c, smallest(c)) }
        for ch in children {
            if let positioned = ch as? RenderPositioned, positioned.isPositioned {
                layoutPositioned(positioned, alignment)
            } else {
                ch.offset = alignOffset(alignment, size, ch.size)
            }
        }
    }

    private func layoutPositioned(_ child: RenderPositioned, _ alignment: Alignment) {
        let p = child.props
        let left = p.d("left")
        let right = p.d("right")
        let top = p.d("top")
        let bottom = p.d("bottom")
        let pw = p.d("width")
        let ph = p.d("height")
        let W = size.width
        let H = size.height
        var c = Constraints(minWidth: 0, maxWidth: INF, minHeight: 0, maxHeight: INF)
        if let left = left, let right = right {
            let w = max(0, W - right - left)
            c.minWidth = w
            c.maxWidth = w
        } else if let pw = pw {
            c.minWidth = pw
            c.maxWidth = pw
        }
        if let top = top, let bottom = bottom {
            let h = max(0, H - bottom - top)
            c.minHeight = h
            c.maxHeight = h
        } else if let ph = ph {
            c.minHeight = ph
            c.maxHeight = ph
        }
        child.layout(c)
        let x: Double
        if let left = left {
            x = left
        } else if let right = right {
            x = W - right - child.size.width
        } else {
            x = ((W - child.size.width) / 2) * (1 + alignment.x)
        }
        let y: Double
        if let top = top {
            y = top
        } else if let bottom = bottom {
            y = H - bottom - child.size.height
        } else {
            y = ((H - child.size.height) / 2) * (1 + alignment.y)
        }
        child.offset = Vec(x: x, y: y)
    }

    /** A stack that clips needs its own view; otherwise it is layout-only. */
    open override func viewKind() -> ViewKind? { jsTruthy(props["clip"]) ? .view : nil }

    open override func viewProps() -> ViewProps { ViewProps([("clip", jsTruthy(props["clip"]))]) }

    open override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        var m = 0.0
        for ch in children where !isPositionedChild(ch) { m = max(m, ch.minIntrinsicWidth(height)) }
        return m
    }
    open override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        var m = 0.0
        for ch in children where !isPositionedChild(ch) { m = max(m, ch.maxIntrinsicWidth(height)) }
        return m
    }
    open override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        var m = 0.0
        for ch in children where !isPositionedChild(ch) { m = max(m, ch.minIntrinsicHeight(width)) }
        return m
    }
    open override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        var m = 0.0
        for ch in children where !isPositionedChild(ch) { m = max(m, ch.maxIntrinsicHeight(width)) }
        return m
    }
}
