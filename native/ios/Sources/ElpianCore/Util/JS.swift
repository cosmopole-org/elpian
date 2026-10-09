import Foundation

/**
 * JavaScript semantics the TypeScript engine (native/web) relies on implicitly — `String(v)`,
 * `parseFloat`, `parseInt`, `Math.round`, UTF-16 `substring` / `indexOf` and
 * `RegExp` — defined once so every ported file reads values the same way.
 */

/** JavaScript `String(v)` for JSON-shaped values. */
public func jsString(_ value: Any?) -> String {
    guard let v = flattenOptional(value) else { return "null" }
    if let b = jsBool(v) { return b ? "true" : "false" }
    if let n = jsNumber(v) { return jsNumberToString(n) }
    switch v {
    case let s as String: return s
    case let s as Substring: return String(s)
    case is JSONObject: return "[object Object]"
    case is [String: Any?], is [String: Any]: return "[object Object]"
    default: break
    }
    if let a = asArray(v) {
        return a.map { e -> String in
            let f = flattenOptional(e)
            return f == nil ? "" : jsString(f)
        }.joined(separator: ",")
    }
    if let s = v as? JSONSerializable {
        let j = flattenOptional(s.toJSON())
        if j is JSONObject { return "[object Object]" }
        return jsString(j)
    }
    return String(describing: v)
}

/** JavaScript truthiness. */
public func jsTruthy(_ value: Any?) -> Bool {
    guard let v = flattenOptional(value) else { return false }
    if let b = jsBool(v) { return b }
    if let n = jsNumber(v) { return n != 0 && !n.isNaN }
    if let s = v as? String { return !s.isEmpty }
    return true
}

/** `Math.round`: halves round toward +∞. */
@inline(__always)
public func jsRound(_ x: Double) -> Double {
    if !x.isFinite { return x }
    let f = x.rounded(.down)
    return x - f >= 0.5 ? f + 1 : f
}

/** `Math.trunc`. */
@inline(__always)
public func jsTrunc(_ x: Double) -> Double { x.rounded(.towardZero) }

/** `Number.prototype.toFixed(digits)`. */
public func jsToFixed(_ x: Double, _ digits: Int) -> String {
    if !x.isFinite { return jsNumberToString(x) }
    if abs(x) >= 1e21 { return jsNumberToString(x) }
    var s = String(format: "%.\(digits)f", x)
    if s.hasPrefix("-") && Double(s) == 0 { s.removeFirst() }
    return s
}

/** `Number.isInteger(v) && Number.isSafeInteger(v)`. */
public func jsIsSafeInteger(_ d: Double) -> Bool {
    d.isFinite && d == d.rounded(.towardZero) && abs(d) <= 9_007_199_254_740_991
}

private func isJSWhitespace(_ u: UInt16) -> Bool {
    switch u {
    case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: return true
    case 0x2000...0x200A: return true
    default: return false
    }
}

/** JavaScript `parseFloat`: the longest numeric prefix after leading whitespace; NaN when none. */
public func jsParseFloat(_ s: String) -> Double {
    let u = Array(s.utf16)
    var i = 0
    while i < u.count, isJSWhitespace(u[i]) { i += 1 }
    let start = i
    if i < u.count, u[i] == 0x2B || u[i] == 0x2D { i += 1 }
    // Infinity
    let inf = Array("Infinity".utf16)
    if i + inf.count <= u.count, Array(u[i..<(i + inf.count)]) == inf {
        return u[start] == 0x2D ? -.infinity : .infinity
    }
    var digits = 0
    while i < u.count, u[i] >= 0x30, u[i] <= 0x39 { i += 1; digits += 1 }
    if i < u.count, u[i] == 0x2E {
        i += 1
        while i < u.count, u[i] >= 0x30, u[i] <= 0x39 { i += 1; digits += 1 }
    }
    if digits == 0 { return .nan }
    var end = i
    if i < u.count, u[i] == 0x65 || u[i] == 0x45 {
        var j = i + 1
        if j < u.count, u[j] == 0x2B || u[j] == 0x2D { j += 1 }
        let expStart = j
        while j < u.count, u[j] >= 0x30, u[j] <= 0x39 { j += 1 }
        if j > expStart { end = j }
    }
    var text = String(decoding: u[start..<end], as: UTF16.self)
    if text.hasSuffix(".") { text.removeLast() }
    if text.hasPrefix("+") { text.removeFirst() }
    if text.hasPrefix(".") { text = "0" + text }
    if text.hasPrefix("-.") { text = "-0" + text.dropFirst() }
    return Double(text) ?? .nan
}

