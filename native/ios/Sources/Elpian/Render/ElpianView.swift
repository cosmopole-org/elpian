#if canImport(UIKit)
import UIKit
import CoreImage
#if !ELPIAN_SINGLE_MODULE
import ElpianCore
#endif

/** Async image loading (the platform's image cache). */
public protocol ImageSource: AnyObject {
    /** Load [src]; [callback] runs on the main thread with the image, or nil on failure. */
    func load(_ src: String, _ callback: @escaping (UIImage?) -> Void)
}

/** What views need from the renderer. */
protocol ViewHost: AnyObject {
    var scale: CGFloat { get }
    var surface: ElpianSurfaceView { get }
    var images: ImageSource { get }
    func emit(_ event: ViewEvent)
}

/** Hit testing in paint order, through each Elpian child's transform (Flutter's inverse-matrix hit test). */
enum ElpianHitTest {
    /** The subviews of [container] top-most first: higher zIndex, then later siblings. */
    static func paintOrderTopDown(_ container: UIView) -> [UIView] {
        let subs = container.subviews
        return subs.indices.sorted { a, b in
            let za = subs[a].layer.zPosition
            let zb = subs[b].layer.zPosition
            return za != zb ? za > zb : a > b
        }.map { subs[$0] }
    }

    /** The deepest view under [point] (in [container]'s coordinates) among its children, or nil. */
    static func children(of container: UIView, _ point: CGPoint, _ event: UIEvent?) -> UIView? {
        for sub in paintOrderTopDown(container) {
            if sub.isHidden || sub.alpha < 0.01 || !sub.isUserInteractionEnabled { continue }
            if let ev = sub as? ElpianView {
                guard let local = ev.localPoint(fromParent: point) else { continue }
                if let hit = ev.hitTest(local, with: event) { return hit }
            } else if let hit = sub.hitTest(container.convert(point, to: sub), with: event) {
                return hit
            }
        }
        return nil
    }
}

/**
 * The platform-owned root of one surface (view id 0). Hosts add it to their
 * hierarchy; the renderer creates every top-level view inside it. It clips
 * like the web host's root (overflow: hidden) and owns the touch router that
 * feeds every view's gesture recognizer.
 */
public final class ElpianSurfaceView: UIView {
    /** Called with the new size (points) whenever the surface is resized. */
    public var onSizeChanged: ((CGSize) -> Void)?
    /** Called when the safe area insets change. */
    public var onInsetsChanged: (() -> Void)?
    /** Called when the trait collection (dark mode, content size category) changes. */
    public var onTraitsChanged: (() -> Void)?

    let router = TouchRouter()
    private var lastSize: CGSize = .zero

    public override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        addGestureRecognizer(router)
        router.surface = self
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /** Safe-area insets in points (top, right, bottom, left). */
    public var safeInsets: UIEdgeInsets { safeAreaInsets }

    public override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastSize {
            lastSize = bounds.size
            onSizeChanged?(bounds.size)
        }
    }

    public override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        onInsetsChanged?()
    }

    public override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        onTraitsChanged?()
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, isUserInteractionEnabled, alpha >= 0.01, bounds.contains(point) else { return nil }
        return ElpianHitTest.children(of: self, point, event)
    }
}

/** The view a box's leaf and children live in: clipped to the box's shape when asked. */
final class ElpianContentView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        ElpianHitTest.children(of: self, point, event)
    }
}

/**
 * One Elpian view (ElpianView.kt): an absolutely positioned box that paints
 * its decoration itself (a [DecorationLayer] under the content), hosts its
 * leaf content (paragraph, image, control…) at the bottom of its content view
 * and its child views above it, clipping the children (not its own shadow)
 * when asked — Flutter's Container + ClipRRect.
 *
 * The layer's anchor is its top-left corner, so a Matrix4 applies about the
 * frame origin exactly as Flutter's `Transform` (with `transformOrigin`
 * folded in by the renderer), including skew and perspective; hit testing
 * maps points through the inverse of that projective map.
 */
public final class ElpianView: UIView {
    public let viewId: Int
    public let kind: ViewKind
    weak var host: ViewHost?

    /** The frame in logical px (points) relative to the parent view. */
    private(set) var frameValues: [Double] = [0, 0, 0, 0]

