import Foundation

/**
 * Animated render objects (render/animated.ts).
 *
 * Implicit animations (Flutter `AnimatedContainer`, `AnimatedOpacity`,
 * `AnimatedPadding`, `AnimatedAlign`, `AnimatedPositioned`, `AnimatedScale`,
 * `AnimatedRotation`, `AnimatedSlide`, `AnimatedSize`,
 * `AnimatedDefaultTextStyle`, `AnimatedCrossFade`, `AnimatedSwitcher`, plus
 * CSS transitions) animate from the current value whenever a re-render
 * changes the target. Explicit animations (`FadeTransition`,
 * `SlideTransition`, `ScaleTransition`, `RotationTransition`,
 * `SizeTransition`, `TweenAnimationBuilder`, `StaggeredAnimation`, `Shimmer`,
 * `Pulse`, `AnimatedGradient`, CSS `@keyframes`) run their own controller from
 * the moment they mount.
 *
 * All of them tick on the owner's frame clock; only paint props change on
 * most frames (opacity / transform / colours), so the platform animates them
 * without relayout.
 */

/** The `curve` prop: a [Curve] function or a curve name. */
func curveOf(_ props: JSONObject, _ fallback: @escaping Curve = Curves.linear) -> Curve {
    let c = props["curve"]
    if let f = c as? Curve { return f }
    return curveByName(c as? String, fallback)
}

private func lerpNullable(_ a: Double?, _ b: Double?, _ t: Double) -> Double? {
    guard let a = a, let b = b else { return t < 0.5 ? a : b }
    return a + (b - a) * t
}

/** JavaScript truthiness of a number (`0` and `NaN` are false). */
private func truthy(_ v: Double) -> Bool { v != 0 && !v.isNaN }

/** An `[x, y]` pair prop (array or [Vec]); nil when absent. */
private func pairOf(_ v: Any?) -> (Double, Double)? {
    let value = flattenOptional(v)
    if let p = value as? Vec { return (p.x, p.y) }
    if let a = asArray(value) {
        return (a.count > 0 ? jsNumber(a[0]) ?? .nan : .nan, a.count > 1 ? jsNumber(a[1]) ?? .nan : .nan)
    }
    return nil
}

/** `p?.[i] ?? fallback`: a missing pair or element falls back. */
private func pairAt(_ v: Any?, _ i: Int, _ fallback: Double) -> Double {
    let value = flattenOptional(v)
    if let a = asArray(value) { return i < a.count ? jsNumber(a[i]) ?? fallback : fallback }
    guard let p = pairOf(value) else { return fallback }
    return i == 0 ? p.0 : p.1
}

/** JavaScript `!==` for prop values: numbers by value, primitives by value, everything else by identity. */
private func strictNotEqual(_ a: Any?, _ b: Any?) -> Bool {
    let x = flattenOptional(a)
    let y = flattenOptional(b)
    if x == nil && y == nil { return false }
    guard let xv = x, let yv = y else { return true }
    if let bx = jsBool(xv) { return jsBool(yv) != bx }
    if jsBool(yv) != nil { return true }
    if let nx = jsNumber(xv) {
        guard let ny = jsNumber(yv) else { return true }
        return nx != ny
    }
    if let sx = xv as? String { return (yv as? String) != sx }
    if yv is String { return true }
    if type(of: xv) is AnyClass, type(of: yv) is AnyClass { return (xv as AnyObject) !== (yv as AnyObject) }
    // Value types have no identity: two of them are the same value only when equal.
    if let hx = xv as? AnyHashable, let hy = yv as? AnyHashable { return hx != hy }
    return true
}

private func colorProp(_ v: Any?) -> Color? {
    if let c = flattenOptional(v) as? Color { return c }
    return jsNumber(v).map { jsToUint32($0) }
}

/** Save and restore one prop around a call (keeps absent keys absent). */
private func withProp<R>(_ props: JSONObject, _ key: String, _ value: Any?, _ body: () -> R) -> R {
    let had = props.has(key)
    let saved = props[key]
    props[key] = value
    defer {
        if had { props[key] = saved } else { props.removeValue(forKey: key) }
    }
    return body()
}

// ============================================================================
// Implicit
// ============================================================================

/** props: padding, percent, duration, curve */
open class RenderAnimatedPadding: RenderPadding {
    private var value: ImplicitValue<EdgeInsets>!

    private static func target(_ p: JSONObject) -> EdgeInsets { p["padding"] as? EdgeInsets ?? .zero }

    open override func initialize(_ props: Props) {
        super.initialize(props)
        value = ImplicitValue(RenderAnimatedPadding.target(props), lerp: EdgeInsets.lerp, equals: { $0 == $1 }) { [weak self] in
            self?.markNeedsLayout()
        }
    }

    open override func didUpdate(_ old: Props) {
        value.set(RenderAnimatedPadding.target(props), duration: props.d("duration"), curve: curveOf(props), owner: owner)
    }

    open override func resolvedPadding(_ c: Constraints?) -> EdgeInsets {
        withProp(props, "padding", value.current) { super.resolvedPadding(c) }
    }

    open override func onDetach() {
        value.dispose()
    }
}

/** props: alignment, widthFactor, heightFactor, duration, curve */
open class RenderAnimatedAlign: RenderAlign {
    private var value: ImplicitValue<Alignment>!

    private static func target(_ p: JSONObject) -> Alignment { p["alignment"] as? Alignment ?? .center }

    open override func initialize(_ props: Props) {
        super.initialize(props)
        value = ImplicitValue(RenderAnimatedAlign.target(props), lerp: Alignment.lerp, equals: { $0 == $1 }) { [weak self] in
            self?.markNeedsLayout()
        }
    }

