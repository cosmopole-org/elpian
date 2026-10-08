package dev.elpian.core.godot

import dev.elpian.core.util.Json
import dev.elpian.core.util.jsString

/**
 * Godot values on the wire — a port of `protocol.dart` and `godot_values.dart`
 * (godot/values.ts).
 *
 * Ops are JSON objects (`{"new": "MeshInstance3D", "def": 7}`,
 * `{"ref": 7, "set": "position", "value": {"vec3": [0, 1, 0]}}` …); typed
 * Godot values are single-key tagged objects. Handles are allocated on this
 * side, so a whole scene can be built and addressed before the engine has
 * rendered a frame.
 *
 * Numbers put on the wire are [Double]s (the JSON number model of the core);
 * handles and callback ids are [Long]s in the Kotlin API.
 */
typealias Wire = Any?
typealias Op = MutableMap<String, Any?>

object OpKey {
    const val create = "new"
    const val def = "def"
    const val self = "self"
    const val tree = "tree"
    const val singleton = "singleton"
    const val load = "load"
    const val free = "free"
    const val ref = "ref"
    const val get = "get"
    const val set = "set"
    const val getIndexed = "geti"
    const val setIndexed = "seti"
    const val value = "value"
    const val props = "props"
    const val method = "method"
    const val args = "args"
    const val static_ = "static"
    const val connect = "connect"
    const val disconnect = "disconnect"
    const val cb = "cb"
    const val flags = "flags"
    const val constant = "const"
    const val expr = "expr"
    const val names = "names"
    const val values = "values"
    const val classes = "classes"
    const val classInfo = "classinfo"
    const val audit = "audit"
    const val mount = "mount"
    const val surface = "surface"
}

data class GodotRef(val id: Long) {
    fun toWire(): MutableMap<String, Any?> = linkedMapOf("ref" to id.toDouble())

    companion object {
        fun isRef(v: Any?): Boolean {
            if (v !is Map<*, *> || v.size != 1) return false
            val r = v["ref"]
            return r is Number && isInteger(r.toDouble())
        }
    }
}

data class GodotCallbackRef(val id: Long) {
    fun toWire(): MutableMap<String, Any?> = linkedMapOf("cb" to id.toDouble())
}

class HandleAllocator(start: Long = selfHandle + 1) {
    private var next: Long = start

    fun allocate(): Long = next++

    val issued: Long get() = next - selfHandle - 1

    companion object {
        const val selfHandle: Long = 1L
    }
}

fun wireError(message: String): MutableMap<String, Any?> = linkedMapOf("__dart_error__" to message)

fun isWireError(v: Any?): Boolean = v is Map<*, *> && v.containsKey("__dart_error__")

fun wireErrorMessage(v: Any?): String? = if (isWireError(v)) jsString((v as Map<*, *>)["__dart_error__"]) else null

class GodotOpException(message: String, val op: Map<String, Any?>? = null) :
    RuntimeException(if (op != null) "GodotOpException: $message (op: ${Json.stringify(op)})" else "GodotOpException: $message")

fun encodeOps(ops: List<Map<String, Any?>>): String = Json.stringify(ops)

fun decodeReplies(json: String?): List<Wire> {
    if (json.isNullOrEmpty()) return emptyList()
    val decoded = Json.parse(json)
    return if (decoded is List<*>) decoded.toList() else listOf(decoded)
}

// ---------------------------------------------------------------------------
// Typed values
// ---------------------------------------------------------------------------

abstract class GodotValue {
    abstract fun toWire(): MutableMap<String, Any?>
}

private fun tagged(tag: String, data: Any?): MutableMap<String, Any?> = linkedMapOf(tag to data)

data class Vector2(val x: Double, val y: Double) : GodotValue() {
    override fun toWire() = tagged("vec2", listOf(x, y))
}

data class Vector2i(val x: Double, val y: Double) : GodotValue() {
    override fun toWire() = tagged("vec2i", listOf(x, y))
}

data class Vector3(val x: Double, val y: Double, val z: Double) : GodotValue() {
    fun plus(o: Vector3): Vector3 = Vector3(x + o.x, y + o.y, z + o.z)
    fun minus(o: Vector3): Vector3 = Vector3(x - o.x, y - o.y, z - o.z)
    fun times(s: Double): Vector3 = Vector3(x * s, y * s, z * s)
    override fun toWire() = tagged("vec3", listOf(x, y, z))

    companion object {
        fun all(v: Double): Vector3 = Vector3(v, v, v)
    }
}

data class Vector3i(val x: Double, val y: Double, val z: Double) : GodotValue() {
    override fun toWire() = tagged("vec3i", listOf(x, y, z))
}

data class Vector4(val x: Double, val y: Double, val z: Double, val w: Double) : GodotValue() {
    override fun toWire() = tagged("vec4", listOf(x, y, z, w))
}

