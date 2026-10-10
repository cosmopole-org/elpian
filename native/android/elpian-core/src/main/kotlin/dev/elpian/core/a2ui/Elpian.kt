package dev.elpian.core.a2ui

import dev.elpian.core.engine.ElpianEngine
import dev.elpian.core.engine.ElpianServices
import dev.elpian.core.events.ElpianEvent
import dev.elpian.core.events.makeEvent
import dev.elpian.core.model.ElpianNode
import dev.elpian.core.platform.Platforms
import dev.elpian.core.platform.platform
import dev.elpian.core.util.Json
import dev.elpian.core.util.JsonMap
import dev.elpian.core.util.Typed
import dev.elpian.core.util.jsString
import dev.elpian.core.util.normalizedArgs
import dev.elpian.core.util.stableKey
import dev.elpian.core.widgets.BuildContext
import dev.elpian.core.widgets.WidgetBuilder
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Deferred
import java.util.Collections
import java.util.WeakHashMap

/**
 * A2UI inside Elpian (a2ui/elpian.ts): the `A2UISurface` widget (also
 * `a2ui-surface`), the per-app conversation registry it and the host APIs
 * share, and the guest host APIs `agent.send`, `agent.action` and
 * `a2ui.dataModel`.
 *
 * Widget props:
 *   agent         agent name (`/apps/<app>/agent/<agent>`)
 *   app           app id (default: the registry's — the current app)
 *   baseUrl       server base URL (default: the registry's / the session's)
 *   conversation  conversation key; widgets with the same key share one
 *                 conversation (default `agent:<agent>`)
 *   prompt        first message, sent once when the conversation is new
 *   surfaceId     render only this surface (default: all, in creation order)
 *   showText      render the agent's prose
 *   chat          add an input row to message the agent
 *   messages      static A2UI messages to render without an agent
 * Events (dispatched to the node's `events` handlers):
 *   a2uiAction  {name, surfaceId, sourceComponentId, timestamp, context}
 *   a2uiText    {text}
 *   a2uiError   {message}
 *   a2uiDone    {stopReason, conversationId}
 */

/** The guest host APIs this module serves (HostApiCatalog's `agentApiNames`). */
val AGENT_API_NAMES: Set<String> = linkedSetOf("agent.send", "agent.action", "a2ui.dataModel")

/** Where agents are reached when a widget or host call does not say. */
class A2UIDefaults(
    var baseUrl: String? = null,
    var appId: String? = null,
    var headers: Map<String, String> = emptyMap(),
)

private class Binding(var engine: ElpianEngine, var node: ElpianNode, val conversation: A2UIConversation) {
    var unsubscribe: () -> Unit = {}
}

/** Conversations of one app (one [ElpianServices]), keyed by conversation key. */
class A2UIRegistry {
    var defaults = A2UIDefaults()
    private val conversations = LinkedHashMap<String, A2UIConversation>()
    private val engines = LinkedHashSet<ElpianEngine>()
    private val bindings = LinkedHashMap<String, Binding>()

    /** The conversation under [key], created by [create] when new. */
    fun conversation(key: String, create: () -> A2UIConversation): A2UIConversation {
        conversations[key]?.let { return it }
        val c = create()
        conversations[key] = c
        c.on { e -> if (e === A2UIConversationEvent.Changed) invalidate() }
        return c
    }

    fun get(key: String): A2UIConversation? = conversations[key]

    fun keys(): List<String> = conversations.keys.toList()

    /** An endpoint for [agent] from the defaults (and overrides), or null without a base URL / app. */
    fun endpoint(agent: String, baseUrl: Any? = null, appId: Any? = null): AgentEndpoint? {
        val base = (baseUrl as? String)?.takeIf { it.isNotEmpty() } ?: defaults.baseUrl
        val app = (appId as? String)?.takeIf { it.isNotEmpty() } ?: defaults.appId
        if (agent.isEmpty() || base == null || app == null) return null
        return AgentEndpoint(base, app, agent, defaults.headers)
    }

    /** An engine renders this registry's conversations. */
    fun attach(engine: ElpianEngine) {
        engines.add(engine)
    }

    /** Every attached engine renders again. */
    fun invalidate() {
        for (e in engines.toList()) e.host.invalidate?.invoke()
    }

