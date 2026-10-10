package dev.elpian.core.a2ui

import dev.elpian.core.util.Json
import dev.elpian.core.util.JsonMap
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * The vendored A2UI conformance suites (a2ui/conformance/json) against the
 * renderer — the same cases, translation and skips as
 * native/web/test/a2ui/conformance.test.mjs.
 *
 * Cases written for protocol v1.0 (inline `createSurface.dataModel/components`,
 * `@call` / `@path`, `title`, `checked`, `selectedIndex`, `Container`) are
 * translated to their v0.9.1 equivalents first ([fromV1]). Skipped:
 * node_resolution (fixtures not vendored; asserts web_core's reactive-node
 * model) and cases with inline custom catalogs.
 */
@Suppress("UNCHECKED_CAST")
class ConformanceTest {
    private val skipped = ArrayList<String>()
    private var passed = 0

    @BeforeTest
    fun setUp() {
        A2UITestPlatform.install()
    }

    @AfterTest
    fun report() {
        println("A2UI conformance: $passed cases passed, ${skipped.size} skipped")
        for (s in skipped) println("  skipped $s")
    }

    private fun obj(v: Any?): JsonMap = v as JsonMap

    private fun expectError(expected: Map<*, *>, where: String, fn: () -> Unit) {
        val error = try {
            fn()
            null
        } catch (e: Exception) {
            e
        }
        assertNotNull(error, "$where: expected ${expected["category"]} error")
        assertTrue(error is A2UIError, "$where: not an A2UIError: $error")
        (expected["category"] as? String)?.let { assertEquals(it, error.category, where) }
        (expected["message"] as? String)?.let { assertContains(error.message, it, where) }
    }

    // -------------------------------------------------------------------------
    // v1.0 → v0.9.1 translation
    // -------------------------------------------------------------------------

    private fun renameKeys(v: Any?): Any? = when (v) {
        is List<*> -> v.map { renameKeys(it) }
        is Map<*, *> -> LinkedHashMap<String, Any?>().also { out ->
            for ((k, x) in v) out[if (k == "@call") "call" else if (k == "@path") "path" else k.toString()] = renameKeys(x)
        }
        else -> v
    }

    private fun fromV1(messages: List<Any?>): List<Any?> {
        val out = ArrayList<Any?>()
        for (raw in messages) {
            val m = renameKeys(raw) as JsonMap
            val cs0 = m["createSurface"] as? JsonMap
            if (cs0 != null) {
                val cs = LinkedHashMap(cs0)
                val hasData = cs.containsKey("dataModel")
                val dataModel = cs.remove("dataModel")
                val components = cs.remove("components")
                if (cs["catalogId"] == "basic") cs["catalogId"] = BASIC_CATALOG_ID
                out.add(linkedMapOf("version" to "v0.9.1", "createSurface" to cs))
                if (hasData) out.add(linkedMapOf("version" to "v0.9.1", "updateDataModel" to linkedMapOf("surfaceId" to cs["surfaceId"], "path" to "/", "value" to dataModel)))
                if (components != null) out.add(linkedMapOf("version" to "v0.9.1", "updateComponents" to linkedMapOf("surfaceId" to cs["surfaceId"], "components" to components)))
            } else {
                val rest = LinkedHashMap<String, Any?>()
                rest["version"] = "v0.9.1"
                for ((k, v) in m) if (k != "version") rest[k] = v
                out.add(rest)
            }
        }
        return out
    }

    private fun payloads(c: JsonMap): List<Any?> = (c["steps"] as List<*>).flatMap { (it as Map<*, *>)["payload"] as List<*> }

    // -------------------------------------------------------------------------

    @Test
    fun dataModel() {
        for (c in A2UIFiles.conformance("data_model")) {
            val name = c["name"].toString()
            val model = DataModel(c["initial"] ?: LinkedHashMap<String, Any?>())
            val notified = ArrayList<String>()
            for (path in (c["watch"] as? List<*>) ?: emptyList<Any?>()) model.watch(path.toString()) { _, _ -> notified.add(path.toString()) }
            for (s in c["steps"] as List<*>) {
                val step = obj(s)
                notified.clear()
                val where = "$name ${Json.stringify(step)}"
                val path = step["path"]?.toString() ?: "/"
                val expectedError = step["expect_error"] as? Map<*, *>
                if (expectedError != null) {
                    expectError(expectedError, where) {
                        when (step["op"]) {
                            "get" -> model.get(path)
                            "delete" -> model.delete(path)
                            else -> model.set(path, step["value"])
                        }
                    }
                    continue
                }
                when (step["op"]) {
                    "get" -> {
                        val v = model.get(path)
                        if (step.containsKey("expect")) assertJson(step["expect"], v, where)
                        if (step["expect_absent"] == true) assertEquals(null, v, where)
                        if (step["expect_type"] == "list") assertTrue(v is List<*>, where)
                        if (step["expect_type"] == "object") assertTrue(v is Map<*, *>, where)
                    }
                    "set" -> model.set(path, step["value"])
                    "delete" -> model.delete(path)
                    "dispose" -> model.dispose()
                    else -> fail("unknown op ${step["op"]}")
                }
                (step["expect_notified"] as? List<*>)?.let { assertEquals(it.map { p -> p.toString() }.sorted(), notified.sorted(), where) }
                (step["expect_values"] as? Map<*, *>)?.forEach { (p, v) -> assertJson(v, model.get(p.toString()), where) }
            }
            passed++
        }
    }

