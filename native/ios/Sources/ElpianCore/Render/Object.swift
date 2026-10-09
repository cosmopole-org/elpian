import Foundation

/**
 * The render-object tree: a compact port of Flutter's box protocol
 * (render/object.ts).
 *
 * Lowering turns every Elpian node into a tree of *widget descriptors*
 * ([W]) — the same widget composition the Flutter engine builds
 * (Padding → ConstrainedBox → DecoratedBox → …). The reconciler keeps one
 * [RenderObject] per descriptor across renders (so animation state, scroll
 * offsets and text input survive a re-render), layout runs Flutter's
 * constraints-down / sizes-up algorithm, and the compositor turns the objects
 * that paint into native views.
 */
public struct Constraints: Equatable, Hashable, JSONSerializable {
    public var minWidth: Double
    public var maxWidth: Double
    public var minHeight: Double
    public var maxHeight: Double

    public init(minWidth: Double, maxWidth: Double, minHeight: Double, maxHeight: Double) {
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.minHeight = minHeight
        self.maxHeight = maxHeight
    }

    public var isTight: Bool { minWidth >= maxWidth && minHeight >= maxHeight }

    public func toJSON() -> Any? {
        JSONObject([("minWidth", minWidth), ("maxWidth", maxWidth), ("minHeight", minHeight), ("maxHeight", maxHeight)])
    }
}

public struct Size: Equatable, Hashable, JSONSerializable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public static let zero = Size(width: 0, height: 0)

    public func toJSON() -> Any? { JSONObject([("width", width), ("height", height)]) }
}

/** A position `{x, y}` (offsets of render objects, view origins). */
public struct Vec: Equatable, Hashable, JSONSerializable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec(x: 0, y: 0)

    public func toJSON() -> Any? { JSONObject([("x", x), ("y", y)]) }
}

/** A rectangle in surface coordinates (`globalFrame`, hero flights). */
public struct Rect: Equatable, Hashable, JSONSerializable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public func toJSON() -> Any? { JSONObject([("x", x), ("y", y), ("width", width), ("height", height)]) }
}

public let INF = Double.infinity

public func tight(_ width: Double, _ height: Double) -> Constraints {
    Constraints(minWidth: width, maxWidth: width, minHeight: height, maxHeight: height)
}

public func loose(_ c: Constraints) -> Constraints {
    Constraints(minWidth: 0, maxWidth: c.maxWidth, minHeight: 0, maxHeight: c.maxHeight)
}

public func tightFor(_ c: Constraints, _ width: Double?, _ height: Double?) -> Constraints {
    Constraints(
        minWidth: width != nil ? clampN(width!, c.minWidth, c.maxWidth) : c.minWidth,
        maxWidth: width != nil ? clampN(width!, c.minWidth, c.maxWidth) : c.maxWidth,
        minHeight: height != nil ? clampN(height!, c.minHeight, c.maxHeight) : c.minHeight,
        maxHeight: height != nil ? clampN(height!, c.minHeight, c.maxHeight) : c.maxHeight
    )
}

/** Flutter `BoxConstraints.enforce`: keep [inner] within [outer]. */
public func enforce(_ inner: Constraints, _ outer: Constraints) -> Constraints {
    Constraints(
        minWidth: clampN(inner.minWidth, outer.minWidth, outer.maxWidth),
        maxWidth: clampN(inner.maxWidth, outer.minWidth, outer.maxWidth),
        minHeight: clampN(inner.minHeight, outer.minHeight, outer.maxHeight),
        maxHeight: clampN(inner.maxHeight, outer.minHeight, outer.maxHeight)
    )
}

public func deflate(_ c: Constraints, _ h: Double, _ v: Double) -> Constraints {
    let minW = max(0, c.minWidth - h)
    let minH = max(0, c.minHeight - v)
    return Constraints(minWidth: minW, maxWidth: max(minW, c.maxWidth - h), minHeight: minH, maxHeight: max(minH, c.maxHeight - v))
}

