package dev.elpian.core.util

/**
 * The typed value envelope of the Elpian VM's host boundary:
 * `{"type": "<tag>", "data": {"value": <payload>}}`.
 */
object Typed {
    fun response(type: String, value: Any?): String = Json.stringify(jsonMapOf("type" to type, "data" to jsonMapOf("value" to value)))

    val NULL: String = response("null", null)
    val OK: String = response("i16", 0)
    val ONE: String = response("i16", 1)

    /** `toTypedVmValue`: integers are i64, other numbers f64. */
    fun toTyped(value: Any?): JsonMap = when (value) {
        null -> env("null", null)
        is Boolean -> env("bool", value)
        is Number -> {
            val d = value.toDouble()
            if (d == Math.rint(d) && Math.abs(d) <= 9007199254740991.0) env("i64", d) else env("f64", d)
        }
        is String -> env("string", value)
        is List<*> -> env("array", value.map { toTyped(it) })
        is Map<*, *> -> env("object", LinkedHashMap<String, Any?>().also { m -> for ((k, v) in value) m[k.toString()] = toTyped(v) })
        else -> env("string", value.toString())
    }

    /** Inverse of [toTyped]. */
    fun fromTyped(value: Any?): Any? {
        val m = value as? Map<*, *> ?: return value
        val type = m["type"] as? String ?: return value
        val data = m["data"] as? Map<*, *> ?: return value
        if (!data.containsKey("value")) return value
        val inner = data["value"]
        return when (type) {
            "array" -> (inner as? List<*>)?.map { fromTyped(it) } ?: inner
            "object" -> (inner as? Map<*, *>)?.let { o -> LinkedHashMap<String, Any?>().also { out -> for ((k, v) in o) out[k.toString()] = fromTyped(v) } } ?: inner
            else -> inner
        }
    }

    private fun env(type: String, v: Any?): JsonMap = jsonMapOf("type" to type, "data" to jsonMapOf("value" to v))
}