    @Test
    fun dataContext() {
        for (c in A2UIFiles.conformance("data_context")) {
            assertEquals("resolve_path", c["action"])
            val args = obj(c["args"])
            assertEquals(c["expect"], resolvePath(args["path"].toString(), args["contextPath"] as? String), c["name"].toString())
            passed++
        }
    }

    private fun rootText(messages: List<Any?>): String {
        val p = A2UIProcessor(A2UIProcessorOptions(validation = "strict"))
        val errors = p.processAll(messages)
        assertEquals(emptyList(), errors.map { it.message })
        val s = p.surfaces[0]
        return s.context().string(s.components["root"]!!["text"])
    }

    @Test
    fun expressions() {
        for (c in A2UIFiles.conformance("expressions")) {
            val name = c["name"].toString()
            when (c["action"]) {
                "parse_expression_template" -> {
                    val err = c["expect_error"] as? Map<*, *>
                    if (err != null) expectError(err, name) { parseTemplate(c["input"].toString()) }
                    else assertJson(c["expect"], parseTemplate(c["input"].toString()), name)
                }
                "validate" -> {
                    val messages = fromV1(payloads(c))
                    val expected = (c["steps"] as List<*>).firstNotNullOfOrNull { (it as Map<*, *>)["expectError"] } as? Map<*, *>
                    if (expected != null) {
                        val issues = messages.flatMap { validateMessage(it, BASIC_CATALOG) }
                        assertTrue(
                            issues.any { it.category == expected["category"] && it.message.contains(expected["message"].toString()) },
                            "$name: ${issues.map { it.message }}",
                        )
                    } else {
                        val expect = obj(obj(obj(obj(obj(c["expect"])["surfaces"])["main"])["components"])["root"])
                        assertEquals(expect["text"], rootText(messages), name)
                    }
                }
                else -> fail("unexpected action ${c["action"]}")
            }
            passed++
        }
    }

    @Test
    fun dataDeletion() {
        for (c in A2UIFiles.conformance("data_deletion")) {
            val name = c["name"].toString()
            val p = A2UIProcessor(A2UIProcessorOptions(validation = "strict"))
            assertEquals(emptyList(), p.processAll(fromV1(payloads(c))).map { it.message }, name)
            for ((sid, exp) in obj(obj(c["expect"])["surfaces"])) assertJson(obj(exp)["dataModel"], p.dataModel(sid), name)
            passed++
        }
    }

    @Test
    fun actions() {
        for (c in A2UIFiles.conformance("actions")) {
            val name = c["name"].toString()
            val p = A2UIProcessor()
            val sid = c["surfaceId"] as? String ?: "main"
            p.process(linkedMapOf("version" to "v0.9.1", "createSurface" to linkedMapOf("surfaceId" to sid, "catalogId" to BASIC_CATALOG_ID)))
            if (c["dataModel"] != null) p.process(linkedMapOf("version" to "v0.9.1", "updateDataModel" to linkedMapOf("surfaceId" to sid, "path" to "/", "value" to c["dataModel"])))
            val emitted = ArrayList<A2UIClientAction>()
            p.on { e -> if (e is A2UIProcessorEvent.Action) emitted.add(e.action) }
            val action = assertNotNull(p.dispatchAction(sid, "btn", c["actionPayload"], c["scope"] as? String ?: "/"), name)
            assertEquals(1, emitted.size)
            assertEquals(sid, action.surfaceId)
            assertEquals("btn", action.sourceComponentId)
            java.time.Instant.parse(action.timestamp)
            val exp = obj(c["expectDispatched"])
            assertEquals(exp["name"], action.name, name)
            assertJson(exp["context"] ?: LinkedHashMap<String, Any?>(), action.context, name)
            (exp["userMessage"] as? String)?.let { assertEquals(it, action.userMessage) }
            passed++
        }
    }

    /** The v1.0 `surface` shorthand → v0.9.1 components. */
    private fun a11yComponents(surface: JsonMap): List<JsonMap> {
        val comps = ArrayList<JsonMap>()
        fun conv(id: String, c: JsonMap) {
            val out = linkedMapOf<String, Any?>("id" to id)
            out.putAll(renameKeys(c) as JsonMap)
            out["id"] = id
            out.remove("components")
            if (out["component"] == "Container") {
                out["component"] = "Column"
                out["children"] = if (out["child"] != null) listOf(out["child"]) else emptyList<Any?>()
                out.remove("child")
            }
            if (out["component"] == "Button" && out["title"] is String) {
                comps.add(linkedMapOf("id" to "${id}__label", "component" to "Text", "text" to out["title"]))
                out["child"] = "${id}__label"
                out["action"] = linkedMapOf("event" to linkedMapOf("name" to "press"))
                out.remove("title")
            }
            if (out["component"] == "CheckBox" && out.containsKey("checked")) {
                out["value"] = out.remove("checked")
            }
            if (out["component"] == "ChoicePicker" && out.containsKey("selectedIndex")) {
                val i = (out.remove("selectedIndex") as Number).toInt()
                out["value"] = listOf(obj((out["options"] as List<*>)[i])["value"])
            }
            comps.add(out)
        }
        conv(surface["id"].toString(), surface)
        (surface["components"] as? Map<*, *>)?.forEach { (id, c) -> conv(id.toString(), obj(c)) }
        return comps
    }

