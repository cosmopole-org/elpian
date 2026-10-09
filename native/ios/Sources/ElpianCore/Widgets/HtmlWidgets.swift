import Foundation

/**
 * The HTML elements (widgets/html.ts) — one builder per file in
 * flutter/lib/src/html_widgets, lowered to the same composition (default
 * margins, sizes and colours are the Flutter engine's), with the elements
 * Flutter leaves as placeholders made real: tables lay out rows and cells,
 * forms collect and submit their fields, `details` expands, `picture` honours
 * its `source` media queries, image maps are clickable, `datalist` feeds input
 * suggestions, `sub`/`sup` shift the baseline.
 *
 * Inline content — a `p`/`span`/heading/`li`/`a` whose children are text-level
 * elements — becomes one paragraph of styled spans that wraps across element
 * boundaries, as HTML does.
 */

private func num(_ v: Any?) -> Double? { toNumber(v) }

/** A [CSSStyle] literal. */
func css(_ configure: (CSSStyle) -> Void) -> CSSStyle { CSSStyle.make(configure) }

private func underline() -> TextDecoration { TextDecoration(underline: true, overline: false, lineThrough: false) }
private func lineThrough() -> TextDecoration { TextDecoration(underline: false, overline: false, lineThrough: true) }

/** `p.key === true || p.key === "<key>"` — an HTML boolean attribute. */
private func attrOn(_ p: JSONObject, _ key: String, _ word: String) -> Bool { p.b(key) || p.s(key) == word }

// ============================================================================
// Inline formatting
// ============================================================================

/** Default text styles of text-level elements. */
private let INLINE_DEFAULTS: [String: TextStyle] = [
    "span": TextStyle(),
    "strong": TextStyle(fontWeight: 700),
    "b": TextStyle(fontWeight: 700),
    "em": TextStyle(italic: true),
    "i": TextStyle(italic: true),
    "cite": TextStyle(italic: true),
    "var": TextStyle(italic: true),
    "dfn": TextStyle(italic: true),
    "u": TextStyle(decoration: Decoration.underline),
    "ins": TextStyle(decoration: Decoration.underline),
    "s": TextStyle(decoration: Decoration.lineThrough),
    "del": TextStyle(decoration: Decoration.lineThrough),
    "strike": TextStyle(decoration: Decoration.lineThrough),
    "code": TextStyle(fontFamily: "monospace", background: 0xfff5f5f5),
    "kbd": TextStyle(fontFamily: "monospace", background: 0xffeeeeee),
    "samp": TextStyle(fontFamily: "monospace"),
    "tt": TextStyle(fontFamily: "monospace"),
    "mark": TextStyle(background: 0xffffff00),
    "small": TextStyle(fontSize: 12),
    "sub": TextStyle(fontSize: 10, baselineShift: 3),
    "sup": TextStyle(fontSize: 10, baselineShift: -6),
    "abbr": TextStyle(decoration: Decoration.underline),
    "a": TextStyle(color: Colors.blue, decoration: Decoration.underline),
    "q": TextStyle(),
    "time": TextStyle(),
    "data": TextStyle(),
    "label": TextStyle(fontWeight: 500),
]

private let INLINE_TAGS: Set<String> = Set(INLINE_DEFAULTS.keys).union(["br", "#text"])

/**
 * The spans of an inline subtree, or nil when it contains something that is
 * not text-level (a box, an image, a control, an element with its own events
 * other than a link).
 */
private func inlineSpans(_ node: ElpianNode, _ inherited: TextStyle, _ ctx: BuildContext, _ depth: Int = 0) -> [SpanInput]? {
    if depth > 12 { return nil }
    if node.type == "#text" { return [SpanInput(text: jsString(node.props["text"] ?? ""), style: inherited)] }
    if node.type == "br" { return [SpanInput(text: "\n", style: inherited)] }
    if !INLINE_TAGS.contains(node.type) { return nil }
    let s = node.style
    if let s = s, s.display == "block" || s.display == "flex" || s.display == "grid" || s.position == "absolute" || s.position == "fixed" { return nil }
    if let s = s, s.width != nil || s.height != nil || s.border != nil || s.borderRadius != nil || s.boxShadow != nil || s.transform != nil { return nil }
    if s?.display == "none" { return [] }
    let events = node.events?.keys ?? []
    let isLink = node.type == "a" && events.allSatisfy { $0 == "click" || $0 == "tap" }
    if !events.isEmpty && !isLink { return nil }
    var own = mergeTextStyle(mergeTextStyle(inherited, INLINE_DEFAULTS[node.type] ?? TextStyle()), createTextStyle(s))
    if let bg = s?.backgroundColor { own.background = bg }
    let link: String? = node.type == "a" ? jsString(node.props["href"] ?? "#") : nil
    var out: [SpanInput] = []
    let t = node.text
    if !t.isEmpty { out.append(SpanInput(text: node.type == "q" ? "“\(t)”" : t, style: own, link: link)) }
    for child in node.children {
        guard let childSpans = inlineSpans(child, own, ctx, depth + 1) else { return nil }
        for span in childSpans {
            if let l = link, span.link == nil {
                var copy = span
                copy.link = l
                out.append(copy)
            } else {
                out.append(span)
            }
        }
    }
    return out
}

/** A paragraph from an element's text and inline children, or nil if not inline. */
private func richText(_ node: ElpianNode, _ style: TextStyle, _ ctx: BuildContext, _ opts: JSONObject = JSONObject()) -> W? {
    if node.children.isEmpty { return nil }
    var spans: [SpanInput] = []
    let t = node.text
    if !t.isEmpty { spans.append(SpanInput(text: t, style: TextStyle())) }
    for child in node.children {
        guard let childSpans = inlineSpans(child, TextStyle(), ctx) else { return nil }
        spans.append(contentsOf: childSpans)
    }
    let props: JSONObject = ["spans": spans, "style": style]
    props.assign(opts)
    props["onLink"] = { (href: String) in openLink(ctx, href, nil) }
    return w("text", props)
}

private let EXTERNAL_LINK = JSRegex("^(https?:|mailto:|tel:|sms:|geo:)", ignoreCase: true)
private let HTTP_LINK = JSRegex("^https?:", ignoreCase: true)

private func openLink(_ ctx: BuildContext, _ href: String, _ node: ElpianNode?) {
    if node?.events?["click"] != nil || node?.events?["tap"] != nil {
        dispatchEvent(ctx, "click")
    }
    if href.isEmpty || href == "#" { return }
    let host = ctx.engine.host
    if EXTERNAL_LINK.test(href) || host.navigate == nil {
        host.openUrl?(href)
    } else {
        host.navigate?(href, false)
    }
}

// ============================================================================
// Layout: HtmlDiv
// ============================================================================

private func childStyle(_ node: ElpianNode) -> CSSStyle? {
    var n = node
    while n.type == "Scope" && n.children.count == 1 { n = n.children[0] }
    return n.style
}

private func stretchChild(_ child: W) -> W {
    if child.t == "flexible", let inner = child.c?.first {
        return W(child.t, child.p, [w("fill", ["width": true], child: inner)], child.k)
    }
    return w("fill", ["width": true], child: child)
}

private func unflex(_ child: W) -> W {
    if child.t == "flexible", let inner = child.c?.first { return inner }
    return child
}

/** `_buildColumn`: stretch children without an explicit width (CSS block flow). */
private func buildColumn(_ node: ElpianNode, _ children: [W], _ gap: Double, _ mainAxisAlignment: String, _ mainAxisSize: String, _ flowNodes: [ElpianNode]) -> W {
    let alignItems = node.style?.alignItems
    let canStretch = alignItems == nil && flowNodes.count == children.count
    let reverse = node.style?.flexDirection == "column-reverse"
    if !canStretch {
        return w(
            "flex",
            ["direction": "column", "mainAxisAlignment": mainAxisAlignment, "crossAxisAlignment": crossOf(alignItems), "mainAxisSize": mainAxisSize, "gap": gap, "reverse": reverse],
            children
        )
    }
    let laid = children.enumerated().map { i, child -> W in
        let cs = childStyle(flowNodes[i])
        return cs?.width == nil && cs?.widthFactor == nil ? stretchChild(child) : child
    }
    return w(
        "flex",
        ["direction": "column", "mainAxisAlignment": mainAxisAlignment, "crossAxisAlignment": "start", "mainAxisSize": mainAxisSize, "gap": gap, "reverse": reverse],
        laid
    )
}

private func mainOf(_ v: String?) -> String {
    switch (v ?? "").lowercased() {
    case "center": return "center"
    case "flex-end", "end", "right": return "end"
    case "space-between": return "spaceBetween"
    case "space-around": return "spaceAround"
    case "space-evenly": return "spaceEvenly"
    default: return "start"
    }
}

