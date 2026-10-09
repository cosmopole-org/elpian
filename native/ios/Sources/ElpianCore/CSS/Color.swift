import Foundation

/**
 * Colour parsing, mirroring `CSSParser.parseColor` in the Flutter engine
 * (css/color.ts).
 *
 * Colours are 32-bit unsigned ARGB integers (Flutter's `Color.value` layout),
 * which every platform renderer can consume directly (UIKit via component
 * extraction).
 *
 * Fidelity notes (Flutter is the source of truth):
 *   * An 8-digit hex is `#AARRGGBB`, as in Flutter's `Color(0xAARRGGBB)` —
 *     NOT the CSS `#RRGGBBAA`. `#rgba` expands to `#rrggbbaa` and is then read
 *     the same way, exactly like the Flutter parser.
 *   * Names Flutter knows (`red`, `blue`, `grey`, `deep-orange` …) resolve to
 *     the Material primary swatches Flutter uses, not the CSS keywords. The
 *     remaining CSS named colours are accepted as a superset.
 */
public typealias Color = UInt32

public let TRANSPARENT: Color = 0x0000_0000
public let BLACK: Color = 0xFF00_0000
public let WHITE: Color = 0xFFFF_FFFF

/** Flutter `Colors.*` values used by the widget defaults. */
public enum Colors {
    public static let transparent: Color = 0x00000000
    public static let black: Color = 0xff000000
    public static let black87: Color = 0xdd000000
    public static let black54: Color = 0x8a000000
    public static let black45: Color = 0x73000000
    public static let black38: Color = 0x61000000
    public static let black26: Color = 0x42000000
    public static let black12: Color = 0x1f000000
    public static let white: Color = 0xffffffff
    public static let white70: Color = 0xb3ffffff
    public static let white60: Color = 0x99ffffff
    public static let white54: Color = 0x8affffff
    public static let white38: Color = 0x62ffffff
    public static let white30: Color = 0x4dffffff
    public static let white24: Color = 0x3dffffff
    public static let white12: Color = 0x1fffffff
    public static let white10: Color = 0x1affffff
    public static let red: Color = 0xfff44336
    public static let pink: Color = 0xffe91e63
    public static let purple: Color = 0xff9c27b0
    public static let deepPurple: Color = 0xff673ab7
    public static let indigo: Color = 0xff3f51b5
    public static let blue: Color = 0xff2196f3
    public static let lightBlue: Color = 0xff03a9f4
    public static let cyan: Color = 0xff00bcd4
    public static let teal: Color = 0xff009688
    public static let green: Color = 0xff4caf50
    public static let lightGreen: Color = 0xff8bc34a
    public static let lime: Color = 0xffcddc39
    public static let yellow: Color = 0xffffeb3b
    public static let amber: Color = 0xffffc107
    public static let orange: Color = 0xffff9800
    public static let deepOrange: Color = 0xffff5722
    public static let brown: Color = 0xff795548
    public static let grey: Color = 0xff9e9e9e
    public static let grey100: Color = 0xfff5f5f5
    public static let grey200: Color = 0xffeeeeee
    public static let grey300: Color = 0xffe0e0e0
    public static let grey400: Color = 0xffbdbdbd
    public static let grey600: Color = 0xff757575
    public static let blueGrey: Color = 0xff607d8b
}

/** Material 3 baseline scheme (what an un-themed Flutter app renders with). */
public enum M3 {
    public static let primary: Color = 0xff6750a4
    public static let onPrimary: Color = 0xffffffff
    public static let primaryContainer: Color = 0xffeaddff
    public static let secondaryContainer: Color = 0xffe8def8
    public static let onSecondaryContainer: Color = 0xff1d192b
    public static let surface: Color = 0xfffef7ff
    public static let surfaceContainerLow: Color = 0xfff7f2fa
    public static let surfaceContainerHighest: Color = 0xffe6e0e9
    public static let onSurface: Color = 0xff1d1b20
    public static let onSurfaceVariant: Color = 0xff49454f
    public static let outline: Color = 0xff79747e
    public static let outlineVariant: Color = 0xffcac4d0
    public static let error: Color = 0xffb3261e
    public static let inverseSurface: Color = 0xff322f35
    public static let onInverseSurface: Color = 0xfff5eff7
    public static let shadow: Color = 0xff000000
}

