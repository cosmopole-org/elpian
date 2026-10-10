package dev.elpian.core.a2ui

import dev.elpian.core.host.HostHandler
import dev.elpian.core.util.Json
import dev.elpian.core.util.JsonMap
import dev.elpian.core.vm.HostReply
import dev.elpian.core.widgets.MATERIAL_ICON_CODEPOINTS
import kotlinx.coroutines.runBlocking
import java.time.LocalDate
import java.time.ZoneId
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * The basic catalog examples through processor + lowering + reconcile +
 * layout, the catalog table against catalog.json, functions, two-way binding,
 * Tabs / Modal state, the transport's chunk-split NDJSON decoding, a
 * conversation against a fake agent, and the A2UISurface widget and host
 * APIs (native/web/test/a2ui/renderer.test.mjs).
 */
@Suppress("UNCHECKED_CAST")
class RendererTest {
    private lateinit var platform: A2UITestPlatform

    @BeforeTest
    fun setUp() {
        platform = A2UITestPlatform.install()
    }

    private fun obj(v: Any?): JsonMap = v as JsonMap

    private fun hooks(processor: A2UIProcessor, log: MutableList<List<Any?>> = ArrayList()): LoweringHooks = object : LoweringHooks {
        override fun write(surfaceId: String, path: String, value: Any?) {
            log.add(listOf("write", path, value))
            processor.setData(surfaceId, path, value)
        }

        override fun action(surfaceId: String, componentId: String, action: Any?, scope: String) {
            log.add(listOf("action", processor.dispatchAction(surfaceId, componentId, action, scope)))
        }

        override fun invalidate() {
            log.add(listOf("invalidate"))
        }

        override fun error(error: A2UIError) {
            log.add(listOf("error", error.message))
        }
    }

    @Test
    fun basicCatalogTableMatchesCatalogJson() {
        val json = obj(A2UIFiles.readJson("spec", "catalogs", "basic", "catalog.json"))
        assertEquals(json["catalogId"], BASIC_CATALOG.id)
        val components = obj(json["components"])
        assertEquals(components.keys.sorted(), BASIC_COMPONENTS.keys.sorted())
        for ((name, schema) in components) {
            val allOf = obj(schema)["allOf"] as List<*>
            val own = allOf.map { obj(it) }.first { (it["properties"] as? Map<*, *>)?.containsKey("component") == true }
            val ownProps = obj(own["properties"])
            val props = ownProps.keys.filter { it != "component" }
            val checkable = allOf.any { (obj(it)["\$ref"] as? String)?.endsWith("Checkable") == true }
            val spec = BASIC_COMPONENTS.getValue(name)
            assertEquals(props.sorted(), spec.props.keys.filter { it != "checks" }.sorted(), name)
            assertEquals(checkable, spec.props.containsKey("checks"), "$name checks")
            assertEquals((own["required"] as List<*>).map { it.toString() }.filter { it != "component" }.sorted(), spec.required.sorted(), "$name required")
            for (p in props) {
                val e = obj(ownProps[p])["enum"] as? List<*> ?: continue
                assertEquals(e.map { it.toString() }.sorted(), spec.props.getValue(p).enum!!.sorted(), "$name.$p")
            }
        }
        assertEquals(listOf("accessibility", "component", "id", "weight"), COMMON_PROPS.keys.sorted())
        val functions = obj(json["functions"])
        assertEquals(functions.keys.sorted(), BASIC_FUNCTION_SPECS.keys.sorted())
        for ((name, schema) in functions) {
            val p = obj(obj(schema)["properties"])
            assertEquals(obj(obj(p["args"])["properties"]).keys.sorted(), BASIC_FUNCTION_SPECS.getValue(name).args.keys.sorted(), name)
            assertEquals(obj(p["returnType"])["const"], BASIC_FUNCTION_SPECS.getValue(name).returnType, name)
        }
        val icon = obj((obj(components["Icon"])["allOf"] as List<*>)[2])
        val iconEnum = (obj((obj(obj(icon["properties"])["name"])["oneOf"] as List<*>)[0])["enum"] as List<*>).map { it.toString() }
        assertEquals(iconEnum.sorted(), ICON_NAMES.sorted())
    }