private func crossOf(_ v: String?) -> String {
    switch (v ?? "").lowercased() {
    case "center": return "center"
    case "flex-end", "end": return "end"
    case "stretch": return "stretch"
    case "baseline": return "baseline"
    default: return "start"
    }
}

private func wrapCrossOf(_ v: String?) -> String {
    let c = crossOf(v)
    return c == "center" || c == "end" ? c : "start"
}

private func buildFlow(_ node: ElpianNode, _ children: [W], _ flowNodes: [ElpianNode]) -> W {
    let s = node.style
    let display = s?.display
    if display == "grid" || display == "inline-grid" { return buildGrid(node, children, flowNodes) }
    let gap = s?.gap ?? s?.columnGap ?? 0
    if display == "flex" || display == "inline-flex" {
        let dir = s?.flexDirection ?? "row"
        let isRow = dir == "row" || dir == "row-reverse"
        let wraps = s?.flexWrap == "wrap" || s?.flexWrap == "wrap-reverse"
        if wraps {
            return w(
                "wrap",
                [
                    "direction": isRow ? "horizontal" : "vertical",
                    "spacing": isRow ? (s?.columnGap ?? gap) : (s?.rowGap ?? gap),
                    "runSpacing": isRow ? (s?.rowGap ?? gap) : (s?.columnGap ?? gap),
                    "alignment": mainOf(s?.justifyContent),
                    "runAlignment": mainOf(s?.alignContent),
                    "crossAxisAlignment": wrapCrossOf(s?.alignItems),
                    "verticalDirection": s?.flexWrap == "wrap-reverse" ? "up" : "down",
                    "reverse": dir.hasSuffix("reverse"),
                ],
                children
            )
        }
        if isRow {
            let flex = w(
                "flex",
                [
                    "direction": "row",
                    "mainAxisAlignment": mainOf(s?.justifyContent),
                    "crossAxisAlignment": crossOf(s?.alignItems),
                    "mainAxisSize": "max",
                    "gap": s?.columnGap ?? gap,
                    "reverse": dir == "row-reverse",
                    "shrink": true,
                ],
                children
            )
            let hasFlex = flowNodes.contains { c in (childStyle(c)?.flex ?? childStyle(c)?.flexGrow) != nil }
            // `_flexSafe`: an unbounded row with flex children takes its intrinsic width.
            return hasFlex ? w("intrinsicWidth", ["onlyWhenUnbounded": true], [flex]) : flex
        }
        return buildColumn(node, children, s?.rowGap ?? gap, mainOf(s?.justifyContent), "max", flowNodes)
    }
    if children.count == 1 { return unflex(children[0]) }
    return buildColumn(node, children, s?.rowGap ?? gap, "start", "min", flowNodes)
}

private func buildGrid(_ node: ElpianNode, _ children: [W], _ flowNodes: [ElpianNode]) -> W {
    let s = node.style ?? CSSStyle()
    let base = s.gridGap ?? s.gap ?? 0
    let items = children.enumerated().map { i, child -> W in
        let cs = childStyle(flowNodes[i])
        let area = cs?.gridArea
        var parts: [String]?
        if let a = area, !a.isEmpty, a.contains("/") { parts = a.components(separatedBy: "/") }
        let partColumn: String? = (parts?.count ?? 0) > 1 ? parts![1] : nil
        let partRow: String? = (parts?.count ?? 0) > 0 ? parts![0] : nil
        return w(
            "gridItem",
            ["column": cs?.gridColumn ?? partColumn, "row": cs?.gridRow ?? partRow, "alignSelf": cs?.alignSelf],
            child: unflex(child)
        )
    }
    return w(
        "grid",
        [
            "columns": s.gridTemplateColumns,
            "rows": s.gridTemplateRows,
            "autoRows": s.gridAutoRows,
            "columnGap": s.gridColumnGap ?? s.columnGap ?? base,
            "rowGap": s.gridRowGap ?? s.rowGap ?? base,
            "alignItems": s.alignItems,
        ],
        items
    )
}

private func buildPositionedLayout(_ node: ElpianNode, _ children: [W]) -> W? {
    let nodes = node.children
    if nodes.count != children.count { return nil }
    let styles = nodes.map { childStyle($0) }
    func isAbs(_ st: CSSStyle?) -> Bool { st?.position == "absolute" || st?.position == "fixed" }
    if !styles.contains(where: { isAbs($0) }) { return nil }
    var flow: [W] = []
    var flowNodes: [ElpianNode] = []
    var positioned: [Int] = []
    for (i, st) in styles.enumerated() {
        if isAbs(st) {
            positioned.append(i)
        } else {
            flow.append(children[i])
            flowNodes.append(nodes[i])
        }
    }
    let order = positioned.sorted { a, b in
        let za = styles[a]?.zIndex ?? 0
        let zb = styles[b]?.zIndex ?? 0
        return za != zb ? za < zb : a < b
    }
    var stackChildren: [W] = []
    if !flow.isEmpty { stackChildren.append(w("fill", ["width": true], child: buildFlow(node, flow, flowNodes))) }
    for i in order {
        let st = styles[i]!
        let lr = st.left != nil && st.right != nil
        let tb = st.top != nil && st.bottom != nil
        stackChildren.append(
            w(
                "positioned",
                ["top": st.top, "left": st.left, "right": st.right, "bottom": st.bottom, "width": lr ? nil : st.width, "height": tb ? nil : st.height],
                child: unflex(children[i])
            )
        )
    }
    return w("stack", ["alignment": Alignment(x: -1, y: -1), "fit": "loose", "clip": true], stackChildren)
}

/** `HtmlDiv.build` — the CSS box: block, flex, grid and positioned layouts. */
public func htmlDiv(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext, fullWidth: Bool = false) -> W {
    if children.isEmpty {
        var empty = SHRINK
        if fullWidth { empty = w("fill", ["width": true], child: empty) }
        return applyStyle(empty, node.style, ApplyStyleOptions(layoutHandled: true), ctx)
    }
    var body = buildPositionedLayout(node, children) ?? buildFlow(node, children, node.children)
    if fullWidth { body = w("fill", ["width": true], child: body) }
    return applyStyle(body, node.style, ApplyStyleOptions(layoutHandled: true), ctx)
}

// ============================================================================
// Text-bearing elements
// ============================================================================

private func textElement(_ node: ElpianNode, _ ctx: BuildContext, _ defaults: CSSStyle, _ baseText: TextStyle = TextStyle()) -> W {
    let style = withDefaults(node.style, defaults)
    let ts = mergeTextStyle(baseText, createTextStyle(style))
    let opts = textOptionsFromStyle(style)
    if let rich = richText(node, ts, ctx, opts) { return applyStyle(rich, style, ApplyStyleOptions(), ctx) }
    return applyStyle(text(node.text, ts, opts), style, ApplyStyleOptions(), ctx)
}

/** A text element that may also hold block children (Column of text + children). */
private func textWithChildren(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext, _ defaults: CSSStyle, _ layout: String) -> W {
    let style = withDefaults(node.style, defaults)
    let ts = createTextStyle(style) ?? TextStyle()
    let opts = textOptionsFromStyle(style)
    if children.isEmpty { return applyStyle(text(node.text, ts, opts), style, ApplyStyleOptions(), ctx) }
    if let rich = richText(node, ts, ctx, opts) { return applyStyle(rich, style, ApplyStyleOptions(), ctx) }
    var parts: [W] = []
    let t = node.text
    if !t.isEmpty { parts.append(text(t, ts, opts)) }
    parts.append(contentsOf: children)
    let body = layout == "column"
        ? column(parts, ["crossAxisAlignment": "start", "mainAxisSize": "min"])
        : w("wrap", ["direction": "horizontal", "crossAxisAlignment": "center"], parts)
    return applyStyle(w("defaultTextStyle", ["style": ts], child: body), style, ApplyStyleOptions(layoutHandled: true), ctx)
}

private func heading(_ size: Double, _ marginV: Double) -> WidgetBuilder {
    return { node, children, ctx in
        textWithChildren(node, children, ctx, css { $0.fontSize = size; $0.fontWeight = 700; $0.margin = EdgeInsets.symmetric(vertical: marginV, horizontal: 0) }, "column")
    }
}

private func monoStyle(_ bg: Color, _ pad: EdgeInsets, _ extra: (CSSStyle) -> Void = { _ in }) -> CSSStyle {
    css { s in
        s.fontFamily = "monospace"
        s.backgroundColor = bg
        s.padding = pad
        extra(s)
    }
}

