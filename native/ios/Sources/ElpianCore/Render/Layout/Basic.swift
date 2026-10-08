import Foundation

/**
 * Single-child layout objects — ports of Flutter's RenderPadding,
 * RenderConstrainedBox, RenderPositionedBox (Align/Center), RenderAspectRatio,
 * RenderFractionallySizedOverflowBox, RenderLimitedBox,
 * RenderConstrainedOverflowBox, RenderFittedBox, RenderBaseline,
 * RenderRotatedBox, RenderIntrinsicWidth/Height, RenderOffstage and
 * RenderIndexedStack (render/layout/basic.ts).
 */
public func alignOffset(_ alignment: Alignment, _ outer: Size, _ inner: Size) -> Vec {
    Vec(
        x: (outer.width - inner.width) / 2 * (1 + alignment.x),
        y: (outer.height - inner.height) / 2 * (1 + alignment.y)
    )
}

public extension JSONObject {
    /** An [Alignment] prop (`props.alignment ?? fallback`). */
    func alignment(_ key: String = "alignment", _ fallback: Alignment = .center) -> Alignment {
        if let a = self[key] as? Alignment { return a }
        if self[key] != nil, let a = CSSParser.parseAlignment(self[key]) { return a }
        return fallback
    }
}

// ----------------------------------------------------------------------------
// Padding
// ----------------------------------------------------------------------------

/** props: { padding: EdgeInsets, percent: SidePercents } */
open class RenderPadding: RenderObject {
    /** Padding with percentage sides resolved against the incoming max width (CSS). */
    open func resolvedPadding(_ c: Constraints?) -> EdgeInsets {
        let p = (props["padding"] as? EdgeInsets) ?? CSSParser.parseEdgeInsets(props["padding"]) ?? .zero
        guard let pct = props["percent"] as? SidePercents else { return p }
        let basis = c != nil && c!.maxWidth.isFinite ? c!.maxWidth : 0
        func side(_ v: Percent?, _ fallback: Double) -> Double { v.map { $0.pct / 100 * basis } ?? fallback }
        return EdgeInsets(top: side(pct.top, p.top), right: side(pct.right, p.right), bottom: side(pct.bottom, p.bottom), left: side(pct.left, p.left))
    }

    open override func performLayout(_ c: Constraints) {
        let p = resolvedPadding(c)
        let h = max(0, p.left + p.right)
        let v = max(0, p.top + p.bottom)
        guard let child = child else {
            size = constrain(c, Size(width: h, height: v))
            return
        }
        child.layout(deflate(c, h, v))
        child.offset = Vec(x: p.left, y: p.top)
        size = constrain(c, Size(width: child.size.width + h, height: child.size.height + v))
    }

    open override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        let p = resolvedPadding(nil)
        let h = p.left + p.right
        let v = p.top + p.bottom
        return (child?.minIntrinsicWidth(max(0, height - v)) ?? 0) + h
    }
    open override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        let p = resolvedPadding(nil)
        return (child?.maxIntrinsicWidth(max(0, height - p.top - p.bottom)) ?? 0) + p.left + p.right
    }
    open override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        let p = resolvedPadding(nil)
        return (child?.minIntrinsicHeight(max(0, width - p.left - p.right)) ?? 0) + p.top + p.bottom
    }
    open override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        let p = resolvedPadding(nil)
        return (child?.maxIntrinsicHeight(max(0, width - p.left - p.right)) ?? 0) + p.top + p.bottom
    }
}

// ----------------------------------------------------------------------------
// ConstrainedBox / SizedBox
// ----------------------------------------------------------------------------

/**
 * props: { minWidth, maxWidth, minHeight, maxHeight, width, height }
 * `width`/`height` produce tight constraints on that axis (SizedBox); the
 * min/max values are additional constraints (ConstrainedBox).
 */
