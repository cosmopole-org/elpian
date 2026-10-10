import Foundation

/**
 * The Flutter-DSL widgets (`Container`, `Text`, `Column`, `Card`, `Slider` …,
 * widgets/flutter.ts) — one builder per file in flutter/lib/src/widgets,
 * lowered to the same widget composition. Material visuals follow Flutter's
 * Material 3 defaults.
 *
 * Where the Flutter builder is a placeholder (Dismissible's no-op callback,
 * Draggable/DragTarget without events, Scaffold ignoring its AppBar,
 * GestureDetector/InkWell swallowing taps), the native builder implements the
 * behaviour the widget is named for and reports it to the guest as events.
 */

/** A JSON object literal (keeps the literal's key order). */
@inline(__always)
func jo(_ o: JSONObject) -> JSONObject { o }

private func first(_ children: [W]) -> W? { children.first }

private func num(_ v: Any?) -> Double? { toNumber(v) }

private let DISPATCH_TYPE_NAMES: [String: String] = [
    "tap": "tap", "focus": "focus", "blur": "blur", "keydown": "keyDown", "keyup": "keyUp", "dismissed": "custom", "drop": "drop",
]

/** Dispatch an Elpian event from a builder-level interaction. */
public func dispatchEvent(_ ctx: BuildContext, _ type: String, _ extra: JSONObject = JSONObject()) {
    let engine = ctx.engine
    let elementId = ctx.elementId
    let events = engine.services.events
    switch type {
    case "change": events.dispatchChange(elementId, extra["value"])
    case "input": events.dispatchInput(elementId, extra["value"])
    case "submit": events.dispatchSubmit(elementId, asMap(extra["data"]) ?? JSONObject())
    case "click": events.dispatchClick(elementId, extra["position"] as? Point)
    default:
        let typeName = DISPATCH_TYPE_NAMES[type] ?? "custom"
        events.dispatchEvent(makeEvent(type, typeName, elementId) { $0.applyExtra(extra) }, elementId)
    }
}

// ----------------------------------------------------------------------------
// Material helpers
// ----------------------------------------------------------------------------

/** Options of a Material button; [variant] is `elevated`, `filled`, `text` or `outlined`. */
public struct ButtonOptions {
    public var child: W
    public var style: CSSStyle?
    public var onPressed: (() -> Void)?
    public var variant: String
    public var semanticsLabel: String?

    public init(child: W, style: CSSStyle?, onPressed: (() -> Void)?, variant: String = "elevated", semanticsLabel: String? = nil) {
        self.child = child
        self.style = style
        self.onPressed = onPressed
        self.variant = variant
        self.semanticsLabel = semanticsLabel
    }
}

private func side(_ color: Color) -> BorderSide { BorderSide(width: 1, color: color, style: .solid) }

/** An `ElevatedButton` (Material 3): stadium shape, 40 px tall in a 48 px tap target. */
public func materialButton(_ opts: ButtonOptions) -> W {
    let s = opts.style ?? CSSStyle()
    let enabled = opts.onPressed != nil
    let variant = opts.variant
    let hasBg = s.backgroundColor != nil || s.gradient != nil
    var bg: Color? = s.backgroundColor
    if bg == nil {
        switch variant {
        case "elevated": bg = M3.surfaceContainerLow
        case "filled": bg = M3.primary
        default: bg = nil
        }
    }
    var fg: Color = s.color ?? (variant == "filled" || hasBg ? Colors.white : M3.primary)
    if !enabled {
        bg = bg != nil ? withOpacity(M3.onSurface, 0.12) : nil
        fg = withOpacity(M3.onSurface, 0.38)
    }
    let shadows = s.boxShadow
    let elevation: Double
    if let sh = shadows, !sh.isEmpty {
        elevation = sh[0].blur / 2
    } else {
        elevation = variant == "elevated" && enabled ? 1 : 0
    }
    let decoration = BoxDecoration(
        color: bg,
        gradients: s.gradient.map { [$0] },
        border: variant == "outlined" ? Border(top: side(M3.outline), right: side(M3.outline), bottom: side(M3.outline), left: side(M3.outline)) : s.border,
        radius: s.borderRadius,
        radiusPercent: s.borderRadius != nil ? nil : BorderRadius.all(50),
        shadows: (shadows?.isEmpty ?? true) ? elevationShadows(elevation) : shadows
    )
    let pad = s.padding ?? EdgeInsets.symmetric(vertical: 0, horizontal: 24)
    let labelStyle = TextStyle.LABEL_LARGE.with { $0.color = fg }
    var content = w("defaultTextStyle", ["style": labelStyle], child: align(Alignment(x: 0, y: 0), opts.child, widthFactor: 1, heightFactor: 1))
    content = padding(pad, content)
    content = w("constrained", ["minWidth": 64.0, "minHeight": 40.0], child: content)
    content = w("decorated", ["decoration": decoration], child: content)
    let onPressed = opts.onPressed
    content = w(
        "gesture",
        [
            "gestures": enabled ? ["tap"] : [String](),
            "ripple": enabled ? scaleAlpha(fg, 0.12) : nil,
            "cursor": enabled ? "pointer" : "default",
            "role": "button",
            "semanticsLabel": opts.semanticsLabel,
            "onEvent": { (e: ViewEvent) in if e.type == "tap" { onPressed?() } },
        ],
        child: content
    )
    // MaterialTapTargetSize.padded: 48 px tall interactive area.
    return padding(EdgeInsets(top: 4, right: 0, bottom: 4, left: 0), content)
}

