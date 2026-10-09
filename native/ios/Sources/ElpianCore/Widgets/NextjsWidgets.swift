import Foundation

/**
 * Server-driven navigation widgets (widgets/nextjs.ts) — ports of
 * `NextjsBridge`'s `NextjsLink` (`next-link`) and `NextjsForm`
 * (`nextjs-form`) builders (flutter/lib/src/integrations/nextjs_bridge.dart).
 * Navigation and form submission go through the engine host
 * (`EngineHost.navigate` / `EngineHost.submitForm`), which the Next.js session
 * implements.
 */

private let GOLD: Color = 0xffd6b36a
private let FIELD_FILL: Color = 0xff0a1626
private let FIELD_BORDER: Color = 0xff1c3450
private let TEXT: Color = 0xfff7eedc
private let HINT: Color = 0xff6e8394
private let INK: Color = 0xff06122a
private let ERROR: Color = 0xffc0492f

// ============================================================================
// NextjsLink
// ============================================================================

private func linkChildStyle(_ child: ElpianNode) -> CSSStyle? {
    if let s = child.style { return s }
    if let inline = asMap(child.props["style"]) { return CSSParser.parse(inline) }
    return nil
}

private func withGaps(_ children: [W], _ gap: Double, _ horizontal: Bool) -> [W] {
    if gap <= 0 || children.count <= 1 { return children }
    var out: [W] = []
    for (i, c) in children.enumerated() {
        out.append(c)
        if i < children.count - 1 { out.append(sizedBox(horizontal ? gap : 0, horizontal ? 0 : gap)) }
    }
    return out
}

private func linkFlow(_ node: ElpianNode, _ flow: [W]) -> W {
    let s = node.style
    let isColumn = s?.flexDirection == "column" || s?.flexDirection == "column-reverse"
    let children = withGaps(flow, s?.gap ?? 0, !isColumn)
    let opts: JSONObject = [
        "mainAxisSize": "min",
        "mainAxisAlignment": mainAxisAlignmentFromCss(s?.justifyContent),
        "crossAxisAlignment": s?.alignItems == nil ? "center" : crossAxisAlignmentFromCss(s?.alignItems),
    ]
    return isColumn ? column(children, opts) : row(children, opts)
}

private func layoutLinkChildren(_ node: ElpianNode, _ children: [W]) -> W {
    let aligned = node.children.count == children.count
    var flow: [W] = []
    var overlays: [W] = []
    for (i, child) in children.enumerated() {
        let cs = aligned ? linkChildStyle(node.children[i]) : nil
        if let cs = cs, cs.position == "absolute" || cs.position == "fixed" {
            overlays.append(w("positioned", ["top": cs.top, "left": cs.left, "right": cs.right, "bottom": cs.bottom], child: child))
        } else {
            flow.append(child)
        }
    }
    let base = flow.isEmpty ? SHRINK : flow.count == 1 ? flow[0] : linkFlow(node, flow)
    if overlays.isEmpty { return base }
    // Clip.none: badges poke past the button's rounded corners.
    return w("stack", ["fit": "loose", "clip": false], [base] + overlays)
}

private func nextjsLink(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let href = flattenOptional(node.props["href"]).map { jsString($0) }
    let replace = node.props.b("replace")
    let label = flattenOptional(node.props["text"]).map { jsString($0) } ?? href ?? "Navigate"
    let s = node.style
    let ariaLabel = flattenOptional(node.props["ariaLabel"]).map { jsString($0) }
    var isButtonLike = false
    if let s = s { isButtonLike = s.backgroundColor != nil || s.gradient != nil || s.border != nil || s.borderColor != nil || s.padding != nil }

    let content: W
    if !children.isEmpty {
        content = layoutLinkChildren(node, children)
    } else {
        content = text(
            label,
            TextStyle(color: s?.color ?? GOLD, fontSize: s?.fontSize, fontWeight: s?.fontWeight ?? (isButtonLike ? 700 : nil), letterSpacing: s?.letterSpacing),
            ["align": s?.textAlign ?? (isButtonLike ? "center" : "start")]
        )
    }

    let styled = applyStyle(content, s, ApplyStyleOptions(applyFlex: false), ctx)
    var tappable = w(
        "gesture",
        [
            "gestures": href != nil ? ["tap"] : [String](),
            "opaque": true,
            "cursor": href != nil ? "pointer" : "default",
            "role": (ariaLabel ?? "").isEmpty ? "link" : "button",
            "semanticsLabel": ariaLabel,
            "onEvent": { (e: ViewEvent) in
                if e.type == "tap", let h = href { ctx.engine.host.navigate?(h, replace) }
            },
        ],
        child: styled
    )
    if let flex = s?.flex ?? s?.flexGrow {
        tappable = w("flexible", ["flex": flex, "fit": "tight"], child: sizedBox(Double.infinity, nil, tappable))
    }
    return tappable
}

