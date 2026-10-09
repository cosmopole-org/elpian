#if canImport(UIKit)
import UIKit
import CoreText
#if !ELPIAN_SINGLE_MODULE
import ElpianCore
#endif

/**
 * Typefaces: the platform families (San Francisco, its serif design,
 * monospace), the bundled Material Icons font (`icons`, the Elpian target's
 * `Fonts/MaterialIcons-Regular.ttf`) and host-registered families.
 */
public final class ElpianFonts {
    public static let iconFile = "MaterialIcons-Regular"
    private static var registered: [String: String] = [:]
    private static var cache: [String: UIFont] = [:]
    private static var iconName: String?
    private static var iconsTried = false
    private static let lock = NSLock()

    /** Register a font family by name → a PostScript / family name UIKit knows (e.g. a font the host app ships). */
    public static func register(_ family: String, fontName: String) {
        lock.lock()
        registered[family.lowercased()] = fontName
        cache.removeAll()
        lock.unlock()
        TextEngine.clearCache()
    }

    /** Register a font file (ttf / otf) with Core Text; returns its PostScript name. */
    @discardableResult
    public static func registerFont(at url: URL, as family: String? = nil) -> String? {
        guard let provider = CGDataProvider(url: url as CFURL), let font = CGFont(provider) else { return nil }
        var error: Unmanaged<CFError>?
        _ = CTFontManagerRegisterGraphicsFont(font, &error)
        let name = font.postScriptName as String?
        if let n = name, let f = family { register(f, fontName: n) }
        return name
    }

    /** The bundles the icon font may live in: SwiftPM's resource bundle, the framework / pod bundle, the app. */
    static func resourceBundles() -> [Bundle] {
        var out: [Bundle] = []
        #if SWIFT_PACKAGE
        out.append(Bundle.module)
        #endif
        let own = Bundle(for: ElpianFonts.self)
        out.append(own)
        // CocoaPods resource bundles (`resource_bundles`) sit inside the framework bundle.
        for b in [own, Bundle.main] {
            if let urls = b.urls(forResourcesWithExtension: "bundle", subdirectory: nil) {
                for u in urls { if let nb = Bundle(url: u) { out.append(nb) } }
            }
        }
        out.append(Bundle.main)
        return out
    }

    /** The bundled Material Icons font file, wherever the package manager put it. */
    static func iconFontURL() -> URL? {
        for b in resourceBundles() {
            for sub in [nil, "Fonts", "Resources/Fonts", "fonts"] as [String?] {
                if let u = b.url(forResource: iconFile, withExtension: "ttf", subdirectory: sub) { return u }
            }
        }
        return nil
    }

    /** Register the bundled fonts (idempotent; also done lazily on first use of `icons`). */
    public static func registerBundledFonts() {
        lock.lock()
        let tried = iconsTried
        iconsTried = true
        lock.unlock()
        if tried { return }
        let name = iconFontURL().flatMap { registerFont(at: $0) }
        lock.lock()
        iconName = name ?? (UIFont(name: "MaterialIcons-Regular", size: 12) != nil ? "MaterialIcons-Regular" : nil)
        lock.unlock()
    }

    private static func weight(_ w: Int) -> UIFont.Weight {
        switch w {
        case ..<150: return .ultraLight
        case ..<250: return .thin
        case ..<350: return .light
        case ..<450: return .regular
        case ..<550: return .medium
        case ..<650: return .semibold
        case ..<750: return .bold
        case ..<850: return .heavy
        default: return .black
        }
    }