open class RenderConstrainedBox: RenderObject {
    public func additional() -> Constraints {
        let p = props
        var c = Constraints(
            minWidth: p.d("minWidth") ?? 0,
            maxWidth: p.d("maxWidth") ?? INF,
            minHeight: p.d("minHeight") ?? 0,
            maxHeight: p.d("maxHeight") ?? INF
        )
        if let w = p.d("width") {
            c.minWidth = w
            c.maxWidth = w
        }
        if let h = p.d("height") {
            c.minHeight = h
            c.maxHeight = h
        }
        if c.maxWidth < c.minWidth { c.maxWidth = c.minWidth }
        if c.maxHeight < c.minHeight { c.maxHeight = c.minHeight }
        return c
    }

    open override func performLayout(_ c: Constraints) {
        let inner = enforce(additional(), c)
        if let child = child {
            child.layout(inner)
            child.offset = .zero
            size = child.size
        } else {
            size = constrain(inner, .zero)
        }
    }

    private func clampW(_ v: Double) -> Double {
        let a = additional()
        return clampN(v, a.minWidth, a.maxWidth)
    }
    private func clampH(_ v: Double) -> Double {
        let a = additional()
        return clampN(v, a.minHeight, a.maxHeight)
    }
    open override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        let a = additional()
        if a.minWidth >= a.maxWidth && a.minWidth.isFinite { return a.minWidth }
        return clampW(child?.minIntrinsicWidth(height) ?? 0)
    }
    open override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        let a = additional()
        if a.minWidth >= a.maxWidth && a.minWidth.isFinite { return a.minWidth }
        return clampW(child?.maxIntrinsicWidth(height) ?? 0)
    }
    open override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        let a = additional()
        if a.minHeight >= a.maxHeight && a.minHeight.isFinite { return a.minHeight }
        return clampH(child?.minIntrinsicHeight(width) ?? 0)
    }
    open override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        let a = additional()
        if a.minHeight >= a.maxHeight && a.minHeight.isFinite { return a.minHeight }
        return clampH(child?.maxIntrinsicHeight(width) ?? 0)
    }
}

// ----------------------------------------------------------------------------
// Align / Center
// ----------------------------------------------------------------------------

/** props: { alignment, widthFactor, heightFactor } */
open class RenderAlign: RenderObject {
    open override func performLayout(_ c: Constraints) {
        let alignment = props.alignment("alignment", .center)
        let wf = props.d("widthFactor")
        let hf = props.d("heightFactor")
        let shrinkW = wf != nil || !c.maxWidth.isFinite
        let shrinkH = hf != nil || !c.maxHeight.isFinite
        if let child = child {
            child.layout(loose(c))
            size = constrain(c, Size(
                width: shrinkW ? child.size.width * (wf ?? 1) : INF,
                height: shrinkH ? child.size.height * (hf ?? 1) : INF
            ))
            child.offset = alignOffset(alignment, size, child.size)
        } else {
            size = constrain(c, Size(width: shrinkW ? 0 : INF, height: shrinkH ? 0 : INF))
        }
    }

    open override func computeMinIntrinsicWidth(_ h: Double) -> Double {
        (child?.minIntrinsicWidth(h) ?? 0) * (props.d("widthFactor") ?? 1)
    }
    open override func computeMaxIntrinsicWidth(_ h: Double) -> Double {
        (child?.maxIntrinsicWidth(h) ?? 0) * (props.d("widthFactor") ?? 1)
    }
    open override func computeMinIntrinsicHeight(_ w: Double) -> Double {
        (child?.minIntrinsicHeight(w) ?? 0) * (props.d("heightFactor") ?? 1)
    }
    open override func computeMaxIntrinsicHeight(_ w: Double) -> Double {
        (child?.maxIntrinsicHeight(w) ?? 0) * (props.d("heightFactor") ?? 1)
    }
}

// ----------------------------------------------------------------------------
// AspectRatio
// ----------------------------------------------------------------------------

/** props: { aspectRatio } */
open class RenderAspectRatio: RenderObject {
    /** `props.aspectRatio || 1` (the intrinsic queries' reading). */
    private var ratioOrOne: Double {
        guard let r = props.d("aspectRatio"), r != 0, !r.isNaN else { return 1 }
        return r
    }

