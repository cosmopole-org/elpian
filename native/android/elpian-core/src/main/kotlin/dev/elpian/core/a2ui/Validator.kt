package dev.elpian.core.a2ui

import dev.elpian.core.util.Json

/**
 * Client-side validation of server-to-client messages (a2ui/validator.ts).
 *
 * - [validateMessage] checks one message against the envelope schema and the
 *   catalog's component / function tables (types, enums, required and unknown
 *   properties, binding path syntax, function-call nesting, `formatString`
 *   templates, data nesting).
 * - [A2UIValidator] validates batches statefully and, in strict mode, also
 *   checks the component graph each batch leaves behind: a `root` exists,
 *   no duplicate ids in one message, no self references, dangling
 *   references or cycles, every component is reachable from `root`, and the
 *   tree is at most [MAX_NESTING] deep.
 *
 * Issues are [A2UIError]s of category `ValidationError` whose `path` is a
 * JSON Pointer into the message (the protocol's `VALIDATION_FAILED` shape).
 */
val SUPPORTED_VERSIONS: List<String> = listOf("v0.9", "v0.9.1")
val MESSAGE_KINDS: List<String> = listOf("createSurface", "updateComponents", "updateDataModel", "deleteSurface")

/** Deepest component tree / data value accepted. */
const val MAX_NESTING = 50

/** Deepest nesting of function calls inside one dynamic value. */
const val MAX_CALL_DEPTH = 5

private val HEX_COLOR = Regex("^#[0-9a-fA-F]{6}$")
private val RETURN_TYPES = listOf("string", "number", "boolean", "array", "object", "any", "void")

@Suppress("UNCHECKED_CAST")
private fun obj(v: Any?): Map<String, Any?>? = if (v is Map<*, *>) v as Map<String, Any?> else null

private class Issues(val surfaceId: String?) {
    val list = ArrayList<A2UIError>()

    fun add(path: String, issue: String, message: String) {
        list.add(A2UIError("ValidationError", message, A2UIErrorDetails(surfaceId, path.ifEmpty { "/" }, issue)))
    }
}

/** The message kind ([MESSAGE_KINDS]) of [msg], or null. */
fun messageKind(msg: Any?): String? {
    val m = obj(msg) ?: return null
    for (k in MESSAGE_KINDS) if (m.containsKey(k)) return k
    return null
}

/** The surface a message addresses, when it names one. */
fun messageSurfaceId(msg: Any?): String? {
    val kind = messageKind(msg) ?: return null
    return obj(obj(msg)!![kind])?.get("surfaceId") as? String
}