    /** Where the leaf and the children live (clipped when [clip]). */
    let contentView = ElpianContentView(frame: .zero)
    private var childHostOverride: UIView?
    /** Where child views are inserted: the content view, or a scroll container. */
    var childHost: UIView {
        get { childHostOverride ?? contentView }
        set { childHostOverride = newValue === contentView ? nil : newValue }
    }
    /** The leaf content (bottom of [contentView]), if this kind has one. */
    var leaf: UIView?

    var decoration: DecorationLayer?
    var clip = false
    var radius: BorderRadius?
    var oval = false
    var zIndex: Double = 0 {
        didSet { layer.zPosition = CGFloat(zIndex) }
    }
    var pointerEventsNone = false
    var hitOpaque = false
    var gestures: GestureRecognizer?
    var role: String?

    private var transformMatrix: Matrix4?
    private var transformOrigin: [Double]?
    /** The inverse of the projective map from local to parent coordinates (nil = translation only). */
    private var inverseMap: [Double]?
    /** Gesture-driven offsets (Dismissible), in points. */
    var gestureDx: CGFloat = 0
    var gestureDy: CGFloat = 0

    private let clipMask = CAShapeLayer()
    private var rippleContainer: CALayer?
    private var hover: UIHoverGestureRecognizer?
    private var pointerInteraction: AnyObject?
    var cursor: String?

