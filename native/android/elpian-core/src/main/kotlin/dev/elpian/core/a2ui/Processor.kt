package dev.elpian.core.a2ui

import dev.elpian.core.util.JsonMap

/**
 * The A2UI message processor (a2ui/processor.ts) — pure state, no UI.
 *
 * It applies server-to-client messages to surfaces:
 *
 * - `createSurface` registers a surface with its catalog (unknown catalog ids
 *   are an error), theme and `sendDataModel` flag; creating an existing
 *   surface is an error;
 * - `updateComponents` upserts the flat adjacency list. Components arriving
 *   before `root` are buffered: a surface is renderable once `root` exists;
 * - `updateDataModel` writes (or, with no / null value, deletes) a JSON
 *   Pointer path of the surface's data model; path `/` replaces it;
 * - `deleteSurface` removes the surface.
 *
 * Inputs write back through [A2UIProcessor.setData] (two-way binding), and
 * interactions go through [A2UIProcessor.dispatchAction], which resolves an
 * `action.event` into the client-to-server `action` (name, surfaceId,
 * sourceComponentId, ISO timestamp, resolved context) and emits it, or runs
 * an `action.functionCall` locally. Listeners observe every change, action
 * and error.
 */

/** The protocol version this renderer speaks. */
const val A2UI_VERSION = "v0.9.1"

class A2UIProcessorOptions(
    override val locale: String? = null,
    override val baseUrl: String? = null,
    override val openUrl: ((String) -> Unit)? = null,
    override val onCall: ((name: String, args: Map<String, Any?>) -> Unit)? = null,
    /** Catalogs this client supports (default: the basic catalog). */
    val catalogs: List<A2UICatalog>? = null,
    /**
     * `strict` rejects a message with any schema issue; `lenient` (default)
     * reports issues but still applies what it can (unknown components render
     * as placeholders); `off` skips schema validation.
     */
    val validation: String? = null,
) : EvaluationHost

/** A component: `id`, `component` and its properties, as JSON. */
typealias A2UIComponent = JsonMap

/** The client-to-server `action` payload. */
class A2UIClientAction(
    val name: String,
    val surfaceId: String,
    val sourceComponentId: String,
    val timestamp: String,
    val context: JsonMap,
    /** Carried through when the action defines one (conformance `userMessage`). */
    val userMessage: String? = null,
) {
    fun toJson(): JsonMap {
        val out: JsonMap = linkedMapOf(
            "name" to name,
            "surfaceId" to surfaceId,
            "sourceComponentId" to sourceComponentId,
            "timestamp" to timestamp,
            "context" to context,
        )
        if (userMessage != null) out["userMessage"] = userMessage
        return out
    }
}

/** surfaceCreated, surfaceUpdated (reason components | data | local), surfaceDeleted, action, error. */
sealed class A2UIProcessorEvent {
    class SurfaceCreated(val surfaceId: String) : A2UIProcessorEvent()
    class SurfaceUpdated(val surfaceId: String, val reason: String) : A2UIProcessorEvent()
    class SurfaceDeleted(val surfaceId: String) : A2UIProcessorEvent()
    class Action(val action: A2UIClientAction) : A2UIProcessorEvent()
    class Error(val error: A2UIError) : A2UIProcessorEvent()
}

typealias A2UIProcessorListener = (A2UIProcessorEvent) -> Unit

class A2UISurfaceModel(
    val id: String,
    val catalog: A2UICatalog,
    /** The catalog id exactly as `createSurface` named it. */
    val catalogId: String,
    val theme: JsonMap,
    val sendDataModel: Boolean,
    private val host: EvaluationHost,
) {
    val components = LinkedHashMap<String, A2UIComponent>()
    val dataModel = DataModel()

    /** Bumped on every change (components, data, local writes). */
    var version = 0

    /** The `root` component, once it has arrived. */
    val root: A2UIComponent? get() = components["root"]

    /** Whether the surface can render (components are buffered until `root` exists). */
    val isReady: Boolean get() = components.containsKey("root")

    /** An evaluation context scoped to [scope]. */
    fun context(scope: String = "/"): DataContext = DataContext(dataModel, catalog, scope, host)
}

