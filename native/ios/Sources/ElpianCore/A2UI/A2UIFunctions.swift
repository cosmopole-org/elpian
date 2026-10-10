import Foundation

/**
 * The basic catalog's client-side functions (a2ui/functions.ts), implemented
 * as the basic catalog implementation guide describes them: validation
 * (`required`, `regex`, `length`, `numeric`, `email`), formatting
 * (`formatString`, `formatNumber`, `formatCurrency`, `formatDate`,
 * `pluralize`), logic (`and`, `or`, `not`) and the `openUrl` side effect.
 *
 * A function receives its arguments already resolved (bindings read, nested
 * calls evaluated) and a [FunctionContext]; only `formatString` reaches back
 * into the context, to evaluate the expressions inside its template.
 *
 * Platform mapping: `Intl.NumberFormat` → `NumberFormatter` (half-up
 * rounding, as Intl's half-expand), `Intl.DateTimeFormat` names →
 * `DateFormatter` patterns in the locale, `Intl.PluralRules` → the CLDR
 * cardinal rules of common languages ([pluralCategory]; other languages use
 * the English rule). Dates use the context's time zone (the device's by
 * default), where the browser uses its local zone.
 */
public protocol FunctionContext {
    var locale: String { get }
    /** The zone dates are read and formatted in (the TypeScript renderer's local time). */
    var timeZone: TimeZone { get }
    /** Resolve a data path (relative paths against the current scope). */
    func read(_ path: String) throws -> Any?
    /** Evaluate a function call with unresolved (expression) arguments. */
    func call(_ name: String, _ args: JSONObject) throws -> Any?
    /** Open a URL (already validated); nil when the host cannot. */
    var openUrl: ((String) -> Void)? { get }
    /** The base for resolving relative URLs in `openUrl`. */
    var baseUrl: String? { get }
}

public typealias A2UIFunction = (_ args: JSONObject, _ ctx: FunctionContext) throws -> Any?

/** Stringify an interpolated value the way the protocol prescribes. */
public func stringifyValue(_ value: Any?) -> String {
    guard let v = flattenOptional(value) else { return "" }
    if let s = v as? String { return s }
    if jsNumber(v) != nil || jsBool(v) != nil { return jsString(v) }
    return JSON.stringify(v)
}

public func toBool(_ value: Any?) -> Bool {
    let v = flattenOptional(value)
    return jsBool(v) == true || (v as? String) == "true"
}

func a2uiToNum(_ value: Any?) -> Double? {
    let v = flattenOptional(value)
    if let n = jsNumber(v) { return n.isFinite ? n : nil }
    if let s = v as? String, !jsTrim(s).isEmpty {
        let n = jsToNumber(s)
        return n.isFinite ? n : nil
    }
    return nil
}

private let EMAIL = JSRegex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$")
private let CURRENCY_CODE = JSRegex("^[A-Za-z]{3}$")
private let URL_SCHEME = JSRegex("^([a-zA-Z][a-zA-Z0-9+.-]*):")

/** Evaluate one parsed template value against [ctx]. */
public func evaluateTemplateValue(_ value: Any?, _ ctx: FunctionContext) throws -> Any? {
    guard let o = flattenOptional(value) as? JSONObject else { return flattenOptional(value) }
    if o.has("path") { return try ctx.read(jsString(o["path"])) }
    return try ctx.call(jsString(o["call"]), asMap(o["args"]) ?? JSONObject())
}

/** A Foundation locale for a BCP 47 tag (`en-US` → `en_US`). */
public func a2uiLocale(_ tag: String) -> Locale {
    Locale(identifier: tag.isEmpty ? "en_US" : tag.replacingOccurrences(of: "-", with: "_"))
}

private func numberFormatter(_ locale: String, _ args: JSONObject, currency: String?) -> NumberFormatter {
    let f = NumberFormatter()
    f.locale = a2uiLocale(locale)
    if let c = currency {
        f.numberStyle = .currency
        f.currencyCode = c
    } else {
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 3
    }
    f.roundingMode = .halfUp
    f.usesGroupingSeparator = jsBool(args["grouping"]) != false
    if let decimals = a2uiToNum(args["decimals"]) {
        let d = Int(max(0, min(20, decimals.rounded(.towardZero))))
        f.minimumFractionDigits = d
        f.maximumFractionDigits = d
    }
    return f
}

