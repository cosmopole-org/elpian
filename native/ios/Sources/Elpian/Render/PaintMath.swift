#if canImport(UIKit) || ELPIAN_HOST_TYPECHECK
import Foundation
#if !ELPIAN_SINGLE_MODULE
import ElpianCore
#endif

/**
 * The platform-independent arithmetic of the painters (Blur.kt and the
 * colour / gradient parts of Paints.kt on Android): Flutter's blur sigma,
 * a CPU Gaussian for shadow masks and backdrops, CSS filter colour matrices
 * and the gradient stop tables the CoreGraphics renderer draws.
 */
enum PaintMath {
    /** Flutter's `convertRadiusToSigma`, in logical px. */
    static func sigma(_ blurRadius: Double) -> Double { blurRadius > 0 ? blurRadius * 0.57735 + 0.5 : 0 }

    // ---------------------------------------------------------------------
    // Gaussian blur (three box passes), in place
    // ---------------------------------------------------------------------

    /**
     * Blur [pixels] (`width`×`height`, [channels] interleaved bytes per pixel,
     * rows [stride] bytes apart) with a Gaussian of [sigma] px.
     */
    static func gaussian(_ pixels: UnsafeMutablePointer<UInt8>, width w: Int, height h: Int, stride: Int, channels: Int, sigma: Double) {
        if sigma < 0.3 || w <= 0 || h <= 0 { return }
        let n = w * h * channels
        var a = [Int32](repeating: 0, count: n)
        var b = [Int32](repeating: 0, count: n)
        for y in 0..<h {
            for x in 0..<w {
                for c in 0..<channels { a[(y * w + x) * channels + c] = Int32(pixels[y * stride + x * channels + c]) }
            }
        }
        for box in boxes(sigma, 3) {
            let r = (box - 1) / 2
            if r <= 0 { continue }
            boxH(&a, &b, w, h, channels, r)
            boxV(&b, &a, w, h, channels, r)
        }
        for y in 0..<h {
            for x in 0..<w {
                for c in 0..<channels { pixels[y * stride + x * channels + c] = UInt8(clamping: a[(y * w + x) * channels + c]) }
            }
        }
    }

    static func boxes(_ sigma: Double, _ n: Int) -> [Int] {
        let wIdeal = (12 * sigma * sigma / Double(n) + 1).squareRoot()
        var wl = Int(wIdeal.rounded(.down))
        if wl % 2 == 0 { wl -= 1 }
        let wu = wl + 2
        let mIdeal = (12 * sigma * sigma - Double(n * wl * wl) - Double(4 * n * wl) - Double(3 * n)) / Double(-4 * wl - 4)
        let m = Int(jsRound(mIdeal))
        return (0..<n).map { $0 < m ? wl : wu }
    }

    private static func boxH(_ src: inout [Int32], _ dst: inout [Int32], _ w: Int, _ h: Int, _ ch: Int, _ r: Int) {
        let div = Int32(2 * r + 1)
        for y in 0..<h {
            let row = y * w
            for c in 0..<ch {
                var sum: Int32 = 0
                for i in -r...r { sum += src[(row + min(w - 1, max(0, i))) * ch + c] }
                for x in 0..<w {
                    dst[(row + x) * ch + c] = sum / div
                    let pOut = src[(row + max(0, x - r)) * ch + c]
                    let pIn = src[(row + min(w - 1, x + r + 1)) * ch + c]
                    sum += pIn - pOut
                }
            }
        }
    }

    private static func boxV(_ src: inout [Int32], _ dst: inout [Int32], _ w: Int, _ h: Int, _ ch: Int, _ r: Int) {
        let div = Int32(2 * r + 1)
        for x in 0..<w {
            for c in 0..<ch {
                var sum: Int32 = 0
                for i in -r...r { sum += src[(min(h - 1, max(0, i)) * w + x) * ch + c] }
                for y in 0..<h {
                    dst[(y * w + x) * ch + c] = sum / div
                    let pOut = src[(max(0, y - r) * w + x) * ch + c]
                    let pIn = src[(min(h - 1, y + r + 1) * w + x) * ch + c]
                    sum += pIn - pOut
                }
            }
        }
    }