    private func apply(_ c: Constraints) -> Size {
        let raw = props.d("aspectRatio")
        let ar = raw != nil && raw! > 0 ? raw! : 1
        if c.minWidth >= c.maxWidth && c.minHeight >= c.maxHeight { return smallest(c) }
        var width = c.maxWidth
        var height: Double
        if width.isFinite {
            height = width / ar
        } else {
            height = c.maxHeight
            width = height * ar
        }
        if width > c.maxWidth {
            width = c.maxWidth
            height = width / ar
        }
        if height > c.maxHeight {
            height = c.maxHeight
            width = height * ar
        }
        if width < c.minWidth {
            width = c.minWidth
            height = width / ar
        }
        if height < c.minHeight {
            height = c.minHeight
            width = height * ar
        }
        if !width.isFinite || !height.isFinite {
            // Unbounded on both axes: fall back to the child's own size.
            return .zero
        }
        return constrain(c, Size(width: width, height: height))
    }

    open override func performLayout(_ c: Constraints) {
        size = apply(c)
        if let child = child {
            child.layout(tight(size.width, size.height))
            child.offset = .zero
        }
    }

    open override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        height.isFinite ? height * ratioOrOne : child?.minIntrinsicWidth(height) ?? 0
    }
    open override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        height.isFinite ? height * ratioOrOne : child?.maxIntrinsicWidth(height) ?? 0
    }
    open override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        width.isFinite ? width / ratioOrOne : child?.minIntrinsicHeight(width) ?? 0
    }
    open override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        width.isFinite ? width / ratioOrOne : child?.maxIntrinsicHeight(width) ?? 0
    }
}

// ----------------------------------------------------------------------------
// FractionallySizedBox
// ----------------------------------------------------------------------------

/**
 * props: { widthFactor, heightFactor, alignment, fallbackWidth, fallbackHeight }
 * A factor applies only when the incoming axis is bounded; otherwise the
 * fallback pixel size is used (the CSS-percentage behaviour of applyStyle).
 */
open class RenderFractional: RenderObject {
    open override func performLayout(_ c: Constraints) {
        let wf = props.d("widthFactor")
        let hf = props.d("heightFactor")
        var inner = c
        if let wf = wf {
            if c.maxWidth.isFinite {
                let w = c.maxWidth * wf
                inner.minWidth = w
                inner.maxWidth = w
            } else if let fw = props.d("fallbackWidth") {
                inner.minWidth = fw
                inner.maxWidth = fw
            }
        }
        if let hf = hf {
            if c.maxHeight.isFinite {
                let h = c.maxHeight * hf
                inner.minHeight = h
                inner.maxHeight = h
            } else if let fh = props.d("fallbackHeight") {
                inner.minHeight = fh
                inner.maxHeight = fh
            }
        }
        if let child = child {
            child.layout(inner)
            size = constrain(c, child.size)
            child.offset = alignOffset(props.alignment("alignment", .center), size, child.size)
        } else {
            size = constrain(c, Size(width: inner.minWidth, height: inner.minHeight))
        }
    }
}

// ----------------------------------------------------------------------------
// LimitedBox / OverflowBox
// ----------------------------------------------------------------------------

/** props: { maxWidth, maxHeight } — limits applied only on unbounded axes. */
open class RenderLimitedBox: RenderObject {
    open override func performLayout(_ c: Constraints) {
        let limited = Constraints(
            minWidth: c.minWidth,
            maxWidth: c.maxWidth.isFinite ? c.maxWidth : constrainLimit(c.minWidth, props.d("maxWidth")),
            minHeight: c.minHeight,
            maxHeight: c.maxHeight.isFinite ? c.maxHeight : constrainLimit(c.minHeight, props.d("maxHeight"))
        )
        if let child = child {
            child.layout(limited)
            child.offset = .zero
            size = constrain(c, child.size)
        } else {
            size = constrain(limited, .zero)
        }
    }
}