    /** Route [conversation]'s events to the widget rendered as [elementId]. */
    fun bind(elementId: String, engine: ElpianEngine, node: ElpianNode, conversation: A2UIConversation) {
        val existing = bindings[elementId]
        if (existing != null && existing.conversation === conversation) {
            existing.node = node
            existing.engine = engine
            return
        }
        existing?.unsubscribe?.invoke()
        val binding = Binding(engine, node, conversation)
        binding.unsubscribe = conversation.on { e -> deliver(elementId, binding, e) }
        bindings[elementId] = binding
    }

    private fun deliver(elementId: String, b: Binding, e: A2UIConversationEvent) {
        val type: String
        val payload: Any?
        when (e) {
            is A2UIConversationEvent.Action -> {
                type = "a2uiAction"
                payload = e.action.toJson()
            }
            is A2UIConversationEvent.Text -> {
                if (e.role != "agent") return
                type = "a2uiText"
                payload = linkedMapOf<String, Any?>("text" to e.text)
            }
            is A2UIConversationEvent.Error -> {
                type = "a2uiError"
                payload = linkedMapOf<String, Any?>("message" to e.message)
            }
            is A2UIConversationEvent.Done -> {
                type = "a2uiDone"
                payload = linkedMapOf<String, Any?>("stopReason" to e.stopReason, "conversationId" to e.conversationId)
            }
            else -> return
        }
        val events = b.node.events ?: emptyMap()
        val name = events.keys.firstOrNull { it.lowercase() == type.lowercase() } ?: return
        val dispatcher = b.engine.services.events
        if (dispatcher.getNode(elementId) == null) {
            // The widget is no longer rendered.
            b.unsubscribe()
            bindings.remove(elementId)
            return
        }
        @Suppress("UNCHECKED_CAST")
        val event: ElpianEvent = makeEvent(name, "custom", elementId) {
            data = if (payload is Map<*, *>) payload as Map<String, Any?> else linkedMapOf("value" to payload)
            value = payload
        }
        dispatcher.dispatchEvent(event, elementId)
    }

    fun dispose() {
        for (b in bindings.values) b.unsubscribe()
        bindings.clear()
        for (c in conversations.values) c.dispose()
        conversations.clear()
        engines.clear()
    }
}

private val registries: MutableMap<ElpianServices, A2UIRegistry> = Collections.synchronizedMap(WeakHashMap())

/** The A2UI registry of an app's services (created on first use). */
fun a2uiRegistry(services: ElpianServices): A2UIRegistry = synchronized(registries) { registries.getOrPut(services) { A2UIRegistry() } }

private fun conversationKey(props: Map<String, Any?>, elementId: String): String {
    val c = props["conversation"]
    if (c is String && c.isNotEmpty()) return c
    if (props["messages"] is List<*>) return "static:$elementId"
    return "agent:${props["agent"] as? String ?: ""}"
}

private fun node(type: String, props: JsonMap = LinkedHashMap(), children: List<JsonMap> = emptyList(), key: String? = null, events: Map<String, Any?>? = null): JsonMap {
    val n: JsonMap = linkedMapOf("type" to type, "props" to props, "children" to children)
    if (key != null) n["key"] = key
    if (events != null) n["events"] = events
    return n
}

