import Foundation

/**
 * Value types of the resolved style model (css/types.ts). These mirror the
 * Flutter painting primitives (`EdgeInsets`, `Alignment`, `BorderSide`,
 * `BoxShadow`, gradients, `Matrix4`) so the lowering code can be written
 * against the same vocabulary as the Flutter widgets it ports. Every type
 * serializes to the same JSON shape as its TypeScript twin.
 */

public struct EdgeInsets: Equatable, Hashable, JSONSerializable {
    public var top: Double
    public var right: Double
    public var bottom: Double
    public var left: Double

    public init(top: Double = 0, right: Double = 0, bottom: Double = 0, left: Double = 0) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    public static let zero = EdgeInsets()
    public static func all(_ v: Double) -> EdgeInsets { EdgeInsets(top: v, right: v, bottom: v, left: v) }
    public static func symmetric(vertical: Double = 0, horizontal: Double = 0) -> EdgeInsets {
        EdgeInsets(top: vertical, right: horizontal, bottom: vertical, left: horizontal)
    }
    public static func only(top: Double = 0, right: Double = 0, bottom: Double = 0, left: Double = 0) -> EdgeInsets {
        EdgeInsets(top: top, right: right, bottom: bottom, left: left)
    }

    public var horizontal: Double { left + right }
    public var vertical: Double { top + bottom }
    public var isZero: Bool { top == 0 && right == 0 && bottom == 0 && left == 0 }

    public static func + (a: EdgeInsets, b: EdgeInsets) -> EdgeInsets {
        EdgeInsets(top: a.top + b.top, right: a.right + b.right, bottom: a.bottom + b.bottom, left: a.left + b.left)
    }

    public static func lerp(_ a: EdgeInsets, _ b: EdgeInsets, _ t: Double) -> EdgeInsets {
        func l(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        return EdgeInsets(top: l(a.top, b.top), right: l(a.right, b.right), bottom: l(a.bottom, b.bottom), left: l(a.left, b.left))
    }

    public func toJSON() -> Any? { JSONObject([("top", top), ("right", right), ("bottom", bottom), ("left", left)]) }
}

public let EdgeInsetsZero = EdgeInsets.zero
public func insetsAll(_ v: Double) -> EdgeInsets { .all(v) }
public func insetsSymmetric(_ vertical: Double, _ horizontal: Double) -> EdgeInsets { .symmetric(vertical: vertical, horizontal: horizontal) }
public func insetsOnly(top: Double? = nil, right: Double? = nil, bottom: Double? = nil, left: Double? = nil) -> EdgeInsets {
    EdgeInsets(top: top ?? 0, right: right ?? 0, bottom: bottom ?? 0, left: left ?? 0)
}
public func horizontalOf(_ e: EdgeInsets) -> Double { e.left + e.right }
public func verticalOf(_ e: EdgeInsets) -> Double { e.top + e.bottom }
public func addInsets(_ a: EdgeInsets, _ b: EdgeInsets) -> EdgeInsets { a + b }
public func lerpInsets(_ a: EdgeInsets, _ b: EdgeInsets, _ t: Double) -> EdgeInsets { .lerp(a, b, t) }

/** Flutter `Alignment`: x and y in -1..1, (0,0) is the centre. */
public struct Alignment: Equatable, Hashable, JSONSerializable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let topLeft = Alignment(x: -1, y: -1)
    public static let topCenter = Alignment(x: 0, y: -1)
    public static let topRight = Alignment(x: 1, y: -1)
    public static let centerLeft = Alignment(x: -1, y: 0)
    public static let center = Alignment(x: 0, y: 0)
    public static let centerRight = Alignment(x: 1, y: 0)
    public static let bottomLeft = Alignment(x: -1, y: 1)
    public static let bottomCenter = Alignment(x: 0, y: 1)
    public static let bottomRight = Alignment(x: 1, y: 1)