public func constrain(_ c: Constraints, _ s: Size) -> Size {
    Size(width: clampN(s.width, c.minWidth, c.maxWidth), height: clampN(s.height, c.minHeight, c.maxHeight))
}

public func biggest(_ c: Constraints) -> Size {
    Size(width: c.maxWidth.isFinite ? c.maxWidth : c.minWidth, height: c.maxHeight.isFinite ? c.maxHeight : c.minHeight)
}

public func smallest(_ c: Constraints) -> Size {
    Size(width: c.minWidth, height: c.minHeight)
}

public func isTight(_ c: Constraints) -> Bool { c.isTight }

public func clampN(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
    if v < lo { return lo }
    if v > hi { return hi }
    return v
}

/** Configuration of a render object (the TypeScript `props` record). */
public typealias Props = JSONObject

/** A widget descriptor: what lowering produces and the reconciler consumes. */
public final class W {
    /** Render-object type (`padding`, `flex`, `text`, …). */
    public let t: String
    /** Configuration. */
    public let p: Props
    public let c: [W]?
    /** Identity across renders (Flutter `Key`). */
    public let k: String?

    public init(_ t: String, _ p: Props = Props(), _ c: [W]? = nil, _ k: String? = nil) {
        self.t = t
        self.p = p
        self.c = c
        self.k = k
    }
}

public func w(_ t: String, _ p: Props = Props(), _ c: [W]? = nil, _ k: String? = nil) -> W { W(t, p, c, k) }
public func w(_ t: String, _ p: Props, child: W?, _ k: String? = nil) -> W { W(t, p, child.map { [$0] }, k) }

/** Typed reads of a props bag (numbers, strings, booleans, typed values). */
public extension JSONObject {
    /** A number (`p.key` when it is a number). */
    func d(_ key: String) -> Double? { jsNumber(self[key]) }
    func s(_ key: String) -> String? { self[key] as? String }
    /** `p.key === true`. */
    func b(_ key: String) -> Bool { jsBool(self[key]) == true }
    /** `p.key === false`. */
    func isFalse(_ key: String) -> Bool { jsBool(self[key]) == false }
    func value<T>(_ key: String, as type: T.Type = T.self) -> T? { self[key] as? T }
}

open class RenderObject: CustomStringConvertible {
    public var type = ""
    public var key: String?
    public var props: Props = Props()
    public weak var parent: RenderObject?
    public var children: [RenderObject] = []
    public weak var owner: RenderOwner?

    public var size = Size.zero
    /** Offset of this object's top-left inside its parent's coordinate space. */
    public var offset = Vec.zero

    public var needsLayout = true
    private var lastConstraints: Constraints?
    /** Cache of intrinsic queries, cleared on layout invalidation. */
    private var intrinsicCache: [String: Double] = [:]

    /** The native view this object owns, when it paints. */
    public var viewId: Int?

    public required init() {}

    // ---------------------------------------------------------------------------
    // Lifecycle (driven by the reconciler)
    // ---------------------------------------------------------------------------

    /** First configuration (`init` in the TypeScript core). */
    open func initialize(_ props: Props) {
        self.props = props
    }

    /** A new configuration for an existing object. Default: relayout. */
    open func update(_ props: Props) {
        let old = self.props
        self.props = props
        didUpdate(old)
        markNeedsLayout()
    }

    /** Hook for subclasses to react to a configuration change (start animations …). */
    open func didUpdate(_ old: Props) {}

    public func attach(_ owner: RenderOwner) {
        self.owner = owner
        onAttach()
    }

    open func detach() {
        onDetach()
        for c in children { c.detach() }
        owner = nil
    }

    open func onAttach() {}
    open func onDetach() {}

    public func markNeedsLayout() {
        var node: RenderObject? = self
        while let n = node, !n.needsLayout {
            n.needsLayout = true
            n.intrinsicCache.removeAll()
            node = n.parent
        }
        node?.intrinsicCache.removeAll()
        owner?.requestVisualUpdate()
    }

    /** Paint-only change: re-emit this view's props without relayout. */
    public func markNeedsPaint() {
        owner?.markPaintDirty(self)
    }

