package dev.elpian.core.fullstack

import dev.elpian.core.css.EdgeInsets
import dev.elpian.core.platform.FetchRequest
import dev.elpian.core.platform.FetchResponse
import dev.elpian.core.platform.StreamHandlers
import dev.elpian.core.platform.platform
import dev.elpian.core.render.TextStyle
import dev.elpian.core.render.ViewEvent
import dev.elpian.core.render.W
import dev.elpian.core.render.w
import dev.elpian.core.session.ElpianSurface
import dev.elpian.core.session.StreamSession
import dev.elpian.core.session.StreamSessionOptions
import dev.elpian.core.session.SurfaceOptions
import dev.elpian.core.session.encodeURIComponent
import dev.elpian.core.session.loadingIndicator
import dev.elpian.core.util.Json
import dev.elpian.core.util.JsonMap
import dev.elpian.core.util.asMap
import dev.elpian.core.util.isMap
import dev.elpian.core.util.jsString
import dev.elpian.core.util.stableKey
import dev.elpian.core.vm.HostCallHandler
import dev.elpian.core.vm.HostReply
import dev.elpian.core.widgets.WidgetBuilder
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Full-stack mini apps — ports of flutter/lib/src/fullstack/{server_client,
 * server_component}.dart (fullstack/server.ts): a mini app calling its own
 * server functions (`server.call`, `server.render`), brokered client
 * networking (`net.fetch` through the host's proxy under an
 * `ElpianNetPolicy`), streamed components, and server-rendered components
 * with islands.
 *
 * Islands are either lowering functions (props + server-rendered children →
 * widget) or host-registered native components (Android View / UIView / DOM
 * element / React Native component) rendered through the `native` view kind.
 */
class ElpianNetPolicy private constructor(
    /** `closed`, `open` or `brokered`. */
    val mode: String,
    val allowlist: List<String>,
) {
    companion object {
        val closed = ElpianNetPolicy("closed", emptyList())
        val open = ElpianNetPolicy("open", emptyList())

        fun brokered(allowlist: List<String>): ElpianNetPolicy = ElpianNetPolicy("brokered", allowlist.toList())

        fun fromManifest(value: Any?): ElpianNetPolicy {
            if (value == "open") return open
            if (isMap(value)) {
                val allow = value.asMap()!!["allow"]
                return brokered(if (allow is List<*>) allow.filterIsInstance<String>() else emptyList())
            }
            return closed
        }
    }

    fun allows(url: String): Boolean {
        if (mode == "closed") return false
        if (mode == "open") return true
        val host = hostOf(url) ?: return false
        if (host.isEmpty()) return false
        return allowlist.any { matches(it.lowercase(), host.lowercase()) }
    }
}

private fun matches(entry: String, host: String): Boolean {
    if (entry.startsWith("*.")) {
        val suffix = entry.substring(2)
        return host != suffix && host.length > suffix.length && host.endsWith(suffix) && host[host.length - suffix.length - 1] == '.'
    }
    return host == entry
}

private val HOST_OF = Regex("^[a-zA-Z][\\w+.-]*://(?:[^@/?#]*@)?(\\[[^\\]]+\\]|[^:/?#]+)")

private fun hostOf(url: String): String? = HOST_OF.find(url)?.groupValues?.get(1)

data class ServerCallResult(val result: Any? = null, val error: String? = null) {
    fun toJson(): JsonMap = if (error != null) linkedMapOf("error" to error) else linkedMapOf("result" to result)
}

data class ServerRenderResult(val payload: JsonMap? = null, val error: String? = null)

/** Receives a streamed component's frames. */
interface ServerStreamSink {
    fun onFrame(frame: Any?)
    fun onError(message: String)
    fun onDone()
}

