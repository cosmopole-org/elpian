import Foundation

/**
 * The view protocol — the only thing a platform renderer has to understand
 * (render/view.ts).
 *
 * The core lays out the Elpian tree itself and emits a flat stream of
 * operations over a small set of primitive *view kinds*. The UIKit renderer
 * maps each kind onto a native view and applies the props. Frames are always
 * in logical pixels, relative to the parent view's top-left corner (a scroll
 * view's children are relative to its content origin).
 *
 * Every value in the protocol serializes to JSON (see [ViewOp.toJSON]), so a
 * renderer can also live behind a JSON bridge or in a test harness.
 */
public enum ViewKind: String, Equatable, Hashable, CaseIterable {
    /** A box: background, border, radius, shadows, clip, transform, opacity, gestures. */
    case view
    /** A laid-out paragraph of styled spans. */
    case text
    /** A bitmap from a URL / asset / data URI. */
    case image
    /** A scrolling container (children live in its content space). */
    case scroll
    /** Single- or multi-line editable text. */
    case textInput
    case checkbox
    case radio
    case `switch`
    case slider
    /** A dropdown / menu picker. */
    case select
    /** Linear or circular, determinate or not. */
    case progress
    /** A 2D canvas fed with Elpian canvas commands. */
    case canvas
    /** An embedded Godot viewport. */
    case scene3d
    case video
    case audio
    /** An embedded web page (iframe / embed / object). */
    case web
    /** A host-registered native component (a server-component island). */
    case native
}

public struct TextStyleSpec: Equatable, Hashable, JSONSerializable {
    public var color: Color
    public var fontSize: Double
    public var fontWeight: Int
    public var italic: Bool
    /** `nil` = the platform's default sans-serif; `serif`, `monospace`, `icons` or a family name. */
    public var fontFamily: String?
    public var letterSpacing: Double
    public var wordSpacing: Double
    /** Line height as a multiple of the font size (Flutter `height`); nil = font default. */
    public var height: Double?
    /** Bit flags: 1 underline, 2 overline, 4 line-through. */
    public var decoration: Int
    public var decorationColor: Color?
    public var decorationStyle: String?
    public var decorationThickness: Double?
    public var shadows: [TextShadow]?
    public var background: Color?
    /** Vertical shift in px (positive = down) for `sub` / `sup`. */
    public var baselineShift: Double

    public init(color: Color, fontSize: Double, fontWeight: Int, italic: Bool, fontFamily: String?, letterSpacing: Double, wordSpacing: Double,
                height: Double?, decoration: Int, decorationColor: Color?, decorationStyle: String?, decorationThickness: Double?,
                shadows: [TextShadow]?, background: Color?, baselineShift: Double) {
        self.color = color
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.italic = italic
        self.fontFamily = fontFamily
        self.letterSpacing = letterSpacing
        self.wordSpacing = wordSpacing
        self.height = height
        self.decoration = decoration
        self.decorationColor = decorationColor
        self.decorationStyle = decorationStyle
        self.decorationThickness = decorationThickness
        self.shadows = shadows
        self.background = background
        self.baselineShift = baselineShift
    }

    public func toJSON() -> Any? {
        JSONObject([
            ("color", color),
            ("fontSize", fontSize),
            ("fontWeight", Double(fontWeight)),
            ("italic", italic),
            ("fontFamily", fontFamily),
            ("letterSpacing", letterSpacing),
            ("wordSpacing", wordSpacing),
            ("height", height),
            ("decoration", Double(decoration)),
            ("decorationColor", decorationColor),
            ("decorationStyle", decorationStyle),
            ("decorationThickness", decorationThickness),
            ("shadows", shadows.map { $0.map { $0 as Any? } }),
            ("background", background),
            ("baselineShift", baselineShift),
        ])
    }
}

public struct TextSpanSpec: Equatable, Hashable, JSONSerializable {
    public var text: String
    public var style: TextStyleSpec
    /** Present when the span is tappable (a link inside rich text). */
    public var link: String?

