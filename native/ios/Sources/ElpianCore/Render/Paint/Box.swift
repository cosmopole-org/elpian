import Foundation

/**
 * Painting objects that own a plain `view` (render/paint/box.ts):
 * DecoratedBox, Opacity, Transform, ClipRRect/ClipOval, IgnorePointer,
 * Visibility, filters and ShaderMask — plus DefaultTextStyle, which paints
 * nothing but provides the inherited text style its descendants resolve
 * against.
 */

/** A background image (view prop `backgroundImage`). */
public struct DecorationImage: Equatable, Hashable, JSONSerializable {
    public var src: String
    public var fit: BoxFit?
    public var alignment: Alignment?
    public var `repeat`: String?
    public var size: SizePx?

    public init(src: String, fit: BoxFit? = nil, alignment: Alignment? = nil, repeat: String? = nil, size: SizePx? = nil) {
        self.src = src
        self.fit = fit
        self.alignment = alignment
        self.repeat = `repeat`
        self.size = size
    }

    public func toJSON() -> Any? {
        let o = JSONObject([("src", src), ("fit", fit?.rawValue), ("alignment", alignment), ("repeat", `repeat`)])
        if let size = size { o["size"] = size }
        return o
    }
}

/** An outline (view prop `outline`). */
public struct Outline: Equatable, Hashable, JSONSerializable {
    public var width: Double
    public var color: Color
    public var style: String
    public var offset: Double

    public init(width: Double, color: Color, style: String, offset: Double) {
        self.width = width
        self.color = color
        self.style = style
        self.offset = offset
    }

    public func toJSON() -> Any? { JSONObject([("width", width), ("color", color), ("style", style), ("offset", offset)]) }
}

/**
 * A box decoration (the TypeScript `Decoration` interface; named
 * `BoxDecoration` here because `Decoration` holds the text-decoration flags).
 */
public struct BoxDecoration: Equatable, Hashable, JSONSerializable {
    public var color: Color?
    public var gradients: [Gradient]?
    public var image: DecorationImage?
    public var border: Border?
    public var radius: BorderRadius?
    /** Corner radii in percent of the box (CSS `border-radius: 50%`). */
    public var radiusPercent: BorderRadius?
    /** `rectangle` or `circle`. */
    public var shape: String?
    public var shadows: [BoxShadow]?
    public var outline: Outline?

    public init(color: Color? = nil, gradients: [Gradient]? = nil, image: DecorationImage? = nil, border: Border? = nil,
                radius: BorderRadius? = nil, radiusPercent: BorderRadius? = nil, shape: String? = nil, shadows: [BoxShadow]? = nil,
                outline: Outline? = nil) {
        self.color = color
        self.gradients = gradients
        self.image = image
        self.border = border
        self.radius = radius
        self.radiusPercent = radiusPercent
        self.shape = shape
        self.shadows = shadows
        self.outline = outline
    }

    public func toJSON() -> Any? {
        let o = JSONObject()
        if let v = color { o["color"] = v }
        if let v = gradients { o["gradients"] = v.map { $0 as Any? } }
        if let v = image { o["image"] = v }
        if let v = border { o["border"] = v }
        if let v = radius { o["radius"] = v }
        if let v = radiusPercent { o["radiusPercent"] = v }
        if let v = shape { o["shape"] = v }
        if let v = shadows { o["shadows"] = v.map { $0 as Any? } }
        if let v = outline { o["outline"] = v }
        return o
    }
}

public func decorationIsEmpty(_ d: BoxDecoration?) -> Bool {
    guard let d = d else { return true }
    return d.color == nil &&
        (d.gradients?.isEmpty ?? true) &&
        d.image == nil &&
        d.border == nil &&
        d.radius == nil &&
        d.radiusPercent == nil &&
        (d.shadows?.isEmpty ?? true) &&
        d.outline == nil &&
        d.shape != "circle"
}

public func resolveRadius(_ d: BoxDecoration, _ width: Double, _ height: Double) -> BorderRadius? {
    let px = d.radius
    guard let pct = d.radiusPercent else { return clampRadius(px, width, height) }
    let basis = min(width, height)
    func r(_ p: Double, _ x: Double?) -> Double { (p != 0 && !p.isNaN ? p / 100 * basis : 0) + (x ?? 0) }
    return clampRadius(
        BorderRadius(
            topLeft: r(pct.topLeft, px?.topLeft),
            topRight: r(pct.topRight, px?.topRight),
            bottomRight: r(pct.bottomRight, px?.bottomRight),
            bottomLeft: r(pct.bottomLeft, px?.bottomLeft)
        ),
        width,
        height
    )
}

