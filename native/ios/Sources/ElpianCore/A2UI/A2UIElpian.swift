import Foundation

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

/** The guest host APIs this module serves (the generated catalog's `agentApiNames`). */
public let AGENT_API_NAMES: Set<String> = HostApiCatalog.agentApiNames

/** Where agents are reached when a widget or host call does not say. */
public struct A2UIDefaults {
    public var baseUrl: String?
    public var appId: String?
    public var headers: [String: String]?

    public init(baseUrl: String? = nil, appId: String? = nil, headers: [String: String]? = nil) {
        self.baseUrl = baseUrl
        self.appId = appId
        self.headers = headers
    }
}

private final class Binding {
    weak var engine: ElpianEngine?
    var node: ElpianNode
    let conversation: A2UIConversation
    var unsubscribe: () -> Void = {}

    init(_ engine: ElpianEngine, _ node: ElpianNode, _ conversation: A2UIConversation) {
        self.engine = engine
        self.node = node
        self.conversation = conversation
    }
}

private struct WeakEngine {
    weak var engine: ElpianEngine?
}

/** Conversations of one app (one [ElpianServices]), keyed by conversation key. */
public final class A2UIRegistry {
    public var defaults = A2UIDefaults()
    private var conversations = A2UIOrderedMap<A2UIConversation>()
    private var engines: [WeakEngine] = []
    private var bindings: [String: Binding] = [:]

    public init() {}

    /** The conversation under [key], created by [create] when new. */
    public func conversation(_ key: String, _ create: () -> A2UIConversation) -> A2UIConversation {
        if let c = conversations[key] { return c }
        let c = create()
        conversations[key] = c
        c.on { [weak self] e in
            if case .changed = e { self?.invalidate() }
        }
        return c
    }

    public func get(_ key: String) -> A2UIConversation? { conversations[key] }

    public func keys() -> [String] { conversations.keys }

    /** An endpoint for [agent] from the defaults (and overrides), or nil without a base URL / app. */
    public func endpoint(_ agent: String, baseUrl: Any? = nil, appId: Any? = nil) -> AgentEndpoint? {
        let b = (flattenOptional(baseUrl) as? String).flatMap { $0.isEmpty ? nil : $0 } ?? defaults.baseUrl
        let a = (flattenOptional(appId) as? String).flatMap { $0.isEmpty ? nil : $0 } ?? defaults.appId
        guard !agent.isEmpty, let base = b, let app = a else { return nil }
        return AgentEndpoint(baseUrl: base, appId: app, agent: agent, headers: defaults.headers)
    }

    /** An engine renders this registry's conversations. */
    public func attach(_ engine: ElpianEngine) {
        engines.removeAll { $0.engine == nil }
        if !engines.contains(where: { $0.engine === engine }) { engines.append(WeakEngine(engine: engine)) }
    }

    /** Every attached engine renders again. */
    public func invalidate() {
        for e in engines { e.engine?.host.invalidate?() }
    }

    /** Route [conversation]'s events to the widget rendered as [elementId]. */
    public func bind(_ elementId: String, _ engine: ElpianEngine, _ node: ElpianNode, _ conversation: A2UIConversation) {
        if let existing = bindings[elementId], existing.conversation === conversation {
            existing.node = node
            existing.engine = engine
            return
        }
        bindings[elementId]?.unsubscribe()
        let binding = Binding(engine, node, conversation)
        binding.unsubscribe = conversation.on { [weak self, weak binding] e in
            guard let self = self, let b = binding else { return }
            self.deliver(elementId, b, e)
        }
        bindings[elementId] = binding
    }

