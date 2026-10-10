package dev.elpian.core.a2ui

import dev.elpian.core.css.EdgeInsets
import dev.elpian.core.platform.FetchRequest
import dev.elpian.core.platform.FetchResponse
import dev.elpian.core.platform.Platform
import dev.elpian.core.platform.Platforms
import dev.elpian.core.platform.StreamHandlers
import dev.elpian.core.platform.Viewport
import dev.elpian.core.render.INF
import dev.elpian.core.render.TextMetrics
import dev.elpian.core.render.TextSpec
import dev.elpian.core.render.ViewOp
import dev.elpian.core.session.ElpianSurface
import dev.elpian.core.util.Json
import dev.elpian.core.util.JsonMap
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import java.io.File
import java.util.TimeZone
import kotlin.math.ceil
import kotlin.math.min
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * Shared harness for the A2UI tests (native/web/test/a2ui/harness.mjs): a
 * headless Platform (fixed-width text metrics, recorded view ops, manual
 * timers, scripted fetchStream delivered on [drain]) and the vendored A2UI
 * files.
 */
object A2UIFiles {
    val a2uiDir: File by lazy {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null) {
            val candidate = File(dir, "a2ui/conformance/json")
            if (candidate.isDirectory) return@lazy File(dir, "a2ui")
            dir = dir.parentFile
        }
        error("a2ui/ not found above ${System.getProperty("user.dir")}")
    }

    fun readJson(vararg parts: String): Any? = Json.parse(parts.fold(a2uiDir) { f, p -> File(f, p) }.readText())

    @Suppress("UNCHECKED_CAST")
    fun conformance(name: String): List<JsonMap> = readJson("conformance", "json", "$name.json") as List<JsonMap>

    @Suppress("UNCHECKED_CAST")
    fun examples(): List<Pair<String, JsonMap>> {
        val dir = File(a2uiDir, "spec/catalogs/basic/examples")
        return dir.listFiles()!!.filter { it.name.endsWith(".json") }.sortedBy { it.name }.map { it.name to (Json.parse(it.readText()) as JsonMap) }
    }
}

/** A scripted agent response: chunks, then done (or the error). */
class StreamScript(val chunks: List<String>, val error: String? = null)

class A2UITestPlatform : Platform {
    override val name = "test"
    override val dispatcher: CoroutineDispatcher = Dispatchers.Unconfined
    val ops = ArrayList<ViewOp>()
    val requests = ArrayList<FetchRequest>()
    val logs = ArrayList<String>()
    var opened: String? = null
    var streamScript: ((FetchRequest) -> StreamScript)? = null
    private val pending = ArrayDeque<() -> Unit>()
    private val timers = LinkedHashMap<Int, () -> Unit>()
    private var nextTimer = 1

    override fun now() = System.currentTimeMillis().toDouble()

    override fun setTimeout(ms: Double, callback: () -> Unit): Int {
        val id = nextTimer++
        timers[id] = callback
        return id
    }

    override fun clearTimeout(handle: Int) {
        timers.remove(handle)
    }

    override fun requestFrame(callback: (Double) -> Unit) {}

    override fun commit(surface: String, ops: List<ViewOp>) {
        this.ops.addAll(ops)
    }

    override fun measureText(spec: TextSpec, maxWidth: Double): TextMetrics {
        val size = spec.spans.firstOrNull()?.style?.fontSize ?: 14.0
        val full = spec.spans.sumOf { it.text.length } * size * 0.5
        val wraps = maxWidth != INF && maxWidth > 0
        val lines = if (wraps && full > maxWidth) ceil(full / maxWidth).toInt() else 1
        return TextMetrics(if (wraps) min(full, maxWidth) else full, lines * size * 1.2, size, lines, false)
    }

    override fun viewport(surface: String) = Viewport(400.0, 800.0, 1.0, EdgeInsets.ZERO, "en-US", "android", false, false, 1.0)

    override fun log(level: String, message: String) {
        logs.add("$level: $message")
    }

    override fun openUrl(url: String) {
        opened = url
    }

    override suspend fun fetch(request: FetchRequest) = FetchResponse(404, emptyMap(), "")

    override fun fetchStream(request: FetchRequest, handlers: StreamHandlers): () -> Unit {
        requests.add(request)
        val script = streamScript?.invoke(request) ?: StreamScript(emptyList())
        var cancelled = false
        for (c in script.chunks) pending.addLast { if (!cancelled) handlers.onChunk(c) }
        pending.addLast {
            if (!cancelled) {
                if (script.error != null) handlers.onError(script.error) else handlers.onDone()
            }
        }
        return { cancelled = true }
    }

    override suspend fun loadAsset(path: String) = ByteArray(0)

    /** Deliver pending stream chunks and due timers until idle. */
    fun drain() {
        repeat(1000) {
            if (pending.isEmpty() && timers.isEmpty()) return
            while (pending.isNotEmpty()) pending.removeFirst()()
            val due = timers.values.toList()
            timers.clear()
            for (t in due) t()
        }
    }

    companion object {
        /** Install a fresh platform (UTC, as the web harness runs). */
        fun install(): A2UITestPlatform {
            TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
            return A2UITestPlatform().also { Platforms.install(it) }
        }
    }
}

private var surfaces = 0

/** Render [node] on a fresh surface: lower, reconcile, lay out and composite one frame. */
fun renderOnSurface(node: JsonMap): Pair<ElpianSurface, List<ViewOp>> {
    val surface = ElpianSurface("a2ui-test-${++surfaces}")
    surface.setContent(node)
    surface.renderNow()
    val ops = surface.owner.flush(0.0)
    return surface to ops
}

/** Walk a node JSON tree. */
@Suppress("UNCHECKED_CAST")
fun walk(node: JsonMap, fn: (JsonMap) -> Unit) {
    fn(node)
    for (c in (node["children"] as? List<*>) ?: emptyList<Any?>()) if (c is Map<*, *>) walk(c as JsonMap, fn)
}

fun findNode(node: JsonMap, pred: (JsonMap) -> Boolean): JsonMap? {
    var hit: JsonMap? = null
    walk(node) { if (hit == null && pred(it)) hit = it }
    return hit
}

@Suppress("UNCHECKED_CAST")
fun JsonMap.nodeProps(): JsonMap = this["props"] as JsonMap

/** Fire an event handler closure of a lowered node. */
@Suppress("UNCHECKED_CAST")
fun JsonMap.fire(event: String, value: Any? = null, hasValue: Boolean = false) {
    val handler = (this["events"] as Map<String, Any?>)[event] as (dev.elpian.core.events.ElpianEvent) -> Unit
    handler(dev.elpian.core.events.makeEvent(event, event, null) { if (hasValue) this.value = value })
}

/** Structural JSON equality with a readable failure. */
fun assertJson(expected: Any?, actual: Any?, where: String = "") {
    if (!jsonEqual(cloneJson(expected), cloneJson(actual))) fail("$where: expected ${Json.stringify(expected)} but was ${Json.stringify(actual)}")
}

fun assertContains(haystack: String, needle: String, where: String = "") {
    assertTrue(haystack.contains(needle), "$where: \"$haystack\" should contain \"$needle\"")
}