    open override func didUpdate(_ old: Props) {
        value.set(RenderAnimatedAlign.target(props), duration: props.d("duration"), curve: curveOf(props), owner: owner)
    }

    open override func performLayout(_ c: Constraints) {
        withProp(props, "alignment", value.current) { super.performLayout(c) }
    }

    open override func onDetach() {
        value.dispose()
    }
}

/** props: opacity, duration, curve */
open class RenderAnimatedOpacity: RenderOpacity {
    private var value: ImplicitValue<Double>!

    open override func initialize(_ props: Props) {
        super.initialize(props)
        value = ImplicitValue(props.d("opacity") ?? 1, lerp: lerpNumber, equals: { $0 == $1 }) { [weak self] in
            self?.markNeedsPaint()
        }
    }

    open override func didUpdate(_ old: Props) {
        value.set(props.d("opacity") ?? 1, duration: props.d("duration"), curve: curveOf(props), owner: owner)
    }

    open override func viewProps() -> ViewProps {
        let o = value.current
        return ViewProps([("opacity", o >= 1 ? nil : max(0, o))])
    }

    open override func onDetach() {
        value.dispose()
    }
}

/** The animated parts of an [RenderAnimatedTransform]. */
public struct TransformTarget: Equatable {
    public var scale: Double
    public var turns: Double
    public var slideX: Double
    public var slideY: Double
    public var tx: Double
    public var ty: Double
    public var base: Matrix4
}

public let lerpTransformTarget: Lerp<TransformTarget> = { a, b, t in
    TransformTarget(
        scale: lerpNumber(a.scale, b.scale, t),
        turns: lerpNumber(a.turns, b.turns, t),
        slideX: lerpNumber(a.slideX, b.slideX, t),
        slideY: lerpNumber(a.slideY, b.slideY, t),
        tx: lerpNumber(a.tx, b.tx, t),
        ty: lerpNumber(a.ty, b.ty, t),
        base: Matrix.lerp(a.base, b.base, t)
    )
}

/**
 * AnimatedScale / AnimatedRotation / AnimatedSlide / CSS transform transitions.
 * props: { scale, turns, slide: [x, y] (fractions of size), translate: [x, y] px,
 *          transform: Matrix4, alignment, duration, curve }
 */
open class RenderAnimatedTransform: RenderTransform {
    private var value: ImplicitValue<TransformTarget>!

    private static func targetOf(_ p: JSONObject) -> TransformTarget {
        TransformTarget(
            scale: p.d("scale") ?? 1,
            turns: p.d("turns") ?? 0,
            slideX: pairAt(p["slide"], 0, 0),
            slideY: pairAt(p["slide"], 1, 0),
            tx: pairAt(p["translate"], 0, 0),
            ty: pairAt(p["translate"], 1, 0),
            base: matrixProp(p["transform"]) ?? Matrix.identity()
        )
    }

    open override func initialize(_ props: Props) {
        super.initialize(props)
        value = ImplicitValue(RenderAnimatedTransform.targetOf(props), lerp: lerpTransformTarget, equals: { $0 == $1 }) { [weak self] in
            self?.markNeedsPaint()
        }
    }

    open override func didUpdate(_ old: Props) {
        value.set(RenderAnimatedTransform.targetOf(props), duration: props.d("duration"), curve: curveOf(props), owner: owner)
    }

    open override func effectiveMatrix() -> Matrix4 {
        let v = value.current
        var m = v.base
        if truthy(v.slideX) || truthy(v.slideY) || truthy(v.tx) || truthy(v.ty) {
            m = Matrix.multiply(Matrix.translation(v.slideX * size.width + v.tx, v.slideY * size.height + v.ty), m)
        }
        if truthy(v.turns) { m = Matrix.multiply(m, Matrix.rotationZ(v.turns * Double.pi * 2)) }
        if v.scale != 1 { m = Matrix.multiply(m, Matrix.scaling(v.scale, v.scale, 1)) }
        return m
    }

    open override func onDetach() {
        value.dispose()
    }
}

public struct BoxTarget: Equatable {
    public var width: Double?
    public var height: Double?
}

/** AnimatedContainer's size: props minWidth…maxHeight, width, height, duration, curve */
open class RenderAnimatedConstrained: RenderConstrainedBox {
    private var value: ImplicitValue<BoxTarget>!

    open override func initialize(_ props: Props) {
        super.initialize(props)
        value = ImplicitValue(
            BoxTarget(width: props.d("width"), height: props.d("height")),
            lerp: { a, b, t in BoxTarget(width: lerpNullable(a.width, b.width, t), height: lerpNullable(a.height, b.height, t)) },
            equals: { $0 == $1 }
        ) { [weak self] in
            self?.markNeedsLayout()
        }
    }

    open override func didUpdate(_ old: Props) {
        value.set(BoxTarget(width: props.d("width"), height: props.d("height")), duration: props.d("duration"), curve: curveOf(props), owner: owner)
    }

    open override func additional() -> Constraints {
        let current = value.current
        return withProp(props, "width", current.width) {
            withProp(props, "height", current.height) { super.additional() }
        }
    }

    open override func onDetach() {
        value.dispose()
    }
}

public struct DecorationTarget: Equatable {
    public var color: Color?
    public var radius: BorderRadius?
    public var borderColor: Color?
    public var borderWidth: Double
}

/** AnimatedContainer's decoration: colour, radius and uniform border animate. */
open class RenderAnimatedDecorated: RenderDecoratedBox {
    private var value: ImplicitValue<DecorationTarget>!

    private static func targetOf(_ d: BoxDecoration?) -> DecorationTarget {
        DecorationTarget(color: d?.color, radius: d?.radius, borderColor: d?.border?.top.color, borderWidth: d?.border?.top.width ?? 0)
    }