    @Test
    fun everyCatalogIconMapsToAMaterialIcon() {
        for (name in ICON_NAMES) assertNotNull(MATERIAL_ICON_CODEPOINTS[materialIconName(name)], "$name -> ${materialIconName(name)}")
    }

    @Test
    fun everyBasicCatalogExampleProcessesLowersAndLaysOut() {
        val all = A2UIFiles.examples()
        assertEquals(43, all.size)
        val orphan = Regex("^Component '(.+)' is not reachable")
        for ((file, example) in all) {
            val messages = example["messages"] as List<Any?>
            val processor = A2UIProcessor(A2UIProcessorOptions(validation = "strict"))
            val errors = processor.processAll(messages)
            assertEquals(emptyList(), errors.map { "${it.path}: ${it.message}" }, "$file processing errors")
            // The whole batch also passes strict topology validation
            // (incremental examples replace placeholders, leaving them unreachable — allowed).
            val topology = A2UIValidator(BASIC_CATALOG, strict = true).validateBatch(messages).map { it.message }
            val orphans = topology.mapNotNull { orphan.find(it)?.groupValues?.get(1) }.toSet()
            assertEquals(emptyList(), topology.filter { !it.contains("is not reachable") }, "$file topology")
            assertTrue(processor.surfaces.isNotEmpty(), file)
            for (surface in processor.surfaces) {
                assertTrue(surface.isReady, "$file ${surface.id} has a root")
                val log = ArrayList<List<Any?>>()
                val result = lowerSurface(surface, LoweringOptions(hooks(processor, log), A2UIUiState(), expandAll = true))
                assertEquals(emptyList(), result.placeholders.map { "${it.id}: ${it.reason}" }, "$file placeholders")
                assertEquals(emptyList(), log.filter { it[0] == "error" }, "$file evaluation errors")
                // Every component is lowered — except a template whose list is empty.
                val lowered = result.lowered.map { it.substringBefore('@') }.toSet()
                for (id in surface.components.keys) {
                    if (id in lowered || id in orphans) continue
                    val asTemplate = surface.components.values.any { c -> (c["children"] as? Map<*, *>)?.get("componentId") == id }
                    assertTrue(asTemplate, "$file: $id was not lowered")
                }
                val (s, ops) = renderOnSurface(result.node)
                assertTrue(ops.isNotEmpty(), "$file committed view ops")
                assertTrue(s.owner.root!!.size.height > 0, "$file laid out with height")
                val types = HashSet<String>()
                walk(result.node) { types.add(it["type"].toString()) }
                for (t in types) assertTrue(s.engine.services.registry.containsKey(t), "$file lowered to unregistered widget $t")
                assertTrue(platform.logs.none { it.contains("render error") || it.contains("Unknown widget") }, platform.logs.joinToString("\n"))
                s.dispose()
            }
        }
    }

    private fun msg(kind: String, body: Map<String, Any?>): JsonMap = linkedMapOf("version" to "v0.9.1", kind to body)