    private static func base(_ family: String?, _ size: CGFloat, _ w: Int) -> UIFont {
        switch family {
        case nil, "", "sans-serif":
            return UIFont.systemFont(ofSize: size, weight: weight(w))
        case "serif":
            let sys = UIFont.systemFont(ofSize: size, weight: weight(w))
            if let d = sys.fontDescriptor.withDesign(.serif) { return UIFont(descriptor: d, size: size) }
            return UIFont(name: "TimesNewRomanPSMT", size: size) ?? sys
        case "monospace":
            return UIFont.monospacedSystemFont(ofSize: size, weight: weight(w))
        case "icons":
            registerBundledFonts()
            lock.lock()
            let n = iconName
            lock.unlock()
            return n.flatMap { UIFont(name: $0, size: size) } ?? UIFont.systemFont(ofSize: size)
        default:
            let fam = family!
            lock.lock()
            let reg = registered[fam.lowercased()]
            lock.unlock()
            if let r = reg, let f = UIFont(name: r, size: size) { return withWeight(f, w) }
            if let f = UIFont(name: fam, size: size) { return f }
            let d = UIFontDescriptor(fontAttributes: [.family: fam, .traits: [UIFontDescriptor.TraitKey.weight: weight(w)]])
            let f = UIFont(descriptor: d, size: size)
            // An unknown family resolves to the system font.
            return f.familyName.lowercased() == fam.lowercased() ? f : UIFont.systemFont(ofSize: size, weight: weight(w))
        }
    }

    private static func withWeight(_ f: UIFont, _ w: Int) -> UIFont {
        if w < 600 { return f }
        if let d = f.fontDescriptor.withSymbolicTraits(f.fontDescriptor.symbolicTraits.union(.traitBold)) { return UIFont(descriptor: d, size: f.pointSize) }
        return f
    }

    public static func font(_ family: String?, _ weight: Int, _ italic: Bool, _ size: CGFloat) -> UIFont {
        let key = "\(family ?? "")|\(weight)|\(italic)|\(size)"
        lock.lock()
        if let f = cache[key] {
            lock.unlock()
            return f
        }
        lock.unlock()
        var f = base(family, size, min(1000, max(1, weight)))
        if italic, let d = f.fontDescriptor.withSymbolicTraits(f.fontDescriptor.symbolicTraits.union(.traitItalic)) {
            f = UIFont(descriptor: d, size: size)
        }
        lock.lock()
        if cache.count > 512 { cache.removeAll() }
        cache[key] = f
        lock.unlock()
        return f
    }
}

/**
 * Builds, measures and lays out paragraphs with TextKit (TextRenderer.kt,
 * text.ts on the web). Flutter line heights: each line is as tall as its
 * tallest run, where a run with `height` takes height × fontSize split between
 * ascent and descent in the font's proportions, and the first span acts as the
 * paragraph strut — applied through the layout manager's line-fragment hook.
 */
final class TextEngine {
    final class Run {
        let range: NSRange
        let style: TextStyleSpec
        let link: String?
        let font: UIFont
        private var metrics: (Double, Double)?

        init(range: NSRange, style: TextStyleSpec, link: String?) {
            self.range = range
            self.style = style
            self.link = link
            font = ElpianFonts.font(style.fontFamily, style.fontWeight, style.italic, CGFloat(style.fontSize))
        }

        /** (ascent, descent) in points this run asks of its line. */
        func lineMetrics() -> (Double, Double) {
            if let m = metrics { return m }
            let a = Double(font.ascender)
            let d = Double(-font.descender)
            var out = (a, d)
            if let h = style.height, h > 0, a + d > 0 {
                let total = h * style.fontSize
                out = (total * a / (a + d), total * d / (a + d))
            }
            metrics = out
            return out
        }
    }

    /** The line-fragment hook that gives TextKit Flutter's line boxes. */
    final class LineHeights: NSObject, NSLayoutManagerDelegate {
        let runs: [Run]
        let strut: Run?

        init(runs: [Run], strut: Run?) {
            self.runs = runs
            self.strut = strut
        }

        func layoutManager(_ layoutManager: NSLayoutManager, shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<CGRect>,
                           lineFragmentUsedRect: UnsafeMutablePointer<CGRect>, baselineOffset: UnsafeMutablePointer<CGFloat>,
                           in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
            let chars = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            var asc = 0.0
            var desc = 0.0
            func take(_ r: Run) {
                let (a, d) = r.lineMetrics()
                asc = max(asc, a)
                desc = max(desc, d)
            }
            if let s = strut { take(s) }
            let end = max(chars.location + chars.length, chars.location + 1)
            for r in runs where r.range.location + r.range.length > chars.location && r.range.location < end { take(r) }
            let a = (asc - 0.0001).rounded(.up)
            let total = jsRound(asc + desc)
            var rect = lineFragmentRect.pointee
            rect.size.height = CGFloat(max(total, a))
            lineFragmentRect.pointee = rect
            var used = lineFragmentUsedRect.pointee
            used.size.height = rect.size.height
            lineFragmentUsedRect.pointee = used
            baselineOffset.pointee = CGFloat(a)
            return true
        }
    }