    // ---------------------------------------------------------------------
    // CSS filter colour matrices (4×5, offsets in 0…255 like android.graphics.ColorMatrix)
    // ---------------------------------------------------------------------

    /** `a` then `b` (ColorMatrix.postConcat: result = b · a). */
    static func concat(_ a: [Double], _ b: [Double]) -> [Double] {
        var out = [Double](repeating: 0, count: 20)
        for row in 0..<4 {
            for col in 0..<5 {
                var v = 0.0
                for k in 0..<4 { v += b[row * 5 + k] * a[k * 5 + col] }
                if col == 4 { v += b[row * 5 + 4] }
                out[row * 5 + col] = v
            }
        }
        return out
    }

    /**
     * The colour part of a CSS filter list as one matrix, in the order the web
     * renderer emits them: brightness, contrast, grayscale, hue-rotate,
     * invert, saturate, sepia, opacity. Nil when there is nothing to apply.
     */
    static func colorMatrix(_ f: Filter?) -> [Double]? {
        guard let f = f else { return nil }
        var out: [Double]?
        func add(_ m: [Double]) { out = out.map { concat($0, m) } ?? m }
        if let v = f.brightness { add([v, 0, 0, 0, 0, 0, v, 0, 0, 0, 0, 0, v, 0, 0, 0, 0, 0, 1, 0]) }
        if let v = f.contrast {
            let t = 255 * (0.5 - 0.5 * v)
            add([v, 0, 0, 0, t, 0, v, 0, 0, t, 0, 0, v, 0, t, 0, 0, 0, 1, 0])
        }
        if let g = f.grayscale {
            let a = 1 - min(1, max(0, g))
            add([
                0.2126 + 0.7874 * a, 0.7152 - 0.7152 * a, 0.0722 - 0.0722 * a, 0, 0,
                0.2126 - 0.2126 * a, 0.7152 + 0.2848 * a, 0.0722 - 0.0722 * a, 0, 0,
                0.2126 - 0.2126 * a, 0.7152 - 0.7152 * a, 0.0722 + 0.9278 * a, 0, 0,
                0, 0, 0, 1, 0,
            ])
        }
        if let deg = f.hueRotate {
            let r = deg * Double.pi / 180
            let c = cos(r)
            let s = sin(r)
            add([
                0.213 + c * 0.787 - s * 0.213, 0.715 - c * 0.715 - s * 0.715, 0.072 - c * 0.072 + s * 0.928, 0, 0,
                0.213 - c * 0.213 + s * 0.143, 0.715 + c * 0.285 + s * 0.140, 0.072 - c * 0.072 - s * 0.283, 0, 0,
                0.213 - c * 0.213 - s * 0.787, 0.715 - c * 0.715 + s * 0.715, 0.072 + c * 0.928 + s * 0.072, 0, 0,
                0, 0, 0, 1, 0,
            ])
        }
        if let i = f.invert {
            let a = min(1, max(0, i))
            let k = 1 - 2 * a
            let t = 255 * a
            add([k, 0, 0, 0, t, 0, k, 0, 0, t, 0, 0, k, 0, t, 0, 0, 0, 1, 0])
        }
        if let sat = f.saturate {
            // ColorMatrix.setSaturation.
            let s = max(0, sat)
            let inv = 1 - s
            let r = 0.213 * inv
            let g = 0.715 * inv
            let b = 0.072 * inv
            add([r + s, g, b, 0, 0, r, g + s, b, 0, 0, r, g, b + s, 0, 0, 0, 0, 0, 1, 0])
        }
        if let sp = f.sepia {
            let a = 1 - min(1, max(0, sp))
            add([
                0.393 + 0.607 * a, 0.769 - 0.769 * a, 0.189 - 0.189 * a, 0, 0,
                0.349 - 0.349 * a, 0.686 + 0.314 * a, 0.168 - 0.168 * a, 0, 0,
                0.272 - 0.272 * a, 0.534 - 0.534 * a, 0.131 + 0.869 * a, 0, 0,
                0, 0, 0, 1, 0,
            ])
        }
        if let o = f.opacity {
            let v = min(1, max(0, o))
            add([1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, v, 0])
        }
        return out
    }

    // ---------------------------------------------------------------------
    // Gradient stop tables
    // ---------------------------------------------------------------------

