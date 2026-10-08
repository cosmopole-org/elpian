import Foundation

/**
 * JSON values as plain Swift data with JavaScript's value model — the single
 * dynamic representation every layer of the Swift core shares (util/json.ts):
 *
 *  - objects are [JSONObject]s (reference type, insertion-ordered like JS
 *    objects, integer-like keys first as JS orders them),
 *  - arrays are `[Any?]`,
 *  - every number is a `Double` (integers print without a fraction),
 *  - strings are `String`, booleans `Bool`,
 *  - `null` is `nil` (an `NSNull` coming from Foundation is read as `nil` too).
 *
 * Typed values (EdgeInsets, Alignment, colours…) may sit in these bags, as in
 * the TypeScript props objects; they serialize through [JSONSerializable].
 */
public typealias JSONValue = Any?

/** Objects that know their JSON form. */
public protocol JSONSerializable {
    func toJSON() -> Any?
}

/** An insertion-ordered JSON object with JavaScript property-order semantics. */
public final class JSONObject: Sequence, ExpressibleByDictionaryLiteral, CustomStringConvertible, JSONSerializable {
    public private(set) var keys: [String] = []
    private var storage: [String: Any?] = [:]
    /** How many leading [keys] are array indices (kept numerically ordered, as JS does). */
    private var indexKeyCount = 0

    public init() {}

    public required init(dictionaryLiteral elements: (String, Any?)...) {
        for (k, v) in elements { self[k] = v }
    }

    public init(_ pairs: [(String, Any?)]) {
        for (k, v) in pairs { self[k] = v }
    }

    /** From a Swift dictionary (its iteration order). */
    public convenience init(_ dict: [String: Any?]) {
        self.init()
        for (k, v) in dict { self[k] = v }
    }

    public var count: Int { keys.count }
    public var isEmpty: Bool { keys.isEmpty }

    /** The value for [key]; nil when absent or JSON null. */
    public subscript(key: String) -> Any? {
        get {
            guard let v = storage[key] else { return nil }
            return v
        }
        set {
            let value = flattenOptional(newValue)
            if storage.index(forKey: key) == nil {
                insertKey(key)
            }
            storage[key] = .some(value)
        }
    }

    /** Whether [key] is present (even with a null value) — JS `key in obj`. */
    public func has(_ key: String) -> Bool { storage.index(forKey: key) != nil }

    @discardableResult
    public func removeValue(forKey key: String) -> Any? {
        guard let idx = storage.index(forKey: key) else { return nil }
        let old = storage[idx].value
        storage.remove(at: idx)
        if let i = keys.firstIndex(of: key) {
            keys.remove(at: i)
            if i < indexKeyCount { indexKeyCount -= 1 }
        }
        return old
    }

    public func removeAll() {
        keys.removeAll()
        storage.removeAll()
        indexKeyCount = 0
    }

    public var values: [Any?] { keys.map { storage[$0] ?? nil } }

    /** A shallow copy (`{...obj}`). */
    public func copy() -> JSONObject {
        let c = JSONObject()
        c.keys = keys
        c.storage = storage
        c.indexKeyCount = indexKeyCount
        return c
    }

    /** `Object.assign(this, other)`. */
    public func assign(_ other: JSONObject?) {
        guard let other = other else { return }
        for (k, v) in other { self[k] = v }
    }

    public func makeIterator() -> AnyIterator<(key: String, value: Any?)> {
        var i = 0
        let ks = keys
        return AnyIterator {
            guard i < ks.count else { return nil }
            let k = ks[i]
            i += 1
            return (key: k, value: self.storage[k] ?? nil)
        }
    }

    public var description: String { JSON.stringify(self) }

    public func toJSON() -> Any? { self }

    private func insertKey(_ key: String) {
        if let n = arrayIndexValue(key) {
            var pos = indexKeyCount
            while pos > 0, let prev = arrayIndexValue(keys[pos - 1]), prev > n { pos -= 1 }
            keys.insert(key, at: pos)
            indexKeyCount += 1
        } else {
            keys.append(key)
        }
    }
}

/** A canonical JS array index ("0", "17", not "01"), as JS orders object keys. */
private func arrayIndexValue(_ key: String) -> UInt64? {
    let u = key.utf8
    guard let first = u.first, first >= 48, first <= 57, u.count <= 10 else { return nil }
    if first == 48 && u.count > 1 { return nil }
    var n: UInt64 = 0
    for c in u {
        guard c >= 48, c <= 57 else { return nil }
        n = n * 10 + UInt64(c - 48)
    }
    return n < 4_294_967_295 ? n : nil
}