private let flutterNamed: [String: Color] = [
    "transparent": Colors.transparent,
    "black": Colors.black,
    "white": Colors.white,
    "red": Colors.red,
    "green": Colors.green,
    "blue": Colors.blue,
    "yellow": Colors.yellow,
    "orange": Colors.orange,
    "purple": Colors.purple,
    "pink": Colors.pink,
    "grey": Colors.grey,
    "gray": Colors.grey,
    "brown": Colors.brown,
    "cyan": Colors.cyan,
    "indigo": Colors.indigo,
    "lime": Colors.lime,
    "teal": Colors.teal,
    "amber": Colors.amber,
    "deeporange": Colors.deepOrange,
    "deep-orange": Colors.deepOrange,
    "deeppurple": Colors.deepPurple,
    "deep-purple": Colors.deepPurple,
    "lightblue": Colors.lightBlue,
    "light-blue": Colors.lightBlue,
    "lightgreen": Colors.lightGreen,
    "light-green": Colors.lightGreen,
    "bluegrey": Colors.blueGrey,
    "blue-grey": Colors.blueGrey,
]

// The CSS keyword colours that Flutter's table does not define.
private let cssNamed: [String: UInt32] = [
    "aliceblue": 0xf0f8ff,
    "antiquewhite": 0xfaebd7,
    "aqua": 0x00ffff,
    "aquamarine": 0x7fffd4,
    "azure": 0xf0ffff,
    "beige": 0xf5f5dc,
    "bisque": 0xffe4c4,
    "blanchedalmond": 0xffebcd,
    "blueviolet": 0x8a2be2,
    "burlywood": 0xdeb887,
    "cadetblue": 0x5f9ea0,
    "chartreuse": 0x7fff00,
    "chocolate": 0xd2691e,
    "coral": 0xff7f50,
    "cornflowerblue": 0x6495ed,
    "cornsilk": 0xfff8dc,
    "crimson": 0xdc143c,
    "darkblue": 0x00008b,
    "darkcyan": 0x008b8b,
    "darkgoldenrod": 0xb8860b,
    "darkgray": 0xa9a9a9,
    "darkgrey": 0xa9a9a9,
    "darkgreen": 0x006400,
    "darkkhaki": 0xbdb76b,
    "darkmagenta": 0x8b008b,
    "darkolivegreen": 0x556b2f,
    "darkorange": 0xff8c00,
    "darkorchid": 0x9932cc,
    "darkred": 0x8b0000,
    "darksalmon": 0xe9967a,
    "darkseagreen": 0x8fbc8f,
    "darkslateblue": 0x483d8b,
    "darkslategray": 0x2f4f4f,
    "darkslategrey": 0x2f4f4f,
    "darkturquoise": 0x00ced1,
    "darkviolet": 0x9400d3,
    "deeppink": 0xff1493,
    "deepskyblue": 0x00bfff,
    "dimgray": 0x696969,
    "dimgrey": 0x696969,
    "dodgerblue": 0x1e90ff,
    "firebrick": 0xb22222,
    "floralwhite": 0xfffaf0,
    "forestgreen": 0x228b22,
    "fuchsia": 0xff00ff,
    "gainsboro": 0xdcdcdc,
    "ghostwhite": 0xf8f8ff,
    "gold": 0xffd700,
    "goldenrod": 0xdaa520,
    "greenyellow": 0xadff2f,
    "honeydew": 0xf0fff0,
    "hotpink": 0xff69b4,
    "indianred": 0xcd5c5c,
    "ivory": 0xfffff0,
    "khaki": 0xf0e68c,
    "lavender": 0xe6e6fa,
    "lavenderblush": 0xfff0f5,
    "lawngreen": 0x7cfc00,
    "lemonchiffon": 0xfffacd,
    "lightcoral": 0xf08080,
    "lightcyan": 0xe0ffff,
    "lightgoldenrodyellow": 0xfafad2,
    "lightgray": 0xd3d3d3,
    "lightgrey": 0xd3d3d3,
    "lightpink": 0xffb6c1,
    "lightsalmon": 0xffa07a,
    "lightseagreen": 0x20b2aa,
    "lightskyblue": 0x87cefa,
    "lightslategray": 0x778899,
    "lightslategrey": 0x778899,
    "lightsteelblue": 0xb0c4de,
    "lightyellow": 0xffffe0,
    "limegreen": 0x32cd32,
    "linen": 0xfaf0e6,
    "magenta": 0xff00ff,
    "maroon": 0x800000,
    "mediumaquamarine": 0x66cdaa,
    "mediumblue": 0x0000cd,
    "mediumorchid": 0xba55d3,
    "mediumpurple": 0x9370db,
    "mediumseagreen": 0x3cb371,
    "mediumslateblue": 0x7b68ee,
    "mediumspringgreen": 0x00fa9a,
    "mediumturquoise": 0x48d1cc,
    "mediumvioletred": 0xc71585,
    "midnightblue": 0x191970,
    "mintcream": 0xf5fffa,
    "mistyrose": 0xffe4e1,
    "moccasin": 0xffe4b5,
    "navajowhite": 0xffdead,
    "navy": 0x000080,
    "oldlace": 0xfdf5e6,
    "olive": 0x808000,
    "olivedrab": 0x6b8e23,
    "orangered": 0xff4500,
    "orchid": 0xda70d6,
    "palegoldenrod": 0xeee8aa,
    "palegreen": 0x98fb98,
    "paleturquoise": 0xafeeee,
    "palevioletred": 0xdb7093,
    "papayawhip": 0xffefd5,
    "peachpuff": 0xffdab9,
    "peru": 0xcd853f,
    "plum": 0xdda0dd,
    "powderblue": 0xb0e0e6,
    "rebeccapurple": 0x663399,
    "rosybrown": 0xbc8f8f,
    "royalblue": 0x4169e1,
    "saddlebrown": 0x8b4513,
    "salmon": 0xfa8072,
    "sandybrown": 0xf4a460,
    "seagreen": 0x2e8b57,
    "seashell": 0xfff5ee,
    "sienna": 0xa0522d,
    "silver": 0xc0c0c0,
    "skyblue": 0x87ceeb,
    "slateblue": 0x6a5acd,
    "slategray": 0x708090,
    "slategrey": 0x708090,
    "snow": 0xfffafa,
    "springgreen": 0x00ff7f,
    "steelblue": 0x4682b4,
    "tan": 0xd2b48c,
    "thistle": 0xd8bfd8,
    "tomato": 0xff6347,
    "turquoise": 0x40e0d0,
    "violet": 0xee82ee,
    "wheat": 0xf5deb3,
    "whitesmoke": 0xf5f5f5,
    "yellowgreen": 0x9acd32,
]
public func argb(_ a: Double, _ r: Double, _ g: Double, _ b: Double) -> Color {
    let av = UInt32(bitPattern: jsToInt32(a)) & 0xFF
    let rv = UInt32(bitPattern: jsToInt32(r)) & 0xFF
    let gv = UInt32(bitPattern: jsToInt32(g)) & 0xFF
    let bv = UInt32(bitPattern: jsToInt32(b)) & 0xFF
    return (av << 24) | (rv << 16) | (gv << 8) | bv
}