/** JavaScript `parseInt(s, radix)`; NaN when there is no digit. */
public func jsParseInt(_ s: String, _ radix: Int = 10) -> Double {
    let u = Array(s.utf16)
    var i = 0
    while i < u.count, isJSWhitespace(u[i]) { i += 1 }
    var negative = false
    if i < u.count, u[i] == 0x2B || u[i] == 0x2D {
        negative = u[i] == 0x2D
        i += 1
    }
    var r = radix
    if r == 16 || r == 0 {
        if i + 1 < u.count, u[i] == 0x30, u[i + 1] == 0x78 || u[i + 1] == 0x58 {
            i += 2
            r = 16
        }
    }
    if r == 0 { r = 10 }
    var value = 0.0
    var any = false
    while i < u.count {
        let c = u[i]
        var d: Int
        switch c {
        case 0x30...0x39: d = Int(c - 0x30)
        case 0x61...0x7A: d = Int(c - 0x61) + 10
        case 0x41...0x5A: d = Int(c - 0x41) + 10
        default: d = 99
        }
        if d >= r { break }
        value = value * Double(r) + Double(d)
        any = true
        i += 1
    }
    if !any { return .nan }
    return negative ? -value : value
}

// ---------------------------------------------------------------------------
// UTF-16 string access (JavaScript string indices)
// ---------------------------------------------------------------------------

/** `s.length`. */
@inline(__always)
public func jsLength(_ s: String) -> Int { s.utf16.count }

/** `s.substring(start, end)`. */
public func jsSubstring(_ s: String, _ start: Int, _ end: Int? = nil) -> String {
    let n = s.utf16.count
    var a = max(0, min(start, n))
    var b = max(0, min(end ?? n, n))
    if a > b { swap(&a, &b) }
    let u = s.utf16
    let ia = u.index(u.startIndex, offsetBy: a)
    let ib = u.index(ia, offsetBy: b - a)
    return String(u[ia..<ib]) ?? String(decoding: Array(u[ia..<ib]), as: UTF16.self)
}

/** `s.indexOf(sub, from)` in UTF-16 units; -1 when absent. */
public func jsIndexOf(_ s: String, _ sub: String, _ from: Int = 0) -> Int {
    let h = Array(s.utf16)
    let n = Array(sub.utf16)
    if n.isEmpty { return min(max(0, from), h.count) }
    if n.count > h.count { return -1 }
    var i = max(0, from)
    while i + n.count <= h.count {
        if h[i] == n[0] {
            var ok = true
            for k in 1..<n.count where h[i + k] != n[k] {
                ok = false
                break
            }
            if ok { return i }
        }
        i += 1
    }
    return -1
}

/** `s.lastIndexOf(sub)`; -1 when absent. */
public func jsLastIndexOf(_ s: String, _ sub: String) -> Int {
    let h = Array(s.utf16)
    let n = Array(sub.utf16)
    if n.count > h.count { return -1 }
    var i = h.count - n.count
    while i >= 0 {
        if Array(h[i..<(i + n.count)]) == n { return i }
        i -= 1
    }
    return -1
}

/** `s.trim()`. */
@inline(__always)
public func jsTrim(_ s: String) -> String {
    s.trimmingCharacters(in: .whitespacesAndNewlines)
}

/** `s.split(sep)` with a string separator. */
public func jsSplit(_ s: String, _ sep: String) -> [String] {
    s.components(separatedBy: sep)
}

// ---------------------------------------------------------------------------
// RegExp
// ---------------------------------------------------------------------------

/** A compiled JavaScript-style regular expression (ICU underneath). */
public final class JSRegex {
    public let regex: NSRegularExpression

    public init(_ pattern: String, ignoreCase: Bool = false) {
        var opts: NSRegularExpression.Options = []
        if ignoreCase { opts.insert(.caseInsensitive) }
        // swiftlint:disable:next force_try
        regex = try! NSRegularExpression(pattern: pattern, options: opts)
    }

    private func range(_ s: String) -> NSRange { NSRange(location: 0, length: s.utf16.count) }