@Suppress("UNCHECKED_CAST")
private fun obj(v: Any?): Map<String, Any?>? = if (v is Map<*, *>) v as Map<String, Any?> else null

class A2UIProcessor(val options: A2UIProcessorOptions = A2UIProcessorOptions()) {
    private val surfaceMap = LinkedHashMap<String, A2UISurfaceModel>()
    private val listeners = LinkedHashSet<A2UIProcessorListener>()
    val catalogs: List<A2UICatalog> = options.catalogs ?: listOf(BASIC_CATALOG)
    val validation: String = options.validation ?: "lenient"

    /** Catalog ids this client supports (for `a2uiClientCapabilities`). */
    val supportedCatalogIds: List<String> get() = catalogs.map { it.id }

    fun catalogFor(catalogId: String): A2UICatalog? = catalogs.firstOrNull { it.id == catalogId || catalogId in it.aliases }

    fun on(listener: A2UIProcessorListener): () -> Unit {
        listeners.add(listener)
        return { listeners.remove(listener) }
    }

    private fun emit(event: A2UIProcessorEvent) {
        for (l in listeners.toList()) {
            try {
                l(event)
            } catch (e: Exception) {
                warn("A2UI listener failed: $e")
            }
        }
    }

    private fun report(error: A2UIError): A2UIError {
        emit(A2UIProcessorEvent.Error(error))
        return error
    }

    /** Surfaces in creation order. */
    val surfaces: List<A2UISurfaceModel> get() = surfaceMap.values.toList()

    fun surface(surfaceId: String): A2UISurfaceModel? = surfaceMap[surfaceId]

    /** Apply several messages; returns every error. */
    fun processAll(messages: List<Any?>): List<A2UIError> {
        val out = ArrayList<A2UIError>()
        for (m in messages) out.addAll(process(m))
        return out
    }

    /** Apply one server-to-client message; returns its errors (also emitted). */
    @Suppress("UNCHECKED_CAST")
    fun process(message: Any?): List<A2UIError> {
        val kind = messageKind(message)
        val msg = obj(message)
        if (kind == null || msg == null) {
            return listOf(report(A2UIError("ValidationError", "Not an A2UI message: expected one of createSurface, updateComponents, updateDataModel, deleteSurface", A2UIErrorDetails(path = "/"))))
        }
        val body = obj(msg[kind])
        val surfaceId = body?.get("surfaceId") as? String
        val errors = ArrayList<A2UIError>()
        if (validation != "off") {
            val catalog = surfaceId?.let { surfaceMap[it]?.catalog }
            val issues = validateMessage(message, catalog ?: catalogs[0], requireVersion = validation == "strict")
            for (e in issues) errors.add(report(e))
            if (issues.isNotEmpty() && validation == "strict") return errors
        }
        if (surfaceId.isNullOrEmpty() || body == null) {
            if (errors.isEmpty()) errors.add(report(A2UIError("ValidationError", "$kind requires a \"surfaceId\"", A2UIErrorDetails(path = "/$kind/surfaceId"))))
            return errors
        }
        fun fail(message: String, path: String = "/$kind"): List<A2UIError> {
            errors.add(report(A2UIError("ValidationError", message, A2UIErrorDetails(surfaceId, path))))
            return errors
        }
        when (kind) {
            "createSurface" -> {
                if (surfaceMap.containsKey(surfaceId)) return fail("Surface \"$surfaceId\" already exists; delete it before creating it again")
                val catalogId = body["catalogId"] as? String ?: ""
                val catalog = catalogFor(catalogId)
                    ?: return fail("Unsupported catalog \"$catalogId\" (supported: ${supportedCatalogIds.joinToString(", ")})", "/createSurface/catalogId")
                val theme = obj(body["theme"])?.let { LinkedHashMap(it) } ?: LinkedHashMap()
                surfaceMap[surfaceId] = A2UISurfaceModel(surfaceId, catalog, catalogId, theme, body["sendDataModel"] == true, options)
                emit(A2UIProcessorEvent.SurfaceCreated(surfaceId))
                return errors
            }
            "updateComponents" -> {
                val surface = surfaceMap[surfaceId] ?: return fail("Surface \"$surfaceId\" has not been created")
                val components = body["components"] as? List<*> ?: return errors
                for (c in components) {
                    val m = obj(c) ?: continue
                    val id = m["id"] as? String ?: continue
                    if (m["component"] !is String) continue
                    surface.components[id] = cloneJson(m) as A2UIComponent
                }
                surface.version++
                emit(A2UIProcessorEvent.SurfaceUpdated(surfaceId, "components"))
                return errors
            }
            "updateDataModel" -> {
                val surface = surfaceMap[surfaceId] ?: return fail("Surface \"$surfaceId\" has not been created")
                val path = body["path"] as? String ?: "/"
                try {
                    // An omitted or null value removes the key (list slots become null).
                    val value = body["value"]
                    if (value == null) surface.dataModel.delete(path) else surface.dataModel.set(path, value)
                } catch (e: A2UIError) {
                    errors.add(report(A2UIError(if (e.category == "DataError") "DataError" else "ValidationError", e.message, A2UIErrorDetails(surfaceId, "/updateDataModel/path"))))
                    return errors
                }
                surface.version++
                emit(A2UIProcessorEvent.SurfaceUpdated(surfaceId, "data"))
                return errors
            }
            "deleteSurface" -> {
                val surface = surfaceMap[surfaceId] ?: return fail("Surface \"$surfaceId\" does not exist")
                surface.dataModel.dispose()
                surfaceMap.remove(surfaceId)
                emit(A2UIProcessorEvent.SurfaceDeleted(surfaceId))
                return errors
            }
        }
        return errors
    }