/** Corners can never exceed half the shortest side (as Flutter/CSS scale them). */
private func clampRadius(_ r: BorderRadius?, _ width: Double, _ height: Double) -> BorderRadius? {
    guard let r = r else { return nil }
    let mx = min(width, height) / 2
    func c(_ v: Double) -> Double { max(0, min(v, mx)) }
    let out = BorderRadius(topLeft: c(r.topLeft), topRight: c(r.topRight), bottomRight: c(r.bottomRight), bottomLeft: c(r.bottomLeft))
    if out.isZero { return nil }
    return out
}

public func decorationViewProps(_ d: BoxDecoration, _ width: Double, _ height: Double) -> ViewProps {
    ViewProps([
        ("background", d.color),
        ("gradients", d.gradients.flatMap { $0.isEmpty ? nil : $0.map { $0 as Any? } }),
        ("backgroundImage", d.image),
        ("border", d.border),
        ("radius", d.shape == "circle" ? nil : resolveRadius(d, width, height)),
        ("oval", d.shape == "circle" ? true : nil),
        ("shadows", d.shadows.flatMap { $0.isEmpty ? nil : $0.map { $0 as Any? } }),
        ("outline", d.outline),
    ])
}

/**
 * Call a prop callback with the arguments it accepts (JavaScript ignores extra
 * arguments). Handlers are Swift closures stored in the props bag; the
 * accepted shapes are `() -> Void`, `(ViewEvent) -> Void`,
 * `(ViewEvent, RenderObject) -> Void`, `(String) -> Void`, `(Any?) -> Void`
 * and `(Any?, Any?) -> Void`.
 */
public func callHandler(_ fn: Any?, _ args: Any?...) {
    guard let fn = flattenOptional(fn) else { return }
    let a0 = args.count > 0 ? args[0] : nil
    let a1 = args.count > 1 ? args[1] : nil
    if let f = fn as? (ViewEvent, RenderObject) -> Void {
        if let e = a0 as? ViewEvent, let ro = a1 as? RenderObject { f(e, ro) }
        return
    }
    if let f = fn as? (Any?, Any?) -> Void { f(a0, a1); return }
    if let f = fn as? ViewEventHandler {
        if let e = a0 as? ViewEvent { f(e) }
        return
    }
    if let f = fn as? (String) -> Void {
        if let s = a0 as? String { f(s) }
        return
    }
    if let f = fn as? (Any?) -> Void { f(a0); return }
    if let f = fn as? () -> Void { f(); return }
}

/** A `Matrix4` prop given as `[Double]` or a JSON array of numbers. */
public func matrixProp(_ v: Any?) -> Matrix4? {
    guard let v = flattenOptional(v) else { return nil }
    if let m = v as? [Double] { return m }
    if let a = asArray(v) {
        var out: Matrix4 = []
        for e in a {
            guard let n = jsNumber(e) else { return nil }
            out.append(n)
        }
        return out
    }
    return nil
}

/** props: { decoration: BoxDecoration, clip?: boolean } */
open class RenderDecoratedBox: RenderProxy {
    open override func viewKind() -> ViewKind? { .view }
    open override func viewProps() -> ViewProps {
        let d = props["decoration"] as? BoxDecoration ?? BoxDecoration()
        let p = decorationViewProps(d, size.width, size.height)
        p["clip"] = jsTruthy(props["clip"]) ? true : nil
        return p
    }
}

/** props: { opacity } */
open class RenderOpacity: RenderProxy {
    open override func viewKind() -> ViewKind? { .view }
    open override func viewProps() -> ViewProps {
        let o = props.d("opacity") ?? 1
        return ViewProps([("opacity", o >= 1 ? nil : max(0, o))])
    }
}

/**
 * props: { transform: Matrix4, alignment?: Alignment, origin?: [x, y] (px) }
 * The matrix is applied about the alignment point (Flutter `Transform` with
 * `alignment`), expressed to the platform as a transform + origin.
 */