/**
 * Flutter's text-level elements use `node.style ?? defaultStyle` (an author
 * style replaces the defaults wholesale) — kept for fidelity.
 */
private func replaceDefaults(_ node: ElpianNode, _ ctx: BuildContext, _ defaults: CSSStyle, _ inline: TextStyle) -> W {
    let style = node.style ?? defaults
    let ts = mergeTextStyle(node.style != nil ? INLINE_DEFAULTS[node.type] ?? TextStyle() : inline, createTextStyle(style))
    let rich = richText(node, ts, ctx)
    return applyStyle(rich ?? text(node.text, ts, textOptionsFromStyle(style)), style, ApplyStyleOptions(), ctx)
}

// ============================================================================
// Form controls
// ============================================================================

private enum DARK {
    static let text: Color = 0xfff7eedc
    static let fill: Color = 0xff0a1626
    static let border: Color = 0xff1c3450
    static let focus: Color = 0xffd6b36a
    static let hint: Color = 0xff6b7e92
}

private final class CheckedState {
    var checked: Bool
    init(_ checked: Bool) { self.checked = checked }
}

private final class NumberState {
    var value: Double
    init(_ value: Double) { self.value = value }
}

private final class StringState {
    var value: String
    init(_ value: String) { self.value = value }
}

private final class SelectState {
    var value: String?
    var lastProp: String?
    init(_ value: String?, _ lastProp: String?) {
        self.value = value
        self.lastProp = lastProp
    }
}

private final class OpenState {
    var open: Bool
    init(_ open: Bool) { self.open = open }
}

private func datalistOptions(_ ctx: BuildContext, _ listId: String?) -> [String]? {
    guard let listId = listId, !listId.isEmpty else { return nil }
    guard let list = ctx.engine.datalists[listId], !list.isEmpty else { return nil }
    return list
}

private func idOf(_ node: ElpianNode) -> String? { node.props["id"].map { jsString($0) } }

private func optString(_ v: Any?) -> String? { flattenOptional(v).map { jsString($0) } }

private func htmlInput(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let p = node.props
    let type = jsString(p["type"] ?? "text").lowercased()
    let name = optString(p["name"])
    let disabled = attrOn(p, "disabled", "disabled")

    if type == "hidden" {
        ctx.engine.registerFormField(ctx.formId, name) { p["value"] ?? "" }
        return SHRINK
    }

    if type == "checkbox" {
        let state = ctx.engine.stateFor(ctx.elementId) { CheckedState(attrOn(p, "checked", "checked")) }
        ctx.engine.registerFormField(ctx.formId, name) { state.checked ? (p["value"] ?? "on") : nil }
        let result = w(
            "control",
            [
                "kind": "checkbox",
                "focusId": idOf(node),
                "view": jo([
                    "checked": state.checked,
                    "enabled": !disabled,
                    "colors": jo(["fill": node.style?.color ?? M3.primary, "check": M3.onPrimary, "border": M3.onSurfaceVariant]),
                ]),
                "onEvent": { (e: ViewEvent) in
                    if e.type == "change" {
                        state.checked = jsTruthy(e.value)
                        dispatchEvent(ctx, "change", jo(["value": state.checked]))
                    }
                },
            ]
        )
        return applyStyle(result, node.style, ApplyStyleOptions(), ctx)
    }

    if type == "radio" {
        let value = p["value"]
        let group = p["groupValue"]
        let checked = p.has("groupValue") ? jsStrictEquals(value, group) : attrOn(p, "checked", "checked")
        ctx.engine.registerFormField(ctx.formId, name) { checked ? value : nil }
        let result = w(
            "control",
            [
                "kind": "radio",
                "focusId": idOf(node),
                "view": jo([
                    "checked": checked,
                    "value": value,
                    "enabled": !disabled,
                    "colors": jo(["fill": node.style?.color ?? M3.primary, "border": M3.onSurfaceVariant]),
                ]),
                "controlled": true,
                "onEvent": { (e: ViewEvent) in
                    if e.type == "change" { dispatchEvent(ctx, "change", jo(["value": value])) }
                },
            ]
        )
        return applyStyle(result, node.style, ApplyStyleOptions(), ctx)
    }

    if type == "range" {
        let minV = num(p["min"]) ?? 0
        let maxV = num(p["max"]) ?? 100
        let state = ctx.engine.stateFor(ctx.elementId) { NumberState(max(minV, min(maxV, num(p["value"]) ?? ((minV + maxV) / 2)))) }
        ctx.engine.registerFormField(ctx.formId, name) { state.value }
        let step = num(p["step"]) ?? 1
        let result = w(
            "control",
            [
                "kind": "slider",
                "focusId": idOf(node),
                "view": jo([
                    "value": state.value,
                    "min": minV,
                    "max": maxV,
                    "step": step,
                    "enabled": !disabled,
                    "colors": jo(["active": DARK.focus, "inactive": DARK.border, "thumb": DARK.focus]),
                ]),
                "onEvent": { (e: ViewEvent) in
                    if e.type == "input" || e.type == "change" {
                        state.value = eventNumber(e.value)
                        dispatchEvent(ctx, e.type == "input" ? "input" : "change", jo(["value": state.value]))
                    }
                },
            ]
        )
        return applyStyle(result, node.style, ApplyStyleOptions(), ctx)
    }

    if type == "submit" || type == "button" || type == "reset" {
        let label = jsString(p["value"] ?? p["text"] ?? (type == "submit" ? "Submit" : type == "reset" ? "Reset" : "Button"))
        let fg = node.style?.color ?? (node.style?.backgroundColor != nil ? Colors.white : M3.primary)
        return htmlButtonLike(node, [text(label, TextStyle(color: fg))], ctx, type)
    }

    // Text-like inputs.
    let state = ctx.engine.stateFor(ctx.elementId) { StringState(optString(p["value"]) ?? "") }
    ctx.engine.registerFormField(ctx.formId, name) {
        if type == "number" { return state.value == "" ? nil : eventNumber(state.value) }
        return state.value
    }
    let s = node.style
    let textColor = s?.color ?? DARK.text
    let fontSize = s?.fontSize ?? 13
    let ts = TextStyle(color: textColor, fontSize: fontSize, letterSpacing: 0, height: 1.3)
    let view: JSONObject = [
        "value": state.value,
        "placeholder": jsString(p["placeholder"] ?? ""),
        "inputType": type,
        "multiline": false,
        "maxLength": num(p["maxLength"] ?? p["maxlength"]),
        "enabled": !disabled,
        "readOnly": p.b("readOnly") || p["readonly"] != nil,
        "autofocus": attrOn(p, "autofocus", "autofocus"),
    ]
    if let v = num(p["min"]) { view["min"] = v }
    if let v = num(p["max"]) { view["max"] = v }
    view["suggestions"] = datalistOptions(ctx, optString(p["list"]))
    view["variant"] = "outline"
    view["textStyle"] = ts.toSpec()
    view["hintStyle"] = ts.with { $0.color = DARK.hint }.toSpec()
    view["contentPadding"] = [10.0, 10.0, 10.0, 10.0]
    view["colors"] = jo([
        "text": textColor,
        "hint": DARK.hint,
        "fill": s?.backgroundColor ?? DARK.fill,
        "border": DARK.border,
        "focusedBorder": DARK.focus,
        "cursor": DARK.focus,
        "radius": 8.0,
    ])
    let result = w(
        "control",
        [
            "kind": "textInput",
            "focusId": idOf(node),
            "lines": 1.0,
            "padding": [10.0, 10.0, 10.0, 10.0],
            "lineHeight": fontSize * 1.3,
            "view": view,
            "onEvent": { (e: ViewEvent) in
                if e.type == "input" || e.type == "change" {
                    state.value = flattenOptional(e.value) == nil ? "" : jsString(e.value)
                    dispatchEvent(ctx, "input", jo(["value": state.value]))
                } else if e.type == "submit" {
                    dispatchEvent(ctx, "submit")
                    if let formId = ctx.formId { ctx.engine.submitForm(formId) }
                } else if e.type == "focus" || e.type == "blur" {
                    dispatchEvent(ctx, e.type)
                    if e.type == "blur" && node.events?["change"] != nil { dispatchEvent(ctx, "change", jo(["value": state.value])) }
                }
            },
        ]
    )
    return applyStyle(result, s, ApplyStyleOptions(), ctx)
}