/** Wrap a material button with the style parts Flutter applies outside it. */
public func buttonOuter(_ result: W, _ style: CSSStyle?) -> W {
    guard let style = style else { return result }
    var out = result
    if let m = style.margin { out = padding(m, out) }
    if let o = style.opacity, o < 1 { out = w("opacity", ["opacity": o], child: out) }
    if style.width != nil || style.height != nil { out = sizedBox(style.width, style.height, out) }
    if style.flex != nil || style.flexGrow != nil { out = w("flexible", ["flex": style.flex ?? style.flexGrow, "fit": "tight"], child: out) }
    return out
}

public func buttonPressed(_ ctx: BuildContext) -> () -> Void {
    return {
        // ElevatedButton.onPressed: click, then tap.
        dispatchEvent(ctx, "click")
        dispatchEvent(ctx, "tap")
    }
}

private func iconGlyph(_ name: String, _ size: Double, _ color: Color?) -> W {
    let glyph = UnicodeScalar(UInt32(truncatingIfNeeded: iconCodepoint(name))).map { String(Character($0)) } ?? ""
    return sizedBox(
        size,
        size,
        center(
            text(
                glyph,
                TextStyle(color: color ?? M3.onSurfaceVariant, fontSize: size, fontFamily: "icons", letterSpacing: 0, wordSpacing: 0, height: 1, decoration: 0),
                ["softWrap": false]
            )
        )
    )
}

/** A Material icon glyph of [size] px. */
public func icon(_ name: String, _ size: Double = 24, _ color: Color? = nil) -> W { iconGlyph(name, size, color) }

private func parseAlignmentProp(_ v: Any?, _ fallback: Alignment) -> Alignment { CSSParser.parseAlignment(v) ?? fallback }

private final class TextValueState {
    var value: String
    /** The `value` prop last seen (nil when absent) — a change of it wins over local edits. */
    var lastProp: String?
    init(_ value: String, _ lastProp: String? = nil) {
        self.value = value
        self.lastProp = lastProp
    }
}

private final class DismissState {
    var dismissed: Bool
    init(_ dismissed: Bool) { self.dismissed = dismissed }
}

// ----------------------------------------------------------------------------
// Builders
// ----------------------------------------------------------------------------

private func buildContainer(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    var child: W?
    if children.count == 1 {
        child = children[0]
    } else if children.count > 1 {
        child = column(children, ["crossAxisAlignment": "start", "mainAxisSize": "min"])
    }
    let p = node.props
    let decoration = asMap(p["decoration"]).map { decorationFromStyle(CSSParser.parse($0), ctx) }
    let result = container(
        child: child,
        width: num(p["width"]),
        height: num(p["height"]),
        padding: CSSParser.parseEdgeInsets(p["padding"]),
        margin: CSSParser.parseEdgeInsets(p["margin"]),
        alignment: CSSParser.parseAlignment(p["alignment"]),
        decoration: decoration
    )
    return applyStyle(result, node.style, ApplyStyleOptions(), ctx)
}

private func buildText(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let value = node.text
    let style = createTextStyle(node.style)
    let opts = textOptionsFromStyle(node.style)
    if let a = node.props["textAlign"] as? String { opts["align"] = a }
    if let m = num(node.props["maxLines"]) { opts["maxLines"] = m }
    if let o = node.props["overflow"] as? String { opts["overflow"] = o }
    if let sw = jsBool(node.props["softWrap"]) { opts["softWrap"] = sw }
    if node.props.b("selectable") { opts["selectable"] = true }
    return applyStyle(text(value, style, opts), node.style, ApplyStyleOptions(), ctx)
}

private func buildButton(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let label = jsString(node.props["text"] ?? "Button")
    let s = node.style
    let fg = s?.color ?? (s?.backgroundColor != nil ? Colors.white : M3.primary)
    let child = first(children) ?? text(label, TextStyle(color: fg))
    let enabled = !node.props.b("disabled") && !node.props.isFalse("enabled")
    return buttonOuter(materialButton(ButtonOptions(child: child, style: s, onPressed: enabled ? buttonPressed(ctx) : nil, semanticsLabel: label)), s)
}

private func buildImage(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let raw = jsString(node.props["src"] ?? "")
    let fit = node.props["fit"] as? String ?? "contain"
    let src = ctx.engine.resolveUrl(raw)
    let result = w(
        "image",
        [
            "src": src,
            "fit": fit,
            "width": node.style?.width ?? num(node.props["width"]),
            "height": node.style?.height ?? num(node.props["height"]),
            "alt": node.props["alt"],
            "onEvent": { (e: ViewEvent) in
                if e.type == "load" || e.type == "error" { dispatchEvent(ctx, e.type, jo(["value": e.value])) }
            },
        ]
    )
    return applyStyle(result, node.style, ApplyStyleOptions(), ctx)
}

private func buildStack(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let alignment = node.style?.alignment ?? Alignment(x: 0, y: 0)
    return applyStyle(w("stack", ["alignment": alignment, "fit": "loose"], children), node.style, ApplyStyleOptions(), ctx)
}

private func buildPositioned(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let s = node.style ?? CSSStyle()
    return w(
        "positioned",
        ["top": s.top, "right": s.right, "bottom": s.bottom, "left": s.left, "width": s.width, "height": s.height],
        child: first(children) ?? container()
    )
}

private func buildListView(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let scrollable = !node.props.isFalse("scrollable")
    let horizontal = node.props.s("scrollDirection") == "horizontal"
    let list = w("flex", ["direction": horizontal ? "row" : "column", "crossAxisAlignment": horizontal ? "start" : "stretch", "mainAxisSize": "min"], children)
    let result = w("scroll", ["axis": horizontal ? "horizontal" : "vertical", "enabled": scrollable], child: list)
    return applyStyle(result, node.style, ApplyStyleOptions(), ctx)
}