private fun chatParts(conversation: A2UIConversation, props: Map<String, Any?>, key: String, invalidate: () -> Unit): List<JsonMap> {
    val parts = ArrayList<JsonMap>()
    val palette = paletteFor(emptyMap())
    if (props["showText"] == true) {
        conversation.transcript.forEachIndexed { i, t ->
            val mine = t.role == "user"
            parts.add(
                node(
                    "Row",
                    linkedMapOf("style" to linkedMapOf<String, Any?>("justifyContent" to (if (mine) "flex-end" else "flex-start"))),
                    listOf(
                        node(
                            "Flexible",
                            linkedMapOf("flex" to 1.0, "fit" to "loose"),
                            listOf(
                                node(
                                    "Container",
                                    linkedMapOf(
                                        "style" to linkedMapOf<String, Any?>(
                                            "padding" to "8 12",
                                            "margin" to 4.0,
                                            "borderRadius" to 16.0,
                                            "backgroundColor" to (if (mine) palette.primaryContainer else palette.surfaceContainer),
                                        ),
                                    ),
                                    listOf(node("Text", linkedMapOf("text" to t.text, "style" to linkedMapOf<String, Any?>("fontSize" to 15.0, "lineHeight" to 1.45, "color" to palette.onSurface)))),
                                ),
                            ),
                        ),
                    ),
                    key = "$key/t$i",
                ),
            )
        }
    }
    if (conversation.busy) {
        parts.add(node("LinearProgressIndicator", linkedMapOf("style" to linkedMapOf<String, Any?>("color" to palette.primary, "margin" to "4 0")), key = "$key/busy"))
    }
    if (props["chat"] == true) {
        val draftKey = "$key#draft"
        val draft = conversation.ui.get(draftKey, "")
        val submit = {
            val text = conversation.ui.get(draftKey, "").trim()
            if (text.isNotEmpty() && conversation.endpoint != null) {
                conversation.ui.set(draftKey, "")
                conversation.send(text)
                invalidate()
            }
        }
        parts.add(
            node(
                "Row",
                linkedMapOf("style" to linkedMapOf<String, Any?>("alignItems" to "center", "margin" to "8 0 0 0")),
                listOf(
                    node(
                        "Expanded",
                        linkedMapOf("flex" to 1.0),
                        listOf(
                            node(
                                "TextField",
                                linkedMapOf("value" to draft, "hint" to "Message the agent", "style" to linkedMapOf<String, Any?>("color" to palette.onSurface, "margin" to "0 8 0 4")),
                                key = "$key/chat/input",
                                events = linkedMapOf(
                                    "input" to { e: ElpianEvent ->
                                        e.propagationStopped = true
                                        conversation.ui.set(draftKey, e.value?.let { if (it is String) it else jsString(it) } ?: "")
                                    },
                                    "submit" to { e: ElpianEvent ->
                                        e.propagationStopped = true
                                        submit()
                                    },
                                ),
                            ),
                        ),
                    ),
                    node(
                        "Button",
                        linkedMapOf("text" to "Send", "disabled" to conversation.busy, "style" to linkedMapOf<String, Any?>("backgroundColor" to palette.primary, "color" to palette.onPrimary)),
                        listOf(node("Icon", linkedMapOf("icon" to "send", "size" to 20.0, "style" to linkedMapOf<String, Any?>("color" to palette.onPrimary)))),
                        key = "$key/chat/send",
                        events = linkedMapOf(
                            "click" to { e: ElpianEvent ->
                                e.propagationStopped = true
                                submit()
                            },
                        ),
                    ),
                ),
                key = "$key/chat",
            ),
        )
    }
    return parts
}

/** Run [fn] after the current build (the turn emits events). */
private fun later(fn: () -> Unit) {
    if (Platforms.isInstalled) platform().setTimeout(0.0, fn) else fn()
}

/** Build the Elpian node tree an `A2UISurface` element shows (exported for previews and tests). */
fun a2uiSurfaceTree(engine: ElpianEngine, props: Map<String, Any?>, elementId: String, node: ElpianNode? = null): JsonMap {
    val registry = a2uiRegistry(engine.services)
    registry.attach(engine)
    val agent = props["agent"] as? String ?: ""
    val key = conversationKey(props, elementId)
    val messages = props["messages"] as? List<*>
    val conversation = registry.conversation(key) {
        A2UIConversation(
            endpoint = if (messages != null) null else registry.endpoint(agent, props["baseUrl"], props["app"]),
            conversationId = props["conversationId"] as? String,
        )
    }
    if (conversation.endpoint == null && agent.isNotEmpty() && messages == null) {
        conversation.endpoint = registry.endpoint(agent, props["baseUrl"], props["app"])
    }
    if (messages != null) conversation.syncStatic(messages, stableKey(messages))
    if (node != null) registry.bind(elementId, engine, node, conversation)
    val prompt = props["prompt"]
    if (prompt is String && prompt.isNotEmpty() && !conversation.prompted && conversation.endpoint != null) {
        conversation.prompted = true
        later { conversation.send(prompt) }
    }
    val invalidate = { registry.invalidate() }
    val hooks = conversation.loweringHooks(invalidate)
    val parts = ArrayList<JsonMap>()
    val only = props["surfaceId"] as? String
    for (surface in conversation.processor.surfaces) {
        if (!only.isNullOrEmpty() && surface.id != only) continue
        parts.add(lowerSurface(surface, LoweringOptions(hooks, conversation.ui, keyPrefix = elementId, showAttribution = props["showAttribution"] != false)).node)
    }
    parts.addAll(chatParts(conversation, props, elementId, invalidate))
    return node("Column", linkedMapOf("style" to linkedMapOf<String, Any?>("alignItems" to "stretch")), parts, key = "$elementId/a2ui")
}

