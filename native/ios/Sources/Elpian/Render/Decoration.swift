#if canImport(UIKit)
import UIKit
#if !ELPIAN_SINGLE_MODULE
import ElpianCore
#endif

/**
 * Paints a view's decoration — Flutter's BoxDecoration plus the CSS extras the
 * core forwards (inset shadows, border styles, outline) — into a CALayer that
 * sits under the view's content (Decoration.kt on Android). The layer extends
 * past the view's bounds by the reach of its outer shadows and outline, so the
 * view's frame stays the border box its children lay out in and a clip on the
 * children never clips the shadow.
 *
 * Painting order: outer shadows (list order) → background colour → image (the
 * bottom-most CSS layer) → gradients bottom-first → inset shadows inside the
 * padding box → border → outline.
 */
final class DecorationLayer: CALayer {
    var background: Color?
    var gradients: [Gradient]?
    private(set) var image: DecorationImage?
    var border: Border?
    var radius: BorderRadius?
    var oval = false
    var shadows: [BoxShadow]?
    var outline: Outline?

    /** The loaded background image (nil while loading). */
    private var bitmap: UIImage?
    private var images: ImageSource?
    /** The view's size in points; the layer's frame is this grown by [pad]. */
    private var boxSize: CGSize = .zero
    private var pad: CGFloat = 0
    private var shadowCache: [String: CGImage] = [:]

    override init() {
        super.init()
        needsDisplayOnBoundsChange = true
        contentsScale = UIScreen.main.scale
        actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "frame": NSNull()]
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var isEmpty: Bool {
        background == nil && (gradients ?? []).isEmpty && image == nil && border == nil && (shadows ?? []).isEmpty && outline == nil
    }

    func setImage(_ img: DecorationImage?, _ source: ImageSource) {
        images = source
        if image?.src != img?.src { bitmap = nil }
        image = img
        guard let src = img?.src, !src.isEmpty else { return }
        source.load(src) { [weak self] loaded in
            guard let self = self, self.image?.src == src else { return }
            self.bitmap = loaded
            self.setNeedsDisplay()
        }
    }

    func clearCaches() { shadowCache.removeAll() }

    /** Lay the layer out for a view of [size] points and repaint. */
    func layout(for size: CGSize, scale: CGFloat) {
        var reach: Double = 0
        for s in shadows ?? [] where s.inset != true {
            reach = max(reach, abs(s.dx) + abs(s.dy) + max(0, s.spread) + 3 * PaintMath.sigma(s.blur) + 2)
        }
        if let o = outline, o.width > 0 { reach = max(reach, max(0, o.offset) + o.width + 2) }
        if border != nil { reach = max(reach, 2) }
        let p = CGFloat(reach.rounded(.up))
        if size != boxSize || p != pad { shadowCache.removeAll() }
        boxSize = size
        pad = p
        contentsScale = scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = CGRect(x: -p, y: -p, width: size.width + 2 * p, height: size.height + 2 * p)
        CATransaction.commit()
        setNeedsDisplay()
    }

    override func draw(in ctx: CGContext) {
        let w = Double(boxSize.width)
        let h = Double(boxSize.height)
        if w <= 0 && h <= 0 { return }
        ctx.translateBy(x: pad, y: pad)
        let radii = oval ? nil : PaintMath.radii(radius, w, h)
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        // 1. Outer shadows (Flutter paints them in list order, under the box).
        for s in shadows ?? [] where s.inset != true { drawOuterShadow(ctx, s, w, h, radii) }
        let shape = Paints.shapePath(rect, radii, oval)
        // 2. Background colour.
        if let c = background {
            ctx.addPath(shape)
            ctx.setFillColor(Paints.cgColor(c))
            ctx.fillPath()
        }
        // 3. Image, then gradients bottom-first.
        if let img = image, let bmp = bitmap { drawImage(ctx, img, bmp, shape, w, h) }
        for g in gradients ?? [] {
            ctx.saveGState()
            ctx.addPath(shape)
            ctx.clip()
            Paints.drawGradient(ctx, g, rect)
            ctx.restoreGState()
        }
        // 4. Inset shadows inside the padding box.
        for s in shadows ?? [] where s.inset == true { drawInsetShadow(ctx, s, w, h, radii) }
        // 5. Border and outline.
        if let b = border { drawBorder(ctx, b, w, h, radii) }
        if let o = outline { drawOutline(ctx, o, w, h, radii) }
    }

    // ---------------------------------------------------------------------
    // Shadows
    // ---------------------------------------------------------------------