    /** Colours and non-decreasing positions in 0…1 (at least two entries). */
    static func colorsAndStops(_ g: Gradient) -> ([Color], [Double]) {
        let stops = g.resolvedStops()
        var colors = g.colors
        var pos = stops.map { min(1, max(0, $0)) }
        if pos.count > 1 { for i in 1..<pos.count where pos[i] < pos[i - 1] { pos[i] = pos[i - 1] } }
        if colors.count == 1 {
            colors = [colors[0], colors[0]]
            pos = [0, 1]
        }
        return (colors, pos)
    }

    /**
     * A repeating gradient's table over the parameter range [from]…[to] (in
     * units of one period), re-expressed in 0…1 of that range — what
     * CoreGraphics draws between the extended end points.
     */
    static func repeated(_ colors: [Color], _ stops: [Double], from: Double, to: Double) -> ([Color], [Double]) {
        let span = to - from
        if span <= 0 || colors.isEmpty { return (colors, stops) }
        var outC: [Color] = []
        var outS: [Double] = []
        var base = (from).rounded(.down)
        // Never more than a few thousand periods.
        let maxPeriods = 2048.0
        var periods = 0.0
        while base < to && periods < maxPeriods {
            for i in 0..<colors.count {
                let p = base + stops[i]
                outC.append(colors[i])
                outS.append((p - from) / span)
            }
            base += 1
            periods += 1
        }
        return (outC, outS)
    }

    /**
     * The sweep table: colours spread over the arc start…end (radians) as a
     * fraction of the full turn, repeated when asked, padded to 1 with the
     * last colour (Paints.kt's SweepGradient stops).
     */
    static func sweepTable(_ g: Gradient) -> ([Color], [Double]) {
        let (colors, stops) = colorsAndStops(g)
        let start = g.startAngle ?? 0
        let end = g.endAngle ?? Double.pi * 2
        let span = (end - start) > 0 ? end - start : Double.pi * 2
        let frac = span / (Double.pi * 2)
        var outC: [Color] = []
        var outS: [Double] = []
        if g.repeat == true && frac < 1 {
            var base = 0.0
            outer: while base < 1 {
                for i in 0..<colors.count {
                    let p = base + stops[i] * frac
                    if p > 1 { break outer }
                    outC.append(colors[i])
                    outS.append(p)
                }
                base += frac
            }
        } else {
            for i in 0..<colors.count {
                outC.append(colors[i])
                outS.append(min(1, stops[i] * frac))
            }
        }
        if (outS.last ?? 0) < 1 {
            outC.append(colors[colors.count - 1])
            outS.append(1)
        }
        if outS.count > 1 { for i in 1..<outS.count where outS[i] < outS[i - 1] { outS[i] = outS[i - 1] } }
        return (outC, outS)
    }

    /** The colour at [t] (0…1) of a stop table, interpolated in ARGB. */
    static func colorAt(_ colors: [Color], _ stops: [Double], _ t: Double) -> Color {
        guard let first = colors.first else { return 0 }
        if t <= stops[0] { return first }
        for i in 1..<colors.count where t <= stops[i] {
            let s0 = stops[i - 1]
            let s1 = stops[i]
            let f = s1 > s0 ? (t - s0) / (s1 - s0) : 1
            return lerpColor(colors[i - 1], colors[i], f)
        }
        return colors[colors.count - 1]
    }

    /** Blend two ARGB colours channel-wise (Controls.kt `lerpColor`). */
    static func lerpARGB(_ a: Color, _ b: Color, _ t: Double) -> Color {
        func ch(_ s: UInt32) -> UInt32 {
            let x = Double((a >> s) & 0xFF)
            let y = Double((b >> s) & 0xFF)
            return UInt32(max(0, min(255, jsRound(x + (y - x) * t)))) & 0xFF
        }
        return (ch(24) << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0)
    }

    /** [c] with its alpha scaled by [a]. */
    static func withAlpha(_ c: Color, _ a: Double) -> Color {
        let alpha = UInt32(max(0, min(255, jsRound(Double(c >> 24) * a))))
        return (alpha << 24) | (c & 0x00FF_FFFF)
    }

    // ---------------------------------------------------------------------
    // Flutter BoxFit
    // ---------------------------------------------------------------------

