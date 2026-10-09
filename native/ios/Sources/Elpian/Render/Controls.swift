#if canImport(UIKit)
import UIKit
#if !ELPIAN_SINGLE_MODULE
import ElpianCore
#endif

/** A display-link driven 0…1 animation (ValueAnimator). */
final class ValueAnimator {
    private var link: CADisplayLink?
    private var start: CFTimeInterval = 0
    private let duration: Double
    private let repeats: Bool
    private let from: Double
    private let to: Double
    private let curve: (Double) -> Double
    private let update: (Double) -> Void

    init(from: Double, to: Double, duration: Double, repeats: Bool = false, curve: @escaping (Double) -> Double = { $0 }, update: @escaping (Double) -> Void) {
        self.from = from
        self.to = to
        self.duration = duration
        self.repeats = repeats
        self.curve = curve
        self.update = update
    }

    func begin() {
        start = CACurrentMediaTime()
        let l = CADisplayLink(target: DisplayLinkProxy { [weak self] in self?.tick() }, selector: #selector(DisplayLinkProxy.tick))
        l.add(to: .main, forMode: .common)
        link = l
    }

    private func tick() {
        let elapsed = CACurrentMediaTime() - start
        var t = duration > 0 ? elapsed / duration : 1
        if repeats {
            t = t.truncatingRemainder(dividingBy: 1)
        } else if t >= 1 {
            t = 1
        }
        update(from + (to - from) * curve(t))
        if !repeats && t >= 1 { cancel() }
    }

    func cancel() {
        link?.invalidate()
        link = nil
    }

    deinit { link?.invalidate() }
}

/** A cubic-bezier easing (PathInterpolator). */
func cubicBezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> (Double) -> Double {
    return { x in
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<40 {
            t = (lo + hi) / 2
            let bx = 3 * (1 - t) * (1 - t) * t * x1 + 3 * (1 - t) * t * t * x2 + t * t * t
            if bx < x { lo = t } else { hi = t }
        }
        return 3 * (1 - t) * (1 - t) * t * y1 + 3 * (1 - t) * t * t * y2 + t * t * t
    }
}

/** Shared plumbing for the custom-drawn Material 3 controls (Controls.kt). */
class MaterialControl: UIView {
    weak var owner: ElpianView?
    var colors: JSONObject = JSONObject() {
        didSet { setNeedsDisplay() }
    }
    var enabledState = true {
        didSet {
            alpha = enabledState ? 1 : 0.38
            setNeedsDisplay()
        }
    }
    var pressedOverlay = false

    init(owner: ElpianView) {
        self.owner = owner
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func color(_ keys: String..., fallback: Color) -> Color {
        for k in keys { if let c = HostProps.color(colors[k]) { return c } }
        return fallback
    }

    func emit(_ type: String, _ value: Any?) {
        guard let o = owner else { return }
        o.host?.emit(ViewEvent(id: o.viewId, type: type, value: value))
    }

    func fill(_ ctx: CGContext, _ c: Color) { ctx.setFillColor(Paints.cgColor(c)) }

    func drawOverlay(_ ctx: CGContext, _ cx: CGFloat, _ cy: CGFloat, _ c: Color) {
        if !pressedOverlay { return }
        fill(ctx, PaintMath.withAlpha(c, 0.1))
        ctx.fillEllipse(in: CGRect(x: cx - 20, y: cy - 20, width: 40, height: 40))
    }

    // Tap handling: press overlay, then [onTap] on release inside.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard enabledState else { return }
        pressedOverlay = true
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard enabledState else { return }
        pressedOverlay = false
        setNeedsDisplay()
        if let t = touches.first, bounds.contains(t.location(in: self)) { onTap() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        pressedOverlay = false
        setNeedsDisplay()
    }

    override func accessibilityActivate() -> Bool {
        guard enabledState else { return false }
        onTap()
        return true
    }

    func onTap() {}
}

/** Material 3 checkbox: 18 px box, 2 px radius and stroke, animated check. */
final class CheckboxView: MaterialControl {
    var checked = false {
        didSet {
            if oldValue != checked { animateTo(checked ? 1 : 0) }
            accessibilityValue = checked ? "1" : "0"
        }
    }
    private var t: CGFloat = 0
    private var anim: ValueAnimator?

    private func animateTo(_ target: CGFloat) {
        anim?.cancel()
        if window == nil {
            t = target
            setNeedsDisplay()
            return
        }
        let a = ValueAnimator(from: Double(t), to: Double(target), duration: 0.15) { [weak self] v in
            self?.t = CGFloat(v)
            self?.setNeedsDisplay()
        }
        anim = a
        a.begin()
    }