/** Schema-level validation of one server-to-client message. */
fun validateMessage(msg: Any?, catalog: A2UICatalog, requireVersion: Boolean? = null): List<A2UIError> {
    val issues = Issues(messageSurfaceId(msg))
    val m = obj(msg)
    if (m == null) {
        issues.add("/", "type_mismatch", "A message must be a JSON object")
        return issues.list
    }
    if (!m.containsKey("version")) {
        if (requireVersion != false) issues.add("/version", "missing_field", "The \"version\" field is required")
    } else if (m["version"] !is String || m["version"] !in SUPPORTED_VERSIONS) {
        issues.add("/version", "invalid_value", "Unsupported version ${Json.stringify(m["version"])} (expected v0.9 or v0.9.1)")
    }
    val kinds = MESSAGE_KINDS.filter { m.containsKey(it) }
    if (kinds.size != 1) {
        issues.add("/", if (kinds.isNotEmpty()) "invalid_value" else "missing_field", "A message must contain exactly one of ${MESSAGE_KINDS.joinToString(", ")}")
        return issues.list
    }
    for (k in m.keys) if (k != "version" && k != kinds[0]) issues.add("/$k", "unknown_field", "Unknown message field \"$k\"")
    val kind = kinds[0]
    val base = "/$kind"
    val body = obj(m[kind])
    if (body == null) {
        issues.add(base, "type_mismatch", "\"$kind\" must be an object")
        return issues.list
    }
    val allowed = when (kind) {
        "createSurface" -> listOf("surfaceId", "catalogId", "theme", "sendDataModel")
        "updateComponents" -> listOf("surfaceId", "components")
        "updateDataModel" -> listOf("surfaceId", "path", "value")
        else -> listOf("surfaceId")
    }
    for (k in body.keys) if (k !in allowed) issues.add("$base/$k", "unknown_field", "Unknown field \"$k\" in $kind")
    requireString(issues, body, "surfaceId", base)
    when (kind) {
        "createSurface" -> {
            requireString(issues, body, "catalogId", base)
            if (body.containsKey("theme")) validateTheme(issues, body["theme"], "$base/theme")
            if (body.containsKey("sendDataModel") && body["sendDataModel"] !is Boolean) issues.add("$base/sendDataModel", "type_mismatch", "\"sendDataModel\" must be a boolean")
        }
        "updateComponents" -> {
            val components = body["components"]
            if (!body.containsKey("components")) issues.add("$base/components", "missing_field", "\"components\" is required")
            else if (components !is List<*>) issues.add("$base/components", "type_mismatch", "\"components\" must be a list")
            else {
                if (components.isEmpty()) issues.add("$base/components", "invalid_value", "\"components\" must not be empty")
                components.forEachIndexed { i, c -> validateComponent(issues, c, catalog, "$base/components/$i") }
            }
        }
        "updateDataModel" -> {
            if (body.containsKey("path")) {
                val p = body["path"]
                if (p !is String) issues.add("$base/path", "type_mismatch", "\"path\" must be a string")
                else if (!isValidPointerSyntax(p)) issues.add("$base/path", "invalid_value", "Invalid path syntax: \"$p\"")
            }
            if (body.containsKey("value") && depthOf(body["value"]) > MAX_NESTING) {
                issues.add("$base/value", "limit", "Global recursion limit exceeded: the value nests deeper than $MAX_NESTING levels")
            }
        }
    }
    return issues.list
}

private fun requireString(issues: Issues, body: Map<String, Any?>, key: String, base: String) {
    if (!body.containsKey(key)) issues.add("$base/$key", "missing_field", "\"$key\" is required")
    else if (body[key] !is String) issues.add("$base/$key", "type_mismatch", "\"$key\" must be a string")
}

private fun validateTheme(issues: Issues, theme: Any?, path: String) {
    val t = obj(theme)
    if (t == null) {
        issues.add(path, "type_mismatch", "\"theme\" must be an object")
        return
    }
    if (t.containsKey("primaryColor")) {
        val c = t["primaryColor"]
        if (c !is String || !HEX_COLOR.matches(c)) issues.add("$path/primaryColor", "invalid_value", "\"primaryColor\" must be a hex color like #00BFFF")
    }
    for (k in listOf("iconUrl", "agentDisplayName")) {
        if (t.containsKey(k) && t[k] !is String) issues.add("$path/$k", "type_mismatch", "\"$k\" must be a string")
    }
}

private fun depthOf(value: Any?): Int {
    val children: Collection<Any?> = when (value) {
        is List<*> -> value
        is Map<*, *> -> value.values
        else -> return 0
    }
    var max = 0
    for (v in children) max = maxOf(max, depthOf(v))
    return max + 1
}

