package dev.elpian.core.util

/**
 * JSON values as plain Kotlin data, with JavaScript's number model: every
 * number is a [Double] (integers print without a fraction), objects are
 * insertion-ordered [MutableMap]s, arrays are [MutableList]s. This mirrors
 * the TypeScript core exactly, so the two engines read guest payloads alike.
 */
typealias JsonMap = MutableMap<String, Any?>

object Json {
    fun parse(text: String): Any? = Parser(text).parseDocument()

    /** Parse, or null when [text] is not valid JSON. */
    fun parseOrNull(text: String?): Any? = if (text.isNullOrEmpty()) null else try {
        parse(text)
    } catch (_: JsonException) {
        null
    }

    fun stringify(value: Any?): String = StringBuilder().also { write(it, value) }.toString()

    fun quote(s: String): String = StringBuilder().also { writeString(it, s) }.toString()

    private fun write(out: StringBuilder, v: Any?) {
        when (v) {
            null -> out.append("null")
            is String -> writeString(out, v)
            is Boolean -> out.append(if (v) "true" else "false")
            is Number -> out.append(formatNumber(v.toDouble()))
            is Map<*, *> -> {
                out.append('{')
                var first = true
                for ((k, value) in v) {
                    if (!first) out.append(',')
                    first = false
                    writeString(out, k.toString())
                    out.append(':')
                    write(out, value)
                }
                out.append('}')
            }
            is Iterable<*> -> {
                out.append('[')
                var first = true
                for (e in v) {
                    if (!first) out.append(',')
                    first = false
                    write(out, e)
                }
                out.append(']')
            }
            is Array<*> -> write(out, v.asList())
            is DoubleArray -> write(out, v.asList())
            is IntArray -> write(out, v.asList())
            is JsonSerializable -> write(out, v.toJson())
            else -> writeString(out, v.toString())
        }
    }

    /** JavaScript's `Number.prototype.toString` for finite values; non-finite → null. */
    fun formatNumber(d: Double): String {
        if (d.isNaN() || d.isInfinite()) return "null"
        if (d == Math.rint(d) && Math.abs(d) < 1e21) {
            val l = d.toLong()
            return if (l == 0L && 1.0 / d < 0) "0" else l.toString()
        }
        val s = d.toString()
        // Kotlin prints 1.0E-7; JavaScript prints 1e-7.
        return if (s.contains('E')) {
            val (mant, exp) = s.split('E')
            val m = if (mant.endsWith(".0")) mant.dropLast(2) else mant
            val e = exp.toInt()
            "${m}e${if (e > 0) "+" else ""}$e"
        } else s
    }

    private fun writeString(out: StringBuilder, s: String) {
        out.append('"')
        for (c in s) {
            when (c) {
                '"' -> out.append("\\\"")
                '\\' -> out.append("\\\\")
                '\n' -> out.append("\\n")
                '\r' -> out.append("\\r")
                '\t' -> out.append("\\t")
                '\b' -> out.append("\\b")
                '\u000C' -> out.append("\\f")
                else -> if (c < ' ' || c == ' ' || c == ' ') {
                    out.append("\\u").append(String.format("%04x", c.code))
                } else out.append(c)
            }
        }
        out.append('"')
    }

    private class Parser(val s: String) {
        var i = 0

        fun parseDocument(): Any? {
            ws()
            val v = value()
            ws()
            if (i != s.length) fail("trailing characters")
            return v
        }

        fun fail(msg: String): Nothing = throw JsonException("$msg at $i")

        fun ws() {
            while (i < s.length && (s[i] == ' ' || s[i] == '\n' || s[i] == '\r' || s[i] == '\t')) i++
        }

        fun value(): Any? {
            if (i >= s.length) fail("unexpected end")
            return when (s[i]) {
                '{' -> obj()
                '[' -> arr()
                '"' -> str()
                't' -> lit("true", true)
                'f' -> lit("false", false)
                'n' -> lit("null", null)
                else -> num()
            }
        }

