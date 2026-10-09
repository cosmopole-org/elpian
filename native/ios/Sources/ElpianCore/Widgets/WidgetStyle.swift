import Foundation

/**
 * Lowering helpers (widgets/style.ts) — the Swift twin of
 * `CSSProperties.applyStyle` and of Flutter's `Container` composition. They
 * wrap a widget descriptor in the same sequence of layout/paint objects the
 * Flutter engine wraps its widgets in, so the box model, stacking and
 * clipping come out identical.
 */

/** A zero-size box (`SizedBox.shrink()`). */
public var SHRINK: W { w("constrained", ["width": 0.0, "height": 0.0]) }

public func sizedBox(_ width: Double?, _ height: Double?, _ child: W? = nil) -> W {
    w("constrained", ["width": width, "height": height], child: child)
}

public func padding(_ insets: EdgeInsets, _ child: W?, _ percent: Any? = nil) -> W {
    w("padding", ["padding": insets, "percent": percent], child: child)
}

public func align(_ alignment: Alignment, _ child: W?, widthFactor: Double? = nil, heightFactor: Double? = nil) -> W {
    w("align", ["alignment": alignment, "widthFactor": widthFactor, "heightFactor": heightFactor], child: child)
}

public func center(_ child: W?) -> W { align(Alignment(x: 0, y: 0), child) }

public func column(_ children: [W], _ opts: JSONObject = JSONObject()) -> W {
    let p: JSONObject = ["direction": "column", "mainAxisAlignment": "start", "crossAxisAlignment": "center", "mainAxisSize": "max"]
    p.assign(opts)
    return w("flex", p, children)
}

public func row(_ children: [W], _ opts: JSONObject = JSONObject()) -> W {
    let p: JSONObject = ["direction": "row", "mainAxisAlignment": "start", "crossAxisAlignment": "center", "mainAxisSize": "max"]
    p.assign(opts)
    return w("flex", p, children)
}

public func expanded(_ child: W, _ flex: Double = 1) -> W { w("flexible", ["flex": flex, "fit": "tight"], child: child) }

public func flexible(_ child: W, _ flex: Double = 1, _ fit: String = "loose") -> W { w("flexible", ["flex": flex, "fit": fit], child: child) }

public func text(_ value: String, _ style: TextStyle? = nil, _ opts: JSONObject = JSONObject()) -> W {
    let p: JSONObject = ["text": value, "style": style]
    p.assign(opts)
    return w("text", p)
}

public func decorated(_ decoration: BoxDecoration, _ child: W?) -> W { w("decorated", ["decoration": decoration], child: child) }

private func sh(_ dx: Double, _ dy: Double, _ blur: Double, _ spread: Double, _ color: Color) -> BoxShadow {
    BoxShadow(color: color, dx: dx, dy: dy, blur: blur, spread: spread)
}

/** `kElevationToShadow` from Flutter's material shadows. */
private let ELEVATION_SHADOWS: [(Double, [BoxShadow])] = [
    (0, []),
    (1, [sh(0, 2, 1, -1, 0x33000000), sh(0, 1, 1, 0, 0x24000000), sh(0, 1, 3, 0, 0x1f000000)]),
    (2, [sh(0, 3, 1, -2, 0x33000000), sh(0, 2, 2, 0, 0x24000000), sh(0, 1, 5, 0, 0x1f000000)]),
    (3, [sh(0, 3, 3, -2, 0x33000000), sh(0, 3, 4, 0, 0x24000000), sh(0, 1, 8, 0, 0x1f000000)]),
    (4, [sh(0, 2, 4, -1, 0x33000000), sh(0, 4, 5, 0, 0x24000000), sh(0, 1, 10, 0, 0x1f000000)]),
    (6, [sh(0, 3, 5, -1, 0x33000000), sh(0, 6, 10, 0, 0x24000000), sh(0, 1, 18, 0, 0x1f000000)]),
    (8, [sh(0, 5, 5, -3, 0x33000000), sh(0, 8, 10, 1, 0x24000000), sh(0, 3, 14, 2, 0x1f000000)]),
    (12, [sh(0, 7, 8, -4, 0x33000000), sh(0, 12, 17, 2, 0x24000000), sh(0, 5, 22, 4, 0x1f000000)]),
    (16, [sh(0, 8, 10, -5, 0x33000000), sh(0, 16, 24, 2, 0x24000000), sh(0, 6, 30, 5, 0x1f000000)]),
    (24, [sh(0, 11, 15, -7, 0x33000000), sh(0, 24, 38, 3, 0x24000000), sh(0, 9, 46, 8, 0x1f000000)]),
]