public func alphaOf(_ c: Color) -> Int { Int((c >> 24) & 0xFF) }
public func redOf(_ c: Color) -> Int { Int((c >> 16) & 0xFF) }
public func greenOf(_ c: Color) -> Int { Int((c >> 8) & 0xFF) }
public func blueOf(_ c: Color) -> Int { Int(c & 0xFF) }

/** Replace the alpha channel with [opacity] (0..1) — `Color.withValues(alpha:)`. */
public func withOpacity(_ c: Color, _ opacity: Double) -> Color {
    let clamped = opacity.isNaN ? Double.nan : max(0, min(1, opacity))
    let a = UInt32(bitPattern: jsToInt32(jsRound(clamped * 255)))
    return (c & 0x00FF_FFFF) | (a << 24)
}

/** Multiply the existing alpha by [factor]. */
public func scaleAlpha(_ c: Color, _ factor: Double) -> Color {
    withOpacity(c, Double(alphaOf(c)) / 255 * factor)
}

public func lerpColor(_ a: Color, _ b: Color, _ t: Double) -> Color {
    func l(_ x: Int, _ y: Int) -> Double { jsRound(Double(x) + Double(y - x) * t) }
    return argb(l(alphaOf(a), alphaOf(b)), l(redOf(a), redOf(b)), l(greenOf(a), greenOf(b)), l(blueOf(a), blueOf(b)))
}

/** `#rrggbb` / `rgba(…)` — the CSS form of a colour. */
public func toCssColor(_ c: Color) -> String {
    let a = alphaOf(c)
    if a == 255 {
        let hex = String(c & 0xFF_FFFF, radix: 16)
        return "#" + String(repeating: "0", count: max(0, 6 - hex.count)) + hex
    }
    let alpha = Double(jsToFixed(Double(a) / 255, 4)) ?? 0
    return "rgba(\(redOf(c)),\(greenOf(c)),\(blueOf(c)),\(jsNumberToString(alpha)))"
}

private func hslToRgb(_ h: Double, _ s: Double, _ l: Double) -> (Double, Double, Double) {
    // HSLColor.toColor in Flutter.
    let chroma = (1 - abs(2 * l - 1)) * s
    let hp = ((h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)) / 60
    let x = chroma * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
    var r = 0.0, g = 0.0, b = 0.0
    if hp < 1 { (r, g, b) = (chroma, x, 0) }
    else if hp < 2 { (r, g, b) = (x, chroma, 0) }
    else if hp < 3 { (r, g, b) = (0, chroma, x) }
    else if hp < 4 { (r, g, b) = (0, x, chroma) }
    else if hp < 5 { (r, g, b) = (x, 0, chroma) }
    else { (r, g, b) = (chroma, 0, x) }
    let m = l - chroma / 2
    return (jsRound((r + m) * 255), jsRound((g + m) * 255), jsRound((b + m) * 255))
}