/** Validate one component definition against [catalog]. */
private fun validateComponent(issues: Issues, component: Any?, catalog: A2UICatalog, base: String) {
    val c = obj(component)
    if (c == null) {
        issues.add(base, "type_mismatch", "A component must be an object")
        return
    }
    requireString(issues, c, "id", base)
    if (!c.containsKey("component")) {
        issues.add("$base/component", "missing_field", "\"component\" is required")
        return
    }
    val type = c["component"]
    if (type !is String) {
        issues.add("$base/component", "type_mismatch", "\"component\" must be a string")
        return
    }
    val spec = catalog.components[type]
    if (spec == null) {
        issues.add("$base/component", "invalid_value", "Unknown component type \"$type\"")
        return
    }
    for ((k, v) in c) {
        if (k == "id" || k == "component") continue
        val ps = spec.props[k] ?: COMMON_PROPS[k]
        if (ps == null) {
            issues.add("$base/$k", "unknown_field", "Unknown property \"$k\" on $type")
            continue
        }
        checkKind(issues, v, ps.kind, "$base/$k", catalog)
        if (ps.enum != null && v is String && v !in ps.enum) issues.add("$base/$k", "invalid_value", "\"$k\" must be one of ${ps.enum.joinToString(", ")}")
    }
    for (r in spec.required) if (!c.containsKey(r)) issues.add("$base/$r", "missing_field", "$type requires \"$r\"")
}

private fun isBindingShape(v: Any?): Boolean = v is Map<*, *> && v.containsKey("path") && v.size == 1

private fun checkBinding(issues: Issues, v: Map<*, *>, path: String) {
    val p = v["path"]
    if (p !is String) issues.add("$path/path", "type_mismatch", "A binding \"path\" must be a string")
    else if (!isValidPointerSyntax(p)) issues.add("$path/path", "invalid_value", "Invalid path syntax: \"$p\"")
}

