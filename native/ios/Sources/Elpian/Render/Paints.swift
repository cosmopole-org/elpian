#if canImport(UIKit)
import UIKit
import CoreGraphics
import CoreImage
#if !ELPIAN_SINGLE_MODULE
import ElpianCore
#endif

/**
 * Flutter painting values → CoreGraphics, with Flutter's geometry (Paints.kt
 * on Android, css.ts on the web): linear gradients run exactly from `begin`
 * to `end` within the box, radial radii are fractions of the shortest side,
 * sweeps start at 3 o'clock and turn clockwise, and blur radii follow
 * Flutter's `convertRadiusToSigma` (blurRadius·0.57735 + 0.5).
 *
 * Every context these helpers draw into is y-down (UIKit / CALayer contexts
 * and the bitmaps made by [Raster]).
 */
enum Paints {
    static let srgb: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    static func cgColor(_ c: Color) -> CGColor {
        CGColor(colorSpace: srgb, components: [CGFloat((c >> 16) & 0xFF) / 255, CGFloat((c >> 8) & 0xFF) / 255, CGFloat(c & 0xFF) / 255, CGFloat(c >> 24) / 255])
            ?? UIColor.black.cgColor
    }

    static func uiColor(_ c: Color) -> UIColor {
        UIColor(red: CGFloat((c >> 16) & 0xFF) / 255, green: CGFloat((c >> 8) & 0xFF) / 255, blue: CGFloat(c & 0xFF) / 255, alpha: CGFloat(c >> 24) / 255)
    }

    static func isTransparent(_ c: Color) -> Bool { (c >> 24) == 0 }

    // ---------------------------------------------------------------------
    // Shapes
    // ---------------------------------------------------------------------

    /** The outline of a box: a rect, a rect with eight radii (elliptical corners) or an inscribed oval. */
    static func shapePath(_ rect: CGRect, _ radii: [Double]?, _ oval: Bool) -> CGMutablePath {
        let p = CGMutablePath()
        if oval {
            p.addEllipse(in: rect)
        } else if let r = radii, r.contains(where: { $0 > 0 }) {
            addRoundRect(p, rect, r)
        } else {
            p.addRect(rect)
        }
        return p
    }

    /** A rounded rect with per-corner elliptical radii [tlx, tly, trx, try, brx, bry, blx, bly]. */
    static func addRoundRect(_ p: CGMutablePath, _ rect: CGRect, _ r: [Double]) {
        let k: CGFloat = 0.5522847498
        let x0 = rect.minX, y0 = rect.minY, x1 = rect.maxX, y1 = rect.maxY
        let tlx = CGFloat(r[0]), tly = CGFloat(r[1]), trx = CGFloat(r[2]), try_ = CGFloat(r[3])
        let brx = CGFloat(r[4]), bry = CGFloat(r[5]), blx = CGFloat(r[6]), bly = CGFloat(r[7])
        p.move(to: CGPoint(x: x0 + tlx, y: y0))
        p.addLine(to: CGPoint(x: x1 - trx, y: y0))
        if trx > 0 || try_ > 0 {
            p.addCurve(to: CGPoint(x: x1, y: y0 + try_), control1: CGPoint(x: x1 - trx + trx * k, y: y0), control2: CGPoint(x: x1, y: y0 + try_ - try_ * k))
        }
        p.addLine(to: CGPoint(x: x1, y: y1 - bry))
        if brx > 0 || bry > 0 {
            p.addCurve(to: CGPoint(x: x1 - brx, y: y1), control1: CGPoint(x: x1, y: y1 - bry + bry * k), control2: CGPoint(x: x1 - brx + brx * k, y: y1))
        }
        p.addLine(to: CGPoint(x: x0 + blx, y: y1))
        if blx > 0 || bly > 0 {
            p.addCurve(to: CGPoint(x: x0, y: y1 - bly), control1: CGPoint(x: x0 + blx - blx * k, y: y1), control2: CGPoint(x: x0, y: y1 - bly + bly * k))
        }
        p.addLine(to: CGPoint(x: x0, y: y0 + tly))
        if tlx > 0 || tly > 0 {
            p.addCurve(to: CGPoint(x: x0 + tlx, y: y0), control1: CGPoint(x: x0, y: y0 + tly - tly * k), control2: CGPoint(x: x0 + tlx - tlx * k, y: y0))
        }
        p.closeSubpath()
    }

