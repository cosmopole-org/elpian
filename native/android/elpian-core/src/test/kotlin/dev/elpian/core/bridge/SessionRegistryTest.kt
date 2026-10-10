package dev.elpian.core.bridge

import dev.elpian.core.css.EdgeInsets
import dev.elpian.core.platform.FetchRequest
import dev.elpian.core.platform.FetchResponse
import dev.elpian.core.platform.Platform
import dev.elpian.core.platform.Platforms
import dev.elpian.core.platform.StreamHandlers
import dev.elpian.core.platform.Viewport
import dev.elpian.core.render.INF
import dev.elpian.core.render.RenderObject
import dev.elpian.core.render.TextMetrics
import dev.elpian.core.render.TextSpec
import dev.elpian.core.render.ViewEvent
import dev.elpian.core.render.ViewOp
import dev.elpian.core.session.surfaceById
import dev.elpian.core.util.Json
import dev.elpian.core.util.JsonMap
import dev.elpian.core.vm.JsSandbox
import dev.elpian.core.vm.JsSandboxFactory
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.runBlocking
import java.lang.Runnable
import kotlin.coroutines.CoroutineContext
import kotlin.math.ceil
import kotlin.math.min
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** A dispatcher that queues work until the test drains it (the UI thread's run loop). */
private class QueueDispatcher : CoroutineDispatcher() {
    val queue = ArrayDeque<Runnable>()

    override fun dispatch(context: CoroutineContext, block: Runnable) {
        queue.addLast(block)
    }
}

/** A JS sandbox that runs nothing: [script] maps each evaluated snippet to host calls and a result. */
private class FakeSandbox(val script: (code: String, host: (String, String) -> String) -> String) : JsSandbox {
    var handler: ((String, String) -> String)? = null
    val evaluated = ArrayList<String>()
    var disposed = false

    override fun setHostCallHandler(handler: (apiName: String, payload: String) -> String) {
        this.handler = handler
    }

    override fun evaluate(code: String): String {
        evaluated.add(code)
        return script(code, handler!!)
    }

    override fun dispose() {
        disposed = true
    }
}

private class FakePlatform : Platform {
    override val name = "fake"
    val queue = QueueDispatcher()
    override val dispatcher: CoroutineDispatcher = queue
    val commits = ArrayList<Pair<String, List<ViewOp>>>()
    val logs = ArrayList<String>()
    private val frames = ArrayList<(Double) -> Unit>()
    private var clock = 0.0
    val timers = LinkedHashMap<Int, () -> Unit>()
    private var nextTimer = 1
    var streamHandlers: StreamHandlers? = null
    var streamRequest: FetchRequest? = null
    var streamCancelled = false
    var sandboxScript: (code: String, host: (String, String) -> String) -> String = { _, _ -> "undefined" }
    val sandboxes = ArrayList<FakeSandbox>()

    override fun now() = clock
    override fun setTimeout(ms: Double, callback: () -> Unit): Int {
        val h = nextTimer++
        timers[h] = callback
        return h
    }
    override fun clearTimeout(handle: Int) {
        timers.remove(handle)
    }
    override fun requestFrame(callback: (Double) -> Unit) {
        frames.add(callback)
    }
    override fun commit(surface: String, ops: List<ViewOp>) {
        commits.add(surface to ops)
    }
    /** Each character is half the font size wide; lines are 1.2 em. */
    override fun measureText(spec: TextSpec, maxWidth: Double): TextMetrics {
        val fs = spec.spans.firstOrNull()?.style?.fontSize ?: 14.0
        val chars = spec.spans.sumOf { it.text.length }
        val natural = chars * fs * 0.5
        val lines = if (maxWidth == INF || natural <= maxWidth) 1 else ceil(natural / maxWidth).toInt()
        return TextMetrics(min(natural, maxWidth), lines * fs * 1.2, fs * 0.8, lines, false)
    }
    override fun viewport(surface: String) = Viewport(400.0, 300.0, 2.0, EdgeInsets.ZERO, "en-US", "android", false, false, 1.0, "https://app.test:8080/home?q=a+b&x=1#top")
    override fun log(level: String, message: String) {
        logs.add("$level: $message")
    }
    override suspend fun fetch(request: FetchRequest) = FetchResponse(404, emptyMap(), "")
    override fun fetchStream(request: FetchRequest, handlers: StreamHandlers): () -> Unit {
        streamRequest = request
        streamHandlers = handlers
        return { streamCancelled = true }
    }
    override suspend fun loadAsset(path: String) = ByteArray(0)

    override val jsSandbox: JsSandboxFactory = object : JsSandboxFactory {
        override fun create(machineId: String): JsSandbox = FakeSandbox { code, host -> sandboxScript(code, host) }.also { sandboxes.add(it) }
    }

    /** Run queued coroutines and pending frames until idle. */
    fun drain() {
        repeat(200) {
            if (queue.queue.isEmpty() && frames.isEmpty()) return
            while (queue.queue.isNotEmpty()) queue.queue.removeFirst().run()
            val due = frames.toList()
            frames.clear()
            clock += 16.0
            for (f in due) f(clock)
        }
    }

    fun allOps(surface: String): List<ViewOp> = commits.filter { it.first == surface }.flatMap { it.second }
}

class SessionRegistryTest {
    private lateinit var platform: FakePlatform
    private lateinit var registry: SessionRegistry
    private val events = ArrayList<Triple<String, String, Any?>>()

    @BeforeTest
    fun setUp() {
        platform = FakePlatform()
        Platforms.install(platform)
        registry = SessionRegistry { surface, event, payload -> events.add(Triple(surface, event, payload)) }
    }

    @AfterTest
    fun tearDown() {
        runBlocking { registry.closeAll() }
        platform.drain()
    }

    @Suppress("UNCHECKED_CAST")
    private fun json(text: String): JsonMap = Json.parse(text) as JsonMap

    private fun open(kind: String, surface: String, options: Map<String, Any?>) {
        runBlocking { registry.open(kind, surface, options) }
        platform.drain()
    }

    private fun call(surface: String, method: String, vararg args: Any?): Any? {
        val r = runBlocking { registry.call(surface, method, args.toList()) }
        platform.drain()
        return r
    }

    private fun texts(surface: String): List<String> = platform.allOps(surface).mapNotNull { op ->
        val props = when (op) {
            is ViewOp.Create -> op.props
            is ViewOp.Update -> op.props
            else -> null
        }
        (props?.get("text") as? TextSpec)?.spans?.joinToString("") { it.text }
    }

    private fun find(surface: String, pred: (RenderObject) -> Boolean): RenderObject? {
        var hit: RenderObject? = null
        surfaceById(surface)?.owner?.root?.visit { if (hit == null && pred(it)) hit = it }
        return hit
    }

    @Test
    fun jsonSessionCommitsViewOpsAndAppliesMethods() {
        open(
            "json",
            "s1",
            mapOf(
                "view" to json(
                    """{"type": "Column", "children": [
                         {"type": "Text", "props": {"text": "Hello"}},
                         {"type": "Text", "key": "second", "props": {"text": "World"}}
                       ]}""",
                ),
            ),
        )
        assertTrue(registry.has("s1"))
        val creates = platform.allOps("s1").filterIsInstance<ViewOp.Create>()
        assertTrue(creates.isNotEmpty(), "the first frame creates native views")
        assertEquals(listOf("Hello", "World"), texts("s1"))

        // A scoped patch replaces only the keyed subtree.
        val patched = call("s1", "patch", json("""{"type": "Text", "props": {"text": "Patched"}}"""), "second")
        assertEquals(true, patched)
        assertTrue("Patched" in texts("s1"))
        // A patch whose scope is missing is dropped.
        assertEquals(false, call("s1", "patch", json("""{"type": "Text", "props": {"text": "Nope"}}"""), "missing"))

        call("s1", "setContent", json("""{"type": "Text", "props": {"text": "Replaced"}}"""))
        assertTrue(platform.allOps("s1").any { it is ViewOp.Remove }, "views no longer rendered are removed")
        assertEquals("Replaced", texts("s1").last())

        val failure = runCatching { runBlocking { registry.call("s1", "nope", emptyList()) } }.exceptionOrNull()
        assertEquals("json session has no method nope", failure?.message)

        runBlocking { registry.close("s1") }
        assertFalse(registry.has("s1"))
        assertNull(surfaceById("s1"))
    }

    @Test
    fun tapOnNodeWithEventHandlerDispatchesClick() {
        open(
            "json",
            "tap",
            mapOf("view" to json("""{"type": "div", "props": {"id": "btn"}, "events": {"click": "onPress"}, "children": [{"type": "Text", "props": {"text": "Press"}}]}""")),
        )
        val surface = assertNotNull(surfaceById("tap"))
        val received = ArrayList<String>()
        surface.engine.services.events.onGlobalEvent { received.add(it.type) }
        val gesture = assertNotNull(find("tap") { it.type == "gesture" && it.viewId != null }, "event-bearing node has a gesture view")
        registry.dispatchViewEvent("tap", ViewEvent(id = gesture.viewId!!, type = "tap", x = 5.0, y = 5.0, localX = 5.0, localY = 5.0))
        platform.drain()
        assertEquals(listOf("click"), received)
    }

    @Test
    fun miniappSessionDrivesTheHostCallProtocol() {
        platform.sandboxScript = { code, host ->
            when {
                code == "PROGRAM" -> {
                    host("println", "\"booted\"")
                    host("render", Json.stringify(json("""{"type": "div", "events": {"click": "onTap"}, "children": [{"type": "Text", "props": {"text": "Count 0"}}]}""")))
                    "undefined"
                }
                code.startsWith("main(") -> {
                    host("render", Json.stringify(json("""{"type": "div", "events": {"click": "onTap"}, "children": [{"type": "Text", "props": {"text": "Count 1"}}]}""")))
                    "undefined"
                }
                code.startsWith("onTap(") -> {
                    host("render", Json.stringify(json("""{"type": "div", "children": [{"type": "Text", "props": {"text": "Tapped"}}]}""")))
                    "undefined"
                }
                else -> "undefined"
            }
        }
        open("miniapp", "m1", mapOf("runtime" to "quickjs", "code" to "PROGRAM", "entryFunction" to "main", "entryInput" to mapOf("n" to 1.0)))

        val sandbox = platform.sandboxes.single()
        // Bootstrap, env sync, program, entry function with its JSON input.
        assertTrue(sandbox.evaluated.contains("PROGRAM"))
        assertTrue(sandbox.evaluated.any { it.startsWith("main(JSON.parse(") && it.contains("\\\"n\\\":1") })
        assertTrue(sandbox.evaluated.any { it.contains("__ELPIAN_HOST_ENV__") && it.contains("landscape") })
        assertEquals(listOf("m1" to "println", "m1" to "ready"), events.map { it.first to it.second })
        assertEquals("booted", events[0].third)

        val view = call("m1", "view") as Map<*, *>
        assertEquals("div", view["type"])
        assertEquals("Count 1", texts("m1").last())

        // A tap routes to the guest function named in node.events.
        val gesture = assertNotNull(find("m1") { it.type == "gesture" && it.viewId != null })
        registry.dispatchViewEvent("m1", ViewEvent(id = gesture.viewId!!, type = "tap", x = 1.0, y = 1.0, localX = 1.0, localY = 1.0))
        platform.drain()
        assertTrue(sandbox.evaluated.any { it.startsWith("onTap(JSON.parse(") })
        assertEquals("Tapped", texts("m1").last())

        // Governance over the string API.
        @Suppress("UNCHECKED_CAST")
        val state = call("m1", "state") as Map<String, Any?>
        assertEquals("running", state["state"])
        call("m1", "terminate")
        assertTrue(sandbox.disposed)

        runBlocking { registry.close("m1") }
    }

    @Test
    fun streamSessionReadsChunkedNdjsonAndSse() {
        open("stream", "st", mapOf("request" to mapOf("url" to "https://example.test/stream", "method" to "POST", "body" to mapOf("a" to 1.0))))
        assertEquals("https://example.test/stream", platform.streamRequest?.url)
        assertEquals("{\"a\":1}", platform.streamRequest?.body)
        val h = assertNotNull(platform.streamHandlers)

        // Chunk boundaries fall mid-line.
        h.onChunk("""{"action": "setView", "view": {"type": "Text", "props": {"text": "Fir""")
        h.onChunk("st\"}}}\n")
        platform.drain()
        assertEquals("First", texts("st").last())

        h.onChunk("data: {\"action\": \"patchView\",\n")
        h.onChunk("data:  \"patch\": {\"props\": {\"text\": \"Second\"}}}\n\n")
        h.onChunk(": a comment\nevent: update\n")
        platform.drain()
        assertEquals("Second", texts("st").last())

        h.onChunk("{\"action\": \"bogus\"}\n")
        platform.drain()
        assertTrue(events.any { it.second == "error" && it.third == "Unknown stream action: bogus." })
        assertTrue(texts("st").last().startsWith("Stream Error:"))

        // A bare view (no action) is a setView; the error clears.
        h.onChunk("{\"type\": \"Text\", \"props\": {\"text\": \"Third\"}}")
        h.onDone()
        platform.drain()
        assertEquals("Third", texts("st").last())
        assertTrue(events.any { it.second == "streamDone" })
        @Suppress("UNCHECKED_CAST")
        val commands = events.filter { it.second == "command" }.map { (it.third as Map<String, Any?>)["action"] }
        assertEquals(listOf("setView", "patchView", "bogus", "setView"), commands)

        // Pushed commands work too.
        call("st", "push", "{\"action\": \"setView\", \"view\": {\"type\": \"Text\", \"props\": {\"text\": \"Pushed\"}}}")
        assertEquals("Pushed", texts("st").last())

        runBlocking { registry.close("st") }
        assertTrue(platform.streamCancelled)
    }

    @Test
    fun callAsyncEmitsResults() {
        open("json", "a1", mapOf("view" to json("""{"type": "Text", "props": {"text": "x"}}""")))
        registry.callAsync("a1", "patch", listOf(json("""{"type": "Text"}"""), "missing"), 7.0)
        registry.callAsync("a1", "unknown", emptyList(), 8.0)
        registry.callAsync("nowhere", "x", emptyList(), 9.0)
        platform.drain()
        val results = events.filter { it.second == "result" }.map { it.third as Map<*, *> }
        assertEquals(listOf(7.0, 8.0, 9.0), results.map { it["requestId"] })
        assertEquals(listOf(true, false, false), results.map { it["ok"] })
        assertEquals(false, results[0]["value"])
        assertEquals("no session on surface \"nowhere\"", results[2]["error"])
    }

    private fun runTimers() {
        repeat(10) {
            val due = platform.timers.values.toList()
            platform.timers.clear()
            for (t in due) t()
            platform.drain()
        }
    }

    private val catalogId = "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"

    private fun agentReply(text: String): String =
        "{\"type\":\"conversation\",\"conversationId\":\"c1\"}\n" +
            "{\"version\":\"v0.9.1\",\"createSurface\":{\"surfaceId\":\"s\",\"catalogId\":\"$catalogId\"}}\n" +
            "{\"version\":\"v0.9.1\",\"updateComponents\":{\"surfaceId\":\"s\",\"components\":[{\"id\":\"root\",\"component\":\"Text\",\"text\":\"$text\"}]}}\n" +
            "{\"type\":\"text\",\"text\":\"prose\"}\n{\"type\":\"done\",\"stopReason\":\"end_turn\"}\n"

    @Test
    fun miniappSessionPointsA2uiSurfacesAtTheAppsAgents() {
        // An agentic mini app: static UI next to an A2UISurface talking to the app's agent.
        platform.sandboxScript = { code, host ->
            if (code == "PROGRAM") {
                host(
                    "render",
                    Json.stringify(
                        json(
                            """{"type": "Column", "children": [
                                 {"type": "Text", "props": {"text": "Static UI"}},
                                 {"type": "A2UISurface", "props": {"agent": "helper", "prompt": "hello"}}
                               ]}""",
                        ),
                    ),
                )
            }
            "undefined"
        }
        open("miniapp", "ma", mapOf("runtime" to "quickjs", "code" to "PROGRAM", "baseUrl" to "https://api.test/", "appId" to "demo", "headers" to mapOf("x-k" to "v")))
        val defaults = dev.elpian.core.a2ui.a2uiRegistry(surfaceById("ma")!!.engine.services).defaults
        assertEquals("https://api.test/", defaults.baseUrl)
        assertEquals("demo", defaults.appId)
        runTimers()
        val request = assertNotNull(platform.streamRequest)
        assertEquals("https://api.test/apps/demo/agent/helper", request.url)
        assertEquals("v", request.headers["x-k"])
        assertEquals("hello", (Json.parse(request.body!!) as Map<*, *>)["message"])
        platform.streamHandlers!!.onChunk(agentReply("From the agent"))
        platform.streamHandlers!!.onDone()
        platform.drain()
        val shown = texts("ma")
        assertTrue(shown.contains("Static UI"), shown.toString())
        assertTrue(shown.contains("From the agent"), shown.toString())
        runBlocking { registry.close("ma") }
    }

    @Test
    fun miniappSessionWithoutAgentDefaultsNeverCallsAnAgent() {
        platform.sandboxScript = { code, host ->
            if (code == "PROGRAM") host("render", Json.stringify(json("""{"type": "A2UISurface", "props": {"agent": "helper", "prompt": "hello"}}""")))
            "undefined"
        }
        open("miniapp", "mb", mapOf("runtime" to "quickjs", "code" to "PROGRAM"))
        runTimers()
        assertNull(platform.streamRequest)
        runBlocking { registry.close("mb") }
    }

    @Test
    fun agentSessionConversesWithAnAgent() {
        open("agent", "ag", mapOf("baseUrl" to "https://api.test", "appId" to "demo", "agent" to "helper", "prompt" to "start"))
        runTimers()
        val request = assertNotNull(platform.streamRequest)
        assertEquals("https://api.test/apps/demo/agent/helper", request.url)
        platform.streamHandlers!!.onChunk(agentReply("Agent UI"))
        platform.streamHandlers!!.onDone()
        platform.drain()
        assertTrue(texts("ag").contains("Agent UI"), texts("ag").toString())
        assertTrue(events.any { it.first == "ag" && it.second == "a2uiText" && (it.third as Map<*, *>)["text"] == "prose" })
        assertTrue(events.any { it.first == "ag" && it.second == "done" })

        registry.callAsync("ag", "send", listOf("more"), 1.0)
        platform.drain()
        val body = Json.parse(platform.streamRequest!!.body!!) as Map<*, *>
        assertEquals("more", body["message"])
        assertEquals("c1", body["conversationId"])
        platform.streamHandlers!!.onChunk("{\"type\":\"conversation\",\"conversationId\":\"c1\"}\n{\"type\":\"done\",\"stopReason\":\"end_turn\"}\n")
        platform.streamHandlers!!.onDone()
        platform.drain()
        val result = events.last { it.second == "result" }.third as Map<*, *>
        assertEquals(true, result["ok"])
        assertEquals("c1", (result["value"] as Map<*, *>)["conversationId"])

        @Suppress("UNCHECKED_CAST")
        val described = call("ag", "conversation") as Map<String, Any?>
        assertEquals("c1", described["conversationId"])
        assertEquals(3, (described["transcript"] as List<*>).size)
        runBlocking { registry.close("ag") }
    }

    @Test
    fun unknownKindFails() {
        val failure = runCatching { runBlocking { registry.open("bogus", "b", emptyMap()) } }.exceptionOrNull()
        assertEquals("unknown session kind \"bogus\"", failure?.message)
    }
}
