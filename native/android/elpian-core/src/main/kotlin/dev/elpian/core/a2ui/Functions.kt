package dev.elpian.core.a2ui

import dev.elpian.core.util.Json
import java.math.BigDecimal
import java.math.RoundingMode
import java.net.URI
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.text.NumberFormat
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Currency
import java.util.Locale

/**
 * The basic catalog's client-side functions (a2ui/functions.ts), implemented
 * as the basic catalog implementation guide describes them: validation
 * (`required`, `regex`, `length`, `numeric`, `email`), formatting
 * (`formatString`, `formatNumber`, `formatCurrency`, `formatDate`,
 * `pluralize`), logic (`and`, `or`, `not`) and the `openUrl` side effect.
 *
 * A function receives its arguments already resolved (bindings read, nested
 * calls evaluated) and a [FunctionContext]; only `formatString` reaches
 * back into the context, to evaluate the expressions inside its template.
 *
 * Kotlin differences: number formatting uses `java.text` (CLDR data) instead
 * of `Intl.NumberFormat`, plural categories come from a small built-in rule
 * table instead of `Intl.PluralRules`, and dates are `ZonedDateTime`s in the
 * JVM's default time zone (JavaScript's local time).
 */
interface FunctionContext {
    val locale: String

    /** Resolve a data path (relative paths against the current scope). */
    fun read(path: String): Any?

    /** Evaluate a function call with unresolved (expression) arguments. */
    fun call(name: String, args: Map<String, Any?>): Any?

    /** Open a URL (already validated); null when the host cannot. */
    val openUrl: ((String) -> Unit)?

    /** The base for resolving relative URLs in `openUrl`. */
    val baseUrl: String?
}

typealias A2UIFunction = (args: Map<String, Any?>, ctx: FunctionContext) -> Any?

/** Stringify an interpolated value the way the protocol prescribes. */
fun stringifyValue(value: Any?): String = when (value) {
    null -> ""
    is String -> value
    is Number -> Json.formatNumber(value.toDouble())
    is Boolean -> value.toString()
    else -> try {
        Json.stringify(value)
    } catch (_: Exception) {
        value.toString()
    }
}

fun toBool(value: Any?): Boolean = value == true || value == "true"

private val JS_NUMBER = Regex("^[+-]?(Infinity|([0-9]+\\.?[0-9]*|\\.[0-9]+)([eE][+-]?[0-9]+)?)$")
private val JS_HEX = Regex("^0[xX][0-9a-fA-F]+$")
private val JS_BIN = Regex("^0[bB][01]+$")
private val JS_OCT = Regex("^0[oO][0-7]+$")

/** JavaScript `Number(s)` for a string (NaN when not numeric). */
fun jsNumberOfString(s: String): Double {
    val t = s.trim { isJsSpace(it) }
    if (t.isEmpty()) return 0.0
    if (JS_HEX.matches(t)) return t.substring(2).toBigInteger(16).toDouble()
    if (JS_BIN.matches(t)) return t.substring(2).toBigInteger(2).toDouble()
    if (JS_OCT.matches(t)) return t.substring(2).toBigInteger(8).toDouble()
    if (!JS_NUMBER.matches(t)) return Double.NaN
    if (t.endsWith("Infinity")) return if (t.startsWith("-")) Double.NEGATIVE_INFINITY else Double.POSITIVE_INFINITY
    return t.toDouble()
}

/** A finite number, or a numeric non-blank string; else null. */
internal fun toNum(value: Any?): Double? {
    if (value is Number) return value.toDouble().takeIf { it.isFinite() }
    if (value is String && value.trim { isJsSpace(it) } != "") {
        val n = jsNumberOfString(value)
        return n.takeIf { it.isFinite() }
    }
    return null
}

private val EMAIL = Regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$")
private val CURRENCY_CODE = Regex("^[A-Za-z]{3}$")
private val SCHEME = Regex("^([a-zA-Z][a-zA-Z0-9+.-]*):")

/** Evaluate one parsed template value against [ctx]. */
fun evaluateTemplateValue(value: Any?, ctx: FunctionContext): Any? {
    if (value !is Map<*, *>) return value
    if (value.containsKey("path")) return ctx.read(value["path"].toString())
    @Suppress("UNCHECKED_CAST")
    return ctx.call(value["call"].toString(), (value["args"] as? Map<String, Any?>) ?: emptyMap())
}

private fun javaLocale(locale: String): Locale {
    val l = try {
        Locale.forLanguageTag(locale)
    } catch (_: Exception) {
        null
    }
    return if (l == null || l.language.isEmpty()) Locale.US else l
}