    public init(text: String, style: TextStyleSpec, link: String? = nil) {
        self.text = text
        self.style = style
        self.link = link
    }

    public func toJSON() -> Any? {
        let o = JSONObject([("text", text), ("style", style)])
        if let link = link { o["link"] = link }
        return o
    }
}

public struct TextSpec: Equatable, Hashable, JSONSerializable {
    public var spans: [TextSpanSpec]
    /** `left`, `right`, `center`, `justify`, `start`, `end`. */
    public var align: String
    public var maxLines: Int?
    /** `clip`, `ellipsis`, `fade`, `visible`. */
    public var overflow: String
    public var softWrap: Bool
    public var selectable: Bool
    /** `ltr` or `rtl`. */
    public var direction: String

    public init(spans: [TextSpanSpec], align: String = "start", maxLines: Int? = nil, overflow: String = "clip",
                softWrap: Bool = true, selectable: Bool = false, direction: String = "ltr") {
        self.spans = spans
        self.align = align
        self.maxLines = maxLines
        self.overflow = overflow
        self.softWrap = softWrap
        self.selectable = selectable
        self.direction = direction
    }

    public func toJSON() -> Any? {
        JSONObject([
            ("spans", spans.map { $0 as Any? }),
            ("align", align),
            ("maxLines", maxLines.map { Double($0) }),
            ("overflow", overflow),
            ("softWrap", softWrap),
            ("selectable", selectable),
            ("direction", direction),
        ])
    }
}

public struct TextMetrics: Equatable, Hashable, JSONSerializable {
    public var width: Double
    public var height: Double
    /** Distance from the top to the first line's alphabetic baseline. */
    public var baseline: Double
    public var lineCount: Int
    /** True when maxLines/overflow cut the text. */
    public var didExceedMaxLines: Bool

    public init(width: Double, height: Double, baseline: Double, lineCount: Int, didExceedMaxLines: Bool) {
        self.width = width
        self.height = height
        self.baseline = baseline
        self.lineCount = lineCount
        self.didExceedMaxLines = didExceedMaxLines
    }

    public func toJSON() -> Any? {
        JSONObject([("width", width), ("height", height), ("baseline", baseline), ("lineCount", Double(lineCount)), ("didExceedMaxLines", didExceedMaxLines)])
    }
}

/** Sizes a native control the core cannot measure itself. */
public struct ControlMeasureSpec {
    public var kind: ViewKind
    public var props: JSONObject

    public init(kind: ViewKind, props: JSONObject) {
        self.kind = kind
        self.props = props
    }
}

/** Gestures a view should recognise and report back with `dispatch`. */
public enum GestureKind: String, Equatable, Hashable, CaseIterable {
    case tap, doubletap, longpress, tapdown, tapup, tapcancel
    /** dragstart / drag / dragend */
    case pan
    case swipe
    /** pointerdown / up / move / cancel */
    case pointer
    /** pointerenter / exit / hover */
    case hover
    /** pinch / rotate */
    case scale
    /** keyboard while focused */
    case key
    /** focus / blur */
    case focus
    /** swipe-to-dismiss (Dismissible) */
    case dismiss
    /** long-press/drag with a floating feedback copy (Draggable) */
    case draggable
    /** report scroll offsets */
    case scroll
}

/**
 * The visual and behavioural properties of one view: a JSON bag keyed by the
 * TypeScript `ViewProps` names (`frame`, `background`, `gradients`, `border`,
 * `radius`, `oval`, `shadows`, `opacity`, `transform`, `clip`, `gestures`,
 * `text`, `src`, `scrollAxis`, `value`, `commands`, …). Absent = unset/default.
 * Values are typed ([Color] numbers, [Gradient], [Border], [TextSpec] …).
 */
public typealias ViewProps = JSONObject