        fun lit(word: String, v: Any?): Any? {
            if (!s.startsWith(word, i)) fail("bad literal")
            i += word.length
            return v
        }

        fun obj(): JsonMap {
            val m = LinkedHashMap<String, Any?>()
            i++
            ws()
            if (i < s.length && s[i] == '}') {
                i++
                return m
            }
            while (true) {
                ws()
                if (i >= s.length || s[i] != '"') fail("expected key")
                val k = str()
                ws()
                if (i >= s.length || s[i] != ':') fail("expected ':'")
                i++
                ws()
                m[k] = value()
                ws()
                if (i >= s.length) fail("unterminated object")
                if (s[i] == ',') {
                    i++
                    continue
                }
                if (s[i] == '}') {
                    i++
                    return m
                }
                fail("expected ',' or '}'")
            }
        }

        fun arr(): MutableList<Any?> {
            val l = ArrayList<Any?>()
            i++
            ws()
            if (i < s.length && s[i] == ']') {
                i++
                return l
            }
            while (true) {
                ws()
                l.add(value())
                ws()
                if (i >= s.length) fail("unterminated array")
                if (s[i] == ',') {
                    i++
                    continue
                }
                if (s[i] == ']') {
                    i++
                    return l
                }
                fail("expected ',' or ']'")
            }
        }

        fun str(): String {
            i++
            val sb = StringBuilder()
            while (true) {
                if (i >= s.length) fail("unterminated string")
                val c = s[i++]
                when (c) {
                    '"' -> return sb.toString()
                    '\\' -> {
                        if (i >= s.length) fail("bad escape")
                        when (val e = s[i++]) {
                            '"' -> sb.append('"')
                            '\\' -> sb.append('\\')
                            '/' -> sb.append('/')
                            'b' -> sb.append('\b')
                            'f' -> sb.append('\u000C')
                            'n' -> sb.append('\n')
                            'r' -> sb.append('\r')
                            't' -> sb.append('\t')
                            'u' -> {
                                if (i + 4 > s.length) fail("bad unicode escape")
                                sb.append(s.substring(i, i + 4).toInt(16).toChar())
                                i += 4
                            }
                            else -> fail("bad escape '$e'")
                        }
                    }
                    else -> sb.append(c)
                }
            }
        }

        fun num(): Double {
            val start = i
            if (i < s.length && s[i] == '-') i++
            while (i < s.length && (s[i].isDigit() || s[i] == '.' || s[i] == 'e' || s[i] == 'E' || s[i] == '+' || s[i] == '-')) i++
            if (start == i) fail("unexpected character '${s[i]}'")
            return s.substring(start, i).toDoubleOrNull() ?: fail("bad number")
        }
    }
}

class JsonException(message: String) : RuntimeException(message)

/** Objects that know their JSON form. */
interface JsonSerializable {
    fun toJson(): Any?
}

// ---------------------------------------------------------------------------
// Loose access, as the TypeScript helpers (`toNumber`, `isMap`, …)
// ---------------------------------------------------------------------------

@Suppress("UNCHECKED_CAST")
fun Any?.asMap(): JsonMap? = this as? JsonMap ?: (this as? Map<String, Any?>)?.toMutableMap()

fun isMap(v: Any?): Boolean = v is Map<*, *>

@Suppress("UNCHECKED_CAST")
fun Any?.asList(): List<Any?>? = this as? List<Any?>

/** `toNumber`: numbers and numeric strings (parseFloat prefix rules), finite only. */
fun toNumber(v: Any?): Double? = when (v) {
    is Number -> v.toDouble().takeIf { it.isFinite() }
    is String -> parseFloatPrefix(v)?.takeIf { it.isFinite() }
    else -> null
}

fun toInt(v: Any?): Int? = toNumber(v)?.let { if (it >= 0) Math.floor(it).toInt() else Math.ceil(it).toInt() }

fun toStr(v: Any?): String? = when (v) {
    null -> null
    is String -> v
    is Number -> Json.formatNumber(v.toDouble())
    else -> v.toString()
}