private protocol OptionalProtocol {
    var wrappedAny: Any? { get }
}

extension Optional: OptionalProtocol {
    fileprivate var wrappedAny: Any? {
        switch self {
        case .none: return nil
        case .some(let w): return w
        }
    }
}

/** Collapse nested optionals (`Any??`) and NSNull into a plain `Any?`. */
public func flattenOptional(_ value: Any?) -> Any? {
    guard let v = value else { return nil }
    if let o = v as? OptionalProtocol { return flattenOptional(o.wrappedAny) }
    if v is NSNull { return nil }
    return v
}

public struct JSONError: Error, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { "JSONError: \(message)" }
}

/** `JSON.parse` / `JSON.stringify` with exact JavaScript output. */
public enum JSON {
    public static func parse(_ text: String) throws -> Any? {
        var p = JSONParser(Array(text.utf16))
        return try p.parseDocument()
    }

    /** Parse, or nil when [text] is empty or not valid JSON. */
    public static func parseOrNil(_ text: String?) -> Any? {
        guard let text = text, !text.isEmpty else { return nil }
        return try? parse(text)
    }

    public static func stringify(_ value: Any?) -> String {
        var out = ""
        write(&out, value)
        return out
    }

    /** `JSON.stringify(string)`. */
    public static func quote(_ s: String) -> String {
        var out = ""
        writeString(&out, s)
        return out
    }

    private static func write(_ out: inout String, _ raw: Any?) {
        let v = flattenOptional(raw)
        guard let v = v else {
            out += "null"
            return
        }
        if let b = v as? Bool, type(of: v) == Bool.self {
            out += b ? "true" : "false"
            return
        }
        if let d = jsNumber(v) {
            out += formatNumber(d)
            return
        }
        switch v {
        case let s as String:
            writeString(&out, s)
        case let o as JSONObject:
            out += "{"
            var first = true
            for (k, value) in o {
                if !first { out += "," }
                first = false
                writeString(&out, k)
                out += ":"
                write(&out, value)
            }
            out += "}"
        case let a as [Any?]:
            out += "["
            for (i, e) in a.enumerated() {
                if i > 0 { out += "," }
                write(&out, e)
            }
            out += "]"
        case let a as [Any]:
            write(&out, a.map { Optional($0) })
        case let d as [String: Any?]:
            write(&out, JSONObject(d))
        case let d as [String: Any]:
            write(&out, JSONObject(d.mapValues { Optional($0) }))
        case let s as JSONSerializable:
            write(&out, s.toJSON())
        case let s as Substring:
            writeString(&out, String(s))
        default:
            writeString(&out, String(describing: v))
        }
    }

    /** JavaScript's `Number.prototype.toString()` for finite values; non-finite → `null` (as JSON). */
    public static func formatNumber(_ d: Double) -> String {
        if d.isNaN || d.isInfinite { return "null" }
        return jsNumberToString(d)
    }