public func elevationShadows(_ elevation: Double) -> [BoxShadow] {
    if elevation <= 0 { return [] }
    var best = ELEVATION_SHADOWS[0]
    for entry in ELEVATION_SHADOWS where abs(entry.0 - elevation) < abs(best.0 - elevation) { best = entry }
    return best.1
}

/** A border style name as the enum (unknown names paint solid). */
func borderStyleOf(_ name: String?) -> BorderStyleName {
    guard let name = name, let s = BorderStyleName(rawValue: name) else { return .solid }
    return s
}

/** The `BoxDecoration` a Flutter `Container` would build from this style. */
public func decorationFromStyle(_ style: CSSStyle, _ ctx: BuildContext? = nil) -> BoxDecoration {
    var gradients: [Gradient] = []
    if let layers = style.gradientLayers { gradients.append(contentsOf: layers.reversed()) }
    if let g = style.gradient { gradients.append(g) }
    var border = style.border
    let borderStyle = style.borderStyle
    let hasStyle = borderStyle != nil && borderStyle != "" && borderStyle != "none"
    if border == nil, let bw = style.borderWidth, style.borderColor != nil || hasStyle {
        border = Border.all(BorderSide(
            width: bw,
            color: style.borderColor ?? style.color ?? 0xff000000,
            style: borderStyle != nil && borderStyle != "" && borderStyle != "solid" ? borderStyleOf(borderStyle) : .solid
        ))
    }
    var image: DecorationImage?
    if let bgImage = style.backgroundImage, !bgImage.isEmpty {
        image = DecorationImage(
            src: ctx?.engine.resolveUrl(bgImage) ?? bgImage,
            fit: style.backgroundSize,
            alignment: style.backgroundPosition,
            repeat: style.backgroundRepeat,
            size: style.backgroundSizePx
        )
    }
    var outline: Outline?
    if let ow = style.outlineWidth, ow > 0, style.outlineStyle != "none" {
        outline = Outline(width: ow, color: style.outlineColor ?? style.color ?? 0xff000000, style: style.outlineStyle ?? "solid", offset: style.outlineOffset ?? 0)
    }
    return BoxDecoration(
        color: style.backgroundColor,
        gradients: gradients.isEmpty ? nil : gradients,
        image: image,
        border: border,
        radius: style.borderRadius,
        radiusPercent: style.borderRadiusPercent,
        shape: style.shape,
        shadows: (style.boxShadow?.isEmpty ?? true) ? nil : style.boxShadow,
        outline: outline
    )
}

private func needsContainer(_ style: CSSStyle) -> Bool {
    style.padding != nil ||
        style.paddingPercent != nil ||
        style.backgroundColor != nil ||
        style.gradient != nil ||
        style.border != nil ||
        style.borderRadius != nil ||
        style.borderRadiusPercent != nil ||
        style.boxShadow != nil ||
        style.borderColor != nil ||
        style.backgroundImage != nil ||
        style.shape == "circle" ||
        (style.outlineWidth ?? 0) > 0
}

private func clips(_ o: String?) -> Bool { o == "hidden" || o == "clip" }

/** `_flexSingleChildAlignment`: centre a lone child inside a fixed-size flex box. */
private func flexSingleChildAlignment(_ style: CSSStyle) -> Alignment {
    let isColumn = style.flexDirection == "column" || style.flexDirection == "column-reverse"
    func factor(_ v: String?) -> Double {
        switch (v ?? "").lowercased() {
        case "center": return 0
        case "flex-end", "end": return 1
        default: return -1
        }
    }
    let main = factor(style.justifyContent)
    let cross = factor(style.alignItems)
    return isColumn ? Alignment(x: cross, y: main) : Alignment(x: main, y: cross)
}

