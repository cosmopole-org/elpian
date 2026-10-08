package dev.elpian.android.render

import dev.elpian.core.css.Alignment
import dev.elpian.core.css.BoxFit
import dev.elpian.core.render.TextStyleSpec

/**
 * Loose accessors for view props. The core's props maps hold typed values
 * (Color ints, [Alignment], data classes) next to JSON-shaped ones (lists of
 * Double, maps), exactly as the TypeScript props objects do; these helpers
 * read both shapes.
 */
internal object P {
    fun num(v: Any?): Double? = when (v) {
        is Number -> v.toDouble().takeIf { !it.isNaN() }
        is String -> v.trim().toDoubleOrNull()
        is Boolean -> if (v) 1.0 else 0.0
        else -> null
    }

    fun num(m: Map<String, Any?>, k: String): Double? = num(m[k])

    fun int(v: Any?): Int? = num(v)?.toInt()

    /** An ARGB colour int: a Number (JS `>>> 0` semantics) or null. */
    fun color(v: Any?): Int? = when (v) {
        is Int -> v
        is Long -> v.toInt()
        is Number -> v.toDouble().let { if (it.isFinite()) it.toLong().toInt() else null }
        is String -> dev.elpian.core.css.parseColor(v)
        else -> null
    }

    fun str(v: Any?): String? = when (v) {
        null -> null
        is String -> v
        is Enum<*> -> v.name
        else -> v.toString()
    }

    fun bool(v: Any?): Boolean = v == true

    /** A fixed-size numeric tuple (`frame`, `contentSize`, `scrollTo`, `contentPadding`). */
    fun doubles(v: Any?): DoubleArray? = when (v) {
        is DoubleArray -> v
        is FloatArray -> DoubleArray(v.size) { v[it].toDouble() }
        is IntArray -> DoubleArray(v.size) { v[it].toDouble() }
        is List<*> -> DoubleArray(v.size) { num(v[it]) ?: 0.0 }
        is Array<*> -> DoubleArray(v.size) { num(v[it]) ?: 0.0 }
        else -> null
    }

    @Suppress("UNCHECKED_CAST")
    fun map(v: Any?): Map<String, Any?>? = v as? Map<String, Any?>

    fun list(v: Any?): List<Any?>? = when (v) {
        is List<*> -> v
        is Array<*> -> v.toList()
        else -> null
    }

    fun strings(v: Any?): List<String> = list(v)?.mapNotNull { str(it) } ?: emptyList()

    fun alignment(v: Any?): Alignment? = when (v) {
        is Alignment -> v
        is Map<*, *> -> Alignment(num(v["x"]) ?: 0.0, num(v["y"]) ?: 0.0)
        is List<*> -> if (v.size >= 2) Alignment(num(v[0]) ?: 0.0, num(v[1]) ?: 0.0) else null
        else -> null
    }

    fun fit(v: Any?): String? = when (v) {
        is BoxFit -> v.name
        else -> str(v)
    }

    fun textStyle(v: Any?): TextStyleSpec? = v as? TextStyleSpec

    /** A field of a data-class or map value (`backgroundImage.src`, `options[i].label`). */
    fun field(v: Any?, name: String): Any? {
        if (v == null) return null
        if (v is Map<*, *>) return v[name]
        return try {
            val getter = "get" + name.replaceFirstChar { it.uppercase() }
            val m = v.javaClass.methods.firstOrNull { (it.name == getter || it.name == name) && it.parameterCount == 0 }
            m?.invoke(v)
        } catch (_: Throwable) {
            null
        }
    }
}
