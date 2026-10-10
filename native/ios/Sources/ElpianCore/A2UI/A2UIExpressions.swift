import Foundation

/**
 * The `formatString` template language (a2ui/expressions.ts): literal text
 * with `${…}` interpolations, `\${` as an escaped literal marker. Inside an
 * interpolation:
 *
 *   - literals: `'…'` / `"…"` strings (backslash escapes), numbers (`-1.5e3`,
 *     `.5`, `+1`, `1.`), `true`, `false`, `null`;
 *   - data paths: `/absolute/path`, `relative/path`, `./x`, `../x`;
 *   - function calls with named arguments: `formatDate(value: /d, format: 'yyyy')`
 *     (arguments are themselves expressions; a trailing comma is allowed);
 *   - nested interpolations: `${${/path}}`.
 *
 * Expressions nest at most [MAX_EXPRESSION_DEPTH] deep (interpolations and
 * function arguments both count). [parseExpressionTemplate] returns the parts with
 * adjacent string literals joined — the representation `expressions.yaml`
 * compares against.
 *
 * Parts are JSON values: a `String`, a `Double`, a `Bool`, a path part
 * `{"path": "…"}` or a call part `{"call": "…", "args": {…}, "returnType": "any"}`
 * ([JSONObject]s). A template value may also be nil (`null`), which produces
 * no part.
 */
public let MAX_EXPRESSION_DEPTH = 100

/** A parsed template value: String, Double, Bool, nil, or a path / call [JSONObject]. */
public typealias TemplateValue = Any?

private let NUMBER_LITERAL = JSRegex("^[+-]?([0-9]+\\.?[0-9]*|\\.[0-9]+)([eE][+-]?[0-9]+)?$")

private func isIdentChar(_ c: UnicodeScalar) -> Bool {
    switch c {
    case "A"..."Z", "a"..."z", "0"..."9", "_", "-", ".", "/", "~", "$", "@", "#", "[", "]": return true
    default: return false
    }
}

private func isArgNameChar(_ c: UnicodeScalar) -> Bool {
    switch c {
    case "A"..."Z", "a"..."z", "0"..."9", "_": return true
    default: return false
    }
}

private func isDigit(_ c: UnicodeScalar?) -> Bool {
    guard let c = c else { return false }
    return c >= "0" && c <= "9"
}

/** A path part (`{"path": …}`). */
public func templatePathPart(_ path: String) -> JSONObject { JSONObject([("path", path)]) }

/** A call part (`{"call": …, "args": …, "returnType": "any"}`). */
public func templateCallPart(_ name: String, _ args: JSONObject) -> JSONObject {
    JSONObject([("call", name), ("args", args), ("returnType", "any")])
}

private struct TemplateParser {
    let s: [UnicodeScalar]
    var i = 0

    init(_ s: String) { self.s = Array(s.unicodeScalars) }

    func peek(_ offset: Int = 0) -> UnicodeScalar? {
        let k = i + offset
        return k >= 0 && k < s.count ? s[k] : nil
    }

    func text(_ from: Int, _ to: Int) -> String {
        let a = max(0, min(from, s.count)), b = max(a, min(to, s.count))
        var out = String.UnicodeScalarView()
        out.append(contentsOf: s[a..<b])
        return String(out)
    }

    mutating func skipWs() {
        while i < s.count, s[i].properties.isWhitespace { i += 1 }
    }

    /** The body of one `${…}` whose `${` has been consumed; leaves `}` consumed. */
    mutating func interpolation(_ depth: Int) throws -> TemplateValue {
        if depth > MAX_EXPRESSION_DEPTH { throw parseError("Max recursion depth (\(MAX_EXPRESSION_DEPTH)) exceeded in expression") }
        skipWs()
        if i >= s.count { throw parseError("Unclosed interpolation: expected \"}\"") }
        let value = try expression(depth)
        skipWs()
        if i >= s.count { throw parseError("Unclosed interpolation: expected \"}\"") }
        if peek() != "}" { throw parseError("Unexpected characters \"\(text(i, i + 10))\" in expression") }
        i += 1
        return value
    }