/** The transform `applyStyle` builds (rotate / scale replace the matrix, as in Flutter). */
public func styleTransform(_ style: CSSStyle) -> Matrix4? {
    if style.transform == nil && style.rotate == nil && style.scale == nil && style.translate == nil && style.scaleX == nil && style.scaleY == nil {
        return nil
    }
    var m = style.transform ?? Matrix.identity()
    if let r = style.rotate { m = Matrix.rotationZ(r * Double.pi / 180) }
    if let s = style.scale { m = Matrix.scaling(s, s, 1) }
    if style.scaleX != nil || style.scaleY != nil { m = Matrix.multiply(m, Matrix.scaling(style.scaleX ?? 1, style.scaleY ?? 1, 1)) }
    if let t = style.translate { m = Matrix.multiply(Matrix.translation(t.dx, t.dy), m) }
    return m
}

public struct ApplyStyleOptions {
    public var applyFlex: Bool
    public var layoutHandled: Bool

    public init(applyFlex: Bool = true, layoutHandled: Bool = false) {
        self.applyFlex = applyFlex
        self.layoutHandled = layoutHandled
    }
}

/** JavaScript truthiness of a number (`0` and NaN are falsy). */
private func nz(_ v: Double) -> Bool { v != 0 && !v.isNaN }

/**
 * `CSSProperties.applyStyle` — wraps [child] with the style's effects, from
 * the innermost wrapper to the outermost, in Flutter's exact order:
 *
 *   flex-single-child Align → Opacity → Transform → Visibility → Align →
 *   scroll / clip → AspectRatio → ConstrainedBox+SizedBox → Container
 *   (padding + decoration) → margin → FractionallySizedBox → transitions →
 *   IgnorePointer → Flexible
 *
 * plus the properties Flutter parses but never applies (filters, outlines,
 * `visibility: hidden`, keyframe animations, `margin: auto`).
 */