    @Test
    fun twoWayBindingChecksAndActionsOnAForm() {
        val p = A2UIProcessor()
        val required = """{"condition": {"call": "required", "args": {"value": {"path": "/form/name"}}}, "message": "Required"}"""
        p.processAll(
            listOf(
                msg("createSurface", linkedMapOf("surfaceId" to "f", "catalogId" to BASIC_CATALOG.id, "theme" to linkedMapOf("primaryColor" to "#00BFFF"))),
                Json.parse(
                    """{"version": "v0.9.1", "updateComponents": {"surfaceId": "f", "components": [
                      {"id": "root", "component": "Column", "children": ["name", "echo", "go"]},
                      {"id": "name", "component": "TextField", "label": "Name", "value": {"path": "/form/name"}, "checks": [$required]},
                      {"id": "echo", "component": "Text", "text": {"call": "formatString", "args": {"value": "Hi ${'$'}{/form/name}"}, "returnType": "string"}},
                      {"id": "go_label", "component": "Text", "text": "Go"},
                      {"id": "go", "component": "Button", "child": "go_label", "variant": "primary",
                       "action": {"event": {"name": "submit", "context": {"name": {"path": "/form/name"}}}}, "checks": [$required]}
                    ]}}""",
                ),
            ),
        )
        val log = ArrayList<List<Any?>>()
        val state = A2UIUiState()
        val lower = { lowerSurface(p.surface("f")!!, LoweringOptions(hooks(p, log), state)).node }
        var tree = lower()
        val button = findNode(tree) { it["type"] == "Button" }!!
        assertEquals(true, button.nodeProps()["disabled"], "disabled while the check fails")
        assertEquals("#00BFFF", obj(button.nodeProps()["style"])["backgroundColor"], "theme primary color")
        findNode(tree) { it["type"] == "TextField" }!!.fire("input", "Ada", hasValue = true)
        assertJson(mapOf("form" to mapOf("name" to "Ada")), p.dataModel("f"))
        tree = lower()
        assertEquals("Ada", findNode(tree) { it["type"] == "TextField" }!!.nodeProps()["value"])
        assertEquals("Hi Ada", findNode(tree) { it["type"] == "Text" && (it.nodeProps()["text"] as String).startsWith("Hi") }!!.nodeProps()["text"])
        val enabled = findNode(tree) { it["type"] == "Button" }!!
        assertEquals(false, enabled.nodeProps()["disabled"])
        enabled.fire("click")
        val action = log.first { it[0] == "action" }[1] as A2UIClientAction
        assertEquals("submit", action.name)
        assertEquals("f", action.surfaceId)
        assertEquals("go", action.sourceComponentId)
        assertJson(mapOf("name" to "Ada"), action.context)
        // A server update re-renders the bound field.
        p.process(msg("updateDataModel", linkedMapOf("surfaceId" to "f", "path" to "/form/name", "value" to "Grace")))
        assertEquals("Grace", findNode(lower()) { it["type"] == "TextField" }!!.nodeProps()["value"])
    }

    @Test
    fun tabsAndModalKeepUiState() {
        val p = A2UIProcessor()
        p.processAll(obj(A2UIFiles.readJson("spec", "catalogs", "basic", "examples", "36_modal.json"))["messages"] as List<Any?>)
        val s = p.surfaces[0]
        val state = A2UIUiState()
        val log = ArrayList<List<Any?>>()
        val closed = lowerSurface(s, LoweringOptions(hooks(p, log), state))
        assertEquals("Column", closed.node["type"], "no overlay while closed")
        findNode(closed.node) { it["type"] == "Button" }!!.fire("click")
        val open = lowerSurface(s, LoweringOptions(hooks(p, log), state))
        assertEquals("ConstrainedBox", open.node["type"], "the dialog overlays the surface")
        findNode(open.node) { (it["key"] as? String)?.endsWith("/barrier") == true }!!.fire("click")
        assertEquals("Column", lowerSurface(s, LoweringOptions(hooks(p, log), state)).node["type"], "closed by the barrier")
    }

