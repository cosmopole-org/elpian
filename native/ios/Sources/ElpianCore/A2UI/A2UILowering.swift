import Foundation

/**
 * Lowering: an A2UI surface → an Elpian node tree (a2ui/lowering.ts) — the
 * same JSON a mini app renders, built from Elpian's existing widgets with
 * Material 3 visuals, so agent UI and static Elpian UI mix freely.
 *
 * | A2UI           | Elpian nodes                                                   |
 * |----------------|----------------------------------------------------------------|
 * | Text           | `Text` (typography per variant); Markdown → `p` + inline spans  |
 * | Image          | `Image` sized per variant (`ClipRRect` for avatars)             |
 * | Icon           | `Icon` (Material name) or an SVG-path `Image`                  |
 * | Video / Audio  | `video` / `audio` with controls                                |
 * | Row / Column   | `Row` / `Column` (justify → justifyContent, align → alignItems; `weight` → `Expanded`) |
 * | List           | `ListView` (vertical or horizontal scroll)                     |
 * | Card           | `Card`                                                         |
 * | Tabs           | tab header row + the selected child (state kept per surface)    |
 * | Modal          | the trigger; when open, a barrier + dialog over the surface     |
 * | Divider        | `Divider` / a vertical rule                                    |
 * | Button         | `Button` (default / primary / borderless; disabled by checks)   |
 * | TextField      | label + `TextField` (+ check error text)                       |
 * | CheckBox       | `Checkbox` + label                                              |
 * | ChoicePicker   | radio / checkbox list or chips, optional filter field          |
 * | Slider         | label + value + `Slider`                                        |
 * | DateTimeInput  | label + date / time / datetime `TextField`                     |
 *
 * Interactions are closures ([ElpianEventListener]s) in the nodes' `events`
 * (Elpian calls host closures directly); they write the data model (two-way
 * binding), dispatch actions, or change UI-local state through
 * [LoweringHooks]. The output is plain node JSON ([JSONObject]s) for the engine.
 */
public struct LoweringHooks {
    /** Two-way binding: write [value] at the absolute [path]. */
    public var write: (_ surfaceId: String, _ path: String, _ value: Any?) -> Void
    /** An interactive component fired its `action` (resolved in [scope]). */
    public var action: (_ surfaceId: String, _ componentId: String, _ action: Any?, _ scope: String) -> Void
    /** UI-local state changed (tab, modal, filter…): render again. */
    public var invalidate: () -> Void
    /** Evaluation problems (unknown function, bad template…). */
    public var error: ((A2UIError) -> Void)?

    public init(write: @escaping (_ surfaceId: String, _ path: String, _ value: Any?) -> Void,
                action: @escaping (_ surfaceId: String, _ componentId: String, _ action: Any?, _ scope: String) -> Void,
                invalidate: @escaping () -> Void, error: ((A2UIError) -> Void)? = nil) {
        self.write = write
        self.action = action
        self.invalidate = invalidate
        self.error = error
    }
}

/** UI-local state that survives re-lowering (selected tab, open modal, filter text, touched fields). */
public final class A2UIUiState {
    private var values: [String: Any?] = [:]

    public init() {}

    public func get<T>(_ key: String, _ fallback: T) -> T {
        if let v = values[key], let t = v as? T { return t }
        return fallback
    }

    public func set(_ key: String, _ value: Any?) {
        values[key] = .some(value)
    }

    /** Drop the state of one surface (after `deleteSurface`). */
    public func clearSurface(_ prefix: String) {
        for k in values.keys where k.hasPrefix(prefix) { values.removeValue(forKey: k) }
    }
}

public struct LoweringOptions {
    public var hooks: LoweringHooks
    public var state: A2UIUiState
    /** Prefix for node keys (element ids) — unique per embedding widget. */
    public var keyPrefix: String?
    /** Show `agentDisplayName` / `iconUrl` above the surface (default true). */
    public var showAttribution: Bool
    /** Lower every deferred subtree too — closed modals, hidden tabs (previews, tests). */
    public var expandAll: Bool

    public init(hooks: LoweringHooks, state: A2UIUiState, keyPrefix: String? = nil, showAttribution: Bool = true, expandAll: Bool = false) {
        self.hooks = hooks
        self.state = state
        self.keyPrefix = keyPrefix
        self.showAttribution = showAttribution
        self.expandAll = expandAll
    }
}

public struct LoweringPlaceholder {
    public let id: String
    public let reason: String
}

public struct LoweringResult {
    public let node: JSONObject
    /** `componentId@scope` of every component lowered. */
    public let lowered: [String]
    /** Components rendered as an error placeholder (unknown type, cycle, depth). */
    public let placeholders: [LoweringPlaceholder]
}

/** The surface palette: Material 3 baseline with the theme's primary color. */
public struct A2UIPalette {
    public let primary: String
    public let onPrimary: String
    public let primaryContainer: String
    public let onSurface: String
    public let onSurfaceVariant: String
    public let outline: String
    public let outlineVariant: String
    public let surfaceContainer: String
    public let surfaceContainerHigh: String
    public let error: String
}

private let HEX6 = JSRegex("^#[0-9a-fA-F]{6}$")

public func paletteFor(_ theme: JSONObject) -> A2UIPalette {
    let given = theme["primaryColor"] as? String
    let primary = given.map { HEX6.test($0) } == true ? given!.uppercased() : "#6750A4"
    return A2UIPalette(
        primary: primary,
        onPrimary: luminance(primary) > 0.5 ? "#1D1B20" : "#FFFFFF",
        primaryContainer: mix(primary, "#FFFFFF", 0.82),
        onSurface: "#1D1B20",
        onSurfaceVariant: "#49454F",
        outline: "#79747E",
        outlineVariant: "#CAC4D0",
        surfaceContainer: "#F7F2FA",
        surfaceContainerHigh: "#ECE6F0",
        error: "#B3261E"
    )
}

private func rgb(_ hex: String) -> [Double] {
    let n = Int(hex.dropFirst(), radix: 16) ?? 0
    return [Double((n >> 16) & 255), Double((n >> 8) & 255), Double(n & 255)]
}