public func applyStyle(_ child: W, _ style: CSSStyle?, _ opts: ApplyStyleOptions = ApplyStyleOptions(), _ ctx: BuildContext? = nil) -> W {
    guard let style = style else { return child }
    let applyFlex = opts.applyFlex
    let dur = style.transitionDuration ?? 0
    let animated = style.transitionDuration != nil && dur > 0
    let curve = style.transitionCurve
    var result = child

    if !opts.layoutHandled && (style.display == "flex" || style.display == "inline-flex") && style.width != nil && style.height != nil {
        let a = flexSingleChildAlignment(style)
        if a.x != -1 || a.y != -1 { result = align(a, result) }
    }

    // Opacity (animated when the style transitions).
    if let opacity = style.opacity, opacity < 1 || animated {
        result = animated
            ? w("animatedOpacity", ["opacity": opacity, "duration": dur, "curve": curve], child: result)
            : w("opacity", ["opacity": opacity], child: result)
    }

    // Transform.
    if let matrix = styleTransform(style) {
        let origin = style.transformOrigin ?? Alignment(x: 0, y: 0)
        result = animated
            ? w("animatedTransform", ["transform": matrix, "alignment": origin, "duration": dur, "curve": curve], child: result)
            : w("transform", ["transform": matrix, "alignment": origin], child: result)
    }

    // Filters (blur, brightness, drop-shadow …) and blend modes.
    if style.filter != nil || style.backdropFilter != nil || !(style.mixBlendMode ?? "").isEmpty {
        result = w("filter", ["filter": style.filter, "backdrop": style.backdropFilter, "blendMode": style.mixBlendMode], child: result)
    }

    // Visibility.
    if style.visible == false {
        result = w("visibility", ["mode": "gone"], child: result)
    } else if style.visibility == "hidden" || style.visibility == "collapse" {
        result = w("visibility", ["mode": "hidden"], child: result)
    }

    // Alignment.
    if let a = style.alignment {
        result = animated ? w("animatedAlign", ["alignment": a, "duration": dur, "curve": curve], child: result) : align(a, result)
    }

    // Overflow: scroll when the axis is bounded by this node, else clip.
    let overflowX = style.overflowX ?? style.overflow
    let overflowY = style.overflowY ?? style.overflow
    let boundedW = style.width != nil || style.maxWidth != nil || style.widthFactor != nil
    let boundedH = style.height != nil || style.maxHeight != nil || style.heightFactor != nil
    let scrollY = overflowY == "scroll" && boundedH
    let scrollX = overflowX == "scroll" && boundedW
    if scrollY || scrollX {
        result = w("scroll", ["axis": scrollY && scrollX ? "both" : scrollY ? "vertical" : "horizontal"], child: result)
    } else if clips(overflowX) || clips(overflowY) || overflowX == "scroll" || overflowY == "scroll" {
        result = w("clip", ["radius": style.borderRadius, "oval": style.shape == "circle"], child: result)
    }

    // Aspect ratio.
    if style.aspectRatio != nil && !(style.width != nil && style.height != nil) {
        result = w("aspectRatio", ["aspectRatio": style.aspectRatio], child: result)
    }

    // Size constraints (percentage axes are handled by the fractional wrapper below).
    let wf = style.widthFactor
    let hf = style.heightFactor
    let fixedWidth = wf == nil ? style.width : nil
    let fixedHeight = hf == nil ? style.height : nil
    if fixedWidth != nil || fixedHeight != nil || style.minWidth != nil || style.maxWidth != nil || style.minHeight != nil || style.maxHeight != nil {
        var inner = result
        if fixedWidth != nil || fixedHeight != nil {
            inner = animated
                ? w("animatedConstrained", ["width": fixedWidth, "height": fixedHeight, "duration": dur, "curve": curve], child: result)
                : w("constrained", ["width": fixedWidth, "height": fixedHeight], child: result)
        }
        result = w(
            "constrained",
            ["minWidth": style.minWidth ?? 0, "maxWidth": style.maxWidth, "minHeight": style.minHeight ?? 0, "maxHeight": style.maxHeight],
            child: inner
        )
    }

    // Container: padding (+ border insets) and decoration.
    if needsContainer(style) {
        let decoration = decorationFromStyle(style, ctx)
        let insets = borderInsets(decoration.border)
        let pad = style.padding ?? .zero
        let effective = EdgeInsets(top: pad.top + insets.top, right: pad.right + insets.right, bottom: pad.bottom + insets.bottom, left: pad.left + insets.left)
        if nz(effective.top) || nz(effective.right) || nz(effective.bottom) || nz(effective.left) || style.paddingPercent != nil {
            result = animated
                ? w("animatedPadding", ["padding": effective, "percent": style.paddingPercent, "duration": dur, "curve": curve], child: result)
                : padding(effective, result, style.paddingPercent)
        }
        let hasPaint = decoration.color != nil ||
            decoration.gradients != nil ||
            decoration.image != nil ||
            decoration.border != nil ||
            decoration.shadows != nil ||
            decoration.outline != nil ||
            decoration.radius != nil ||
            decoration.radiusPercent != nil ||
            decoration.shape == "circle"
        if hasPaint {
            result = animated
                ? w("animatedDecorated", ["decoration": decoration, "duration": dur, "curve": curve], child: result)
                : decorated(decoration, result)
        }
    }

    // Keyframe animation (`animation-name` resolved against the stylesheet).
    if let animationName = style.animationName, !animationName.isEmpty, let ctx = ctx {
        if let frames = style.keyframes ?? ctx.engine.services.stylesheets.keyframes(animationName), !frames.isEmpty {
            result = w(
                "keyframes",
                [
                    "frames": frames,
                    "duration": style.animationDuration ?? 1000,
                    "delay": style.animationDelay ?? 0,
                    "iterations": style.animationIterationCount ?? 1,
                    "direction": style.animationDirection ?? "normal",
                    "fillMode": style.animationFillMode ?? "none",
                    "timing": style.animationTimingFunction ?? "ease",
                    "playState": style.animationPlayState ?? "running",
                ],
                child: result
            )
        }
    }

    // Margin (with `auto` margins centring the box).
    if style.margin != nil || style.marginPercent != nil {
        let m = style.margin ?? .zero
        if nz(m.top) || nz(m.right) || nz(m.bottom) || nz(m.left) || style.marginPercent != nil { result = padding(m, result, style.marginPercent) }
    }
    if let auto = style.marginAuto, auto.left || auto.right {
        let ax: Double = auto.left && auto.right ? 0 : auto.left ? 1 : -1
        // Expands horizontally within a bounded parent and places the box there.
        result = w("align", ["alignment": Alignment(x: ax, y: -1), "heightFactor": 1.0], child: result)
    }

    // Percentage width/height relative to the parent.
    if wf != nil || hf != nil {
        result = w(
            "fractional",
            [
                "widthFactor": wf,
                "heightFactor": hf,
                "alignment": Alignment(x: -1, y: 0),
                "fallbackWidth": wf != nil ? style.width : nil,
                "fallbackHeight": hf != nil ? style.height : nil,
            ],
            child: result
        )
    }

    // pointer-events: none.
    if style.pointerEvents == "none" { result = w("ignorePointer", ["ignoring": true], child: result) }

    // Flex (outermost, so it is a direct child of the flex box).
    if applyFlex { result = wrapFlex(result, style) }
    return result
}