    // ---------------------------------------------------------------------
    // Gradients
    // ---------------------------------------------------------------------

    private static func cgGradient(_ colors: [Color], _ stops: [Double]) -> CGGradient? {
        let cs = colors.map { cgColor($0) } as CFArray
        let locs = stops.map { CGFloat($0) }
        return CGGradient(colorsSpace: srgb, colors: cs, locations: locs)
    }

    private static func point(_ a: Alignment?, _ fallback: Alignment, _ r: CGRect) -> CGPoint {
        let al = a ?? fallback
        return CGPoint(x: r.minX + CGFloat((al.x + 1) / 2) * r.width, y: r.minY + CGFloat((al.y + 1) / 2) * r.height)
    }

    /** Fill the current clip with [g] laid out over [rect]. */
    static func drawGradient(_ ctx: CGContext, _ g: Gradient, _ rect: CGRect) {
        if g.colors.isEmpty { return }
        let r = CGRect(x: rect.minX, y: rect.minY, width: max(rect.width, 0.0001), height: max(rect.height, 0.0001))
        let (colors, stops) = PaintMath.colorsAndStops(g)
        let repeating = g.repeat == true
        let extend: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        switch g.kind {
        case .linear:
            let p0 = point(g.begin, .centerLeft, r)
            var p1 = point(g.end, .centerRight, r)
            if p0 == p1 { p1.x += 0.0001 }
            if !repeating {
                guard let grad = cgGradient(colors, stops) else { return }
                ctx.drawLinearGradient(grad, start: p0, end: p1, options: extend)
                return
            }
            let dx = Double(p1.x - p0.x), dy = Double(p1.y - p0.y)
            let len2 = dx * dx + dy * dy
            var tmin = Double.infinity, tmax = -Double.infinity
            for c in [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)] {
                let t = (Double(c.x - p0.x) * dx + Double(c.y - p0.y) * dy) / len2
                tmin = min(tmin, t)
                tmax = max(tmax, t)
            }
            let (rc, rs) = PaintMath.repeated(colors, stops, from: tmin, to: tmax)
            guard let grad = cgGradient(rc, rs) else { return }
            let a = CGPoint(x: Double(p0.x) + dx * tmin, y: Double(p0.y) + dy * tmin)
            let b = CGPoint(x: Double(p0.x) + dx * tmax, y: Double(p0.y) + dy * tmax)
            ctx.drawLinearGradient(grad, start: a, end: b, options: extend)
        case .radial:
            let c = point(g.center, .center, r)
            let radius = max(0.0001, (g.radius ?? 0.5) * Double(min(r.width, r.height)))
            if !repeating {
                guard let grad = cgGradient(colors, stops) else { return }
                ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(radius), options: extend)
                return
            }
            var far = 0.0
            for p in [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)] {
                far = max(far, hypot(Double(p.x - c.x), Double(p.y - c.y)))
            }
            let tmax = max(1, far / radius)
            let (rc, rs) = PaintMath.repeated(colors, stops, from: 0, to: tmax)
            guard let grad = cgGradient(rc, rs) else { return }
            ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(radius * tmax), options: extend)
        case .sweep:
            let c = point(g.center, .center, r)
            let (sc, ss) = PaintMath.sweepTable(g)
            drawSweep(ctx, center: c, start: g.startAngle ?? 0, colors: sc, stops: ss, cover: r)
        }
    }

    /**
     * A conic (sweep) gradient as a fan of thin wedges, each filled with the
     * table's colour at its middle angle — CoreGraphics has no conic shader.
     * Angles turn clockwise from 3 o'clock (y-down), rotated by [start].
     */
    static func drawSweep(_ ctx: CGContext, center c: CGPoint, start: Double, colors: [Color], stops: [Double], cover r: CGRect) {
        var far = 1.0
        for p in [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)] {
            far = max(far, hypot(Double(p.x - c.x), Double(p.y - c.y)))
        }
        far += 2
        let n = max(180, min(1440, Int(far * Double.pi)))
        let step = Double.pi * 2 / Double(n)
        ctx.saveGState()
        ctx.setShouldAntialias(false)
        for i in 0..<n {
            let a0 = start + Double(i) * step
            let a1 = a0 + step * 1.5
            let t = (Double(i) + 0.5) / Double(n)
            ctx.setFillColor(cgColor(PaintMath.colorAt(colors, stops, t)))
            ctx.move(to: c)
            ctx.addLine(to: CGPoint(x: Double(c.x) + far * cos(a0), y: Double(c.y) + far * sin(a0)))
            ctx.addLine(to: CGPoint(x: Double(c.x) + far * cos(a1), y: Double(c.y) + far * sin(a1)))
            ctx.closePath()
            ctx.fillPath()
        }
        ctx.restoreGState()
    }

    // ---------------------------------------------------------------------
    // Blend modes
    // ---------------------------------------------------------------------

    private static func normalize(_ mode: String) -> String {
        var out = ""
        for ch in mode {
            if ch.isUppercase {
                out += "-" + ch.lowercased()
            } else {
                out.append(ch)
            }
        }
        return out
    }

    /** A Flutter / CSS blend-mode or composite-operation name → CGBlendMode; nil when unknown. */
    static func cgBlendMode(_ mode: String?) -> CGBlendMode? {
        guard let mode = mode, !mode.isEmpty else { return nil }
        switch normalize(mode) {
        case "normal", "src-over", "source-over": return .normal
        case "multiply", "modulate": return .multiply
        case "screen": return .screen
        case "overlay": return .overlay
        case "darken": return .darken
        case "lighten": return .lighten
        case "color-dodge": return .colorDodge
        case "color-burn": return .colorBurn
        case "hard-light": return .hardLight
        case "soft-light": return .softLight
        case "difference": return .difference
        case "exclusion": return .exclusion
        case "hue": return .hue
        case "saturation": return .saturation
        case "color": return .color
        case "luminosity": return .luminosity
        case "plus", "lighter", "plus-lighter": return .plusLighter
        case "clear": return .clear
        case "src", "copy": return .copy
        case "dst", "destination": return nil
        case "src-in", "source-in": return .sourceIn
        case "src-out", "source-out": return .sourceOut
        case "src-atop", "source-atop": return .sourceAtop
        case "dst-over", "destination-over": return .destinationOver
        case "dst-in", "destination-in": return .destinationIn
        case "dst-out", "destination-out": return .destinationOut
        case "dst-atop", "destination-atop": return .destinationAtop
        case "xor": return .xor
        default: return nil
        }
    }

    /**
     * The Core Animation compositing filter for a view blend mode
     * (`CALayer.compositingFilter`), nil for source-over or unknown names.
     */
    static func caCompositingFilter(_ mode: String?) -> String? {
        guard let mode = mode, !mode.isEmpty else { return nil }
        switch normalize(mode) {
        case "multiply", "modulate": return "multiplyBlendMode"
        case "screen": return "screenBlendMode"
        case "overlay": return "overlayBlendMode"
        case "darken": return "darkenBlendMode"
        case "lighten": return "lightenBlendMode"
        case "color-dodge": return "colorDodgeBlendMode"
        case "color-burn": return "colorBurnBlendMode"
        case "hard-light": return "hardLightBlendMode"
        case "soft-light": return "softLightBlendMode"
        case "difference": return "differenceBlendMode"
        case "exclusion": return "exclusionBlendMode"
        case "hue": return "hueBlendMode"
        case "saturation": return "saturationBlendMode"
        case "color": return "colorBlendMode"
        case "luminosity": return "luminosityBlendMode"
        case "plus", "lighter", "plus-lighter": return "plusL"
        case "clear": return "clear"
        case "src", "copy": return "copy"
        case "src-in", "source-in": return "sourceIn"
        case "src-out", "source-out": return "sourceOut"
        case "src-atop", "source-atop": return "sourceAtop"
        case "dst-over", "destination-over": return "destinationOver"
        case "dst-in", "destination-in": return "destinationIn"
        case "dst-out", "destination-out": return "destinationOut"
        case "dst-atop", "destination-atop": return "destinationAtop"
        case "xor": return "xor"
        default: return nil
        }
    }

    // ---------------------------------------------------------------------
    // Filters (Core Image)
    // ---------------------------------------------------------------------

    /** Apply a 4×5 colour matrix (offsets in 0…255) with CIColorMatrix. */
    static func applyColorMatrix(_ image: CIImage, _ m: [Double]) -> CIImage {
        guard let f = CIFilter(name: "CIColorMatrix") else { return image }
        f.setValue(image, forKey: kCIInputImageKey)
        f.setValue(CIVector(x: CGFloat(m[0]), y: CGFloat(m[1]), z: CGFloat(m[2]), w: CGFloat(m[3])), forKey: "inputRVector")
        f.setValue(CIVector(x: CGFloat(m[5]), y: CGFloat(m[6]), z: CGFloat(m[7]), w: CGFloat(m[8])), forKey: "inputGVector")
        f.setValue(CIVector(x: CGFloat(m[10]), y: CGFloat(m[11]), z: CGFloat(m[12]), w: CGFloat(m[13])), forKey: "inputBVector")
        f.setValue(CIVector(x: CGFloat(m[15]), y: CGFloat(m[16]), z: CGFloat(m[17]), w: CGFloat(m[18])), forKey: "inputAVector")
        f.setValue(CIVector(x: CGFloat(m[4] / 255), y: CGFloat(m[9] / 255), z: CGFloat(m[14] / 255), w: CGFloat(m[19] / 255)), forKey: "inputBiasVector")
        return f.outputImage ?? image
    }

    /** A Gaussian blur of [sigma] px that keeps the image's extent (transparent outside). */
    static func blur(_ image: CIImage, sigma: Double) -> CIImage {
        if sigma <= 0 { return image }
        guard let f = CIFilter(name: "CIGaussianBlur") else { return image }
        f.setValue(image, forKey: kCIInputImageKey)
        f.setValue(sigma, forKey: kCIInputRadiusKey)
        return f.outputImage ?? image
    }

    static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
}