private func buildGridView(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let count = max(1, num(node.props["crossAxisCount"]) ?? 2)
    let spacing = num(node.props["crossAxisSpacing"]) ?? 0
    let mainSpacing = num(node.props["mainAxisSpacing"]) ?? 0
    let ratio = num(node.props["childAspectRatio"]) ?? 1
    let grid = w(
        "grid",
        ["columns": "repeat(\(jsString(count)), 1fr)", "columnGap": spacing, "rowGap": mainSpacing, "alignItems": "stretch"],
        children.map { w("aspectRatio", ["aspectRatio": ratio], child: $0) }
    )
    return applyStyle(w("scroll", ["axis": "vertical", "enabled": !node.props.isFalse("scrollable")], child: grid), node.style, ApplyStyleOptions(), ctx)
}

private func buildTextField(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let incoming: String? = node.props["value"] != nil ? jsString(node.props["value"]) : nil
    let state = ctx.engine.stateFor(ctx.elementId) { TextValueState(incoming ?? "", incoming) }
    // didUpdateWidget: a changed `value` prop (e.g. a bound model update) wins.
    if incoming != state.lastProp {
        if let incoming = incoming { state.value = incoming }
        state.lastProp = incoming
    }
    let s = node.style
    let textStyle = TextStyle.BODY_LARGE.merge(createTextStyle(s))
    let lines = max(1, num(node.props["maxLines"]) ?? 1)
    let p = node.props
    let result = w(
        "control",
        [
            "kind": "textInput",
            "lines": jsTruthy(p["multiline"]) ? max(lines, 3) : lines,
            "padding": [12.0, 0.0, 12.0, 0.0],
            "view": jo([
                "value": state.value,
                "placeholder": jsString(p["hint"] ?? p["placeholder"] ?? ""),
                "inputType": jsTruthy(p["obscureText"]) ? "password" as Any : (p["keyboardType"] ?? "text"),
                "multiline": lines > 1 || jsTruthy(p["multiline"]),
                "maxLines": lines,
                "maxLength": num(p["maxLength"]),
                "enabled": !p.isFalse("enabled"),
                "readOnly": p.b("readOnly"),
                "autofocus": p.b("autofocus"),
                "min": p["min"],
                "max": p["max"],
                "variant": "underline",
                "textStyle": textStyle.toSpec(),
                "hintStyle": textStyle.with { $0.color = M3.onSurfaceVariant }.toSpec(),
                "contentPadding": [12.0, 0.0, 12.0, 0.0],
                "colors": jo([
                    "text": textStyle.color ?? M3.onSurface,
                    "hint": M3.onSurfaceVariant,
                    "border": M3.onSurfaceVariant,
                    "focusedBorder": M3.primary,
                    "cursor": M3.primary,
                    "fill": nil,
                ]),
            ]),
            "onEvent": { (e: ViewEvent) in
                if e.type == "input" || e.type == "change" {
                    state.value = flattenOptional(e.value) == nil ? "" : jsString(e.value)
                    dispatchEvent(ctx, "input", jo(["value": state.value]))
                } else if e.type == "submit" {
                    dispatchEvent(ctx, "submit")
                } else if e.type == "focus" || e.type == "blur" {
                    dispatchEvent(ctx, e.type)
                }
            },
        ]
    )
    return applyStyle(result, s, ApplyStyleOptions(), ctx)
}

private func buildCheckbox(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let value = node.props.b("value")
    return w(
        "control",
        [
            "kind": "checkbox",
            "view": jo([
                "checked": value,
                "enabled": !node.props.isFalse("enabled"),
                "colors": jo(["fill": node.style?.color ?? M3.primary, "check": M3.onPrimary, "border": M3.onSurfaceVariant]),
            ]),
            "controlled": true,
            "onEvent": { (e: ViewEvent) in
                if e.type == "change" { dispatchEvent(ctx, "change", jo(["value": jsTruthy(e.value)])) }
            },
        ]
    )
}

private func buildRadio(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let value = node.props["value"]
    let group = node.props["groupValue"]
    return w(
        "control",
        [
            "kind": "radio",
            "view": jo([
                "checked": jsStrictEquals(value, group) && node.props.has("value"),
                "value": value,
                "colors": jo(["fill": node.style?.color ?? M3.primary, "border": M3.onSurfaceVariant]),
            ]),
            "controlled": true,
            "onEvent": { (e: ViewEvent) in
                if e.type == "change" { dispatchEvent(ctx, "change", jo(["value": value])) }
            },
        ]
    )
}

private func buildSwitch(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let value = node.props.b("value")
    return w(
        "control",
        [
            "kind": "switch",
            "view": jo([
                "checked": value,
                "enabled": !node.props.isFalse("enabled"),
                "colors": jo([
                    "trackOn": node.style?.color ?? M3.primary,
                    "thumbOn": M3.onPrimary,
                    "trackOff": M3.surfaceContainerHighest,
                    "thumbOff": M3.outline,
                    "outline": M3.outline,
                ]),
            ]),
            "controlled": true,
            "onEvent": { (e: ViewEvent) in
                if e.type == "change" { dispatchEvent(ctx, "change", jo(["value": jsTruthy(e.value)])) }
            },
        ]
    )
}

private func buildSlider(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let minV = num(node.props["min"]) ?? 0
    let maxV = num(node.props["max"]) ?? 1
    let value = max(minV, min(maxV, num(node.props["value"]) ?? 0.5))
    let divisions = num(node.props["divisions"])
    var step: Double?
    if let d = divisions, d > 0 { step = (maxV - minV) / d }
    return w(
        "control",
        [
            "kind": "slider",
            "view": jo([
                "value": value,
                "min": minV,
                "max": maxV,
                "step": step,
                "enabled": !node.props.isFalse("enabled"),
                "colors": jo(["active": node.style?.color ?? M3.primary, "inactive": M3.secondaryContainer, "thumb": node.style?.color ?? M3.primary]),
            ]),
            "controlled": true,
            "onEvent": { (e: ViewEvent) in
                if e.type == "change" || e.type == "input" { dispatchEvent(ctx, "change", jo(["value": eventNumber(e.value)])) }
            },
        ]
    )
}