/** Wrap [child] in Flexible when the style declares a flex factor (CSS `flex:n` → tight). */
public func wrapFlex(_ child: W, _ style: CSSStyle?) -> W {
    guard let style = style else { return child }
    let grow = style.flex ?? style.flexGrow
    let basis = parseBasis(style.flexBasis)
    if let g = grow, g > 0 {
        return w("flexible", ["flex": g, "fit": "tight", "shrink": style.flexShrink ?? 1, "alignSelf": alignSelfOf(style), "basis": basis], child: child)
    }
    if style.flexShrink != nil || style.alignSelf != nil || basis != nil {
        return w("flexible", ["flex": 0.0, "fit": "loose", "shrink": style.flexShrink ?? 1, "alignSelf": alignSelfOf(style), "basis": basis], child: child)
    }
    return child
}

/** JavaScript `parseFloat`, or nil for NaN. */
func parseFloatPrefix(_ s: String) -> Double? {
    let n = jsParseFloat(s)
    return n.isNaN ? nil : n
}

private func parseBasis(_ basis: String?) -> Double? {
    guard let basis = basis, !basis.isEmpty, basis != "auto", basis != "content" else { return nil }
    guard let n = parseFloatPrefix(basis), n.isFinite, !jsTrim(basis).hasSuffix("%") else { return nil }
    return n
}

private func alignSelfOf(_ style: CSSStyle) -> String? {
    switch (style.alignSelf ?? "").lowercased() {
    case "center": return "center"
    case "flex-end", "end": return "end"
    case "flex-start", "start": return "start"
    case "stretch": return "stretch"
    case "baseline": return "baseline"
    default: return nil
    }
}

/** `CSSProperties.createTextStyle`. */
public func createTextStyle(_ style: CSSStyle?) -> TextStyle? { textStyleFromCss(style) }

/** Text widget props from a style (`textAlign`, `textOverflow`, `white-space`, line clamp). */
public func textOptionsFromStyle(_ style: CSSStyle?) -> JSONObject {
    let out = JSONObject()
    guard let style = style else { return out }
    if let a = style.textAlign, !a.isEmpty { out["align"] = a }
    if let o = style.textOverflow { out["overflow"] = o.rawValue }
    if style.whiteSpace == "nowrap" || style.whiteSpace == "pre" {
        out["softWrap"] = false
        if style.whiteSpace == "nowrap" { out["maxLines"] = 1.0 }
    }
    if let clamp = style.lineClamp, clamp > 0 {
        out["maxLines"] = clamp
        if out["overflow"] == nil { out["overflow"] = "ellipsis" }
    }
    return out
}

