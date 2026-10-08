import Foundation

/**
 * Canvas command model and the per-mini-app context store (canvas/store.ts) —
 * a port of `CanvasCommand`, `CanvasAPIExecutor`'s command list and
 * `CanvasContextStore`.
 *
 * The core never rasterises: it normalises commands (colours to ARGB,
 * defaults filled in, fonts parsed) and hands the list to the platform
 * painter (Canvas2D on the web, android.graphics.Canvas, CoreGraphics), which
 * implements the full HTML-canvas-like semantics — including the commands
 * the Flutter executor leaves unhandled (drawImage, polygons, setTransform,
 * patterns, pixel data, arcTo with tangents).
 */
public let CANVAS_COMMAND_TYPES: [String] = [
    "moveTo", "lineTo", "quadraticCurveTo", "bezierCurveTo", "arc", "arcTo", "ellipse", "rect", "roundRect",
    "circle", "fillRect", "strokeRect", "clearRect", "fillCircle", "strokeCircle", "fillPolygon", "strokePolygon",
    "fillText", "strokeText", "drawImage", "drawImageRect",
    "beginPath", "closePath", "fill", "stroke", "clip",
    "save", "restore", "translate", "rotate", "scale", "transform", "setTransform", "resetTransform",
    "setFillStyle", "setStrokeStyle", "setLineWidth", "setLineCap", "setLineJoin", "setMiterLimit", "setLineDash",
    "setLineDashOffset", "setShadowBlur", "setShadowColor", "setShadowOffsetX", "setShadowOffsetY", "setGlobalAlpha",
    "setGlobalCompositeOperation", "setFont", "setTextAlign", "setTextBaseline",
    "createLinearGradient", "createRadialGradient", "addColorStop", "createPattern",
    "putImageData", "getImageData", "createImageData", "custom",
]

/** A canvas command: [type] is one of [CANVAS_COMMAND_TYPES]. */
public struct CanvasCommand: JSONSerializable {
    public var type: String
    public var params: JSONObject
    public var id: String?

    public init(type: String, params: JSONObject = JSONObject(), id: String? = nil) {
        self.type = type
        self.params = params
        self.id = id
    }

    public func toJSON() -> Any? { JSONObject([("type", type), ("params", params), ("id", id)]) }
}

private let TYPES = Set(CANVAS_COMMAND_TYPES)

public func isCanvasCommandType(_ name: String) -> Bool { TYPES.contains(name) }

/** `CanvasCommand.fromJson` (unknown types become `custom`). */
public func commandFromJson(_ json: Any?) -> CanvasCommand {
    let m = asMap(json)
    let rawType = m?["type"] as? String
    let t = rawType != nil && TYPES.contains(rawType!) ? rawType! : "custom"
    let params = JSONObject()
    let raw = m?["params"]
    if let pm = asMap(raw) {
        for (k, v) in pm { params[k] = v }
    } else if let pa = asArray(raw) {
        // `{ ...array }` spreads indices as keys.
        for (i, v) in pa.enumerated() { params[String(i)] = v }
    }
    let rawId = m?["id"]
    let id: String? = rawId == nil ? nil : (rawId as? String ?? jsString(rawId))
    return CanvasCommand(type: t, params: params, id: id)
}

private let COLOR_KEYS = ["color", "shadowColor"]
private let NUMERIC = JSRegex("^-?\\d+(\\.\\d+)?$")
private let NON_NUMERIC_KEYS = ["text", "font", "id", "gradientId", "patternId", "src", "imageId", "data"]

/**
 * Normalise a command for the platform painter: colours to ARGB ints (the
 * Flutter parser's rules), gradient colour lists, numeric strings to numbers.
 * The result is a JSON object `{type, params, id?}`, the same shape as
 * inline command lists.
 */
public func normalizeCommand(_ cmd: CanvasCommand) -> JSONObject {
    let p = JSONObject()
    for (k, v) in cmd.params {
        if COLOR_KEYS.contains(k) {
            p[k] = Double(canvasColor(v))
        } else if k == "colors", let list = asArray(v) {
            p[k] = list.map { Double(canvasColor($0)) as Any? }
        } else if let s = v as? String, NUMERIC.test(jsTrim(s)), !NON_NUMERIC_KEYS.contains(k) {
            p[k] = jsParseFloat(s)
        } else {
            p[k] = v
        }
    }
    let out = JSONObject([("type", cmd.type), ("params", p)])
    if let id = cmd.id, !id.isEmpty { out["id"] = id }
    return out
}