    /** A built paragraph: attributed text, runs and the strut. */
    final class Built {
        let spec: TextSpec
        let text: NSAttributedString
        let runs: [Run]
        let strut: Run?
        let heights: LineHeights
        private var desired: CGFloat?

        init(spec: TextSpec, text: NSAttributedString, runs: [Run], strut: Run?) {
            self.spec = spec
            self.text = text
            self.runs = runs
            self.strut = strut
            heights = LineHeights(runs: runs, strut: strut)
        }

        /** The unwrapped width (the widest hard line). */
        var desiredWidth: CGFloat {
            if let d = desired { return d }
            if text.length == 0 { return 0 }
            let l = TextEngine.layout(self, width: .greatestFiniteMagnitude, maxLines: nil, ellipsize: false, truncateLines: false)
            let d = l.usedWidth
            desired = d
            return d
        }
    }

    /** A TextKit stack laid out at one width. */
    final class Laid {
        let storage: NSTextStorage
        let manager: NSLayoutManager
        let container: NSTextContainer
        let built: Built

        init(_ built: Built, _ storage: NSTextStorage, _ manager: NSLayoutManager, _ container: NSTextContainer) {
            self.built = built
            self.storage = storage
            self.manager = manager
            self.container = container
        }

        var glyphRange: NSRange { manager.glyphRange(for: container) }

        /** Line fragments in order: (rect, glyph range). */
        func lines() -> [(CGRect, NSRange)] {
            var out: [(CGRect, NSRange)] = []
            let range = glyphRange
            if range.length == 0 { return out }
            manager.enumerateLineFragments(forGlyphRange: range) { rect, _, _, glyphs, _ in out.append((rect, glyphs)) }
            return out
        }

        var usedWidth: CGFloat { manager.usedRect(for: container).width }

        func baseline(ofLine rect: CGRect, glyph: Int) -> CGFloat { rect.minY + manager.location(forGlyphAt: glyph).y }
    }

    private static let measureCache = NSCache<NSString, MeasureBox>()

    final class MeasureBox {
        let metrics: TextMetrics
        init(_ m: TextMetrics) { metrics = m }
    }

    /** Forget cached metrics (fonts or text scale changed). */
    static func clearCache() { measureCache.removeAllObjects() }

    private static func alignment(_ spec: TextSpec) -> NSTextAlignment {
        let rtl = spec.direction == "rtl"
        switch spec.align {
        case "center": return .center
        case "right": return .right
        case "left": return .left
        case "justify": return .justified
        case "end": return rtl ? .left : .right
        default: return rtl ? .right : .left
        }
    }

    static func build(_ spec: TextSpec) -> Built {
        let out = NSMutableAttributedString()
        var runs: [Run] = []
        let para = NSMutableParagraphStyle()
        para.alignment = alignment(spec)
        para.baseWritingDirection = spec.direction == "rtl" ? .rightToLeft : .leftToRight
        para.lineBreakMode = .byWordWrapping
        para.hyphenationFactor = 0
        for s in spec.spans {
            let start = out.length
            let st = s.style
            let run = Run(range: NSRange(location: start, length: (s.text as NSString).length), style: st, link: s.link)
            var attrs: [NSAttributedString.Key: Any] = [
                .font: run.font,
                .foregroundColor: Paints.uiColor(st.color),
                .kern: st.letterSpacing,
                .paragraphStyle: para,
            ]
            if st.baselineShift != 0 { attrs[.baselineOffset] = -st.baselineShift }
            if let bg = st.background { attrs[.backgroundColor] = Paints.uiColor(bg) }
            out.append(NSAttributedString(string: s.text, attributes: attrs))
            if st.wordSpacing != 0 {
                // Word spacing: extra advance after each space (CSS word-spacing).
                let ns = s.text as NSString
                for i in 0..<ns.length where ns.character(at: i) == 0x20 {
                    out.addAttribute(.kern, value: st.letterSpacing + st.wordSpacing, range: NSRange(location: start + i, length: 1))
                }
            }
            if run.range.length > 0 { runs.append(run) }
        }
        let strut = spec.spans.first.map { Run(range: NSRange(location: 0, length: 0), style: $0.style, link: nil) }
        return Built(spec: spec, text: out, runs: runs, strut: strut)
    }

