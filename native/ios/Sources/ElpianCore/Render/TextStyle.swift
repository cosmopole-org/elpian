import Foundation

/**
 * Text styles (render/text-style.ts): the inheritable `TextStyle` used while
 * lowering, its merge rules (Flutter `TextStyle.merge` / `DefaultTextStyle`),
 * font-family resolution (`CSSProperties.resolveFontFamily`) and the
 * conversion to the wire [TextStyleSpec] platforms render with.
 */
public struct TextStyle: Equatable, Hashable {
    public var color: Color?
    public var fontSize: Double?
    public var fontWeight: Int?
    public var italic: Bool?
    public var fontFamily: String?
    public var letterSpacing: Double?
    public var wordSpacing: Double?
    /** Height multiplier. */
    public var height: Double?
    /** Pixel line height (resolved against the final font size). */
    public var heightPx: Double?
    public var decoration: Int?
    public var decorationColor: Color?
    public var decorationStyle: String?
    public var decorationThickness: Double?
    public var shadows: [TextShadow]?
    public var background: Color?
    public var baselineShift: Double?
    public var textTransform: String?

    public init(color: Color? = nil, fontSize: Double? = nil, fontWeight: Int? = nil, italic: Bool? = nil, fontFamily: String? = nil,
                letterSpacing: Double? = nil, wordSpacing: Double? = nil, height: Double? = nil, heightPx: Double? = nil,
                decoration: Int? = nil, decorationColor: Color? = nil, decorationStyle: String? = nil, decorationThickness: Double? = nil,
                shadows: [TextShadow]? = nil, background: Color? = nil, baselineShift: Double? = nil, textTransform: String? = nil) {
        self.color = color
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.italic = italic
        self.fontFamily = fontFamily
        self.letterSpacing = letterSpacing
        self.wordSpacing = wordSpacing
        self.height = height
        self.heightPx = heightPx
        self.decoration = decoration
        self.decorationColor = decorationColor
        self.decorationStyle = decorationStyle
        self.decorationThickness = decorationThickness
        self.shadows = shadows
        self.background = background
        self.baselineShift = baselineShift
        self.textTransform = textTransform
    }

    /** Later wins for every field it defines. */
    public func merge(_ over: TextStyle?) -> TextStyle {
        guard let o = over else { return self }
        var out = TextStyle(
            color: o.color ?? color,
            fontSize: o.fontSize ?? fontSize,
            fontWeight: o.fontWeight ?? fontWeight,
            italic: o.italic ?? italic,
            fontFamily: o.fontFamily ?? fontFamily,
            letterSpacing: o.letterSpacing ?? letterSpacing,
            wordSpacing: o.wordSpacing ?? wordSpacing,
            height: o.height ?? height,
            heightPx: o.heightPx ?? heightPx,
            decoration: o.decoration ?? decoration,
            decorationColor: o.decorationColor ?? decorationColor,
            decorationStyle: o.decorationStyle ?? decorationStyle,
            decorationThickness: o.decorationThickness ?? decorationThickness,
            shadows: o.shadows ?? shadows,
            background: o.background ?? background,
            baselineShift: o.baselineShift ?? baselineShift,
            textTransform: o.textTransform ?? textTransform
        )
        if o.height != nil { out.heightPx = nil }
        if o.heightPx != nil { out.height = nil }
        return out
    }

    /** Material 3 `bodyMedium` — what Flutter's default `Text` uses inside a themed app. */
    public static let DEFAULT = TextStyle(color: M3.onSurface, fontSize: 14, fontWeight: 400, italic: false, fontFamily: nil,
                                          letterSpacing: 0.25, wordSpacing: 0, height: 20.0 / 14, decoration: 0)
    /** Material 3 `labelLarge` (buttons). */
    public static let LABEL_LARGE = TextStyle(fontSize: 14, fontWeight: 500, letterSpacing: 0.1, height: 20.0 / 14)
    /** Material 3 `titleLarge` (app bar titles). */
    public static let TITLE_LARGE = TextStyle(fontSize: 22, fontWeight: 400, letterSpacing: 0, height: 28.0 / 22)
    /** Material 3 `bodyLarge` (text fields). */
    public static let BODY_LARGE = TextStyle(fontSize: 16, fontWeight: 400, letterSpacing: 0.5, height: 24.0 / 16)
    /** Material 3 `labelSmall` (badges). */
    public static let LABEL_SMALL = TextStyle(fontSize: 11, fontWeight: 500, letterSpacing: 0.5, height: 16.0 / 11)

    /** Resolve an inheritable style into the wire spec (`toSpec`). */
    public func toSpec(_ textScale: Double = 1) -> TextStyleSpec {
        ElpianCore.toSpec(self, textScale)
    }
}

/** `mergeTextStyle(base, over)`: later wins for every field it defines. */
public func mergeTextStyle(_ base: TextStyle?, _ over: TextStyle?) -> TextStyle {
    guard let b = base else { return over ?? TextStyle() }
    return b.merge(over)
}

public let DEFAULT_TEXT_STYLE = TextStyle.DEFAULT
public let LABEL_LARGE = TextStyle.LABEL_LARGE
public let TITLE_LARGE = TextStyle.TITLE_LARGE
public let BODY_LARGE = TextStyle.BODY_LARGE
public let LABEL_SMALL = TextStyle.LABEL_SMALL