private func htmlTextarea(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let p = node.props
    let state = ctx.engine.stateFor(ctx.elementId) { StringState(jsString(p["value"] ?? p["text"] ?? "")) }
    ctx.engine.registerFormField(ctx.formId, optString(p["name"])) { state.value }
    let lines = max(1, num(p["rows"]) ?? 5)
    let ts = TextStyle(color: node.style?.color ?? M3.onSurface, fontSize: 16, letterSpacing: 0.5, height: 1.5)
    let result = w(
        "control",
        [
            "kind": "textInput",
            "focusId": idOf(node),
            "lines": lines,
            "padding": [16.0, 12.0, 16.0, 12.0],
            "lineHeight": 24.0,
            "view": jo([
                "value": state.value,
                "placeholder": jsString(p["placeholder"] ?? ""),
                "inputType": "multiline",
                "multiline": true,
                "maxLines": lines,
                "minLines": lines,
                "enabled": p["disabled"] == nil,
                "readOnly": p.b("readOnly") || p["readonly"] != nil,
                "variant": "outline",
                "textStyle": ts.toSpec(),
                "hintStyle": ts.with { $0.color = M3.onSurfaceVariant }.toSpec(),
                "contentPadding": [16.0, 12.0, 16.0, 12.0],
                "colors": jo([
                    "text": ts.color ?? M3.onSurface,
                    "hint": M3.onSurfaceVariant,
                    "border": M3.outline,
                    "focusedBorder": M3.primary,
                    "cursor": M3.primary,
                    "fill": nil,
                    "radius": 4.0,
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
    return applyStyle(result, node.style, ApplyStyleOptions(), ctx)
}

/** A select option: `{value, label}` plus `group` / `disabled` when known. */
private func selectOptions(_ node: ElpianNode) -> [JSONObject] {
    var out: [JSONObject] = []
    if let raw = asArray(node.props["options"]) {
        for o in raw {
            if let m = asMap(o) {
                let v = jsString(m["value"] ?? m["label"] ?? "")
                out.append(jo(["value": v, "label": jsString(m["label"] ?? v), "group": m["group"], "disabled": m.b("disabled")]))
            } else if let o = flattenOptional(o) {
                out.append(jo(["value": jsString(o), "label": jsString(o)]))
            }
        }
    }
    if out.isEmpty {
        func visit(_ n: ElpianNode, _ group: String?) {
            for c in n.children {
                if c.type == "option" {
                    let v = jsString(c.props["value"] ?? c.props["text"] ?? "")
                    out.append(jo([
                        "value": v,
                        "label": jsString(c.props["text"] ?? c.props["label"] ?? v),
                        "group": group,
                        "disabled": c.props["disabled"] != nil && !c.props.isFalse("disabled"),
                    ]))
                } else if c.type == "optgroup" {
                    visit(c, jsString(c.props["label"] ?? ""))
                }
            }
        }
        visit(node, nil)
    }
    return out
}

private func htmlSelect(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let options = selectOptions(node)
    let selectedChild = node.children.first { $0.type == "option" && attrOn($0.props, "selected", "selected") }
    let incoming = optString(node.props["value"])
    let state = ctx.engine.stateFor(ctx.elementId) {
        SelectState(incoming ?? selectedChild.map { jsString($0.props["value"] ?? $0.props["text"] ?? "") }, incoming)
    }
    // didUpdateWidget: an incoming prop value change wins.
    if let inc = incoming, inc != state.lastProp {
        state.value = inc
        state.lastProp = inc
    }
    let value: String? = options.contains { ($0["value"] as? String) == state.value } ? state.value : options.first?["value"] as? String
    ctx.engine.registerFormField(ctx.formId, optString(node.props["name"])) { value }
    let s = node.style
    let ts = TextStyle(color: s?.color ?? DARK.text, fontSize: s?.fontSize ?? 13, height: 1.3)
    var result = w(
        "control",
        [
            "kind": "select",
            "focusId": idOf(node),
            "padding": [0.0, 10.0, 0.0, 10.0],
            "view": jo([
                "value": value,
                "options": options,
                "enabled": node.props["disabled"] == nil,
                "textStyle": ts.toSpec(),
                "colors": jo(["text": ts.color ?? DARK.text, "fill": DARK.fill, "icon": DARK.focus, "menu": DARK.fill]),
            ]),
            "onEvent": { (e: ViewEvent) in
                if e.type == "change", flattenOptional(e.value) != nil {
                    state.value = jsString(e.value)
                    dispatchEvent(ctx, "change", jo(["value": state.value]))
                    ctx.engine.host.invalidate?()
                }
            },
        ]
    )
    result = container(
        child: result,
        padding: EdgeInsets.symmetric(vertical: 0, horizontal: 10),
        decoration: BoxDecoration(color: DARK.fill, border: Border.all(BorderSide(width: 1, color: DARK.border, style: .solid)), radius: BorderRadius.all(8))
    )
    return applyStyle(result, s, ApplyStyleOptions(), ctx)
}

private func htmlButtonLike(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext, _ type: String? = nil) -> W {
    let s = node.style
    let label = jsString(node.props["text"] ?? "Button")
    let fg = s?.color ?? (s?.backgroundColor != nil ? Colors.white : M3.primary)
    let child = children.first ?? text(label, TextStyle(color: fg))
    let kind = type ?? jsString(node.props["type"] ?? (ctx.formId != nil ? "submit" : "button")).lowercased()
    let disabled = attrOn(node.props, "disabled", "disabled")
    let press = buttonPressed(ctx)
    let onPressed: (() -> Void)? = disabled ? nil : {
        press()
        if kind == "submit", let formId = ctx.formId { ctx.engine.submitForm(formId) }
        if kind == "reset", ctx.formId != nil { dispatchEvent(ctx, "reset") }
    }
    return buttonOuter(materialButton(ButtonOptions(child: child, style: s, onPressed: onPressed, semanticsLabel: label)), s)
}

// ============================================================================
// Media
// ============================================================================

private func mediaSource(_ node: ElpianNode, _ ctx: BuildContext) -> String {
    let direct = node.props["src"]
    if jsTruthy(direct) { return ctx.engine.resolveUrl(jsString(direct)) }
    for c in node.children where c.type == "source" && jsTruthy(c.props["src"]) { return ctx.engine.resolveUrl(jsString(c.props["src"])) }
    return ""
}

private let MEDIA_EVENTS: Set<String> = ["play", "pause", "ended", "timeupdate", "load", "error", "volumechange", "seeked"]

private func mediaElement(_ kind: String) -> WidgetBuilder {
    return { node, _, ctx in
        let p = node.props
        let src = mediaSource(node, ctx)
        let tracks: [JSONObject] = node.children
            .filter { $0.type == "track" && jsTruthy($0.props["src"]) }
            .map { c in
                jo([
                    "src": ctx.engine.resolveUrl(jsString(c.props["src"])),
                    "kind": jsString(c.props["kind"] ?? "subtitles"),
                    "srclang": optString(c.props["srclang"]),
                    "label": optString(c.props["label"]),
                    "default": attrOn(c.props, "default", "default"),
                ])
            }
        if src.isEmpty {
            let msg = kind == "video" ? "video src is required" : "audio src is required"
            let placeholder = kind == "video"
                ? decorated(BoxDecoration(color: Colors.black), center(text(msg, TextStyle(color: Colors.white70))))
                : row([padding(EdgeInsets.all(16), icon("audiotrack", 24)), text(msg)], ["mainAxisSize": "min"])
            return applyStyle(placeholder, node.style, ApplyStyleOptions(), ctx)
        }
        let result = w(
            "media",
            [
                "kind": kind,
                "src": src,
                "autoplay": attrOn(p, "autoplay", "autoplay"),
                "loop": attrOn(p, "loop", "loop"),
                "muted": attrOn(p, "muted", "muted"),
                "controls": !p.isFalse("controls"),
                "poster": jsTruthy(p["poster"]) ? ctx.engine.resolveUrl(jsString(p["poster"])) : nil,
                "tracks": tracks.isEmpty ? nil : tracks,
                "width": kind == "video" ? (node.style?.width ?? num(p["width"])) : node.style?.width,
                "height": kind == "video" ? (node.style?.height ?? num(p["height"])) : nil,
                "fit": node.style?.objectFit?.rawValue ?? "contain",
                "onEvent": { (e: ViewEvent) in
                    if MEDIA_EVENTS.contains(e.type) {
                        dispatchEvent(ctx, e.type == "load" ? "loadedmetadata" : e.type, jo(["value": e.value]))
                        if e.type == "load" { dispatchEvent(ctx, "load", jo(["value": e.value])) }
                    }
                },
            ]
        )
        return applyStyle(result, node.style, ApplyStyleOptions(), ctx)
    }
}

private let IMAGE_EXT = JSRegex("\\.(png|jpe?g|gif|webp|svg|bmp|avif)$")
private let VIDEO_EXT = JSRegex("\\.(mp4|webm|mov|m3u8|mkv|ogv)$")
private let AUDIO_EXT = JSRegex("\\.(mp3|wav|ogg|aac|m4a|flac|opus)$")

private func looksLike(_ kind: String, _ type: String, _ src: String) -> Bool {
    let s = src.lowercased().components(separatedBy: "?")[0]
    switch kind {
    case "image": return type.hasPrefix("image/") || IMAGE_EXT.test(s)
    case "video": return type.hasPrefix("video/") || VIDEO_EXT.test(s)
    default: return type.hasPrefix("audio/") || AUDIO_EXT.test(s)
    }
}

private func webContent(_ node: ElpianNode, _ ctx: BuildContext, _ src: String, _ label: String) -> W {
    let p = node.props
    if src.isEmpty && !jsTruthy(p["srcdoc"]) {
        return applyStyle(center(text("\(label) source is required")), node.style, ApplyStyleOptions(), ctx)
    }
    let result = w(
        "web",
        [
            "src": src.isEmpty ? nil : ctx.engine.resolveUrl(src),
            "html": jsTruthy(p["srcdoc"]) ? jsString(p["srcdoc"]) : nil,
            "width": node.style?.width ?? num(p["width"]),
            "height": node.style?.height ?? num(p["height"]),
            "onEvent": { (e: ViewEvent) in
                if e.type == "load" || e.type == "error" { dispatchEvent(ctx, e.type, jo(["value": e.value])) }
            },
        ]
    )
    return applyStyle(result, node.style, ApplyStyleOptions(), ctx)
}

private func embedTyped(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext, _ src: String) -> W {
    let type = jsString(node.props["type"] ?? "").lowercased()
    let props = node.props.copy()
    props["src"] = src
    let withSrc = ElpianNode(type: node.type, props: props, children: node.children, key: node.key, events: node.events, style: node.style)
    if looksLike("image", type, src) { return htmlImg(withSrc, children, ctx) }
    if looksLike("video", type, src) { return mediaElement("video")(withSrc, children, ctx) }
    if looksLike("audio", type, src) { return mediaElement("audio")(withSrc, children, ctx) }
    return webContent(withSrc, ctx, src, node.type)
}

private func htmlImg(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let rawSrc = jsString(node.props["src"] ?? "")
    let src = ctx.engine.resolveUrl(chooseSrcset(node, rawSrc))
    let s = node.style
    let img = w(
        "image",
        [
            "src": src,
            "fit": s?.objectFit?.rawValue ?? (s?.width != nil && s?.height != nil ? "fill" : "contain"),
            "alignment": s?.objectPosition,
            "width": s?.width ?? num(node.props["width"]),
            "height": s?.height ?? num(node.props["height"]),
            "alt": optString(node.props["alt"]),
            "onEvent": { (e: ViewEvent) in
                if e.type == "load" || e.type == "error" { dispatchEvent(ctx, e.type, jo(["value": e.value])) }
            },
        ]
    )
    var result = img
    var usemap = node.props["usemap"] as? String
    if let u = usemap, u.hasPrefix("#") { usemap = String(u.dropFirst()) }
    let areas: [ElpianNode]? = (usemap?.isEmpty ?? true) ? nil : ctx.engine.imageMaps[usemap!]
    if let areas = areas, !areas.isEmpty {
        var specs: [AreaSpec] = []
        var regions: [W] = []
        for (i, area) in areas.enumerated() {
            let shape = jsString(area.props["shape"] ?? "rect").lowercased()
            let coords = jsString(area.props["coords"] ?? "").components(separatedBy: ",").compactMap { parseFloatPrefix($0) }.filter { $0.isFinite }
            let specShape: String
            switch shape {
            case "circ", "circle": specShape = "circle"
            case "poly", "polygon": specShape = "poly"
            case "default": specShape = "default"
            default: specShape = "rect"
            }
            let spec = AreaSpec(shape: specShape, coords: coords)
            specs.append(spec)
            let href = optString(area.props["href"])
            let areaId = area.key ?? "\(ctx.elementId)/area\(i)"
            regions.append(
                w(
                    "gesture",
                    [
                        "gestures": ["tap"],
                        "cursor": "pointer",
                        "tooltip": area.props["title"] ?? area.props["alt"],
                        "semanticsLabel": area.props["alt"],
                        "onEvent": { (e: ViewEvent, ro: RenderObject) in
                            if e.type == "tap" {
                                // Precise hit test in natural image pixels.
                                let map = ro.parent as? RenderImageMap
                                let sx = map?.scale.x ?? 1
                                let sy = map?.scale.y ?? 1
                                let px = ((e.localX ?? 0) + ro.offset.x) / sx
                                let py = ((e.localY ?? 0) + ro.offset.y) / sy
                                if areaContains(spec, px, py) {
                                    if area.events != nil {
                                        ctx.engine.services.events.registerNode(areaId, area, ctx.elementId)
                                        var tap = e
                                        tap.type = "tap"
                                        ctx.engine.handleGesture(areaId, area, tap)
                                    }
                                    if let h = href { openLink(ctx, h, nil) }
                                }
                            }
                        },
                    ]
                )
            )
        }
        result = w("imageMap", ["src": src, "areas": specs], [img] + regions)
    }
    return applyStyle(result, s, ApplyStyleOptions(), ctx)
}

private let WS = JSRegex("\\s+")

/** `srcset` with `w` descriptors: the smallest candidate covering the viewport × dpr. */
private func chooseSrcset(_ node: ElpianNode, _ fallback: String) -> String {
    guard let srcset = (node.props["srcset"] ?? node.props["srcSet"]) as? String, jsTrim(srcset) != "" else { return fallback }
    let dpr = CssEnvironment.devicePixelRatio
    let target = CssEnvironment.viewportWidth * dpr
    struct Candidate {
        let url: String
        let w: Double?
        let x: Double?
    }
    let candidates: [Candidate] = srcset.components(separatedBy: ",")
        .map { WS.split(jsTrim($0)) }
        .filter { !$0[0].isEmpty }
        .map { p in
            let d = p.count > 1 ? p[1] : "1x"
            return Candidate(
                url: p[0],
                w: d.hasSuffix("w") ? parseFloatPrefix(d) ?? .nan : nil,
                x: d.hasSuffix("x") ? parseFloatPrefix(d) ?? .nan : nil
            )
        }
    // Stable sorts, as Array.prototype.sort is.
    let byWidth = candidates.enumerated().filter { $0.element.w != nil }.sorted { a, b in
        a.element.w! != b.element.w! ? a.element.w! < b.element.w! : a.offset < b.offset
    }.map { $0.element }
    if !byWidth.isEmpty { return (byWidth.first { $0.w! >= target } ?? byWidth.last!).url }
    let byDensity = candidates.enumerated().filter { $0.element.x != nil }.sorted { a, b in
        a.element.x! != b.element.x! ? a.element.x! < b.element.x! : a.offset < b.offset
    }.map { $0.element }
    if !byDensity.isEmpty { return (byDensity.first { $0.x! >= dpr } ?? byDensity.last!).url }
    return fallback
}

// ============================================================================
// Tables
// ============================================================================

private func tableCell(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext, _ header: Bool) -> W {
    let t = node.text
    let base = header ? TextStyle(fontWeight: 700) : TextStyle()
    var child: W
    if children.count == 1 {
        child = children[0]
    } else if children.count > 1 {
        child = richText(node, mergeTextStyle(base, createTextStyle(node.style)), ctx)
            ?? column(children, ["crossAxisAlignment": "start", "mainAxisSize": "min"])
    } else {
        child = text(t, mergeTextStyle(base, createTextStyle(node.style)), textOptionsFromStyle(node.style))
    }
    if header && node.style?.textAlign == nil { child = center(child) }
    let style = withDefaults(node.style, css { $0.padding = EdgeInsets.all(8) })
    let boxed = applyStyle(child, style, ApplyStyleOptions(), ctx)
    let va = jsString(node.style?.verticalAlign ?? node.props["valign"] ?? "middle")
    return w(
        "tableCell",
        [
            "colSpan": num(node.props["colspan"] ?? node.props["colSpan"]) ?? 1,
            "rowSpan": num(node.props["rowspan"] ?? node.props["rowSpan"]) ?? 1,
            "verticalAlign": va == "top" ? "top" : va == "bottom" ? "bottom" : "middle",
            "width": num(node.props["width"]),
        ],
        child: boxed
    )
}

private func tableRow(_ node: ElpianNode, _ children: [W]) -> W {
    let cells = children.map { $0.t == "tableCell" ? $0 : w("tableCell", Props(), child: $0) }
    return w("tableRow", ["decorated": node.style?.backgroundColor != nil, "background": node.style?.backgroundColor], cells)
}

private func htmlTable(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    var rows: [W] = []
    var caption: W?
    for (i, child) in node.children.enumerated() {
        let wc = children[i]
        switch child.type {
        case "caption": caption = wc
        // Row groups are flattened; their rows were lowered as the group's children.
        case "thead", "tbody", "tfoot": rows.append(contentsOf: wc.c ?? [])
        case "tr": rows.append(wc)
        // Column hints are read through cell widths.
        case "colgroup", "col": break
        default: rows.append(w("tableRow", Props(), [w("tableCell", Props(), child: wc)]))
        }
    }
    let collapse = node.style?.borderCollapse == "collapse"
    let table = w(
        "table",
        [
            "collapse": collapse,
            "borderSpacing": collapse ? 0 : (node.style?.borderSpacing ?? num(node.props["cellspacing"]) ?? 2),
            "caption": "top",
            "fullWidth": node.style?.width != nil || node.style?.widthFactor != nil,
        ],
        caption.map { [$0] + rows } ?? rows
    )
    // Flutter's Table(border: TableBorder.all()) draws grid lines; a bordered table keeps them.
    let bordered = node.props["border"] != nil && !jsStrictEquals(node.props["border"], "0")
    let result = bordered ? decorated(BoxDecoration(border: Border.all(BorderSide(width: 1, color: Colors.black, style: .solid))), table) : table
    return applyStyle(result, node.style, ApplyStyleOptions(), ctx)
}

// ============================================================================
// Lists, details, dialog, misc
// ============================================================================

private func listItem(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext, _ marker: String) -> W {
    let ts = createTextStyle(node.style)
    let content: W
    if let rich = richText(node, ts ?? TextStyle(), ctx) {
        content = rich
    } else if children.count == 1 {
        content = children[0]
    } else if children.count > 1 {
        content = column(children, ["crossAxisAlignment": "start", "mainAxisSize": "min"])
    } else {
        content = text(node.text, ts)
    }
    let result = w("flex", ["direction": "row", "crossAxisAlignment": "start", "mainAxisSize": "max"], [text(marker, ts), expanded(content)])
    return applyStyle(result, node.style, ApplyStyleOptions(), ctx)
}

private func detailsElement(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let state = ctx.engine.stateFor(ctx.elementId) { OpenState(attrOn(node.props, "open", "open")) }
    let summaryIndex = node.children.firstIndex { $0.type == "summary" } ?? -1
    let summary = summaryIndex >= 0 ? children[summaryIndex] : text("Details", TextStyle(fontWeight: 600))
    let body = children.enumerated().filter { $0.offset != summaryIndex }.map { $0.element }
    let header = w(
        "gesture",
        [
            "gestures": ["tap"],
            "ripple": scaleAlpha(M3.onSurface, 0.08),
            "cursor": "pointer",
            "role": "button",
            "onEvent": { (e: ViewEvent) in
                if e.type == "tap" {
                    state.open = !state.open
                    dispatchEvent(ctx, "toggle", jo(["data": jo(["open": state.open])]))
                    ctx.engine.host.invalidate?()
                }
            },
        ],
        child: padding(
            EdgeInsets.symmetric(vertical: 8, horizontal: 0),
            row(
                [
                    expanded(summary),
                    w(
                        "animatedTransform",
                        ["turns": state.open ? 0.5 : 0.0, "duration": 200.0, "curve": "easeInOut", "alignment": Alignment(x: 0, y: 0)],
                        child: icon("expand_more", 24)
                    ),
                ],
                ["mainAxisSize": "max"]
            )
        )
    )
    let content = w(
        "animatedSize",
        ["duration": 200.0, "curve": "easeInOut", "alignment": Alignment(x: -1, y: -1)],
        child: state.open ? column(body, ["crossAxisAlignment": "start", "mainAxisSize": "min"]) : SHRINK
    )
    return applyStyle(column([header, content], ["crossAxisAlignment": "stretch", "mainAxisSize": "min"]), node.style, ApplyStyleOptions(), ctx)
}

private func dialogElement(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    if node.props.isFalse("open") || node.props.s("open") == "false" { return SHRINK }
    let content = padding(EdgeInsets.all(24), column(children, ["crossAxisAlignment": "start", "mainAxisSize": "min"]))
    let card = decorated(
        BoxDecoration(
            color: node.style?.backgroundColor ?? 0xffece6f0,
            radius: node.style?.borderRadius ?? BorderRadius.all(28),
            shadows: [
                BoxShadow(color: 0x33000000, dx: 0, dy: 3, blur: 5, spread: -1),
                BoxShadow(color: 0x24000000, dx: 0, dy: 6, blur: 10, spread: 0),
                BoxShadow(color: 0x1f000000, dx: 0, dy: 1, blur: 18, spread: 0),
            ]
        ),
        w("constrained", ["minWidth": 280.0, "maxWidth": 560.0], child: content)
    )
    let inset = padding(EdgeInsets(top: 24, right: 40, bottom: 24, left: 40), card)
    return applyStyle(center(inset), withDefaults(node.style, CSSStyle()), ApplyStyleOptions(), ctx)
}

private func progressElement(_ node: ElpianNode, _ meter: Bool) -> W {
    let value = num(node.props["value"])
    let minV = num(node.props["min"]) ?? 0
    let maxV = num(node.props["max"]) ?? 1
    func orOne(_ v: Double) -> Double { v == 0 || v.isNaN ? 1 : v }
    let fraction: Double? = meter ? ((value ?? 0.5) - minV) / orOne(maxV - minV) : value.map { $0 / orOne(maxV) }
    var indicator: Color = node.style?.color ?? (meter ? Colors.green : M3.primary)
    if meter {
        let low = num(node.props["low"])
        let high = num(node.props["high"])
        let v = value ?? 0.5
        if (low != nil && v < low!) || (high != nil && v > high!) { indicator = node.style?.color ?? Colors.amber }
    }
    return w(
        "control",
        [
            "kind": "progress",
            "focusId": idOf(node),
            "width": node.style?.width,
            "view": jo([
                "variant": "linear",
                "value": fraction.map { max(0, min(1, $0)) },
                "strokeWidth": node.style?.height ?? 4,
                "colors": jo(["indicator": indicator, "track": node.style?.backgroundColor ?? 0xffeeeeee as Color]),
            ]),
        ]
    )
}

/** `<picture>`: the first `<source>` whose media matches, applied to the inner `<img>`. */
private func pictureElement(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let source = node.children.first { c in
        c.type == "source" &&
            (jsTruthy(c.props["srcset"]) || jsTruthy(c.props["srcSet"]) || jsTruthy(c.props["src"])) &&
            (!jsTruthy(c.props["media"]) || mediaMatches(jsString(c.props["media"]), CssEnvironment.viewportWidth, CssEnvironment.viewportHeight))
    }
    if let imgIndex = node.children.firstIndex(where: { $0.type == "img" }) {
        let img = node.children[imgIndex]
        if let source = source {
            let srcset = jsString(source.props["srcset"] ?? source.props["srcSet"] ?? source.props["src"])
            let firstUrl = WS.split(jsTrim(srcset.components(separatedBy: ",")[0]))[0]
            let props = img.props.copy()
            props["src"] = firstUrl
            props["srcset"] = srcset.contains(",") ? srcset : img.props["srcset"]
            let swapped = ElpianNode(type: img.type, props: props, children: img.children, key: img.key, events: img.events, style: img.style)
            return applyStyle(htmlImg(swapped, [], ctx.with(elementId: "\(ctx.elementId)/img")), node.style, ApplyStyleOptions(), ctx)
        }
        return applyStyle(children[imgIndex], node.style, ApplyStyleOptions(), ctx)
    }
    let fallback = children.first { $0.t != "constrained" } ?? children.first ?? SHRINK
    return applyStyle(fallback, node.style, ApplyStyleOptions(), ctx)
}

private let hidden: WidgetBuilder = { _, _, _ in SHRINK }

private let URI_COMPONENT_ALLOWED: CharacterSet = {
    var set = CharacterSet()
    set.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
    return set
}()

/** JavaScript `encodeURIComponent`. */
public func encodeURIComponent(_ s: String) -> String {
    s.addingPercentEncoding(withAllowedCharacters: URI_COMPONENT_ALLOWED) ?? s
}

private func noneSide() -> BorderSide { BorderSide(width: 0, color: Colors.black, style: .none) }

private func listItemWrap(_ child: W, _ marker: String) -> W {
    w("flex", ["direction": "row", "crossAxisAlignment": "start", "mainAxisSize": "max"], [text(marker), expanded(child)])
}

private func simpleText(_ node: ElpianNode, _ ctx: BuildContext) -> W {
    applyStyle(text(node.text, createTextStyle(node.style)), node.style, ApplyStyleOptions(), ctx)
}

// ============================================================================
// Builders with bodies
// ============================================================================

private func htmlSpan(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let s = node.style
    let ts = createTextStyle(s) ?? TextStyle()
    let opts = JSONObject()
    if let o = s?.textOverflow { opts["overflow"] = o.rawValue }
    if s?.whiteSpace == "nowrap" {
        opts["maxLines"] = 1.0
        opts["softWrap"] = false
    }
    if children.isEmpty { return applyStyle(text(node.text, ts, opts), s, ApplyStyleOptions(), ctx) }
    if let rich = richText(node, ts, ctx, opts) { return applyStyle(rich, s, ApplyStyleOptions(), ctx) }
    var parts: [W] = []
    let t = node.text
    if !t.isEmpty { parts.append(text(t, ts, opts)) }
    parts.append(contentsOf: children)
    return applyStyle(w("wrap", ["direction": "horizontal", "crossAxisAlignment": "center"], parts), s, ApplyStyleOptions(layoutHandled: true), ctx)
}

private func htmlAnchor(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let href = jsString(node.props["href"] ?? "#")
    let style = withDefaults(node.style, css { $0.color = Colors.blue; $0.textDecoration = underline() })
    let ts = createTextStyle(style) ?? TextStyle()
    let content: W
    if let rich = richText(node, ts, ctx) {
        content = rich
    } else if !children.isEmpty {
        var parts: [W] = []
        let t = node.text
        if !t.isEmpty { parts.append(text(t, ts)) }
        parts.append(contentsOf: children)
        content = w("wrap", ["direction": "horizontal", "crossAxisAlignment": "center"], parts)
    } else {
        content = text(node.text, ts)
    }
    let link = w(
        "gesture",
        [
            "gestures": ["tap"],
            "cursor": "pointer",
            "role": "link",
            "semanticsLabel": node.props["title"],
            "onEvent": { (e: ViewEvent) in
                if e.type == "tap" {
                    let target = jsString(node.props["target"] ?? "")
                    if target == "_blank" && HTTP_LINK.test(href) {
                        ctx.engine.host.openUrl?(href)
                    } else {
                        openLink(ctx, href, node)
                    }
                }
            },
        ],
        child: content
    )
    return applyStyle(link, style, ApplyStyleOptions(), ctx)
}

private func htmlLabel(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let ts = TextStyle(fontWeight: 500).merge(createTextStyle(node.style))
    var result: W
    if let rich = richText(node, ts, ctx) {
        result = rich
    } else if !children.isEmpty {
        result = row([text(node.text, ts)] + children, ["mainAxisSize": "min"])
    } else {
        result = text(node.text, ts)
    }
    let forId = node.props["for"] ?? node.props["htmlFor"]
    if jsTruthy(forId) {
        result = w("gesture", ["gestures": ["tap"], "cursor": "pointer", "onEvent": { (_: ViewEvent) in ctx.engine.focusElement(jsString(forId)) }], child: result)
    }
    return applyStyle(result, node.style, ApplyStyleOptions(), ctx)
}

private func htmlObject(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let data = jsString(node.props["data"] ?? "")
    // `<param>` children become query parameters of the embedded content.
    let params = node.children.filter { $0.type == "param" && jsTruthy($0.props["name"]) }
    var src = data
    if !params.isEmpty && !data.isEmpty && !looksLike("image", jsString(node.props["type"] ?? ""), data) {
        let q = params.map { p in "\(encodeURIComponent(jsString(p.props["name"])))=\(encodeURIComponent(jsString(p.props["value"] ?? "")))" }.joined(separator: "&")
        src = data + (data.contains("?") ? "&" : "?") + q
    }
    return embedTyped(node, children, ctx, src)
}

private func htmlCanvas(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let raw = asArray(node.props["commands"]) ?? []
    let commands = raw.filter { isMap($0) }.map { normalizeCommand(commandFromJson($0)) }
    if jsTruthy(node.props["contextId"]) {
        return applyStyle(cachedCanvas(node, ctx), node.style, ApplyStyleOptions(), ctx)
    }
    let result = w(
        "canvas",
        [
            "width": num(node.props["width"]) ?? node.style?.width,
            "height": num(node.props["height"]) ?? node.style?.height,
            "background": parseColor(node.props["backgroundColor"]) ?? node.style?.backgroundColor,
            "commands": commands,
            "onEvent": { (e: ViewEvent) in ctx.engine.handleGesture(ctx.elementId, node, e) },
        ]
    )
    return applyStyle(result, node.style, ApplyStyleOptions(), ctx)
}

private func htmlOl(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let start = num(node.props["start"]) ?? 1
    let items = children.enumerated().map { i, c -> W in
        let li = node.children[i]
        let marker = "\(jsString(start + Double(i))). "
        // Flutter renders `ol` items as Row(Text('n. '), Expanded(li)); an li's own bullet is replaced.
        return li.type == "li" ? listItem(li, c.c ?? [], ctx.with(elementId: "\(ctx.elementId)/\(i)"), marker) : listItemWrap(c, marker)
    }
    return applyStyle(column(items, ["crossAxisAlignment": "start", "mainAxisSize": "max"]), node.style, ApplyStyleOptions(), ctx)
}

private func htmlPre(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let style = node.style ?? monoStyle(0xfff5f5f5, EdgeInsets.all(8))
    let ts = createTextStyle(style) ?? TextStyle()
    let body = w("scroll", ["axis": "horizontal"], child: text(node.text, TextStyle(fontFamily: "monospace").merge(ts), ["softWrap": false]))
    return applyStyle(body, style, ApplyStyleOptions(), ctx)
}

private func htmlBlockquote(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let child: W
    if children.count == 1 {
        child = children[0]
    } else if children.count > 1 {
        child = column(children, ["crossAxisAlignment": "start", "mainAxisSize": "min"])
    } else {
        child = text(node.text, createTextStyle(node.style))
    }
    let box = container(
        child: child,
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(border: Border(top: noneSide(), right: noneSide(), bottom: noneSide(), left: BorderSide(width: 4, color: Colors.grey, style: .solid)))
    )
    let style = node.style ?? css { s in
        s.padding = EdgeInsets.all(16)
        s.margin = EdgeInsets.symmetric(vertical: 8, horizontal: 0)
        s.borderColor = Colors.grey
        s.borderWidth = 4
    }
    let outer = style.copy()
    outer.padding = nil
    outer.border = nil
    outer.borderColor = nil
    outer.borderWidth = nil
    return applyStyle(box, outer, ApplyStyleOptions(), ctx)
}

private func htmlNav(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let s = node.style
    let result = w(
        "flex",
        [
            "direction": "row",
            "mainAxisAlignment": mainOf(s?.justifyContent ?? "space-around"),
            "crossAxisAlignment": crossOf(s?.alignItems),
            "mainAxisSize": "max",
            "gap": s?.gap ?? 0,
            "shrink": true,
        ],
        children
    )
    return applyStyle(result, s, ApplyStyleOptions(layoutHandled: true), ctx)
}

// ============================================================================
// Registry
// ============================================================================

/** The HTML element builders, in registration order. */
public let htmlWidgets: [(String, WidgetBuilder)] = [
    ("div", { node, children, ctx in htmlDiv(node, children, ctx) }),
    ("section", { node, children, ctx in htmlDiv(node, children, ctx) }),
    ("article", { node, children, ctx in htmlDiv(node, children, ctx) }),
    ("aside", { node, children, ctx in htmlDiv(node, children, ctx) }),
    ("main", { node, children, ctx in htmlDiv(node, children, ctx) }),
    ("header", { node, children, ctx in htmlDiv(node, children, ctx, fullWidth: true) }),
    ("footer", { node, children, ctx in htmlDiv(node, children, ctx, fullWidth: true) }),
    ("body", { node, children, ctx in htmlDiv(node, children, ctx, fullWidth: true) }),
    ("html", { node, children, ctx in htmlDiv(node, children, ctx, fullWidth: true) }),

    ("span", htmlSpan),

    ("p", { node, children, ctx in textWithChildren(node, children, ctx, css { $0.margin = EdgeInsets.symmetric(vertical: 8, horizontal: 0) }, "wrap") }),
    ("h1", heading(32, 16)),
    ("h2", heading(28, 14)),
    ("h3", heading(24, 12)),
    ("h4", heading(20, 10)),
    ("h5", heading(16, 8)),
    ("h6", heading(14, 6)),

    ("a", htmlAnchor),

    ("button", { node, children, ctx in htmlButtonLike(node, children, ctx) }),
    ("input", htmlInput),
    ("textarea", htmlTextarea),
    ("select", htmlSelect),
    ("option", { node, _, _ in text(jsString(node.props["text"] ?? node.props["label"] ?? "")) }),
    ("optgroup", { node, children, ctx in
        let label = jsString(node.props["label"] ?? "")
        return applyStyle(column([text(label, TextStyle(fontWeight: 700))] + children, ["crossAxisAlignment": "start", "mainAxisSize": "max"]), node.style, ApplyStyleOptions(), ctx)
    }),
    ("datalist", hidden),
    ("label", htmlLabel),
    ("form", { node, children, ctx in
        applyStyle(column(children, ["crossAxisAlignment": "start", "mainAxisSize": "max"]), node.style, ApplyStyleOptions(), ctx)
    }),
    ("fieldset", { node, children, ctx in
        let box = container(
            child: column(children, ["crossAxisAlignment": "start", "mainAxisSize": "max"]),
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(border: Border.all(BorderSide(width: 1, color: Colors.grey, style: .solid)), radius: BorderRadius.all(4))
        )
        return applyStyle(box, node.style, ApplyStyleOptions(), ctx)
    }),
    ("legend", { node, _, ctx in applyStyle(text(node.text, TextStyle(fontWeight: 700)), node.style, ApplyStyleOptions(), ctx) }),
    ("output", { node, _, ctx in
        let box = container(
            child: text(node.text, createTextStyle(node.style)),
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(border: Border.all(BorderSide(width: 1, color: Colors.grey, style: .solid)), radius: BorderRadius.all(4))
        )
        return applyStyle(box, node.style, ApplyStyleOptions(), ctx)
    }),

    ("img", htmlImg),
    ("picture", pictureElement),
    ("source", hidden),
    ("track", hidden),
    ("param", hidden),
    ("map", hidden),
    ("area", hidden),
    ("video", mediaElement("video")),
    ("audio", mediaElement("audio")),
    ("iframe", { node, _, ctx in webContent(node, ctx, jsString(node.props["src"] ?? ""), "iframe") }),
    ("embed", { node, children, ctx in embedTyped(node, children, ctx, jsString(node.props["src"] ?? "")) }),
    ("object", htmlObject),
    ("canvas", htmlCanvas),

    ("ul", { node, children, ctx in
        let items = children.enumerated().map { i, c in node.children[i].type == "li" ? c : listItemWrap(c, "• ") }
        return applyStyle(column(items, ["crossAxisAlignment": "start", "mainAxisSize": "max"]), node.style, ApplyStyleOptions(), ctx)
    }),
    ("ol", htmlOl),
    ("li", { node, children, ctx in listItem(node, children, ctx, "• ") }),

    ("table", htmlTable),
    ("thead", { _, children, _ in w("proxy", Props(), children) }),
    ("tbody", { _, children, _ in w("proxy", Props(), children) }),
    ("tfoot", { _, children, _ in w("proxy", Props(), children) }),
    ("caption", { node, children, ctx in
        textWithChildren(node, children, ctx, css { $0.textAlign = "center"; $0.padding = EdgeInsets.symmetric(vertical: 4, horizontal: 0) }, "column")
    }),
    ("colgroup", hidden),
    ("col", hidden),
    ("tr", { node, children, _ in tableRow(node, children) }),
    ("td", { node, children, ctx in tableCell(node, children, ctx, false) }),
    ("th", { node, children, ctx in tableCell(node, children, ctx, true) }),

    ("strong", { node, _, ctx in textElement(node, ctx, css { $0.fontWeight = 700 }) }),
    ("b", { node, _, ctx in textElement(node, ctx, css { $0.fontWeight = 700 }) }),
    ("em", { node, _, ctx in textElement(node, ctx, css { $0.fontStyle = "italic" }) }),
    ("i", { node, _, ctx in textElement(node, ctx, css { $0.fontStyle = "italic" }) }),
    ("u", { node, _, ctx in textElement(node, ctx, css { $0.textDecoration = underline() }) }),
    ("s", { node, _, ctx in textElement(node, ctx, css { $0.textDecoration = lineThrough() }) }),
    ("q", { node, _, ctx in applyStyle(text("“\(node.text)”", createTextStyle(node.style)), node.style, ApplyStyleOptions(), ctx) }),
    ("code", { node, _, ctx in replaceDefaults(node, ctx, monoStyle(0xfff5f5f5, EdgeInsets.symmetric(vertical: 2, horizontal: 4)), INLINE_DEFAULTS["code"]!) }),
    ("pre", htmlPre),
    ("kbd", { node, _, ctx in
        replaceDefaults(node, ctx, monoStyle(0xffeeeeee, EdgeInsets.all(4)) { $0.borderRadius = BorderRadius.all(3) }, INLINE_DEFAULTS["kbd"]!)
    }),
    ("samp", { node, _, ctx in replaceDefaults(node, ctx, css { $0.fontFamily = "monospace" }, INLINE_DEFAULTS["samp"]!) }),
    ("var", { node, _, ctx in replaceDefaults(node, ctx, css { $0.fontStyle = "italic" }, INLINE_DEFAULTS["var"]!) }),
    ("cite", { node, _, ctx in replaceDefaults(node, ctx, css { $0.fontStyle = "italic" }, INLINE_DEFAULTS["cite"]!) }),
    ("mark", { node, _, ctx in
        replaceDefaults(node, ctx, css { $0.backgroundColor = 0xffffff00; $0.padding = EdgeInsets.symmetric(vertical: 2, horizontal: 4) }, INLINE_DEFAULTS["mark"]!)
    }),
    ("del", { node, _, ctx in replaceDefaults(node, ctx, css { $0.textDecoration = lineThrough() }, INLINE_DEFAULTS["del"]!) }),
    ("ins", { node, _, ctx in replaceDefaults(node, ctx, css { $0.textDecoration = underline() }, INLINE_DEFAULTS["ins"]!) }),
    ("small", { node, _, ctx in replaceDefaults(node, ctx, css { $0.fontSize = 12 }, INLINE_DEFAULTS["small"]!) }),
    ("sub", { node, _, _ in
        let style = node.style ?? css { $0.fontSize = 10 }
        let ts = mergeTextStyle(TextStyle(baselineShift: 3), createTextStyle(style))
        return w("padding", ["padding": EdgeInsets(top: 4, right: 0, bottom: 0, left: 0)], child: text(node.text, ts))
    }),
    ("sup", { node, _, _ in
        let style = node.style ?? css { $0.fontSize = 10 }
        let ts = mergeTextStyle(TextStyle(baselineShift: -6), createTextStyle(style))
        return w("padding", ["padding": EdgeInsets(top: 0, right: 0, bottom: 4, left: 0)], child: text(node.text, ts))
    }),
    ("abbr", { node, _, ctx in
        let result = w(
            "gesture",
            ["gestures": ["longpress", "hover"], "tooltip": jsString(node.props["title"] ?? ""), "onEvent": { (_: ViewEvent) in }],
            child: text(node.text, TextStyle(decoration: Decoration.underline).merge(createTextStyle(node.style)))
        )
        return applyStyle(result, node.style, ApplyStyleOptions(), ctx)
    }),
    ("time", { node, _, ctx in simpleText(node, ctx) }),
    ("data", { node, _, ctx in simpleText(node, ctx) }),
    ("blockquote", htmlBlockquote),
    ("hr", { node, _, ctx in
        applyStyle(widgetBuilder(flutterWidgets, "Divider")!(node.copy(style: .some(nil)), [], ctx), node.style, ApplyStyleOptions(), ctx)
    }),
    ("br", { _, _, _ in sizedBox(nil, 16) }),
    ("figure", { node, children, ctx in
        applyStyle(column(children, ["crossAxisAlignment": "start", "mainAxisSize": "min"]), node.style, ApplyStyleOptions(), ctx)
    }),
    ("figcaption", { node, _, ctx in
        replaceDefaults(node, ctx, css { $0.fontStyle = "italic"; $0.color = Colors.grey; $0.fontSize = 14 }, TextStyle(color: Colors.grey, fontSize: 14, italic: true))
    }),
    ("details", detailsElement),
    ("summary", { node, children, ctx in textWithChildren(node, children, ctx, css { $0.fontWeight = 700 }, "wrap") }),
    ("dialog", dialogElement),
    ("progress", { node, _, _ in progressElement(node, false) }),
    ("meter", { node, _, _ in progressElement(node, true) }),
    ("nav", htmlNav),
]