    @Test
    fun functionsFormattingAndValidation() {
        val p = A2UIProcessor(A2UIProcessorOptions(locale = "en-US"))
        p.process(msg("createSurface", linkedMapOf("surfaceId" to "s", "catalogId" to BASIC_CATALOG.id)))
        val ctx = p.surface("s")!!.context()
        fun call(name: String, args: String) = ctx.call(name, Json.parse(args) as Map<String, Any?>)
        assertEquals("1,234.50", call("formatNumber", """{"value": 1234.5, "decimals": 2}"""))
        assertEquals("1235", call("formatNumber", """{"value": 1234.5, "decimals": 0, "grouping": false}"""))
        assertEquals("€49.99", call("formatCurrency", """{"value": 49.99, "currency": "EUR"}"""))
        assertEquals("Monday, Feb 2 at 3:17 PM", call("formatDate", """{"value": "2026-02-02T15:17:00Z", "format": "EEEE, MMM d 'at' h:mm a"}"""))
        assertEquals("2026-01-16 Fri January 26", formatDatePattern(LocalDate.of(2026, 1, 16).atStartOfDay(ZoneId.systemDefault()), "yyyy-MM-dd EEE MMMM yy"))
        assertEquals("item", call("pluralize", """{"value": 1, "one": "item", "other": "items"}"""))
        assertEquals("items", call("pluralize", """{"value": 3, "one": "item", "other": "items"}"""))
        assertEquals("none", call("pluralize", """{"value": 0, "zero": "none", "other": "items"}"""))
        assertEquals(false, call("required", """{"value": []}"""))
        assertEquals(true, call("email", """{"value": "a@b.co"}"""))
        assertEquals(false, call("length", """{"value": "abc", "min": 4}"""))
        assertEquals(true, call("numeric", """{"value": "5", "min": 1, "max": 10}"""))
        assertEquals(true, call("regex", """{"value": "12345", "pattern": "^[0-9]{5}$"}"""))
        assertEquals(true, call("and", """{"values": [true, {"call": "not", "args": {"value": false}}]}"""))
        assertEquals(false, call("or", """{"values": [false, false]}"""))
        assertContains(assertFailsWith<A2UIError> { call("openUrl", """{"url": "javascript:alert(1)"}""") }.message, "not allowed")
        assertContains(assertFailsWith<A2UIError> { call("nope", "{}") }.message, "Unknown function")
        // openUrl resolves relative URLs against the base and reaches the host.
        var opened: String? = null
        val q = A2UIProcessor(A2UIProcessorOptions(baseUrl = "https://shop.test/app/", openUrl = { opened = it }))
        q.process(msg("createSurface", linkedMapOf("surfaceId" to "s", "catalogId" to BASIC_CATALOG.id)))
        q.surface("s")!!.context().call("openUrl", mapOf("url" to "help"))
        assertEquals("https://shop.test/app/help", opened)
    }

    @Test
    fun ndjsonDecodingSurvivesArbitraryChunkSplits() {
        val lines = listOf(
            mapOf("type" to "conversation", "conversationId" to "c1"),
            mapOf("version" to "v0.9.1", "createSurface" to mapOf("surfaceId" to "s", "catalogId" to BASIC_CATALOG.id)),
            mapOf("type" to "text", "text" to "héllo — ünïcode ✓"),
            mapOf("type" to "done", "stopReason" to "end_turn"),
        )
        val text = lines.joinToString("\n") { Json.stringify(it) } + "\n"
        for (size in listOf(1, 2, 3, 7, 13, text.length)) {
            val d = NdjsonDecoder()
            val out = ArrayList<Any?>()
            var i = 0
            while (i < text.length) {
                out.addAll(d.push(text.substring(i, minOf(text.length, i + size))))
                i += size
            }
            out.addAll(d.end())
            assertJson(lines, out, "chunk size $size")
        }
        // A final line without a newline and a CRLF line.
        val d = NdjsonDecoder()
        assertJson(listOf(mapOf("a" to 1)), d.push("{\"a\":1}\r\n{\"b\""))
        assertJson(emptyList<Any?>(), d.push(":2}"))
        assertJson(listOf(mapOf("b" to 2)), d.end())
        // Unknown lines are dropped; known ones classified.
        assertEquals(null, classifyLine(mapOf("type" to "bogus")))
        assertEquals(AgentStreamLine.Status("tool", "search"), classifyLine(mapOf("type" to "status", "state" to "tool", "tool" to "search")))
    }