data class Vector4i(val x: Double, val y: Double, val z: Double, val w: Double) : GodotValue() {
    override fun toWire() = tagged("vec4i", listOf(x, y, z, w))
}

data class GodotColor(val r: Double, val g: Double, val b: Double, val a: Double = 1.0) : GodotValue() {
    override fun toWire() = tagged("color", listOf(r, g, b, a))

    companion object {
        fun hex(rgb: Int, a: Double = 1.0): GodotColor =
            GodotColor(((rgb shr 16) and 0xff) / 255.0, ((rgb shr 8) and 0xff) / 255.0, (rgb and 0xff) / 255.0, a)
    }
}

data class Rect2(val x: Double, val y: Double, val w: Double, val h: Double) : GodotValue() {
    override fun toWire() = tagged("rect2", listOf(x, y, w, h))
}

data class Rect2i(val x: Double, val y: Double, val w: Double, val h: Double) : GodotValue() {
    override fun toWire() = tagged("rect2i", listOf(x, y, w, h))
}

data class Plane(val nx: Double, val ny: Double, val nz: Double, val d: Double) : GodotValue() {
    override fun toWire() = tagged("plane", listOf(nx, ny, nz, d))
}

data class Quaternion(val x: Double, val y: Double, val z: Double, val w: Double) : GodotValue() {
    override fun toWire() = tagged("quat", listOf(x, y, z, w))
}

data class AABB(val px: Double, val py: Double, val pz: Double, val sx: Double, val sy: Double, val sz: Double) : GodotValue() {
    override fun toWire() = tagged("aabb", listOf(px, py, pz, sx, sy, sz))
}

data class Basis(val rows: List<List<Double>>) : GodotValue() {
    override fun toWire() = tagged("basis", rows)
}

data class Transform2D(val m: List<Double>) : GodotValue() {
    override fun toWire() = tagged("xform2d", m)
}

data class Transform3D(val m: List<Double>) : GodotValue() {
    override fun toWire() = tagged("xform3d", m)
}

data class Projection(val m: List<Double>) : GodotValue() {
    override fun toWire() = tagged("proj", m)
}

data class StringName(val value: String) : GodotValue() {
    override fun toWire() = tagged("sname", value)
}

data class NodePath(val value: String) : GodotValue() {
    override fun toWire() = tagged("npath", value)
}

data class GRid(val id: Double) : GodotValue() {
    override fun toWire() = tagged("rid", id)
}

data class GSignal(val sourceHandle: Long, val name: String) : GodotValue() {
    override fun toWire() = tagged("sig", listOf(GodotRef(sourceHandle).toWire(), name))
}

data class GCallable(val callbackId: Long) : GodotValue() {
    override fun toWire() = tagged("callable", callbackId.toDouble())
}

data class GInt(val value: Double) : GodotValue() {
    override fun toWire() = tagged("int", trunc(value))
}

data class GFloat(val value: Double) : GodotValue() {
    override fun toWire() = tagged("float", value)
}

data class GDict(val entries: List<Pair<Any?, Any?>>) : GodotValue() {
    override fun toWire() = tagged("dictv", entries.map { (k, v) -> listOf(marshal(k), marshal(v)) })
}

data class Packed(val tag: String, val data: Any?) : GodotValue() {
    override fun toWire() = tagged(tag, data)

    companion object {
        fun bytesBase64(b64: String) = Packed("u8", b64)
        fun i32(v: List<Double>) = Packed("i32", v)
        fun i64(v: List<Double>) = Packed("i64", v)
        fun f32(v: List<Double>) = Packed("f32", v)
        fun f64(v: List<Double>) = Packed("f64", v)
        fun strings(v: List<String>) = Packed("strs", v)
        fun vector2s(flat: List<Double>) = Packed("pv2", flat)
        fun vector3s(flat: List<Double>) = Packed("pv3", flat)
        fun vector4s(flat: List<Double>) = Packed("pv4", flat)
        fun colors(flat: List<Double>) = Packed("pcol", flat)
    }
}

/** Anything that exposes a [GodotRef] (GodotObject). */
interface GodotHandle {
    val ref: GodotRef
}

fun marshal(v: Any?): Any? {
    if (v == null || v is Boolean || v is String) return v
    if (v is Number) return v.toDouble()
    if (v is GodotValue) return v.toWire()
    if (v is GodotRef) return v.toWire()
    if (v is GodotCallbackRef) return v.toWire()
    if (v is GodotHandle) return v.ref.toWire()
    if (v is List<*>) return v.map { marshal(it) }
    if (v is Array<*>) return v.map { marshal(it) }
    if (v is Map<*, *>) {
        val out = LinkedHashMap<String, Any?>()
        for ((k, value) in v) out[k.toString()] = marshal(value)
        return linkedMapOf<String, Any?>("dict" to out)
    }
    return v
}

fun marshalArgs(args: List<Any?>?): List<Any?> = args?.map { marshal(it) } ?: emptyList()