/** Flutter `Container(width, height, padding, margin, alignment, decoration, child)`. */
public func container(
    child: W? = nil,
    width: Double? = nil,
    height: Double? = nil,
    padding: EdgeInsets? = nil,
    margin: EdgeInsets? = nil,
    alignment: Alignment? = nil,
    decoration: BoxDecoration? = nil,
    minWidth: Double? = nil,
    minHeight: Double? = nil
) -> W {
    var current: W? = child
    let tightW = width != nil
    let tightH = height != nil
    if current == nil && !(tightW && tightH) {
        // Container with no child expands (LimitedBox(0,0) around an expanded box).
        current = w(
            "limited",
            ["maxWidth": 0.0, "maxHeight": 0.0],
            child: w("constrained", ["minWidth": Double.infinity, "minHeight": Double.infinity])
        )
    }
    if let a = alignment { current = align(a, current) }
    let borderPad = borderInsets(decoration?.border)
    let p = padding ?? .zero
    let eff = EdgeInsets(top: p.top + borderPad.top, right: p.right + borderPad.right, bottom: p.bottom + borderPad.bottom, left: p.left + borderPad.left)
    if nz(eff.top) || nz(eff.right) || nz(eff.bottom) || nz(eff.left) { current = ElpianCore.padding(eff, current) }
    if let d = decoration { current = decorated(d, current) }
    if width != nil || height != nil || minWidth != nil || minHeight != nil {
        current = w("constrained", ["width": width, "height": height, "minWidth": minWidth ?? 0, "minHeight": minHeight ?? 0], child: current)
    }
    if let m = margin { current = ElpianCore.padding(m, current) }
    // Without a child either the expanding box or the tight constrained box exists.
    return current!
}

public extension TextStyle {
    /** A modified copy (the TypeScript `{...style, color}`). */
    func with(_ change: (inout TextStyle) -> Void) -> TextStyle {
        var copy = self
        change(&copy)
        return copy
    }
}

public extension CSSStyle {
    /** A [CSSStyle] literal: a fresh style configured by [configure]. */
    static func make(_ configure: (CSSStyle) -> Void) -> CSSStyle {
        let s = CSSStyle()
        configure(s)
        return s
    }