private fun checkKind(issues: Issues, v: Any?, kind: String, path: String, catalog: A2UICatalog) {
    fun dynamic(literal: (Any?) -> Boolean, what: String) {
        if (literal(v)) return
        if (isBindingShape(v)) return checkBinding(issues, v as Map<*, *>, path)
        if (v is Map<*, *> && v.containsKey("call")) return checkCall(issues, obj(v)!!, path, catalog)
        issues.add(path, "type_mismatch", "Expected $what, a {\"path\"} binding or a function call")
    }
    when (kind) {
        "any" -> {
            if (isBindingShape(v)) checkBinding(issues, v as Map<*, *>, path)
            else if (v is Map<*, *> && v.containsKey("call")) checkCall(issues, obj(v)!!, path, catalog)
        }
        "DynamicString" -> dynamic({ it is String }, "a string")
        "DynamicNumber" -> dynamic({ it is Number }, "a number")
        "DynamicBoolean" -> dynamic({ it is Boolean }, "a boolean")
        "DynamicStringList" -> dynamic({ it is List<*> && it.all { s -> s is String } }, "a list of strings")
        "DynamicValue" -> dynamic({ it is String || it is Number || it is Boolean || it is List<*> }, "a value")
        "DynamicBooleanList" -> {
            if (v !is List<*>) return issues.add(path, "type_mismatch", "Expected a list")
            if (v.size < 2) issues.add(path, "invalid_value", "Expected at least two values")
            v.forEachIndexed { i, x -> checkKind(issues, x, "DynamicBoolean", "$path/$i", catalog) }
        }
        "ComponentId" -> if (v !is String) issues.add(path, "type_mismatch", "Expected a component id (string)")
        "ChildList" -> {
            if (v is List<*>) {
                v.forEachIndexed { i, x -> if (x !is String) issues.add("$path/$i", "type_mismatch", "Expected a component id (string)") }
            } else if (v is Map<*, *>) {
                for (k in v.keys) if (k != "componentId" && k != "path") issues.add("$path/$k", "unknown_field", "Unknown template field \"$k\"")
                if (!v.containsKey("componentId")) issues.add("$path/componentId", "missing_field", "A child template requires \"componentId\"")
                else if (v["componentId"] !is String) issues.add("$path/componentId", "type_mismatch", "\"componentId\" must be a string")
                if (!v.containsKey("path")) issues.add("$path/path", "missing_field", "A child template requires \"path\"")
                else checkBinding(issues, v, path)
            } else issues.add(path, "invalid_value", "Expected a list of component ids or a {componentId, path} template")
        }
        "Action" -> {
            val a = obj(v)
            if (a != null && a.size == 1 && a["event"] is Map<*, *>) {
                val e = obj(a["event"])!!
                if (e["name"] !is String) issues.add("$path/event/name", if (!e.containsKey("name")) "missing_field" else "type_mismatch", "An event requires a \"name\" string")
                for (k in e.keys) if (k != "name" && k != "context") issues.add("$path/event/$k", "unknown_field", "Unknown event field \"$k\"")
                if (e.containsKey("context")) {
                    val ctx = obj(e["context"])
                    if (ctx == null) issues.add("$path/event/context", "type_mismatch", "An event \"context\" must be an object")
                    else for ((k, x) in ctx) checkKind(issues, x, "any", "$path/event/context/$k", catalog)
                }
            } else if (a != null && a.size == 1 && a["functionCall"] is Map<*, *>) {
                checkCall(issues, obj(a["functionCall"])!!, "$path/functionCall", catalog)
            } else issues.add(path, "invalid_value", "An action must be {\"event\": {\"name\", \"context\"}} or {\"functionCall\": {...}}")
        }
        "Checks" -> {
            if (v !is List<*>) return issues.add(path, "type_mismatch", "\"checks\" must be a list")
            v.forEachIndexed { i, item ->
                val p = "$path/$i"
                val check = obj(item)
                if (check == null) {
                    issues.add(p, "type_mismatch", "A check must be an object")
                    return@forEachIndexed
                }
                if (check["message"] !is String) issues.add("$p/message", if (!check.containsKey("message")) "missing_field" else "type_mismatch", "A check requires a \"message\" string")
                if (check.containsKey("condition")) checkKind(issues, check["condition"], "DynamicBoolean", "$p/condition", catalog)
                else if (check["call"] is String) checkCall(issues, linkedMapOf("call" to check["call"], "args" to (check["args"] ?: LinkedHashMap<String, Any?>())), p, catalog)
                else issues.add("$p/condition", "missing_field", "A check requires a \"condition\"")
            }
        }
        "Accessibility" -> {
            val a = obj(v) ?: return issues.add(path, "type_mismatch", "\"accessibility\" must be an object")
            for (k in listOf("label", "description")) if (a.containsKey(k)) checkKind(issues, a[k], "DynamicString", "$path/$k", catalog)
        }
        "IconName" -> {
            if (v is String) {
                if (v !in ICON_NAMES) issues.add(path, "invalid_value", "Unknown icon name \"$v\"")
            } else if (v is Map<*, *> && v.containsKey("svgPath")) {
                if (v["svgPath"] !is String || v.size != 1) issues.add(path, "invalid_value", "An icon must be {\"svgPath\": \"…\"}")
            } else if (isBindingShape(v)) checkBinding(issues, v as Map<*, *>, path)
            else issues.add(path, "type_mismatch", "Expected an icon name, {\"svgPath\"} or a binding")
        }
        "TabList" -> {
            if (v !is List<*> || v.isEmpty()) return issues.add(path, "invalid_value", "\"tabs\" must be a non-empty list")
            v.forEachIndexed { i, item ->
                val p = "$path/$i"
                val t = obj(item)
                if (t == null) {
                    issues.add(p, "type_mismatch", "A tab must be an object")
                    return@forEachIndexed
                }
                if (!t.containsKey("title")) issues.add("$p/title", "missing_field", "A tab requires \"title\"")
                else checkKind(issues, t["title"], "DynamicString", "$p/title", catalog)
                if (t["child"] !is String) issues.add("$p/child", if (!t.containsKey("child")) "missing_field" else "type_mismatch", "A tab requires a \"child\" id")
                for (k in t.keys) if (k != "title" && k != "child") issues.add("$p/$k", "unknown_field", "Unknown tab field \"$k\"")
            }
        }
        "OptionList" -> {
            if (v !is List<*>) return issues.add(path, "type_mismatch", "\"options\" must be a list")
            v.forEachIndexed { i, item ->
                val p = "$path/$i"
                val o = obj(item)
                if (o == null) {
                    issues.add(p, "type_mismatch", "An option must be an object")
                    return@forEachIndexed
                }
                if (!o.containsKey("label")) issues.add("$p/label", "missing_field", "An option requires \"label\"")
                else checkKind(issues, o["label"], "DynamicString", "$p/label", catalog)
                if (o["value"] !is String) issues.add("$p/value", if (!o.containsKey("value")) "missing_field" else "type_mismatch", "An option requires a \"value\" string")
            }
        }
        "string" -> if (v !is String) issues.add(path, "type_mismatch", "Expected a string")
        "number" -> if (v !is Number) issues.add(path, "type_mismatch", "Expected a number")
        "boolean" -> if (v !is Boolean) issues.add(path, "type_mismatch", "Expected a boolean")
    }
}