public let BASIC_FUNCTIONS: [String: A2UIFunction] = [
    "required": { args, _ in
        let v = flattenOptional(args["value"])
        if v == nil { return false }
        if (v as? String) == "" { return false }
        if let a = asArray(v), a.isEmpty { return false }
        return true
    },

    "regex": { args, _ in
        guard let pattern = flattenOptional(args["pattern"]) as? String else { throw expressionError("regex: \"pattern\" must be a string") }
        guard let re = try? NSRegularExpression(pattern: pattern) else { throw expressionError("regex: invalid pattern \"\(pattern)\"") }
        let s = stringifyValue(args["value"])
        return re.firstMatch(in: s, options: [], range: NSRange(location: 0, length: s.utf16.count)) != nil
    },

    "length": { args, _ in
        let n = Double(jsLength(stringifyValue(args["value"])))
        if let min = a2uiToNum(args["min"]), n < min { return false }
        if let max = a2uiToNum(args["max"]), n > max { return false }
        return true
    },

    "numeric": { args, _ in
        guard let n = a2uiToNum(args["value"]) else { return false }
        if let min = a2uiToNum(args["min"]), n < min { return false }
        if let max = a2uiToNum(args["max"]), n > max { return false }
        return true
    },

    "email": { args, _ in
        guard let s = flattenOptional(args["value"]) as? String else { return false }
        return EMAIL.test(s)
    },

    "formatString": { args, ctx in
        guard let value = flattenOptional(args["value"]) else { return "" }
        let parts = try parseExpressionTemplate(stringifyValue(value))
        return try parts.map { stringifyValue(try evaluateTemplateValue($0, ctx)) }.joined()
    },

    "formatNumber": { args, ctx in
        guard let n = a2uiToNum(args["value"]) else { return "" }
        return numberFormatter(ctx.locale, args, currency: nil).string(from: NSNumber(value: n)) ?? jsNumberToString(n)
    },

    "formatCurrency": { args, ctx in
        guard let n = a2uiToNum(args["value"]) else { return "" }
        var currency = "USD"
        if let c = flattenOptional(args["currency"]) as? String, CURRENCY_CODE.test(c) { currency = c.uppercased() }
        return numberFormatter(ctx.locale, args, currency: currency).string(from: NSNumber(value: n)) ?? jsNumberToString(n)
    },

    "formatDate": { args, ctx in
        guard let date = parseDate(args["value"], ctx.timeZone) else { return "" }
        let format = flattenOptional(args["format"]) as? String
        return formatDatePattern(date, (format?.isEmpty ?? true) ? "yyyy-MM-dd" : format!, ctx.locale, ctx.timeZone)
    },

    "pluralize": { args, ctx in
        guard let n = a2uiToNum(args["value"]) else { return stringifyValue(args["other"]) }
        var category = pluralCategory(n, ctx.locale)
        // English (and most locales) report 0 as "other"; an explicit zero form wins.
        if n == 0 && args["zero"] != nil { category = "zero" }
        let chosen = args[category] != nil ? args[category] : args["other"]
        return stringifyValue(chosen)
    },

    "openUrl": { args, ctx in
        let resolved = try validateOpenUrl(args["url"], ctx.baseUrl)
        ctx.openUrl?(resolved)
        return nil
    },

    "and": { args, _ in
        guard let values = asArray(args["values"]) else { throw expressionError("and: \"values\" must be a list") }
        for v in values where !toBool(v) { return false }
        return true
    },

    "or": { args, _ in
        guard let values = asArray(args["values"]) else { throw expressionError("or: \"values\" must be a list") }
        for v in values where toBool(v) { return true }
        return false
    },

    "not": { args, _ in !toBool(args["value"]) },
]

/**
 * `openUrl`'s mandatory checks: resolve relative URLs against [base], then
 * allow only `http:` and `https:` (no `javascript:`, `data:`, …).
 */
public func validateOpenUrl(_ url: Any?, _ base: String?) throws -> String {
    guard let s = flattenOptional(url) as? String, !jsTrim(s).isEmpty else { throw expressionError("openUrl: \"url\" must be a non-empty string") }
    let raw = jsTrim(s)
    var resolved = raw
    if URL_SCHEME.exec(raw) == nil {
        guard let base = base, !base.isEmpty else { throw expressionError("openUrl: cannot resolve relative URL \"\(raw)\"") }
        guard let b = URL(string: base), let r = URL(string: raw, relativeTo: b) else { throw expressionError("openUrl: invalid URL \"\(raw)\"") }
        resolved = r.absoluteString
    }
    let proto = ((URL_SCHEME.exec(resolved)?[1] ?? nil) ?? "").lowercased()
    if proto != "http" && proto != "https" { throw expressionError("openUrl: the \"\(proto):\" scheme is not allowed (http and https only)") }
    return resolved
}

// ----------------------------------------------------------------------------
// Plural rules
// ----------------------------------------------------------------------------