    public static func lerp(_ a: Alignment, _ b: Alignment, _ t: Double) -> Alignment {
        Alignment(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    public func toJSON() -> Any? { JSONObject([("x", x), ("y", y)]) }
}

/** The TypeScript `Align` table. */
public typealias Align = Alignment
public func lerpAlignment(_ a: Alignment, _ b: Alignment, _ t: Double) -> Alignment { .lerp(a, b, t) }

public struct Offset: Equatable, Hashable, JSONSerializable {
    public var dx: Double
    public var dy: Double

    public init(dx: Double, dy: Double) {
        self.dx = dx
        self.dy = dy
    }

    public func toJSON() -> Any? { JSONObject([("dx", dx), ("dy", dy)]) }
}

public enum BorderStyleName: String, Equatable, Hashable, CaseIterable {
    case solid, dashed, dotted, double, none
}

public struct BorderSide: Equatable, Hashable, JSONSerializable {
    public var width: Double
    public var color: Color
    public var style: BorderStyleName

    public init(width: Double, color: Color, style: BorderStyleName = .solid) {
        self.width = width
        self.color = color
        self.style = style
    }

    public static let none = BorderSide(width: 0, color: 0xFF00_0000, style: .none)

    public func toJSON() -> Any? { JSONObject([("width", width), ("color", color), ("style", style.rawValue)]) }
}

public let BorderSideNone = BorderSide.none

public struct Border: Equatable, Hashable, JSONSerializable {
    public var top: BorderSide
    public var right: BorderSide
    public var bottom: BorderSide
    public var left: BorderSide

    public init(top: BorderSide, right: BorderSide, bottom: BorderSide, left: BorderSide) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    public static func all(_ side: BorderSide) -> Border { Border(top: side, right: side, bottom: side, left: side) }

    public var isUniform: Bool { top == right && right == bottom && bottom == left }

    /** The insets the border takes up (Container adds them to its padding). */
    public var insets: EdgeInsets {
        func w(_ s: BorderSide) -> Double { s.style == .none ? 0 : s.width }
        return EdgeInsets(top: w(top), right: w(right), bottom: w(bottom), left: w(left))
    }

    public func toJSON() -> Any? {
        JSONObject([("top", top.toJSON()), ("right", right.toJSON()), ("bottom", bottom.toJSON()), ("left", left.toJSON())])
    }
}

public func borderAll(_ side: BorderSide) -> Border { .all(side) }
public func borderInsets(_ b: Border?) -> EdgeInsets { b?.insets ?? .zero }

/** Per-corner circular radii, Flutter `BorderRadius`. */
public struct BorderRadius: Equatable, Hashable, JSONSerializable {
    public var topLeft: Double
    public var topRight: Double
    public var bottomRight: Double
    public var bottomLeft: Double

    public init(topLeft: Double, topRight: Double, bottomRight: Double, bottomLeft: Double) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    public static let zero = BorderRadius(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)
    public static func all(_ r: Double) -> BorderRadius { BorderRadius(topLeft: r, topRight: r, bottomRight: r, bottomLeft: r) }
    public var isZero: Bool { topLeft == 0 && topRight == 0 && bottomRight == 0 && bottomLeft == 0 }

    public static func lerp(_ a: BorderRadius, _ b: BorderRadius, _ t: Double) -> BorderRadius {
        func l(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        return BorderRadius(topLeft: l(a.topLeft, b.topLeft), topRight: l(a.topRight, b.topRight), bottomRight: l(a.bottomRight, b.bottomRight), bottomLeft: l(a.bottomLeft, b.bottomLeft))
    }

    /** Corner by its TypeScript key (`topLeft`, …). */
    public subscript(corner: Int) -> Double {
        get { [topLeft, topRight, bottomRight, bottomLeft][corner] }
        set {
            switch corner {
            case 0: topLeft = newValue
            case 1: topRight = newValue
            case 2: bottomRight = newValue
            default: bottomLeft = newValue
            }
        }
    }

    public func toJSON() -> Any? {
        JSONObject([("topLeft", topLeft), ("topRight", topRight), ("bottomRight", bottomRight), ("bottomLeft", bottomLeft)])
    }
}

public func radiusAll(_ r: Double) -> BorderRadius { .all(r) }
public func lerpRadius(_ a: BorderRadius, _ b: BorderRadius, _ t: Double) -> BorderRadius { .lerp(a, b, t) }

public struct BoxShadow: Equatable, Hashable, JSONSerializable {
    public var color: Color
    public var dx: Double
    public var dy: Double
    public var blur: Double
    public var spread: Double
    public var inset: Bool?

    public init(color: Color, dx: Double, dy: Double, blur: Double, spread: Double = 0, inset: Bool? = nil) {
        self.color = color
        self.dx = dx
        self.dy = dy
        self.blur = blur
        self.spread = spread
        self.inset = inset
    }

    public func toJSON() -> Any? {
        let o = JSONObject([("color", color), ("dx", dx), ("dy", dy), ("blur", blur), ("spread", spread)])
        if let inset = inset { o["inset"] = inset }
        return o
    }
}

public struct TextShadow: Equatable, Hashable, JSONSerializable {
    public var color: Color
    public var dx: Double
    public var dy: Double
    public var blur: Double

    public init(color: Color, dx: Double, dy: Double, blur: Double) {
        self.color = color
        self.dx = dx
        self.dy = dy
        self.blur = blur
    }

    public func toJSON() -> Any? { JSONObject([("color", color), ("dx", dx), ("dy", dy), ("blur", blur)]) }
}

public enum GradientKind: String, Equatable, Hashable {
    case linear, radial, sweep
}

/**
 * Gradients in Flutter's vocabulary. Linear gradients run from [begin] to
 * [end] (alignments within the painted box); radial ones are centred on
 * [center] with [radius] as a fraction of the shortest side (Flutter's
 * `RadialGradient.radius`, default 0.5); sweep gradients turn around
 * [center] from [startAngle] to [endAngle] (radians).
 */
public struct Gradient: Equatable, Hashable, JSONSerializable {
    public var kind: GradientKind
    public var colors: [Color]
    public var stops: [Double]?
    public var begin: Alignment?
    public var end: Alignment?
    public var center: Alignment?
    public var radius: Double?
    public var startAngle: Double?
    public var endAngle: Double?
    /** CSS `repeating-*` / Flutter `TileMode.repeated`. */
    public var `repeat`: Bool?

    public init(kind: GradientKind, colors: [Color], stops: [Double]? = nil, begin: Alignment? = nil, end: Alignment? = nil,
                center: Alignment? = nil, radius: Double? = nil, startAngle: Double? = nil, endAngle: Double? = nil, repeat: Bool? = nil) {
        self.kind = kind
        self.colors = colors
        self.stops = stops
        self.begin = begin
        self.end = end
        self.center = center
        self.radius = radius
        self.startAngle = startAngle
        self.endAngle = endAngle
        self.repeat = `repeat`
    }

    /** Stops, evenly spread when absent or mismatched. */
    public func resolvedStops() -> [Double] {
        if let stops = stops, stops.count == colors.count { return stops }
        let n = colors.count
        return (0..<n).map { n > 1 ? Double($0) / Double(n - 1) : 0 }
    }

    public func toJSON() -> Any? {
        let o = JSONObject([("kind", kind.rawValue), ("colors", colors.map { $0 as Any? })])
        o["stops"] = stops.map { $0.map { $0 as Any? } }
        if let begin = begin { o["begin"] = begin }
        if let end = end { o["end"] = end }
        if let center = center { o["center"] = center }
        if let radius = radius { o["radius"] = radius }
        if let startAngle = startAngle { o["startAngle"] = startAngle }
        if let endAngle = endAngle { o["endAngle"] = endAngle }
        if let r = `repeat` { o["repeat"] = r }
        return o
    }
}

/** A 4x4 matrix in Flutter's column-major `Matrix4.storage` order. */
public typealias Matrix4 = [Double]

public let IDENTITY: Matrix4 = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]

/** `visible`, `hidden`, `clip` or `scroll`. */
public typealias Overflow = String

/** `left`, `right`, `center`, `justify`, `start`, `end`. */
public typealias TextAlign = String

public struct TextDecoration: Equatable, Hashable, JSONSerializable {
    public var underline: Bool
    public var overline: Bool
    public var lineThrough: Bool

    public init(underline: Bool = false, overline: Bool = false, lineThrough: Bool = false) {
        self.underline = underline
        self.overline = overline
        self.lineThrough = lineThrough
    }

    public var isNone: Bool { !underline && !overline && !lineThrough }

    public func toJSON() -> Any? { JSONObject([("underline", underline), ("overline", overline), ("lineThrough", lineThrough)]) }
}

public enum BoxFit: String, Equatable, Hashable, CaseIterable {
    case fill, contain, cover, fitWidth, fitHeight, none, scaleDown
}

public enum TextOverflow: String, Equatable, Hashable, CaseIterable {
    case clip, ellipsis, fade, visible
}

public struct Filter: Equatable, Hashable, JSONSerializable {
    public var blur: Double?
    public var brightness: Double?
    public var contrast: Double?
    public var grayscale: Double?
    public var hueRotate: Double?
    public var invert: Double?
    public var saturate: Double?
    public var sepia: Double?
    public var opacity: Double?
    public var dropShadow: TextShadow?

    public init(blur: Double? = nil, brightness: Double? = nil, contrast: Double? = nil, grayscale: Double? = nil, hueRotate: Double? = nil,
                invert: Double? = nil, saturate: Double? = nil, sepia: Double? = nil, opacity: Double? = nil, dropShadow: TextShadow? = nil) {
        self.blur = blur
        self.brightness = brightness
        self.contrast = contrast
        self.grayscale = grayscale
        self.hueRotate = hueRotate
        self.invert = invert
        self.saturate = saturate
        self.sepia = sepia
        self.opacity = opacity
        self.dropShadow = dropShadow
    }

    public var isEmpty: Bool { self == Filter() }

    public func toJSON() -> Any? {
        let o = JSONObject()
        if let v = blur { o["blur"] = v }
        if let v = brightness { o["brightness"] = v }
        if let v = contrast { o["contrast"] = v }
        if let v = grayscale { o["grayscale"] = v }
        if let v = hueRotate { o["hueRotate"] = v }
        if let v = invert { o["invert"] = v }
        if let v = saturate { o["saturate"] = v }
        if let v = sepia { o["sepia"] = v }
        if let v = opacity { o["opacity"] = v }
        if let v = dropShadow { o["dropShadow"] = v }
        return o
    }
}

public struct Keyframe: JSONSerializable {
    public var offset: Double
    public var styles: JSONObject

    public init(offset: Double, styles: JSONObject) {
        self.offset = offset
        self.styles = styles
    }

    public func toJSON() -> Any? { JSONObject([("offset", offset), ("styles", styles)]) }
}

/** A percentage of the parent's size, kept symbolic until layout (CSS `%`). */
public struct Percent: Equatable, Hashable, JSONSerializable {
    public var pct: Double
    public init(pct: Double) { self.pct = pct }
    public init(_ pct: Double) { self.pct = pct }
    public func toJSON() -> Any? { JSONObject([("pct", pct)]) }
}

/** A CSS length: absolute px or a [Percent]. */
public enum Length: Equatable, Hashable, JSONSerializable {
    case px(Double)
    case pct(Double)

    public func resolve(_ basis: Double) -> Double? {
        switch self {
        case .px(let v): return v
        case .pct(let p): return basis.isFinite ? p / 100 * basis : nil
        }
    }

    public func toJSON() -> Any? {
        switch self {
        case .px(let v): return v
        case .pct(let p): return Percent(p).toJSON()
        }
    }
}

public func isPercent(_ v: Any?) -> Bool {
    let f = flattenOptional(v)
    if f is Percent { return true }
    if case .pct? = f as? Length { return true }
    if let m = f as? JSONObject { return m.has("pct") }
    return false
}

public func resolveLength(_ v: Length?, _ basis: Double) -> Double? { v?.resolve(basis) }