private func buildIcon(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let name = jsString(node.props["icon"] ?? "star")
    let size = node.style?.fontSize ?? num(node.props["size"]) ?? 24
    return applyStyle(icon(name, size, node.style?.color), node.style, ApplyStyleOptions(), ctx)
}

private func buildCard(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let s = node.style ?? CSSStyle()
    var child: W = children.isEmpty ? SHRINK : children.count == 1 ? children[0] : column(children)
    let shadows = s.boxShadow
    let elevation: Double
    if let sh = shadows, !sh.isEmpty {
        elevation = sh[0].blur / 2
    } else {
        elevation = num(node.props["elevation"]) ?? 1
    }
    if let p = s.padding { child = padding(p, child) }
    let border = s.borderColor.map { BorderSide(width: s.borderWidth ?? 1, color: $0, style: .solid) }
    let radius = s.borderRadius ?? BorderRadius.all(12)
    var result = w("clip", ["radius": radius], child: child)
    result = decorated(
        BoxDecoration(
            color: s.backgroundColor ?? M3.surfaceContainerLow,
            border: border.map { Border(top: $0, right: $0, bottom: $0, left: $0) },
            radius: radius,
            shadows: elevationShadows(elevation)
        ),
        result
    )
    result = padding(EdgeInsets.all(4), result)
    let external = CSSStyle()
    external.width = s.width
    external.height = s.height
    external.minWidth = s.minWidth
    external.maxWidth = s.maxWidth
    external.minHeight = s.minHeight
    external.maxHeight = s.maxHeight
    external.margin = s.margin
    external.opacity = s.opacity
    external.flex = s.flex
    external.transform = s.transform
    external.rotate = s.rotate
    external.scale = s.scale
    external.alignment = s.alignment
    external.visible = s.visible
    return applyStyle(result, external, ApplyStyleOptions(), ctx)
}

private func buildScaffold(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    var appBar: W?
    var fab: W?
    var bottom: W?
    var body: [W] = []
    for (i, child) in node.children.enumerated() {
        let slot = child.props["slot"] as? String
        if child.type == "AppBar" || slot == "appBar" {
            appBar = children[i]
        } else if slot == "floatingActionButton" || child.type == "FloatingActionButton" {
            fab = children[i]
        } else if slot == "bottomNavigationBar" || slot == "bottomBar" {
            bottom = children[i]
        } else {
            body.append(children[i])
        }
    }
    let bodyW = body.last ?? SHRINK
    var columnChildren: [W] = []
    if let a = appBar { columnChildren.append(a) }
    columnChildren.append(expanded(w("align", ["alignment": Alignment(x: -1, y: -1)], child: bodyW)))
    if let b = bottom { columnChildren.append(b) }
    var result = w("flex", ["direction": "column", "crossAxisAlignment": "stretch", "mainAxisSize": "max"], columnChildren)
    if let f = fab {
        result = w(
            "stack",
            ["alignment": Alignment(x: -1, y: -1), "fit": "expand"],
            [result, w("positioned", ["right": 16.0, "bottom": 16.0 + (bottom != nil ? 80.0 : 0.0)], child: f)]
        )
    }
    return decorated(BoxDecoration(color: node.style?.backgroundColor ?? M3.surface), w("defaultTextStyle", ["style": TextStyle()], child: result))
}

private func buildAppBar(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let title = jsString(node.props["title"] ?? "")
    let s = node.style ?? CSSStyle()
    let fg = s.color ?? M3.onSurface
    var row1: [W] = []
    let leading = node.children.firstIndex { ($0.props["slot"] as? String) == "leading" } ?? -1
    if leading >= 0 { row1.append(padding(EdgeInsets(top: 0, right: 0, bottom: 0, left: 4), sizedBox(48, 48, center(children[leading])))) }
    row1.append(
        expanded(
            padding(
                EdgeInsets(top: 0, right: 16, bottom: 0, left: 16),
                text(title, TextStyle.TITLE_LARGE.with { $0.color = fg }, ["maxLines": 1.0, "overflow": "ellipsis", "softWrap": false])
            )
        )
    )
    for (i, c) in node.children.enumerated() where i != leading && (c.props["slot"] as? String) != "title" { row1.append(children[i]) }
    var bar = sizedBox(nil, s.height ?? 64, w("flex", ["direction": "row", "crossAxisAlignment": "center", "mainAxisSize": "max"], row1))
    // A primary AppBar extends under the status bar (MediaQuery padding top).
    if !node.props.isFalse("primary") { bar = w("safeArea", ["top": true], child: bar) }
    let elevation = num(node.props["elevation"])
    var shadows: [BoxShadow]?
    if let e = elevation, e != 0 { shadows = elevationShadows(e) }
    return decorated(
        BoxDecoration(color: s.backgroundColor ?? M3.surface, shadows: shadows),
        w("defaultTextStyle", ["style": TextStyle(color: fg)], child: bar)
    )
}

private func buildWrap(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let s = node.style
    let result = w("wrap", ["direction": "horizontal", "spacing": s?.gap ?? 8, "runSpacing": s?.rowGap ?? 8, "alignment": "start"], children)
    return applyStyle(result, s, ApplyStyleOptions(), ctx)
}

private func buildInkWell(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let child = first(children) ?? container()
    let result = w(
        "gesture",
        ["gestures": ["tap"], "ripple": scaleAlpha(node.style?.color ?? M3.onSurface, 0.12), "cursor": "pointer", "onEvent": { (_: ViewEvent) in }],
        child: child
    )
    return applyStyle(result, node.style, ApplyStyleOptions(), ctx)
}