/**
 * The CLDR cardinal plural category (`zero`, `one`, `two`, `few`, `many`,
 * `other`) of [n] in [locale] — `Intl.PluralRules.select` for the common
 * languages; others follow English.
 */
public func pluralCategory(_ n: Double, _ locale: String) -> String {
    let lang = locale.lowercased().components(separatedBy: CharacterSet(charactersIn: "-_")).first ?? "en"
    let isInt = n == n.rounded(.towardZero)
    let i = abs(n.rounded(.towardZero))
    let mod10 = i.truncatingRemainder(dividingBy: 10)
    let mod100 = i.truncatingRemainder(dividingBy: 100)
    switch lang {
    case "ja", "zh", "ko", "vi", "th", "id", "ms", "lo", "my", "yue":
        return "other"
    case "fr", "hi", "bn", "fa", "gu", "kn", "zu", "am":
        return i == 0 || i == 1 ? "one" : "other"
    case "pt":
        return (i == 0 || i == 1) && (isInt || i == 0) ? "one" : "other"
    case "ru", "uk", "be":
        if !isInt { return "other" }
        if mod10 == 1 && mod100 != 11 { return "one" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "few" }
        return "many"
    case "pl":
        if !isInt { return "other" }
        if i == 1 { return "one" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "few" }
        return "many"
    case "cs", "sk":
        if !isInt { return "many" }
        if i == 1 { return "one" }
        if (2...4).contains(i) { return "few" }
        return "other"
    case "ar":
        if !isInt { return "other" }
        if i == 0 { return "zero" }
        if i == 1 { return "one" }
        if i == 2 { return "two" }
        if (3...10).contains(mod100) { return "few" }
        if (11...99).contains(mod100) { return "many" }
        return "other"
    case "he", "iw":
        if !isInt { return "other" }
        if i == 1 { return "one" }
        if i == 2 { return "two" }
        return "other"
    default:
        return isInt && i == 1 ? "one" : "other"
    }
}

// ----------------------------------------------------------------------------
// Dates
// ----------------------------------------------------------------------------

private let DATE_ONLY = JSRegex("^(\\d{4})-(\\d{2})-(\\d{2})$")
private let TIME_ONLY = JSRegex("^(\\d{1,2}):(\\d{2})(?::(\\d{2})(?:\\.\\d+)?)?$")
private let DATE_TIME = JSRegex("^([+-]?\\d{4,6})-(\\d{2})-(\\d{2})[T ](\\d{2}):(\\d{2})(?::(\\d{2})(?:\\.(\\d+))?)?(Z|z|[+-]\\d{2}(?::?\\d{2})?)?$")

private func gregorian(_ zone: TimeZone) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = zone
    return c
}

private func makeDate(_ zone: TimeZone, _ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0, _ ms: Double = 0) -> Date? {
    var dc = DateComponents()
    dc.year = y
    dc.month = mo
    dc.day = d
    dc.hour = h
    dc.minute = mi
    dc.second = s
    guard let date = gregorian(zone).date(from: dc) else { return nil }
    return date.addingTimeInterval(ms / 1000)
}

/**
 * Parse an A2UI date value: an ISO 8601 date-time (`2026-02-02T15:17:00Z`),
 * a date (`2026-02-02`, local midnight), a time (`14:30`, today), or epoch
 * milliseconds. A date-time without an offset is local time ([zone]).
 */
public func parseDate(_ value: Any?, _ zone: TimeZone = .current) -> Date? {
    let v = flattenOptional(value)
    if let d = v as? Date { return d }
    if let n = jsNumber(v) { return n.isFinite ? Date(timeIntervalSince1970: n / 1000) : nil }
    guard let str = v as? String, !jsTrim(str).isEmpty else { return nil }
    let s = jsTrim(str)
    if let m = DATE_ONLY.exec(s) {
        return makeDate(zone, Int(m[1]!)!, Int(m[2]!)!, Int(m[3]!)!)
    }
    if let m = TIME_ONLY.exec(s) {
        let cal = gregorian(zone)
        let today = cal.dateComponents([.year, .month, .day], from: Date())
        return makeDate(zone, today.year!, today.month!, today.day!, Int(m[1]!)!, Int(m[2]!)!, Int(m[3] ?? "0") ?? 0)
    }
    if let m = DATE_TIME.exec(s) {
        let frac = m[7] ?? nil
        let ms = frac.map { Double("0." + $0).map { $0 * 1000 } ?? 0 } ?? 0
        var tz = zone
        if let off = m[8] ?? nil {
            if off == "Z" || off == "z" {
                tz = TimeZone(secondsFromGMT: 0)!
            } else {
                let sign = off.hasPrefix("-") ? -1 : 1
                let digits = off.dropFirst().replacingOccurrences(of: ":", with: "")
                let hh = Int(digits.prefix(2)) ?? 0
                let mm = digits.count >= 4 ? Int(digits.suffix(2)) ?? 0 : 0
                guard let z = TimeZone(secondsFromGMT: sign * (hh * 3600 + mm * 60)) else { return nil }
                tz = z
            }
        }
        let mo = Int(m[2]!)!, d = Int(m[3]!)!, h = Int(m[4]!)!, mi = Int(m[5]!)!, sec = Int(m[6] ?? "0") ?? 0
        if mo < 1 || mo > 12 || d < 1 || d > 31 || h > 24 || mi > 59 || sec > 59 { return nil }
        return makeDate(tz, Int(m[1]!)!, mo, d, h, mi, sec, ms)
    }
    let iso = ISO8601DateFormatter()
    if let d = iso.date(from: s) { return d }
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return iso.date(from: s)
}