    init(id: Int, kind: ViewKind, host: ViewHost) {
        viewId = id
        self.kind = kind
        self.host = host
        super.init(frame: .zero)
        layer.anchorPoint = .zero
        clipsToBounds = false
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        contentView.frame = bounds
        addSubview(contentView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var scale: CGFloat { host?.scale ?? UIScreen.main.scale }

    // ---------------------------------------------------------------------
    // Frame and transform
    // ---------------------------------------------------------------------

    func setFrame(_ f: [Double]) {
        frameValues = Array(f.prefix(4))
        while frameValues.count < 4 { frameValues.append(0) }
        let w = CGFloat(max(0, frameValues[2]))
        let h = CGFloat(max(0, frameValues[3]))
        let sizeChanged = bounds.size != CGSize(width: w, height: h)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bounds = CGRect(x: 0, y: 0, width: w, height: h)
        layer.position = CGPoint(x: frameValues[0], y: frameValues[1])
        contentView.frame = bounds
        leaf?.frame = contentView.bounds
        if sizeChanged {
            decoration?.layout(for: bounds.size, scale: scale)
            updateClip()
            updateRippleMask()
            effects?.sizeChanged()
            backdrop?.sizeChanged()
        }
        CATransaction.commit()
    }

    func setTransform(_ m: Matrix4?, _ origin: [Double]?) {
        transformMatrix = m
        transformOrigin = origin
        applyTransform()
    }

    func applyTransform() {
        var mm: Matrix4 = Matrix.identity()
        if let m = transformMatrix, !Matrix.isIdentity(m) {
            if let o = transformOrigin, o.count >= 2 { mm = Matrix.aboutOrigin(m, o[0], o[1]) } else { mm = m }
        }
        if gestureDx != 0 || gestureDy != 0 {
            mm = Matrix.multiply(Matrix.translation(Double(gestureDx), Double(gestureDy)), mm)
        }
        layer.transform = ElpianView.caTransform(mm)
        let affineTranslationOnly = abs(mm[0] - 1) < 1e-12 && abs(mm[1]) < 1e-12 && abs(mm[4]) < 1e-12 && abs(mm[5] - 1) < 1e-12
            && abs(mm[3]) < 1e-12 && abs(mm[7]) < 1e-12 && abs(mm[15] - 1) < 1e-12
        if affineTranslationOnly {
            inverseMap = [1, 0, -mm[12], 0, 1, -mm[13], 0, 0, 1]
        } else {
            inverseMap = PaintMath.invert3(PaintMath.projective(mm))
        }
    }

    /** Flutter's column-major storage reads straight into CATransform3D's row-vector fields. */
    static func caTransform(_ s: Matrix4) -> CATransform3D {
        var t = CATransform3DIdentity
        t.m11 = CGFloat(s[0]); t.m12 = CGFloat(s[1]); t.m13 = CGFloat(s[2]); t.m14 = CGFloat(s[3])
        t.m21 = CGFloat(s[4]); t.m22 = CGFloat(s[5]); t.m23 = CGFloat(s[6]); t.m24 = CGFloat(s[7])
        t.m31 = CGFloat(s[8]); t.m32 = CGFloat(s[9]); t.m33 = CGFloat(s[10]); t.m34 = CGFloat(s[11])
        t.m41 = CGFloat(s[12]); t.m42 = CGFloat(s[13]); t.m43 = CGFloat(s[14]); t.m44 = CGFloat(s[15])
        return t
    }

    /** A point in the parent's coordinates → this view's local coordinates (nil when the map is singular). */
    func localPoint(fromParent p: CGPoint) -> CGPoint? {
        let x = Double(p.x) - frameValues[0]
        let y = Double(p.y) - frameValues[1]
        guard let inv = inverseMap else {
            if transformMatrix == nil && gestureDx == 0 && gestureDy == 0 { return CGPoint(x: x, y: y) }
            return nil
        }
        let (lx, ly) = PaintMath.apply3(inv, x, y)
        return CGPoint(x: lx, y: ly)
    }

    // ---------------------------------------------------------------------
    // Clip
    // ---------------------------------------------------------------------

    func updateClip() {
        if !clip {
            contentView.layer.mask = nil
            contentView.clipsToBounds = false
            return
        }
        let radii = oval ? nil : PaintMath.radii(radius, Double(bounds.width), Double(bounds.height))
        if radii == nil && !oval {
            contentView.layer.mask = nil
            contentView.clipsToBounds = true
            return
        }
        contentView.clipsToBounds = false
        clipMask.frame = contentView.bounds
        clipMask.path = Paints.shapePath(contentView.bounds, radii, oval)
        contentView.layer.mask = clipMask
    }

    /** The box's outline in local coordinates. */
    func shapePath() -> CGPath {
        Paints.shapePath(bounds, oval ? nil : PaintMath.radii(radius, Double(bounds.width), Double(bounds.height)), oval)
    }

    // ---------------------------------------------------------------------
    // Decoration
    // ---------------------------------------------------------------------

    func ensureDecoration() -> DecorationLayer {
        if let d = decoration { return d }
        let d = DecorationLayer()
        layer.insertSublayer(d, at: 0)
        decoration = d
        return d
    }

    func removeDecoration() {
        decoration?.removeFromSuperlayer()
        decoration = nil
    }

    // ---------------------------------------------------------------------
    // Effects: filters, shader masks, blend modes, backdrop filters
    // ---------------------------------------------------------------------

    private(set) var effects: EffectRenderer?
    private(set) var backdrop: BackdropRenderer?
    private var filter: Filter?
    var shaderMask: Gradient? {
        didSet { updateEffects() }
    }

    func setEffects(_ filter: Filter?, _ blendMode: String?) {
        self.filter = filter
        layer.compositingFilter = Paints.caCompositingFilter(blendMode)
        updateEffects()
    }

    private func updateEffects() {
        let needs = (filter.map { !$0.isEmpty } ?? false) || shaderMask != nil
        if needs {
            let e = effects ?? EffectRenderer(self)
            effects = e
            e.filter = filter
            e.shaderMask = shaderMask
            e.start()
        } else {
            effects?.stop()
            effects = nil
        }
    }

    func setBackdrop(_ f: Filter?) {
        if let f = f {
            let b = backdrop ?? BackdropRenderer(self)
            backdrop = b
            b.filter = f
            b.start()
        } else {
            backdrop?.stop()
            backdrop = nil
        }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            gestures?.detached()
            effects?.pause()
            backdrop?.pause()
        } else {
            effects?.start()
            backdrop?.start()
        }
    }

    // ---------------------------------------------------------------------
    // Ripple (Material ink) above the content
    // ---------------------------------------------------------------------

    var rippleColor: Color? {
        didSet { if oldValue != rippleColor { updateRippleMask() } }
    }
    private var activeRipple: CAShapeLayer?

    func updateRippleMask() {
        guard rippleColor != nil else {
            rippleContainer?.removeFromSuperlayer()
            rippleContainer = nil
            return
        }
        let c = rippleContainer ?? {
            let l = CALayer()
            l.zPosition = 10_000
            layer.addSublayer(l)
            rippleContainer = l
            return l
        }()
        c.frame = bounds
        let mask = CAShapeLayer()
        mask.path = shapePath()
        c.mask = mask
    }

    /** Material ink: a circle spreading from [point] over the box. */
    func startRipple(at point: CGPoint) {
        guard let color = rippleColor, let c = rippleContainer else { return }
        activeRipple?.removeFromSuperlayer()
        let w = bounds.width, h = bounds.height
        let far = max(hypot(point.x, point.y), hypot(w - point.x, point.y), hypot(point.x, h - point.y), hypot(w - point.x, h - point.y))
        let l = CAShapeLayer()
        l.fillColor = Paints.cgColor(color)
        l.frame = c.bounds
        l.path = UIBezierPath(arcCenter: point, radius: far, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
        c.addSublayer(l)
        let grow = CABasicAnimation(keyPath: "transform")
        var from = CATransform3DMakeTranslation(point.x, point.y, 0)
        from = CATransform3DScale(from, 0.05, 0.05, 1)
        from = CATransform3DTranslate(from, -point.x, -point.y, 0)
        grow.fromValue = NSValue(caTransform3D: from)
        grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        grow.duration = 0.3
        grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
        l.add(grow, forKey: "grow")
        activeRipple = l
    }

    func stopRipple() {
        guard let l = activeRipple else { return }
        activeRipple = nil
        CATransaction.begin()
        CATransaction.setCompletionBlock { l.removeFromSuperlayer() }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.2
        l.opacity = 0
        l.add(fade, forKey: "fade")
        CATransaction.commit()
    }

    // ---------------------------------------------------------------------
    // Cursor (pointer interactions on iPad) and hover
    // ---------------------------------------------------------------------

    func applyCursor(_ name: String?) {
        cursor = name
        if let p = pointerInteraction as? UIPointerInteraction {
            removeInteraction(p)
            pointerInteraction = nil
        }
        guard let name = name, !name.isEmpty, name != "default", name != "auto" else { return }
        let p = UIPointerInteraction(delegate: PointerStyles.shared)
        addInteraction(p)
        pointerInteraction = p
    }

    func setHoverEnabled(_ on: Bool) {
        if on, hover == nil {
            let g = UIHoverGestureRecognizer(target: self, action: #selector(onHover(_:)))
            addGestureRecognizer(g)
            hover = g
        } else if !on, let g = hover {
            removeGestureRecognizer(g)
            hover = nil
        }
    }

    @objc private func onHover(_ g: UIHoverGestureRecognizer) {
        gestures?.onHover(g)
    }

    // ---------------------------------------------------------------------
    // Input
    // ---------------------------------------------------------------------

    /** Whether a touch inside the box with no child taking it lands on this view. */
    private var takesTouches: Bool {
        if hitOpaque { return true }
        guard let g = gestures else { return false }
        return !g.kinds.isEmpty || g.ripple != nil
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if pointerEventsNone || isHidden || alpha < 0.01 || !isUserInteractionEnabled { return nil }
        let inside = point.x >= 0 && point.y >= 0 && point.x <= bounds.width && point.y <= bounds.height
        if clip && !inside { return nil }
        if let hit = ElpianHitTest.children(of: contentView, convert(point, to: contentView), event) { return hit }
        return inside && takesTouches ? self : nil
    }

    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        hitTest(point, with: event) != nil
    }

    var focusable = false

    public override var canBecomeFirstResponder: Bool { focusable }

    public override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { gestures?.onFocus(true) }
        return ok
    }

    public override func resignFirstResponder() -> Bool {
        let was = isFirstResponder
        let ok = super.resignFirstResponder()
        if ok && was { gestures?.onFocus(false) }
        return ok
    }

    public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for p in presses where gestures?.onKey("keydown", p) == true { handled = true }
        if !handled { super.pressesBegan(presses, with: event) }
    }