    @Test
    fun aConversationStreamsATurnFromAFakeAgent() {
        val id = BASIC_CATALOG.id
        val body = listOf(
            "{\"type\":\"conversation\",\"conversationId\":\"conv-1\"}\n{\"version\":\"v0.9.1\",\"createSurface\":{\"surfaceId\":\"s\",\"catalogId\":\"$id\",\"sendDataModel\":true}}\n",
            "{\"version\":\"v0.9.1\",\"updateComponents\":{\"surfaceId\":\"s\",\"components\":[{\"id\":\"root\",\"component\":\"Text\",\"text\":{\"path\":\"/greeting\"}}]}}\n{\"version\":\"v0.9",
            ".1\",\"updateDataModel\":{\"surfaceId\":\"s\",\"path\":\"/greeting\",\"value\":\"Hello\"}}\n{\"type\":\"text\",\"text\":\"Here you go\"}\n{\"type\":\"done\",\"stopReason\":\"end_turn\"}\n",
        )
        platform.streamScript = { StreamScript(body) }
        val conv = A2UIConversation(endpoint = AgentEndpoint("http://agent.test/", "shop", "assistant"))
        val events = ArrayList<String>()
        conv.on { e -> events.add(e::class.simpleName!!) }
        val turn = conv.send("hi")
        assertTrue(conv.busy)
        platform.drain()
        assertEquals("conv-1", runBlocking { turn.conversationId.await() })
        assertEquals(A2UITurnResult("conv-1", "end_turn"), runBlocking { turn.done.await() })
        assertTrue(!conv.busy)
        assertEquals("http://agent.test/apps/shop/agent/assistant", platform.requests[0].url)
        assertEquals("POST", platform.requests[0].method)
        assertEquals("application/x-ndjson", platform.requests[0].headers["accept"])
        assertJson(mapOf("message" to "hi", "capabilities" to mapOf("supportedCatalogIds" to listOf(id))), Json.parse(platform.requests[0].body!!))
        assertEquals("Hello", obj(conv.dataModel("s"))["greeting"])
        assertEquals(listOf(A2UITranscriptEntry("user", "hi"), A2UITranscriptEntry("agent", "Here you go")), conv.transcript)
        assertTrue(events.containsAll(listOf("Done", "Text", "Conversation")))
        // The next turn carries the conversation id and the sendDataModel surface.
        platform.streamScript = { StreamScript(listOf("{\"type\":\"done\",\"stopReason\":\"end_turn\"}")) }
        val second = conv.sendAction(mapOf("name" to "x", "surfaceId" to "s", "sourceComponentId" to "root", "timestamp" to isoTimestamp(), "context" to emptyMap<String, Any?>()))
        platform.drain()
        assertEquals("end_turn", runBlocking { second.done.await() }.stopReason)
        val sent = obj(Json.parse(platform.requests[1].body!!))
        assertEquals("conv-1", sent["conversationId"])
        assertEquals("x", obj(sent["action"])["name"])
        assertJson(mapOf("version" to "v0.9.1", "surfaces" to mapOf("s" to mapOf("greeting" to "Hello"))), sent["dataModel"])
        // Turns queue: the second waits for the first.
        platform.streamScript = { StreamScript(listOf("{\"type\":\"done\",\"stopReason\":\"end_turn\"}\n")) }
        val a = conv.send("one")
        val b = conv.send("two")
        assertEquals(3, platform.requests.size)
        platform.drain()
        assertEquals(4, platform.requests.size)
        assertTrue(a.done.isCompleted && b.done.isCompleted)
        // A transport failure ends the turn with an error.
        platform.streamScript = { StreamScript(emptyList(), error = "HTTP status 500") }
        val failed = conv.send("again")
        platform.drain()
        assertEquals("error", runBlocking { failed.done.await() }.stopReason)
        // Without an endpoint a turn fails at once.
        assertEquals("error", runBlocking { A2UIConversation().send("x").done.await() }.stopReason)
    }