/** Every documented `ViewProps` key (render/view.ts), for renderers that switch over them. */
public enum ViewPropKey {
    public static let frame = "frame"
    public static let background = "background"
    public static let gradients = "gradients"
    public static let backgroundImage = "backgroundImage"
    public static let border = "border"
    public static let radius = "radius"
    public static let oval = "oval"
    public static let shadows = "shadows"
    public static let outline = "outline"
    public static let opacity = "opacity"
    public static let transform = "transform"
    public static let transformOrigin = "transformOrigin"
    public static let clip = "clip"
    public static let hidden = "hidden"
    public static let pointerEvents = "pointerEvents"
    public static let cursor = "cursor"
    public static let filter = "filter"
    public static let backdropFilter = "backdropFilter"
    public static let shaderMask = "shaderMask"
    public static let blendMode = "blendMode"
    public static let zIndex = "zIndex"
    public static let gestures = "gestures"
    public static let ripple = "ripple"
    public static let focusable = "focusable"
    public static let tooltip = "tooltip"
    public static let semanticsLabel = "semanticsLabel"
    public static let role = "role"
    public static let dragData = "dragData"
    public static let dismissDirection = "dismissDirection"
    public static let text = "text"
    public static let src = "src"
    public static let fit = "fit"
    public static let alignment = "alignment"
    public static let alt = "alt"
    public static let tint = "tint"
    public static let scrollAxis = "scrollAxis"
    public static let contentSize = "contentSize"
    public static let scrollEnabled = "scrollEnabled"
    public static let showScrollbar = "showScrollbar"
    public static let scrollTo = "scrollTo"
    public static let value = "value"
    public static let checked = "checked"
    public static let enabled = "enabled"
    public static let placeholder = "placeholder"
    public static let inputType = "inputType"
    public static let multiline = "multiline"
    public static let minLines = "minLines"
    public static let maxLines = "maxLines"
    public static let maxLength = "maxLength"
    public static let readOnly = "readOnly"
    public static let autofocus = "autofocus"
    public static let suggestions = "suggestions"
    public static let options = "options"
    public static let min = "min"
    public static let max = "max"
    public static let step = "step"
    public static let colors = "colors"
    public static let textStyle = "textStyle"
    public static let hintStyle = "hintStyle"
    public static let contentPadding = "contentPadding"
    public static let variant = "variant"
    public static let strokeWidth = "strokeWidth"
    public static let commands = "commands"
    public static let appendCommands = "appendCommands"
    public static let canvasVersion = "canvasVersion"
    public static let surfaceId = "surfaceId"
    public static let clickable = "clickable"
    public static let autoplay = "autoplay"
    public static let loop = "loop"
    public static let muted = "muted"
    public static let controls = "controls"
    public static let poster = "poster"
    public static let tracks = "tracks"
    public static let html = "html"
    public static let javascript = "javascript"
    public static let component = "component"
    public static let componentProps = "componentProps"
}

public enum ViewOp: JSONSerializable {
    case create(id: Int, kind: ViewKind, parent: Int, index: Int, props: ViewProps)
    case update(id: Int, props: ViewProps)
    case move(id: Int, parent: Int, index: Int)
    case remove(id: Int)
    case command(id: Int, name: String, args: Any?)

    public var id: Int {
        switch self {
        case .create(let id, _, _, _, _), .update(let id, _), .move(let id, _, _), .remove(let id), .command(let id, _, _): return id
        }
    }

    public func toJSON() -> Any? {
        switch self {
        case let .create(id, kind, parent, index, props):
            return JSONObject([("op", "create"), ("id", Double(id)), ("kind", kind.rawValue), ("parent", Double(parent)), ("index", Double(index)), ("props", props)])
        case let .update(id, props):
            return JSONObject([("op", "update"), ("id", Double(id)), ("props", props)])
        case let .move(id, parent, index):
            return JSONObject([("op", "move"), ("id", Double(id)), ("parent", Double(parent)), ("index", Double(index))])
        case let .remove(id):
            return JSONObject([("op", "remove"), ("id", Double(id))])
        case let .command(id, name, args):
            let o = JSONObject([("op", "command"), ("id", Double(id)), ("name", name)])
            if let a = flattenOptional(args) { o["args"] = a }
            return o
        }
    }
}