    /** `{...this, ...other}` keeping only the non-null fields of [other] (the spread of a sparse TypeScript style object). */
    func overlaid(with other: CSSStyle?) -> CSSStyle {
        let c = copy()
        guard let o = other else { return c }
        if let v = o.width { c.width = v }
        if let v = o.height { c.height = v }
        if let v = o.widthFactor { c.widthFactor = v }
        if let v = o.heightFactor { c.heightFactor = v }
        if let v = o.minWidth { c.minWidth = v }
        if let v = o.maxWidth { c.maxWidth = v }
        if let v = o.minHeight { c.minHeight = v }
        if let v = o.maxHeight { c.maxHeight = v }
        if let v = o.aspectRatio { c.aspectRatio = v }
        if let v = o.padding { c.padding = v }
        if let v = o.margin { c.margin = v }
        if let v = o.marginAuto { c.marginAuto = v }
        if let v = o.paddingPercent { c.paddingPercent = v }
        if let v = o.marginPercent { c.marginPercent = v }
        if let v = o.alignment { c.alignment = v }
        if let v = o.position { c.position = v }
        if let v = o.top { c.top = v }
        if let v = o.right { c.right = v }
        if let v = o.bottom { c.bottom = v }
        if let v = o.left { c.left = v }
        if let v = o.zIndex { c.zIndex = v }
        if let v = o.display { c.display = v }
        if let v = o.flexDirection { c.flexDirection = v }
        if let v = o.justifyContent { c.justifyContent = v }
        if let v = o.alignItems { c.alignItems = v }
        if let v = o.alignContent { c.alignContent = v }
        if let v = o.alignSelf { c.alignSelf = v }
        if let v = o.flex { c.flex = v }
        if let v = o.flexGrow { c.flexGrow = v }
        if let v = o.flexShrink { c.flexShrink = v }
        if let v = o.flexBasis { c.flexBasis = v }
        if let v = o.flexWrap { c.flexWrap = v }
        if let v = o.order { c.order = v }
        if let v = o.gap { c.gap = v }
        if let v = o.rowGap { c.rowGap = v }
        if let v = o.columnGap { c.columnGap = v }
        if let v = o.overflow { c.overflow = v }
        if let v = o.overflowX { c.overflowX = v }
        if let v = o.overflowY { c.overflowY = v }
        if let v = o.boxSizing { c.boxSizing = v }
        if let v = o.gridTemplateColumns { c.gridTemplateColumns = v }
        if let v = o.gridTemplateRows { c.gridTemplateRows = v }
        if let v = o.gridTemplateAreas { c.gridTemplateAreas = v }
        if let v = o.gridAutoColumns { c.gridAutoColumns = v }
        if let v = o.gridAutoRows { c.gridAutoRows = v }
        if let v = o.gridAutoFlow { c.gridAutoFlow = v }
        if let v = o.gridColumnGap { c.gridColumnGap = v }
        if let v = o.gridRowGap { c.gridRowGap = v }
        if let v = o.gridGap { c.gridGap = v }
        if let v = o.gridColumn { c.gridColumn = v }
        if let v = o.gridRow { c.gridRow = v }
        if let v = o.gridArea { c.gridArea = v }
        if let v = o.justifyItems { c.justifyItems = v }
        if let v = o.justifySelf { c.justifySelf = v }
        if let v = o.backgroundColor { c.backgroundColor = v }
        if let v = o.backgroundImage { c.backgroundImage = v }
        if let v = o.backgroundSize { c.backgroundSize = v }
        if let v = o.backgroundSizePx { c.backgroundSizePx = v }
        if let v = o.backgroundPosition { c.backgroundPosition = v }
        if let v = o.backgroundRepeat { c.backgroundRepeat = v }
        if let v = o.gradient { c.gradient = v }
        if let v = o.gradientLayers { c.gradientLayers = v }
        if let v = o.border { c.border = v }
        if let v = o.borderRadius { c.borderRadius = v }
        if let v = o.borderRadiusPercent { c.borderRadiusPercent = v }
        if let v = o.borderColor { c.borderColor = v }
        if let v = o.borderWidth { c.borderWidth = v }
        if let v = o.borderStyle { c.borderStyle = v }
        if let v = o.outlineColor { c.outlineColor = v }
        if let v = o.outlineWidth { c.outlineWidth = v }
        if let v = o.outlineStyle { c.outlineStyle = v }
        if let v = o.outlineOffset { c.outlineOffset = v }
        if let v = o.color { c.color = v }
        if let v = o.fontSize { c.fontSize = v }
        if let v = o.fontWeight { c.fontWeight = v }
        if let v = o.fontStyle { c.fontStyle = v }
        if let v = o.fontFamily { c.fontFamily = v }
        if let v = o.letterSpacing { c.letterSpacing = v }
        if let v = o.wordSpacing { c.wordSpacing = v }
        if let v = o.lineHeight { c.lineHeight = v }
        if let v = o.lineHeightPx { c.lineHeightPx = v }
        if let v = o.textAlign { c.textAlign = v }
        if let v = o.textDecoration { c.textDecoration = v }
        if let v = o.textDecorationColor { c.textDecorationColor = v }
        if let v = o.textDecorationStyle { c.textDecorationStyle = v }
        if let v = o.textDecorationThickness { c.textDecorationThickness = v }
        if let v = o.textOverflow { c.textOverflow = v }
        if let v = o.textTransform { c.textTransform = v }
        if let v = o.whiteSpace { c.whiteSpace = v }
        if let v = o.borderCollapse { c.borderCollapse = v }
        if let v = o.borderSpacing { c.borderSpacing = v }
        if let v = o.verticalAlign { c.verticalAlign = v }
        if let v = o.writingMode { c.writingMode = v }
        if let v = o.wordBreak { c.wordBreak = v }
        if let v = o.lineClamp { c.lineClamp = v }
        if let v = o.boxShadow { c.boxShadow = v }
        if let v = o.textShadow { c.textShadow = v }
        if let v = o.transform { c.transform = v }
        if let v = o.rotate { c.rotate = v }
        if let v = o.scale { c.scale = v }
        if let v = o.scaleX { c.scaleX = v }
        if let v = o.scaleY { c.scaleY = v }
        if let v = o.translate { c.translate = v }
        if let v = o.transformOrigin { c.transformOrigin = v }
        if let v = o.opacity { c.opacity = v }
        if let v = o.visible { c.visible = v }
        if let v = o.visibility { c.visibility = v }
        if let v = o.filter { c.filter = v }
        if let v = o.backdropFilter { c.backdropFilter = v }
        if let v = o.mixBlendMode { c.mixBlendMode = v }
        if let v = o.cursor { c.cursor = v }
        if let v = o.pointerEvents { c.pointerEvents = v }
        if let v = o.userSelect { c.userSelect = v }
        if let v = o.touchAction { c.touchAction = v }
        if let v = o.objectFit { c.objectFit = v }
        if let v = o.objectPosition { c.objectPosition = v }
        if let v = o.clipBehavior { c.clipBehavior = v }
        if let v = o.shape { c.shape = v }
        if let v = o.transitionDuration { c.transitionDuration = v }
        if let v = o.transitionCurve { c.transitionCurve = v }
        if let v = o.transitionProperty { c.transitionProperty = v }
        if let v = o.transitionDelay { c.transitionDelay = v }
        if let v = o.animationName { c.animationName = v }
        if let v = o.animationDuration { c.animationDuration = v }
        if let v = o.animationTimingFunction { c.animationTimingFunction = v }
        if let v = o.animationDelay { c.animationDelay = v }
        if let v = o.animationIterationCount { c.animationIterationCount = v }
        if let v = o.animationDirection { c.animationDirection = v }
        if let v = o.animationFillMode { c.animationFillMode = v }
        if let v = o.animationPlayState { c.animationPlayState = v }
        if let v = o.animateOnBuild { c.animateOnBuild = v }
        if let v = o.staggerDelay { c.staggerDelay = v }
        if let v = o.staggerChildren { c.staggerChildren = v }
        if let v = o.animationFrom { c.animationFrom = v }
        if let v = o.animationTo { c.animationTo = v }
        if let v = o.slideBegin { c.slideBegin = v }
        if let v = o.slideEnd { c.slideEnd = v }
        if let v = o.scaleBegin { c.scaleBegin = v }
        if let v = o.scaleEnd { c.scaleEnd = v }
        if let v = o.rotationBegin { c.rotationBegin = v }
        if let v = o.rotationEnd { c.rotationEnd = v }
        if let v = o.fadeBegin { c.fadeBegin = v }
        if let v = o.fadeEnd { c.fadeEnd = v }
        if let v = o.colorBegin { c.colorBegin = v }
        if let v = o.colorEnd { c.colorEnd = v }
        if let v = o.paddingBegin { c.paddingBegin = v }
        if let v = o.paddingEnd { c.paddingEnd = v }
        if let v = o.alignmentBegin { c.alignmentBegin = v }
        if let v = o.alignmentEnd { c.alignmentEnd = v }
        if let v = o.shimmerBaseColor { c.shimmerBaseColor = v }
        if let v = o.shimmerHighlightColor { c.shimmerHighlightColor = v }
        if let v = o.animationAutoReverse { c.animationAutoReverse = v }
        if let v = o.animationRepeat { c.animationRepeat = v }
        if let v = o.keyframes { c.keyframes = v }
        if let v = o.gradientColors { c.gradientColors = v }
        if let v = o.gradientStops { c.gradientStops = v }
        return c
    }
}

/** `{...defaults, ...style}` keeping only the author's non-null fields. */
func withDefaults(_ style: CSSStyle?, _ defaults: CSSStyle) -> CSSStyle { defaults.overlaid(with: style) }