    @Test
    fun a2uiSurfaceWidgetStaticMessagesEventsAndTheAgentHostApis() {
        val messages = obj(A2UIFiles.readJson("spec", "catalogs", "basic", "examples", "00_interactive-button.json"))["messages"]
        val got = ArrayList<Any?>()
        val (surface, _) = renderOnSurface(
            linkedMapOf(
                "type" to "A2UISurface",
                "key" to "w",
                "props" to linkedMapOf("messages" to messages),
                "events" to linkedMapOf("a2uiAction" to { e: dev.elpian.core.events.ElpianEvent -> got.add(e.value) }),
            ),
        )
        val reg = a2uiRegistry(surface.engine.services)
        val key = reg.keys().single()
        assertTrue(key.startsWith("static:"), key)
        val conv = reg.get(key)!!
        assertEquals(1, conv.processor.surfaces.size)
        val s = conv.processor.surfaces[0]
        val button = s.components.values.first { it["component"] == "Button" }
        conv.processor.dispatchAction(s.id, button["id"].toString(), button["action"])
        assertEquals(1, got.size)
        assertEquals(button["id"], obj(got[0])["sourceComponentId"])
        // Host APIs share the registry.
        val handler = HostHandler(surface.engine.services)
        fun call(api: String, payload: String): JsonMap = obj(Json.parse(runBlocking { (handler.handleHostCallReply(api, payload) as HostReply.Later).value.await() }))
        val model = call("a2ui.dataModel", Json.stringify(mapOf("conversation" to key, "surfaceId" to s.id)))
        assertTrue(model["type"] == "object" || model["type"] == "null")
        assertEquals("null", call("a2ui.dataModel", "{}")["type"])
        // Without defaults there is no endpoint.
        assertContains(Json.stringify(call("agent.send", """{"agent": "assistant", "message": "hi"}""")), "no agent endpoint")
        reg.defaults = A2UIDefaults(baseUrl = "http://agent.test", appId = "shop")
        platform.streamScript = { StreamScript(listOf("{\"type\":\"conversation\",\"conversationId\":\"c9\"}\n{\"type\":\"done\",\"stopReason\":\"end_turn\"}\n")) }
        // The guest SDK's shape: askHost(name, [{...}]).
        val reply = handler.handleHostCallReply("agent.send", """[{"agent": "assistant", "message": "hello"}]""") as HostReply.Later
        platform.drain()
        val sent = obj(Json.parse(runBlocking { reply.value.await() }))
        assertJson(mapOf("conversationId" to "c9", "conversation" to "agent:assistant"), obj(sent["data"])["value"])
        assertEquals("http://agent.test/apps/shop/agent/assistant", platform.requests.last().url)
        // agent.action fills timestamp and context.
        platform.streamScript = { StreamScript(listOf("{\"type\":\"done\",\"stopReason\":\"end_turn\"}\n")) }
        val acted = handler.handleHostCallReply("agent.action", """{"agent": "assistant", "action": {"name": "buy", "surfaceId": "s"}}""") as HostReply.Later
        platform.drain()
        assertEquals("object", obj(Json.parse(runBlocking { acted.value.await() }))["type"])
        val action = obj(obj(Json.parse(platform.requests.last().body!!))["action"])
        assertEquals("buy", action["name"])
        assertTrue(action["timestamp"] is String)
        assertJson(emptyMap<String, Any?>(), action["context"])
        assertContains(Json.stringify(call("agent.action", """{"agent": "assistant", "action": {}}""")), "requires an \\\"action\\\"")
        // A policy refusal answers null.
        val refusing = HostHandler(surface.engine.services, dev.elpian.core.host.HostHandlerOptions(onAuthorize = { false }))
        assertEquals(dev.elpian.core.util.Typed.NULL, (refusing.handleHostCallReply("agent.send", "{}") as HostReply.Now).value)
        surface.dispose()
    }