private func buildTransform(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    var m = node.style?.transform ?? Matrix.identity()
    if let r = node.style?.rotate { m = Matrix.rotationZ(r * Double.pi / 180) }
    if let s = node.style?.scale { m = Matrix.scaling(s, s, 1) }
    return w("transform", ["transform": m, "alignment": Alignment(x: 0, y: 0)], child: first(children) ?? container())
}

private func buildConstrainedBox(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let s = node.style ?? CSSStyle()
    return w(
        "constrained",
        ["minWidth": s.minWidth ?? 0, "maxWidth": s.maxWidth, "minHeight": s.minHeight ?? 0, "maxHeight": s.maxHeight],
        child: first(children) ?? container()
    )
}

private func buildOverflowBox(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let s = node.style ?? CSSStyle()
    return w(
        "overflowBox",
        [
            "alignment": s.alignment ?? Alignment(x: 0, y: 0),
            "minWidth": s.minWidth,
            "maxWidth": s.maxWidth,
            "minHeight": s.minHeight,
            "maxHeight": s.maxHeight,
        ],
        child: first(children) ?? container()
    )
}

private func buildDivider(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let s = node.style ?? CSSStyle()
    let thickness = s.borderWidth ?? 1
    let height = s.height ?? 16
    let indent = num(node.props["indent"]) ?? 0
    let endIndent = num(node.props["endIndent"]) ?? 0
    return sizedBox(
        nil,
        height,
        center(padding(
            EdgeInsets(top: 0, right: endIndent, bottom: 0, left: indent),
            container(height: thickness, decoration: BoxDecoration(color: s.borderColor ?? s.color ?? M3.outlineVariant))
        ))
    )
}

private func buildVerticalDivider(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let s = node.style ?? CSSStyle()
    let thickness = s.borderWidth ?? 1
    let width = s.width ?? 16
    return sizedBox(width, nil, center(container(width: thickness, decoration: BoxDecoration(color: s.borderColor ?? s.color ?? M3.outlineVariant))))
}

private func buildCircularProgress(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let value = num(node.props["value"])
    return w(
        "control",
        [
            "kind": "progress",
            "view": jo([
                "variant": "circular",
                "value": value,
                "strokeWidth": node.style?.borderWidth ?? 4,
                "colors": jo(["indicator": node.style?.color ?? M3.primary, "track": node.style?.backgroundColor]),
            ]),
        ]
    )
}

private func buildLinearProgress(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let value = num(node.props["value"])
    return w(
        "control",
        [
            "kind": "progress",
            "view": jo([
                "variant": "linear",
                "value": value,
                "strokeWidth": num(node.props["minHeight"]) ?? 4,
                "colors": jo(["indicator": node.style?.color ?? M3.primary, "track": node.style?.backgroundColor ?? M3.secondaryContainer]),
            ]),
        ]
    )
}

private func buildTooltip(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    w(
        "gesture",
        ["gestures": ["longpress", "hover"], "tooltip": jsString(node.props["message"] ?? ""), "onEvent": { (_: ViewEvent) in }],
        child: first(children) ?? container()
    )
}

private func buildBadge(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let label = node.props["label"].map { jsString($0) } ?? ""
    let child = first(children) ?? container()
    let s = node.style ?? CSSStyle()
    let pill: W
    if label == "" {
        pill = container(width: 6, height: 6, decoration: BoxDecoration(color: s.backgroundColor ?? M3.error, shape: "circle"))
    } else {
        pill = container(
            child: text(label, TextStyle(color: s.color ?? Colors.white, fontSize: 11, fontWeight: 500, letterSpacing: 0.5, height: 16.0 / 11), ["softWrap": false]),
            height: 16,
            padding: EdgeInsets.symmetric(vertical: 0, horizontal: 4),
            alignment: Alignment(x: 0, y: 0),
            decoration: BoxDecoration(color: s.backgroundColor ?? M3.error, radius: BorderRadius.all(8)),
            minWidth: 16
        )
    }
    let off: Double = label == "" ? 0 : -4
    return w("stack", ["alignment": Alignment(x: -1, y: -1), "fit": "loose"], [child, w("positioned", ["top": off, "right": off], child: pill)])
}

private func buildChip(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let label = jsString(node.props["label"] ?? "")
    let s = node.style ?? CSSStyle()
    var content: [W] = []
    if let avatar = node.children.firstIndex(where: { ($0.props["slot"] as? String) == "avatar" }) {
        content.append(padding(EdgeInsets(top: 0, right: 8, bottom: 0, left: 0), sizedBox(18, 18, children[avatar])))
    }
    content.append(text(label, TextStyle.LABEL_LARGE.with { $0.color = s.color ?? M3.onSurfaceVariant }, ["softWrap": false]))
    return padding(
        EdgeInsets.symmetric(vertical: 8, horizontal: 0),
        container(
            child: w("flex", ["direction": "row", "crossAxisAlignment": "center", "mainAxisSize": "min"], content),
            padding: EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            alignment: nil,
            decoration: BoxDecoration(
                color: s.backgroundColor,
                border: Border(top: side(M3.outlineVariant), right: side(M3.outlineVariant), bottom: side(M3.outlineVariant), left: side(M3.outlineVariant)),
                radius: s.borderRadius ?? BorderRadius.all(8)
            ),
            minHeight: 32
        )
    )
}

private func buildDismissible(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let state = ctx.engine.stateFor(ctx.elementId) { DismissState(false) }
    let child = first(children) ?? container()
    if state.dismissed { return SHRINK }
    return w(
        "gesture",
        [
            "gestures": ["dismiss"],
            "dismissDirection": jsString(node.props["direction"] ?? "horizontal"),
            "onEvent": { (e: ViewEvent) in
                if e.type == "dismissed" {
                    state.dismissed = true
                    dispatchEvent(ctx, "dismissed", jo(["data": jo(["direction": e.direction])]))
                    if node.events?["dismiss"] != nil { dispatchEvent(ctx, "dismiss", jo(["data": jo(["direction": e.direction])])) }
                    ctx.engine.host.invalidate?()
                }
            },
        ],
        child: child
    )
}