/** JavaScript `parseFloat`: the longest numeric prefix after leading whitespace. */
fun parseFloatPrefix(s: String): Double? {
    val m = FLOAT_PREFIX.find(s.trimStart()) ?: return null
    val t = m.value
    if (t.isEmpty() || t == "-" || t == "+" || t == ".") return null
    return when {
        t.endsWith("Infinity") -> if (t.startsWith("-")) Double.NEGATIVE_INFINITY else Double.POSITIVE_INFINITY
        else -> t.toDoubleOrNull()
    }
}

private val FLOAT_PREFIX = Regex("^[+-]?(Infinity|(\\d+\\.?\\d*|\\.\\d+)([eE][+-]?\\d+)?)")

/** JavaScript truthiness of `String(v)` for values coming from JSON. */
fun jsString(v: Any?): String = when (v) {
    null -> "null"
    is String -> v
    is Number -> Json.formatNumber(v.toDouble())
    is Boolean -> v.toString()
    is Map<*, *> -> "[object Object]"
    is List<*> -> v.joinToString(",") { if (it == null) "" else jsString(it) }
    else -> v.toString()
}

/** Parse a VM payload: JSON when it is JSON, a bare string otherwise. */
fun parseVmPayload(payload: String?): Any? {
    if (payload.isNullOrEmpty()) return null
    return try {
        Json.parse(payload)
    } catch (_: JsonException) {
        if (payload.length >= 2 && payload.startsWith("\"") && payload.endsWith("\"")) payload.substring(1, payload.length - 1) else payload
    }
}

fun unwrapHostArgs(parsed: Any?): Any? = if (parsed is List<*>) parsed.firstOrNull() else parsed

fun asHostArgs(parsed: Any?): List<Any?> = if (parsed is List<*>) parsed.toList() else listOf(parsed)

fun normalizedArgs(payload: String?): JsonMap = unwrapHostArgs(parseVmPayload(payload)).asMap() ?: LinkedHashMap()

fun coerceJsonMap(value: Any?): JsonMap? {
    value.asMap()?.let { return it }
    if (value !is String) return null
    return Json.parseOrNull(value).asMap()
}

fun deepEqual(a: Any?, b: Any?): Boolean {
    if (a === b) return true
    if (a == null || b == null) return false
    if (a is Number && b is Number) return a.toDouble() == b.toDouble()
    if (a is List<*> && b is List<*>) {
        if (a.size != b.size) return false
        for (i in a.indices) if (!deepEqual(a[i], b[i])) return false
        return true
    }
    if (a is Map<*, *> && b is Map<*, *>) {
        if (a.size != b.size) return false
        for ((k, v) in a) {
            if (!b.containsKey(k)) return false
            if (!deepEqual(v, b[k])) return false
        }
        return true
    }
    if (a is DoubleArray && b is DoubleArray) return a.contentEquals(b)
    return a == b
}

fun deepMerge(base: Map<String, Any?>, patch: Map<String, Any?>): JsonMap {
    val result = LinkedHashMap(base)
    for ((k, pv) in patch) {
        val bv = result[k]
        result[k] = if (pv is Map<*, *> && bv is Map<*, *>) deepMerge(bv.asMap()!!, pv.asMap()!!) else pv
    }
    return result
}

/** Stable string form of a JSON value (sorted keys) — a cache key. */
fun stableKey(v: Any?): String = when (v) {
    is Map<*, *> -> v.keys.map { it.toString() }.sorted().joinToString(",", "{", "}") { Json.quote(it) + ":" + stableKey(v[it]) }
    is List<*> -> v.joinToString(",", "[", "]") { stableKey(it) }
    else -> Json.stringify(v)
}

fun clamp(v: Double, lo: Double, hi: Double): Double = if (v < lo) lo else if (v > hi) hi else v

fun jsonMapOf(vararg pairs: Pair<String, Any?>): JsonMap = linkedMapOf(*pairs)