/** `Intl.NumberFormat` options this port honours. */
private class NumberOptions(val grouping: Boolean, val decimals: Int?)

private fun fractionOptions(args: Map<String, Any?>): NumberOptions {
    val decimals = toNum(args["decimals"])
    val d = if (decimals != null) maxOf(0, minOf(20, decimals.toLong().toInt())) else null
    return NumberOptions(args["grouping"] != false, d)
}

/** The shortest decimal form of [n] (what `Intl` rounds from). */
private fun decimalOf(n: Double): BigDecimal = BigDecimal(Json.formatNumber(n).let { if (it.contains('e')) n.toString() else it })

private fun formatDecimal(n: Double, locale: String, o: NumberOptions): String {
    val f = NumberFormat.getNumberInstance(javaLocale(locale))
    f.isGroupingUsed = o.grouping
    f.roundingMode = RoundingMode.HALF_UP
    if (o.decimals != null) {
        f.minimumFractionDigits = o.decimals
        f.maximumFractionDigits = o.decimals
    } else {
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 3
    }
    return f.format(decimalOf(n))
}

private fun formatCurrencyValue(n: Double, code: String, locale: String, o: NumberOptions): String {
    val loc = javaLocale(locale)
    val f = NumberFormat.getCurrencyInstance(loc)
    val currency = try {
        Currency.getInstance(code)
    } catch (_: Exception) {
        null
    }
    if (currency != null) {
        f.currency = currency
        if (f is DecimalFormat) {
            // The locale's own symbol for the currency (`€`, `US$`…), as Intl shows it.
            val symbols = f.decimalFormatSymbols
            symbols.currency = currency
            symbols.currencySymbol = currency.getSymbol(loc)
            f.decimalFormatSymbols = symbols
        }
    } else if (f is DecimalFormat) {
        val symbols = DecimalFormatSymbols.getInstance(loc)
        symbols.currencySymbol = code
        f.decimalFormatSymbols = symbols
    }
    val digits = o.decimals ?: (currency?.defaultFractionDigits?.takeIf { it >= 0 } ?: 2)
    f.minimumFractionDigits = digits
    f.maximumFractionDigits = digits
    f.isGroupingUsed = o.grouping
    f.roundingMode = RoundingMode.HALF_UP
    return f.format(decimalOf(n))
}

/**
 * The CLDR plural category of [n] for [locale] — the common rules (`one` /
 * `other`, French-style `one` for 0 and 1, no categories for East Asian
 * languages); `Intl.PluralRules` knows more locales.
 */
fun pluralCategory(locale: String, n: Double): String {
    val lang = javaLocale(locale).language
    val integer = n == Math.rint(n)
    return when (lang) {
        "ja", "zh", "ko", "th", "vi", "id", "ms", "my", "lo", "km" -> "other"
        "fr", "hy", "kab" -> if (n >= 0 && n < 2) "one" else "other"
        "pt" -> if (javaLocale(locale).country == "PT") (if (n == 1.0) "one" else "other") else if (n >= 0 && n < 2) "one" else "other"
        else -> if (n == 1.0 && integer) "one" else "other"
    }
}

