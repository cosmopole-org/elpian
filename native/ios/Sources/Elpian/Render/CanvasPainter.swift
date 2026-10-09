#if canImport(UIKit)
import UIKit
import CoreText
#if !ELPIAN_SINGLE_MODULE
import ElpianCore
#endif

/** Host hooks for `custom` canvas commands: name → painter (context in logical px, y-down). */
public typealias CustomCanvasPainter = (_ context: CGContext, _ params: JSONObject) -> Void

/**
 * Executes Elpian canvas commands with CoreGraphics — every command of the web
 * painter (native/web/src/canvas.ts, CanvasPainter.kt on Android) with the
 * same semantics: HTML canvas paths (arc, arcTo, ellipse, roundRect…), fill
 * and stroke styles (colours, gradients, patterns), line dashes, caps, joins,
 * shadows, global alpha and composite operations, clipping, the state stack,
 * transforms, text with CSS fonts, alignment and baselines, images and pixel
 * data. Coordinates are logical px; the bitmap is device px.
 *
 * Paths are built in the coordinates of the command and painted with the
 * transform current at paint time (as the Android port does). Composite
 * operations other than source-over and shadows draw through an offscreen
 * bitmap composited over the whole canvas, like an HTML canvas.
 */
final class CanvasPainter {
    private static var customPainters: [String: CustomCanvasPainter] = [:]

    static func registerCanvasPainter(_ name: String, _ painter: @escaping CustomCanvasPainter) {
        customPainters[name] = painter
    }

    private static var imageCache: [String: UIImage?] = [:]
    private static var imageOrder: [String] = []

    static func num(_ p: JSONObject, _ k: String, _ d: Double = 0) -> Double {
        let v = flattenOptional(p[k])
        if let x = jsNumber(v) { return x.isFinite ? x : d }
        if let s = v as? String {
            let x = jsParseFloat(s)
            return x.isFinite ? x : d
        }
        return d
    }

    static func color(_ v: Any?) -> Color {
        let f = flattenOptional(v)
        if let n = jsNumber(f) { return n.isFinite ? jsToUint32(n) : 0 }
        if let s = f as? String { return parseColor(s) ?? 0xFF00_0000 }
        return 0xFF00_0000
    }

    /** Points as `[[x,y],…]`, `[{x,y},…]` or a flat `[x0,y0,x1,y1,…]`. */
    static func pointsOf(_ v: Any?) -> [CGPoint] {
        guard let l = asArray(v) else { return [] }
        if let first = l.first, jsNumber(flattenOptional(first)) != nil {
            var out: [CGPoint] = []
            var i = 0
            while i + 1 < l.count {
                out.append(CGPoint(x: HostProps.num(l[i]) ?? 0, y: HostProps.num(l[i + 1]) ?? 0))
                i += 2
            }
            return out
        }
        return l.map { p in
            if let a = asArray(p) { return CGPoint(x: HostProps.num(a.first ?? nil) ?? 0, y: HostProps.num(a.count > 1 ? a[1] : nil) ?? 0) }
            if let m = asMap(p) { return CGPoint(x: HostProps.num(m["x"]) ?? 0, y: HostProps.num(m["y"]) ?? 0) }
            return .zero
        }
    }

    private final class Grad {
        let kind: String
        var colors: [Color]
        var stops: [Double]
        let x0: Double, y0: Double, x1: Double, y1: Double, r0: Double, r1: Double

        init(_ kind: String, _ colors: [Color], _ stops: [Double], _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ r0: Double, _ r1: Double) {
            self.kind = kind
            self.colors = colors
            self.stops = stops
            self.x0 = x0; self.y0 = y0; self.x1 = x1; self.y1 = y1; self.r0 = r0; self.r1 = r1
        }
    }

    private struct Pattern {
        let src: String
        let repetition: String
    }

    /** Non-premultiplied ARGB pixels in device px. */
    final class ImageData {
        let width: Int
        let height: Int
        var pixels: [UInt32]

        init(_ width: Int, _ height: Int, _ pixels: [UInt32]) {
            self.width = width
            self.height = height
            self.pixels = pixels
        }
    }

    private enum Style {
        case solid(Color)
        case gradient(String)
        case pattern(String)
    }

    private struct State {
        var fill: Style = .solid(0xFF00_0000)
        var stroke: Style = .solid(0xFF00_0000)
        var alpha: CGFloat = 1
        var composite = "source-over"
        var lineWidth: CGFloat = 1
        var cap: CGLineCap = .butt
        var join: CGLineJoin = .miter
        var miter: CGFloat = 10
        var dash: [CGFloat]?
        var dashOffset: CGFloat = 0
        var shadowBlur: CGFloat = 0
        var shadowColor: Color = 0
        var shadowX: CGFloat = 0
        var shadowY: CGFloat = 0
        var font: UIFont = UIFont.systemFont(ofSize: 10)
        var align = "start"
        var baseline = "alphabetic"
    }

    private let images: ImageSource
    private let onImageReady: () -> Void
    private var gradients: [String: Grad] = [:]
    private var patterns: [String: Pattern] = [:]
    private var imageData: [String: ImageData] = [:]
    private var path = CGMutablePath()
    private var cur = CGPoint.zero
    private var hasCurrent = false
    private var state = State()
    private var stack: [State] = []
    private var dpr: CGFloat = 1
    private var pending = Set<String>()

    private(set) var context: CGContext?
    private var pixelWidth = 0
    private var pixelHeight = 0

    init(images: ImageSource, onImageReady: @escaping () -> Void) {
        self.images = images
        self.onImageReady = onImageReady
    }