private fun callDepth(v: Any?): Int {
    if (v is List<*>) return v.maxOfOrNull { callDepth(it) }?.coerceAtLeast(0) ?: 0
    val m = obj(v) ?: return 0
    val args = obj(m["args"]) ?: emptyMap()
    val inner = args.values.maxOfOrNull { callDepth(it) }?.coerceAtLeast(0) ?: 0
    return if (m["call"] is String) inner + 1 else (m.values.maxOfOrNull { callDepth(it) }?.coerceAtLeast(0) ?: 0)
}

private fun checkCall(issues: Issues, v: Map<String, Any?>, path: String, catalog: A2UICatalog) {
    if (callDepth(v) > MAX_CALL_DEPTH) {
        issues.add(path, "limit", "functionCall depth exceeds the maximum of $MAX_CALL_DEPTH")
        return
    }
    val call = v["call"] as? String ?: return issues.add("$path/call", "type_mismatch", "\"call\" must be a function name")
    for (k in v.keys) if (k != "call" && k != "args" && k != "returnType") issues.add("$path/$k", "unknown_field", "Unknown function-call field \"$k\"")
    val spec = catalog.functions[call] ?: return issues.add("$path/call", "invalid_value", "Unknown function \"$call\"")
    if (v.containsKey("returnType") && v["returnType"] !in RETURN_TYPES) {
        issues.add("$path/returnType", "invalid_value", "Invalid returnType ${Json.stringify(v["returnType"])}")
    }
    val rawArgs = if (!v.containsKey("args")) LinkedHashMap<String, Any?>() else v["args"]
    val args = obj(rawArgs) ?: return issues.add("$path/args", "type_mismatch", "\"args\" must be an object")
    for ((k, x) in args) {
        val kind = spec.args[k]
        if (kind == null) {
            issues.add("$path/args/$k", "unknown_field", "$call() has no argument \"$k\"")
            continue
        }
        checkKind(issues, x, kind, "$path/args/$k", catalog)
    }
    for (r in spec.required) if (!args.containsKey(r)) issues.add("$path/args/$r", "missing_field", "$call() requires \"$r\"")
    val anyOf = spec.anyOf
    if (anyOf != null && !anyOf.any { group -> group.all { args.containsKey(it) } }) {
        issues.add("$path/args", "missing_field", "$call() requires one of ${anyOf.joinToString(" or ") { it.joinToString("+") }}")
    }
    val value = args["value"]
    if (call == "formatString" && value is String) {
        try {
            parseTemplate(value)
        } catch (e: Exception) {
            issues.add("$path/args/value", "invalid_value", e.message ?: e.toString())
        }
    }
}

/** A surface's component map as the validator tracks it. */
class SurfaceShape(val components: LinkedHashMap<String, Map<String, Any?>>)

/**
 * Stateful batch validation (the conformance `validate` action): each batch
 * is checked against the state the previous accepted batches left; a batch
 * with issues changes nothing.
 */