    open override func initialize(_ props: Props) {
        super.initialize(props)
        value = ImplicitValue(
            RenderAnimatedDecorated.targetOf(props["decoration"] as? BoxDecoration),
            lerp: { a, b, t in
                DecorationTarget(
                    color: a.color == nil || b.color == nil ? (t < 0.5 ? a.color : b.color) : lerpColor(a.color!, b.color!, t),
                    radius: a.radius != nil && b.radius != nil ? BorderRadius.lerp(a.radius!, b.radius!, t) : (t < 0.5 ? a.radius : b.radius),
                    borderColor: a.borderColor == nil || b.borderColor == nil ? (t < 0.5 ? a.borderColor : b.borderColor) : lerpColor(a.borderColor!, b.borderColor!, t),
                    borderWidth: lerpNumber(a.borderWidth, b.borderWidth, t)
                )
            },
            equals: { $0 == $1 }
        ) { [weak self] in
            self?.markNeedsPaint()
        }
    }

    open override func didUpdate(_ old: Props) {
        value.set(RenderAnimatedDecorated.targetOf(props["decoration"] as? BoxDecoration), duration: props.d("duration"), curve: curveOf(props), owner: owner)
    }

    open override func viewProps() -> ViewProps {
        var d = props["decoration"] as? BoxDecoration ?? BoxDecoration()
        let v = value.current
        d.color = v.color
        d.radius = v.radius
        if let border = d.border, let bc = v.borderColor {
            func side(_ s: BorderSide) -> BorderSide {
                BorderSide(width: s.style == .none ? s.width : v.borderWidth, color: bc, style: s.style)
            }
            d.border = Border(top: side(border.top), right: side(border.right), bottom: side(border.bottom), left: side(border.left))
        }
        return decorationViewProps(d, size.width, size.height)
    }

    open override func onDetach() {
        value.dispose()
    }
}

public struct PosTarget: Equatable {
    public var top: Double?
    public var right: Double?
    public var bottom: Double?
    public var left: Double?
    public var width: Double?
    public var height: Double?
}

/**
 * AnimatedPositioned. The current animated values are written into the props
 * (the parent stack reads them) whenever they change and before layout.
 */
open class RenderAnimatedPositioned: RenderPositioned {
    private var value: ImplicitValue<PosTarget>?

    private static func targetOf(_ p: JSONObject) -> PosTarget {
        PosTarget(top: p.d("top"), right: p.d("right"), bottom: p.d("bottom"), left: p.d("left"), width: p.d("width"), height: p.d("height"))
    }

    private func assignCurrent() {
        guard let v = value?.current else { return }
        func put(_ k: String, _ x: Double?) {
            if let x = x { props[k] = x } else { props.removeValue(forKey: k) }
        }
        put("top", v.top)
        put("right", v.right)
        put("bottom", v.bottom)
        put("left", v.left)
        put("width", v.width)
        put("height", v.height)
    }

    open override func initialize(_ props: Props) {
        super.initialize(props)
        value = ImplicitValue(
            RenderAnimatedPositioned.targetOf(props),
            lerp: { a, b, t in
                PosTarget(
                    top: lerpNullable(a.top, b.top, t),
                    right: lerpNullable(a.right, b.right, t),
                    bottom: lerpNullable(a.bottom, b.bottom, t),
                    left: lerpNullable(a.left, b.left, t),
                    width: lerpNullable(a.width, b.width, t),
                    height: lerpNullable(a.height, b.height, t)
                )
            },
            equals: { $0 == $1 }
        ) { [weak self] in
            // TS overrides markNeedsLayout to sync props first; same effect.
            self?.assignCurrent()
            self?.markNeedsLayout()
        }
        assignCurrent()
    }

    open override func didUpdate(_ old: Props) {
        let target = RenderAnimatedPositioned.targetOf(props)
        value?.set(target, duration: props.d("duration"), curve: curveOf(props), owner: owner)
        assignCurrent()
    }

    open override func performLayout(_ c: Constraints) {
        assignCurrent()
        super.performLayout(c)
    }

    open override func onDetach() {
        value?.dispose()
    }
}

public let lerpTextStyle: Lerp<TextStyle> = { a, b, t in
    var out = t < 0.5 ? a : b
    if let x = a.color, let y = b.color { out.color = lerpColor(x, y, t) }
    if let x = a.fontSize, let y = b.fontSize { out.fontSize = x + (y - x) * t }
    if let x = a.letterSpacing, let y = b.letterSpacing { out.letterSpacing = x + (y - x) * t }
    if let x = a.wordSpacing, let y = b.wordSpacing { out.wordSpacing = x + (y - x) * t }
    if let x = a.height, let y = b.height { out.height = x + (y - x) * t }
    if let x = a.fontWeight, let y = b.fontWeight {
        out.fontWeight = Int(jsRound((Double(x) + Double(y - x) * t) / 100) * 100)
    }
    return out
}

/** AnimatedDefaultTextStyle: props style, duration, curve. */
open class RenderAnimatedDefaultTextStyle: RenderDefaultTextStyle {
    private var value: ImplicitValue<TextStyle>!

    open override func initialize(_ props: Props) {
        super.initialize(props)
        value = ImplicitValue(props["style"] as? TextStyle ?? TextStyle(), lerp: lerpTextStyle, equals: { $0 == $1 }) { [weak self] in
            self?.markDescendantsDirty()
        }
    }

    open override func didUpdate(_ old: Props) {
        value.set(props["style"] as? TextStyle ?? TextStyle(), duration: props.d("duration"), curve: curveOf(props), owner: owner)
    }

    open override var textStyle: TextStyle { value.current }

    private func markDescendantsDirty() {
        visit { ro in if ro.type == "text" { ro.markNeedsLayout() } }
    }