    /** The painted bitmap. */
    var image: CGImage? { context?.makeImage() }

    /** Reset the bitmap to [w]×[h] logical px at [dpr] and the state to defaults. */
    func reset(_ w: Double, _ h: Double, _ dpr: CGFloat) {
        let cw = max(1, Int((CGFloat(w) * dpr).rounded()))
        let ch = max(1, Int((CGFloat(h) * dpr).rounded()))
        // A fresh bitmap: no transform, clip or saved state survives a reset.
        context = Raster.context(cw, ch, gray: false)
        pixelWidth = cw
        pixelHeight = ch
        guard let c = context else { return }
        c.scaleBy(x: dpr, y: dpr)
        self.dpr = dpr
        // Flutter's CanvasState / HTML defaults.
        state = State()
        stack.removeAll()
        path = CGMutablePath()
        hasCurrent = false
        cur = .zero
        gradients.removeAll()
        patterns.removeAll()
        c.setLineCap(.butt)
        c.setLineJoin(.miter)
        c.setMiterLimit(10)
        c.setAlpha(1)
        c.setBlendMode(.normal)
    }

    func run(_ commands: [Any?]) {
        guard let c = context else { return }
        for cmd in commands {
            guard let m = asMap(cmd), let type = m["type"] as? String else { continue }
            let params = asMap(m["params"]) ?? JSONObject()
            exec(c, type, params)
        }
    }

    func release() {
        context = nil
    }

    // ---------------------------------------------------------------------
    // Paths
    // ---------------------------------------------------------------------

    private func moveTo(_ x: CGFloat, _ y: CGFloat) {
        path.move(to: CGPoint(x: x, y: y))
        cur = CGPoint(x: x, y: y)
        hasCurrent = true
    }