class ElpianServerClient(
    val baseUrl: String,
    val appId: String,
    val netPolicy: ElpianNetPolicy = ElpianNetPolicy.closed,
    val authorization: String? = null,
    val timeoutMs: Double = 15000.0,
) {
    private var closed = false
    private val cancels = LinkedHashSet<() -> Unit>()

    /** Where asynchronous host calls run; cancelled on [close]. */
    val scope: CoroutineScope = CoroutineScope(SupervisorJob() + platform().dispatcher)

    /** Host handlers for a mini app runtime: `server.call`, `server.render`, `net.fetch`. */
    val hostHandlers: Map<String, HostCallHandler>
        get() = linkedMapOf(
            "server.call" to { _, p -> HostReply.of(scope.async { invoke(p, false) }) },
            "server.render" to { _, p -> HostReply.of(scope.async { invoke(p, true) }) },
            "net.fetch" to { _, p -> HostReply.of(scope.async { clientFetch(p) }) },
        )

    private fun headers(): Map<String, String> {
        val h = linkedMapOf("content-type" to "application/json")
        if (!authorization.isNullOrEmpty()) h["authorization"] = authorization
        return h
    }

    private suspend fun post(url: String, body: Any?): FetchResponse =
        platform().fetch(FetchRequest(url = url, method = "POST", headers = headers(), body = Json.stringify(body), timeoutMs = timeoutMs.toLong()))

    private suspend fun invoke(payload: String, render: Boolean): String {
        val args = positional(payload)
        val name = args.getOrNull(0)
        if (name !is String || name.isEmpty()) return "null"
        val body = if (args.size > 1) args[1] else LinkedHashMap<String, Any?>()
        val path = if (render) "render" else "fn"
        // Percent-encoded so a guest-chosen name cannot change the path's shape.
        val url = "$baseUrl/apps/${encodeURIComponent(appId)}/$path/${encodeURIComponent(name)}"
        try {
            val res = post(url, body)
            if (res.status != 200) return typedError(errorMessage(res.body) ?: "the call failed")
            val decoded = Json.parse(res.body)
            if (isMap(decoded) && decoded.asMap()!!["ok"] == true) return Json.stringify(decoded.asMap()!!["result"])
            return typedError(errorMessage(res.body) ?: "the call failed")
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            val text = e.toString()
            if (TIMED_OUT.containsMatchIn(text)) return typedError("the server did not answer in time")
            if (UNREACHABLE.containsMatchIn(text)) return typedError("the server could not be reached")
            platform().log("warn", "ElpianServerClient: $appId/$path failed: $e")
            return typedError("the call failed")
        }
    }

    private suspend fun clientFetch(payload: String): String {
        val url = positional(payload).getOrNull(0)
        if (url !is String) return "null"
        // Refused locally without a round trip; the server would refuse it too.
        if (!netPolicy.allows(url)) return typedError("the request was not permitted")
        // Allowed requests still go through the host's broker (one policy, one audit trail).
        try {
            val res = post("$baseUrl/apps/$appId/proxy", linkedMapOf("url" to url))
            if (res.status != 200) return typedError("the request was not permitted")
            val decoded = Json.parse(res.body)
            if (isMap(decoded) && decoded.asMap()!!["ok"] == true) return Json.stringify(decoded.asMap()!!["result"])
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            /* fall through */
        }
        return typedError("the request was not permitted")
    }

    suspend fun renderComponent(name: String, args: Map<String, Any?>): ServerRenderResult {
        val raw = invoke(Json.stringify(listOf(name, args)), true)
        try {
            val d = Json.parse(raw)
            if (isMap(d)) {
                val m = d.asMap()!!
                if (m["error"] != null) return ServerRenderResult(error = errorOf(m["error"]))
                return ServerRenderResult(payload = m)
            }
        } catch (_: Exception) {
            /* fall through */
        }
        return ServerRenderResult(error = "the server returned no payload")
    }

    suspend fun callAction(name: String, args: Map<String, Any?>): ServerCallResult {
        val raw = invoke(Json.stringify(listOf(name, args)), false)
        return try {
            val d = Json.parse(raw)
            if (isMap(d) && d.asMap()!!["error"] != null) ServerCallResult(error = errorOf(d.asMap()!!["error"]))
            else ServerCallResult(result = d)
        } catch (_: Exception) {
            ServerCallResult(error = "the call failed")
        }
    }

    /**
     * Stream a component: newline-delimited frames, each a stream command
     * (`{"action":"error"}` frames surface as errors). Returns a canceller.
     */
    fun streamComponent(name: String, args: Map<String, Any?>, sink: ServerStreamSink): () -> Unit {
        if (closed) {
            sink.onError("the stream could not be opened")
            sink.onDone()
            return {}
        }
        val buffer = StringBuilder()
        var finished = false
        lateinit var cancel: () -> Unit
        fun finish() {
            if (finished) return
            finished = true
            cancels.remove(cancel)
            sink.onDone()
        }
        fun emit(line: String) {
            try {
                val d = Json.parse(line)
                if (isMap(d) && d.asMap()!!["action"] == "error") sink.onError(jsString(d.asMap()!!["message"] ?: "the stream failed"))
                else sink.onFrame(d)
            } catch (_: Exception) {
                // A bad line is skipped; the stream keeps going.
                platform().log("debug", "ElpianServerClient: $appId dropped an unparseable stream line")
            }
        }
        val cancelStream = platform().fetchStream(
            FetchRequest(
                url = "$baseUrl/apps/${encodeURIComponent(appId)}/stream/${encodeURIComponent(name)}",
                method = "POST",
                headers = headers(),
                body = Json.stringify(args),
                timeoutMs = timeoutMs.toLong(),
            ),
            object : StreamHandlers {
                override fun onChunk(text: String) {
                    // Chunk boundaries fall anywhere, including mid-line.
                    buffer.append(text)
                    while (true) {
                        val i = buffer.indexOf("\n")
                        if (i < 0) break
                        val line = buffer.substring(0, i).trim()
                        buffer.delete(0, i + 1)
                        if (line.isNotEmpty()) emit(line)
                    }
                }

                override fun onDone() {
                    val tail = buffer.toString().trim()
                    if (tail.isNotEmpty()) emit(tail)
                    finish()
                }

                override fun onError(message: String) {
                    sink.onError(
                        if (Regex("time", RegexOption.IGNORE_CASE).containsMatchIn(message)) "the stream timed out"
                        else if (Regex("status|HTTP", RegexOption.IGNORE_CASE).containsMatchIn(message)) "the stream could not be opened"
                        else "the stream failed",
                    )
                    finish()
                }
            },
        )
        cancel = {
            cancelStream()
            finish()
        }
        cancels.add(cancel)
        return cancel
    }

    /** Show a streamed component on a surface (ElpianStreamWidget over streamComponent). */
    fun mountStream(surfaceId: String, name: String, args: Map<String, Any?>, options: StreamSessionOptions = StreamSessionOptions()): StreamSession {
        val session = StreamSession(surfaceId, options)
        val cancel = streamComponent(
            name,
            args,
            object : ServerStreamSink {
                override fun onFrame(frame: Any?) = session.push(frame)
                override fun onError(message: String) = session.error(message)
                override fun onDone() = session.done()
            },
        )
        session.beforeDispose = { cancel() }
        return session
    }

    fun close() {
        closed = true
        for (c in cancels.toList()) c()
        scope.cancel()
    }
}