    open override func performLayout(_ c: Constraints) {
        withProp(props, "style", value.current) { super.performLayout(c) }
    }

    open override func onDetach() {
        value.dispose()
    }
}

/** AnimatedSize: animates its own size towards the child's. props duration, curve, alignment */
open class RenderAnimatedSize: RenderObject {
    private var controller: AnimationController?
    private var fromSize = Size.zero
    private var toSize: Size?
    private var hasLaidOut = false

    open override func performLayout(_ c: Constraints) {
        guard let child = child else {
            size = constrain(c, .zero)
            return
        }
        child.layout(c)
        let target = child.size
        let duration = props.d("duration")
        if !hasLaidOut || duration == nil || !truthy(duration!) {
            hasLaidOut = true
            toSize = target
            fromSize = target
            size = constrain(c, target)
        } else if let to0 = toSize, target.width != to0.width || target.height != to0.height {
            fromSize = size
            toSize = target
            let ctl: AnimationController
            if let existing = controller {
                ctl = existing
            } else {
                ctl = AnimationController(duration!)
                controller = ctl
                ctl.addListener { [weak self] in self?.markNeedsLayout() }
            }
            ctl.duration = duration!
            if let owner = owner { ctl.attach(owner) }
            ctl.forward(from: 0)
        }
        let t: Double
        if let ctl = controller, ctl.isAnimating { t = curveOf(props)(ctl.value) } else { t = 1 }
        let to = toSize ?? target
        size = constrain(c, Size(
            width: fromSize.width + (to.width - fromSize.width) * t,
            height: fromSize.height + (to.height - fromSize.height) * t
        ))
        let a = props["alignment"] as? Alignment ?? .center
        child.offset = Vec(x: (size.width - child.size.width) / 2 * (1 + a.x), y: (size.height - child.size.height) / 2 * (1 + a.y))
    }

    open override func viewKind() -> ViewKind? { .view }
    open override func viewProps() -> ViewProps { ViewProps([("clip", true)]) }

    open override func onDetach() {
        controller?.detach()
        controller?.stop()
    }
}

/**
 * AnimatedCrossFade: props { showFirst, duration, curve } with exactly two
 * children (each an opacity holder created by lowering).
 */
open class RenderAnimatedCrossFade: RenderObject {
    private var controller: AnimationController?

    open override func onAttach() {
        let ctl: AnimationController
        if let existing = controller {
            ctl = existing
        } else {
            ctl = AnimationController(props.d("duration") ?? 300, initial: props.isFalse("showFirst") ? 1 : 0)
            controller = ctl
            ctl.addListener { [weak self] in self?.markNeedsLayout() }
        }
        if let owner = owner { ctl.attach(owner) }
    }

    open override func didUpdate(_ old: Props) {
        guard let ctl = controller else { return }
        ctl.duration = props.d("duration") ?? 300
        if (!old.isFalse("showFirst")) != (!props.isFalse("showFirst")) {
            if props.isFalse("showFirst") { ctl.forward() } else { ctl.reverse() }
        }
    }

    private var t: Double {
        let v = controller?.value ?? (props.isFalse("showFirst") ? 1 : 0)
        return curveOf(props)(v)
    }

    open override func performLayout(_ c: Constraints) {
        let first = children.count > 0 ? children[0] : nil
        let second = children.count > 1 ? children[1] : nil
        let inner = Constraints(minWidth: 0, maxWidth: c.maxWidth, minHeight: 0, maxHeight: c.maxHeight)
        first?.layout(inner)
        second?.layout(inner)
        let t = self.t
        let a = first?.size ?? .zero
        let b = second?.size ?? .zero
        size = constrain(c, Size(width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t))
        if let first = first {
            first.offset = .zero
            first.props["opacity"] = 1 - t
            first.markNeedsPaint()
        }
        if let second = second {
            second.offset = .zero
            second.props["opacity"] = t
            second.markNeedsPaint()
        }
    }

    open override func viewKind() -> ViewKind? { .view }
    open override func viewProps() -> ViewProps { ViewProps([("clip", true)]) }

    open override func paintsChild(_ child: RenderObject) -> Bool {
        let t = self.t
        if !children.isEmpty && child === children[0] { return t < 1 }
        return t > 0
    }

    open override func onDetach() {
        controller?.detach()
        controller?.stop()
    }
}

/**
 * AnimatedSwitcher: when the child's identity changes, the old child stays
 * mounted and transitions out while the new one transitions in.
 * props { duration, transitionType: 'fade'|'scale'|'rotation'|'slide', curve }
 */
open class RenderAnimatedSwitcher: RenderObject {
    /** Children leaving, with their remaining progress controllers. */
    public private(set) var outgoing: [ObjectIdentifier: AnimationController] = [:]
    public private(set) var incoming: [ObjectIdentifier: AnimationController] = [:]
    private var mounted = false

    /** Whether [child] is transitioning out. */
    public func isOutgoing(_ child: RenderObject) -> Bool { outgoing[ObjectIdentifier(child)] != nil }

    /** Called by the reconciler when the current child is replaced. */
    public func childReplaced(_ oldChild: RenderObject, _ newChild: RenderObject) {
        childRemoved(oldChild)
        startIncoming(newChild)
    }