    /**
     * Flutter `applyBoxFit` + `Alignment.inscribe`: where an image of [iw]×[ih]
     * (pixels) lands in a [bw]×[bh] box (points); [scale] is the pixel → point
     * factor for `none` / `scaleDown` (natural size).
     */
    static func fitRect(_ fit: String?, _ iw: Double, _ ih: Double, _ bw: Double, _ bh: Double, _ a: Alignment, _ scale: Double) -> (x: Double, y: Double, w: Double, h: Double) {
        var dw: Double
        var dh: Double
        switch fit {
        case "fill": dw = bw; dh = bh
        case "cover": let s = max(bw / iw, bh / ih); dw = iw * s; dh = ih * s
        case "fitWidth": dw = bw; dh = ih * bw / iw
        case "fitHeight": dh = bh; dw = iw * bh / ih
        case "none": dw = iw * scale; dh = ih * scale
        case "scaleDown": let s = min(scale, min(bw / iw, bh / ih)); dw = iw * s; dh = ih * s
        default: let s = min(bw / iw, bh / ih); dw = iw * s; dh = ih * s
        }
        let x = (bw - dw) * (a.x + 1) / 2
        let y = (bh - dh) * (a.y + 1) / 2
        return (x, y, dw, dh)
    }

    /** Radii (x, y per corner, clockwise from top-left), scaled down as CSS / Flutter do when they overlap. */
    static func scaleRadii(_ a: [Double], _ w: Double, _ h: Double) -> [Double] {
        var f = 1.0
        func lim(_ len: Double, _ s: Double) { if s > 0 && len / s < f { f = len / s } }
        lim(w, a[0] + a[2])
        lim(w, a[6] + a[4])
        lim(h, a[1] + a[7])
        lim(h, a[3] + a[5])
        if f < 1 { return a.map { $0 * max(0, f) } }
        return a
    }

    /** Radii grown (or shrunk, for negative values) per side, never below 0. */
    static func adjust(_ r: [Double]?, _ left: Double, _ top: Double, _ right: Double, _ bottom: Double) -> [Double]? {
        guard let r = r else { return nil }
        return [
            max(0, r[0] + left), max(0, r[1] + top),
            max(0, r[2] + right), max(0, r[3] + top),
            max(0, r[4] + right), max(0, r[5] + bottom),
            max(0, r[6] + left), max(0, r[7] + bottom),
        ]
    }

    /** The eight radii of a [BorderRadius] in a w×h box, nil when square. */
    static func radii(_ r: BorderRadius?, _ w: Double, _ h: Double) -> [Double]? {
        guard let r = r, !r.isZero else { return nil }
        return scaleRadii([r.topLeft, r.topLeft, r.topRight, r.topRight, r.bottomRight, r.bottomRight, r.bottomLeft, r.bottomLeft], w, h)
    }

    // ---------------------------------------------------------------------
    // Projective 3×3 maps of Matrix4 (hit testing through transforms)
    // ---------------------------------------------------------------------

    /** The 2D projective part of [m] (z = 0 plane): row-major [a c tx; b d ty; p q w]. */
    static func projective(_ m: Matrix4) -> [Double] {
        [m[0], m[4], m[12], m[1], m[5], m[13], m[3], m[7], m[15]]
    }

    static func invert3(_ m: [Double]) -> [Double]? {
        let a = m[0], b = m[1], c = m[2], d = m[3], e = m[4], f = m[5], g = m[6], h = m[7], i = m[8]
        let A = e * i - f * h, B = -(d * i - f * g), C = d * h - e * g
        let det = a * A + b * B + c * C
        if abs(det) < 1e-12 { return nil }
        let inv = [
            A, -(b * i - c * h), b * f - c * e,
            B, a * i - c * g, -(a * f - c * d),
            C, -(a * h - b * g), a * e - b * d,
        ]
        return inv.map { $0 / det }
    }

    static func apply3(_ m: [Double], _ x: Double, _ y: Double) -> (Double, Double) {
        let tx = m[0] * x + m[1] * y + m[2]
        let ty = m[3] * x + m[4] * y + m[5]
        let tw = m[6] * x + m[7] * y + m[8]
        return tw != 0 && tw != 1 ? (tx / tw, ty / tw) : (tx, ty)
    }
}
#endif