    private func deliver(_ elementId: String, _ b: Binding, _ e: A2UIConversationEvent) {
        let type: String
        let payload: Any?
        switch e {
        case .action(let action):
            type = "a2uiAction"
            payload = action.toJson()
        case .text(let text, let role):
            if role != "agent" { return }
            type = "a2uiText"
            payload = JSONObject([("text", text)])
        case .error(let message, _):
            type = "a2uiError"
            payload = JSONObject([("message", message)])
        case .done(let stopReason, let conversationId):
            type = "a2uiDone"
            payload = JSONObject([("stopReason", stopReason), ("conversationId", conversationId)])
        default:
            return
        }
        let events = b.node.events ?? JSONObject()
        guard let name = events.keys.first(where: { $0.lowercased() == type.lowercased() }) else { return }
        guard let dispatcher = b.engine?.services.events, dispatcher.getNode(elementId) != nil else {
            // The widget is no longer rendered.
            b.unsubscribe()
            bindings.removeValue(forKey: elementId)
            return
        }
        let event = makeEvent(name, "custom", elementId) { ev in
            ev.data = asMap(payload) ?? JSONObject([("value", payload)])
            ev.value = payload
        }
        dispatcher.dispatchEvent(event, elementId)
    }

    public func dispose() {
        for b in bindings.values { b.unsubscribe() }
        bindings.removeAll()
        for c in conversations.values { c.dispose() }
        conversations.removeAll()
        engines.removeAll()
    }
}

private struct RegistryEntry {
    weak var services: ElpianServices?
    let registry: A2UIRegistry
}

private let registriesLock = NSLock()
private var registries: [ObjectIdentifier: RegistryEntry] = [:]

/** The A2UI registry of an app's services (created on first use). */
public func a2uiRegistry(_ services: ElpianServices) -> A2UIRegistry {
    registriesLock.lock()
    defer { registriesLock.unlock() }
    let id = ObjectIdentifier(services)
    if let e = registries[id], e.services === services { return e.registry }
    // Drop the registries of services that are gone (their ids may be reused).
    registries = registries.filter { $0.value.services != nil }
    let r = A2UIRegistry()
    registries[id] = RegistryEntry(services: services, registry: r)
    return r
}

private func conversationKey(_ props: JSONObject, _ elementId: String) -> String {
    if let c = props["conversation"] as? String, !c.isEmpty { return c }
    if asArray(props["messages"]) != nil { return "static:\(elementId)" }
    return "agent:\((props["agent"] as? String) ?? "")"
}

private func chatParts(_ conversation: A2UIConversation, _ props: JSONObject, _ key: String, _ invalidate: @escaping () -> Void) -> [JSONObject] {
    var parts: [JSONObject] = []
    let palette = paletteFor(JSONObject())
    if jsBool(props["showText"]) == true {
        for (i, t) in conversation.transcript.enumerated() {
            let mine = t.role == "user"
            parts.append(a2uiElement("Row", JSONObject([("style", JSONObject([("justifyContent", mine ? "flex-end" : "flex-start")]))]), [
                a2uiElement("Flexible", JSONObject([("flex", 1.0), ("fit", "loose")]), [
                    a2uiElement("Container", JSONObject([("style", JSONObject([
                        ("padding", "8 12"), ("margin", 4.0), ("borderRadius", 16.0),
                        ("backgroundColor", mine ? palette.primaryContainer : palette.surfaceContainer),
                    ]))]), [
                        a2uiElement("Text", JSONObject([("text", t.text), ("style", JSONObject([("fontSize", 15.0), ("lineHeight", 1.45), ("color", palette.onSurface)]))])),
                    ]),
                ]),
            ], key: "\(key)/t\(i)"))
        }
    }
    if conversation.busy {
        parts.append(a2uiElement("LinearProgressIndicator", JSONObject([("style", JSONObject([("color", palette.primary), ("margin", "4 0")]))]), key: "\(key)/busy"))
    }
    if jsBool(props["chat"]) == true {
        let draftKey = "\(key)#draft"
        let draft = conversation.ui.get(draftKey, "")
        let submit: () -> Void = { [weak conversation] in
            guard let conversation = conversation else { return }
            let text = jsTrim(conversation.ui.get(draftKey, ""))
            if text.isEmpty || conversation.endpoint == nil { return }
            conversation.ui.set(draftKey, "")
            conversation.send(text)
            invalidate()
        }
        parts.append(a2uiElement("Row", JSONObject([("style", JSONObject([("alignItems", "center"), ("margin", "8 0 0 0")]))]), [
            a2uiElement("Expanded", JSONObject([("flex", 1.0)]), [
                a2uiElement("TextField", JSONObject([
                    ("value", draft), ("hint", "Message the agent"), ("style", JSONObject([("color", palette.onSurface), ("margin", "0 8 0 4")])),
                ]), key: "\(key)/chat/input", events: [
                    ("input", { [weak conversation] e in
                        e.propagationStopped = true
                        conversation?.ui.set(draftKey, e.value == nil ? "" : jsString(e.value))
                    }),
                    ("submit", { e in
                        e.propagationStopped = true
                        submit()
                    }),
                ]),
            ]),
            a2uiElement("Button", JSONObject([
                ("text", "Send"), ("disabled", conversation.busy), ("style", JSONObject([("backgroundColor", palette.primary), ("color", palette.onPrimary)])),
            ]), [
                a2uiElement("Icon", JSONObject([("icon", "send"), ("size", 20.0), ("style", JSONObject([("color", palette.onPrimary)]))])),
            ], key: "\(key)/chat/send", events: [("click", { e in
                e.propagationStopped = true
                submit()
            })]),
        ], key: "\(key)/chat"))
    }
    return parts
}