    /** Transition [oldChild] out, then detach it. */
    public func childRemoved(_ oldChild: RenderObject) {
        let duration = props.d("duration") ?? 300
        guard let o = owner, duration > 0 else {
            oldChild.detach()
            children = children.filter { $0 !== oldChild }
            return
        }
        let out = AnimationController(duration, initial: 1)
        out.attach(o)
        out.addListener { [weak self] in self?.markNeedsLayout() }
        let id = ObjectIdentifier(oldChild)
        outgoing[id] = out
        // Keep the old child mounted (painted beneath the new one) while it leaves.
        if !children.contains(where: { $0 === oldChild }) { children.insert(oldChild, at: 0) }
        oldChild.parent = self
        out.reverse().then { [weak self, weak oldChild] in
            guard let self = self else { return }
            self.outgoing[id] = nil
            if let oldChild = oldChild {
                oldChild.detach()
                self.children = self.children.filter { $0 !== oldChild }
            }
            self.markNeedsLayout()
        }
    }

    private func startIncoming(_ child: RenderObject) {
        guard let o = owner else { return }
        let c = AnimationController(props.d("duration") ?? 300, initial: 0)
        c.attach(o)
        c.addListener { [weak self] in self?.markNeedsLayout() }
        let id = ObjectIdentifier(child)
        incoming[id] = c
        c.forward().then { [weak self] in self?.incoming[id] = nil }
    }

    open override func onAttach() {
        mounted = true
    }

    public func progressOf(_ child: RenderObject) -> Double {
        let curve = curveOf(props)
        let id = ObjectIdentifier(child)
        if let c = outgoing[id] { return curve(c.value) }
        if let c = incoming[id] { return curve(c.value) }
        return 1
    }

    open override func performLayout(_ c: Constraints) {
        var w = 0.0
        var h = 0.0
        for ch in children {
            ch.layout(Constraints(minWidth: 0, maxWidth: c.maxWidth, minHeight: 0, maxHeight: c.maxHeight))
            w = max(w, ch.size.width)
            h = max(h, ch.size.height)
        }
        size = constrain(c, Size(width: w, height: h))
        for ch in children {
            ch.offset = Vec(x: (size.width - ch.size.width) / 2, y: (size.height - ch.size.height) / 2)
            // Transition applied through the child's wrapper (a RenderSwitcherSlot).
            if let slot = ch as? RenderSwitcherSlot {
                slot.progress = progressOf(slot)
                slot.kind = props.s("transitionType") ?? "fade"
                slot.markNeedsPaint()
            }
        }
    }

    open override func onDetach() {
        for c in outgoing.values { c.stop() }
        for c in incoming.values { c.stop() }
        mounted = false
    }

    public var isMounted: Bool { mounted }
}

/** One child slot of an AnimatedSwitcher; paints the transition. */
open class RenderSwitcherSlot: RenderProxy {
    public var progress = 1.0
    public var kind = "fade"

    open override func viewKind() -> ViewKind? { .view }

    open override func viewProps() -> ViewProps {
        let p = progress
        let w = size.width
        let h = size.height
        switch kind {
        case "scale":
            return ViewProps([("transform", Matrix.scaling(p, p, 1).map { $0 as Any? }), ("transformOrigin", [w / 2, h / 2] as [Any?])])
        case "rotation":
            return ViewProps([("transform", Matrix.rotationZ(p * Double.pi * 2).map { $0 as Any? }), ("transformOrigin", [w / 2, h / 2] as [Any?])])
        case "slide":
            return ViewProps([("transform", Matrix.translation((1 - p) * w, 0).map { $0 as Any? }), ("transformOrigin", [0.0, 0.0] as [Any?])])
        default:
            return ViewProps([("opacity", p >= 1 ? nil : p)])
        }
    }
}

// ============================================================================
// Explicit transitions
// ============================================================================

/**
 * One class for Fade/Slide/Scale/Rotation/Size transitions, Pulse and
 * TweenAnimationBuilder.
 *
 * props {
 *   kind: 'fade'|'slide'|'scale'|'rotation'|'size'|'pulse'|'tween',
 *   begin, end (numbers; slide uses [x, y] pairs), duration, curve,
 *   repeat, autoReverse, axis ('vertical'|'horizontal'), tweenType, alignment
 * }
 */
open class RenderTransition: RenderObject {
    private var controller: AnimationController?
    /** TweenAnimationBuilder: begin of the current run (animates to new ends). */
    private var tweenFrom: Double?

    private var kind: String? { props.s("kind") }

    open override func onAttach() {
        let ctl: AnimationController
        if let existing = controller {
            ctl = existing
        } else {
            ctl = AnimationController(props.d("duration") ?? 300)
            controller = ctl
            ctl.addListener { [weak self] in
                guard let self = self else { return }
                if self.kind == "size" { self.markNeedsLayout() } else { self.markNeedsPaint() }
            }
        }
        if let owner = owner { ctl.attach(owner) }
        start()
    }

    private func start() {
        guard let c = controller else { return }
        if kind == "pulse" {
            c.repeatAnimation(reverse: true)
            return
        }
        if jsTruthy(props["repeat"]) {
            c.repeatAnimation(reverse: jsTruthy(props["autoReverse"]))
        } else if jsTruthy(props["autoReverse"]) {
            c.forward(from: 0).then { [weak c] in c?.reverse() }
        } else {
            c.forward(from: 0)
        }
    }

    open override func didUpdate(_ old: Props) {
        guard let ctl = controller else { return }
        ctl.duration = props.d("duration") ?? 300
        if kind == "tween" && strictNotEqual(old["end"], props["end"]) {
            // TweenAnimationBuilder animates from the current value to the new end.
            tweenFrom = value()
            ctl.forward(from: 0)
        }
    }

    /** Current animated value in the begin..end range. */
    public func value() -> Double {
        let raw = controller?.value ?? 0
        let t = curveOf(props, kind == "pulse" ? Curves.easeInOut : Curves.linear)(raw)
        let begin = tweenFrom ?? numberOr(props["begin"], defaultBegin(kind))
        let end = numberOr(props["end"], defaultEnd(kind))
        return begin + (end - begin) * t
    }