    private static func writeString(_ out: inout String, _ s: String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if u.value < 0x20 {
                    let hex = String(u.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        out += "\""
    }
}

/** JS `Number::toString(10)` including the special values. */
public func jsNumberToString(_ d: Double) -> String {
    if d.isNaN { return "NaN" }
    if d.isInfinite { return d < 0 ? "-Infinity" : "Infinity" }
    if d == 0 { return "0" }
    if d < 0 { return "-" + jsNumberToString(-d) }
    // Shortest round-trip digits from Swift's description ("1.2345e-07", "123.45", "1e+16").
    let desc = d.description
    var mantissa = desc
    var exp = 0
    if let e = desc.firstIndex(where: { $0 == "e" || $0 == "E" }) {
        mantissa = String(desc[desc.startIndex..<e])
        exp = Int(desc[desc.index(after: e)...]) ?? 0
    }
    var intPart = mantissa
    var fracPart = ""
    if let dot = mantissa.firstIndex(of: ".") {
        intPart = String(mantissa[mantissa.startIndex..<dot])
        fracPart = String(mantissa[mantissa.index(after: dot)...])
    }
    var digits = intPart + fracPart
    // value = 0.digits × 10^n
    var n = intPart.count + exp
    // strip leading zeros
    while digits.hasPrefix("0") && digits.count > 1 {
        digits.removeFirst()
        n -= 1
    }
    while digits.hasSuffix("0") && digits.count > 1 { digits.removeLast() }
    let k = digits.count
    if k <= n && n <= 21 {
        return digits + String(repeating: "0", count: n - k)
    }
    if 0 < n && n <= 21 {
        let i = digits.index(digits.startIndex, offsetBy: n)
        return String(digits[..<i]) + "." + String(digits[i...])
    }
    if -6 < n && n <= 0 {
        return "0." + String(repeating: "0", count: -n) + digits
    }
    let e = n - 1
    let sign = e >= 0 ? "+" : "-"
    let first = String(digits.first!)
    let rest = String(digits.dropFirst())
    return first + (rest.isEmpty ? "" : "." + rest) + "e" + sign + String(abs(e))
}

private struct JSONParser {
    let s: [UInt16]
    var i = 0

    init(_ s: [UInt16]) { self.s = s }

    func fail(_ msg: String) -> JSONError { JSONError("\(msg) at position \(i)") }

    mutating func parseDocument() throws -> Any? {
        ws()
        let v = try value()
        ws()
        if i != s.count { throw fail("Unexpected non-whitespace character after JSON") }
        return v
    }

    mutating func ws() {
        while i < s.count, s[i] == 0x20 || s[i] == 0x0A || s[i] == 0x0D || s[i] == 0x09 { i += 1 }
    }

    mutating func value() throws -> Any? {
        guard i < s.count else { throw fail("Unexpected end of JSON input") }
        switch s[i] {
        case 0x7B: return try object()
        case 0x5B: return try array()
        case 0x22: return try string()
        case 0x74: try literal("true"); return true
        case 0x66: try literal("false"); return false
        case 0x6E: try literal("null"); return nil
        default: return try number()
        }
    }

    mutating func literal(_ word: String) throws {
        for u in word.utf16 {
            guard i < s.count, s[i] == u else { throw fail("Unexpected token") }
            i += 1
        }
    }

    mutating func object() throws -> JSONObject {
        let o = JSONObject()
        i += 1
        ws()
        if i < s.count, s[i] == 0x7D {
            i += 1
            return o
        }
        while true {
            ws()
            guard i < s.count, s[i] == 0x22 else { throw fail("Expected property name") }
            let k = try string()
            ws()
            guard i < s.count, s[i] == 0x3A else { throw fail("Expected ':' after property name") }
            i += 1
            ws()
            o[k] = try value()
            ws()
            guard i < s.count else { throw fail("Unterminated object") }
            if s[i] == 0x2C {
                i += 1
                continue
            }
            if s[i] == 0x7D {
                i += 1
                return o
            }
            throw fail("Expected ',' or '}' after property value")
        }
    }

    mutating func array() throws -> [Any?] {
        var a: [Any?] = []
        i += 1
        ws()
        if i < s.count, s[i] == 0x5D {
            i += 1
            return a
        }
        while true {
            ws()
            a.append(try value())
            ws()
            guard i < s.count else { throw fail("Unterminated array") }
            if s[i] == 0x2C {
                i += 1
                continue
            }
            if s[i] == 0x5D {
                i += 1
                return a
            }
            throw fail("Expected ',' or ']' after array element")
        }
    }

    mutating func string() throws -> String {
        i += 1
        var out: [UInt16] = []
        while true {
            guard i < s.count else { throw fail("Unterminated string") }
            let c = s[i]
            i += 1
            if c == 0x22 { return String(decoding: out, as: UTF16.self) }
            if c < 0x20 { throw fail("Bad control character in string literal") }
            if c != 0x5C {
                out.append(c)
                continue
            }
            guard i < s.count else { throw fail("Bad escaped character") }
            let e = s[i]
            i += 1
            switch e {
            case 0x22: out.append(0x22)
            case 0x5C: out.append(0x5C)
            case 0x2F: out.append(0x2F)
            case 0x62: out.append(0x08)
            case 0x66: out.append(0x0C)
            case 0x6E: out.append(0x0A)
            case 0x72: out.append(0x0D)
            case 0x74: out.append(0x09)
            case 0x75:
                guard i + 4 <= s.count else { throw fail("Bad Unicode escape") }
                var v: UInt16 = 0
                for k in 0..<4 {
                    let h = s[i + k]
                    let d: UInt16
                    switch h {
                    case 0x30...0x39: d = h - 0x30
                    case 0x41...0x46: d = h - 0x41 + 10
                    case 0x61...0x66: d = h - 0x61 + 10
                    default: throw fail("Bad Unicode escape")
                    }
                    v = v * 16 + d
                }
                out.append(v)
                i += 4
            default:
                throw fail("Bad escaped character")
            }
        }
    }

    mutating func number() throws -> Double {
        let start = i
        if i < s.count, s[i] == 0x2D { i += 1 }
        guard i < s.count, isDigit(s[i]) else { throw fail("Unexpected token") }
        if s[i] == 0x30 {
            i += 1
        } else {
            while i < s.count, isDigit(s[i]) { i += 1 }
        }
        if i < s.count, s[i] == 0x2E {
            i += 1
            guard i < s.count, isDigit(s[i]) else { throw fail("Unterminated fractional number") }
            while i < s.count, isDigit(s[i]) { i += 1 }
        }
        if i < s.count, s[i] == 0x65 || s[i] == 0x45 {
            i += 1
            if i < s.count, s[i] == 0x2B || s[i] == 0x2D { i += 1 }
            guard i < s.count, isDigit(s[i]) else { throw fail("Exponent part is missing a number") }
            while i < s.count, isDigit(s[i]) { i += 1 }
        }
        let text = String(decoding: s[start..<i], as: UTF16.self)
        guard let d = Double(text) else { throw fail("Bad number") }
        return d
    }

    func isDigit(_ c: UInt16) -> Bool { c >= 0x30 && c <= 0x39 }
}

// ---------------------------------------------------------------------------
// Loose access, as the TypeScript helpers (`isMap`, `toNumber`, …)
// ---------------------------------------------------------------------------

/** `typeof v === 'number'`: any Swift numeric type (never a Bool). */
public func jsNumber(_ v: Any?) -> Double? {
    guard let v = v else { return nil }
    if v is Bool { return nil }
    switch v {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let f as Float: return Double(f)
    case let u as UInt32: return Double(u)
    case let i as Int64: return Double(i)
    case let i as Int32: return Double(i)
    case let u as UInt64: return Double(u)
    case let u as UInt: return Double(u)
    case let i as Int16: return Double(i)
    case let i as Int8: return Double(i)
    case let u as UInt16: return Double(u)
    case let u as UInt8: return Double(u)
    default: return nil
    }
}

/** `typeof v === 'boolean'`. */
public func jsBool(_ v: Any?) -> Bool? {
    guard let v = v, type(of: v) == Bool.self else { return nil }
    return v as? Bool
}

/** `isMap`: a plain object (a [JSONObject] or a Swift string-keyed dictionary). */
public func isMap(_ value: Any?) -> Bool {
    guard let v = flattenOptional(value) else { return false }
    return v is JSONObject || v is [String: Any?] || v is [String: Any]
}

/** The value as a [JSONObject] (Swift dictionaries are converted), or nil. */
public func asMap(_ value: Any?) -> JSONObject? {
    guard let v = flattenOptional(value) else { return nil }
    if let o = v as? JSONObject { return o }
    if let d = v as? [String: Any?] { return JSONObject(d) }
    if let d = v as? [String: Any] { return JSONObject(d.mapValues { Optional($0) }) }
    return nil
}

/** `Array.isArray`: the value as an array, or nil. */
public func asArray(_ value: Any?) -> [Any?]? {
    guard let v = flattenOptional(value) else { return nil }
    if let a = v as? [Any?] { return a }
    if let a = v as? [Any] { return a.map { Optional($0) } }
    return nil
}

/** Parse a VM payload: JSON when it is JSON, a bare string otherwise. */
public func parseVmPayload(_ payload: String?) -> Any? {
    guard let payload = payload, !payload.isEmpty else { return nil }
    if let parsed = try? JSON.parse(payload) { return parsed }
    if payload.utf16.count >= 2 && payload.hasPrefix("\"") && payload.hasSuffix("\"") {
        return jsSubstring(payload, 1, payload.utf16.count - 1)
    }
    return payload
}

/** The first positional argument when the payload is an argument list. */
public func unwrapHostArgs(_ parsed: Any?) -> Any? {
    if let a = asArray(parsed) { return a.isEmpty ? nil : a[0] }
    return parsed
}

/** Positional arguments, always as a list. */
public func asHostArgs(_ parsed: Any?) -> [Any?] {
    if let a = asArray(parsed) { return a }
    return [parsed]
}

/** The payload's first argument coerced to a map (empty when it is not one). */
public func normalizedArgs(_ payload: String?) -> JSONObject {
    asMap(unwrapHostArgs(parseVmPayload(payload))) ?? JSONObject()
}

/** A JSON map from a value that may itself be a JSON-encoded string. */
public func coerceJsonMap(_ value: Any?) -> JSONObject? {
    if let m = asMap(value) { return m }
    guard let s = flattenOptional(value) as? String else { return nil }
    return asMap(JSON.parseOrNil(s))
}

/** `toNumber`: finite numbers, and numeric strings by `parseFloat` rules. */
public func toNumber(_ value: Any?) -> Double? {
    let v = flattenOptional(value)
    if let n = jsNumber(v) { return n.isFinite ? n : nil }
    if let s = v as? String {
        let n = jsParseFloat(s)
        return n.isFinite ? n : nil
    }
    return nil
}

/** `toInt`: [toNumber] truncated toward zero. */
public func toInt(_ value: Any?) -> Double? {
    guard let n = toNumber(value) else { return nil }
    return n.rounded(.towardZero)
}

/** `toStr`: null stays null, everything else is `String(v)`. */
public func toStr(_ value: Any?) -> String? {
    guard let v = flattenOptional(value) else { return nil }
    if let s = v as? String { return s }
    return jsString(v)
}

/** Structural equality for JSON-shaped values. */
public func deepEqual(_ a: Any?, _ b: Any?) -> Bool {
    let a = flattenOptional(a)
    let b = flattenOptional(b)
    if a == nil && b == nil { return true }
    guard var x = a, var y = b else { return false }
    // Typed values compare by their JSON form.
    if !(x is JSONObject), jsNumber(x) == nil, let s = x as? JSONSerializable, let j = flattenOptional(s.toJSON()) { x = j }
    if !(y is JSONObject), jsNumber(y) == nil, let s = y as? JSONSerializable, let j = flattenOptional(s.toJSON()) { y = j }
    if type(of: x) is AnyClass, type(of: y) is AnyClass, (x as AnyObject) === (y as AnyObject) { return true }
    if let bx = jsBool(x) { return bx == jsBool(y) }
    if jsBool(y) != nil { return false }
    if let nx = jsNumber(x) {
        guard let ny = jsNumber(y) else { return false }
        return nx == ny
    }
    if let sx = x as? String {
        guard let sy = y as? String else { return false }
        return sx == sy
    }
    if let ax = asArray(x) {
        guard let ay = asArray(y), ax.count == ay.count else { return false }
        for i in 0..<ax.count where !deepEqual(ax[i], ay[i]) { return false }
        return true
    }
    if let mx = asMap(x) {
        guard let my = asMap(y), mx.count == my.count else { return false }
        for (k, v) in mx {
            if !my.has(k) { return false }
            if !deepEqual(v, my[k]) { return false }
        }
        return true
    }
    return false
}

/** Deep-merge [patch] into a copy of [base] (maps merge, everything else replaces). */
public func deepMerge(_ base: JSONObject, _ patch: JSONObject) -> JSONObject {
    let result = base.copy()
    for (key, pv) in patch {
        let bv = result[key]
        if let pm = asMap(pv), let bm = asMap(bv) {
            result[key] = deepMerge(bm, pm)
        } else {
            result[key] = pv
        }
    }
    return result
}

/** Stable string form of a JSON value (sorted keys) — used as a cache key. */
public func stableKey(_ value: Any?) -> String {
    let v = flattenOptional(value)
    guard let x = v else { return "null" }
    if let a = asArray(x) { return "[" + a.map { stableKey($0) }.joined(separator: ",") + "]" }
    if let m = asMap(x) {
        let keys = m.keys.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
        return "{" + keys.map { JSON.quote($0) + ":" + stableKey(m[$0]) }.joined(separator: ",") + "}"
    }
    if jsBool(x) == nil, jsNumber(x) == nil, !(x is String), let s = x as? JSONSerializable {
        return stableKey(s.toJSON())
    }
    return JSON.stringify(x)
}

public func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
    v < lo ? lo : v > hi ? hi : v
}