    private func lineTo(_ x: CGFloat, _ y: CGFloat) {
        if !hasCurrent { moveTo(x, y) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        cur = CGPoint(x: x, y: y)
        hasCurrent = true
    }

    /** An elliptical arc as cubic Béziers (HTML `ellipse` / `arc` semantics, lineTo the start). */
    private func arc(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ rot: Double, _ start: Double, _ end: Double, _ ccw: Bool) {
        let tau = Double.pi * 2
        let sweep: Double
        if !ccw {
            if end - start >= tau { sweep = tau } else { let m = (end - start).truncatingRemainder(dividingBy: tau); sweep = m < 0 ? m + tau : m }
        } else {
            if start - end >= tau { sweep = -tau } else { let m = (start - end).truncatingRemainder(dividingBy: tau); sweep = -(m < 0 ? m + tau : m) }
        }
        arcSweep(cx, cy, rx, ry, rot, start, sweep)
    }

    private func arcSweep(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ rot: Double, _ start: Double, _ sweep: Double) {
        let cr = cos(rot)
        let sr = sin(rot)
        func map(_ ux: Double, _ uy: Double) -> CGPoint { CGPoint(x: cx + rx * ux * cr - ry * uy * sr, y: cy + rx * ux * sr + ry * uy * cr) }
        let p0 = map(cos(start), sin(start))
        if hasCurrent { lineTo(p0.x, p0.y) } else { moveTo(p0.x, p0.y) }
        if sweep == 0 { return }
        let n = max(1, Int((abs(sweep) / (Double.pi / 2) - 1e-9).rounded(.up)))
        let da = sweep / Double(n)
        let k = 4.0 / 3.0 * tan(da / 4)
        var a0 = start
        for _ in 0..<n {
            let a1 = a0 + da
            let c0 = cos(a0), s0 = sin(a0)
            let c1 = cos(a1), s1 = sin(a1)
            let q1 = map(c0 - k * s0, s0 + k * c0)
            let q2 = map(c1 + k * s1, s1 - k * c1)
            let q3 = map(c1, s1)
            path.addCurve(to: q3, control1: q1, control2: q2)
            cur = q3
            a0 = a1
        }
    }

    /** HTML `arcTo(x1, y1, x2, y2, r)`. */
    private func arcTo(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ r: Double) {
        if !hasCurrent { moveTo(CGFloat(x1), CGFloat(y1)) }
        let x0 = Double(cur.x)
        let y0 = Double(cur.y)
        if (x0 == x1 && y0 == y1) || (x1 == x2 && y1 == y2) || r == 0 {
            lineTo(CGFloat(x1), CGFloat(y1))
            return
        }
        let v1x = x0 - x1, v1y = y0 - y1
        let v2x = x2 - x1, v2y = y2 - y1
        let l1 = hypot(v1x, v1y), l2 = hypot(v2x, v2y)
        let n1x = v1x / l1, n1y = v1y / l1
        let n2x = v2x / l2, n2y = v2y / l2
        let cross = n1x * n2y - n1y * n2x
        if abs(cross) < 1e-9 {
            lineTo(CGFloat(x1), CGFloat(y1))
            return
        }
        let angle = acos(min(1, max(-1, n1x * n2x + n1y * n2y)))
        let dist = r / tan(angle / 2)
        let t1x = x1 + n1x * dist, t1y = y1 + n1y * dist
        let t2x = x1 + n2x * dist, t2y = y1 + n2y * dist
        let bx = n1x + n2x, by = n1y + n2y
        let bl = hypot(bx, by)
        let h = r / sin(angle / 2)
        let cx = x1 + bx / bl * h
        let cy = y1 + by / bl * h
        lineTo(CGFloat(t1x), CGFloat(t1y))
        let a0 = atan2(t1y - cy, t1x - cx)
        let a1 = atan2(t2y - cy, t2x - cx)
        var sweep = a1 - a0
        while sweep > Double.pi { sweep -= 2 * Double.pi }
        while sweep < -Double.pi { sweep += 2 * Double.pi }
        arcSweep(cx, cy, r, r, 0, a0, sweep)
        cur = CGPoint(x: t2x, y: t2y)
    }

    /**
     * Flutter `Path.arcToPoint`: a circular arc of [radius] from the current
     * point to (x, y) — clockwise by default, the shorter arc unless [largeArc].
     * A radius too small for the chord grows to half the chord (SVG rules).
     */
    private func arcToPoint(_ x: Double, _ y: Double, _ radius: Double, _ clockwise: Bool, _ largeArc: Bool) {
        let x0 = Double(cur.x)
        let y0 = Double(cur.y)
        let dx = x - x0
        let dy = y - y0
        let d = hypot(dx, dy)
        if d == 0 { return }
        if radius <= 0 {
            lineTo(CGFloat(x), CGFloat(y))
            return
        }
        let r = max(radius, d / 2)
        let h = max(0, r * r - (d / 2) * (d / 2)).squareRoot()
        let sign: Double = clockwise != largeArc ? 1 : -1
        let cx = (x0 + x) / 2 - (sign * h * dy) / d
        let cy = (y0 + y) / 2 + (sign * h * dx) / d
        let a0 = atan2(y0 - cy, x0 - cx)
        let a1 = atan2(y - cy, x - cx)
        arc(cx, cy, r, r, 0, a0, a1, !clockwise)
        cur = CGPoint(x: x, y: y)
    }

    private func radiiOf(_ v: Any?, _ fallback: Double) -> [Double] {
        func one(_ x: Any?) -> (Double, Double) {
            if let m = asMap(x) { return (HostProps.num(m["x"]) ?? 0, HostProps.num(m["y"]) ?? 0) }
            let n = HostProps.num(x) ?? 0
            return (n, n)
        }
        let l = asArray(v)
        let r: [(Double, Double)] = (l == nil || l!.isEmpty) ? [one(fallback)] : l!.map { one($0) }
        let q: [(Double, Double)]
        switch r.count {
        case 1: q = [r[0], r[0], r[0], r[0]]
        case 2: q = [r[0], r[1], r[0], r[1]]
        case 3: q = [r[0], r[1], r[2], r[1]]
        default: q = [r[0], r[1], r[2], r[3]]
        }
        return [q[0].0, q[0].1, q[1].0, q[1].1, q[2].0, q[2].1, q[3].0, q[3].1].map { max(0, $0) }
    }

    // ---------------------------------------------------------------------
    // Paints
    // ---------------------------------------------------------------------

    private func applyStroke(_ c: CGContext) {
        let st = state
        c.setLineWidth(st.lineWidth)
        c.setLineCap(st.cap)
        c.setLineJoin(st.join)
        c.setMiterLimit(st.miter)
        if let d = st.dash, !d.isEmpty, d.contains(where: { $0 > 0 }) {
            c.setLineDash(phase: st.dashOffset, lengths: d)
        } else {
            c.setLineDash(phase: 0, lengths: [])
        }
    }

    /** Fill the current clip with a non-solid [style] (gradient or pattern). */
    private func fillClip(_ c: CGContext, _ style: Style) {
        switch style {
        case .solid(let col):
            c.setFillColor(Paints.cgColor(col))
            c.fill(c.boundingBoxOfClipPath)
        case .gradient(let id):
            guard let g = gradients[id], !g.colors.isEmpty else { return }
            var colors = g.colors
            var stops = g.stops.map { min(1, max(0, $0)) }
            if colors.count == 1 {
                colors = [colors[0], colors[0]]
                stops = [0, 1]
            }
            let cs = colors.map { Paints.cgColor($0) } as CFArray
            guard let grad = CGGradient(colorsSpace: Paints.srgb, colors: cs, locations: stops.map { CGFloat($0) }) else { return }
            if g.kind == "linear" {
                let end = (g.x0 == g.x1 && g.y0 == g.y1) ? CGPoint(x: g.x1 + 0.0001, y: g.y1) : CGPoint(x: g.x1, y: g.y1)
                c.drawLinearGradient(grad, start: CGPoint(x: g.x0, y: g.y0), end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            } else {
                c.drawRadialGradient(grad, startCenter: CGPoint(x: g.x0, y: g.y0), startRadius: CGFloat(max(0, g.r0)),
                                     endCenter: CGPoint(x: g.x1, y: g.y1), endRadius: CGFloat(max(0.0001, g.r1)),
                                     options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
        case .pattern(let id):
            guard let pat = patterns[id], let img = image(pat.src) else { return }
            let rx = pat.repetition == "repeat" || pat.repetition == "repeat-x" || pat.repetition.isEmpty
            let ry = pat.repetition == "repeat" || pat.repetition == "repeat-y" || pat.repetition.isEmpty
            // One image pixel per logical px, tiled from the origin.
            let tw = img.size.width * img.scale
            let th = img.size.height * img.scale
            if tw <= 0 || th <= 0 { return }
            let box = c.boundingBoxOfClipPath
            let x0 = rx ? (box.minX / tw).rounded(.down) * tw : 0
            let y0 = ry ? (box.minY / th).rounded(.down) * th : 0
            let x1 = rx ? box.maxX : tw
            let y1 = ry ? box.maxY : th
            UIGraphicsPushContext(c)
            var count = 0
            var y = y0
            while y < y1 && count < 20_000 {
                var x = x0
                while x < x1 && count < 20_000 {
                    img.draw(in: CGRect(x: x, y: y, width: tw, height: th))
                    x += tw
                    count += 1
                }
                y += th
            }
            UIGraphicsPopContext()
        }
    }

    /** Paint [p] (filled or stroked) with the current style. */
    private func paintPath(_ c: CGContext, _ p: CGPath, fill: Bool, evenOdd: Bool = false, style: Style? = nil) {
        let s = style ?? (fill ? state.fill : state.stroke)
        c.saveGState()
        if !fill { applyStroke(c) }
        if case .solid(let col) = s {
            c.addPath(p)
            if fill {
                c.setFillColor(Paints.cgColor(col))
                c.fillPath(using: evenOdd ? .evenOdd : .winding)
            } else {
                c.setStrokeColor(Paints.cgColor(col))
                c.strokePath()
            }
        } else {
            c.addPath(p)
            if !fill { c.replacePathWithStrokedPath() }
            c.clip(using: evenOdd && fill ? .evenOdd : .winding)
            fillClip(c, s)
        }
        c.restoreGState()
    }

    /**
     * Draw with the current global alpha, composite operation and shadow.
     * Source-over without a shadow draws directly; otherwise the drawing goes
     * to an offscreen bitmap (same transform) that is composited over the
     * whole canvas — the shadow first, offset in device px and blurred by
     * shadowBlur / 2 as HTML specifies.
     */
    private func composite(_ c: CGContext, _ block: (CGContext) -> Void) {
        let st = state
        let op = st.composite
        let blend = Paints.cgBlendMode(op) ?? .normal
        let hasShadow = !Paints.isTransparent(st.shadowColor) && (st.shadowBlur > 0 || st.shadowX != 0 || st.shadowY != 0)
        if (op == "source-over" || op.isEmpty || Paints.cgBlendMode(op) == nil) && !hasShadow {
            c.saveGState()
            c.setAlpha(st.alpha)
            block(c)
            c.restoreGState()
            return
        }
        if op == "destination" || op == "dst" { return }
        guard let off = Raster.context(pixelWidth, pixelHeight, gray: false) else { return }
        // Raster.context flipped the offscreen to y-down; replace that with the canvas's full transform.
        off.concatenate(off.ctm.inverted())
        off.concatenate(c.ctm)
        block(off)
        guard let drawn = off.makeImage() else { return }
        let device = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        c.saveGState()
        c.concatenate(c.ctm.inverted())
        if hasShadow, let shadow = shadowImage(drawn, st) {
            c.saveGState()
            c.setBlendMode(blend)
            c.setAlpha(st.alpha)
            // Device space is y-up: a positive (downward) offset moves the shadow down.
            c.draw(shadow, in: device.offsetBy(dx: st.shadowX * dpr, dy: -st.shadowY * dpr))
            c.restoreGState()
        }
        c.setBlendMode(blend)
        c.setAlpha(st.alpha)
        c.draw(drawn, in: device)
        c.restoreGState()
    }

    /** The drawing's alpha tinted with the shadow colour and blurred (σ = shadowBlur / 2). */
    private func shadowImage(_ drawn: CGImage, _ st: State) -> CGImage? {
        guard let s = Raster.context(pixelWidth, pixelHeight, gray: false) else { return nil }
        s.concatenate(s.ctm.inverted())
        let r = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        s.draw(drawn, in: r)
        s.setBlendMode(.sourceIn)
        s.setFillColor(Paints.cgColor(st.shadowColor))
        s.fill(r)
        Raster.blur(s, sigma: Double(st.shadowBlur / 2 * dpr))
        return s.makeImage()
    }

    private func parseFont(_ font: String) -> UIFont {
        var italic = false
        var weight = 400
        var size: CGFloat = 10
        var family: String? = "sans-serif"
        let parts = font.trimmingCharacters(in: .whitespaces).split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        let sizeRe = JSRegex("^([\\d.]+)(px|pt|em|rem|%)(/.*)?$")
        var i = 0
        while i < parts.count {
            let lower = parts[i].lowercased()
            if lower == "italic" || lower == "oblique" {
                italic = true
            } else if lower == "bold" || lower == "bolder" {
                weight = 700
            } else if lower == "lighter" {
                weight = 300
            } else if lower == "normal" || lower == "small-caps" {
                // no-op
            } else if lower.count == 3, lower.hasSuffix("00"), let w = Int(lower), w >= 100, w <= 900 {
                weight = w
            } else if let m = sizeRe.exec(lower) {
                let v = CGFloat(Double(m[1] ?? "") ?? 10)
                switch m[2] ?? "" {
                case "pt": size = v * 4 / 3
                case "em", "rem": size = v * 16
                case "%": size = v / 100 * 10
                default: size = v
                }
                let rest = parts[(i + 1)...].joined(separator: " ")
                family = rest.trimmingCharacters(in: .whitespaces).isEmpty ? "sans-serif" : rest
                break
            }
            i += 1
        }
        let resolved = resolveFontFamily(family)
        return ElpianFonts.font(resolved, weight, italic, size > 0 ? size : 10)
    }

    // ---------------------------------------------------------------------
    // Images
    // ---------------------------------------------------------------------

    /** A decoded image, or nil while it loads (the painter re-runs on load). */
    private func image(_ src: String) -> UIImage? {
        if src.isEmpty { return nil }
        if let hit = CanvasPainter.imageCache[src] { return hit }
        if !pending.contains(src) {
            pending.insert(src)
            images.load(src) { [weak self] img in
                CanvasPainter.imageCache[src] = .some(img)
                CanvasPainter.imageOrder.append(src)
                if CanvasPainter.imageOrder.count > 64 {
                    let old = CanvasPainter.imageOrder.removeFirst()
                    if old != src { CanvasPainter.imageCache.removeValue(forKey: old) }
                }
                guard let self = self else { return }
                self.pending.remove(src)
                if img != nil { self.onImageReady() }
            }
        }
        return nil
    }

    // ---------------------------------------------------------------------
    // Commands
    // ---------------------------------------------------------------------

    private func exec(_ c: CGContext, _ type: String, _ p: JSONObject) {
        func n(_ k: String, _ d: Double = 0) -> Double { CanvasPainter.num(p, k, d) }
        func f(_ k: String, _ d: Double = 0) -> CGFloat { CGFloat(CanvasPainter.num(p, k, d)) }
        func rect() -> CGRect { CGRect(x: f("x"), y: f("y"), width: f("width"), height: f("height")).standardized }
        switch type {
        // ---- path building ----
        case "beginPath":
            path = CGMutablePath(); hasCurrent = false; cur = .zero
        case "closePath":
            if !path.isEmpty { path.closeSubpath() }
        case "moveTo":
            moveTo(f("x"), f("y"))
        case "lineTo":
            lineTo(f("x"), f("y"))
        case "quadraticCurveTo":
            if !hasCurrent { moveTo(f("cpx"), f("cpy")) }
            path.addQuadCurve(to: CGPoint(x: f("x"), y: f("y")), control: CGPoint(x: f("cpx"), y: f("cpy")))
            cur = CGPoint(x: f("x"), y: f("y"))
        case "bezierCurveTo":
            if !hasCurrent { moveTo(f("cp1x"), f("cp1y")) }
            path.addCurve(to: CGPoint(x: f("x"), y: f("y")), control1: CGPoint(x: f("cp1x"), y: f("cp1y")), control2: CGPoint(x: f("cp2x"), y: f("cp2y")))
            cur = CGPoint(x: f("x"), y: f("y"))
        case "arc":
            let r = max(0, n("radius"))
            arc(n("x"), n("y"), r, r, 0, n("startAngle"), n("endAngle"), HostProps.bool(p["counterclockwise"]))
        case "arcTo":
            // HTML arcTo(x1, y1, x2, y2, r); the Flutter-only shape {x, y, radius} (an arc to a point) too.
            if p["x1"] != nil || p["x2"] != nil {
                arcTo(n("x1"), n("y1"), n("x2"), n("y2"), max(0, n("radius")))
            } else {
                arcToPoint(n("x"), n("y"), n("radius"), !HostProps.isFalse(p["clockwise"]), HostProps.bool(p["largeArc"]))
            }
        case "ellipse":
            arc(n("x"), n("y"), abs(n("radiusX")), abs(n("radiusY")), n("rotation"), n("startAngle", 0), n("endAngle", Double.pi * 2), HostProps.bool(p["counterclockwise"]))
        case "rect":
            path.addRect(rect())
            moveTo(f("x"), f("y"))
        case "roundRect":
            let r = rect()
            let radii = PaintMath.scaleRadii(radiiOf(p["radii"], n("radius")), Double(r.width), Double(r.height))
            Paints.addRoundRect(path, r, radii)
            moveTo(f("x"), f("y"))
        case "circle":
            let r = max(0, n("radius"))
            moveTo(CGFloat(n("x") + r), f("y"))
            arc(n("x"), n("y"), r, r, 0, 0, Double.pi * 2, false)

        // ---- painting the path ----
        case "fill":
            let fp = path.copy() ?? path
            let evenOdd = HostProps.str(p["fillRule"]) == "evenodd"
            composite(c) { cc in paintPath(cc, fp, fill: true, evenOdd: evenOdd) }
        case "stroke":
            let sp = path.copy() ?? path
            composite(c) { cc in paintPath(cc, sp, fill: false) }
        case "clip":
            c.addPath(path)
            c.clip(using: HostProps.str(p["fillRule"]) == "evenodd" ? .evenOdd : .winding)

        // ---- shapes ----
        case "fillRect":
            let r = rect()
            composite(c) { cc in paintPath(cc, CGPath(rect: r, transform: nil), fill: true) }
        case "strokeRect":
            let r = rect()
            composite(c) { cc in paintPath(cc, CGPath(rect: r, transform: nil), fill: false) }
        case "clearRect":
            c.clear(rect())
        case "fillCircle", "strokeCircle":
            let r = max(0, f("radius"))
            let circle = CGPath(ellipseIn: CGRect(x: f("x") - r, y: f("y") - r, width: 2 * r, height: 2 * r), transform: nil)
            composite(c) { cc in paintPath(cc, circle, fill: type == "fillCircle") }
        case "fillPolygon", "strokePolygon":
            let pts = CanvasPainter.pointsOf(p["points"])
            if pts.count < 2 { return }
            let poly = CGMutablePath()
            poly.move(to: pts[0])
            for i in 1..<pts.count { poly.addLine(to: pts[i]) }
            if !HostProps.isFalse(p["closed"]) { poly.closeSubpath() }
            composite(c) { cc in paintPath(cc, poly, fill: type == "fillPolygon") }

        // ---- text ----
        case "fillText", "strokeText":
            drawText(c, HostProps.str(p["text"]) ?? "", f("x"), f("y"), p["maxWidth"] != nil ? f("maxWidth") : nil, type == "fillText")

        // ---- images ----
        case "drawImage", "drawImageRect":
            guard let img = image(HostProps.str(p["src"] ?? p["imageId"]) ?? ""), let cg = img.cgImage else { return }
            let nw = Double(cg.width)
            let nh = Double(cg.height)
            var source: CGImage = cg
            let dst: CGRect
            if type == "drawImageRect" || p["sx"] != nil {
                let sr = CGRect(x: jsRound(n("sx")), y: jsRound(n("sy")), width: jsRound(n("sw", nw)), height: jsRound(n("sh", nh)))
                if let cropped = cg.cropping(to: sr) { source = cropped }
                let dx = n("dx", n("x")), dy = n("dy", n("y"))
                dst = CGRect(x: dx, y: dy, width: n("dw", n("width", nw)), height: n("dh", n("height", nh)))
            } else if p["width"] != nil || p["height"] != nil {
                dst = CGRect(x: n("x"), y: n("y"), width: n("width", nw), height: n("height", nh))
            } else {
                dst = CGRect(x: n("x"), y: n("y"), width: nw, height: nh)
            }
            let src = source
            composite(c) { cc in
                cc.interpolationQuality = .high
                Raster.drawImage(cc, src, dst)
            }

        // ---- state and transforms ----
        case "save":
            stack.append(state)
            c.saveGState()
        case "restore":
            if let s = stack.popLast() {
                state = s
                c.restoreGState()
            }
        case "translate":
            c.translateBy(x: f("x"), y: f("y"))
        case "rotate":
            c.rotate(by: f("angle"))
        case "scale":
            c.scaleBy(x: f("x", 1), y: CGFloat(CanvasPainter.num(p, "y", n("x", 1))))
        case "transform":
            c.concatenate(affine(p))
        case "setTransform":
            // Relative to the device-pixel base, like an HTML canvas of CSS size.
            c.concatenate(c.ctm.inverted())
            c.translateBy(x: 0, y: CGFloat(pixelHeight))
            c.scaleBy(x: 1, y: -1)
            c.scaleBy(x: dpr, y: dpr)
            c.concatenate(affine(p))
        case "resetTransform":
            c.concatenate(c.ctm.inverted())
            c.translateBy(x: 0, y: CGFloat(pixelHeight))
            c.scaleBy(x: 1, y: -1)
            c.scaleBy(x: dpr, y: dpr)

        // ---- styles ----
        case "setFillStyle":
            if let s = style(p) { state.fill = s }
        case "setStrokeStyle":
            if let s = style(p) { state.stroke = s }
        case "setLineWidth":
            state.lineWidth = f("width", 1)
        case "setLineCap":
            switch HostProps.str(p["cap"]) {
            case "round": state.cap = .round
            case "square": state.cap = .square
            default: state.cap = .butt
            }
        case "setLineJoin":
            switch HostProps.str(p["join"]) {
            case "round": state.join = .round
            case "bevel": state.join = .bevel
            default: state.join = .miter
            }
        case "setMiterLimit":
            state.miter = f("limit", 10)
        case "setLineDash":
            let segs = (asArray(p["segments"]) ?? []).compactMap { HostProps.num($0) }.filter { $0 >= 0 }.map { CGFloat($0) }
            state.dash = segs.isEmpty ? nil : (segs.count % 2 == 1 ? segs + segs : segs)
        case "setLineDashOffset":
            state.dashOffset = f("offset")
        case "setShadowBlur":
            state.shadowBlur = f("blur")
        case "setShadowColor":
            state.shadowColor = CanvasPainter.color(p["color"])
        case "setShadowOffsetX":
            state.shadowX = CGFloat(CanvasPainter.num(p, "offset", n("x")))
        case "setShadowOffsetY":
            state.shadowY = CGFloat(CanvasPainter.num(p, "offset", n("y")))
        case "setGlobalAlpha":
            state.alpha = CGFloat(min(1, max(0, n("alpha", 1))))
        case "setGlobalCompositeOperation":
            state.composite = HostProps.str(p["operation"]) ?? "source-over"
        case "setFont":
            state.font = parseFont(HostProps.str(p["font"]) ?? "10px sans-serif")
        case "setTextAlign":
            let a = HostProps.str(p["align"]) ?? ""
            state.align = ["left", "right", "center", "start", "end"].contains(a) ? a : "start"
        case "setTextBaseline":
            let b = HostProps.str(p["baseline"]) ?? ""
            state.baseline = ["top", "hanging", "middle", "alphabetic", "ideographic", "bottom"].contains(b) ? b : "alphabetic"

        // ---- gradients and patterns ----
        case "createLinearGradient":
            gradients[HostProps.str(p["id"]) ?? ""] = Grad("linear", colorsOf(p), stopsOf(p), n("x0"), n("y0"), n("x1"), n("y1"), 0, 0)
        case "createRadialGradient":
            gradients[HostProps.str(p["id"]) ?? ""] = Grad("radial", colorsOf(p), stopsOf(p),
                                                    CanvasPainter.num(p, "x0", n("x")), CanvasPainter.num(p, "y0", n("y")),
                                                    CanvasPainter.num(p, "x1", n("x")), CanvasPainter.num(p, "y1", n("y")),
                                                    n("r0"), CanvasPainter.num(p, "r1", n("r")))
        case "addColorStop":
            guard let g = gradients[HostProps.str(p["gradientId"] ?? p["id"]) ?? ""] else { return }
            let offset = min(1, max(0, n("offset")))
            let col = jsNumber(flattenOptional(p["color"])) != nil ? CanvasPainter.color(p["color"]) : 0xFF00_0000
            // Keep stops sorted, as CanvasGradient does.
            let i = g.stops.firstIndex { $0 > offset } ?? g.stops.count
            g.stops.insert(offset, at: i)
            g.colors.insert(col, at: i)
        case "createPattern":
            patterns[HostProps.str(p["id"]) ?? ""] = Pattern(src: HostProps.str(p["src"] ?? p["imageId"]) ?? "", repetition: HostProps.str(p["repetition"]) ?? "repeat")

        // ---- pixels ----
        case "createImageData":
            let w = max(1, Int(jsRound(n("width", 1))))
            let h = max(1, Int(jsRound(n("height", 1))))
            imageData[HostProps.str(p["id"]) ?? ""] = ImageData(w, h, [UInt32](repeating: 0, count: w * h))
        case "getImageData":
            let x = Int(jsRound(n("x") * Double(dpr)))
            let y = Int(jsRound(n("y") * Double(dpr)))
            let w = max(1, Int(jsRound(n("width", 1) * Double(dpr))))
            let h = max(1, Int(jsRound(n("height", 1) * Double(dpr))))
            var px = [UInt32](repeating: 0, count: w * h)
            let ix0 = max(0, x), iy0 = max(0, y)
            let ix1 = min(pixelWidth, x + w), iy1 = min(pixelHeight, y + h)
            if ix1 > ix0 && iy1 > iy0, let data = c.data?.bindMemory(to: UInt8.self, capacity: c.bytesPerRow * c.height) {
                for yy in iy0..<iy1 {
                    for xx in ix0..<ix1 {
                        let o = yy * c.bytesPerRow + xx * 4
                        let a = UInt32(data[o + 3])
                        func un(_ v: UInt8) -> UInt32 { a == 0 ? 0 : min(255, (UInt32(v) * 255 + a / 2) / a) }
                        px[(yy - y) * w + (xx - x)] = (a << 24) | (un(data[o]) << 16) | (un(data[o + 1]) << 8) | un(data[o + 2])
                    }
                }
            }
            imageData[HostProps.str(p["id"]) ?? ""] = ImageData(w, h, px)
        case "putImageData":
            var d: ImageData? = p["id"] != nil ? imageData[HostProps.str(p["id"]) ?? ""] : nil
            if let bytes = pixelsOf(p["data"]) {
                let w = max(1, Int(jsRound(n("width", Double(d?.width ?? 1)))))
                let h = max(1, Int(jsRound(n("height", Double(d?.height ?? Int((Double(bytes.count) / 4 / Double(w)).rounded(.up)))))))
                var px = [UInt32](repeating: 0, count: w * h)
                for i in 0..<min(w * h, bytes.count / 4) {
                    let o = i * 4
                    px[i] = (UInt32(bytes[o + 3]) << 24) | (UInt32(bytes[o]) << 16) | (UInt32(bytes[o + 1]) << 8) | UInt32(bytes[o + 2])
                }
                d = ImageData(w, h, px)
                if p["id"] != nil { imageData[HostProps.str(p["id"]) ?? ""] = d }
            }
            guard let src = d, let data = c.data?.bindMemory(to: UInt8.self, capacity: c.bytesPerRow * c.height) else { return }
            let x = Int(jsRound(n("x") * Double(dpr)))
            let y = Int(jsRound(n("y") * Double(dpr)))
            let ix0 = max(0, x), iy0 = max(0, y)
            let ix1 = min(pixelWidth, x + src.width), iy1 = min(pixelHeight, y + src.height)
            if ix1 <= ix0 || iy1 <= iy0 { return }
            for yy in iy0..<iy1 {
                for xx in ix0..<ix1 {
                    let v = src.pixels[(yy - y) * src.width + (xx - x)]
                    let a = (v >> 24) & 0xFF
                    func pre(_ ch: UInt32) -> UInt8 { UInt8((ch * a + 127) / 255) }
                    let o = yy * c.bytesPerRow + xx * 4
                    data[o] = pre((v >> 16) & 0xFF)
                    data[o + 1] = pre((v >> 8) & 0xFF)
                    data[o + 2] = pre(v & 0xFF)
                    data[o + 3] = UInt8(a)
                }
            }

        case "custom":
            guard let painter = CanvasPainter.customPainters[HostProps.str(p["name"]) ?? ""] else { return }
            c.saveGState()
            painter(c, p)
            c.restoreGState()
        default:
            break
        }
    }

    private func affine(_ p: JSONObject) -> CGAffineTransform {
        CGAffineTransform(a: CGFloat(CanvasPainter.num(p, "a", 1)), b: CGFloat(CanvasPainter.num(p, "b")), c: CGFloat(CanvasPainter.num(p, "c")),
                          d: CGFloat(CanvasPainter.num(p, "d", 1)), tx: CGFloat(CanvasPainter.num(p, "e")), ty: CGFloat(CanvasPainter.num(p, "f")))
    }

    private func style(_ p: JSONObject) -> Style? {
        if p["color"] != nil { return .solid(CanvasPainter.color(p["color"])) }
        if let id = HostProps.str(p["gradientId"]) { return gradients[id] != nil ? .gradient(id) : nil }
        if let id = HostProps.str(p["patternId"]) { return patterns[id] != nil ? .pattern(id) : nil }
        return nil
    }

    private func colorsOf(_ p: JSONObject) -> [Color] { (asArray(p["colors"]) ?? []).map { CanvasPainter.color($0) } }

    private func stopsOf(_ p: JSONObject) -> [Double] {
        let colors = asArray(p["colors"]) ?? []
        if let stops = asArray(p["stops"]), stops.count == colors.count { return stops.map { HostProps.num($0) ?? 0 } }
        return colors.indices.map { colors.count > 1 ? Double($0) / Double(colors.count - 1) : 0 }
    }

    /** RGBA bytes from an array of numbers or a base64 string. */
    private func pixelsOf(_ data: Any?) -> [UInt8]? {
        let v = flattenOptional(data)
        if let b = v as? [UInt8] { return b }
        if let l = asArray(v) { return l.map { UInt8(max(0, min(255, jsRound(HostProps.num($0) ?? 0)))) } }
        if let s = v as? String, !s.isEmpty { return try? Bytes.base64Decode(s) }
        return nil
    }

    private func drawText(_ c: CGContext, _ text: String, _ x: CGFloat, _ y: CGFloat, _ maxWidth: CGFloat?, _ fill: Bool) {
        let st = state
        let font = st.font
        var attrs: [NSAttributedString.Key: Any] = [.font: font]
        let solid: Color?
        if case .solid(let col) = fill ? st.fill : st.stroke { solid = col } else { solid = nil }
        let paintColor = solid ?? 0xFFFF_FFFF
        if fill {
            attrs[.foregroundColor] = Paints.uiColor(paintColor)
        } else {
            attrs[.strokeColor] = Paints.uiColor(paintColor)
            attrs[.strokeWidth] = font.pointSize > 0 ? st.lineWidth / font.pointSize * 100 : 0
        }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        let w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        var dx: CGFloat
        switch st.align {
        case "center": dx = -w / 2
        case "right", "end": dx = -w
        default: dx = 0
        }
        let ascent = font.ascender
        let descent = -font.descender
        let dy: CGFloat
        switch st.baseline {
        case "top": dy = ascent
        case "hanging": dy = ascent * 0.8
        case "middle": dy = (ascent - descent) / 2
        case "ideographic", "bottom": dy = -descent
        default: dy = 0
        }
        let squeeze = maxWidth.flatMap { $0 >= 0 && w > $0 && w > 0 ? $0 / w : nil }
        if let s = squeeze { dx *= s }
        let draw: (CGContext) -> Void = { cc in
            cc.saveGState()
            cc.translateBy(x: x + dx, y: y + dy)
            if let s = squeeze { cc.scaleBy(x: s, y: 1) }
            // Core Text draws y-up glyphs.
            cc.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            cc.textPosition = .zero
            if solid != nil {
                CTLineDraw(line, cc)
            } else {
                // Gradient / pattern text: the glyphs as a clip for the style.
                cc.setTextDrawingMode(.clip)
                CTLineDraw(line, cc)
                cc.textMatrix = .identity
                cc.translateBy(x: -(x + dx), y: -(y + dy))
                self.fillClip(cc, fill ? st.fill : st.stroke)
            }
            cc.restoreGState()
        }
        composite(c, draw)
    }
}

/** The `canvas` view kind: a bitmap the [CanvasPainter] draws, reporting pointer events. */
final class CanvasLeafView: UIView {
    private weak var owner: ElpianView?
    var commands: [Any?]?
    private(set) var painter: CanvasPainter!
    var backgroundColorValue: Color? {
        didSet { setNeedsDisplay() }
    }
    private var pointerIds: [ObjectIdentifier: Int] = [:]
    private var nextPointer = 1

    init(owner: ElpianView) {
        self.owner = owner
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        isMultipleTouchEnabled = true
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let images: ImageSource = owner.host?.images ?? NoImages()
        painter = CanvasPainter(images: images) { [weak self] in
            DispatchQueue.main.async { self?.repaint() }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /** Re-run the whole command list at the current size. */
    func repaint() {
        guard let cmds = commands, let o = owner else { return }
        painter.reset(o.frameValues[2], o.frameValues[3], o.scale)
        painter.run(cmds)
        setNeedsDisplay()
    }

    func replace(_ cmds: [Any?]) {
        commands = cmds
        repaint()
    }

    func append(_ cmds: [Any?]) {
        if commands == nil { commands = [] }
        commands?.append(contentsOf: cmds)
        if painter.context == nil, let o = owner { painter.reset(o.frameValues[2], o.frameValues[3], o.scale) }
        painter.run(cmds)
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        if let bg = backgroundColorValue {
            ctx.setFillColor(Paints.cgColor(bg))
            ctx.fill(bounds)
        }
        guard let img = painter.image else { return }
        ctx.interpolationQuality = .high
        Raster.drawImage(ctx, img, bounds)
    }

    private func emitPointer(_ type: String, _ touches: Set<UITouch>) {
        guard let o = owner, let surface = o.host?.surface else { return }
        for t in touches {
            let oid = ObjectIdentifier(t)
            let pid: Int
            if let existing = pointerIds[oid] {
                pid = existing
            } else {
                pid = nextPointer
                nextPointer += 1
                pointerIds[oid] = pid
            }
            let l = t.location(in: self)
            let s = t.location(in: surface)
            o.host?.emit(ViewEvent(id: o.viewId, type: type, x: Double(s.x), y: Double(s.y), localX: Double(l.x), localY: Double(l.y),
                                   buttons: type == "pointerup" ? 0 : 1, pointerId: pid))
            if type == "pointerup" { pointerIds.removeValue(forKey: oid) }
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { emitPointer("pointerdown", touches) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { emitPointer("pointermove", touches) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { emitPointer("pointerup", touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { emitPointer("pointerup", touches) }

    func release() {
        painter.release()
    }
}

/** An image source that never loads (a view detached from its renderer). */
final class NoImages: ImageSource {
    func load(_ src: String, _ callback: @escaping (UIImage?) -> Void) { callback(nil) }
}
#endif