/** Build the Elpian node tree an `A2UISurface` element shows (exported for previews and tests). */
public func a2uiSurfaceTree(_ engine: ElpianEngine, _ props: JSONObject, _ elementId: String, _ node: ElpianNode? = nil) -> JSONObject {
    let registry = a2uiRegistry(engine.services)
    registry.attach(engine)
    let agent = (props["agent"] as? String) ?? ""
    let key = conversationKey(props, elementId)
    let messages = asArray(props["messages"])
    let conversation = registry.conversation(key) {
        A2UIConversation(A2UIConversationOptions(
            endpoint: messages != nil ? nil : registry.endpoint(agent, baseUrl: props["baseUrl"], appId: props["app"]),
            conversationId: props["conversationId"] as? String
        ))
    }
    if conversation.endpoint == nil && !agent.isEmpty && messages == nil {
        conversation.endpoint = registry.endpoint(agent, baseUrl: props["baseUrl"], appId: props["app"])
    }
    if let m = messages { conversation.syncStatic(m, stableKey(m)) }
    if let n = node { registry.bind(elementId, engine, n, conversation) }
    if let prompt = props["prompt"] as? String, !prompt.isEmpty, !conversation.prompted, conversation.endpoint != nil {
        conversation.prompted = true
        // Not during a build: the turn emits events.
        scheduleMicrotask { [weak conversation] in conversation?.send(prompt) }
    }
    let invalidate: () -> Void = { [weak registry] in registry?.invalidate() }
    let hooks = conversation.loweringHooks(invalidate)
    var parts: [JSONObject] = []
    let only = (props["surfaceId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    for surface in conversation.processor.surfaces {
        if let o = only, surface.id != o { continue }
        parts.append(lowerSurface(surface, LoweringOptions(hooks: hooks, state: conversation.ui, keyPrefix: elementId,
                                                           showAttribution: jsBool(props["showAttribution"]) != false)).node)
    }
    parts += chatParts(conversation, props, elementId, invalidate)
    return a2uiElement("Column", JSONObject([("style", JSONObject([("alignItems", "stretch")]))]), parts, key: "\(elementId)/a2ui")
}

private func buildA2UISurface(_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W {
    let tree = a2uiSurfaceTree(ctx.engine, node.props, ctx.elementId, node)
    return ctx.engine.renderNode(nodeFromJson(tree), ctx, 0)
}

public let a2uiWidgets: [(String, WidgetBuilder)] = [
    ("A2UISurface", buildA2UISurface),
    ("a2ui-surface", buildA2UISurface),
]

// ----------------------------------------------------------------------------
// Host APIs
// ----------------------------------------------------------------------------

private func errorResponse(_ message: String) -> String {
    Typed.makeResponse("object", JSONObject([("error", JSONObject([("message", message)]))]))
}

/** A typed host response for a JSON value. */
private func valueResponse(_ value: Any?) -> String {
    guard let v = flattenOptional(value) else { return Typed.NULL_RESPONSE }
    if let a = asArray(v) { return Typed.makeResponse("array", a) }
    if let o = asMap(v) { return Typed.makeResponse("object", o) }
    if let s = v as? String { return Typed.makeResponse("string", s) }
    if let b = jsBool(v) { return Typed.makeResponse("bool", b) }
    if let n = jsNumber(v) { return Typed.makeResponse(n == n.rounded(.towardZero) && n.isFinite ? "i64" : "f64", n) }
    return Typed.NULL_RESPONSE
}

/** The synchronous part of an agent host call: an answer now, or a started turn. */
private enum AgentHostStart {
    case reply(String)
    case turn(A2UITurn, key: String, registry: A2UIRegistry, conversation: A2UIConversation)
}

private func startAgentHostCall(_ services: ElpianServices, _ apiName: String, _ payload: String) -> AgentHostStart {
    // `askHost(name, [{...}])` and a bare object both arrive as one map.
    let args = normalizedArgs(payload)
    let registry = a2uiRegistry(services)
    let agent = (args["agent"] as? String) ?? ""
    let key = (args["conversation"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "agent:\(agent)"
    switch apiName {
    case "agent.send", "agent.action":
        if agent.isEmpty && registry.get(key) == nil { return .reply(errorResponse("\(apiName) requires \"agent\"")) }
        let conversation = registry.conversation(key) { A2UIConversation(A2UIConversationOptions(endpoint: registry.endpoint(agent))) }
        if conversation.endpoint == nil && !agent.isEmpty { conversation.endpoint = registry.endpoint(agent) }
        if conversation.endpoint == nil { return .reply(errorResponse("no agent endpoint is configured for this app")) }
        let turn: A2UITurn
        if apiName == "agent.send" {
            let m = args["message"]
            turn = conversation.send((flattenOptional(m) as? String) ?? JSON.stringify(m ?? ""))
        } else {
            guard let action = asMap(args["action"])?.copy(), action["name"] is String else {
                return .reply(errorResponse("agent.action requires an \"action\" with a \"name\""))
            }
            if !(action["timestamp"] is String) { action["timestamp"] = isoTimestamp(Date().timeIntervalSince1970 * 1000) }
            if !isMap(action["context"]) { action["context"] = JSONObject() }
            turn = conversation.sendAction(action)
        }
        return .turn(turn, key: key, registry: registry, conversation: conversation)
    case "a2ui.dataModel":
        let surfaceId = (args["surfaceId"] as? String) ?? ""
        guard let conversation = registry.get(key), !surfaceId.isEmpty else { return .reply(Typed.NULL_RESPONSE) }
        return .reply(valueResponse(conversation.dataModel(surfaceId)))
    default:
        return .reply(Typed.NULL_RESPONSE)
    }
}

/**
 * `agent.send {agent, conversation?, message}` → `{conversationId, conversation}`
 * (once the agent named the conversation); `agent.action {agent, conversation?,
 * action}` → the same; `a2ui.dataModel {conversation, surfaceId}` → the
 * surface's current data model. `conversation` is the conversation key the
 * widgets use (default `agent:<agent>`), so guest code and `A2UISurface`
 * widgets share conversations.
 */
@MainActor
public func handleAgentHostCall(_ services: ElpianServices, _ apiName: String, _ payload: String) async -> String {
    switch startAgentHostCall(services, apiName, payload) {
    case .reply(let s):
        return s
    case .turn(let turn, let key, let registry, _):
        let conversationId = await turn.conversationId.value()
        registry.invalidate()
        return Typed.makeResponse("object", JSONObject([("conversationId", conversationId), ("conversation", key)]))
    }
}

/**
 * The synchronous form for callers that cannot await (no TypeScript
 * counterpart): `a2ui.dataModel` answers in full; `agent.send` / `agent.action`
 * start the turn and answer with the conversation id known so far (nil for a
 * new conversation).
 */
public func handleAgentHostCallNow(_ services: ElpianServices, _ apiName: String, _ payload: String) -> String {
    switch startAgentHostCall(services, apiName, payload) {
    case .reply(let s):
        return s
    case .turn(let turn, let key, let registry, let conversation):
        turn.conversationId.then { [weak registry] _ in registry?.invalidate() }
        return Typed.makeResponse("object", JSONObject([("conversationId", conversation.conversationId), ("conversation", key)]))
    }
}