private val TIMED_OUT = Regex("timed? ?out", RegexOption.IGNORE_CASE)
private val UNREACHABLE = Regex("network|connect|resolve|unreachable", RegexOption.IGNORE_CASE)

private fun errorOf(e: Any?): String =
    if (isMap(e)) jsString(e.asMap()!!["message"] ?: "the call failed") else jsString(e)

private fun positional(payload: String): List<Any?> = try {
    val d = Json.parse(payload)
    if (d is List<*>) d.toList() else listOf(d)
} catch (_: Exception) {
    emptyList()
}

private fun errorMessage(body: String): String? = try {
    val d = Json.parse(body)
    if (isMap(d)) d.asMap()!!["error"] as? String else null
} catch (_: Exception) {
    null
}

private fun typedError(message: String): String =
    Json.stringify(linkedMapOf("error" to linkedMapOf("code" to "unavailable", "message" to message)))

// ============================================================================
// ServerComponent
// ============================================================================

/** Builds an island from its props; server-rendered children arrive as `#children`. */
typealias IslandBuilder = (props: JsonMap) -> W

class ServerComponentOptions(
    val client: ElpianServerClient,
    val name: String,
    val args: Map<String, Any?>? = null,
    /** Lowering-function islands. */
    val islandBuilders: Map<String, IslandBuilder>? = null,
    /** Islands rendered by host-registered native components, by island name → component name. */
    val nativeIslands: Map<String, String>? = null,
    /** Re-fetch interval (ms). */
    val revalidateMs: Double? = null,
    val pending: W? = null,
    val errorBuilder: ((message: String) -> W)? = null,
    val surface: SurfaceOptions? = null,
)

class ServerComponentSession(surfaceId: String, private var options: ServerComponentOptions) {
    val surface: ElpianSurface = ElpianSurface(surfaceId, options.surface ?: SurfaceOptions())
    private var payload: JsonMap? = null
    private var error: String? = null
    private var loading = true
    private var generation = 0
    private var timer: Int? = null
    private var disposed = false
    private var stylesheetKey: String? = null

    /** Fetches run here; cancelled on dispose. */
    val scope: CoroutineScope = CoroutineScope(SupervisorJob() + platform().dispatcher)

    init {
        registerIslands()
        scope.launch { fetch() }
        scheduleRevalidation()
    }

    private fun registerIslands() {
        val engine = surface.engine
        for ((name, build) in options.islandBuilders ?: emptyMap()) {
            val builder: WidgetBuilder = { node, children, _ ->
                val props: JsonMap = LinkedHashMap(node.props)
                if (children.isNotEmpty()) props["#children"] = children
                build(props)
            }
            engine.registerWidget(name, builder)
        }
        for ((name, component) in options.nativeIslands ?: emptyMap()) {
            engine.registerWidget(name) { node, children, _ ->
                w(
                    "native",
                    mapOf(
                        "component" to component,
                        "componentProps" to LinkedHashMap(node.props),
                        "width" to node.style?.width,
                        "height" to node.style?.height,
                        "onEvent" to { _: ViewEvent -> },
                    ),
                    children,
                )
            }
        }
    }