private func buildDraggable(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let child = first(children) ?? container()
    let data = node.props["data"]
    return w(
        "gesture",
        [
            "gestures": ["draggable"],
            "dragData": data,
            "onEvent": { (e: ViewEvent) in
                switch e.type {
                case "dragstart": dispatchEvent(ctx, "dragstart", jo(["data": jo(["data": data])]))
                case "dragupdate": ctx.engine.dragOver(ctx.elementId, e, data)
                case "dragend", "drop": ctx.engine.dropAt(ctx.elementId, e, data)
                default: break
                }
            },
        ],
        child: child
    )
}

private func buildDragTarget(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let child = first(children) ?? container()
    return w("gesture", ["gestures": [String](), "dragTargetId": ctx.elementId, "onEvent": { (_: ViewEvent) in }], child: child, "dt:\(ctx.elementId)")
}

private func buildCanvas(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let raw = asArray(node.props["commands"]) ?? []
    let commands = raw.filter { isMap($0) }.map { normalizeCommand(commandFromJson($0)) }
    let bg = parseColor(node.props["backgroundColor"]) ?? node.style?.backgroundColor
    return w(
        "canvas",
        [
            "width": num(node.props["width"]) ?? node.style?.width,
            "height": num(node.props["height"]) ?? node.style?.height,
            "background": bg,
            "commands": commands,
            "onEvent": { (e: ViewEvent) in ctx.engine.handleGesture(ctx.elementId, node, e) },
        ]
    )
}

/** The Flutter-DSL builders, in registration order. */
public let flutterWidgets: [(String, WidgetBuilder)] = [
    ("Container", buildContainer),
    ("Text", buildText),
    ("Button", buildButton),
    ("Image", buildImage),
    ("Column", { node, children, ctx in applyStyle(flexOrWrap("column", node.style, children), node.style, ApplyStyleOptions(), ctx) }),
    ("Row", { node, children, ctx in applyStyle(flexOrWrap("row", node.style, children), node.style, ApplyStyleOptions(), ctx) }),
    ("Stack", buildStack),
    ("Positioned", buildPositioned),
    ("Expanded", { node, children, _ in
        w("flexible", ["flex": num(node.props["flex"]) ?? 1, "fit": "tight"], child: first(children) ?? container())
    }),
    ("Flexible", { node, children, _ in
        w("flexible", ["flex": num(node.props["flex"]) ?? 1, "fit": node.props.s("fit") == "tight" ? "tight" : "loose"], child: first(children) ?? container())
    }),
    ("Center", { node, children, ctx in applyStyle(center(first(children) ?? container()), node.style, ApplyStyleOptions(), ctx) }),
    ("Padding", { node, children, _ in
        padding(node.style?.padding ?? EdgeInsets.all(8), first(children) ?? container(), node.style?.paddingPercent)
    }),
    ("Align", { node, children, _ in align(node.style?.alignment ?? Alignment(x: 0, y: 0), first(children) ?? container()) }),
    ("SizedBox", { node, children, _ in
        sizedBox(node.style?.width ?? num(node.props["width"]), node.style?.height ?? num(node.props["height"]), first(children))
    }),
    ("ListView", buildListView),
    ("GridView", buildGridView),
    ("TextField", buildTextField),
    ("Checkbox", buildCheckbox),
    ("Radio", buildRadio),
    ("Switch", buildSwitch),
    ("Slider", buildSlider),
    ("Icon", buildIcon),
    ("Card", buildCard),
    ("Scaffold", buildScaffold),
    ("AppBar", buildAppBar),
    ("Wrap", buildWrap),
    ("InkWell", buildInkWell),
    // Events on the node are recognised by the engine's gesture region.
    ("GestureDetector", { _, children, _ in w("proxy", Props(), child: first(children) ?? container()) }),
    ("Opacity", { node, children, _ in
        let opacity = node.style?.opacity ?? num(node.props["opacity"]) ?? 1
        return w("opacity", ["opacity": opacity], child: first(children) ?? container())
    }),
    ("Transform", buildTransform),
    ("ClipRRect", { node, children, _ in
        w("clip", ["radius": node.style?.borderRadius ?? BorderRadius.all(8)], child: first(children) ?? container())
    }),
    ("ConstrainedBox", buildConstrainedBox),
    ("AspectRatio", { node, children, _ in
        w("aspectRatio", ["aspectRatio": num(node.props["aspectRatio"]) ?? node.style?.aspectRatio ?? 1], child: first(children) ?? container())
    }),
    ("FractionallySizedBox", { node, children, _ in
        w(
            "fractional",
            [
                "widthFactor": num(node.props["widthFactor"]),
                "heightFactor": num(node.props["heightFactor"]),
                "alignment": node.style?.alignment ?? Alignment(x: 0, y: 0),
            ],
            child: first(children)
        )
    }),
    ("FittedBox", { node, children, _ in
        let fit = node.props["fit"] as? String ?? "contain"
        return w("fitted", ["fit": fit, "alignment": node.style?.alignment ?? Alignment(x: 0, y: 0)], child: w("fittedContent", Props(), child: first(children) ?? container()))
    }),
    ("LimitedBox", { node, children, _ in
        w("limited", ["maxWidth": node.style?.maxWidth, "maxHeight": node.style?.maxHeight], child: first(children) ?? container())
    }),
    ("OverflowBox", buildOverflowBox),
    ("Baseline", { node, children, _ in w("baseline", ["baseline": num(node.props["baseline"]) ?? 0], child: first(children) ?? container()) }),
    ("Spacer", { node, _, _ in w("flexible", ["flex": num(node.props["flex"]) ?? 1, "fit": "tight"], child: SHRINK) }),
    ("Divider", buildDivider),
    ("VerticalDivider", buildVerticalDivider),
    ("CircularProgressIndicator", buildCircularProgress),
    ("LinearProgressIndicator", buildLinearProgress),
    ("Tooltip", buildTooltip),
    ("Badge", buildBadge),
    ("Chip", buildChip),
    ("Dismissible", buildDismissible),
    ("Draggable", buildDraggable),
    ("DragTarget", buildDragTarget),
    ("Hero", { node, children, _ in w("hero", ["tag": node.props["tag"] ?? "hero"], child: first(children) ?? container()) }),
    ("IndexedStack", { node, children, _ in
        w("indexedStack", ["index": num(node.props["index"]) ?? 0, "alignment": parseAlignmentProp(node.props["alignment"], Alignment(x: -1, y: -1))], children)
    }),
    ("RotatedBox", { node, children, _ in
        w("rotatedBox", ["quarterTurns": num(node.props["quarterTurns"]) ?? 0], child: first(children) ?? container())
    }),
    ("DecoratedBox", { node, children, ctx in
        let s = node.style ?? CSSStyle()
        let d = decorationFromStyle(s, ctx)
        return decorated(d, first(children) ?? container())
    }),
    ("Scope", { _, children, _ in children.isEmpty ? SHRINK : children.count == 1 ? children[0] : column(children) }),
    ("Canvas", buildCanvas),
    ("CachedCanvas", { node, _, ctx in cachedCanvas(node, ctx) }),
    ("Scene3D", { node, children, ctx in scene3d(node, children, ctx) }),
    ("scene3d", { node, children, ctx in scene3d(node, children, ctx) }),
    ("MathExpression", { node, _, ctx in mathExpression(node, ctx) }),
    ("Math", { node, _, ctx in mathExpression(node, ctx) }),
]