class A2UIValidator(
    val catalog: A2UICatalog,
    val strict: Boolean = false,
    val requireVersion: Boolean? = null,
) {
    private var surfaces = LinkedHashMap<String, SurfaceShape>()

    fun validateBatch(messages: List<Any?>): List<A2UIError> {
        val issues = ArrayList<A2UIError>()
        messages.forEachIndexed { i, m ->
            for (e in validateMessage(m, catalog, requireVersion)) {
                issues.add(A2UIError("ValidationError", e.message, e.details.copy(path = "/$i${if (e.path == "/") "" else e.path}")))
            }
        }
        if (issues.isNotEmpty()) return issues
        val next = LinkedHashMap<String, SurfaceShape>()
        for ((id, s) in surfaces) next[id] = SurfaceShape(LinkedHashMap(s.components))
        val touched = LinkedHashSet<String>()
        messages.forEachIndexed { i, m ->
            val kind = messageKind(m)!!
            val body = obj(obj(m)!![kind])!!
            val sid = body["surfaceId"].toString()
            fun fail(message: String, path: String = "/$i/$kind") {
                issues.add(A2UIError("ValidationError", message, A2UIErrorDetails(sid, path, "topology")))
            }
            when (kind) {
                "createSurface" -> if (next.containsKey(sid)) fail("Surface \"$sid\" already exists") else next[sid] = SurfaceShape(LinkedHashMap())
                "deleteSurface" -> next.remove(sid)
                "updateComponents" -> {
                    val s = next[sid]
                    if (s == null) {
                        fail("Surface \"$sid\" has not been created")
                        return@forEachIndexed
                    }
                    val seen = HashSet<String>()
                    (body["components"] as List<*>).forEachIndexed { j, raw ->
                        val c = obj(raw)!!
                        val id = c["id"].toString()
                        if (strict && id in seen) fail("Duplicate component ID \"$id\" in one updateComponents message", "/$i/updateComponents/components/$j/id")
                        seen.add(id)
                        s.components[id] = c
                    }
                    touched.add(sid)
                }
                "updateDataModel" -> if (!next.containsKey(sid)) fail("Surface \"$sid\" has not been created")
            }
        }
        if (strict) for (sid in touched) next[sid]?.let { issues.addAll(topology(sid, it)) }
        if (issues.isEmpty()) surfaces = next
        return issues
    }

    /** Graph checks for one surface's component map. */
    fun topology(surfaceId: String, surface: SurfaceShape): List<A2UIError> {
        val out = ArrayList<A2UIError>()
        fun fail(message: String, path: String = "/") {
            out.add(A2UIError("ValidationError", message, A2UIErrorDetails(surfaceId, path, "topology")))
        }
        val comps = surface.components
        if (comps.isEmpty()) return out
        if (!comps.containsKey("root")) {
            fail("Missing root component: surface \"$surfaceId\" has no component with id \"root\"")
            return out
        }
        for ((id, c) in comps) {
            for (ref in childReferences(c, catalog)) {
                if (ref.id == id) fail("Self-reference detected: component \"$id\" references itself (${ref.prop})")
                else if (!comps.containsKey(ref.id)) fail("Dangling reference: component \"$id\" references non-existent component '${ref.id}' (${ref.prop})")
            }
        }
        if (out.isNotEmpty()) return out
        val reached = LinkedHashSet<String>()
        val stack = ArrayList<String>()
        var cycle: List<String>? = null
        var tooDeep = false
        fun visit(id: String) {
            if (cycle != null || tooDeep) return
            if (id in stack) {
                cycle = stack.subList(stack.indexOf(id), stack.size).toList() + id
                return
            }
            if (stack.size + 1 > MAX_NESTING) {
                tooDeep = true
                return
            }
            reached.add(id)
            stack.add(id)
            for (ref in childReferences(comps[id]!!, catalog)) if (comps.containsKey(ref.id)) visit(ref.id)
            stack.removeAt(stack.size - 1)
        }
        visit("root")
        val c = cycle
        if (c != null) fail("Circular reference detected. Circular component reference: ${c.joinToString(" -> ")}")
        else if (tooDeep) fail("Global recursion limit exceeded: the component tree is deeper than $MAX_NESTING levels")
        else for (id in comps.keys) if (id !in reached) fail("Component '$id' is not reachable from 'root'")
        return out
    }
}