private let SERIF: Set<String> = [
    "serif", "georgia", "times", "times new roman", "cambria", "garamond", "cinzel", "playfair display",
    "merriweather", "crimson", "crimson pro", "pt serif", "noto serif", "liberation serif", "roboto serif",
]
private let MONO: Set<String> = [
    "monospace", "courier", "courier new", "consolas", "menlo", "monaco", "roboto mono", "sf mono",
    "source code pro", "fira code", "jetbrains mono", "liberation mono", "ui-monospace",
]
private let SANS: Set<String> = [
    "sans-serif", "arial", "helvetica", "helvetica neue", "roboto", "inter", "segoe ui", "verdana",
    "tahoma", "noto sans", "liberation sans", "ubuntu",
]
private let QUOTES = JSRegex("^['\"]|['\"]$")

/**
 * Resolve a CSS font-family list the way Flutter's engine does: generic and
 * well-known serif / monospace stacks map to `serif` / `monospace`, sans
 * stacks to the platform default (nil), anything else is passed through as
 * a concrete family the host may have bundled.
 */
public func resolveFontFamily(_ family: String?) -> String? {
    guard let family = family, !family.isEmpty else { return nil }
    if family == "icons" { return "icons" }
    for raw in jsSplit(family, ",") {
        let name = QUOTES.replace(jsTrim(raw), with: "").lowercased()
        if name.isEmpty { continue }
        if SERIF.contains(name) || (name.contains("serif") && !name.contains("sans")) { return "serif" }
        if MONO.contains(name) || name.contains("mono") { return "monospace" }
        if SANS.contains(name) || name.contains("sans") || name == "system-ui" || name.hasPrefix("-apple") || name == "ui-sans-serif" {
            return nil
        }
        if name == "material icons" || name == "materialicons" { return "icons" }
        return QUOTES.replace(jsTrim(raw), with: "")
    }
    return nil
}

/** Text decoration bit flags (`Decoration` in the TypeScript engine (native/web)). */
public enum Decoration {
    public static let underline = 1
    public static let overline = 2
    public static let lineThrough = 4
}

/** `CSSProperties.createTextStyle` — the text-relevant part of a resolved CSS style. */
public func textStyleFromCss(_ style: CSSStyle?) -> TextStyle? {
    guard let style = style else { return nil }
    var t = TextStyle()
    if let v = style.color { t.color = v }
    if let v = style.fontSize { t.fontSize = v }
    if let v = style.fontWeight { t.fontWeight = v }
    if let v = style.fontStyle { t.italic = v == "italic" }
    if let v = style.fontFamily { t.fontFamily = resolveFontFamily(v) ?? "" }
    if let v = style.letterSpacing { t.letterSpacing = v }
    if let v = style.wordSpacing { t.wordSpacing = v }
    if let v = style.lineHeight { t.height = v }
    if let v = style.lineHeightPx { t.heightPx = v }
    if let d = style.textDecoration {
        t.decoration = (d.underline ? Decoration.underline : 0) | (d.overline ? Decoration.overline : 0) | (d.lineThrough ? Decoration.lineThrough : 0)
    }
    if let v = style.textDecorationColor { t.decorationColor = v }
    if let v = style.textDecorationStyle { t.decorationStyle = v }
    if let v = style.textDecorationThickness { t.decorationThickness = v }
    if let v = style.textShadow { t.shadows = v }
    if let v = style.textTransform { t.textTransform = v }
    return t
}

/** Resolve an inheritable style into the wire spec. */
public func toSpec(_ style: TextStyle, _ textScale: Double = 1) -> TextStyleSpec {
    let merged = mergeTextStyle(DEFAULT_TEXT_STYLE, style)
    let fontSize = (merged.fontSize ?? 14) * textScale
    var height = merged.height
    if let px = merged.heightPx, fontSize > 0 { height = px * textScale / fontSize }
    return TextStyleSpec(
        color: merged.color ?? M3.onSurface,
        fontSize: fontSize,
        fontWeight: merged.fontWeight ?? 400,
        italic: merged.italic == true,
        fontFamily: merged.fontFamily == "" ? nil : merged.fontFamily,
        letterSpacing: merged.letterSpacing ?? 0,
        wordSpacing: merged.wordSpacing ?? 0,
        height: height,
        decoration: merged.decoration ?? 0,
        decorationColor: merged.decorationColor,
        decorationStyle: merged.decorationStyle,
        decorationThickness: merged.decorationThickness,
        shadows: merged.shadows,
        background: merged.background,
        baselineShift: merged.baselineShift ?? 0
    )
}

private let CAPITALIZE = JSRegex("(^|\\s|[-(\\[\"'])(\\p{L})")

/** CSS `text-transform`. */
public func applyTextTransform(_ text: String, _ transform: String?) -> String {
    switch transform {
    case "uppercase": return text.uppercased()
    case "lowercase": return text.lowercased()
    case "capitalize": return CAPITALIZE.replace(text) { m in (m[1] ?? "") + (m[2] ?? "").uppercased() }
    default: return text
    }
}
