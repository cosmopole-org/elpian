#if canImport(UIKit) || ELPIAN_HOST_TYPECHECK
import Foundation
#if !ELPIAN_SINGLE_MODULE
import ElpianCore
#endif

/**
 * Loose accessors for view props. The core's props maps hold typed values
 * (Color numbers, [Alignment], structs) next to JSON-shaped ones (lists of
 * Double, maps), exactly as the TypeScript props objects do; these helpers
 * read both shapes (Props.kt on Android).
 */
enum HostProps {
    static func num(_ v: Any?) -> Double? {
        guard let v = flattenOptional(v) else { return nil }
        if let b = jsBool(v) { return b ? 1 : 0 }
        if let n = jsNumber(v) { return n.isNaN ? nil : n }
        if let s = v as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    static func int(_ v: Any?) -> Int? {
        guard let n = num(v), n.isFinite else { return nil }
        return Int(n.rounded(.towardZero))
    }

    /** An ARGB colour: a number (JS `>>> 0` semantics) or a colour string. */
    static func color(_ v: Any?) -> Color? {
        guard let v = flattenOptional(v) else { return nil }
        if let c = v as? UInt32 { return c }
        if let n = jsNumber(v) { return n.isFinite ? jsToUint32(n) : nil }
        if let s = v as? String { return parseColor(s) }
        return nil
    }

    static func str(_ v: Any?) -> String? {
        guard let v = flattenOptional(v) else { return nil }
        if let s = v as? String { return s }
        if let f = v as? BoxFit { return f.rawValue }
        if let e = v as? BorderStyleName { return e.rawValue }
        return jsString(v)
    }

    static func bool(_ v: Any?) -> Bool { jsBool(flattenOptional(v)) == true }

    /** Explicitly `false` (an absent value is not). */
    static func isFalse(_ v: Any?) -> Bool { jsBool(flattenOptional(v)) == false }

    /** A fixed-size numeric tuple (`frame`, `contentSize`, `scrollTo`, `contentPadding`). */
    static func doubles(_ v: Any?) -> [Double]? {
        guard let v = flattenOptional(v) else { return nil }
        if let d = v as? [Double] { return d }
        if let a = asArray(v) { return a.map { num($0) ?? 0 } }
        if let e = v as? EdgeInsets { return [e.top, e.right, e.bottom, e.left] }
        return nil
    }

    static func map(_ v: Any?) -> JSONObject? { asMap(v) }

    static func list(_ v: Any?) -> [Any?]? { asArray(v) }

    static func strings(_ v: Any?) -> [String] { (list(v) ?? []).compactMap { str($0) } }

    static func alignment(_ v: Any?) -> Alignment? {
        guard let v = flattenOptional(v) else { return nil }
        if let a = v as? Alignment { return a }
        if let m = asMap(v) { return Alignment(x: num(m["x"]) ?? 0, y: num(m["y"]) ?? 0) }
        if let l = asArray(v), l.count >= 2 { return Alignment(x: num(l[0]) ?? 0, y: num(l[1]) ?? 0) }
        return nil
    }

    static func fit(_ v: Any?) -> String? {
        guard let v = flattenOptional(v) else { return nil }
        if let f = v as? BoxFit { return f.rawValue }
        return str(v)
    }

    /** A typed list (`gradients`, `shadows`). */
    static func typed<T>(_ v: Any?, _ type: T.Type) -> [T]? {
        guard let l = list(v) else { return nil }
        return l.compactMap { flattenOptional($0) as? T }
    }

    static func matrix(_ v: Any?) -> Matrix4? {
        guard let d = doubles(v), d.count == 16 else { return nil }
        return d
    }

    /** A [TextStyleSpec] (or its JSON form) — `textStyle`, `hintStyle`. */
    static func textStyle(_ v: Any?) -> TextStyleSpec? {
        guard let v = flattenOptional(v) else { return nil }
        if let s = v as? TextStyleSpec { return s }
        guard let m = asMap(v) else { return nil }
        let shadows: [TextShadow]? = list(m["shadows"])?.compactMap { e -> TextShadow? in
            if let s = flattenOptional(e) as? TextShadow { return s }
            guard let o = asMap(e) else { return nil }
            return TextShadow(color: color(o["color"]) ?? 0xFF00_0000, dx: num(o["dx"]) ?? 0, dy: num(o["dy"]) ?? 0, blur: num(o["blur"]) ?? 0)
        }
        return TextStyleSpec(
            color: color(m["color"]) ?? 0xFF00_0000,
            fontSize: num(m["fontSize"]) ?? 14,
            fontWeight: int(m["fontWeight"]) ?? 400,
            italic: bool(m["italic"]),
            fontFamily: str(m["fontFamily"]),
            letterSpacing: num(m["letterSpacing"]) ?? 0,
            wordSpacing: num(m["wordSpacing"]) ?? 0,
            height: num(m["height"]),
            decoration: int(m["decoration"]) ?? 0,
            decorationColor: color(m["decorationColor"]),
            decorationStyle: str(m["decorationStyle"]),
            decorationThickness: num(m["decorationThickness"]),
            shadows: shadows,
            background: color(m["background"]),
            baselineShift: num(m["baselineShift"]) ?? 0
        )
    }

    /** A field of a struct or map value (`backgroundImage.src`, `options[i].label`). */
    static func field(_ v: Any?, _ name: String) -> Any? {
        guard let v = flattenOptional(v) else { return nil }
        if let m = asMap(v) { return m[name] }
        for child in Mirror(reflecting: v).children where child.label == name || child.label == "_" + name {
            return flattenOptional(child.value)
        }
        return nil
    }
}
#endif