    /**
     * Lay [b] out [width] points wide: at most [maxLines] lines, the last one
     * ellipsized when [ellipsize]; [truncateLines] ellipsizes every hard line
     * on its own (CSS text-overflow on pre text).
     */
    static func layout(_ b: Built, width: CGFloat, maxLines: Int?, ellipsize: Bool, truncateLines: Bool) -> Laid {
        let text: NSAttributedString
        if truncateLines {
            let m = NSMutableAttributedString(attributedString: b.text)
            m.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: m.length)) { v, range, _ in
                guard let p = (v as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle else { return }
                p.lineBreakMode = .byTruncatingTail
                m.addAttribute(.paragraphStyle, value: p, range: range)
            }
            text = m
        } else {
            text = b.text
        }
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        manager.usesFontLeading = false
        manager.delegate = b.heights
        let container = NSTextContainer(size: CGSize(width: max(1, width), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        if let n = maxLines, n > 0 { container.maximumNumberOfLines = n }
        container.lineBreakMode = ellipsize ? .byTruncatingTail : .byWordWrapping
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        return Laid(b, storage, manager, container)
    }

    /** Metrics for an empty paragraph: one strut line. */
    private static func emptyMetrics(_ b: Built) -> TextMetrics {
        let (a, d) = b.strut?.lineMetrics() ?? (0, 0)
        return TextMetrics(width: 0, height: ((a + d) * 100).rounded(.up) / 100, baseline: a, lineCount: 1, didExceedMaxLines: false)
    }

    /**
     * Flutter's TextPainter contract: width is the max intrinsic width clamped
     * to the constraint, height the laid-out height, baseline the first line's
     * alphabetic baseline.
     */
    static func measure(_ spec: TextSpec, _ maxWidth: Double) -> TextMetrics {
        let bounded = maxWidth.isFinite && maxWidth >= 0
        let key = "\(spec.hashValue)|\(bounded ? Int((maxWidth * 1000).rounded()) : -1)|\(JSON.stringify(spec))" as NSString
        if let hit = measureCache.object(forKey: key) { return hit.metrics }
        let b = build(spec)
        if b.text.length == 0 {
            let m = emptyMetrics(b)
            measureCache.setObject(MeasureBox(m), forKey: key)
            return m
        }
        let intrinsic = Double(b.desiredWidth)
        let maxLines = spec.maxLines.flatMap { $0 > 0 ? $0 : nil }
        var width = intrinsic
        let wraps = bounded && intrinsic > maxWidth + 0.01
        let layoutWidth = wraps && spec.softWrap ? CGFloat(maxWidth) : (b.desiredWidth.rounded(.up) + 1)
        if wraps { width = maxWidth }
        let lay = layout(b, width: layoutWidth, maxLines: maxLines, ellipsize: false, truncateLines: false)
        var exceeded = false
        if let n = maxLines {
            let unclamped = layout(b, width: layoutWidth, maxLines: nil, ellipsize: false, truncateLines: false)
            exceeded = unclamped.lines().count > n
        } else if !spec.softWrap && wraps {
            exceeded = spec.overflow != "visible"
        }
        let lines = lay.lines()
        let count = maxLines.map { min(lines.count, $0) } ?? lines.count
        let height = count > 0 ? Double(lines[count - 1].0.maxY) : 0
        let baseline = lines.first.map { Double(lay.baseline(ofLine: $0.0, glyph: $0.1.location)) } ?? 0
        let result = TextMetrics(
            width: (width * 100).rounded(.up) / 100,
            height: (height * 100).rounded(.up) / 100,
            baseline: jsRound(baseline * 1000) / 1000,
            lineCount: max(1, count),
            didExceedMaxLines: exceeded
        )
        measureCache.setObject(MeasureBox(result), forKey: key)
        return result
    }

    /** The layout a [TextLeafView] paints for a frame [frameWidth] points wide. */
    static func paintLayout(_ b: Built, _ frameWidth: CGFloat) -> Laid {
        let spec = b.spec
        let maxLines = spec.maxLines.flatMap { $0 > 0 ? $0 : nil }
        let desired = b.desiredWidth.rounded(.up)
        if spec.softWrap {
            // The measured width was rounded up; never wrap a line the measurement kept whole.
            var w = frameWidth
            if desired > w && desired - w <= 2 { w = desired }
            return layout(b, width: w, maxLines: maxLines, ellipsize: spec.overflow == "ellipsis" && maxLines != nil, truncateLines: false)
        }
        if spec.overflow == "ellipsis" && desired > frameWidth + 1 {
            return layout(b, width: frameWidth, maxLines: maxLines, ellipsize: false, truncateLines: true)
        }
        return layout(b, width: max(frameWidth, desired + 1), maxLines: maxLines, ellipsize: false, truncateLines: false)
    }
}

/**
 * Paints a [TextSpec] exactly as [TextEngine.measure] laid it out: spans,
 * multiple shadows, decorations with style / colour / thickness, fade
 * overflow, tappable links and (when selectable) long-press copy.
 */
final class TextLeafView: UIView {
    private weak var owner: ElpianView?
    private var spec: TextSpec?
    private var built: TextEngine.Built?
    private var laid: TextEngine.Laid?
    private var laidWidth: CGFloat = -1
    private var pressedLink: String?
    private var selected = false
    private var longPress: DispatchWorkItem?
    private var downPoint = CGPoint.zero