    private func slideValue() -> (Double, Double) {
        let raw = controller?.value ?? 0
        let t = curveOf(props)(raw)
        let b = pairOf(props["begin"]) ?? (-1, 0)
        let e = pairOf(props["end"]) ?? (0, 0)
        return (b.0 + (e.0 - b.0) * t, b.1 + (e.1 - b.1) * t)
    }

    open override func performLayout(_ c: Constraints) {
        guard let child = child else {
            size = constrain(c, .zero)
            return
        }
        if kind == "size" {
            let factor = max(0, value())
            let horizontal = props.s("axis") == "horizontal"
            var inner = c
            if horizontal {
                inner.minWidth = 0
                inner.maxWidth = INF
            } else {
                inner.minHeight = 0
                inner.maxHeight = INF
            }
            child.layout(inner)
            let s = horizontal ? Size(width: child.size.width * factor, height: child.size.height) : Size(width: child.size.width, height: child.size.height * factor)
            size = constrain(c, s)
            // SizeTransition aligns the child at the centre of the axis (axisAlignment 0).
            child.offset = horizontal ? Vec(x: (size.width - child.size.width) / 2, y: 0) : Vec(x: 0, y: (size.height - child.size.height) / 2)
            return
        }
        child.layout(c)
        child.offset = .zero
        size = child.size
    }

    open override func viewKind() -> ViewKind? { .view }

    open override func viewProps() -> ViewProps {
        let w = size.width
        let h = size.height
        let center: [Any?] = [w / 2, h / 2]
        let origin: [Any?] = [0.0, 0.0]
        func m(_ x: Matrix4) -> [Any?] { x.map { $0 as Any? } }
        switch kind {
        case "fade":
            let o = max(0, min(1, value()))
            return ViewProps([("opacity", o >= 1 ? nil : o)])
        case "slide":
            let (x, y) = slideValue()
            return ViewProps([("transform", m(Matrix.translation(x * w, y * h))), ("transformOrigin", origin)])
        case "scale", "pulse":
            let s = value()
            return ViewProps([("transform", m(Matrix.scaling(s, s, 1))), ("transformOrigin", center)])
        case "rotation":
            return ViewProps([("transform", m(Matrix.rotationZ(value() * Double.pi * 2))), ("transformOrigin", center)])
        case "size":
            return ViewProps([("clip", true)])
        case "tween":
            let v = value()
            switch props.s("tweenType") ?? "opacity" {
            case "scale":
                return ViewProps([("transform", m(Matrix.scaling(v, v, 1))), ("transformOrigin", center)])
            case "rotation":
                return ViewProps([("transform", m(Matrix.rotationZ(v * Double.pi * 2))), ("transformOrigin", center)])
            case "translateX":
                return ViewProps([("transform", m(Matrix.translation(v, 0))), ("transformOrigin", origin)])
            case "translateY":
                return ViewProps([("transform", m(Matrix.translation(0, v))), ("transformOrigin", origin)])
            default:
                let o = max(0, min(1, v))
                return ViewProps([("opacity", o >= 1 ? nil : o)])
            }
        default:
            return ViewProps()
        }
    }

    open override func onDetach() {
        controller?.detach()
        controller?.stop()
    }
}

private func numberOr(_ v: Any?, _ fallback: Double) -> Double {
    if let n = jsNumber(v), n.isFinite { return n }
    return fallback
}

private func defaultBegin(_ kind: String?) -> Double { kind == "pulse" ? 1 : 0 }
private func defaultEnd(_ kind: String?) -> Double { kind == "pulse" ? 1.05 : 1 }

/**
 * StaggeredAnimation: a column whose children fade and rise in one after
 * another. props { duration (total), staggerDelay, curve }
 */
open class RenderStaggered: RenderObject {
    private var controller: AnimationController?

    open override func onAttach() {
        let ctl: AnimationController
        if let existing = controller {
            ctl = existing
        } else {
            ctl = AnimationController(props.d("duration") ?? 1000)
            controller = ctl
            ctl.addListener { [weak self] in
                guard let self = self else { return }
                for c in self.children { c.markNeedsPaint() }
            }
        }
        if let owner = owner { ctl.attach(owner) }
        ctl.forward(from: 0)
    }

    public func itemProgress(_ index: Int) -> Double {
        let count = children.count
        let total = props.d("duration") ?? 1000
        let delay = props.d("staggerDelay") ?? 100
        let totalDelay = delay * Double(count - 1)
        let start = max(0, min(1, (delay * Double(index)) / total))
        let end = max(0, min(1, (delay * Double(index) + (total - totalDelay)) / total))
        let curve = interval(start, end, curveOf(props, Curves.easeOut))
        return curve(controller?.value ?? 0)
    }

    open override func performLayout(_ c: Constraints) {
        var y = 0.0
        var w = 0.0
        for ch in children {
            ch.layout(Constraints(minWidth: 0, maxWidth: c.maxWidth, minHeight: 0, maxHeight: INF))
            ch.offset = Vec(x: 0, y: y)
            y += ch.size.height
            w = max(w, ch.size.width)
        }
        size = constrain(c, Size(width: w, height: y))
    }

    open override func onDetach() {
        controller?.detach()
        controller?.stop()
    }
}

/** One staggered child: fades in and slides up 20px. */
open class RenderStaggerItem: RenderProxy {
    open override func viewKind() -> ViewKind? { .view }

    open override func viewProps() -> ViewProps {
        let parent = self.parent
        let index = parent?.children.firstIndex { $0 === self } ?? 0
        let v = (parent as? RenderStaggered)?.itemProgress(index) ?? 1
        let o = max(0, min(1, v))
        return ViewProps([
            ("opacity", o >= 1 ? nil : o),
            ("transform", v >= 1 ? nil : Matrix.translation(0, 20 * (1 - v)).map { $0 as Any? }),
            ("transformOrigin", [0.0, 0.0] as [Any?]),
        ])
    }
}