private func luminance(_ hex: String) -> Double {
    let c = rgb(hex).map { (c: Double) -> Double in
        let s = c / 255
        return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
}

private func mix(_ a: String, _ b: String, _ t: Double) -> String {
    let x = rgb(a)
    let y = rgb(b)
    return "#" + (0..<3).map { i -> String in
        let h = String(Int(jsRound(x[i] + (y[i] - x[i]) * t)), radix: 16)
        return (h.count < 2 ? "0" + h : h)
    }.joined().uppercased()
}

/** Leaf-margin strategy: visual leaves carry the spacing, containers none. */
private let LEAF_MARGIN = 4.0
private let MAX_DEPTH = 64

private let TEXT_VARIANTS: [String: [(String, Any?)]] = [
    "h1": [("fontSize", 40.0), ("fontWeight", 600.0), ("lineHeight", 1.2)],
    "h2": [("fontSize", 32.0), ("fontWeight", 600.0), ("lineHeight", 1.25)],
    "h3": [("fontSize", 28.0), ("fontWeight", 600.0), ("lineHeight", 1.28)],
    "h4": [("fontSize", 24.0), ("fontWeight", 600.0), ("lineHeight", 1.33)],
    "h5": [("fontSize", 20.0), ("fontWeight", 600.0), ("lineHeight", 1.4)],
    "caption": [("fontSize", 13.0), ("lineHeight", 1.35)],
    "body": [("fontSize", 16.0), ("lineHeight", 1.5)],
]

/** A2UI icon names → Material icon names where the snake_case form differs. */
private let ICON_ALIASES: [String: String] = [
    "favoriteOff": "favorite_border",
    "starOff": "star_border",
    "play": "play_arrow",
    "rewind": "fast_rewind",
]

private let CAMEL_BOUNDARY = JSRegex("([a-z0-9])([A-Z])")

/** The Material icon name for an A2UI icon name (`accountCircle` → `account_circle`). */
public func materialIconName(_ name: String) -> String {
    ICON_ALIASES[name] ?? CAMEL_BOUNDARY.replace(name) { g in "\(g[1] ?? "")_\(g[2] ?? "")" }.lowercased()
}

private let JUSTIFY: [String: String] = [
    "start": "flex-start",
    "center": "center",
    "end": "flex-end",
    "spaceBetween": "space-between",
    "spaceAround": "space-around",
    "spaceEvenly": "space-evenly",
    "stretch": "flex-start",
]

private let ALIGN: [String: String] = ["start": "flex-start", "center": "center", "end": "flex-end", "stretch": "stretch"]

private struct Ctx {
    var dc: DataContext
    var scope: String
    var depth: Int
    var stack: [String]
    /** The A2UI type of the parent (for `weight`). */
    var parent: String?
    /** Inside a button: no leaf margins, icons take the button's content color. */
    var contentColor: String?
    /** Modal trigger: a press opens the modal instead of firing the action. */
    var interceptPress: (() -> Void)?
}

/** An Elpian node `{type, props, children, key?, events?}`. */
func a2uiElement(_ type: String, _ props: JSONObject = JSONObject(), _ children: [JSONObject] = [], key: String? = nil,
                 events: [(String, ElpianEventListener)] = []) -> JSONObject {
    let node = JSONObject([("type", type), ("props", props), ("children", children.map { $0 as Any? })])
    if let k = key, !k.isEmpty { node["key"] = k }
    if !events.isEmpty {
        let e = JSONObject()
        for (name, fn) in events { e[name] = fn }
        node["events"] = e
    }
    return node
}

private func el(_ type: String, _ props: JSONObject = JSONObject(), _ children: [JSONObject] = [], key: String? = nil,
                events: [(String, ElpianEventListener)] = []) -> JSONObject {
    a2uiElement(type, props, children, key: key, events: events)
}

private func style(_ pairs: [(String, Any?)]) -> JSONObject { JSONObject(pairs) }

private func textNode(_ text: String, _ style: JSONObject = JSONObject(), key: String? = nil) -> JSONObject {
    el("Text", JSONObject([("text", text), ("style", style)]), [], key: key)
}

/** Stop an internal event from bubbling into the embedding app's handlers. */
private func handled(_ e: ElpianEvent) {
    e.propagationStopped = true
}

private func childrenOf(_ node: JSONObject) -> [JSONObject] {
    (asArray(node["children"]) ?? []).compactMap { flattenOptional($0) as? JSONObject }
}

private func propsOf(_ node: JSONObject) -> JSONObject {
    if let p = node["props"] as? JSONObject { return p }
    let p = JSONObject()
    node["props"] = p
    return p
}

/** Lower [surface] to an Elpian node tree. */
public func lowerSurface(_ surface: A2UISurfaceModel, _ options: LoweringOptions) -> LoweringResult {
    Lowerer(surface, options).run()
}

private final class Lowerer {
    let surface: A2UISurfaceModel
    let options: LoweringOptions
    let palette: A2UIPalette
    let prefix: String
    var lowered: [String] = []
    var placeholders: [LoweringPlaceholder] = []
    var overlays: [JSONObject] = []

    init(_ surface: A2UISurfaceModel, _ options: LoweringOptions) {
        self.surface = surface
        self.options = options
        palette = paletteFor(surface.theme)
        prefix = "\(options.keyPrefix ?? "a2ui"):\(surface.id)"
    }

    var hooks: LoweringHooks { options.hooks }

    func stateKey(_ key: String, _ what: String) -> String { "\(key)#\(what)" }

    func run() -> LoweringResult {
        var parts: [JSONObject] = []
        if options.showAttribution, let header = attribution() { parts.append(header) }
        if surface.isReady {
            let ctx = Ctx(dc: surface.context("/"), scope: "/", depth: 0, stack: [], parent: nil, contentColor: nil, interceptPress: nil)
            parts.append(child("root", ctx))
        }
        var node = el("Column", JSONObject([("style", style([("alignItems", "stretch"), ("justifyContent", "flex-start"), ("color", palette.onSurface)]))]),
                      parts, key: prefix)
        if !overlays.isEmpty {
            node = el("ConstrainedBox", JSONObject([("style", style([("minHeight", 420.0)]))]), [
                el("Stack", JSONObject([("style", style([("alignment", "top left")]))]), [node] + overlays),
            ])
        }
        return LoweringResult(node: node, lowered: lowered, placeholders: placeholders)
    }

    private static let ICON_URL = JSRegex("^https?:|^data:image/", ignoreCase: true)

    func attribution() -> JSONObject? {
        let theme = surface.theme
        let name = (theme["agentDisplayName"] as? String) ?? ""
        let iconUrl = theme["iconUrl"] as? String
        let icon = iconUrl.map { Lowerer.ICON_URL.test($0) } == true ? iconUrl! : ""
        if name.isEmpty && icon.isEmpty { return nil }
        var row: [JSONObject] = []
        if !icon.isEmpty {
            row.append(el("ClipRRect", JSONObject([("style", style([("borderRadius", 10.0)]))]), [
                el("Image", JSONObject([("src", icon), ("fit", "cover"), ("alt", name), ("style", style([("width", 20.0), ("height", 20.0)]))])),
            ]))
        }
        if !name.isEmpty {
            row.append(textNode(name, style([("fontSize", 12.0), ("fontWeight", 500.0), ("color", palette.onSurfaceVariant), ("margin", "0 0 0 8")])))
        }
        return el("Row", JSONObject([("style", style([("alignItems", "center"), ("padding", "4 4 8 4")]))]), row, key: "\(prefix)/attribution")
    }

    func keyFor(_ id: String, _ ctx: Ctx) -> String {
        ctx.scope == "/" ? "\(prefix):\(id)" : "\(prefix):\(id)@\(ctx.scope)"
    }

    func report(_ e: A2UIError) {
        hooks.error?(A2UIError(e.category, e.message, surfaceId: surface.id, path: e.path))
    }

    func eval<T>(_ ctx: Ctx, _ fn: () throws -> T, _ fallback: T) -> T {
        ctx.dc.safe(fn, fallback) { [weak self] e in self?.report(e) }
    }

    func str(_ ctx: Ctx, _ v: Any?, present: Bool = true) -> String {
        if !present { return "" }
        return eval(ctx, { try ctx.dc.string(v) }, "")
    }

    func placeholder(_ id: String, _ reason: String, _ key: String) -> JSONObject {
        placeholders.append(LoweringPlaceholder(id: id, reason: reason))
        return el("Container", JSONObject([("style", style([("padding", 8.0), ("margin", LEAF_MARGIN), ("backgroundColor", "#FDECEA"), ("borderRadius", 8.0)]))]),
                  [textNode(reason, style([("fontSize", 13.0), ("color", palette.error)]))], key: key)
    }

    /** Lower the component [id] (a child reference) in [ctx]. */
    func child(_ id: String, _ ctx: Ctx) -> JSONObject {
        let key = keyFor(id, ctx)
        // Not arrived yet (progressive rendering).
        guard let component = surface.components[id] else { return el("SizedBox", JSONObject([("width", 0.0), ("height", 0.0)]), [], key: key) }
        let marker = "\(id)@\(ctx.scope)"
        if ctx.stack.contains(marker) { return placeholder(id, "Circular reference to \"\(id)\"", key) }
        if ctx.depth >= MAX_DEPTH { return placeholder(id, "Component tree too deep", key) }
        lowered.append(marker)
        var inner = ctx
        inner.depth += 1
        inner.stack.append(marker)
        var node = self.component(component, key, inner)
        let type = jsString(component["component"])
        let weight = jsNumber(component["weight"])
        if let w = weight, w > 0, ctx.parent == "Row" || ctx.parent == "Column" {
            node = el("Expanded", JSONObject([("flex", w)]), [node])
        } else if ctx.parent == "Row" && ["Text", "Column", "Row", "List", "Card", "TextField", "ChoicePicker", "Slider", "DateTimeInput"].contains(type) {
            // A row shrinks text and nested layouts to its width (CSS flex-shrink).
            node = el("Flexible", JSONObject([("flex", 1.0), ("fit", "loose")]), [node])
        }
        return node
    }

    func children(_ component: JSONObject, _ ctx: Ctx) -> [JSONObject] {
        let spec = flattenOptional(component["children"])
        var out: [JSONObject] = []
        var childCtx = ctx
        childCtx.parent = jsString(component["component"])
        childCtx.interceptPress = nil
        if let ids = asArray(spec) {
            for raw in ids {
                if let id = flattenOptional(raw) as? String { out.append(child(id, childCtx)) }
            }
        } else if let t = spec as? JSONObject, let template = t["componentId"] as? String, let path = t["path"] as? String {
            let base = ctx.dc.resolvePath(path)
            let items = eval(ctx, { try ctx.dc.model.get(base) }, nil)
            func join(_ k: String) -> String { base == "/" ? "/\(k)" : "\(base)/\(k)" }
            var keys: [String] = []
            if let a = asArray(items) {
                keys = (0..<a.count).map { String($0) }
            } else if let o = items as? JSONObject {
                keys = o.keys
            }
            for k in keys {
                let scope = join(k)
                var c = childCtx
                c.dc = ctx.dc.child(scope)
                c.scope = scope
                out.append(child(template, c))
            }
        }
        return out
    }

    func component(_ c: JSONObject, _ key: String, _ ctx: Ctx) -> JSONObject {
        let type = jsString(c["component"])
        switch type {
        case "Text":
            return text(c, key, ctx)
        case "Image":
            return image(c, key, ctx)
        case "Icon":
            return icon(c, key, ctx)
        case "Video":
            return el("video", JSONObject([("src", str(ctx, c["url"], present: c.has("url"))), ("controls", true),
                                           ("style", style([("height", 220.0), ("margin", LEAF_MARGIN), ("objectFit", "contain")]))]), [], key: key)
        case "AudioPlayer":
            let description = str(ctx, c["description"], present: c.has("description"))
            var parts: [JSONObject] = []
            if !description.isEmpty { parts.append(textNode(description, style([("fontSize", 14.0), ("color", palette.onSurfaceVariant)]))) }
            parts.append(el("audio", JSONObject([("src", str(ctx, c["url"], present: c.has("url"))), ("controls", true), ("style", style([("height", 54.0)]))]),
                            [], key: "\(key)/audio"))
            return el("Column", JSONObject([("style", style([("alignItems", "stretch"), ("margin", LEAF_MARGIN)]))]), parts, key: key)
        case "Row", "Column":
            return flex(c, key, ctx)
        case "List":
            return list(c, key, ctx)
        case "Card":
            var childCtx = ctx
            childCtx.parent = "Card"
            childCtx.interceptPress = nil
            let kids: [JSONObject] = (c["child"] as? String).map { [child($0, childCtx)] } ?? []
            return el("Card", JSONObject([
                ("elevation", 1.0),
                ("style", style([("padding", 16.0), ("margin", LEAF_MARGIN), ("borderRadius", 12.0), ("backgroundColor", "#FFFFFF"),
                                 ("borderColor", palette.outlineVariant), ("borderWidth", 1.0)])),
            ]), kids, key: key)
        case "Tabs":
            return tabs(c, key, ctx)
        case "Modal":
            return modal(c, key, ctx)
        case "Divider":
            if (c["axis"] as? String) == "vertical" {
                return el("Container", JSONObject([("style", style([("width", 1.0), ("minHeight", 24.0), ("margin", "0 8"), ("backgroundColor", palette.outlineVariant)]))]),
                          [], key: key)
            }
            return el("Divider", JSONObject([("style", style([("height", 17.0), ("borderColor", palette.outlineVariant)]))]), [], key: key)
        case "Button":
            return button(c, key, ctx)
        case "TextField":
            return textField(c, key, ctx)
        case "CheckBox":
            return checkBox(c, key, ctx)
        case "ChoicePicker":
            return choicePicker(c, key, ctx)
        case "Slider":
            return slider(c, key, ctx)
        case "DateTimeInput":
            return dateTime(c, key, ctx)
        default:
            return placeholder(jsString(c["id"]), "Unknown component: \(type)", key)
        }
    }

    // --------------------------------------------------------------------------
    // Display
    // --------------------------------------------------------------------------

    func textStyle(_ variant: String, _ ctx: Ctx) -> JSONObject {
        let base = JSONObject(TEXT_VARIANTS[variant] ?? TEXT_VARIANTS["body"]!)
        if variant == "caption" { base["color"] = palette.onSurfaceVariant }
        if let cc = ctx.contentColor { base["color"] = cc }
        return base
    }

    func text(_ c: JSONObject, _ key: String, _ ctx: Ctx) -> JSONObject {
        let value = str(ctx, c["text"], present: c.has("text"))
        let v = c["variant"] as? String
        let variant = v.map { TEXT_VARIANTS[$0] != nil } == true ? v! : "body"
        let margin = ctx.contentColor != nil ? 0.0 : LEAF_MARGIN
        let blocks = parseMarkdown(value)
        func styled() -> JSONObject {
            let s = textStyle(variant, ctx)
            s["margin"] = margin
            return s
        }
        if blocks.isEmpty { return textNode("", styled(), key: key) }
        if isPlainText(blocks) { return textNode(plainText(blocks), styled(), key: key) }
        let lowered = blocks.enumerated().map { i, b in markdownBlock(b, variant, ctx, "\(key)/md\(i)") }
        if lowered.count == 1 {
            lowered[0]["key"] = key
            (propsOf(lowered[0])["style"] as? JSONObject)?["margin"] = margin
            return lowered[0]
        }
        return el("Column", JSONObject([("style", style([("alignItems", "flex-start"), ("margin", margin)]))]), lowered, key: key)
    }

    func markdownBlock(_ block: MarkdownBlock, _ variant: String, _ ctx: Ctx, _ key: String) -> JSONObject {
        var s = textStyle(variant, ctx)
        var prefix = ""
        if block.type == .heading && variant == "body" { s = textStyle("h\(min(5, block.level))", ctx) }
        if block.type == .bullet { prefix = "•  " }
        if block.type == .ordered { prefix = "\(block.number).  " }
        let inlines = prefix.isEmpty ? block.inlines : [MarkdownInline(text: prefix)] + block.inlines
        let spans = inlines.map { inline($0) }
        s["margin"] = 0.0
        s["padding"] = block.type == .bullet || block.type == .ordered ? "0 0 0 8" as Any : 0.0
        return el("p", JSONObject([("style", s)]), spans, key: key)
    }

    private static let HTTP_URL = JSRegex("^https?://", ignoreCase: true)

    func inline(_ i: MarkdownInline) -> JSONObject {
        let s = JSONObject()
        if i.bold { s["fontWeight"] = 700.0 }
        if i.italic { s["fontStyle"] = "italic" }
        if i.strike { s["textDecoration"] = "line-through" }
        if i.code {
            s["fontFamily"] = "monospace"
            s["backgroundColor"] = "#F1EDF4"
        }
        if let href = i.href, Lowerer.HTTP_URL.test(href) {
            let ls = s.copy()
            ls["color"] = palette.primary
            return el("a", JSONObject([("href", href), ("target", "_blank"), ("text", i.text), ("style", ls)]))
        }
        return el("span", JSONObject([("text", i.text), ("style", s)]))
    }

    func image(_ c: JSONObject, _ key: String, _ ctx: Ctx) -> JSONObject {
        let src = str(ctx, c["url"], present: c.has("url"))
        let variant = (c["variant"] as? String) ?? "mediumFeature"
        let alt = accessibilityLabel(c, ctx) ?? str(ctx, c["description"], present: c.has("description"))
        let fitProp = (c["fit"] as? String) ?? (variant == "icon" ? "contain" : "cover")
        let sizes: [String: [(String, Any?)]] = [
            "icon": [("width", 24.0), ("height", 24.0)],
            "avatar": [("width", 40.0), ("height", 40.0)],
            "smallFeature": [("width", 100.0), ("height", 100.0)],
            "mediumFeature": [("height", 200.0), ("maxWidth", 300.0)],
            "largeFeature": [("height", 320.0)],
            "header": [("height", 200.0)],
        ]
        let size = JSONObject(sizes[variant] ?? sizes["mediumFeature"]!)
        let image = el("Image", JSONObject([("src", src), ("fit", fitProp), ("alt", alt), ("style", size)]), [], key: "\(key)/img")
        let radius = variant == "avatar" ? 20.0 : variant == "icon" ? 0.0 : 8.0
        let inner = radius != 0 ? el("ClipRRect", JSONObject([("style", style([("borderRadius", radius)]))]), [image]) : image
        return el("Container", JSONObject([("style", style([("margin", variant == "header" ? 0.0 : LEAF_MARGIN)]))]), [inner], key: key)
    }

    func icon(_ c: JSONObject, _ key: String, _ ctx: Ctx) -> JSONObject {
        let name = eval(ctx, { try ctx.dc.evaluate(c["name"]) }, nil)
        let color = ctx.contentColor ?? palette.onSurfaceVariant
        let margin = ctx.contentColor != nil ? 0.0 : LEAF_MARGIN
        if let o = name as? JSONObject, let path = o["svgPath"] as? String {
            let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\"><path fill=\"\(color)\" d=\"\(path.replacingOccurrences(of: "\"", with: ""))\"/></svg>"
            return el("Image", JSONObject([
                ("src", "data:image/svg+xml;utf8,\(encodeURIComponent(svg))"), ("fit", "contain"), ("alt", accessibilityLabel(c, ctx) ?? ""),
                ("style", style([("width", 24.0), ("height", 24.0), ("margin", margin)])),
            ]), [], key: key)
        }
        let s = stringifyValue(name)
        return el("Icon", JSONObject([("icon", materialIconName(s.isEmpty ? "help" : s)), ("size", 24.0), ("style", style([("color", color), ("margin", margin)]))]),
                  [], key: key)
    }

    // --------------------------------------------------------------------------
    // Layout
    // --------------------------------------------------------------------------

    func flex(_ c: JSONObject, _ key: String, _ ctx: Ctx) -> JSONObject {
        let justify = (c["justify"] as? String) ?? "start"
        let align = (c["align"] as? String) ?? "stretch"
        var kids = children(c, ctx)
        if justify == "stretch" {
            kids = kids.map { n in
                let t = n["type"] as? String
                return t == "Expanded" || t == "Flexible" ? n : el("Expanded", JSONObject([("flex", 1.0)]), [n])
            }
        }
        return el(jsString(c["component"]), JSONObject([("style", style([("justifyContent", JUSTIFY[justify] ?? "flex-start"), ("alignItems", ALIGN[align] ?? "stretch")]))]),
                  kids, key: key)
    }

    func list(_ c: JSONObject, _ key: String, _ ctx: Ctx) -> JSONObject {
        let horizontal = (c["direction"] as? String) == "horizontal"
        let align = (c["align"] as? String) ?? "stretch"
        let asFlex = c.copy()
        asFlex["component"] = horizontal ? "Row" : "Column"
        var kids = children(asFlex, ctx).map { n in (n["type"] as? String) == "Flexible" ? childrenOf(n)[0] : n }
        if horizontal { kids = kids.map { el("ConstrainedBox", JSONObject([("style", style([("maxWidth", 320.0)]))]), [$0]) } }
        let inner = el(horizontal ? "Row" : "Column", JSONObject([("style", style([("alignItems", ALIGN[align] ?? "stretch")]))]), kids)
        return el("ListView", JSONObject([("scrollDirection", horizontal ? "horizontal" : "vertical")]), horizontal ? kids : [inner], key: key)
    }

    func tabs(_ c: JSONObject, _ key: String, _ ctx: Ctx) -> JSONObject {
        let tabs = (asArray(c["tabs"]) ?? []).compactMap { flattenOptional($0) as? JSONObject }
        let sk = stateKey(key, "tab")
        let selected = min(options.state.get(sk, 0), max(0, tabs.count - 1))
        let p = palette
        let state = options.state
        let hooks = self.hooks
        var headers: [JSONObject] = []
        for (i, t) in tabs.enumerated() {
            let active = i == selected
            headers.append(el("Container", JSONObject([("style", style([("padding", "12 16 0 16"), ("cursor", "pointer")]))]), [
                el("Column", JSONObject([("style", style([("alignItems", "stretch")]))]), [
                    textNode(str(ctx, t["title"], present: t.has("title")),
                             style([("fontSize", 14.0), ("fontWeight", 600.0), ("color", active ? p.primary : p.onSurfaceVariant), ("textAlign", "center")])),
                    el("Container", JSONObject([("style", style([("height", 3.0), ("margin", "10 0 0 0"), ("backgroundColor", active ? p.primary : "transparent"),
                                                                 ("borderRadius", "3 3 0 0")]))])),
                ]),
            ], key: "\(key)/tab\(i)", events: [("click", { e in
                handled(e)
                state.set(sk, i)
                hooks.invalidate()
            })]))
        }
        var childCtx = ctx
        childCtx.parent = "Tabs"
        childCtx.interceptPress = nil
        var bodies: [JSONObject] = []
        for (i, t) in tabs.enumerated() {
            guard let id = t["child"] as? String else { continue }
            if i == selected {
                bodies.append(child(id, childCtx))
            } else if options.expandAll {
                _ = child(id, childCtx)
            }
        }
        return el("Column", JSONObject([("style", style([("alignItems", "stretch")]))]), [
            el("Row", JSONObject([("style", style([("alignItems", "flex-end"), ("justifyContent", "flex-start")]))]), headers),
            el("Divider", JSONObject([("style", style([("height", 1.0), ("borderColor", p.outlineVariant)]))])),
        ] + bodies, key: key)
    }

    func modal(_ c: JSONObject, _ key: String, _ ctx: Ctx) -> JSONObject {
        let sk = stateKey(key, "open")
        let open = options.state.get(sk, false)
        let state = options.state
        let hooks = self.hooks
        let setOpen: (Bool) -> Void = { v in
            state.set(sk, v)
            hooks.invalidate()
        }
        var trigger = el("SizedBox", JSONObject([("width", 0.0), ("height", 0.0)]))
        if let tid = c["trigger"] as? String {
            let target = surface.components[tid]
            var tctx = ctx
            tctx.parent = "Modal"
            tctx.interceptPress = { setOpen(true) }
            trigger = child(tid, tctx)
            if let t = target, jsString(t["component"]) != "Button" {
                trigger = el("GestureDetector", JSONObject(), [trigger], key: "\(key)/trigger", events: [("click", { e in
                    handled(e)
                    setOpen(true)
                })])
            }
        }
        if open || options.expandAll, let cid = c["content"] as? String {
            var cctx = ctx
            cctx.parent = "Modal"
            cctx.interceptPress = nil
            let content = child(cid, cctx)
            if open { overlays.append(dialog(key, content) { setOpen(false) }) }
        }
        return el("Column", JSONObject([("style", style([("alignItems", "flex-start")]))]), [trigger], key: key)
    }

    func dialog(_ key: String, _ content: JSONObject, _ close: @escaping () -> Void) -> JSONObject {
        let p = palette
        let closeButton = el("Container", JSONObject([("style", style([("padding", 8.0), ("borderRadius", 20.0), ("cursor", "pointer")]))]), [
            el("Icon", JSONObject([("icon", "close"), ("size", 24.0), ("style", style([("color", p.onSurfaceVariant)]))])),
        ], key: "\(key)/close", events: [("click", { e in
            handled(e)
            close()
        })])
        let panel = el("Container", JSONObject([("style", style([
            ("backgroundColor", p.surfaceContainerHigh), ("borderRadius", 28.0), ("padding", "8 16 24 24"), ("maxWidth", 560.0), ("margin", 24.0),
            ("boxShadow", "0 8px 24px rgba(0,0,0,0.25)"),
        ]))]), [
            el("Column", JSONObject([("style", style([("alignItems", "stretch")]))]), [
                el("Row", JSONObject([("style", style([("justifyContent", "flex-end")]))]), [closeButton]), content,
            ]),
        ], key: "\(key)/dialog",
        // Taps inside the dialog stay inside (the barrier closes on outside taps).
        events: [("click", { e in handled(e) })])
        let barrier = el("Container", JSONObject([("style", style([("backgroundColor", "rgba(0,0,0,0.4)")]))]), [el("Center", JSONObject(), [panel])],
                         key: "\(key)/barrier", events: [("click", { e in
                             handled(e)
                             close()
                         })])
        return el("Positioned", JSONObject([("style", style([("top", 0.0), ("left", 0.0), ("right", 0.0), ("bottom", 0.0)]))]), [barrier])
    }

    // --------------------------------------------------------------------------
    // Inputs
    // --------------------------------------------------------------------------

    func accessibilityLabel(_ c: JSONObject, _ ctx: Ctx) -> String? {
        if let a = c["accessibility"] as? JSONObject, a.has("label") {
            let s = str(ctx, a["label"])
            if !s.isEmpty { return s }
        }
        return nil
    }

    struct Bind {
        let read: (_ fallback: Any?) -> Any?
        let write: (_ value: Any?) -> Void
    }

    /** Bind an input: the absolute path its value writes to, or a UI-state slot for literals. */
    func binding(_ value: Any?, _ ctx: Ctx, _ key: String) -> Bind {
        let path = ctx.dc.bindingPath(value)
        let local = stateKey(key, "value")
        let state = options.state
        let hooks = self.hooks
        let surfaceId = surface.id
        let model = ctx.dc.model
        return Bind(
            read: { [weak self] fallback in
                if let p = path { return self?.eval(ctx, { try model.get(p) }, nil) ?? nil }
                let stored: Any? = state.get(local, fallback)
                return stored
            },
            write: { v in
                if let p = path {
                    hooks.write(surfaceId, p, v)
                } else {
                    state.set(local, v)
                    hooks.invalidate()
                }
            }
        )
    }

    func checks(_ c: JSONObject, _ ctx: Ctx) -> [String] {
        evaluateChecks(c["checks"], ctx.dc) { [weak self] e in self?.report(e) }
    }

    func label(_ text: String, _ color: String? = nil) -> JSONObject {
        textNode(text, style([("fontSize", 12.0), ("fontWeight", 500.0), ("color", color ?? palette.onSurfaceVariant), ("margin", "0 0 2 0")]))
    }

    func errorText(_ messages: [String]) -> [JSONObject] {
        messages.isEmpty ? [] : [textNode(messages[0], style([("fontSize", 12.0), ("color", palette.error), ("margin", "4 0 0 0")]))]
    }

    func touched(_ key: String) -> Bool { options.state.get(stateKey(key, "touched"), false) }

    func button(_ c: JSONObject, _ key: String, _ ctx: Ctx) -> JSONObject {
        let variant = (c["variant"] as? String) ?? "default"
        let p = palette
        let failures = checks(c, ctx)
        let press = ctx.interceptPress
        let enabled = press != nil || failures.isEmpty
        let contentColor = variant == "primary" ? p.onPrimary : p.primary
        var kid = textNode("")
        var childComponent: JSONObject?
        if let cid = c["child"] as? String {
            var cctx = ctx
            cctx.parent = "Button"
            cctx.contentColor = contentColor
            cctx.interceptPress = nil
            kid = child(cid, cctx)
            childComponent = surface.components[cid]
        }
        var label = accessibilityLabel(c, ctx)
        if label == nil {
            if let cc = childComponent, jsString(cc["component"]) == "Text" {
                label = plainText(parseMarkdown(str(ctx, cc["text"], present: cc.has("text"))))
            } else {
                label = ""
            }
        }
        let s: JSONObject
        switch variant {
        case "primary":
            s = style([("backgroundColor", p.primary), ("color", p.onPrimary), ("margin", LEAF_MARGIN)])
        case "borderless":
            s = style([("backgroundColor", "transparent"), ("color", p.primary), ("boxShadow", "0 0 0 0 rgba(0,0,0,0)"), ("padding", "0 12"), ("margin", LEAF_MARGIN)])
        default:
            s = style([("backgroundColor", p.surfaceContainer), ("color", p.primary), ("border", "1px solid \(p.outlineVariant)"), ("margin", LEAF_MARGIN)])
        }
        var events: [(String, ElpianEventListener)] = []
        if enabled {
            let hooks = self.hooks
            let surfaceId = surface.id
            let componentId = jsString(c["id"])
            let action = c["action"]
            let scope = ctx.scope
            events.append(("click", { e in
                handled(e)
                if let press = press { press() } else { hooks.action(surfaceId, componentId, action, scope) }
            }))
        }
        let text = label ?? ""
        return el("Button", JSONObject([("text", text.isEmpty ? "Button" : text), ("disabled", !enabled), ("style", s)]), [kid], key: key, events: events)
    }

    func textField(_ c: JSONObject, _ key: String, _ ctx: Ctx) -> JSONObject {
        let variant = (c["variant"] as? String) ?? "shortText"
        let label = str(ctx, c["label"], present: c.has("label"))
        let bind = binding(c["value"], ctx, key)
        let raw = bind.read(isBinding(c["value"]) ? nil : str(ctx, c["value"], present: c.has("value")))
        let value = stringifyValue(raw)
        var failures = checks(c, ctx)
        if let pattern = c["validationRegexp"] as? String, !value.isEmpty {
            var ok = true
            if let re = try? NSRegularExpression(pattern: pattern) {
                ok = re.firstMatch(in: value, options: [], range: NSRange(location: 0, length: value.utf16.count)) != nil
            }
            if !ok { failures.append("Invalid format") }
        }
        let showErrors = !failures.isEmpty && (touched(key) || !value.isEmpty)
        let p = palette
        let a11y = accessibilityLabel(c, ctx)
        let state = options.state
        let touchedKey = stateKey(key, "touched")
        let field = el("TextField", JSONObject([
            ("value", value),
            ("hint", a11y != nil && label.isEmpty ? a11y! : ""),
            ("obscureText", variant == "obscured"),
            ("multiline", variant == "longText"),
            ("maxLines", variant == "longText" ? 4.0 : 1.0),
            ("keyboardType", variant == "number" ? "number" : "text"),
            ("style", style([("color", p.onSurface)])),
        ]), [], key: "\(key)/input", events: [("input", { e in
            handled(e)
            state.set(touchedKey, true)
            bind.write(e.value == nil ? "" : jsString(e.value))
        })])
        var parts: [JSONObject] = []
        if !label.isEmpty { parts.append(self.label(label, showErrors ? p.error : nil)) }
        parts.append(field)
        parts += errorText(showErrors ? failures : [])
        return el("Column", JSONObject([("style", style([("alignItems", "stretch"), ("margin", LEAF_MARGIN)]))]), parts, key: key)
    }

    func checkBox(_ c: JSONObject, _ key: String, _ ctx: Ctx) -> JSONObject {
        let bind = binding(c["value"], ctx, key)
        let checked: Bool
        if isBinding(c["value"]) {
            checked = jsBool(bind.read(false)) == true
        } else {
            checked = jsBool(bind.read(eval(ctx, { try ctx.dc.boolean(c["value"]) }, false))) == true
        }
        let state = options.state
        let touchedKey = stateKey(key, "touched")
        let toggle: (Bool) -> Void = { v in
            state.set(touchedKey, true)
            bind.write(v)
        }
        let failures = checks(c, ctx)
        let showErrors = !failures.isEmpty && touched(key)
        let box = el("Checkbox", JSONObject([("value", checked), ("style", style([("color", palette.primary)]))]), [], key: "\(key)/box", events: [("change", { e in
            handled(e)
            toggle(jsTruthy(e.value))
        })])
        let labelNode = el("Container", JSONObject([("style", style([("cursor", "pointer"), ("padding", "0 4")]))]),
                           [textNode(str(ctx, c["label"], present: c.has("label")), style([("fontSize", 16.0)]))],
                           key: "\(key)/label", events: [("click", { e in
                               handled(e)
                               toggle(!checked)
                           })])
        let row = el("Row", JSONObject([("style", style([("alignItems", "center")]))]), [box, el("Flexible", JSONObject([("flex", 1.0), ("fit", "loose")]), [labelNode])])
        return el("Column", JSONObject([("style", style([("alignItems", "stretch"), ("margin", LEAF_MARGIN)]))]), [row] + errorText(showErrors ? failures : []), key: key)
    }

    func choicePicker(_ c: JSONObject, _ key: String, _ ctx: Ctx) -> JSONObject {
        let p = palette
        let multiple = (c["variant"] as? String) == "multipleSelection"
        let chips = (c["displayStyle"] as? String) == "chips"
        let bind = binding(c["value"], ctx, key)
        let current = bind.read(isBinding(c["value"]) ? nil : eval(ctx, { try ctx.dc.stringList(c["value"]) }, [String]()).map { $0 as Any? })
        var selected: [String] = []
        if let a = asArray(current) {
            selected = a.map { stringifyValue($0) }
        } else if let s = current as? String, !s.isEmpty {
            selected = [s]
        }
        struct Option {
            let value: String
            let label: String
        }
        let options: [Option] = (asArray(c["options"]) ?? []).compactMap { raw in
            guard let o = flattenOptional(raw) as? JSONObject, let value = o["value"] as? String else { return nil }
            let l = str(ctx, o["label"], present: o.has("label"))
            return Option(value: value, label: l.isEmpty ? value : l)
        }
        let filterKey = stateKey(key, "filter")
        let filterable = jsBool(c["filterable"]) == true
        let filter = filterable ? self.options.state.get(filterKey, "") : ""
        let visible = filter.isEmpty ? options : options.filter { $0.label.lowercased().contains(filter.lowercased()) }
        let state = self.options.state
        let hooks = self.hooks
        let touchedKey = stateKey(key, "touched")
        let choose: (String) -> Void = { value in
            state.set(touchedKey, true)
            if multiple {
                bind.write((selected.contains(value) ? selected.filter { $0 != value } : selected + [value]).map { $0 as Any? })
            } else {
                bind.write([value as Any?])
            }
        }
        var parts: [JSONObject] = []
        let label = str(ctx, c["label"], present: c.has("label"))
        if !label.isEmpty { parts.append(self.label(label)) }
        if filterable {
            parts.append(el("TextField", JSONObject([("value", filter), ("hint", "Filter options"), ("style", style([("color", p.onSurface)]))]), [],
                            key: "\(key)/filter", events: [("input", { e in
                                handled(e)
                                state.set(filterKey, e.value == nil ? "" : jsString(e.value))
                                hooks.invalidate()
                            })]))
        }
        if chips {
            let items = visible.map { o -> JSONObject in
                let on = selected.contains(o.value)
                var content: [JSONObject] = []
                if on { content.append(el("Icon", JSONObject([("icon", "check"), ("size", 18.0), ("style", style([("color", p.primary), ("margin", "0 6 0 0")]))]))) }
                content.append(textNode(o.label, style([("fontSize", 14.0), ("fontWeight", 500.0), ("color", on ? p.onSurface : p.onSurfaceVariant)])))
                return el("Container", JSONObject([("style", style([
                    ("padding", "6 14"), ("margin", 4.0), ("borderRadius", 8.0), ("border", "1px solid \(on ? p.primary : p.outline)"),
                    ("backgroundColor", on ? p.primaryContainer : "transparent"), ("cursor", "pointer"),
                ]))]), [el("Row", JSONObject([("style", style([("alignItems", "center")]))]), content)], key: "\(key)/opt/\(o.value)", events: [("click", { e in
                    handled(e)
                    choose(o.value)
                })])
            }
            parts.append(el("Wrap", JSONObject([("style", style([("gap", 0.0)]))]), items))
        } else {
            for o in visible {
                let on = selected.contains(o.value)
                let control: JSONObject
                if multiple {
                    control = el("Checkbox", JSONObject([("value", on), ("style", style([("color", p.primary)]))]), [], key: "\(key)/opt/\(o.value)", events: [("change", { e in
                        handled(e)
                        choose(o.value)
                    })])
                } else {
                    control = el("Radio", JSONObject([("value", o.value), ("groupValue", selected.first), ("style", style([("color", p.primary)]))]), [],
                                 key: "\(key)/opt/\(o.value)", events: [("change", { e in
                                     handled(e)
                                     choose(o.value)
                                 })])
                }
                let text = el("Container", JSONObject([("style", style([("cursor", "pointer"), ("padding", "0 4")]))]), [textNode(o.label, style([("fontSize", 16.0)]))],
                              key: "\(key)/optlabel/\(o.value)", events: [("click", { e in
                                  handled(e)
                                  choose(o.value)
                              })])
                parts.append(el("Row", JSONObject([("style", style([("alignItems", "center")]))]), [control, el("Flexible", JSONObject([("flex", 1.0), ("fit", "loose")]), [text])]))
            }
        }
        let failures = checks(c, ctx)
        parts += errorText(!failures.isEmpty && touched(key) ? failures : [])
        return el("Column", JSONObject([("style", style([("alignItems", "stretch"), ("margin", LEAF_MARGIN)]))]), parts, key: key)
    }

    func slider(_ c: JSONObject, _ key: String, _ ctx: Ctx) -> JSONObject {
        let p = palette
        let min = jsNumber(c["min"]) ?? 0
        let max = jsNumber(c["max"]).flatMap { $0 > min ? $0 : nil } ?? min + 100
        let bind = binding(c["value"], ctx, key)
        let raw = bind.read(isBinding(c["value"]) ? nil : eval(ctx, { try ctx.dc.number(c["value"]) }, min))
        var n = min
        if let x = jsNumber(raw) {
            n = x
        } else if let s = raw as? String, !jsTrim(s).isEmpty, jsToNumber(s).isFinite {
            n = jsToNumber(s)
        }
        let value = Swift.max(min, Swift.min(max, n))
        let label = str(ctx, c["label"], present: c.has("label"))
        let shown = value == value.rounded(.towardZero) ? jsNumberToString(value) : jsToFixed(value, abs(max - min) <= 1 ? 2 : 1)
        let header = el("Row", JSONObject([("style", style([("alignItems", "center"), ("justifyContent", "space-between")]))]), [
            el("Flexible", JSONObject([("flex", 1.0), ("fit", "loose")]), [textNode(label, style([("fontSize", 14.0), ("color", p.onSurfaceVariant)]))]),
            textNode(shown, style([("fontSize", 14.0), ("fontWeight", 600.0), ("color", p.onSurface)])),
        ])
        let slider = el("Slider", JSONObject([("min", min), ("max", max), ("value", value), ("style", style([("color", p.primary)]))]), [], key: "\(key)/slider",
                        events: [("change", { e in
                            handled(e)
                            let v = eventNumber(e.value)
                            if v.isFinite { bind.write(v) }
                        })])
        let failures = checks(c, ctx)
        return el("Column", JSONObject([("style", style([("alignItems", "stretch"), ("margin", LEAF_MARGIN)]))]), [header, slider] + errorText(failures), key: key)
    }

    func dateTime(_ c: JSONObject, _ key: String, _ ctx: Ctx) -> JSONObject {
        let p = palette
        let enableDate = jsBool(c["enableDate"]) == true
        let enableTime = jsBool(c["enableTime"]) == true
        let mode = enableDate && enableTime ? "datetime-local" : enableTime ? "time" : enableDate ? "date" : "datetime-local"
        let bind = binding(c["value"], ctx, key)
        let iso = stringifyValue(bind.read(isBinding(c["value"]) ? nil : str(ctx, c["value"], present: c.has("value"))))
        let label = str(ctx, c["label"], present: c.has("label"))
        let zone = ctx.dc.timeZone
        func bound(_ prop: String) -> Any? {
            guard c.has(prop) else { return nil }
            let v = isoToInput(str(ctx, c[prop]), mode, zone)
            return v.isEmpty ? nil : v
        }
        let state = options.state
        let touchedKey = stateKey(key, "touched")
        let field = el("TextField", JSONObject([
            ("value", isoToInput(iso, mode, zone)),
            ("keyboardType", mode),
            ("min", bound("min")),
            ("max", bound("max")),
            ("style", style([("color", p.onSurface)])),
        ]), [], key: "\(key)/input", events: [("input", { e in
            handled(e)
            state.set(touchedKey, true)
            bind.write(inputToIso(e.value == nil ? "" : jsString(e.value), mode))
        })])
        let failures = checks(c, ctx)
        var parts: [JSONObject] = []
        if !label.isEmpty { parts.append(self.label(label)) }
        parts.append(field)
        parts += errorText(!failures.isEmpty && touched(key) ? failures : [])
        return el("Column", JSONObject([("style", style([("alignItems", "stretch"), ("margin", LEAF_MARGIN)]))]), parts, key: key)
    }
}