/** `CachedCanvas`: a canvas drawing a guest-managed (`canvas.ctx.*`) command context. */
func cachedCanvas(_ node: ElpianNode, _ ctx: BuildContext) -> W {
    let id = jsString(node.props["contextId"] ?? node.props["id"] ?? "")
    if id == "" { return SHRINK }
    let store = ctx.engine.services.canvasContexts
    let c = store[ctx.engine.services.scopeId(id)] ?? store[id]
    let width = num(node.props["width"]) ?? node.style?.width
    let height = num(node.props["height"]) ?? node.style?.height
    guard let context = c else { return SHRINK }
    if let wv = width, let hv = height { context.setSize(wv, hv) }
    let bg = parseColor(node.props["backgroundColor"]) ?? node.style?.backgroundColor
    return w(
        "canvas",
        [
            "width": width ?? context.width,
            "height": height ?? context.height,
            "background": bg,
            "context": context,
            // The TypeScript props carry a `{id, version, generation, commands}` snapshot so a
            // changed context reconfigures the render object; the live context is passed here,
            // with its version and generation alongside for the same change detection.
            "contextVersion": Double(context.version),
            "contextGeneration": Double(context.generation),
        ]
    )
}

private func flexOrWrap(_ direction: String, _ style: CSSStyle?, _ children: [W]) -> W {
    let gap = style?.gap ?? 0
    let wraps = style?.flexWrap == "wrap" || style?.flexWrap == "wrap-reverse"
    let main = style?.justifyContent
    let cross = style?.alignItems
    func mainMap(_ v: String?) -> String {
        switch (v ?? "").lowercased() {
        case "center": return "center"
        case "flex-end", "end": return "end"
        case "space-between": return "spaceBetween"
        case "space-around": return "spaceAround"
        case "space-evenly": return "spaceEvenly"
        default: return "start"
        }
    }
    func crossMap(_ v: String?) -> String {
        switch (v ?? "").lowercased() {
        case "center": return "center"
        case "flex-end", "end": return "end"
        case "stretch": return "stretch"
        case "baseline": return "baseline"
        default: return "start"
        }
    }
    if wraps {
        let c = crossMap(cross)
        return w(
            "wrap",
            [
                "direction": direction == "row" ? "horizontal" : "vertical",
                "spacing": gap,
                "runSpacing": gap,
                "alignment": mainMap(main),
                "crossAxisAlignment": c == "stretch" || c == "baseline" ? "start" : c,
                "verticalDirection": style?.flexWrap == "wrap-reverse" ? "up" : "down",
            ],
            children
        )
    }
    return w("flex", ["direction": direction, "mainAxisAlignment": mainMap(main), "crossAxisAlignment": crossMap(cross), "mainAxisSize": "max", "gap": gap], children)
}

private func scene3d(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let p = node.props
    let raw = p["initialScene"] ?? p["scene"] ?? p["world"]
    var json: JSONObject?
    if let m = asMap(raw) {
        json = m
    } else if let a = asArray(raw) {
        json = JSONObject([("nodes", a)])
    }
    let controller = ctx.engine.sceneFor(ctx.elementId, json)
    let placeholder = first(children) ?? scenePlaceholder()
    let clickable = p.b("clickable")
    return w(
        "scene3d",
        [
            "surfaceId": Double(controller.godot.surfaceId),
            "live": controller.isLive,
            "width": num(p["width"]) ?? node.style?.width,
            "height": num(p["height"]) ?? node.style?.height,
            "clickable": clickable,
            "onEvent": { (e: ViewEvent) in
                if e.type == "tap" && clickable { ctx.engine.host.sceneTap?(p.copy()) }
            },
        ],
        child: placeholder
    )
}