val BASIC_FUNCTIONS: Map<String, A2UIFunction> = linkedMapOf(
    "required" to { a, _ ->
        val value = a["value"]
        !(value == null || value == "" || (value is List<*> && value.isEmpty()))
    },

    "regex" to { a, _ ->
        val pattern = a["pattern"] as? String ?: throw expressionError("regex: \"pattern\" must be a string")
        val re = try {
            Regex(pattern)
        } catch (_: Exception) {
            throw expressionError("regex: invalid pattern \"$pattern\"")
        }
        re.containsMatchIn(stringifyValue(a["value"]))
    },

    "length" to { a, _ ->
        val n = stringifyValue(a["value"]).length.toDouble()
        val min = toNum(a["min"])
        val max = toNum(a["max"])
        !(min != null && n < min) && !(max != null && n > max)
    },

    "numeric" to { a, _ ->
        val n = toNum(a["value"])
        if (n == null) false
        else {
            val min = toNum(a["min"])
            val max = toNum(a["max"])
            !(min != null && n < min) && !(max != null && n > max)
        }
    },

    "email" to { a, _ -> (a["value"] as? String)?.let { EMAIL.matches(it) } ?: false },

    "formatString" to { a, ctx ->
        val value = a["value"]
        if (value == null) ""
        else parseTemplate(stringifyValue(value)).joinToString("") { stringifyValue(evaluateTemplateValue(it, ctx)) }
    },

    "formatNumber" to { a, ctx ->
        val n = toNum(a["value"])
        if (n == null) "" else formatDecimal(n, ctx.locale, fractionOptions(a))
    },

    "formatCurrency" to { a, ctx ->
        val n = toNum(a["value"])
        if (n == null) ""
        else {
            val c = a["currency"]
            val currency = if (c is String && CURRENCY_CODE.matches(c)) c.uppercase() else "USD"
            formatCurrencyValue(n, currency, ctx.locale, fractionOptions(a))
        }
    },

    "formatDate" to { a, ctx ->
        val date = parseDate(a["value"])
        if (date == null) ""
        else {
            val format = a["format"]
            formatDatePattern(date, if (format is String && format.isNotEmpty()) format else "yyyy-MM-dd", ctx.locale)
        }
    },

    "pluralize" to { a, ctx ->
        val n = toNum(a["value"])
        if (n == null) stringifyValue(a["other"])
        else {
            var category = pluralCategory(ctx.locale, n)
            // English (and most locales) report 0 as "other"; an explicit zero form wins.
            if (n == 0.0 && a["zero"] != null) category = "zero"
            val chosen = if (a[category] != null) a[category] else a["other"]
            stringifyValue(chosen)
        }
    },

    "openUrl" to { a, ctx ->
        val resolved = validateOpenUrl(a["url"], ctx.baseUrl)
        ctx.openUrl?.invoke(resolved)
        null
    },

    "and" to { a, _ ->
        val values = a["values"] as? List<*> ?: throw expressionError("and: \"values\" must be a list")
        values.all { toBool(it) }
    },

    "or" to { a, _ ->
        val values = a["values"] as? List<*> ?: throw expressionError("or: \"values\" must be a list")
        values.any { toBool(it) }
    },

    "not" to { a, _ -> !toBool(a["value"]) },
)

/**
 * `openUrl`'s mandatory checks: resolve relative URLs against [base], then
 * allow only `http:` and `https:` (no `javascript:`, `data:`, …).
 */
fun validateOpenUrl(url: Any?, base: String?): String {
    if (url !is String || url.trim().isEmpty()) throw expressionError("openUrl: \"url\" must be a non-empty string")
    val raw = url.trim()
    var resolved = raw
    if (SCHEME.find(raw) == null) {
        if (base.isNullOrEmpty()) throw expressionError("openUrl: cannot resolve relative URL \"$raw\"")
        resolved = try {
            var b = URI(base)
            if (b.rawPath.isNullOrEmpty()) b = URI("$base/")
            b.resolve(raw).toString()
        } catch (_: Exception) {
            throw expressionError("openUrl: invalid URL \"$raw\"")
        }
    }
    val protocol = (SCHEME.find(resolved)?.groupValues?.get(1) ?: "").lowercase()
    if (protocol != "http" && protocol != "https") throw expressionError("openUrl: the \"$protocol:\" scheme is not allowed (http and https only)")
    return resolved
}

// ----------------------------------------------------------------------------
// Dates
// ----------------------------------------------------------------------------

private val DATE_ONLY = Regex("^(\\d{4})-(\\d{2})-(\\d{2})$")
private val TIME_ONLY = Regex("^(\\d{1,2}):(\\d{2})(?::(\\d{2})(?:\\.\\d+)?)?$")

/**
 * Parse an A2UI date value: an ISO 8601 date-time (`2026-02-02T15:17:00Z`),
 * a date (`2026-02-02`, local midnight), a time (`14:30`, today), or epoch
 * milliseconds.
 */
fun parseDate(value: Any?): ZonedDateTime? {
    val zone = ZoneId.systemDefault()
    when (value) {
        is ZonedDateTime -> return value
        is Instant -> return value.atZone(zone)
        is Number -> {
            val d = value.toDouble()
            return if (d.isFinite()) Instant.ofEpochMilli(d.toLong()).atZone(zone) else null
        }
        !is String -> return null
        else -> {}
    }
    val s = (value as String).trim()
    if (s.isEmpty()) return null
    DATE_ONLY.matchEntire(s)?.let { m ->
        val (y, mo, d) = m.destructured
        return LocalDate.of(y.toInt(), 1, 1).plusMonths(mo.toLong() - 1).plusDays(d.toLong() - 1).atStartOfDay(zone)
    }
    TIME_ONLY.matchEntire(s)?.let { m ->
        val h = m.groupValues[1].toLong()
        val min = m.groupValues[2].toLong()
        val sec = m.groupValues[3].ifEmpty { "0" }.toLong()
        return LocalDate.now(zone).atStartOfDay(zone).plusHours(h).plusMinutes(min).plusSeconds(sec)
    }
    // A date-time without an offset is local time (as `Date` reads it); with one, absolute.
    try {
        return OffsetDateTime.parse(s, DateTimeFormatter.ISO_OFFSET_DATE_TIME).atZoneSameInstant(zone)
    } catch (_: Exception) {
    }
    try {
        return LocalDateTime.parse(s, DateTimeFormatter.ISO_LOCAL_DATE_TIME).atZone(zone)
    } catch (_: Exception) {
    }
    try {
        return ZonedDateTime.parse(s, DateTimeFormatter.RFC_1123_DATE_TIME).withZoneSameInstant(zone)
    } catch (_: Exception) {
    }
    return null
}

