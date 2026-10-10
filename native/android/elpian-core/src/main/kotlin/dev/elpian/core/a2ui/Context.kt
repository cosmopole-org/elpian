package dev.elpian.core.a2ui

import dev.elpian.core.util.JsonMap

/**
 * `DataContext` — evaluation of dynamic values within a data scope
 * (a2ui/context.ts).
 *
 * A dynamic value is a literal, a data binding `{ "path": "…" }` or a function
 * call `{ "call": "…", "args": {…}, "returnType": "…" }`. Paths are absolute
 * (`/user/name`) or relative to the context's scope (the template item a
 * component was instantiated for, e.g. `/users/0`). Function arguments are
 * evaluated recursively — lists element by element — before the function runs.
 */
interface EvaluationHost {
    /** BCP 47 locale for formatting (default `en-US`). */
    val locale: String? get() = null

    /** Base for relative URLs (`openUrl`). */
    val baseUrl: String? get() = null

    /** Perform `openUrl` (already validated to be http/https). */
    val openUrl: ((String) -> Unit)? get() = null

    /** Observe a function call before it runs (tests, tracing). */
    val onCall: ((name: String, args: Map<String, Any?>) -> Unit)? get() = null
}

/** An [EvaluationHost] with nothing configured. */
object DefaultEvaluationHost : EvaluationHost

/** `{ "path": "…" }` and nothing else. */
fun isBinding(v: Any?): Boolean = v is Map<*, *> && v["path"] is String && v.keys.all { it == "path" }

/** `{ "call": "…", "args"?: {…}, "returnType"?: "…" }`. */
fun isFunctionCall(v: Any?): Boolean =
    v is Map<*, *> && v["call"] is String && v.keys.all { it == "call" || it == "args" || it == "returnType" }

@Suppress("UNCHECKED_CAST")
private fun asObject(v: Any?): Map<String, Any?>? = if (v is Map<*, *>) v as Map<String, Any?> else null

class DataContext(
    val model: DataModel,
    val catalog: A2UICatalog,
    /** The data scope relative paths resolve against (`/` at the root). */
    val scope: String = "/",
    val host: EvaluationHost = DefaultEvaluationHost,
) {
    val locale: String get() = host.locale ?: "en-US"

    /** A context scoped to [scope] (an absolute pointer). */
    fun child(scope: String): DataContext = DataContext(model, catalog, scope, host)

    fun resolvePath(path: String): String = resolvePath(path, scope)

    fun read(path: String): Any? = model.get(resolvePath(path))

    fun write(path: String, value: Any?) {
        model.set(resolvePath(path), value)
    }

    /** The absolute path a binding writes to, or null when [value] is not a binding. */
    fun bindingPath(value: Any?): String? = if (isBinding(value)) resolvePath((value as Map<*, *>)["path"] as String) else null

    /** Evaluate a dynamic property value (literal lists stay literal). */
    fun evaluate(value: Any?): Any? {
        if (isBinding(value)) return read((value as Map<*, *>)["path"] as String)
        if (isFunctionCall(value)) {
            val m = value as Map<*, *>
            return call(m["call"] as String, asObject(m["args"]) ?: emptyMap())
        }
        return value
    }

    /** Evaluate and coerce to a string (`''` for null). */
    fun string(value: Any?): String = stringifyValue(evaluate(value))

    /** Evaluate and coerce to a number (null when not numeric). */
    fun number(value: Any?): Double? {
        val v = evaluate(value)
        if (v is Number) return v.toDouble().takeIf { it.isFinite() }
        if (v is String && v.trim { isJsSpace(it) } != "") return jsNumberOfString(v).takeIf { it.isFinite() }
        return null
    }

    fun boolean(value: Any?): Boolean = toBool(evaluate(value))

    /** Evaluate to a list of strings (non-lists become `[]`, a lone string `[s]`). */
    fun stringList(value: Any?): List<String> {
        val v = evaluate(value)
        if (v is List<*>) return v.filterNotNull().map { stringifyValue(it) }
        if (v is String && v != "") return listOf(v)
        return emptyList()
    }

    /** Evaluate a function argument: bindings, calls, and lists of them. */
    fun argument(value: Any?): Any? {
        if (value is List<*>) return value.map { argument(it) }
        return evaluate(value)
    }

    /** Call catalog function [name] with unevaluated [args]. */
    fun call(name: String, args: Map<String, Any?>): Any? {
        val impl = catalog.implementations[name] ?: throw expressionError("Unknown function \"$name\"")
        val resolved = LinkedHashMap<String, Any?>()
        for ((k, v) in args) resolved[k] = argument(v)
        host.onCall?.invoke(name, resolved)
        return impl(resolved, functionContext())
    }

    private fun functionContext(): FunctionContext {
        val self = this
        return object : FunctionContext {
            override val locale: String get() = self.locale
            override val baseUrl: String? get() = self.host.baseUrl
            override fun read(path: String): Any? = self.read(path)
            override fun call(name: String, args: Map<String, Any?>): Any? = self.call(name, args)
            override val openUrl: ((String) -> Unit)? = self.host.openUrl
        }
    }

    /**
     * Evaluate without throwing: expression errors (unknown function, bad
     * template) yield [fallback] and are reported to [onError].
     */
    fun <T> safe(fallback: T, onError: ((A2UIError) -> Unit)? = null, fn: () -> T): T = try {
        fn()
    } catch (e: Exception) {
        val err = e as? A2UIError ?: expressionError(e.message ?: e.toString())
        onError?.invoke(err)
        fallback
    }
}

/**
 * Run a component's `checks` and return the messages of those that fail. A
 * check is `{ condition, message }`; the protocol document's shorthand
 * `{ call, args, message }` is accepted too.
 */
fun evaluateChecks(checks: Any?, ctx: DataContext, onError: ((A2UIError) -> Unit)? = null): List<String> {
    if (checks !is List<*>) return emptyList()
    val failures = ArrayList<String>()
    for (check in checks) {
        if (check !is Map<*, *>) continue
        val condition: Any? = when {
            check.containsKey("condition") -> check["condition"]
            check["call"] is String -> linkedMapOf("call" to check["call"], "args" to (check["args"] ?: LinkedHashMap<String, Any?>()))
            else -> true
        }
        val ok = ctx.safe(false, onError) { ctx.boolean(condition) }
        if (!ok) failures.add(check["message"] as? String ?: "Invalid value")
    }
    return failures
}

/** An `action.event` with its context resolved. */
class ResolvedEvent(val name: String, val context: JsonMap, val userMessage: String? = null)

/**
 * Resolve an `Action`: `{ event: { name, context } }` (also the v0.9 shorthand
 * `{ name, context }`) becomes a [ResolvedEvent] with every context value
 * evaluated now; `{ functionCall }` runs locally and yields null.
 */
fun resolveAction(action: Any?, ctx: DataContext): ResolvedEvent? {
    val a = asObject(action) ?: throw expressionError("Action must be an object")
    val fc = asObject(a["functionCall"])
    if (fc != null) {
        val call = fc["call"] as? String ?: throw expressionError("functionCall needs a \"call\" name")
        ctx.call(call, asObject(fc["args"]) ?: emptyMap())
        return null
    }
    val event = asObject(a["event"]) ?: if (a["name"] is String) a else null
    val name = event?.get("name") as? String ?: throw expressionError("Action needs an \"event\" with a \"name\"")
    val context = LinkedHashMap<String, Any?>()
    asObject(event["context"])?.let { c -> for ((k, v) in c) context[k] = ctx.evaluate(v) }
    return ResolvedEvent(name, context, event["userMessage"] as? String)
}