    /**
     * Change name/args/revalidation (didUpdateWidget). [next] holds the
     * changed fields by option name (`name`, `args`, `islandBuilders`,
     * `nativeIslands`, `revalidateMs`, `pending`, `errorBuilder`), as the TS
     * `Partial<ServerComponentOptions>` does.
     */
    @Suppress("UNCHECKED_CAST")
    fun update(next: Map<String, Any?>) {
        val prev = options
        fun <T> pick(key: String, current: T): T = if (next.containsKey(key)) next[key] as T else current
        options = ServerComponentOptions(
            client = prev.client,
            name = pick<Any?>("name", prev.name)?.let { jsString(it) } ?: prev.name,
            args = pick<Any?>("args", prev.args)?.asMap(),
            islandBuilders = pick("islandBuilders", prev.islandBuilders),
            nativeIslands = pick("nativeIslands", prev.nativeIslands),
            revalidateMs = pick<Any?>("revalidateMs", prev.revalidateMs)?.let { (it as? Number)?.toDouble() },
            pending = pick("pending", prev.pending),
            errorBuilder = pick("errorBuilder", prev.errorBuilder),
            surface = prev.surface,
        )
        registerIslands()
        val nextName = next["name"]
        val nextArgs = next["args"]
        if ((nextName != null && jsString(nextName) != prev.name) || (nextArgs != null && !sameArgs(prev.args ?: emptyMap(), nextArgs.asMap() ?: emptyMap()))) {
            scope.launch { fetch() }
        }
        if (next.containsKey("revalidateMs") && (next["revalidateMs"] as? Number)?.toDouble() != prev.revalidateMs) scheduleRevalidation()
    }

    private fun scheduleRevalidation() {
        timer?.let { platform().clearTimeout(it) }
        timer = null
        val interval = options.revalidateMs
        if (interval == null || interval <= 0) return
        lateinit var tick: () -> Unit
        tick = {
            if (!disposed) {
                timer = platform().setTimeout(interval, tick)
                scope.launch { fetch() }
            }
        }
        timer = platform().setTimeout(interval, tick)
    }

    suspend fun fetch() {
        val gen = ++generation
        // Only the first fetch shows the pending state; revalidation keeps the screen.
        if (payload == null) {
            loading = true
            paint()
        }
        val result = options.client.renderComponent(options.name, options.args ?: emptyMap())
        if (disposed || gen != generation) return
        loading = false
        if (result.error != null) {
            error = result.error
        } else {
            // A failed revalidation keeps content that is already showing.
            error = null
            payload = result.payload
        }
        paint()
    }

    /** Islands the payload declares that no builder handles. */
    fun unresolvedIslands(): List<String> {
        val declared = payload?.get("clientComponents")
        if (!isMap(declared)) return emptyList()
        return declared.asMap()!!.keys.filter { k ->
            (options.islandBuilders?.containsKey(k) != true) && (options.nativeIslands?.containsKey(k) != true)
        }
    }

    private fun paint() {
        if (disposed) return
        val s = surface
        fun errorBox(m: String): W = options.errorBuilder?.invoke(m)
            ?: w("padding", mapOf("padding" to EdgeInsets(12.0, 12.0, 12.0, 12.0)), w("text", mapOf("text" to m, "style" to TextStyle(color = 0xffb3261e.toInt()))))
        val p = payload
        if (p == null) {
            val err = error
            if (err != null) s.setOverlay(errorBox(err))
            else if (loading) s.setOverlay(options.pending ?: loadingIndicator())
            else s.setContent(null)
            return
        }
        val component = p["component"]
        if (!isMap(component)) {
            s.setOverlay(errorBox("the server component returned no component tree"))
            return
        }
        val sheet = p["stylesheet"]
        if (isMap(sheet)) {
            val key = stableKey(sheet)
            if (key != stylesheetKey) {
                stylesheetKey = key
                s.engine.loadStylesheet(sheet)
            }
        }
        s.setContent(component.asMap())
    }

    fun dispose() {
        disposed = true
        timer?.let { platform().clearTimeout(it) }
        scope.cancel()
        surface.dispose()
    }
}

/** `b[k] === a[k]` for every key: value equality for primitives, identity for objects. */
private fun sameArgs(a: Map<String, Any?>, b: Map<String, Any?>): Boolean {
    if (a.size != b.size) return false
    return a.keys.all { k ->
        val x = a[k]
        val y = b[k]
        when {
            x == null || y == null -> x == null && y == null && b.containsKey(k)
            x is Number && y is Number -> x.toDouble() == y.toDouble()
            x is String || x is Boolean -> x == y
            else -> x === y
        }
    }
}