private func constrainLimit(_ minimum: Double, _ limit: Double?) -> Double {
    guard let limit = limit else { return INF }
    return max(minimum, limit)
}

/** props: { alignment, minWidth, maxWidth, minHeight, maxHeight } (nil = parent's) */
open class RenderOverflowBox: RenderObject {
    open override func performLayout(_ c: Constraints) {
        let p = props
        let inner = Constraints(
            minWidth: p.d("minWidth") ?? c.minWidth,
            maxWidth: p.d("maxWidth") ?? c.maxWidth,
            minHeight: p.d("minHeight") ?? c.minHeight,
            maxHeight: p.d("maxHeight") ?? c.maxHeight
        )
        size = biggest(c)
        if let child = child {
            child.layout(inner)
            child.offset = alignOffset(p.alignment("alignment", .center), size, child.size)
        }
    }
}

// ----------------------------------------------------------------------------
// FittedBox — scales its child (paints a transform)
// ----------------------------------------------------------------------------

/** props: { fit, alignment, clip } — the child sits in a [RenderFittedContent] transform view. */
open class RenderFittedBox: RenderObject {
    private var scaleX = 1.0
    private var scaleY = 1.0
    private var childOffset = Vec.zero

    open override func performLayout(_ c: Constraints) {
        guard let child = child else {
            size = smallest(c)
            return
        }
        child.layout(Constraints(minWidth: 0, maxWidth: INF, minHeight: 0, maxHeight: INF))
        let cs = child.size
        let fit = props.s("fit") ?? (props["fit"] as? BoxFit)?.rawValue ?? "contain"
        // constrainSizeAndAttemptToPreserveAspectRatio
        size = preserveAspect(c, cs)
        let (sx, sy) = fitScale(fit, cs, size)
        scaleX = sx
        scaleY = sy
        let scaled = Size(width: cs.width * sx, height: cs.height * sy)
        childOffset = alignOffset(props.alignment("alignment", .center), size, scaled)
        child.offset = .zero
    }

    open override func viewKind() -> ViewKind? { .view }

    open override func viewProps() -> ViewProps {
        let p = ViewProps()
        p["clip"] = !props.isFalse("clip")
        p["transform"] = nil as Any?
        return p
    }

    open override func childOriginInView() -> Vec { .zero }

    /** The child is wrapped in a transform view by the compositor hook below. */
    public var contentTransform: Matrix4 {
        Matrix.multiply(Matrix.translation(childOffset.x, childOffset.y), Matrix.scaling(scaleX, scaleY, 1))
    }
}

public func fitScale(_ fit: String, _ child: Size, _ box: Size) -> (Double, Double) {
    if child.width <= 0 || child.height <= 0 { return (1, 1) }
    let rw = box.width / child.width
    let rh = box.height / child.height
    switch fit {
    case "fill":
        return (rw, rh)
    case "cover":
        let s = max(rw, rh)
        return (s, s)
    case "fitWidth":
        return (rw, rw)
    case "fitHeight":
        return (rh, rh)
    case "none":
        return (1, 1)
    case "scaleDown":
        let s = min(1, min(rw, rh))
        return (s, s)
    default: // contain
        let s = min(rw, rh)
        return (s, s)
    }
}

public func preserveAspect(_ c: Constraints, _ s: Size) -> Size {
    if c.minWidth >= c.maxWidth && c.minHeight >= c.maxHeight { return smallest(c) }
    var width = s.width
    var height = s.height
    if width <= 0 || height <= 0 { return constrain(c, s) }
    let ar = width / height
    if width > c.maxWidth {
        width = c.maxWidth
        height = width / ar
    }
    if height > c.maxHeight {
        height = c.maxHeight
        width = height * ar
    }
    if width < c.minWidth {
        width = c.minWidth
        height = width / ar
    }
    if height < c.minHeight {
        height = c.minHeight
        width = height * ar
    }
    return constrain(c, Size(width: width, height: height))
}