private val a2uiSurfaceBuilder: WidgetBuilder = { node, _, ctx: BuildContext ->
    val tree = a2uiSurfaceTree(ctx.engine, node.props, ctx.elementId, node)
    ctx.engine.renderNode(ElpianNode.fromJson(tree), ctx, 0)
}

val a2uiWidgets: Map<String, WidgetBuilder> = linkedMapOf(
    "A2UISurface" to a2uiSurfaceBuilder,
    "a2ui-surface" to a2uiSurfaceBuilder,
)

// ----------------------------------------------------------------------------
// Host APIs
// ----------------------------------------------------------------------------

private fun errorResponse(message: String): String = Typed.response("object", linkedMapOf("error" to linkedMapOf("message" to message)))

/** A typed host response for a JSON value. */
private fun valueResponse(value: Any?): String = when (value) {
    null -> Typed.NULL
    is List<*> -> Typed.response("array", value)
    is Map<*, *> -> Typed.response("object", value)
    is String -> Typed.response("string", value)
    is Boolean -> Typed.response("bool", value)
    is Number -> Typed.response(if (value.toDouble() == Math.rint(value.toDouble()) && value.toDouble().isFinite()) "i64" else "f64", value)
    else -> Typed.NULL
}

private fun done(value: String): Deferred<String> = CompletableDeferred(value)

/**
 * `agent.send {agent, conversation?, message}` → `{conversationId, conversation}`
 * (once the agent named the conversation); `agent.action {agent, conversation?,
 * action}` → the same; `a2ui.dataModel {conversation, surfaceId}` → the
 * surface's current data model. `conversation` is the conversation key the
 * widgets use (default `agent:<agent>`), so guest code and `A2UISurface`
 * widgets share conversations.
 *
 * The payload may be a bare object or the guest SDK's `[{...}]` (an args
 * array whose first element is the object).
 */
@Suppress("UNCHECKED_CAST")
fun handleAgentHostCall(services: ElpianServices, apiName: String, payload: String): Deferred<String> {
    val args = normalizedArgs(payload)
    val registry = a2uiRegistry(services)
    val agent = args["agent"] as? String ?: ""
    val key = (args["conversation"] as? String)?.takeIf { it.isNotEmpty() } ?: "agent:$agent"
    when (apiName) {
        "agent.send", "agent.action" -> {
            if (agent.isEmpty() && registry.get(key) == null) return done(errorResponse("$apiName requires \"agent\""))
            val conversation = registry.conversation(key) { A2UIConversation(endpoint = registry.endpoint(agent)) }
            if (conversation.endpoint == null && agent.isNotEmpty()) conversation.endpoint = registry.endpoint(agent)
            if (conversation.endpoint == null) return done(errorResponse("no agent endpoint is configured for this app"))
            val turn = if (apiName == "agent.send") {
                val m = args["message"]
                conversation.send(if (m is String) m else Json.stringify(m ?: ""))
            } else {
                val raw = args["action"]
                val action = if (raw is Map<*, *>) LinkedHashMap(raw as Map<String, Any?>) else null
                if (action == null || action["name"] !is String) return done(errorResponse("agent.action requires an \"action\" with a \"name\""))
                if (action["timestamp"] !is String) action["timestamp"] = isoTimestamp()
                if (action["context"] !is Map<*, *>) action["context"] = LinkedHashMap<String, Any?>()
                conversation.sendAction(action)
            }
            val out = CompletableDeferred<String>()
            turn.conversationId.invokeOnCompletion {
                val id = if (turn.conversationId.isCompleted && !turn.conversationId.isCancelled) {
                    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
                    turn.conversationId.getCompleted()
                } else null
                registry.invalidate()
                out.complete(Typed.response("object", linkedMapOf("conversationId" to id, "conversation" to key)))
            }
            return out
        }
        "a2ui.dataModel" -> {
            val conversation = registry.get(key)
            val surfaceId = args["surfaceId"] as? String ?: ""
            if (conversation == null || surfaceId.isEmpty()) return done(Typed.NULL)
            return done(valueResponse(conversation.dataModel(surfaceId)))
        }
    }
    return done(Typed.NULL)
}