/** Shimmer: a sweeping highlight gradient masked onto the child (srcATop). */
open class RenderShimmer: RenderShaderMask {
    private var controller: AnimationController?

    open override func onAttach() {
        let ctl: AnimationController
        if let existing = controller {
            ctl = existing
        } else {
            ctl = AnimationController(props.d("duration") ?? 1500)
            controller = ctl
            ctl.addListener { [weak self] in self?.markNeedsPaint() }
        }
        if let owner = owner { ctl.attach(owner) }
        ctl.repeatAnimation(reverse: false)
    }

    open override func viewProps() -> ViewProps {
        let v = -1 + 3 * (controller?.value ?? 0) // Tween(-1, 2)
        let base: Color = colorProp(props["baseColor"]) ?? 0xFFE0_E0E0
        let highlight: Color = colorProp(props["highlightColor"]) ?? 0xFFF5_F5F5
        func clamp01(_ x: Double) -> Double { max(0, min(1, x)) }
        let gradient = Gradient(
            kind: .linear,
            colors: [base, highlight, base],
            stops: [clamp01(v - 0.3), clamp01(v), clamp01(v + 0.3)],
            begin: Alignment(x: -1, y: 0),
            end: Alignment(x: 1, y: 0)
        )
        return ViewProps([("shaderMask", gradient)])
    }

    open override func onDetach() {
        controller?.detach()
        controller?.stop()
    }
}

/** AnimatedGradient: a decorated box whose gradient stops rotate continuously. */
open class RenderAnimatedGradient: RenderDecoratedBox {
    private var controller: AnimationController?

    open override func onAttach() {
        let ctl: AnimationController
        if let existing = controller {
            ctl = existing
        } else {
            ctl = AnimationController(props.d("duration") ?? 2000)
            controller = ctl
            ctl.addListener { [weak self] in self?.markNeedsPaint() }
        }
        if let owner = owner { ctl.attach(owner) }
        ctl.repeatAnimation(reverse: false)
    }

    open override func viewProps() -> ViewProps {
        let colors: [Color] = asArray(props["colors"]).map { $0.map { colorProp($0) ?? 0 } }
            ?? [0xFF21_96F3, 0xFF9C_27B0, 0xFFE9_1E63, 0xFF21_96F3]
        let shift = controller?.value ?? 0
        let stops = colors.indices.map { i -> Double in
            ((colors.count > 1 ? Double(i) / Double(colors.count - 1) : 0) + shift).truncatingRemainder(dividingBy: 1)
        }.sorted()
        var d = props["decoration"] as? BoxDecoration ?? BoxDecoration()
        d.gradients = [Gradient(kind: .linear, colors: colors, stops: stops, begin: Alignment(x: -1, y: -1), end: Alignment(x: 1, y: 1))]
        return decorationViewProps(d, size.width, size.height)
    }

    open override func onDetach() {
        controller?.detach()
        controller?.stop()
    }
}

// ============================================================================
// CSS @keyframes
// ============================================================================

public struct ParsedFrame {
    public var offset: Double
    public var opacity: Double?
    public var transform: Matrix4?
    public var background: Color?
}

/**
 * CSS keyframe animation on an element: animates opacity, transform and
 * background colour between the stylesheet's `@keyframes` frames.
 * props { frames: [Keyframe], duration, delay, iterations (-1 = infinite),
 *         direction, fillMode, timing, playState }
 */
open class RenderKeyframes: RenderProxy {
    private var controller: AnimationController?
    private var frames: [ParsedFrame] = []
    private var iteration = 0
    private var delayTimer: Int?

    open override func initialize(_ props: Props) {
        super.initialize(props)
        frames = parseFrames(keyframesOf(props["frames"]))
    }

    open override func didUpdate(_ old: Props) {
        if !deepEqual(old["frames"], props["frames"]) { frames = parseFrames(keyframesOf(props["frames"])) }
        if strictNotEqual(old["playState"], props["playState"]), let ctl = controller {
            if props.s("playState") == "paused" { ctl.stop() } else { run() }
        }
    }

    open override func onAttach() {
        let ctl: AnimationController
        if let existing = controller {
            ctl = existing
        } else {
            ctl = AnimationController(props.d("duration") ?? 1000)
            controller = ctl
            ctl.addListener { [weak self] in self?.markNeedsPaint() }
            ctl.addStatusListener { [weak self] s in
                if s == .completed || s == .dismissed { self?.onIterationEnd() }
            }
        }
        if let owner = owner { ctl.attach(owner) }
        let delay = props.d("delay") ?? 0
        if delay > 0, let o = owner {
            delayTimer = o.platform.setTimeout({ [weak self] in
                guard let self = self else { return }
                self.delayTimer = nil
                self.run()
            }, delay)
        } else {
            run()
        }
    }

    private func direction(_ iteration: Int) -> String {
        switch props.s("direction") {
        case "reverse": return "reverse"
        case "alternate": return iteration % 2 == 0 ? "forward" : "reverse"
        case "alternate-reverse": return iteration % 2 == 0 ? "reverse" : "forward"
        default: return "forward"
        }
    }

    private func run() {
        guard let ctl = controller, props.s("playState") != "paused" else { return }
        ctl.duration = max(1, props.d("duration") ?? 1000)
        if direction(iteration) == "forward" { ctl.forward(from: 0) } else { ctl.reverse(from: 1) }
    }

    private func onIterationEnd() {
        iteration += 1
        let total = props.d("iterations") ?? 1
        if total == -1 || Double(iteration) < total { run() } else { markNeedsPaint() }
    }