private fun pad(n: Long, width: Int): String {
    val s = n.toString()
    return if (s.length >= width) s else "0".repeat(width - s.length) + s
}

/** Format [date] with a Unicode TR35 pattern (`yyyy-MM-dd`, `EEEE, MMM d 'at' h:mm a`, …). */
fun formatDatePattern(date: ZonedDateTime, pattern: String, locale: String = "en-US"): String {
    val out = StringBuilder()
    var i = 0
    while (i < pattern.length) {
        val ch = pattern[i]
        if (ch == '\'') {
            // Quoted literal; '' is a single quote.
            if (i + 1 < pattern.length && pattern[i + 1] == '\'') {
                out.append('\'')
                i += 2
                continue
            }
            var j = i + 1
            while (j < pattern.length) {
                if (pattern[j] == '\'' && j + 1 < pattern.length && pattern[j + 1] == '\'') {
                    out.append('\'')
                    j += 2
                    continue
                }
                if (pattern[j] == '\'') break
                out.append(pattern[j++])
            }
            i = j + 1
            continue
        }
        if (!(ch in 'A'..'Z' || ch in 'a'..'z')) {
            out.append(ch)
            i++
            continue
        }
        var n = 1
        while (i + n < pattern.length && pattern[i + n] == ch) n++
        i += n
        out.append(field(date, ch, n, locale))
    }
    return out.toString()
}

private fun field(d: ZonedDateTime, ch: Char, n: Int, locale: String): String {
    val loc = javaLocale(locale)
    return when (ch) {
        'y', 'Y', 'u' -> if (n == 2) pad((d.year % 100).toLong(), 2) else pad(d.year.toLong(), n)
        'M', 'L' -> when {
            n >= 4 -> d.month.getDisplayName(TextStyle.FULL, loc)
            n == 3 -> d.month.getDisplayName(TextStyle.SHORT, loc)
            else -> pad(d.monthValue.toLong(), n)
        }
        'd' -> pad(d.dayOfMonth.toLong(), n)
        'D' -> pad(d.dayOfYear.toLong(), n)
        'E', 'e', 'c' -> when {
            n == 5 -> d.dayOfWeek.getDisplayName(TextStyle.NARROW, loc)
            n >= 4 -> d.dayOfWeek.getDisplayName(TextStyle.FULL, loc)
            else -> d.dayOfWeek.getDisplayName(TextStyle.SHORT, loc)
        }
        'a' -> if (d.hour < 12) "AM" else "PM"
        'h' -> pad((if (d.hour % 12 == 0) 12 else d.hour % 12).toLong(), n)
        'K' -> pad((d.hour % 12).toLong(), n)
        'H' -> pad(d.hour.toLong(), n)
        'k' -> pad((if (d.hour == 0) 24 else d.hour).toLong(), n)
        'm' -> pad(d.minute.toLong(), n)
        's' -> pad(d.second.toLong(), n)
        'S' -> pad((d.nano / 1_000_000).toLong(), 3).take(n)
        'z', 'Z', 'x', 'X' -> {
            val offset = d.offset.totalSeconds / 60
            if (offset == 0 && (ch == 'X' || ch == 'x')) "Z"
            else {
                val sign = if (offset >= 0) "+" else "-"
                val abs = Math.abs(offset)
                "$sign${pad((abs / 60).toLong(), 2)}:${pad((abs % 60).toLong(), 2)}"
            }
        }
        else -> ch.toString().repeat(n)
    }
}

/** `Date.prototype.toISOString` for epoch milliseconds (`2026-10-09T16:05:31.123Z`). */
fun isoTimestamp(epochMs: Long = System.currentTimeMillis()): String =
    DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").withZone(ZoneId.of("UTC")).format(Instant.ofEpochMilli(epochMs))
