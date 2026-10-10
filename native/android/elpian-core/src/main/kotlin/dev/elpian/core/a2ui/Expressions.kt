package dev.elpian.core.a2ui

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
 * Expressions nest at most [MAX_EXPRESSION_DEPTH] deep (interpolations
 * and function arguments both count). [parseTemplate] returns the parts with
 * adjacent string literals joined — the representation `expressions.yaml`
 * compares against.
 *
 * Template values are JSON-shaped: a `String`, `Double`, `Boolean`, `null`,
 * a path part `{"path": …}` or a call part `{"call", "args", "returnType": "any"}`
 * (see [pathPart] / [callPart]).
 */
const val MAX_EXPRESSION_DEPTH = 100

private val IDENT_CHAR = Regex("[A-Za-z0-9_\\-./~$@#\\[\\]]")
private val ARG_NAME_CHAR = Regex("[A-Za-z0-9_]")
private val NUMBER_LITERAL = Regex("^[+-]?([0-9]+\\.?[0-9]*|\\.[0-9]+)([eE][+-]?[0-9]+)?$")
private val INTERPOLATION = Regex("(^|[^\\\\])\\$\\{")

fun pathPart(path: String): MutableMap<String, Any?> = linkedMapOf("path" to path)

fun callPart(name: String, args: Map<String, Any?>): MutableMap<String, Any?> = linkedMapOf("call" to name, "args" to args, "returnType" to "any")

/** JavaScript's `\s`. */
internal fun isJsSpace(c: Char): Boolean = c.isWhitespace() || c == ' ' || c == '﻿'

private class TemplateParser(val s: String) {
    var i = 0

    fun peek(offset: Int = 0): String = if (i + offset < s.length) s[i + offset].toString() else ""

    fun skipWs() {
        while (i < s.length && isJsSpace(s[i])) i++
    }

    private fun snippet(): String = s.substring(i, minOf(s.length, i + 10))

    /** The body of one `${…}` whose `${` has been consumed; leaves `}` consumed. */
    fun interpolation(depth: Int): Any? {
        if (depth > MAX_EXPRESSION_DEPTH) throw parseError("Max recursion depth ($MAX_EXPRESSION_DEPTH) exceeded in expression")
        skipWs()
        if (i >= s.length) throw parseError("Unclosed interpolation: expected \"}\"")
        val value = expression(depth)
        skipWs()
        if (i >= s.length) throw parseError("Unclosed interpolation: expected \"}\"")
        if (peek() != "}") throw parseError("Unexpected characters \"${snippet()}\" in expression")
        i++
        return value
    }

    fun expression(depth: Int): Any? {
        if (depth > MAX_EXPRESSION_DEPTH) throw parseError("Max recursion depth ($MAX_EXPRESSION_DEPTH) exceeded in expression")
        skipWs()
        val c = peek()
        if (c == "") throw parseError("Unclosed interpolation: expected an expression")
        if (c == "$" && peek(1) == "{") {
            i += 2
            return interpolation(depth + 1)
        }
        if (c == "'" || c == "\"") return stringLiteral(c[0])
        if (startsNumber()) return number()
        val start = i
        while (i < s.length && IDENT_CHAR.matches(s[i].toString()) && !(s[i] == '$' && peek(1) == "{")) i++
        val token = s.substring(start, i)
        if (token == "") throw parseError("Unexpected characters \"${snippet()}\" in expression")
        val save = i
        skipWs()
        if (peek() == "(") {
            i++
            return call(token, depth)
        }
        i = save
        if (token == "true") return true
        if (token == "false") return false
        if (token == "null") return null
        return pathPart(token)
    }

    private fun digit(ch: String): Boolean = ch.length == 1 && ch[0] in '0'..'9'

    private fun startsNumber(): Boolean {
        val c = peek()
        if (digit(c)) return true
        if (c == ".") return digit(peek(1))
        if (c == "+" || c == "-") return digit(peek(1)) || (peek(1) == "." && digit(peek(2)))
        return false
    }

    private fun number(): Double {
        val start = i
        if (peek() == "+" || peek() == "-") i++
        while (i < s.length) {
            val ch = s[i]
            if (ch in '0'..'9' || ch == '.') i++
            else if (ch == 'e' || ch == 'E') {
                i++
                if (peek() == "+" || peek() == "-") i++
            } else break
        }
        val text = s.substring(start, i)
        if (!NUMBER_LITERAL.matches(text)) throw parseError("Invalid number literal \"$text\"")
        val value = text.toDouble()
        if (!value.isFinite()) throw parseError("Number literal \"$text\" is out of range")
        return if (value == 0.0) 0.0 else value
    }

    private fun stringLiteral(quote: Char): String {
        i++
        val out = StringBuilder()
        while (i < s.length) {
            val ch = s[i++]
            if (ch == quote) return out.toString()
            if (ch == '\\') {
                val next = if (i < s.length) s[i++].toString() else ""
                out.append(
                    when (next) {
                        "n" -> "\n"
                        "t" -> "\t"
                        "r" -> "\r"
                        else -> next
                    },
                )
            } else out.append(ch)
        }
        throw parseError("Unclosed string literal in expression")
    }

    private fun call(name: String, depth: Int): MutableMap<String, Any?> {
        val args = LinkedHashMap<String, Any?>()
        skipWs()
        if (peek() == ")") {
            i++
            return callPart(name, args)
        }
        while (true) {
            skipWs()
            val start = i
            while (i < s.length && ARG_NAME_CHAR.matches(s[i].toString())) i++
            val argName = s.substring(start, i)
            skipWs()
            if (argName.isEmpty() || peek() != ":") throw parseError("Expected \":\" after argument name in call to $name()")
            i++
            args[argName] = expression(depth + 1)
            skipWs()
            val c = peek()
            if (c == ",") {
                i++
                skipWs()
                if (peek() == ")") {
                    i++
                    break
                }
                continue
            }
            if (c == ")") {
                i++
                break
            }
            throw parseError("Expected \",\" or \")\" after function arguments in call to $name()")
        }
        return callPart(name, args)
    }
}

/** Parse a `formatString` template into its parts (adjacent literals joined). */
fun parseTemplate(input: String): List<Any?> {
    val parts = ArrayList<Any?>()
    val literal = StringBuilder()
    fun flush() {
        if (literal.isNotEmpty()) parts.add(literal.toString())
        literal.setLength(0)
    }
    val p = TemplateParser(input)
    while (p.i < input.length) {
        val ch = input[p.i]
        if (ch == '\\' && p.i + 2 < input.length && input[p.i + 1] == '$' && input[p.i + 2] == '{') {
            literal.append("\${")
            p.i += 3
            continue
        }
        if (ch == '$' && p.i + 1 < input.length && input[p.i + 1] == '{') {
            p.i += 2
            val value = p.interpolation(1) ?: continue
            if (value is String) literal.append(value)
            else {
                flush()
                parts.add(value)
            }
            continue
        }
        literal.append(ch)
        p.i++
    }
    flush()
    return parts
}

/** True when [input] contains an interpolation (an unescaped `${`). */
fun hasInterpolation(input: String): Boolean = INTERPOLATION.containsMatchIn(input)