    public override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for p in presses where gestures?.onKey("keyup", p) == true { handled = true }
        if !handled { super.pressesEnded(presses, with: event) }
    }

    // ---------------------------------------------------------------------
    // Accessibility
    // ---------------------------------------------------------------------

    func updateAccessibility(label: String?) {
        accessibilityLabel = label
        var traits: UIAccessibilityTraits = []
        switch role {
        case "button", "menuitem", "tab": traits.insert(.button)
        case "link": traits.insert(.link)
        case "image", "img": traits.insert(.image)
        case "heading", "header": traits.insert(.header)
        case "slider": traits.insert(.adjustable)
        case "textbox", "textfield": traits.insert(.searchField)
        default: break
        }
        if gestures?.has("tap") == true { traits.insert(.button) }
        accessibilityTraits = traits
        isAccessibilityElement = label != nil || !traits.isEmpty
    }

    public override func accessibilityActivate() -> Bool {
        guard gestures?.has("tap") == true else { return false }
        gestures?.accessibilityTap()
        return true
    }
}

/** Cursor names → pointer styles (iPad pointer). */
final class PointerStyles: NSObject, UIPointerInteractionDelegate {
    static let shared = PointerStyles()

    func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
        guard let view = interaction.view as? ElpianView else { return nil }
        switch view.cursor {
        case "none":
            return UIPointerStyle.hidden()
        case "text", "vertical-text":
            return UIPointerStyle(shape: .verticalBeam(length: 20), constrainedAxis: nil)
        case "pointer", "click", "grab", "grabbing":
            return UIPointerStyle(effect: .highlight(UITargetedPreview(view: view)), shape: nil)
        default:
            return UIPointerStyle(effect: .automatic(UITargetedPreview(view: view)), shape: nil)
        }
    }
}