fun unmarshal(v: Any?): Any? {
    if (v is List<*>) return v.map { unmarshal(it) }
    if (v !is Map<*, *>) return v
    if (v.containsKey("__dart_error__")) return v
    if (v.size != 1) return v
    val key = v.keys.first().toString()
    val data = v.values.first()
    fun nums(): List<Double> = (data as List<*>).map { jsNumber(it) }
    fun ints(): List<Double> = (data as List<*>).map { trunc(jsNumber(it)) }
    fun List<Double>.at(i: Int): Double = getOrElse(i) { Double.NaN }
    return when (key) {
        "ref" -> GodotRef(jsNumber(data).toLong())
        "vec2" -> nums().let { Vector2(it.at(0), it.at(1)) }
        "vec2i" -> ints().let { Vector2i(it.at(0), it.at(1)) }
        "vec3" -> nums().let { Vector3(it.at(0), it.at(1), it.at(2)) }
        "vec3i" -> ints().let { Vector3i(it.at(0), it.at(1), it.at(2)) }
        "vec4" -> nums().let { Vector4(it.at(0), it.at(1), it.at(2), it.at(3)) }
        "vec4i" -> ints().let { Vector4i(it.at(0), it.at(1), it.at(2), it.at(3)) }
        "color" -> nums().let { GodotColor(it.at(0), it.at(1), it.at(2), it.at(3)) }
        "rect2" -> nums().let { Rect2(it.at(0), it.at(1), it.at(2), it.at(3)) }
        "rect2i" -> ints().let { Rect2i(it.at(0), it.at(1), it.at(2), it.at(3)) }
        "plane" -> nums().let { Plane(it.at(0), it.at(1), it.at(2), it.at(3)) }
        "quat" -> nums().let { Quaternion(it.at(0), it.at(1), it.at(2), it.at(3)) }
        "aabb" -> nums().let { AABB(it.at(0), it.at(1), it.at(2), it.at(3), it.at(4), it.at(5)) }
        "basis" -> Basis((data as List<*>).map { row -> (row as List<*>).map { jsNumber(it) } })
        "xform2d" -> Transform2D(nums())
        "xform3d" -> Transform3D(nums())
        "proj" -> Projection(nums())
        "sname" -> StringName(jsString(data))
        "npath" -> NodePath(jsString(data))
        "rid" -> GRid(jsNumber(data))
        "int" -> trunc(jsNumber(data))
        "float" -> jsNumber(data)
        "callable" -> GCallable(jsNumber(data).toLong())
        "dict" -> {
            val out = LinkedHashMap<String, Any?>()
            (data as? Map<*, *>)?.forEach { (k, value) -> out[k.toString()] = unmarshal(value) }
            out
        }
        "dictv" -> GDict((data as List<*>).map { pair -> (pair as List<*>).let { Pair(unmarshal(it.getOrNull(0)), unmarshal(it.getOrNull(1))) } })
        "u8", "i32", "i64", "f32", "f64", "strs", "pv2", "pv3", "pv4", "pcol" -> Packed(key, data)
        else -> v
    }
}

// ---------------------------------------------------------------------------
// JavaScript coercions used by the wire codec
// ---------------------------------------------------------------------------

/** `Number.isInteger`. */
internal fun isInteger(d: Double): Boolean = d.isFinite() && d == Math.floor(d)

/** `Math.trunc`. */
internal fun trunc(d: Double): Double = if (d.isNaN() || d.isInfinite()) d else if (d < 0) Math.ceil(d) else Math.floor(d)

/** JavaScript `Number(v)` for JSON values. */
internal fun jsNumber(v: Any?): Double = when (v) {
    null -> 0.0
    is Number -> v.toDouble()
    is Boolean -> if (v) 1.0 else 0.0
    is String -> {
        val s = v.trim()
        when {
            s.isEmpty() -> 0.0
            s == "Infinity" || s == "+Infinity" -> Double.POSITIVE_INFINITY
            s == "-Infinity" -> Double.NEGATIVE_INFINITY
            s.startsWith("0x") || s.startsWith("0X") -> s.substring(2).toLongOrNull(16)?.toDouble() ?: Double.NaN
            s.startsWith("0o") || s.startsWith("0O") -> s.substring(2).toLongOrNull(8)?.toDouble() ?: Double.NaN
            s.startsWith("0b") || s.startsWith("0B") -> s.substring(2).toLongOrNull(2)?.toDouble() ?: Double.NaN
            JS_DECIMAL.matches(s) -> s.toDouble()
            else -> Double.NaN
        }
    }
    is List<*> -> if (v.isEmpty()) 0.0 else if (v.size == 1) jsNumber(if (v[0] == null) "" else jsString(v[0])) else Double.NaN
    else -> Double.NaN
}

private val JS_DECIMAL = Regex("^[+-]?(\\d+\\.?\\d*|\\.\\d+)([eE][+-]?\\d+)?$")