/** The id of the platform-owned root container every top-level view is created in. */
public let ROOT_VIEW_ID = 0

/**
 * An event a platform reports back for a view: tap, doubletap, longpress,
 * tapdown, tapup, tapcancel, dragstart, drag, dragend, swipe, pointerdown,
 * pointerup, pointermove, pointercancel, pointerenter, pointerexit,
 * pointerhover, scalestart, scaleupdate, scaleend, keydown, keyup, focus,
 * blur, change, input, submit, scroll, dismissed, dragaccept, load, error,
 * play, pause, ended, timeupdate, signal …
 */
public struct ViewEvent {
    public var id: Int
    public var type: String
    public var x: Double?
    public var y: Double?
    public var localX: Double?
    public var localY: Double?
    public var dx: Double?
    public var dy: Double?
    public var vx: Double?
    public var vy: Double?
    public var scale: Double?
    public var rotation: Double?
    public var buttons: Int?
    public var pressure: Double?
    public var pointerId: Int?
    public var key: String?
    public var keyCode: Int?
    public var altKey: Bool?
    public var ctrlKey: Bool?
    public var shiftKey: Bool?
    public var metaKey: Bool?
    public var value: Any?
    public var scrollX: Double?
    public var scrollY: Double?
    public var direction: String?
    public var data: Any?

    public init(id: Int, type: String, x: Double? = nil, y: Double? = nil, localX: Double? = nil, localY: Double? = nil,
                dx: Double? = nil, dy: Double? = nil, vx: Double? = nil, vy: Double? = nil, scale: Double? = nil, rotation: Double? = nil,
                buttons: Int? = nil, pressure: Double? = nil, pointerId: Int? = nil, key: String? = nil, keyCode: Int? = nil,
                altKey: Bool? = nil, ctrlKey: Bool? = nil, shiftKey: Bool? = nil, metaKey: Bool? = nil, value: Any? = nil,
                scrollX: Double? = nil, scrollY: Double? = nil, direction: String? = nil, data: Any? = nil) {
        self.id = id
        self.type = type
        self.x = x
        self.y = y
        self.localX = localX
        self.localY = localY
        self.dx = dx
        self.dy = dy
        self.vx = vx
        self.vy = vy
        self.scale = scale
        self.rotation = rotation
        self.buttons = buttons
        self.pressure = pressure
        self.pointerId = pointerId
        self.key = key
        self.keyCode = keyCode
        self.altKey = altKey
        self.ctrlKey = ctrlKey
        self.shiftKey = shiftKey
        self.metaKey = metaKey
        self.value = value
        self.scrollX = scrollX
        self.scrollY = scrollY
        self.direction = direction
        self.data = data
    }

    /** From the JSON form a bridged renderer sends. */
    public init?(json: JSONObject) {
        guard let id = jsNumber(json["id"]), let type = json["type"] as? String else { return nil }
        func d(_ k: String) -> Double? { jsNumber(json[k]) }
        func i(_ k: String) -> Int? { jsNumber(json[k]).map { Int($0) } }
        func b(_ k: String) -> Bool? { jsBool(json[k]) }
        self.init(id: Int(id), type: type, x: d("x"), y: d("y"), localX: d("localX"), localY: d("localY"), dx: d("dx"), dy: d("dy"),
                  vx: d("vx"), vy: d("vy"), scale: d("scale"), rotation: d("rotation"), buttons: i("buttons"), pressure: d("pressure"),
                  pointerId: i("pointerId"), key: json["key"] as? String, keyCode: i("keyCode"), altKey: b("altKey"), ctrlKey: b("ctrlKey"),
                  shiftKey: b("shiftKey"), metaKey: b("metaKey"), value: json["value"], scrollX: d("scrollX"), scrollY: d("scrollY"),
                  direction: json["direction"] as? String, data: json["data"])
    }
}
