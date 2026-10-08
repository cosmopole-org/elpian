package dev.elpian.core.host

import dev.elpian.core.platform.platform
import dev.elpian.core.util.Json
import dev.elpian.core.util.JsonMap
import dev.elpian.core.util.Typed
import dev.elpian.core.util.asMap
import dev.elpian.core.util.jsString
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.launch

/**
 * `setTimeout` / `setInterval` / `clearTimeout` / `clearInterval` for guests —
 * a port of `VmTimerHostApi` (flutter/lib/src/vm/timer_host_api.dart) via
 * host/timers.ts. Timers run on the platform clock and call back into the
 * guest by function name.
 */
typealias VmTimerInvoke = suspend (funcName: String, inputJson: String?) -> Unit

private const val MAX_DELAY = 2147483648.0 // 2 ** 31

class VmTimerHostApi(
    private val invoke: VmTimerInvoke,
    private val onError: ((message: String) -> Unit)? = null,
) {
    private class IntervalEntry(var handle: Int)

    private var nextId = 1L
    private val timeouts = LinkedHashMap<Long, Int>()
    private val intervals = LinkedHashMap<Long, IntervalEntry>()
    private var disposed = false

    fun handle(apiName: String, payload: String): String = try {
        when (apiName) {
            "setTimeout" -> setTimer(payload, false)
            "setInterval" -> setTimer(payload, true)
            "clearTimeout", "clearInterval" -> clear(payload)
            else -> Typed.OK
        }
    } catch (e: Exception) {
        onError?.invoke("VmTimerHostApi error ($apiName): $e")
        Typed.OK
    }

    /** Live timer count (governance usage). */
    val activeCount: Int get() = timeouts.size + intervals.size

    fun dispose() {
        disposed = true
        val p = platform()
        for (h in timeouts.values) p.clearTimeout(h)
        for (i in intervals.values) p.clearTimeout(i.handle)
        timeouts.clear()
        intervals.clear()
    }

    private fun setTimer(payload: String, repeat: Boolean): String {
        val args = normalized(payload)
        val handler = args["handler"] ?: args["callback"] ?: args["fn"]
        if (handler == null || jsString(handler) == "") return Typed.OK
        val name = jsString(handler)
        val delay = readDelay(args)
        val input = readInputJson(args)
        val id = nextId++
        val p = platform()
        if (repeat) {
            // Periodic: re-arm after each tick (Timer.periodic semantics — ticks
            // never pile up while the guest is busy).
            val entry = IntervalEntry(0)
            lateinit var tick: () -> Unit
            tick = {
                if (!disposed && intervals.containsKey(id)) {
                    entry.handle = p.setTimeout(maxOf(delay, 0.0), tick)
                    safeInvoke(name, input)
                }
            }
            entry.handle = p.setTimeout(maxOf(delay, 0.0), tick)
            intervals[id] = entry
        } else {
            timeouts[id] = p.setTimeout(delay) {
                timeouts.remove(id)
                if (!disposed) safeInvoke(name, input)
            }
        }
        return Typed.response("i64", id.toDouble())
    }

    private fun clear(payload: String): String {
        val id = readId(payload) ?: return Typed.OK
        val p = platform()
        val t = timeouts[id]
        if (t != null) {
            p.clearTimeout(t)
            timeouts.remove(id)
        }
        val i = intervals[id]
        if (i != null) {
            p.clearTimeout(i.handle)
            intervals.remove(id)
        }
        return Typed.OK
    }

    /** Fire-and-forget guest call (`void this.safeInvoke(...)`): starts at once, failures go to [onError]. */
    private fun safeInvoke(handler: String, input: String?) {
        CoroutineScope(platform().dispatcher).launch(start = CoroutineStart.UNDISPATCHED) {
            try {
                invoke(handler, input)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                onError?.invoke("VmTimerHostApi invoke error ($handler): $e")
            }
        }
    }
}

private fun parsePayload(payload: String?): Any? {
    if (payload.isNullOrEmpty()) return null
    val parsed: Any? = try {
        Json.parse(payload)
    } catch (_: Exception) {
        if (payload.length >= 2 && payload.startsWith("\"") && payload.endsWith("\"")) return payload.substring(1, payload.length - 1)
        return payload
    }
    if (parsed is List<*>) return if (parsed.isNotEmpty()) parsed[0] else null
    if (parsed is Map<*, *>) {
        val data = parsed["data"]
        if (data is Map<*, *> && data.containsKey("value")) return data["value"]
    }
    return parsed
}

private fun normalized(payload: String): JsonMap = parsePayload(payload).asMap() ?: LinkedHashMap()

private val INTEGER = Regex("^-?\\d+$")

/** `Math.round`: halves round up (towards +∞). */
private fun jsRound(v: Double): Double = if (v.isNaN() || v.isInfinite()) v else Math.floor(v + 0.5)

/** `parseInt(s, 10)` for strings already known to hold an integer (after trimming). */
private fun parseIntDecimal(s: String): Double = s.trim().toBigInteger().toDouble()

private fun readDelay(args: JsonMap): Double {
    val raw = args["delay"] ?: args["ms"] ?: args["interval"]
    var v = 0.0
    if (raw is Number) v = jsRound(raw.toDouble())
    else if (raw is String && INTEGER.matches(raw.trim())) v = parseIntDecimal(raw)
    return maxOf(0.0, minOf(MAX_DELAY, if (v.isFinite()) v else 0.0))
}

private fun readInputJson(args: JsonMap): String? {
    val inputJson = args["inputJson"]
    if (inputJson is String) return inputJson
    if (args.containsKey("input")) return Json.stringify(args["input"])
    return null
}

private fun readId(payload: String): Long? {
    val p = parsePayload(payload)
    val v = if (p is Map<*, *>) p["id"] ?: p["timerId"] ?: p["value"] else p
    if (v is Number) return jsRound(v.toDouble()).let { if (it.isFinite()) it.toLong() else null }
    if (v is String && INTEGER.matches(v.trim())) return parseIntDecimal(v).toLong()
    return null
}