    /** `re.test(s)`. */
    public func test(_ s: String) -> Bool {
        regex.firstMatch(in: s, options: [], range: range(s)) != nil
    }

    /** `re.exec(s)`: group 0…n (nil for unmatched groups), or nil when no match. */
    public func exec(_ s: String) -> [String?]? {
        guard let m = regex.firstMatch(in: s, options: [], range: range(s)) else { return nil }
        return groups(m, s)
    }

    /** Every match (`matchAll` / a global `exec` loop). */
    public func matchAll(_ s: String) -> [[String?]] {
        regex.matches(in: s, options: [], range: range(s)).map { groups($0, s) }
    }

    /** Every match with its UTF-16 range. */
    public func matchesWithRanges(_ s: String) -> [(groups: [String?], range: NSRange)] {
        regex.matches(in: s, options: [], range: range(s)).map { (groups($0, s), $0.range) }
    }

    private func groups(_ m: NSTextCheckingResult, _ s: String) -> [String?] {
        let ns = s as NSString
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
    }

    /** `s.replace(/re/g, fn)`. */
    public func replace(_ s: String, global: Bool = true, _ fn: ([String?]) -> String) -> String {
        let ns = s as NSString
        let all = regex.matches(in: s, options: [], range: range(s))
        let matches = global ? all : Array(all.prefix(1))
        if matches.isEmpty { return s }
        var out = ""
        var last = 0
        for m in matches {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += fn(groups(m, s))
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    /** `s.replace(/re/g, literal)`. */
    public func replace(_ s: String, with literal: String, global: Bool = true) -> String {
        replace(s, global: global) { _ in literal }
    }

    /** `s.split(/re/)`. */
    public func split(_ s: String) -> [String] {
        let ns = s as NSString
        var out: [String] = []
        var last = 0
        for m in regex.matches(in: s, options: [], range: range(s)) where m.range.length > 0 {
            out.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        out.append(ns.substring(from: last))
        return out
    }
}

/** JavaScript `ToInt32` (what `|`, `&`, `<<` apply to their operands). */
public func jsToInt32(_ x: Double) -> Int32 {
    if !x.isFinite { return 0 }
    let t = x.rounded(.towardZero)
    let m = t.truncatingRemainder(dividingBy: 4_294_967_296)
    let u = m < 0 ? m + 4_294_967_296 : m
    return Int32(bitPattern: UInt32(u))
}

/** JavaScript `ToUint32` (`x >>> 0`). */
public func jsToUint32(_ x: Double) -> UInt32 { UInt32(bitPattern: jsToInt32(x)) }

/** JavaScript `Number(v)`. */
public func jsToNumber(_ value: Any?) -> Double {
    guard let v = flattenOptional(value) else { return 0 }
    if let b = jsBool(v) { return b ? 1 : 0 }
    if let n = jsNumber(v) { return n }
    if let s = v as? String {
        let t = jsTrim(s)
        if t.isEmpty { return 0 }
        if t == "Infinity" || t == "+Infinity" { return .infinity }
        if t == "-Infinity" { return -.infinity }
        let lower = t.lowercased()
        if lower.hasPrefix("0x") || lower.hasPrefix("0o") || lower.hasPrefix("0b") {
            let radix = lower.hasPrefix("0x") ? 16 : lower.hasPrefix("0o") ? 8 : 2
            guard let n = UInt64(String(t.dropFirst(2)), radix: radix) else { return .nan }
            return Double(n)
        }
        // Strict decimal literal only (no trailing garbage, no "inf"/"nan" words).
        let ok = t.unicodeScalars.allSatisfy { "0123456789+-.eE".unicodeScalars.contains($0) }
        if !ok { return .nan }
        var text = t
        if text.hasSuffix(".") { text.removeLast() }
        if text.hasPrefix(".") { text = "0" + text }
        if text.hasPrefix("-.") { text = "-0" + text.dropFirst() }
        if text.hasPrefix("+.") { text = "0" + text.dropFirst() }
        return Double(text) ?? .nan
    }
    if asArray(v) != nil {
        let s = jsString(v)
        return s.isEmpty ? 0 : jsToNumber(s)
    }
    return .nan
}

/** `s.split(/\s+/)`. */
private let WHITESPACE_RUN = JSRegex("\\s+")
public func jsSplitWhitespace(_ s: String) -> [String] { WHITESPACE_RUN.split(s) }