/** `_Scene3DPlaceholder`: a quiet gradient panel with an AR icon and a caption. */
private func scenePlaceholder() -> W {
    decorated(
        BoxDecoration(gradients: [Gradient(kind: .linear, colors: [0xff10141d, 0xff1a2233], begin: Alignment(x: -1, y: -1), end: Alignment(x: 1, y: 1))]),
        center(
            column(
                [icon("view_in_ar", 36, Colors.white24), sizedBox(nil, 8), text("3D unavailable on this platform", TextStyle(color: Colors.white38, fontSize: 12))],
                ["mainAxisSize": "min", "crossAxisAlignment": "center"]
            )
        )
    )
}

// ----------------------------------------------------------------------------
// MathExpression
// ----------------------------------------------------------------------------

private let MATH_SYMBOLS: [(JSRegex, String)] = [
    ("alpha", "α"), ("beta", "β"), ("gamma", "γ"), ("delta", "δ"), ("theta", "θ"), ("lambda", "λ"), ("mu", "μ"),
    ("pi", "π"), ("sigma", "σ"), ("phi", "φ"), ("omega", "ω"), ("sum", "∑"), ("prod", "∏"), ("int", "∫"),
    ("infty", "∞"), ("sqrt", "√"), ("neq", "≠"), ("leq", "≤"), ("geq", "≥"), ("approx", "≈"), ("times", "×"),
    ("cdot", "·"), ("pm", "±"), ("to", "→"), ("leftarrow", "←"), ("Rightarrow", "⇒"), ("forall", "∀"),
    ("exists", "∃"), ("in", "∈"), ("notin", "∉"), ("subset", "⊂"), ("subseteq", "⊆"), ("cup", "∪"), ("cap", "∩"),
].map { (JSRegex("\\\\" + $0.0), $0.1) }

private let SUPER: [String: String] = [
    "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
    "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ", "i": "ⁱ",
]
private let SUB: [String: String] = [
    "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
    "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎",
]
private let BLOCKED = ["write", "input", "include", "openout", "read", "catcode", "usepackage", "newcommand", "renewcommand", "def", "csname", "every", "special"]
private let BLOCKED_RES: [JSRegex] = BLOCKED.map { JSRegex("\\\\" + $0, ignoreCase: true) }
private let CONTROL_CHARS = JSRegex("[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F\\x7F]")

public struct SanitizedMath: Equatable {
    public var value: String
    public var sanitized: Bool

    public init(value: String, sanitized: Bool) {
        self.value = value
        self.sanitized = sanitized
    }
}

/** Strip control characters, cap the length and neutralise TeX commands that could reach the file system. */
public func sanitizeMath(_ input: String) -> SanitizedMath {
    var expression = jsTrim(CONTROL_CHARS.replace(input, with: " "))
    if jsLength(expression) > 4096 { expression = jsSubstring(expression, 0, 4096) }
    var sanitized = false
    for re in BLOCKED_RES {
        if re.test(expression) { sanitized = true }
        expression = re.replace(expression, with: "\\text{blocked}")
    }
    return SanitizedMath(value: expression, sanitized: sanitized)
}

private let FRAC = JSRegex("\\\\frac\\s*\\{([^{}]*)\\}\\s*\\{([^{}]*)\\}")
private let SUPER_RE = JSRegex("\\^\\{([^{}]+)\\}|\\^([A-Za-z0-9+\\-=()])")
private let SUB_RE = JSRegex("_\\{([^{}]+)\\}|_([A-Za-z0-9+\\-=()])")
private let LEFT_RIGHT = JSRegex("\\\\left|\\\\right")
private let TEXT_CMD = JSRegex("\\\\text\\{([^{}]*)\\}")
private let BRACES = JSRegex("[{}]")

private func mapScript(_ value: String, _ map: [String: String]) -> String {
    var out = ""
    for scalar in value.unicodeScalars {
        let ch = String(Character(scalar))
        out += map[ch] ?? ch
    }
    return out
}

/** A LaTeX subset rendered to Unicode (fractions, Greek letters, operators, super/subscripts). */
public func renderMathToUnicode(_ expression: String) -> String {
    var out = expression
    var i = 0
    while i < 24 && FRAC.test(out) {
        out = FRAC.replace(out) { m in "(\(m[1] ?? ""))/(\(m[2] ?? ""))" }
        i += 1
    }
    for (re, sym) in MATH_SYMBOLS { out = re.replace(out, with: sym) }
    out = SUPER_RE.replace(out) { m in mapScript(m[1] ?? m[2] ?? "", SUPER) }
    out = SUB_RE.replace(out) { m in mapScript(m[1] ?? m[2] ?? "", SUB) }
    out = LEFT_RIGHT.replace(out, with: "")
    out = TEXT_CMD.replace(out) { m in m[1] ?? "" }
    out = BRACES.replace(out, with: "")
    return jsTrim(out)
}

private func mathExpression(_ node: ElpianNode, _ ctx: BuildContext) -> W {
    let p = node.props
    let raw = jsString(p["expression"] ?? p["latex"] ?? p["text"] ?? p["data"] ?? "")
    let sanitized = sanitizeMath(raw)
    let rendered = renderMathToUnicode(sanitized.value)
    let style: TextStyle = node.style != nil ? (createTextStyle(node.style) ?? TextStyle()) : TextStyle(fontSize: 18)
    let result: W
    if jsTrim(rendered) == "" {
        result = text("Math expression is required", style)
    } else {
        var parts = [w("scroll", ["axis": "horizontal"], child: text(rendered, style, ["selectable": true, "softWrap": false]))]
        if sanitized.sanitized {
            parts.append(padding(EdgeInsets(top: 4, right: 0, bottom: 0, left: 0), text("Unsafe commands were sanitized from the expression.", TextStyle(color: Colors.orange, fontSize: 11))))
        }
        result = column(parts, ["crossAxisAlignment": "start", "mainAxisSize": "min"])
    }
    return applyStyle(result, node.style, ApplyStyleOptions(), ctx)
}