/**
 * The scaled content of a FittedBox: a transform view the FittedBox's child
 * is placed in. Kept as a separate object so the child keeps its natural
 * size and the platform only needs a matrix.
 */
open class RenderFittedContent: RenderObject {
    open override func performLayout(_ c: Constraints) {
        if let child = child {
            child.layout(c)
            child.offset = .zero
            size = child.size
        } else {
            size = smallest(c)
        }
    }

    open override func viewKind() -> ViewKind? { .view }

    open override func viewProps() -> ViewProps {
        let fitted = parent as? RenderFittedBox
        let transform: Matrix4 = fitted?.contentTransform ?? Matrix.identity()
        let p = ViewProps()
        p["transform"] = transform
        p["transformOrigin"] = [0.0, 0.0]
        return p
    }
}

// ----------------------------------------------------------------------------
// Baseline
// ----------------------------------------------------------------------------

/** props: { baseline } */
open class RenderBaseline: RenderObject {
    open override func performLayout(_ c: Constraints) {
        guard let child = child else {
            size = smallest(c)
            return
        }
        child.layout(loose(c))
        let target = props.d("baseline") ?? 0
        let childBaseline = child.baseline() ?? child.size.height
        let top = target - childBaseline
        child.offset = Vec(x: 0, y: top)
        size = constrain(c, Size(width: child.size.width, height: top + child.size.height))
    }
}

// ----------------------------------------------------------------------------
// RotatedBox — rotates by quarter turns, swapping the axes
// ----------------------------------------------------------------------------

/** props: { quarterTurns } */
open class RenderRotatedBox: RenderObject {
    private var turns: Double {
        let q = props.d("quarterTurns") ?? 0
        return (q.truncatingRemainder(dividingBy: 4) + 4).truncatingRemainder(dividingBy: 4)
    }

    open override func performLayout(_ c: Constraints) {
        let odd = turns.truncatingRemainder(dividingBy: 2) == 1
        guard let child = child else {
            size = smallest(c)
            return
        }
        child.layout(odd ? Constraints(minWidth: c.minHeight, maxWidth: c.maxHeight, minHeight: c.minWidth, maxHeight: c.maxWidth) : c)
        size = odd ? Size(width: child.size.height, height: child.size.width) : child.size
        child.offset = .zero
    }

    open override func viewKind() -> ViewKind? { .view }

    open override func viewProps() -> ViewProps {
        guard let child = child else { return ViewProps() }
        let t = turns
        // Rotate the child's box about its centre, then centre it in ours.
        let cw = child.size.width
        let ch = child.size.height
        let m = Matrix.multiply(
            Matrix.translation(size.width / 2, size.height / 2),
            Matrix.multiply(Matrix.rotationZ(t * Double.pi / 2), Matrix.translation(-cw / 2, -ch / 2))
        )
        return ViewProps([("transform", m.map { $0 as Any? }), ("transformOrigin", [0.0, 0.0] as [Any?])])
    }

    open override func computeMinIntrinsicWidth(_ h: Double) -> Double {
        turns.truncatingRemainder(dividingBy: 2) != 0 ? child?.minIntrinsicHeight(h) ?? 0 : child?.minIntrinsicWidth(h) ?? 0
    }
    open override func computeMaxIntrinsicWidth(_ h: Double) -> Double {
        turns.truncatingRemainder(dividingBy: 2) != 0 ? child?.maxIntrinsicHeight(h) ?? 0 : child?.maxIntrinsicWidth(h) ?? 0
    }
}

// ----------------------------------------------------------------------------
// IntrinsicWidth / IntrinsicHeight
// ----------------------------------------------------------------------------