private func pad2(_ n: Int) -> String { n < 10 ? "0\(n)" : String(n) }

private let TIME_PREFIX = JSRegex("^(\\d{2}):(\\d{2})")
private let DATE_ONLY_ISO = JSRegex("^(\\d{4}-\\d{2}-\\d{2})$")
private let LOCAL_DATE_TIME = JSRegex("^(\\d{4}-\\d{2}-\\d{2})T(\\d{2}):(\\d{2})(?::\\d{2}(?:\\.\\d+)?)?$")
private let HH_MM = JSRegex("^\\d{2}:\\d{2}$")
private let DATE_HH_MM = JSRegex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}$")

/** ISO 8601 (model) → the value a native date / time / datetime-local input shows (`mode`); absolute times read in [zone]. */
public func isoToInput(_ iso: String, _ mode: String, _ zone: TimeZone = .current) -> String {
    if iso.isEmpty { return "" }
    let s = jsTrim(iso)
    if mode == "time", let t = TIME_PREFIX.exec(s) { return "\(t[1]!):\(t[2]!)" }
    if let d = DATE_ONLY_ISO.exec(s) { return mode == "time" ? "" : mode == "date" ? d[1]! : "\(d[1]!)T00:00" }
    if let l = LOCAL_DATE_TIME.exec(s) {
        if mode == "date" { return l[1]! }
        if mode == "time" { return "\(l[2]!):\(l[3]!)" }
        return "\(l[1]!)T\(l[2]!):\(l[3]!)"
    }
    guard let d = parseDate(s, zone) else { return "" }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = zone
    let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: d)
    let year = String(c.year ?? 0)
    let date = "\(String(repeating: "0", count: max(0, 4 - year.count)))\(year)-\(pad2(c.month ?? 1))-\(pad2(c.day ?? 1))"
    let t = "\(pad2(c.hour ?? 0)):\(pad2(c.minute ?? 0))"
    return mode == "date" ? date : mode == "time" ? t : "\(date)T\(t)"
}

/** A native input's value → ISO 8601 for the data model. */
public func inputToIso(_ value: String, _ mode: String) -> String {
    let v = jsTrim(value)
    if v.isEmpty { return "" }
    if mode == "time" { return HH_MM.test(v) ? "\(v):00" : v }
    if mode == "datetime-local" { return DATE_HH_MM.test(v) ? "\(v):00" : v }
    return v
}