    private func finished() -> Bool {
        let total = props.d("iterations") ?? 1
        return total != -1 && Double(iteration) >= total
    }

    open override func viewKind() -> ViewKind? { .view }

    open override func viewProps() -> ViewProps {
        if frames.isEmpty { return ViewProps() }
        let fill = props.s("fillMode") ?? "none"
        if finished() && fill != "forwards" && fill != "both" { return ViewProps() }
        let t = curveByName(props.s("timing"), Curves.ease)(controller?.value ?? 0)
        let sampled = sampleFrames(frames, t)
        let out = ViewProps()
        if let o = sampled.opacity { out["opacity"] = o }
        if let m = sampled.transform {
            out["transform"] = m.map { $0 as Any? }
            out["transformOrigin"] = [size.width / 2, size.height / 2] as [Any?]
        }
        if let b = sampled.background { out["background"] = b }
        return out
    }

    open override func onDetach() {
        if let timer = delayTimer, let o = owner { o.platform.clearTimeout(timer) }
        controller?.detach()
        controller?.stop()
    }
}

/** The `frames` prop: [Keyframe]s (or their JSON form `{offset, styles}`). */
private func keyframesOf(_ v: Any?) -> [Keyframe] {
    guard let list = asArray(v) else { return [] }
    return list.compactMap { e -> Keyframe? in
        if let k = flattenOptional(e) as? Keyframe { return k }
        if let m = asMap(e), let offset = jsNumber(m["offset"]) { return Keyframe(offset: offset, styles: asMap(m["styles"]) ?? JSONObject()) }
        return nil
    }
}

func parseFrames(_ frames: [Keyframe]) -> [ParsedFrame] {
    let parsed = frames.map { f -> ParsedFrame in
        let s = CSSParser.parse(f.styles)
        var m: Matrix4? = s.transform
        if let tr = s.translate { m = Matrix.multiply(m ?? Matrix.identity(), Matrix.translation(tr.dx, tr.dy)) }
        if let rot = s.rotate { m = Matrix.multiply(m ?? Matrix.identity(), Matrix.rotationZ(rot * Double.pi / 180)) }
        if let sc = s.scale { m = Matrix.multiply(m ?? Matrix.identity(), Matrix.scaling(sc, sc, 1)) }
        return ParsedFrame(offset: f.offset, opacity: s.opacity, transform: m, background: s.backgroundColor)
    }
    // A stable sort by offset (Array.prototype.sort is stable).
    return parsed.enumerated().sorted { a, b in
        a.element.offset != b.element.offset ? a.element.offset < b.element.offset : a.offset < b.offset
    }.map { $0.element }
}

struct SampledFrame {
    var opacity: Double?
    var transform: Matrix4?
    var background: Color?
}

func sampleFrames(_ frames: [ParsedFrame], _ t: Double) -> SampledFrame {
    func pick<V>(_ get: (ParsedFrame) -> V?, _ lerp: (V, V, Double) -> V) -> V? {
        let withKey = frames.filter { get($0) != nil }
        if withKey.isEmpty { return nil }
        if t <= withKey[0].offset { return get(withKey[0]) }
        for i in 0..<(withKey.count - 1) {
            let a = withKey[i]
            let b = withKey[i + 1]
            if t >= a.offset && t <= b.offset {
                let local = b.offset > a.offset ? (t - a.offset) / (b.offset - a.offset) : 1
                return lerp(get(a)!, get(b)!, local)
            }
        }
        return get(withKey[withKey.count - 1])
    }
    return SampledFrame(
        opacity: pick({ $0.opacity }, { a, b, l in a + (b - a) * l }),
        transform: pick({ $0.transform }, { a, b, l in Matrix.lerp(a, b, l) }),
        background: pick({ $0.background }, { a, b, l in lerpColor(a, b, l) })
    )
}

// ============================================================================
// Hero
// ============================================================================

/**
 * Hero: when a hero with the same tag appears at a new place on screen (a
 * re-render moved it, or a new screen replaced the old one), it flies from
 * its previous global rect to the new one (fastOutSlowIn, 300 ms).
 */
open class RenderHero: RenderProxy, HeroFlight {
    private var controller: AnimationController?
    private var fromRect: Rect?

    /** Called by the owner's hero registry after layout of a frame. */
    public func flyFrom(_ rect: Rect, _ owner: RenderOwner) {
        fromRect = rect
        let ctl: AnimationController
        if let existing = controller {
            ctl = existing
        } else {
            ctl = AnimationController(300)
            controller = ctl
            ctl.addListener { [weak self] in self?.markNeedsPaint() }
        }
        ctl.attach(owner)
        ctl.forward(from: 0).then { [weak self] in
            self?.fromRect = nil
            self?.markNeedsPaint()
        }
    }

    open override func viewKind() -> ViewKind? { .view }

    open override func viewProps() -> ViewProps {
        guard let from = fromRect, let o = owner, let ctl = controller else { return ViewProps([("transform", nil)]) }
        let here = o.compositor.globalFrame(self)
        let t = Curves.fastOutSlowIn(ctl.value)
        let sx = size.width > 0 ? from.width / size.width : 1
        let sy = size.height > 0 ? from.height / size.height : 1
        let scaleX = sx + (1 - sx) * t
        let scaleY = sy + (1 - sy) * t
        let dx = (from.x - here.x) * (1 - t)
        let dy = (from.y - here.y) * (1 - t)
        let m = Matrix.multiply(Matrix.translation(dx, dy), Matrix.scaling(scaleX, scaleY, 1))
        return ViewProps([("transform", m.map { $0 as Any? }), ("transformOrigin", [0.0, 0.0] as [Any?])])
    }

    open override func onDetach() {
        controller?.detach()
        controller?.stop()
    }
}