private func channel(_ token: String, _ scale: Double) -> Double {
    let t = jsTrim(token)
    if t.hasSuffix("%") { return jsParseFloat(t) / 100 * scale }
    return jsParseFloat(t)
}

private func alphaChannel(_ token: String?) -> Double {
    guard let token = token, !jsTrim(token).isEmpty else { return 1 }
    let t = jsTrim(token)
    if t.hasSuffix("%") { return jsParseFloat(t) / 100 }
    return jsParseFloat(t)
}

private let colorCacheLock = NSLock()
private var colorCache: [String: Color?] = [:]

/** Parse a colour value: an ARGB number or a CSS / Flutter colour string. */
public func parseColor(_ raw: Any?) -> Color? {
    let value = flattenOptional(raw)
    guard let v = value else { return nil }
    if let c = v as? UInt32 { return c }
    if let n = jsNumber(v) { return jsToUint32(n) }
    guard let s = v as? String else { return nil }
    colorCacheLock.lock()
    if let hit = colorCache[s] {
        colorCacheLock.unlock()
        return hit
    }
    colorCacheLock.unlock()
    let parsed = parseColorString(jsTrim(s))
    colorCacheLock.lock()
    if colorCache.count > 2048 { colorCache.removeAll() }
    colorCache[s] = .some(parsed)
    colorCacheLock.unlock()
    return parsed
}

private let HEX_DIGITS = JSRegex("^[0-9a-f]+$")
private let COLOR_FN = JSRegex("^(rgba?|hsla?)\\(\\s*([^)]*)\\)$")

private func parseColorString(_ raw: String) -> Color? {
    if raw.isEmpty { return nil }
    let lower = raw.lowercased()

    if lower.hasPrefix("#") {
        var hex = String(lower.dropFirst())
        let n = hex.utf16.count
        if n == 3 || n == 4 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        if !HEX_DIGITS.test(hex) { return nil }
        if hex.utf16.count == 6 { return 0xFF00_0000 | jsToUint32(jsParseInt(hex, 16)) }
        if hex.utf16.count == 8 { return jsToUint32(jsParseInt(hex, 16)) } // AARRGGBB, as Flutter
        return nil
    }

    if lower.hasPrefix("0x") {
        let n = jsParseInt(jsSubstring(lower, 2), 16)
        if n.isFinite { return lower.utf16.count <= 8 ? (0xFF00_0000 | jsToUint32(n)) : jsToUint32(n) }
        return nil
    }

    if let fn = COLOR_FN.exec(lower) {
        let body = fn[2] ?? ""
        var parts: [String]
        var alphaPart: String?
        if body.contains(",") {
            parts = jsSplit(body, ",").map { jsTrim($0) }
            if parts.count == 4 { alphaPart = parts.removeLast() }
        } else {
            let split = jsSplit(body, "/")
            parts = jsSplitWhitespace(jsTrim(split[0]))
            alphaPart = split.count > 1 ? split[1] : nil
            if parts.count == 4 && alphaPart == nil { alphaPart = parts.removeLast() }
        }
        if parts.count < 3 { return nil }
        let rawAlpha = alphaChannel(alphaPart)
        let alpha = rawAlpha.isNaN ? Double.nan : max(0, min(1, rawAlpha))
        if (fn[1] ?? "").hasPrefix("rgb") {
            let r = channel(parts[0], 255), g = channel(parts[1], 255), b = channel(parts[2], 255)
            if [r, g, b, alpha].contains(where: { $0.isNaN }) { return nil }
            // Flutter truncates alpha: (a * 255).toInt()
            return argb(jsTrunc(alpha * 255), jsRound(r), jsRound(g), jsRound(b))
        }
        var h = jsParseFloat(parts[0])
        if parts[0].hasSuffix("turn") { h *= 360 }
        else if parts[0].hasSuffix("rad") { h = h * 180 / Double.pi }
        let s = jsParseFloat(parts[1]) / 100
        let l = jsParseFloat(parts[2]) / 100
        if [h, s, l, alpha].contains(where: { $0.isNaN }) { return nil }
        let (r, g, b) = hslToRgb(h, s, l)
        return argb(jsRound(alpha * 255), r, g, b)
    }

    if let named = flutterNamed[lower] { return named }
    if let css = cssNamed[lower] { return 0xFF00_0000 | css }
    if lower == "currentcolor" { return nil }
    return nil
}