// ============================================================================
// NextjsForm
// ============================================================================

private struct FieldOption {
    let value: String
    let label: String
}

private func optionsOf(_ f: JSONObject) -> [FieldOption] {
    var out: [FieldOption] = []
    if let options = asArray(f["options"]) {
        for o in options {
            if let m = asMap(o) {
                let v = jsString(m["value"] ?? m["label"] ?? "")
                out.append(FieldOption(value: v, label: jsString(m["label"] ?? v)))
            } else if let o = flattenOptional(o) {
                out.append(FieldOption(value: jsString(o), label: jsString(o)))
            }
        }
    }
    if out.isEmpty {
        for part in jsString(f["placeholder"] ?? "").components(separatedBy: ",") {
            let v = jsTrim(part)
            if !v.isEmpty { out.append(FieldOption(value: v, label: v)) }
        }
    }
    return out
}

private func numProp(_ f: JSONObject, _ key: String, _ fallback: Double) -> Double { toNumber(f[key]) ?? fallback }

/** `Math.round` (half up) then `String`, or the number as JavaScript prints it. */
private func fmtRange(_ v: Double) -> String {
    let r = (v + 0.5).rounded(.down)
    return v == r ? jsString(r) : jsString(v)
}

private final class FormState {
    /** Field name → string value (insertion-ordered, as the TypeScript record). */
    var values: JSONObject
    var busy: Bool
    var error: String?

    init(_ values: JSONObject, _ busy: Bool, _ error: String?) {
        self.values = values
        self.busy = busy
        self.error = error
    }

    func value(_ name: String) -> String? { values[name] as? String }

    /** `{...values, [name]: value}`. */
    func with(_ name: String, _ value: String) -> JSONObject {
        let next = values.copy()
        next[name] = value
        return next
    }
}

private func fieldBox(_ child: W, _ pad: EdgeInsets = EdgeInsets.symmetric(vertical: 4, horizontal: 8)) -> W {
    container(
        child: child,
        padding: pad,
        decoration: BoxDecoration(color: FIELD_FILL, border: Border.all(BorderSide(width: 1, color: FIELD_BORDER, style: .solid)), radius: BorderRadius.all(10))
    )
}