    init(owner: ElpianView) {
        self.owner = owner
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        isUserInteractionEnabled = false
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setSpec(_ s: TextSpec?) {
        spec = s
        built = s.map { TextEngine.build($0) }
        laid = nil
        accessibilityLabel = s?.spans.map { $0.text }.joined()
        isAccessibilityElement = s != nil
        accessibilityTraits = .staticText
        isUserInteractionEnabled = s.map { $0.selectable || $0.spans.contains { $0.link != nil } } ?? false
        setNeedsDisplay()
    }

    private func ensureLayout() -> TextEngine.Laid? {
        guard let b = built else { return nil }
        if laid == nil || laidWidth != bounds.width {
            laidWidth = bounds.width
            laid = TextEngine.paintLayout(b, bounds.width)
        }
        return laid
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if laidWidth != bounds.width {
            laid = nil
            setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let lay = ensureLayout(), let s = spec, let b = built else { return }
        let range = lay.glyphRange
        let fade = s.overflow == "fade" && !s.softWrap && lay.usedWidth > bounds.width
        if fade { ctx.beginTransparencyLayer(auxiliaryInfo: nil) }
        // Shadow passes, last shadow first (CSS paints the first one on top).
        let maxShadows = b.runs.map { $0.style.shadows?.count ?? 0 }.max() ?? 0
        if maxShadows > 0 {
            for p in stride(from: maxShadows - 1, through: 0, by: -1) { drawShadowPass(ctx, lay, p) }
        }
        if selected {
            ctx.setFillColor(Paints.cgColor(0x6633_B5E5))
            for (r, _) in lay.lines() { ctx.fill(lay.manager.usedRect(for: lay.container).intersection(r.insetBy(dx: -1000, dy: 0)).intersection(r)) }
        }
        lay.manager.drawBackground(forGlyphRange: range, at: .zero)
        lay.manager.drawGlyphs(forGlyphRange: range, at: .zero)
        drawDecorations(ctx, lay)
        if fade {
            let w = bounds.width
            ctx.saveGState()
            ctx.setBlendMode(.destinationIn)
            let colors = [UIColor.black.cgColor, UIColor.clear.cgColor] as CFArray
            if let g = CGGradient(colorsSpace: Paints.srgb, colors: colors, locations: [0, 1]) {
                ctx.clip(to: CGRect(x: w * 0.85, y: 0, width: w * 0.15, height: bounds.height))
                ctx.drawLinearGradient(g, start: CGPoint(x: w * 0.85, y: 0), end: CGPoint(x: w, y: 0), options: [])
            }
            ctx.restoreGState()
            ctx.endTransparencyLayer()
        }
    }

    /** Shadow pass [p]: each run's p-th shadow, as its glyphs blurred into a tinted mask. */
    private func drawShadowPass(_ ctx: CGContext, _ lay: TextEngine.Laid, _ p: Int) {
        guard let b = built else { return }
        let scale = owner?.scale ?? UIScreen.main.scale
        let w = Double(bounds.width), h = Double(bounds.height)
        for run in b.runs {
            guard let shadows = run.style.shadows, p < shadows.count else { continue }
            let s = shadows[p]
            if Paints.isTransparent(s.color) { continue }
            let glyphs = lay.manager.glyphRange(forCharacterRange: run.range, actualCharacterRange: nil)
            if glyphs.length == 0 { continue }
            let sigma = PaintMath.sigma(s.blur)
            let pad = (3 * sigma).rounded(.up) + 1
            let full = NSRange(location: 0, length: lay.storage.length)
            lay.manager.addTemporaryAttribute(.foregroundColor, value: UIColor.white, forCharacterRange: full)
            let mask = Raster.blurredMask(w, h, pad: pad, sigma: sigma, scale: Double(scale)) { c in
                UIGraphicsPushContext(c)
                lay.manager.drawGlyphs(forGlyphRange: glyphs, at: .zero)
                UIGraphicsPopContext()
            }
            lay.manager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
            if let m = mask {
                Raster.drawMask(ctx, m, CGRect(x: -pad + s.dx, y: -pad + s.dy, width: w + 2 * pad, height: h + 2 * pad), Paints.cgColor(s.color))
            }
        }
    }

    private func drawDecorations(_ ctx: CGContext, _ lay: TextEngine.Laid) {
        guard let b = built else { return }
        let lines = lay.lines()
        for run in b.runs {
            let st = run.style
            if st.decoration == 0 { continue }
            let font = run.font as CTFont
            let size = CGFloat(st.fontSize)
            let baseThick = CTFontGetUnderlineThickness(font) > 0 ? CTFontGetUnderlineThickness(font) : size * 0.0488
            let thick = max(1, baseThick * CGFloat(st.decorationThickness ?? 1))
            let underPos = -CTFontGetUnderlinePosition(font) > 0 ? -CTFontGetUnderlinePosition(font) : size * 0.0733
            let strikePos = -size * 0.258
            let ascent = run.font.ascender
            ctx.saveGState()
            ctx.setStrokeColor(Paints.cgColor(st.decorationColor ?? st.color))
            ctx.setLineWidth(thick)
            switch st.decorationStyle {
            case "dotted": ctx.setLineDash(phase: 0, lengths: [thick, thick])
            case "dashed": ctx.setLineDash(phase: 0, lengths: [thick * 4, thick * 2])
            default: break
            }
            let shift = CGFloat(st.baselineShift)
            let runGlyphs = lay.manager.glyphRange(forCharacterRange: run.range, actualCharacterRange: nil)
            for (rect, lineGlyphs) in lines {
                let inter = NSIntersectionRange(runGlyphs, lineGlyphs)
                if inter.length == 0 { continue }
                // Skip a truncated tail (the ellipsis is drawn in place of these glyphs).
                let bounds = lay.manager.boundingRect(forGlyphRange: inter, in: lay.container)
                if bounds.width <= 0 { continue }
                let x0 = bounds.minX
                let x1 = bounds.maxX
                let base = lay.baseline(ofLine: rect, glyph: inter.location) + shift
                if st.decoration & 1 != 0 { decoLine(ctx, x0, x1, base + underPos + thick / 2, thick, st.decorationStyle) }
                if st.decoration & 2 != 0 { decoLine(ctx, x0, x1, base - ascent + thick / 2, thick, st.decorationStyle) }
                if st.decoration & 4 != 0 { decoLine(ctx, x0, x1, base + strikePos, thick, st.decorationStyle) }
            }
            ctx.restoreGState()
        }
    }

    private func decoLine(_ ctx: CGContext, _ x0: CGFloat, _ x1: CGFloat, _ y: CGFloat, _ thick: CGFloat, _ style: String?) {
        switch style {
        case "double":
            ctx.move(to: CGPoint(x: x0, y: y - thick)); ctx.addLine(to: CGPoint(x: x1, y: y - thick))
            ctx.move(to: CGPoint(x: x0, y: y + thick)); ctx.addLine(to: CGPoint(x: x1, y: y + thick))
        case "wavy":
            let amp = thick * 1.5
            let wl = thick * 4
            var x = x0
            ctx.move(to: CGPoint(x: x, y: y))
            var up = true
            while x < x1 {
                let nx = min(x1, x + wl / 2)
                ctx.addQuadCurve(to: CGPoint(x: nx, y: y), control: CGPoint(x: (x + nx) / 2, y: up ? y - amp : y + amp))
                up.toggle()
                x = nx
            }
        default:
            ctx.move(to: CGPoint(x: x0, y: y)); ctx.addLine(to: CGPoint(x: x1, y: y))
        }
        ctx.strokePath()
    }

    // ---------------------------------------------------------------------
    // Links and selection
    // ---------------------------------------------------------------------

    private func linkAt(_ p: CGPoint) -> String? {
        guard let lay = ensureLayout(), let b = built else { return nil }
        let used = lay.manager.usedRect(for: lay.container)
        if p.y < 0 || p.y > used.maxY { return nil }
        var fraction: CGFloat = 0
        let glyph = lay.manager.glyphIndex(for: p, in: lay.container, fractionOfDistanceThroughGlyph: &fraction)
        let glyphRect = lay.manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: lay.container)
        if !glyphRect.insetBy(dx: -2, dy: -2).contains(p) {
            // Past the end of a line.
            let line = lay.manager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            if p.x < line.minX || p.x > line.maxX { return nil }
        }
        let off = lay.manager.characterIndexForGlyph(at: glyph)
        return b.runs.first { $0.link != nil && $0.range.location <= off && off < $0.range.location + $0.range.length }?.link
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let s = spec, let t = touches.first else { return }
        let p = t.location(in: self)
        pressedLink = linkAt(p)
        downPoint = p
        if s.selectable {
            let w = DispatchWorkItem { [weak self] in self?.showCopy() }
            longPress = w
            DispatchQueue.main.asyncAfter(deadline: .now() + GestureRecognizer.LONG_PRESS_TIMEOUT, execute: w)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        if let l = pressedLink, linkAt(p) != l { pressedLink = nil }
        if abs(p.x - downPoint.x) > 30 || abs(p.y - downPoint.y) > 30 { cancelCopyTimer() }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelCopyTimer()
        let link = pressedLink
        pressedLink = nil
        guard let l = link, let t = touches.first, linkAt(t.location(in: self)) == l, let o = owner else { return }
        o.host?.emit(ViewEvent(id: o.viewId, type: "link", value: l))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelCopyTimer()
        pressedLink = nil
    }

    private func cancelCopyTimer() {
        longPress?.cancel()
        longPress = nil
    }

    override var canBecomeFirstResponder: Bool { spec?.selectable == true }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        action == #selector(UIResponderStandardEditActions.copy(_:)) && spec?.selectable == true
    }

    override func copy(_ sender: Any?) {
        UIPasteboard.general.string = spec?.spans.map { $0.text }.joined()
        endSelection()
    }

    private func showCopy() {
        guard spec != nil, becomeFirstResponder() else { return }
        selected = true
        setNeedsDisplay()
        let menu = UIMenuController.shared
        menu.showMenu(from: self, rect: bounds)
        NotificationCenter.default.addObserver(self, selector: #selector(menuHidden), name: UIMenuController.didHideMenuNotification, object: nil)
    }

    @objc private func menuHidden() {
        NotificationCenter.default.removeObserver(self, name: UIMenuController.didHideMenuNotification, object: nil)
        endSelection()
    }

    private func endSelection() {
        selected = false
        setNeedsDisplay()
        if isFirstResponder { _ = resignFirstResponder() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            cancelCopyTimer()
            if selected { endSelection() }
        }
    }
}
#endif