// ---------------------------------------------------------------------------
// Filters and shader masks
// ---------------------------------------------------------------------------

/**
 * CSS `filter` and `ShaderMask` on a view: the view's own drawing (decoration
 * and content) is captured each frame while the effect is live, the shader
 * mask composited over it source-atop, then the colour matrix, blur and drop
 * shadow applied with Core Image (RenderEffect on Android). The live layers
 * are made transparent and the filtered bitmap shown in their place.
 */
final class EffectRenderer {
    weak var view: ElpianView?
    var filter: Filter?
    var shaderMask: Gradient?
    private let output = CALayer()
    private var link: CADisplayLink?

    init(_ view: ElpianView) {
        self.view = view
        output.zPosition = 20_000
        output.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "frame": NSNull()]
        view.layer.addSublayer(output)
    }

    func start() {
        guard let v = view, v.window != nil else { return }
        if link == nil {
            let l = CADisplayLink(target: DisplayLinkProxy { [weak self] in self?.render() }, selector: #selector(DisplayLinkProxy.tick))
            l.add(to: .main, forMode: .common)
            link = l
        }
        render()
    }

    func pause() {
        link?.invalidate()
        link = nil
    }

    func stop() {
        pause()
        output.removeFromSuperlayer()
        setLiveOpacity(1)
    }

    func sizeChanged() { render() }

    private func setLiveOpacity(_ o: Float) {
        guard let v = view else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        v.decoration?.opacity = o
        v.contentView.layer.opacity = o
        CATransaction.commit()
    }

    /** How far the effect reaches past the bounds (blur and drop shadow). */
    private func reach() -> CGFloat {
        var r = 0.0
        if let b = filter?.blur, b > 0 { r += 3 * b }
        if let s = filter?.dropShadow { r += abs(s.dx) + abs(s.dy) + 3 * PaintMath.sigma(s.blur) }
        // Outer shadows painted by the decoration.
        if let d = view?.decoration { r = max(r, Double(-d.frame.minX)) + (r > 0 ? Double(-d.frame.minX) : 0) }
        return CGFloat(r.rounded(.up))
    }

    func render() {
        guard let v = view else { return }
        let size = v.bounds.size
        if size.width <= 0 || size.height <= 0 { return }
        let scale = v.scale
        let pad = reach()
        let rect = CGRect(x: -pad, y: -pad, width: size.width + 2 * pad, height: size.height + 2 * pad)
        let pw = Int((rect.width * scale).rounded(.up))
        let ph = Int((rect.height * scale).rounded(.up))
        guard let ctx = Raster.context(pw, ph, gray: false) else { return }
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: pad, y: pad)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        output.isHidden = true
        v.decoration?.opacity = 1
        v.contentView.layer.opacity = 1
        let ripple = v.layer.sublayers?.filter { $0.zPosition == 10_000 } ?? []
        for r in ripple { r.isHidden = true }
        // The view's own layer tree, without its position / transform.
        if let d = v.decoration {
            ctx.saveGState()
            ctx.translateBy(x: d.frame.minX, y: d.frame.minY)
            d.render(in: ctx)
            ctx.restoreGState()
        }
        v.contentView.layer.render(in: ctx)
        for r in ripple { r.isHidden = false }
        CATransaction.commit()
        if let g = shaderMask {
            ctx.saveGState()
            ctx.setBlendMode(.sourceAtop)
            ctx.clip(to: CGRect(origin: .zero, size: size))
            Paints.drawGradient(ctx, g, CGRect(origin: .zero, size: size))
            ctx.restoreGState()
        }
        guard let captured = ctx.makeImage() else { return }
        var image = CIImage(cgImage: captured)
        let extent = image.extent
        if let b = filter?.blur, b > 0 { image = Paints.blur(image, sigma: b * Double(scale)).cropped(to: extent) }
        if let m = PaintMath.colorMatrix(filter) { image = Paints.applyColorMatrix(image, m) }
        if let s = filter?.dropShadow {
            let colored = CIImage(color: CIColor(cgColor: Paints.cgColor(s.color))).cropped(to: extent)
            var shadow = colored.applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: image])
            shadow = Paints.blur(shadow, sigma: PaintMath.sigma(s.blur) * Double(scale))
            // Core Image is y-up: a positive dy moves the shadow down the screen.
            shadow = shadow.transformed(by: CGAffineTransform(translationX: CGFloat(s.dx) * scale, y: -CGFloat(s.dy) * scale))
            image = image.composited(over: shadow).cropped(to: extent)
        }
        guard let out = Paints.ciContext.createCGImage(image, from: extent) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        output.frame = rect
        output.contentsScale = scale
        output.contents = out
        output.isHidden = false
        v.decoration?.opacity = 0
        v.contentView.layer.opacity = 0
        CATransaction.commit()
    }
}