/** Canvas colours: the canvas executor's own parser (hex, rgb/rgba, ints), falling back to CSS. */
public func canvasColor(_ value: Any?) -> Color {
    if let d = jsNumber(value) {
        // JavaScript `>>> 0`: non-finite values become 0, others wrap to 32 bits.
        return jsToUint32(d)
    }
    return parseColor(value) ?? 0xFF00_0000
}

/** A cached drawing context (`canvas.ctx.*`), rendered by `CachedCanvas`. */
public final class CanvasContext {
    public let id: String
    public var width: Double
    public var height: Double
    /** Every command ever added since the last clear (normalised, see [normalizeCommand]). */
    public var commands: [JSONObject] = []
    /** Bumped on every change (Flutter's `version` notifier). */
    public var version = 0
    /** Bumped when the command list is reset (clear / resize) — painters redraw from scratch. */
    public var generation = 0
    private var listeners: [(id: Int, fn: () -> Void)] = []
    private var nextListenerId = 1

    public init(_ id: String, _ width: Double, _ height: Double) {
        self.id = id
        self.width = width
        self.height = height
    }

    public func setSize(_ w: Double, _ h: Double) {
        if w == width && h == height { return }
        width = w
        height = h
        generation += 1
        changed()
    }

    public func addCommand(_ cmd: CanvasCommand) {
        commands.append(normalizeCommand(cmd))
        changed()
    }

    public func addCommands(_ cmds: [CanvasCommand]) {
        for c in cmds { commands.append(normalizeCommand(c)) }
        changed()
    }

    public func clear() {
        commands = []
        generation += 1
        changed()
    }

    /** Listen for changes; returns the unsubscriber. */
    @discardableResult
    public func onChange(_ fn: @escaping () -> Void) -> () -> Void {
        let id = nextListenerId
        nextListenerId += 1
        listeners.append((id, fn))
        return { [weak self] in self?.listeners.removeAll { $0.id == id } }
    }

    private func changed() {
        version += 1
        for l in listeners { l.fn() }
    }

    public func dispose() {
        listeners.removeAll()
        commands = []
    }
}

public final class CanvasContextStore {
    private var contexts: [String: CanvasContext] = [:]
    private var order: [String] = []
    private var nextId = 1

    public init() {}

    public func create(id: String? = nil, width: Double? = nil, height: Double? = nil) -> CanvasContext {
        let key: String
        if let id = id, !id.isEmpty {
            key = id
        } else {
            key = "ctx_\(nextId)"
            nextId += 1
        }
        if let existing = contexts[key] { return existing }
        let ctx = CanvasContext(key, width ?? 0, height ?? 0)
        contexts[key] = ctx
        order.append(key)
        return ctx
    }

    public func get(_ id: String) -> CanvasContext? { contexts[id] }

    public subscript(id: String) -> CanvasContext? { contexts[id] }

    public func dispose(_ id: String) {
        let ctx = contexts.removeValue(forKey: id)
        order.removeAll { $0 == id }
        ctx?.dispose()
    }

    public func clearAll() {
        for key in order { contexts[key]?.dispose() }
        contexts.removeAll()
        order.removeAll()
    }
}

/** The single, context-less command list of the `canvas.*` host APIs (`CanvasAPIExecutor`). */
public final class CanvasExecutor {
    public var commands: [CanvasCommand] = []

    public init() {}

    public func addCommand(_ cmd: CanvasCommand) {
        commands.append(cmd)
    }

    public func addCommands(_ cmds: [CanvasCommand]) {
        commands.append(contentsOf: cmds)
    }

    public func clear() {
        commands = []
    }
}

public struct ParsedCanvasFont: Equatable {
    public var size: Double
    public var family: String
    public var bold: Bool
    public var italic: Bool
}

private let THREE_DIGITS = JSRegex("^\\d{3}$")
private let BOLD = JSRegex("bold|[6-9]00")

/** Parse a CSS-ish canvas font (`bold italic 16px Arial`), as `_ParsedFont.parse` does. */
public func parseCanvasFont(_ font: String) -> ParsedCanvasFont {
    var size = 10.0
    var family = "sans-serif"
    let parts = jsSplit(font, " ")
    for i in parts.indices {
        let part = parts[i]
        if part.hasSuffix("px") {
            let v = jsParseFloat(part)
            size = v.isNaN || v == 0 ? 10 : v
        } else if !part.contains("bold") && !part.contains("italic") && jsTrim(part) != "" && !THREE_DIGITS.test(part) {
            family = parts[i...].joined(separator: " ")
            break
        }
    }
    return ParsedCanvasFont(size: size, family: family, bold: BOLD.test(font), italic: font.contains("italic"))
}