    // ---------------------------------------------------------------------------
    // Layout
    // ---------------------------------------------------------------------------

    public func layout(_ c: Constraints) {
        if !needsLayout && lastConstraints == c { return }
        lastConstraints = c
        performLayout(c)
        if !size.width.isFinite { size.width = c.minWidth.isFinite ? c.minWidth : 0 }
        if !size.height.isFinite { size.height = c.minHeight.isFinite ? c.minHeight : 0 }
        needsLayout = false
        intrinsicCache.removeAll()
    }

    public var constraints: Constraints? { lastConstraints }

    /** Subclasses lay out their children and set [size]. */
    open func performLayout(_ c: Constraints) {
        fatalError("\(Swift.type(of: self)) must override performLayout")
    }

    public var child: RenderObject? { children.first }

    // Intrinsics (Flutter getMin/MaxIntrinsicWidth/Height).
    public func minIntrinsicWidth(_ height: Double) -> Double {
        cachedIntrinsic("minW", height) { self.computeMinIntrinsicWidth(height) }
    }
    public func maxIntrinsicWidth(_ height: Double) -> Double {
        cachedIntrinsic("maxW", height) { self.computeMaxIntrinsicWidth(height) }
    }
    public func minIntrinsicHeight(_ width: Double) -> Double {
        cachedIntrinsic("minH", width) { self.computeMinIntrinsicHeight(width) }
    }
    public func maxIntrinsicHeight(_ width: Double) -> Double {
        cachedIntrinsic("maxH", width) { self.computeMaxIntrinsicHeight(width) }
    }

    private func cachedIntrinsic(_ kind: String, _ extent: Double, _ compute: () -> Double) -> Double {
        let key = kind + ":" + jsNumberToString(extent)
        if let hit = intrinsicCache[key] { return hit }
        let v = compute()
        intrinsicCache[key] = v
        return v
    }

    open func computeMinIntrinsicWidth(_ height: Double) -> Double { child?.minIntrinsicWidth(height) ?? 0 }
    open func computeMaxIntrinsicWidth(_ height: Double) -> Double { child?.maxIntrinsicWidth(height) ?? 0 }
    open func computeMinIntrinsicHeight(_ width: Double) -> Double { child?.minIntrinsicHeight(width) ?? 0 }
    open func computeMaxIntrinsicHeight(_ width: Double) -> Double { child?.maxIntrinsicHeight(width) ?? 0 }

    /** Distance from the top to the first alphabetic baseline, if any. */
    open func baseline() -> Double? {
        guard let c = child, let b = c.baseline() else { return nil }
        return b + c.offset.y
    }

    // ---------------------------------------------------------------------------
    // Painting
    // ---------------------------------------------------------------------------

    /** The native view kind when this object owns a view, otherwise nil. */
    open func viewKind() -> ViewKind? { nil }

    /** This object's view props (frame excluded — the compositor fills it). */
    open func viewProps() -> ViewProps { ViewProps() }

    /**
     * Offset added to children inside this object's own view (a scroll view's
     * children live in content space, so it reports none).
     */
    open func childOriginInView() -> Vec { .zero }

    /** Whether [child] is painted (IndexedStack / Offstage hide some children). */
    open func paintsChild(_ child: RenderObject) -> Bool { true }

    /** Called by the compositor when the platform reports an event on this view. */
    open func handleViewEvent(_ event: ViewEvent) {}

    /** Visit descendants. */
    public func visit(_ fn: (RenderObject) -> Void) {
        fn(self)
        for c in children { c.visit(fn) }
    }

    open var description: String {
        "\(type)\(key.map { "#\($0)" } ?? "")(\(jsToFixed(size.width, 1))x\(jsToFixed(size.height, 1)))"
    }
}

/** A single-child object that sizes to its child (or the smallest size without one). */
open class RenderProxy: RenderObject {
    open override func performLayout(_ c: Constraints) {
        if let child = child {
            child.layout(c)
            child.offset = .zero
            size = child.size
        } else {
            size = smallest(c)
        }
    }
}