/**
 * CSS `backdrop-filter`: what is painted behind the view (everything drawn
 * before it in paint order) is snapshotted each frame at reduced resolution,
 * blurred and colour-filtered with Core Image and shown clipped to the view's
 * shape under its decoration (Backdrop in ElpianView.kt).
 */
final class BackdropRenderer {
    weak var view: ElpianView?
    var filter: Filter?
    private let output = CALayer()
    private let mask = CAShapeLayer()
    private var link: CADisplayLink?
    private var capturing = false

    init(_ view: ElpianView) {
        self.view = view
        output.zPosition = -10_000
        output.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "frame": NSNull()]
        output.mask = mask
        view.layer.insertSublayer(output, at: 0)
    }

    func start() {
        guard let v = view, v.window != nil else { return }
        if link == nil {
            let l = CADisplayLink(target: DisplayLinkProxy { [weak self] in self?.render() }, selector: #selector(DisplayLinkProxy.tick))
            l.add(to: .main, forMode: .common)
            link = l
        }
        render()
    }

    func pause() {
        link?.invalidate()
        link = nil
    }

    func stop() {
        pause()
        output.removeFromSuperlayer()
    }

    func sizeChanged() { render() }

    /** This view and every view painted after it, which the snapshot must not show. */
    private func paintedAfter(_ v: ElpianView, _ root: UIView) -> [CALayer] {
        var out: [CALayer] = [v.layer]
        var node: UIView = v
        while let parent = node.superview, node !== root {
            let order = ElpianHitTest.paintOrderTopDown(parent).reversed().map { $0 }
            if let i = order.firstIndex(where: { $0 === node }) {
                for later in order[(i + 1)...] where !later.isHidden { out.append(later.layer) }
            }
            node = parent
        }
        return out
    }

    func render() {
        guard !capturing, let v = view, let host = v.host, let f = filter else { return }
        let root = host.surface
        let size = v.bounds.size
        if size.width <= 0 || size.height <= 0 { return }
        let scale = v.scale
        let sigma = Double(scale) * (f.blur ?? 0)
        let down = sigma > 2 ? CGFloat(max(0.125, min(0.5, 4 / sigma))) : 1
        let px = scale * down
        let bw = max(1, Int((size.width * px).rounded(.up)))
        let bh = max(1, Int((size.height * px).rounded(.up)))
        guard let ctx = Raster.context(bw, bh, gray: false) else { return }
        let origin = v.convert(CGPoint.zero, to: root)
        ctx.scaleBy(x: px, y: px)
        ctx.translateBy(x: -origin.x, y: -origin.y)
        capturing = true
        let hide = paintedAfter(v, root)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let was = hide.map { $0.isHidden }
        for l in hide { l.isHidden = true }
        root.layer.render(in: ctx)
        for (l, h) in zip(hide, was) { l.isHidden = h }
        CATransaction.commit()
        capturing = false
        guard let snap = ctx.makeImage() else { return }
        var image = CIImage(cgImage: snap)
        let extent = image.extent
        if sigma > 0 { image = Paints.blur(image.clampedToExtent(), sigma: sigma * Double(down)).cropped(to: extent) }
        if let m = PaintMath.colorMatrix(f) { image = Paints.applyColorMatrix(image, m) }
        guard let out = Paints.ciContext.createCGImage(image, from: extent) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        output.frame = v.bounds
        output.contents = out
        mask.frame = v.bounds
        mask.path = v.shapePath()
        CATransaction.commit()
    }
}

/** A CADisplayLink target that does not retain its owner. */
final class DisplayLinkProxy: NSObject {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func tick() { action() }
}
#endif