    override func onTap() {
        checked.toggle()
        emit("change", checked)
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let cx = bounds.midX, cy = bounds.midY
        let fillC = color("fill", "active", fallback: M3.primary)
        let border = color("border", fallback: M3.onSurfaceVariant)
        drawOverlay(ctx, cx, cy, checked ? fillC : border)
        let s: CGFloat = 18
        let r = CGRect(x: cx - s / 2, y: cy - s / 2, width: s, height: s)
        if t < 1 {
            ctx.setStrokeColor(Paints.cgColor(border))
            ctx.setLineWidth(2)
            ctx.addPath(UIBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), cornerRadius: 2).cgPath)
            ctx.strokePath()
        }
        if t > 0 {
            fill(ctx, PaintMath.withAlpha(fillC, Double(t)))
            ctx.addPath(UIBezierPath(roundedRect: r, cornerRadius: 2).cgPath)
            ctx.fillPath()
            ctx.setStrokeColor(Paints.cgColor(color("check", fallback: M3.onPrimary)))
            ctx.setLineWidth(2)
            ctx.setLineCap(.butt)
            ctx.setLineJoin(.miter)
            ctx.move(to: CGPoint(x: r.minX + s * 0.15, y: r.minY + s * 0.45))
            ctx.addLine(to: CGPoint(x: r.minX + s * 0.4, y: r.minY + s * 0.7))
            ctx.addLine(to: CGPoint(x: r.minX + s * 0.4 + s * 0.45 * t, y: r.minY + s * 0.7 - s * 0.45 * t))
            ctx.strokePath()
        }
    }
}

/** Material 3 radio: 20 px ring, 2 px stroke, 10 px dot. */
final class RadioView: MaterialControl {
    var checked = false {
        didSet {
            setNeedsDisplay()
            accessibilityValue = checked ? "1" : "0"
        }
    }
    var value: Any?

    override func onTap() {
        checked = true
        emit("change", flattenOptional(value) ?? true)
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let cx = bounds.midX, cy = bounds.midY
        let fillC = color("fill", "active", fallback: M3.primary)
        let border = color("border", fallback: M3.onSurfaceVariant)
        let c = checked ? fillC : border
        drawOverlay(ctx, cx, cy, c)
        ctx.setStrokeColor(Paints.cgColor(c))
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: CGRect(x: cx - 9, y: cy - 9, width: 18, height: 18))
        if checked {
            fill(ctx, c)
            ctx.fillEllipse(in: CGRect(x: cx - 5, y: cy - 5, width: 10, height: 10))
        }
    }
}

/** Material 3 switch: 52×32 track, 16 px thumb off / 24 px on (28 px pressed). */
final class SwitchView: MaterialControl {
    var checked = false {
        didSet {
            if oldValue != checked { animateTo(checked ? 1 : 0) }
            accessibilityValue = checked ? "1" : "0"
        }
    }
    private var t: CGFloat = 0
    private var anim: ValueAnimator?

    private func animateTo(_ target: CGFloat) {
        anim?.cancel()
        if window == nil {
            t = target
            setNeedsDisplay()
            return
        }
        let a = ValueAnimator(from: Double(t), to: Double(target), duration: 0.15) { [weak self] v in
            self?.t = CGFloat(v)
            self?.setNeedsDisplay()
        }
        anim = a
        a.begin()
    }

    override func onTap() {
        checked.toggle()
        emit("change", checked)
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let cx = bounds.midX, cy = bounds.midY
        let tw: CGFloat = 52, th: CGFloat = 32
        let left = cx - tw / 2
        let top = cy - th / 2
        let active = color("active", "fill", "trackOn", fallback: M3.primary)
        let thumbOn = color("thumb", "thumbOn", fallback: M3.onPrimary)
        let trackOff = color("inactiveTrack", "trackOff", fallback: M3.surfaceContainerHighest)
        let outline = color("border", "outline", fallback: M3.outline)
        let thumbOff = color("inactiveThumb", "thumbOff", fallback: outline)
        let track = CGRect(x: left, y: top, width: tw, height: th)
        fill(ctx, PaintMath.lerpARGB(trackOff, active, Double(t)))
        ctx.addPath(UIBezierPath(roundedRect: track, cornerRadius: th / 2).cgPath)
        ctx.fillPath()
        if t < 1 {
            ctx.setStrokeColor(Paints.cgColor(PaintMath.withAlpha(outline, Double(1 - t))))
            ctx.setLineWidth(2)
            ctx.addPath(UIBezierPath(roundedRect: track.insetBy(dx: 1, dy: 1), cornerRadius: th / 2 - 1).cgPath)
            ctx.strokePath()
        }
        let size: CGFloat = pressedOverlay ? 28 : 16 + 8 * t
        let offX: CGFloat = 14
        let onX: CGFloat = 52 - 4 - 12 - 2
        let tx = left + offX + (onX - offX) * t
        drawOverlay(ctx, tx, cy, checked ? active : outline)
        fill(ctx, PaintMath.lerpARGB(thumbOff, thumbOn, Double(t)))
        ctx.fillEllipse(in: CGRect(x: tx - size / 2, y: cy - size / 2, width: size, height: size))
    }
}