open class RenderTransform: RenderProxy {
    open override func viewKind() -> ViewKind? { .view }

    open func effectiveMatrix() -> Matrix4 { matrixProp(props["transform"]) ?? Matrix.identity() }

    public func origin() -> (Double, Double) {
        let o = flattenOptional(props["origin"])
        if let v = o as? Vec { return (v.x, v.y) }
        if let a = o as? [Double], a.count >= 2 { return (a[0], a[1]) }
        if let a = asArray(o), a.count >= 2 { return (jsNumber(a[0]) ?? 0, jsNumber(a[1]) ?? 0) }
        let a = props.alignment("alignment", .center)
        return (size.width / 2 * (1 + a.x), size.height / 2 * (1 + a.y))
    }

    open override func viewProps() -> ViewProps {
        let m = effectiveMatrix()
        if Matrix.isIdentity(m) { return ViewProps([("transform", nil)]) }
        let (ox, oy) = origin()
        return ViewProps([("transform", m.map { $0 as Any? }), ("transformOrigin", [ox, oy] as [Any?])])
    }

    /** The full matrix in this view's coordinate space (used for hit testing). */
    public func matrixInSpace() -> Matrix4 {
        let (ox, oy) = origin()
        return Matrix.aboutOrigin(effectiveMatrix(), ox, oy)
    }
}

/** props: { radius?: BorderRadius, oval?: boolean, enabled?: boolean } */
open class RenderClip: RenderProxy {
    open override func viewKind() -> ViewKind? { .view }
    open override func viewProps() -> ViewProps {
        if props.isFalse("enabled") { return ViewProps() }
        let r = props["radius"] as? BorderRadius
        return ViewProps([
            ("clip", true),
            ("radius", r != nil ? resolveRadius(BoxDecoration(radius: r), size.width, size.height) : nil),
            ("oval", jsTruthy(props["oval"]) ? true : nil),
        ])
    }
}

/** props: { ignoring: boolean } */
open class RenderIgnorePointer: RenderProxy {
    open override func viewKind() -> ViewKind? { .view }
    open override func viewProps() -> ViewProps {
        ViewProps([("pointerEvents", props.isFalse("ignoring") ? "auto" : "none")])
    }
}

/**
 * props: { mode: 'gone' | 'hidden' | 'visible' }
 * `gone` (Flutter `Visibility(visible: false)`) takes no space and paints
 * nothing; `hidden` (CSS `visibility: hidden`) keeps its space.
 */
open class RenderVisibility: RenderObject {
    open override func performLayout(_ c: Constraints) {
        if props.s("mode") == "gone" {
            child?.layout(c)
            size = smallest(c)
            return
        }
        if let child = child {
            child.layout(c)
            child.offset = .zero
            size = child.size
        } else {
            size = smallest(c)
        }
    }

    open override func paintsChild(_ child: RenderObject) -> Bool { props.s("mode") != "gone" }
    open override func viewKind() -> ViewKind? { props.s("mode") == "hidden" ? .view : nil }
    open override func viewProps() -> ViewProps { ViewProps([("hidden", true)]) }
}

/** props: { filter?: Filter, backdrop?: Filter, blendMode?: string, zIndex?: number } */
open class RenderFilter: RenderProxy {
    open override func viewKind() -> ViewKind? { .view }
    open override func viewProps() -> ViewProps {
        ViewProps([
            ("filter", props["filter"] as? Filter),
            ("backdropFilter", props["backdrop"] as? Filter),
            ("blendMode", props["blendMode"]),
        ])
    }
}

/** props: { gradient: Gradient } — ShaderMask(srcATop) as Shimmer uses it. */
open class RenderShaderMask: RenderProxy {
    open override func viewKind() -> ViewKind? { .view }
    open override func viewProps() -> ViewProps { ViewProps([("shaderMask", props["gradient"] as? Gradient)]) }
}

/**
 * props: { style: TextStyle, textAlign?, maxLines?, overflow?, softWrap? }
 * Provides the inherited text style (Flutter `DefaultTextStyle`).
 */
open class RenderDefaultTextStyle: RenderProxy {
    open var textStyle: TextStyle { props["style"] as? TextStyle ?? TextStyle() }
}