    @Test
    fun accessibility() {
        for (c in A2UIFiles.conformance("accessibility")) {
            val name = c["name"].toString()
            val p = A2UIProcessor(A2UIProcessorOptions(validation = "off"))
            p.process(linkedMapOf("version" to "v0.9.1", "createSurface" to linkedMapOf("surfaceId" to "s", "catalogId" to BASIC_CATALOG_ID)))
            p.process(linkedMapOf("version" to "v0.9.1", "updateComponents" to linkedMapOf("surfaceId" to "s", "components" to a11yComponents(obj(c["surface"])))))
            val s = p.surface("s")!!
            for ((id, exp) in obj(obj(c["assertions"])["accessibilityTree"])) {
                val node = describeAccessibility(s, s.components[id]!!)
                val json = node.toJson()
                for ((k, v) in obj(exp)) {
                    if (v is Map<*, *> && v.containsKey("path")) assertEquals(v["path"], node.bindings?.get(k), "$name $id.$k")
                    else assertJson(v, json[k], "$name $id.$k")
                }
            }
            passed++
        }
    }

    private fun dotted(path: String?): String = "messages" + (path ?: "/").split('/').filter { it.isNotEmpty() }.joinToString("") { ".$it" }

    private fun checkExpected(issues: List<A2UIError>, expected: Any?, where: String) {
        assertTrue(issues.isNotEmpty(), "$where: expected an error")
        if (expected is String) {
            assertTrue(issues.any { it.message.contains(expected) }, "$where: ${issues.joinToString(" | ") { it.message }} should mention \"$expected\"")
            return
        }
        val e = obj(expected)
        (e["category"] as? String)?.let { cat -> assertTrue(issues.all { it.category == cat }, where) }
        (e["message"] as? String)?.let { m -> assertTrue(issues.any { it.message.contains(m) }, "$where: ${issues.joinToString(" | ") { it.message }}") }
        for (d in (e["details"] as? List<*>) ?: emptyList<Any?>()) {
            val detail = obj(d)
            assertTrue(
                issues.any { dotted(it.path) == detail["path"] && it.details.issue == detail["code"] },
                "$where: no issue at ${detail["path"]} (${detail["code"]}); got ${issues.joinToString(", ") { "${dotted(it.path)} ${it.details.issue}" }}",
            )
        }
    }

    @Test
    fun validatorV09() {
        for (c in A2UIFiles.conformance("validator_v0_9")) {
            val name = c["name"].toString()
            if (c["catalog"] != null) {
                skipped.add("$name: inline custom catalog (only the basic catalog is built in)")
                continue
            }
            val v = A2UIValidator(BASIC_CATALOG, strict = c["strictMode"] == true, requireVersion = true)
            (c["steps"] as List<*>).forEachIndexed { i, s ->
                val step = obj(s)
                val issues = v.validateBatch(step["messages"] as List<Any?>)
                if (step["expectError"] != null) checkExpected(issues, step["expectError"], "$name step $i")
                else assertEquals(emptyList(), issues.map { it.message }, "$name step $i")
            }
            if (c["expectError"] != null) fail("$name: case-level expectError not handled")
            passed++
        }
    }

    @Test
    fun compositionConstraints() {
        for (c in A2UIFiles.conformance("composition_constraints")) {
            val name = c["name"].toString()
            if ((c["catalog"] as? Map<*, *>)?.get("catalogSchema") != null) {
                skipped.add("$name: v1.0 allowedParents/allowedChildren on an inline custom catalog")
                continue
            }
            val p = A2UIProcessor(A2UIProcessorOptions(validation = "strict"))
            assertEquals(emptyList(), p.processAll(fromV1(payloads(c))).map { it.message }, name)
            val v = A2UIValidator(BASIC_CATALOG, strict = true)
            assertEquals(emptyList(), v.validateBatch(fromV1(payloads(c))).map { it.message }, name)
            for ((sid, exp) in obj(obj(c["expect"])["surfaces"])) {
                for ((id, comp) in obj(obj(exp)["components"])) {
                    val actual = LinkedHashMap(p.surface(sid)!!.components[id]!!).also { it.remove("id") }
                    val expected = LinkedHashMap(obj(comp)).also { it.remove("id") }
                    assertJson(expected, actual, "$name $id")
                }
            }
            passed++
        }
    }

    @Test
    fun nodeResolution() {
        for (c in A2UIFiles.conformance("node_resolution")) skipped.add("${c["name"]}: fixtures (test_data/node/*.yaml) are not vendored; asserts web_core reactive-node identity")
    }
}