    mutating func expression(_ depth: Int) throws -> TemplateValue {
        if depth > MAX_EXPRESSION_DEPTH { throw parseError("Max recursion depth (\(MAX_EXPRESSION_DEPTH)) exceeded in expression") }
        skipWs()
        guard let c = peek() else { throw parseError("Unclosed interpolation: expected an expression") }
        if c == "$" && peek(1) == "{" {
            i += 2
            return try interpolation(depth + 1)
        }
        if c == "'" || c == "\"" { return try stringLiteral(c) }
        if startsNumber() { return try number() }
        let start = i
        while i < s.count, isIdentChar(s[i]), !(s[i] == "$" && peek(1) == "{") { i += 1 }
        let token = text(start, i)
        if token.isEmpty { throw parseError("Unexpected characters \"\(text(i, i + 10))\" in expression") }
        let save = i
        skipWs()
        if peek() == "(" {
            i += 1
            return try call(token, depth)
        }
        i = save
        if token == "true" { return true }
        if token == "false" { return false }
        if token == "null" { return nil }
        return templatePathPart(token)
    }

    func startsNumber() -> Bool {
        guard let c = peek() else { return false }
        if isDigit(c) { return true }
        if c == "." { return isDigit(peek(1)) }
        if c == "+" || c == "-" { return isDigit(peek(1)) || (peek(1) == "." && isDigit(peek(2))) }
        return false
    }

    mutating func number() throws -> Double {
        let start = i
        if peek() == "+" || peek() == "-" { i += 1 }
        while i < s.count {
            let ch = s[i]
            if isDigit(ch) || ch == "." {
                i += 1
            } else if ch == "e" || ch == "E" {
                i += 1
                if peek() == "+" || peek() == "-" { i += 1 }
            } else {
                break
            }
        }
        let literal = text(start, i)
        if !NUMBER_LITERAL.test(literal) { throw parseError("Invalid number literal \"\(literal)\"") }
        let value = jsToNumber(literal)
        if !value.isFinite { throw parseError("Number literal \"\(literal)\" is out of range") }
        return value == 0 ? 0 : value
    }

    mutating func stringLiteral(_ quote: UnicodeScalar) throws -> String {
        i += 1
        var out = String.UnicodeScalarView()
        while i < s.count {
            let ch = s[i]
            i += 1
            if ch == quote { return String(out) }
            if ch == "\\" {
                let next = peek()
                i += 1
                switch next {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case let n?: out.append(n)
                case nil: break
                }
            } else {
                out.append(ch)
            }
        }
        throw parseError("Unclosed string literal in expression")
    }

    mutating func call(_ name: String, _ depth: Int) throws -> JSONObject {
        let args = JSONObject()
        skipWs()
        if peek() == ")" {
            i += 1
            return templateCallPart(name, args)
        }
        while true {
            skipWs()
            let start = i
            while i < s.count, isArgNameChar(s[i]) { i += 1 }
            let argName = text(start, i)
            skipWs()
            if argName.isEmpty || peek() != ":" { throw parseError("Expected \":\" after argument name in call to \(name)()") }
            i += 1
            args[argName] = try expression(depth + 1)
            skipWs()
            let c = peek()
            if c == "," {
                i += 1
                skipWs()
                if peek() == ")" {
                    i += 1
                    break
                }
                continue
            }
            if c == ")" {
                i += 1
                break
            }
            throw parseError("Expected \",\" or \")\" after function arguments in call to \(name)()")
        }
        return templateCallPart(name, args)
    }
}

/** Parse a `formatString` template into its parts (adjacent literals joined). */
public func parseExpressionTemplate(_ input: String) throws -> [Any?] {
    var parts: [Any?] = []
    var literal = ""
    func flush() {
        if !literal.isEmpty { parts.append(literal) }
        literal = ""
    }
    var p = TemplateParser(input)
    let s = p.s
    while p.i < s.count {
        let ch = s[p.i]
        if ch == "\\" && p.peek(1) == "$" && p.peek(2) == "{" {
            literal += "${"
            p.i += 3
            continue
        }
        if ch == "$" && p.peek(1) == "{" {
            p.i += 2
            let value = flattenOptional(try p.interpolation(1))
            guard let v = value else { continue }
            if let str = v as? String {
                literal += str
            } else {
                flush()
                parts.append(v)
            }
            continue
        }
        literal.unicodeScalars.append(ch)
        p.i += 1
    }
    flush()
    return parts
}

private let INTERPOLATION = JSRegex("(^|[^\\\\])\\$\\{")

/** True when [input] contains an interpolation (an unescaped `${`). */
public func hasInterpolation(_ input: String) -> Bool {
    INTERPOLATION.test(input)
}