    @Test
    fun reconcilerRemovingAKeyedMiddleChildKeepsTheBottomRunIntact() {
        // Regression: the bottom run was reconciled against the old middle's objects
        // (the A2UI chat row collapsed to 0x0 when the busy indicator went away).
        val surface = dev.elpian.core.session.ElpianSurface("reconcile")
        fun view(busy: Boolean): JsonMap {
            val children = ArrayList<Any?>()
            children.add(mapOf("type" to "Text", "key" to "a", "props" to mapOf("text" to "a")))
            if (busy) children.add(mapOf("type" to "LinearProgressIndicator", "key" to "busy"))
            children.add(mapOf("type" to "Text", "key" to "b", "props" to mapOf("text" to "b")))
            children.add(
                mapOf(
                    "type" to "Row",
                    "key" to "chat",
                    "children" to listOf(mapOf("type" to "Expanded", "children" to listOf(mapOf("type" to "TextField", "key" to "in", "props" to mapOf("hint" to "x"))))),
                ),
            )
            return linkedMapOf("type" to "Column", "children" to children)
        }
        for (busy in listOf(false, true, false)) {
            surface.setContent(view(busy))
            surface.renderNow()
            surface.owner.flush(0.0)
        }
        var input: dev.elpian.core.render.RenderObject? = null
        surface.owner.root!!.visit { if (it.type == "control" && it.props["kind"] == "textInput") input = it }
        val size = assertNotNull(input).size
        assertTrue(size.width > 0 && size.height > 0, size.toString())
        surface.dispose()
    }

    @Test
    fun a2uiSurfaceWidgetSendsItsPromptAndRendersTheAgentsSurface() {
        val (surface, _) = renderOnSurface(linkedMapOf("type" to "Text", "props" to linkedMapOf("text" to "boot")))
        val reg = a2uiRegistry(surface.engine.services)
        reg.defaults = A2UIDefaults(baseUrl = "http://agent.test", appId = "shop")
        val id = BASIC_CATALOG.id
        platform.streamScript = {
            StreamScript(
                listOf(
                    "{\"type\":\"conversation\",\"conversationId\":\"c1\"}\n",
                    "{\"version\":\"v0.9.1\",\"createSurface\":{\"surfaceId\":\"s\",\"catalogId\":\"$id\"}}\n",
                    "{\"version\":\"v0.9.1\",\"updateComponents\":{\"surfaceId\":\"s\",\"components\":[{\"id\":\"root\",\"component\":\"Text\",\"text\":\"Agent says hi\"}]}}\n",
                    "{\"type\":\"text\",\"text\":\"prose\"}\n{\"type\":\"done\",\"stopReason\":\"end_turn\"}\n",
                ),
            )
        }
        surface.setContent(linkedMapOf("type" to "A2UISurface", "key" to "w", "props" to linkedMapOf("agent" to "assistant", "prompt" to "start", "showText" to true, "chat" to true)))
        surface.renderNow()
        platform.drain()
        assertEquals(1, platform.requests.size)
        assertEquals("start", obj(Json.parse(platform.requests[0].body!!))["message"])
        val conv = reg.get("agent:assistant")!!
        assertTrue(conv.processor.surface("s")!!.isReady)
        // The prompt is sent once.
        surface.renderNow()
        platform.drain()
        assertEquals(1, platform.requests.size)
        val tree = a2uiSurfaceTree(surface.engine, mapOf("agent" to "assistant", "showText" to true, "chat" to true), "w")
        assertNotNull(findNode(tree) { it["type"] == "Text" && it.nodeProps()["text"] == "Agent says hi" })
        assertNotNull(findNode(tree) { it["type"] == "Text" && it.nodeProps()["text"] == "prose" })
        assertNotNull(findNode(tree) { it["key"] == "w/chat/send" })
        surface.dispose()
    }
}