/** props: { onlyWhenUnbounded } (Flutter's `_flexSafe`). */
open class RenderIntrinsicWidth: RenderObject {
    open override func performLayout(_ c: Constraints) {
        guard let child = child else {
            size = smallest(c)
            return
        }
        var inner = c
        // `onlyWhenUnbounded` (Flutter's `_flexSafe`): pass bounded constraints through.
        let applies = !jsTruthy(props["onlyWhenUnbounded"]) || !c.maxWidth.isFinite
        if applies && !(c.minWidth >= c.maxWidth) {
            let w = clampN(child.maxIntrinsicWidth(c.maxHeight), c.minWidth, c.maxWidth)
            inner.minWidth = w
            inner.maxWidth = w
        }
        child.layout(inner)
        child.offset = .zero
        size = child.size
    }
}

open class RenderIntrinsicHeight: RenderObject {
    open override func performLayout(_ c: Constraints) {
        guard let child = child else {
            size = smallest(c)
            return
        }
        var inner = c
        if !(c.minHeight >= c.maxHeight) {
            let h = clampN(child.maxIntrinsicHeight(c.maxWidth), c.minHeight, c.maxHeight)
            inner.minHeight = h
            inner.maxHeight = h
        }
        child.layout(inner)
        child.offset = .zero
        size = child.size
    }
}

// ----------------------------------------------------------------------------
// Offstage / IndexedStack
// ----------------------------------------------------------------------------

/** Lays the child out but takes no space and paints nothing (`offstage: true`). */
open class RenderOffstage: RenderProxy {
    open override func performLayout(_ c: Constraints) {
        if props.isFalse("offstage") {
            super.performLayout(c)
            return
        }
        child?.layout(c)
        size = smallest(c)
    }

    open override func paintsChild(_ child: RenderObject) -> Bool {
        props.isFalse("offstage")
    }
}

/** props: { index, alignment } — every child keeps its state; only one paints. */
open class RenderIndexedStack: RenderObject {
    open override func performLayout(_ c: Constraints) {
        let alignment = props.alignment("alignment", .topLeft)
        var w = 0.0
        var h = 0.0
        let inner = loose(c)
        for child in children {
            child.layout(inner)
            w = max(w, child.size.width)
            h = max(h, child.size.height)
        }
        size = children.isEmpty ? biggest(c) : constrain(c, Size(width: w, height: h))
        for child in children { child.offset = alignOffset(alignment, size, child.size) }
    }

    open override func paintsChild(_ child: RenderObject) -> Bool {
        let raw = jsTrunc(props.d("index") ?? 0)
        let index = max(0, min(Double(children.count - 1), raw.isNaN ? 0 : raw))
        let i = Int(index)
        return i < children.count && children[i] === child
    }
}

// ----------------------------------------------------------------------------
// SafeArea — pads by the platform's safe-area insets
// ----------------------------------------------------------------------------

/** props: { top, right, bottom, left } (booleans; default all true) */
open class RenderSafeArea: RenderPadding {
    open override func resolvedPadding(_ c: Constraints?) -> EdgeInsets {
        let inset = owner.map { $0.platform.viewport($0.surface).safeArea } ?? .zero
        let p = props
        return EdgeInsets(
            top: !p.isFalse("top") ? inset.top : 0,
            right: !p.isFalse("right") ? inset.right : 0,
            bottom: !p.isFalse("bottom") ? inset.bottom : 0,
            left: !p.isFalse("left") ? inset.left : 0
        )
    }
}

// ----------------------------------------------------------------------------
// FillAxis — `SizedBox(width: double.infinity)` only when the axis is bounded
// ----------------------------------------------------------------------------

/** props: { width?: Bool, height?: Bool } */
open class RenderFillAxis: RenderObject {
    open override func performLayout(_ c: Constraints) {
        let fillW = jsTruthy(props["width"]) && c.maxWidth.isFinite
        let fillH = jsTruthy(props["height"]) && c.maxHeight.isFinite
        let inner = Constraints(
            minWidth: fillW ? c.maxWidth : c.minWidth,
            maxWidth: c.maxWidth,
            minHeight: fillH ? c.maxHeight : c.minHeight,
            maxHeight: c.maxHeight
        )
        if let child = child {
            child.layout(inner)
            child.offset = .zero
            size = child.size
        } else {
            size = constrain(inner, .zero)
        }
    }
}