    private func drawOuterShadow(_ ctx: CGContext, _ s: BoxShadow, _ w: Double, _ h: Double, _ radii: [Double]?) {
        if Paints.isTransparent(s.color) { return }
        let spread = s.spread
        let sw = w + 2 * spread
        let sh = h + 2 * spread
        if sw <= 0 || sh <= 0 { return }
        let r = PaintMath.adjust(radii, spread, spread, spread, spread)
        let sigma = PaintMath.sigma(s.blur)
        let oval = self.oval
        if sigma <= 0 {
            ctx.addPath(Paints.shapePath(CGRect(x: -spread + s.dx, y: -spread + s.dy, width: sw, height: sh), r, oval))
            ctx.setFillColor(Paints.cgColor(s.color))
            ctx.fillPath()
            return
        }
        let pad = (3 * sigma).rounded(.up)
        let key = "o|\(sw)|\(sh)|\(r ?? [])|\(oval)|\(sigma)"
        let mask = shadowCache[key] ?? Raster.blurredMask(sw, sh, pad: pad, sigma: sigma, scale: Double(contentsScale)) { c in
            c.addPath(Paints.shapePath(CGRect(x: 0, y: 0, width: sw, height: sh), r, oval))
            c.fillPath()
        }
        guard let m = mask else { return }
        shadowCache[key] = m
        Raster.drawMask(ctx, m, CGRect(x: -spread - pad + s.dx, y: -spread - pad + s.dy, width: sw + 2 * pad, height: sh + 2 * pad), Paints.cgColor(s.color))
    }