private func pad(_ n: Int, _ width: Int) -> String {
    let s = String(abs(n))
    let padded = s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
    return n < 0 ? "-" + padded : padded
}

private func names(_ locale: String, _ format: String, _ date: Date, _ zone: TimeZone) -> String {
    let f = DateFormatter()
    f.locale = a2uiLocale(locale)
    f.timeZone = zone
    f.dateFormat = format
    return f.string(from: date)
}

/** Format [date] with a Unicode TR35 pattern (`yyyy-MM-dd`, `EEEE, MMM d 'at' h:mm a`, …) in [zone]. */
public func formatDatePattern(_ date: Date, _ pattern: String, _ locale: String = "en-US", _ zone: TimeZone = .current) -> String {
    let p = Array(pattern.unicodeScalars)
    var out = ""
    var i = 0
    func at(_ k: Int) -> UnicodeScalar? { k < p.count ? p[k] : nil }
    while i < p.count {
        let ch = p[i]
        if ch == "'" {
            // Quoted literal; '' is a single quote.
            if at(i + 1) == "'" {
                out += "'"
                i += 2
                continue
            }
            var j = i + 1
            while j < p.count {
                if p[j] == "'" && at(j + 1) == "'" {
                    out += "'"
                    j += 2
                    continue
                }
                if p[j] == "'" { break }
                out.unicodeScalars.append(p[j])
                j += 1
            }
            i = j + 1
            continue
        }
        let isLetter = (ch >= "A" && ch <= "Z") || (ch >= "a" && ch <= "z")
        if !isLetter {
            out.unicodeScalars.append(ch)
            i += 1
            continue
        }
        var n = 1
        while at(i + n) == ch { n += 1 }
        i += n
        out += dateField(date, Character(ch), n, locale, zone)
    }
    return out
}

private func dateField(_ d: Date, _ ch: Character, _ n: Int, _ locale: String, _ zone: TimeZone) -> String {
    let cal = gregorian(zone)
    let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: d)
    let year = c.year ?? 0, month = c.month ?? 1, day = c.day ?? 1, hour = c.hour ?? 0, minute = c.minute ?? 0, second = c.second ?? 0
    let millis = Int((Double(c.nanosecond ?? 0) / 1_000_000).rounded(.down))
    switch ch {
    case "y", "Y", "u":
        return n == 2 ? pad(year % 100, 2) : pad(year, n)
    case "M", "L":
        if n >= 4 { return names(locale, "LLLL", d, zone) }
        if n == 3 { return names(locale, "LLL", d, zone) }
        return pad(month, n)
    case "d":
        return pad(day, n)
    case "D":
        return pad(cal.ordinality(of: .day, in: .year, for: d) ?? 1, n)
    case "E", "e", "c":
        if n == 5 { return names(locale, "ccccc", d, zone) }
        if n >= 4 { return names(locale, "cccc", d, zone) }
        return names(locale, "ccc", d, zone)
    case "a":
        return hour < 12 ? "AM" : "PM"
    case "h":
        return pad(hour % 12 == 0 ? 12 : hour % 12, n)
    case "K":
        return pad(hour % 12, n)
    case "H":
        return pad(hour, n)
    case "k":
        return pad(hour == 0 ? 24 : hour, n)
    case "m":
        return pad(minute, n)
    case "s":
        return pad(second, n)
    case "S":
        return String(pad(millis, 3).prefix(n))
    case "z", "Z", "x", "X":
        let offset = zone.secondsFromGMT(for: d) / 60
        if offset == 0 && (ch == "X" || ch == "x") { return "Z" }
        let sign = offset >= 0 ? "+" : "-"
        let a = abs(offset)
        return "\(sign)\(pad(a / 60, 2)):\(pad(a % 60, 2))"
    default:
        return String(repeating: String(ch), count: n)
    }
}