/**
 * Small bitmaps the painters rasterise into: gray alpha masks (shadows, text
 * shadows) blurred with [PaintMath.gaussian], drawn back tinted. Bitmaps are
 * y-down like the contexts they are drawn into.
 */
enum Raster {
    /** A y-down bitmap context of [w]×[h] px; gray (alpha mask) or premultiplied RGBA. */
    static func context(_ w: Int, _ h: Int, gray: Bool) -> CGContext? {
        guard w > 0, h > 0, w * h <= 16_000_000 else { return nil }
        let ctx: CGContext?
        if gray {
            ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        } else {
            ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: Paints.srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        guard let c = ctx else { return nil }
        c.translateBy(x: 0, y: CGFloat(h))
        c.scaleBy(x: 1, y: -1)
        return c
    }

    /** Blur a bitmap context's pixels in place with a Gaussian of [sigma] px. */
    static func blur(_ ctx: CGContext, sigma: Double) {
        guard sigma >= 0.3, let data = ctx.data else { return }
        let channels = ctx.bitsPerPixel / 8
        PaintMath.gaussian(data.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * ctx.height), width: ctx.width, height: ctx.height, stride: ctx.bytesPerRow, channels: channels, sigma: sigma)
    }

    /**
     * Rasterise [draw] (white on black, in points) blurred with a Gaussian of
     * [sigma] points into a gray mask covering ([w] + 2·[pad]) × ([h] + 2·[pad])
     * points at [scale] px per point, downsampled for wide blurs.
     */
    static func blurredMask(_ w: Double, _ h: Double, pad: Double, sigma: Double, scale: Double, _ draw: (CGContext) -> Void) -> CGImage? {
        let sigmaPx = sigma * scale
        let down = sigmaPx <= 8 ? 1.0 : max(0.125, 8 / sigmaPx)
        let px = scale * down
        let bw = max(1, Int(((w + 2 * pad) * px).rounded(.up)))
        let bh = max(1, Int(((h + 2 * pad) * px).rounded(.up)))
        guard let c = context(bw, bh, gray: true) else { return nil }
        c.scaleBy(x: CGFloat(Double(bw) / (w + 2 * pad)), y: CGFloat(Double(bh) / (h + 2 * pad)))
        c.translateBy(x: CGFloat(pad), y: CGFloat(pad))
        c.setFillColor(gray: 1, alpha: 1)
        c.setStrokeColor(gray: 1, alpha: 1)
        draw(c)
        blur(c, sigma: sigma * px)
        return c.makeImage()
    }

    /** Fill [rect] with [color] through the gray [mask] (y-down aware). */
    static func drawMask(_ ctx: CGContext, _ mask: CGImage, _ rect: CGRect, _ color: CGColor) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        let r = CGRect(origin: .zero, size: rect.size)
        ctx.clip(to: r, mask: mask)
        ctx.setFillColor(color)
        ctx.fill(r)
        ctx.restoreGState()
    }

    /** Draw a CGImage upright into a y-down context. */
    static func drawImage(_ ctx: CGContext, _ image: CGImage, _ rect: CGRect) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }
}
#endif