/** Material 3 slider: 4 px track, 20 px thumb, optional division ticks. */
final class SliderView: MaterialControl {
    var min = 0.0
    var max = 1.0
    var step: Double?
    var value = 0.0 {
        didSet {
            setNeedsDisplay()
            accessibilityValue = jsNumberToString(value)
        }
    }
    private var dragging = false
    private var down = CGPoint.zero
    private let pad: CGFloat = 24

    override init(owner: ElpianView) {
        super.init(owner: owner)
        accessibilityTraits = .adjustable
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func valueAt(_ x: CGFloat) -> Double {
        let w = bounds.width - 2 * pad
        let f = w > 0 ? Swift.min(1, Swift.max(0, Double((x - pad) / w))) : 0
        var v = min + (max - min) * f
        if let s = step, s > 0 {
            v = Swift.min(Swift.max(min + jsRound((v - min) / s) * s, Swift.min(min, max)), Swift.max(min, max))
        }
        return v
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard enabledState, let t = touches.first else { return }
        down = t.location(in: self)
        dragging = false
        pressedOverlay = true
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard enabledState, let t = touches.first else { return }
        let p = t.location(in: self)
        if !dragging && abs(p.x - down.x) > 8 && abs(p.x - down.x) > abs(p.y - down.y) {
            dragging = true
            if let o = owner { o.host?.surface.router.requestDisallowIntercept(o) }
        }
        if dragging {
            let v = valueAt(p.x)
            if v != value {
                value = v
                emit("input", v)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard enabledState, let t = touches.first else { return }
        let v = valueAt(t.location(in: self).x)
        if v != value || !dragging {
            value = v
            emit("input", v)
        }
        emit("change", value)
        dragging = false
        pressedOverlay = false
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if dragging { emit("change", value) }
        dragging = false
        pressedOverlay = false
        setNeedsDisplay()
    }

    override func accessibilityIncrement() { nudge(1) }
    override func accessibilityDecrement() { nudge(-1) }

    private func nudge(_ dir: Double) {
        let s = step ?? (max - min) / 10
        let v = Swift.min(Swift.max(min, value + dir * s), max)
        value = v
        emit("input", v)
        emit("change", v)
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let cy = bounds.midY
        let active = color("active", "fill", fallback: M3.primary)
        let inactive = color("inactive", "inactiveTrack", fallback: M3.secondaryContainer)
        let thumb = color("thumb", fallback: active)
        let x0 = pad
        let x1 = bounds.width - pad
        let range = max - min
        let f = range != 0 ? CGFloat(Swift.min(1, Swift.max(0, (value - min) / range))) : 0
        let tx = x0 + (x1 - x0) * f
        let h: CGFloat = 4
        fill(ctx, inactive)
        ctx.addPath(UIBezierPath(roundedRect: CGRect(x: x0, y: cy - h / 2, width: Swift.max(0, x1 - x0), height: h), cornerRadius: h / 2).cgPath)
        ctx.fillPath()
        fill(ctx, active)
        ctx.addPath(UIBezierPath(roundedRect: CGRect(x: x0, y: cy - h / 2, width: Swift.max(0, tx - x0), height: h), cornerRadius: h / 2).cgPath)
        ctx.fillPath()
        if let s = step, s > 0, range / s >= 1, range / s <= 100 {
            let n = Int(jsRound(range / s))
            for i in 0...n {
                let x = x0 + (x1 - x0) * CGFloat(i) / CGFloat(n)
                fill(ctx, x <= tx ? PaintMath.withAlpha(color("activeTick", fallback: M3.onPrimary), 0.38) : PaintMath.withAlpha(color("inactiveTick", fallback: M3.onSurfaceVariant), 0.38))
                ctx.fillEllipse(in: CGRect(x: x - 1, y: cy - 1, width: 2, height: 2))
            }
        }
        if pressedOverlay {
            fill(ctx, HostProps.color(colors["overlay"]) ?? PaintMath.withAlpha(active, 0.12))
            ctx.fillEllipse(in: CGRect(x: tx - 24, y: cy - 24, width: 48, height: 48))
        }
        fill(ctx, thumb)
        ctx.fillEllipse(in: CGRect(x: tx - 10, y: cy - 10, width: 20, height: 20))
    }
}

/** Linear or circular progress, determinate or indeterminate (Material timings). */
final class ProgressView: MaterialControl {
    private(set) var circular = false
    var value: Double? {
        didSet {
            updateAnimation()
            setNeedsDisplay()
        }
    }
    var strokeWidth: Double?
    private var phase: Double = 0
    private var anim: ValueAnimator?
    private let ease = cubicBezier(0.4, 0, 0.2, 1)
    private let easeInOut = cubicBezier(0.42, 0, 0.58, 1)

    override init(owner: ElpianView) {
        super.init(owner: owner)
        isUserInteractionEnabled = false
        accessibilityTraits = .updatesFrequently
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func updateAnimation() {
        let needs = value == nil && window != nil
        if needs && anim == nil {
            let a = ValueAnimator(from: 0, to: 1, duration: circular ? 1.4 : 1.8, repeats: true) { [weak self] v in
                self?.phase = v
                self?.setNeedsDisplay()
            }
            anim = a
            a.begin()
        } else if !needs {
            anim?.cancel()
            anim = nil
        }
    }

    func setVariant(_ circular: Bool) {
        if self.circular != circular {
            self.circular = circular
            anim?.cancel()
            anim = nil
            updateAnimation()
            setNeedsDisplay()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            anim?.cancel()
            anim = nil
        } else {
            updateAnimation()
        }
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let indicator = color("indicator", fallback: M3.primary)
        let track = HostProps.color(colors["track"]) ?? 0
        let v = value.map { CGFloat(Swift.min(1, Swift.max(0, $0))) }
        let w = bounds.width, h = bounds.height
        if circular {
            let stroke = CGFloat(strokeWidth ?? 4)
            let m = Swift.min(w, h)
            let size = m > 0 ? m : 36
            let r = size / 2 - stroke / 2
            let c = CGPoint(x: w / 2, y: h / 2)
            ctx.setLineWidth(stroke)
            ctx.setLineCap(.butt)
            if !Paints.isTransparent(track) {
                ctx.setStrokeColor(Paints.cgColor(track))
                ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            }
            ctx.setStrokeColor(Paints.cgColor(indicator))
            if let v = v {
                if v > 0 {
                    ctx.addArc(center: c, radius: r, startAngle: -.pi / 2, endAngle: -.pi / 2 + .pi * 2 * v, clockwise: false)
                    ctx.strokePath()
                }
            } else {
                // elpian-spin (rotate 360° / 1.4 s) with elpian-dash (1 → 60 → 60 of 200, offset 0 → -10 → -80).
                let circ = 2 * Double.pi * 18
                let t = phase
                let half = t < 0.5 ? easeInOut(t * 2) : easeInOut((t - 0.5) * 2)
                let dash = t < 0.5 ? 1 + 59 * half : 60
                let offset = t < 0.5 ? -10 * half : -10 - 70 * half
                let startDeg = -90 + 360 * t + (-offset / circ) * 360
                let sweepDeg = 360 * dash / circ
                let a0 = CGFloat(startDeg * Double.pi / 180)
                ctx.addArc(center: c, radius: r, startAngle: a0, endAngle: a0 + CGFloat(sweepDeg * Double.pi / 180), clockwise: false)
                ctx.strokePath()
            }
        } else {
            if !Paints.isTransparent(track) {
                fill(ctx, track)
                ctx.fill(bounds)
            }
            fill(ctx, indicator)
            if let v = v {
                ctx.fill(CGRect(x: 0, y: 0, width: w * v, height: h))
            } else {
                // elpian-indeterminate: a 40 % bar from -40 % to 100 %.
                let p = CGFloat(ease(phase))
                let l = w * (-0.4 + 1.4 * p)
                ctx.saveGState()
                ctx.clip(to: bounds)
                ctx.fill(CGRect(x: l, y: 0, width: w * 0.4, height: h))
                ctx.restoreGState()
            }
        }
    }
}
#endif