    /** A local write through a two-way binding (an input changed). */
    fun setData(surfaceId: String, path: String, value: Any?) {
        val surface = surfaceMap[surfaceId] ?: return
        try {
            surface.dataModel.set(path, value)
        } catch (e: A2UIError) {
            report(A2UIError(e.category, e.message, A2UIErrorDetails(surfaceId, path)))
            return
        }
        surface.version++
        emit(A2UIProcessorEvent.SurfaceUpdated(surfaceId, "local"))
    }

    /** The surface's current data model (a copy), or null. */
    fun dataModel(surfaceId: String): Any? = surfaceMap[surfaceId]?.dataModel?.snapshot()

    /**
     * The `a2uiClientDataModel` metadata: the models of the surfaces created
     * with `sendDataModel: true`, or null when there are none.
     */
    fun clientDataModel(): JsonMap? {
        val surfaces = LinkedHashMap<String, Any?>()
        var any = false
        for (s in surfaceMap.values) {
            if (!s.sendDataModel) continue
            surfaces[s.id] = s.dataModel.snapshot()
            any = true
        }
        return if (any) linkedMapOf("version" to A2UI_VERSION, "surfaces" to surfaces) else null
    }

    /**
     * The user interacted with [componentId]: resolve its [action] in [scope].
     * An `event` becomes an [A2UIClientAction], emitted and returned; a
     * `functionCall` runs locally (returns null). Failures are reported and
     * return null.
     */
    fun dispatchAction(surfaceId: String, componentId: String, action: Any?, scope: String = "/", nowMs: Long = System.currentTimeMillis()): A2UIClientAction? {
        val surface = surfaceMap[surfaceId] ?: return null
        try {
            val event = resolveAction(action, surface.context(scope))
            if (event == null) {
                surface.version++
                emit(A2UIProcessorEvent.SurfaceUpdated(surfaceId, "local"))
                return null
            }
            val out = A2UIClientAction(event.name, surfaceId, componentId, isoTimestamp(nowMs), event.context, event.userMessage)
            emit(A2UIProcessorEvent.Action(out))
            return out
        } catch (e: Exception) {
            val err = e as? A2UIError ?: A2UIError("ExpressionError", e.message ?: e.toString())
            report(A2UIError(err.category, err.message, A2UIErrorDetails(surfaceId, null)))
            return null
        }
    }

    /** Remove every surface. */
    fun reset() {
        for (id in surfaceMap.keys.toList()) {
            surfaceMap[id]!!.dataModel.dispose()
            surfaceMap.remove(id)
            emit(A2UIProcessorEvent.SurfaceDeleted(id))
        }
    }
}

/** The client-to-server message carrying [action]. */
fun clientActionMessage(action: A2UIClientAction): JsonMap = linkedMapOf("version" to A2UI_VERSION, "action" to action.toJson())