    private func drawInsetShadow(_ ctx: CGContext, _ s: BoxShadow, _ w: Double, _ h: Double, _ radii: [Double]?) {
        if Paints.isTransparent(s.color) { return }
        let ins = border?.insets ?? .zero
        let l = ins.left, t = ins.top, rr = ins.right, b = ins.bottom
        let iw = w - l - rr
        let ih = h - t - b
        if iw <= 0 || ih <= 0 { return }
        let innerRadii = PaintMath.adjust(radii, -l, -t, -rr, -b)
        let spread = s.spread
        let dx = s.dx
        let dy = s.dy
        let sigma = PaintMath.sigma(s.blur)
        let holeRadii = PaintMath.adjust(innerRadii, -spread, -spread, -spread, -spread)
        let hole = CGRect(x: spread + dx, y: spread + dy, width: iw - 2 * spread, height: ih - 2 * spread)
        let oval = self.oval
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(l), y: CGFloat(t))
        ctx.addPath(Paints.shapePath(CGRect(x: 0, y: 0, width: iw, height: ih), innerRadii, oval))
        ctx.clip()
        let far = 3 * sigma + abs(dx) + abs(dy) + abs(spread) + 1
        let ring: (CGContext) -> Void = { c in
            let p = CGMutablePath()
            p.addRect(CGRect(x: -far, y: -far, width: iw + 2 * far, height: ih + 2 * far))
            if hole.width > 0 && hole.height > 0 { p.addPath(Paints.shapePath(hole, holeRadii, oval)) }
            c.addPath(p)
            c.fillPath(using: .evenOdd)
        }
        if sigma <= 0 {
            ctx.setFillColor(Paints.cgColor(s.color))
            ring(ctx)
        } else {
            let key = "i|\(iw)|\(ih)|\(innerRadii ?? [])|\(oval)|\(sigma)|\(hole)|\(holeRadii ?? [])"
            if let m = shadowCache[key] ?? Raster.blurredMask(iw, ih, pad: 0, sigma: sigma, scale: Double(contentsScale), ring) {
                shadowCache[key] = m
                Raster.drawMask(ctx, m, CGRect(x: 0, y: 0, width: iw, height: ih), Paints.cgColor(s.color))
            }
        }
        ctx.restoreGState()
    }

    // ---------------------------------------------------------------------
    // Background image (CSS background-size / position / repeat)
    // ---------------------------------------------------------------------

    private func drawImage(_ ctx: CGContext, _ img: DecorationImage, _ bmp: UIImage, _ shape: CGPath, _ w: Double, _ h: Double) {
        // Natural size in points (one image pixel per logical px, as Android's density scaling).
        let nw = Double(bmp.size.width * bmp.scale)
        let nh = Double(bmp.size.height * bmp.scale)
        if nw <= 0 || nh <= 0 { return }
        var tw: Double
        var th: Double
        if let size = img.size, size.width != nil || size.height != nil {
            let sw = size.width
            let sh = size.height
            tw = sw ?? (sh != nil ? sh! * nw / nh : nw)
            th = sh ?? (sw != nil ? sw! * nh / nw : nh)
        } else {
            switch HostProps.fit(img.fit) {
            case "cover": let s = max(w / nw, h / nh); tw = nw * s; th = nh * s
            case "contain", "scaleDown": let s = min(w / nw, h / nh); tw = nw * s; th = nh * s
            case "fill": tw = w; th = h
            case "fitWidth": tw = w; th = w * nh / nw
            case "fitHeight": th = h; tw = h * nw / nh
            default: tw = nw; th = nh
            }
        }
        if tw <= 0 || th <= 0 { return }
        let a = img.alignment ?? .center
        let x = (w - tw) * (a.x + 1) / 2
        let y = (h - th) * (a.y + 1) / 2
        let repeatMode = img.repeat ?? "no-repeat"
        let rx = ["repeat", "repeat-x", "space", "round"].contains(repeatMode)
        let ry = ["repeat", "repeat-y", "space", "round"].contains(repeatMode)
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        ctx.interpolationQuality = .high
        UIGraphicsPushContext(ctx)
        if !rx && !ry {
            bmp.draw(in: CGRect(x: x, y: y, width: tw, height: th))
        } else {
            // Tile from the aligned origin outward over the repeating axes.
            var x0 = x
            var y0 = y
            if rx { x0 = x - (x / tw).rounded(.up) * tw }
            if ry { y0 = y - (y / th).rounded(.up) * th }
            let x1 = rx ? w : x + tw
            let y1 = ry ? h : y + th
            var count = 0
            var yy = y0
            while yy < y1 && count < 20_000 {
                var xx = x0
                while xx < x1 && count < 20_000 {
                    bmp.draw(in: CGRect(x: xx, y: yy, width: tw, height: th))
                    xx += tw
                    count += 1
                }
                yy += th
            }
        }
        UIGraphicsPopContext()
        ctx.restoreGState()
    }

    // ---------------------------------------------------------------------
    // Borders
    // ---------------------------------------------------------------------

    private func sideWidth(_ s: BorderSide) -> Double { s.style == .none || s.width <= 0 ? 0 : s.width }

    private func drawBorder(_ ctx: CGContext, _ b: Border, _ w: Double, _ h: Double, _ radii: [Double]?) {
        let t = sideWidth(b.top)
        let r = sideWidth(b.right)
        let bo = sideWidth(b.bottom)
        let l = sideWidth(b.left)
        if t == 0 && r == 0 && bo == 0 && l == 0 { return }
        let sides: [(BorderSide, Double)] = [(b.top, t), (b.right, r), (b.bottom, bo), (b.left, l)]
        let visible = sides.filter { $0.1 > 0 }
        let uniform = visible.count == 4 && visible.allSatisfy { $0.0.color == visible[0].0.color && $0.0.style == visible[0].0.style }
        let uniformWidth = uniform && t == r && r == bo && bo == l
        if uniform {
            paintBorderRegion(ctx, visible[0].0.style, visible[0].0.color, w, h, radii, t, r, bo, l, uniformWidth)
            return
        }
        // Per side: clip to the side's trapezoid (outer corner → inner corner), like CSS.
        for (i, (side, width)) in sides.enumerated() {
            if width <= 0 || Paints.isTransparent(side.color) { continue }
            ctx.saveGState()
            ctx.addPath(extendTrapezoid(i, w, h, t, r, bo, l))
            ctx.clip()
            paintBorderRegion(ctx, side.style, side.color, w, h, radii, t, r, bo, l, false, i)
            ctx.restoreGState()
        }
    }

    /** The side's trapezoid, extended outward so antialiased edges are not cut. */
    private func extendTrapezoid(_ i: Int, _ w: Double, _ h: Double, _ t: Double, _ r: Double, _ b: Double, _ l: Double) -> CGPath {
        let e = 2.0
        let p = CGMutablePath()
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }
        switch i {
        case 0: p.addLines(between: [pt(-e, -e), pt(w + e, -e), pt(w - r, t), pt(l, t)])
        case 1: p.addLines(between: [pt(w + e, -e), pt(w + e, h + e), pt(w - r, h - b), pt(w - r, t)])
        case 2: p.addLines(between: [pt(w + e, h + e), pt(-e, h + e), pt(l, h - b), pt(w - r, h - b)])
        default: p.addLines(between: [pt(-e, h + e), pt(-e, -e), pt(l, t), pt(l, h - b)])
        }
        p.closeSubpath()
        return p
    }

    private func ring(_ outer: CGRect, _ outerRadii: [Double]?, _ l: Double, _ t: Double, _ r: Double, _ b: Double) -> CGPath {
        let p = CGMutablePath()
        p.addPath(Paints.shapePath(outer, outerRadii, oval))
        let inner = CGRect(x: Double(outer.minX) + l, y: Double(outer.minY) + t, width: Double(outer.width) - l - r, height: Double(outer.height) - t - b)
        if inner.width > 0 && inner.height > 0 { p.addPath(Paints.shapePath(inner, PaintMath.adjust(outerRadii, -l, -t, -r, -b), oval)) }
        return p
    }

    /** Fill (solid / double) or stroke (dashed / dotted) the border ring; [only] limits a stroked side to one edge. */
    private func paintBorderRegion(_ ctx: CGContext, _ style: BorderStyleName, _ color: Color, _ w: Double, _ h: Double, _ radii: [Double]?,
                                   _ t: Double, _ r: Double, _ b: Double, _ l: Double, _ uniformWidth: Bool, _ only: Int = -1) {
        let cg = Paints.cgColor(color)
        let outer = CGRect(x: 0, y: 0, width: w, height: h)
        switch style {
        case .none:
            return
        case .solid:
            ctx.addPath(ring(outer, radii, l, t, r, b))
            ctx.setFillColor(cg)
            ctx.fillPath(using: .evenOdd)
        case .double:
            ctx.setFillColor(cg)
            ctx.addPath(ring(outer, radii, l / 3, t / 3, r / 3, b / 3))
            ctx.fillPath(using: .evenOdd)
            let mid = CGRect(x: l * 2 / 3, y: t * 2 / 3, width: w - l * 2 / 3 - r * 2 / 3, height: h - t * 2 / 3 - b * 2 / 3)
            ctx.addPath(ring(mid, PaintMath.adjust(radii, -l * 2 / 3, -t * 2 / 3, -r * 2 / 3, -b * 2 / 3), l / 3, t / 3, r / 3, b / 3))
            ctx.fillPath(using: .evenOdd)
        case .dashed, .dotted:
            let dotted = style == .dotted
            ctx.setStrokeColor(cg)
            func effect(_ width: Double) {
                ctx.setLineWidth(CGFloat(width))
                if dotted {
                    ctx.setLineCap(.round)
                    ctx.setLineDash(phase: 0, lengths: [0.001, CGFloat(width * 2)])
                } else {
                    ctx.setLineCap(.butt)
                    let dash = CGFloat(max(3 * width, 2))
                    ctx.setLineDash(phase: 0, lengths: [dash, dash])
                }
            }
            if uniformWidth && only < 0 {
                effect(t)
                let inset = CGRect(x: t / 2, y: t / 2, width: w - t, height: h - t)
                ctx.addPath(Paints.shapePath(inset, PaintMath.adjust(radii, -t / 2, -t / 2, -t / 2, -t / 2), oval))
                ctx.strokePath()
                return
            }
            let edges = only >= 0 ? [only] : [0, 1, 2, 3]
            for e in edges {
                switch e {
                case 0 where t > 0: effect(t); ctx.move(to: CGPoint(x: 0, y: t / 2)); ctx.addLine(to: CGPoint(x: w, y: t / 2))
                case 1 where r > 0: effect(r); ctx.move(to: CGPoint(x: w - r / 2, y: 0)); ctx.addLine(to: CGPoint(x: w - r / 2, y: h))
                case 2 where b > 0: effect(b); ctx.move(to: CGPoint(x: w, y: h - b / 2)); ctx.addLine(to: CGPoint(x: 0, y: h - b / 2))
                case 3 where l > 0: effect(l); ctx.move(to: CGPoint(x: l / 2, y: h)); ctx.addLine(to: CGPoint(x: l / 2, y: 0))
                default: continue
                }
                ctx.strokePath()
            }
        }
    }

    private func drawOutline(_ ctx: CGContext, _ o: Outline, _ w: Double, _ h: Double, _ radii: [Double]?) {
        if o.width <= 0 || o.style == "none" { return }
        let ow = o.width
        let grow = o.offset + ow / 2
        ctx.saveGState()
        ctx.setStrokeColor(Paints.cgColor(o.color))
        ctx.setLineWidth(CGFloat(ow))
        switch o.style {
        case "dashed":
            let d = CGFloat(max(3 * ow, 2))
            ctx.setLineDash(phase: 0, lengths: [d, d])
        case "dotted":
            ctx.setLineCap(.round)
            ctx.setLineDash(phase: 0, lengths: [0.001, CGFloat(ow * 2)])
        default:
            break
        }
        let rr = CGRect(x: -grow, y: -grow, width: w + 2 * grow, height: h + 2 * grow)
        ctx.addPath(Paints.shapePath(rr, PaintMath.adjust(radii, grow, grow, grow, grow), oval))
        ctx.strokePath()
        ctx.restoreGState()
    }
}
#endif