private func nextjsForm(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let action = jsString(node.props["action"] ?? "")
    let submitLabel = jsString(node.props["submitLabel"] ?? "Submit")
    let fields: [JSONObject] = (asArray(node.props["fields"]) ?? []).compactMap { asMap($0) }

    let state = ctx.engine.stateFor(ctx.elementId) { () -> FormState in
        let values = JSONObject()
        for f in fields {
            let name = jsString(f["name"] ?? "")
            if name.isEmpty { continue }
            let type = jsString(f["type"] ?? "")
            let value = flattenOptional(f["value"]).map { jsString($0) } ?? ""
            switch type {
            case "select":
                let options = optionsOf(f)
                values[name] = options.contains { $0.value == value } ? value : options.first?.value ?? value
            case "checkbox":
                values[name] = value == "true" || value == "on" ? "true" : "false"
            case "range":
                let minV = numProp(f, "min", 0)
                let maxV = numProp(f, "max", 100)
                let parsed = toNumber(value)
                values[name] = fmtRange(maxV > minV ? min(maxV, max(minV, parsed ?? minV)) : minV)
            default:
                values[name] = value // text-like and hidden
            }
        }
        return FormState(values, false, nil)
    }

    func update(values: JSONObject? = nil, busy: Bool? = nil, error: String?? = .none) {
        if let v = values { state.values = v }
        if let b = busy { state.busy = b }
        if case let .some(e) = error { state.error = e }
        ctx.engine.host.invalidate?()
    }

    let submit: () -> Void = {
        guard let handler = ctx.engine.host.submitForm, !state.busy else { return }
        update(busy: true, error: .some(nil))
        let values = state.values.copy()
        launchDetached {
            let error: String?
            do {
                error = try await handler(action, values)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                update(busy: false, error: .some("Request failed: \(error)"))
                return
            }
            update(busy: false, error: .some(error))
        }
    }

    func labelOf(_ label: String) -> W {
        padding(EdgeInsets(bottom: 4), text(label, TextStyle(color: HINT, fontSize: 11, fontWeight: 600)))
    }
    var items: [W] = []

    for f in fields {
        let name = jsString(f["name"] ?? "")
        if name.isEmpty { continue }
        let type = jsString(f["type"] ?? "")
        if type == "hidden" { continue }
        let label = flattenOptional(f["label"]).map { jsString($0) }
        let control: W

        if type == "select" {
            let options = optionsOf(f)
            let current = options.contains { $0.value == state.value(name) } ? state.value(name) : options.first?.value
            let ts = TextStyle(color: TEXT, fontSize: 14)
            control = container(
                child: w(
                    "control",
                    [
                        "kind": "select",
                        "view": jo([
                            "value": current,
                            "options": options.map { jo(["value": $0.value, "label": $0.label, "group": nil, "disabled": false]) },
                            "placeholder": jsString(f["placeholder"] ?? name),
                            "enabled": !state.busy,
                            "textStyle": ts.toSpec(),
                            "hintStyle": ts.with { $0.color = HINT }.toSpec(),
                            "colors": jo(["text": TEXT, "fill": FIELD_FILL, "icon": GOLD, "menu": FIELD_FILL, "hint": HINT]),
                        ]),
                        "onEvent": { (e: ViewEvent) in
                            if e.type == "change" {
                                update(values: state.with(name, flattenOptional(e.value).map { jsString($0) } ?? current ?? ""))
                            }
                        },
                    ]
                ),
                padding: EdgeInsets.symmetric(vertical: 4, horizontal: 10),
                decoration: BoxDecoration(color: FIELD_FILL, border: Border.all(BorderSide(width: 1, color: FIELD_BORDER, style: .solid)), radius: BorderRadius.all(10))
            )
        } else if type == "checkbox" {
            let checked = state.value(name) == "true"
            let toggle = { (v: Bool) in update(values: state.with(name, v ? "true" : "false")) }
            control = w(
                "gesture",
                [
                    "gestures": state.busy ? [String]() : ["tap"],
                    "ripple": scaleAlpha(GOLD, 0.12),
                    "rippleRadius": 10.0,
                    "cursor": state.busy ? "default" : "pointer",
                    "onEvent": { (e: ViewEvent) in if e.type == "tap" { toggle(!checked) } },
                ],
                child: fieldBox(
                    row(
                        [
                            w(
                                "control",
                                [
                                    "kind": "checkbox",
                                    "view": jo(["checked": checked, "enabled": !state.busy, "colors": jo(["fill": GOLD, "check": INK, "border": HINT])]),
                                    "controlled": true,
                                    "onEvent": { (e: ViewEvent) in if e.type == "change" { toggle(jsBool(e.value) == true) } },
                                ]
                            ),
                            w("flexible", ["flex": 1.0, "fit": "loose"], child: text(jsString(f["placeholder"] ?? label ?? name), TextStyle(color: TEXT, fontSize: 13))),
                        ],
                        ["mainAxisSize": "min"]
                    )
                )
            )
        } else if type == "range" {
            let minV = numProp(f, "min", 0)
            let maxV = numProp(f, "max", 100)
            let step = numProp(f, "step", 1)
            let hasRoom = maxV > minV
            let current = hasRoom ? min(maxV, max(minV, toNumber(state.values[name]) ?? minV)) : minV
            let slider: W
            if hasRoom {
                slider = w(
                    "control",
                    [
                        "kind": "slider",
                        "view": jo([
                            "value": current,
                            "min": minV,
                            "max": maxV,
                            "step": step > 0 ? step : nil,
                            "enabled": !state.busy,
                            "trackHeight": 3.0,
                            "colors": jo(["active": GOLD, "inactive": FIELD_BORDER, "thumb": GOLD, "overlay": withOpacity(GOLD, 0.15)]),
                        ]),
                        "controlled": true,
                        "onEvent": { (e: ViewEvent) in
                            if e.type == "change" || e.type == "input" { update(values: state.with(name, fmtRange(eventNumber(e.value)))) }
                        },
                    ]
                )
            } else {
                slider = padding(EdgeInsets.symmetric(vertical: 8, horizontal: 0), text(jsString(f["placeholder"] ?? "No range available"), TextStyle(color: HINT, fontSize: 13)))
            }
            control = fieldBox(
                row([expanded(slider), sizedBox(6, nil), text(state.value(name) ?? fmtRange(current), TextStyle(color: GOLD, fontSize: 13, fontWeight: 700))]),
                EdgeInsets.symmetric(vertical: 6, horizontal: 10)
            )
        } else {
            let multiline = type == "textarea"
            let ts = TextStyle(color: TEXT, fontSize: 14, height: 1.3)
            let view: JSONObject = [
                "value": state.value(name) ?? "",
                "placeholder": jsString(f["placeholder"] ?? name),
                "inputType": type == "password" ? "password" : type == "number" ? "number" : "text",
            ]
            if type == "number" { view["allowedPattern"] = "[0-9.\\-]" }
            view["multiline"] = multiline
            view["enabled"] = true
            view["variant"] = "outline"
            view["textStyle"] = ts.toSpec()
            view["hintStyle"] = ts.with { $0.color = HINT }.toSpec()
            view["contentPadding"] = [12.0, 12.0, 12.0, 12.0]
            view["colors"] = jo([
                "text": TEXT,
                "hint": HINT,
                "fill": FIELD_FILL,
                "border": FIELD_BORDER,
                "focusedBorder": GOLD,
                "focusedBorderWidth": 1.5,
                "cursor": GOLD,
                "radius": 10.0,
            ])
            control = w(
                "control",
                [
                    "kind": "textInput",
                    "lines": multiline ? 3.0 : 1.0,
                    "maxLines": multiline ? 4.0 : 1.0,
                    "padding": [12.0, 12.0, 12.0, 12.0],
                    "lineHeight": 14 * 1.3,
                    "view": view,
                    "onEvent": { (e: ViewEvent) in
                        if e.type == "input" || e.type == "change" {
                            state.values = state.with(name, flattenOptional(e.value).map { jsString($0) } ?? "")
                        } else if e.type == "submit" && !multiline && !state.busy {
                            submit()
                        }
                    },
                ]
            )
        }

        var col: [W] = []
        if let l = label, !l.isEmpty { col.append(labelOf(l)) }
        col.append(control)
        items.append(padding(EdgeInsets(bottom: 12), column(col, ["crossAxisAlignment": "start", "mainAxisSize": "min"])))
    }

    if let err = state.error, !err.isEmpty {
        items.append(padding(EdgeInsets(bottom: 8), text(err, TextStyle(color: ERROR, fontSize: 13))))
    }

    let buttonChild: W
    if state.busy {
        buttonChild = sizedBox(
            16,
            16,
            w("control", ["kind": "progress", "view": jo(["variant": "circular", "value": nil, "strokeWidth": 2.0, "colors": jo(["indicator": INK, "track": nil])])])
        )
    } else {
        buttonChild = text(submitLabel, TextStyle(color: INK, fontSize: 14, fontWeight: 700, letterSpacing: 0.3))
    }
    let button = w(
        "gesture",
        [
            "gestures": state.busy ? [String]() : ["tap"],
            "ripple": scaleAlpha(INK, 0.12),
            "cursor": state.busy ? "default" : "pointer",
            "role": "button",
            "semanticsLabel": submitLabel,
            "onEvent": { (e: ViewEvent) in if e.type == "tap" { submit() } },
        ],
        child: container(
            child: buttonChild,
            padding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            alignment: Alignment(x: 0, y: 0),
            decoration: BoxDecoration(color: state.busy ? withOpacity(GOLD, 0.5) : GOLD, radius: BorderRadius.all(10), shadows: [])
        )
    )
    items.append(sizedBox(Double.infinity, nil, w("constrained", ["minHeight": 40.0], child: button)))
    return column(items, ["mainAxisSize": "min"])
}

/** The Next.js bridge builders, in registration order. */
public let nextjsWidgets: [(String, WidgetBuilder)] = [
    ("NextjsLink", nextjsLink),
    ("next-link", nextjsLink),
    ("NextjsForm", nextjsForm),
    ("nextjs-form", nextjsForm),
]
