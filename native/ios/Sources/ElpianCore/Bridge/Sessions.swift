import Foundation

/**
 * One registry of the sessions a host app has open, addressed by surface id
 * and driven by JSON (bridge/sessions.ts) — the API every embedding speaks:
 * the iOS and Android hosts and the Expo module.
 *
 * Session kinds:
 *   - `json`      — render Elpian JSON directly (setContent / patch).
 *   - `miniapp`   — a mini app on one of the three runtimes (ElpianVmWidget).
 *   - `superapp`  — a governed third-party mini app (MiniAppHost.launch + mount).
 *   - `stream`    — a view driven by pushed / streamed commands.
 *   - `nextjs`    — a server-driven page (NextjsServerWidget).
 *   - `server`    — a server-rendered component (ServerComponent).
 *   - `agent`     — a full-screen conversation with an app agent (A2UI surfaces,
 *                   prose and a chat input); methods send / action / conversation.
 *
 * Events flow back through the `emit(surface, event, payload)` sink:
 *   ready, error, println, updateApp, routeChanged, scriptExecuted,
 *   scriptError, streamDone, command, sceneTap, callRefused, unservicedApi,
 *   navigate, result (async call results: `{requestId, ok, value | error}`,
 *   from [callAsync]), a2uiText, a2uiAction, done (agent sessions).
 *
 * Payloads are JSON values ([JSONObject]s, arrays, strings, Doubles, Bools, nil).
 */
public typealias EmitSink = (_ surface: String, _ event: String, _ payload: Any?) -> Void

public final class SessionEntry {
    public let kind: String
    public let surface: ElpianSurface
    public let dispose: @MainActor () async -> Void
    public let call: @MainActor (_ method: String, _ args: [Any?]) async throws -> Any?
    public let viewportChanged: () -> Void

    public init(kind: String, surface: ElpianSurface, dispose: @escaping @MainActor () async -> Void,
                call: @escaping @MainActor (_ method: String, _ args: [Any?]) async throws -> Any?, viewportChanged: @escaping () -> Void) {
        self.kind = kind
        self.surface = surface
        self.dispose = dispose
        self.call = call
        self.viewportChanged = viewportChanged
    }
}

public struct SessionException: MessageError, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { "Error: \(message)" }
}

public final class SessionRegistry {
    private let emit: EmitSink
    private var entries: [String: SessionEntry] = [:]
    private var order: [String] = []

    /** Where [openAsync] / [callAsync] / [closeAsync] run; cancelled by [shutdown]. */
    public let scope = TaskScope()

    public init(emit: @escaping EmitSink) {
        self.emit = emit
    }

    public func has(_ surfaceId: String) -> Bool { entries[surfaceId] != nil }

    public func get(_ surfaceId: String) -> SessionEntry? { entries[surfaceId] }

    /** Open a session of [kind] on [surfaceId] (closing any session already there). */
    @MainActor
    public func open(_ kind: String, _ surfaceId: String, _ options: JSONObject) async throws {
        await close(surfaceId)
        let sink = self.emit
        let emit: (String, Any?) -> Void = { event, payload in sink(surfaceId, event, payload) }
        let surfaceHost = EngineHost(
            navigate: { href, replace in emit("navigate", JSONObject([("href", href), ("replace", replace)])) },
            openUrl: { url in platform().openUrl(url) },
            sceneTap: { props in emit("sceneTap", props) },
            baseUrl: { options["baseUrl"] as? String }
        )
        let surfaceOpts = SurfaceOptions(document: jsBool(options["document"]) == true, host: surfaceHost)
        let entry: SessionEntry
        switch kind {
        case "json":
            let surface = ElpianSurface(surfaceId, surfaceOpts)
            if jsTruthy(options["stylesheet"]) { surface.engine.loadStylesheet(options["stylesheet"]) }
            if let view = asMap(options["view"]) { surface.setContent(view) }
            entry = SessionEntry(
                kind: kind,
                surface: surface,
                dispose: { surface.dispose() },
                call: { method, args in
                    switch method {
                    case "setContent":
                        surface.setContent(asMap(arg(args, 0)))
                        return nil
                    case "patch":
                        // A scoped render, bounded like the VM's.
                        guard let view = asMap(arg(args, 0)) else { throw SessionException("patch requires a view object") }
                        let key = arg(args, 1).map { jsString($0) }
                        let next = ScopePatch.applyBounded(surface.currentContent, view, key)
                        if let n = next { surface.setContent(n) }
                        return next != nil
                    case "merge":
                        surface.setContent(deepMerge(surface.currentContent ?? JSONObject(), asMap(arg(args, 0)) ?? JSONObject()))
                        return nil
                    case "loadStylesheet":
                        surface.engine.loadStylesheet(arg(args, 0))
                        surface.scheduleRender()
                        return nil
                    case "clearStylesheets":
                        surface.engine.clearStylesheets()
                        surface.scheduleRender()
                        return nil
                    default:
                        throw SessionException("json session has no method \(method)")
                    }
                },
                viewportChanged: { surface.viewportChanged() }
            )
        case "miniapp":
            let ast = options["ast"]
            let session = MiniAppSession(
                surfaceId,
                MiniAppOptions(
                    machineId: jsString(options["machineId"] ?? surfaceId),
                    runtime: runtimeOf(options["runtime"]),
                    code: options["code"] as? String,
                    astJson: (options["astJson"] as? String) ?? (isMap(ast) ? JSON.stringify(ast) : nil),
                    bytecodeBase64: options["bytecodeBase64"] as? String,
                    stylesheet: options["stylesheet"],
                    entryFunction: options["entryFunction"] as? String,
                    entryInput: jsonText(options["entryInput"]),
                    hostEnvironment: asMap(options["hostEnvironment"]),
                    onPrintln: { m in emit("println", m) },
                    onUpdateApp: { d in emit("updateApp", d) },
                    onError: { m in emit("error", m) },
                    onCallRefused: { api in emit("callRefused", api) },
                    onUnservicedApi: { api, advertised in emit("unservicedApi", JSONObject([("api", api), ("advertised", advertised)])) },
                    onReady: { emit("ready", nil) },
                    showDefaultStates: jsBool(options["showDefaultStates"]) != false,
                    surface: surfaceOpts
                )
            )
            // Where this app's agents live: A2UISurface widgets and the agent.* host APIs default to it.
            if options["baseUrl"] is String || options["appId"] is String {
                a2uiRegistry(session.surface.engine.services).defaults = A2UIDefaults(
                    baseUrl: options["baseUrl"] as? String,
                    appId: options["appId"] as? String,
                    headers: stringMap(options["headers"])
                )
            }
            entry = SessionEntry(
                kind: kind,
                surface: session.surface,
                dispose: { await session.dispose() },
                call: { method, args in
                    let gov = session.runtime?.governor
                    switch method {
                    case "callFunction": return try await session.callFunction(jsString(arg(args, 0)), jsonText(arg(args, 1)))
                    case "usage": return try await gov?.usage().toJson()
                    case "state": return try await gov?.state().toJson()
                    case "pause":
                        try await gov?.pause()
                        return nil
                    case "resume":
                        try await gov?.resumeExecution()
                        return nil
                    case "terminate":
                        try await gov?.terminate()
                        return nil
                    case "setLimits":
                        try await gov?.setLimits(Limits.fromJson(asMap(arg(args, 0)) ?? JSONObject()))
                        return nil
                    case "sandbox":
                        try await gov?.sandbox(capsOf(arg(args, 0)))
                        return nil
                    case "view": return session.view
                    default: throw SessionException("miniapp session has no method \(method)")
                    }
                },
                viewportChanged: { session.viewportChanged() }
            )
            session.scope.launch { await session.start() }
        case "superapp":
            let manifest = MiniAppManifests.fromJson(asMap(options["manifest"]) ?? JSONObject())
            let grant = grantOf(options["grant"])
            let host: MiniAppHost
            do {
                host = try await MiniAppHost.launch(manifest: manifest, grant: grant, source: jsString(options["source"] ?? ""))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                emit("error", errorText(error))
                return
            }
            let session = try await host.mount(
                surfaceId,
                MountOptions(
                    stylesheet: options["stylesheet"],
                    entryInput: jsonText(options["entryInput"]),
                    onPrintln: { m in emit("println", m) },
                    onUpdateApp: { d in emit("updateApp", d) },
                    onError: { m in emit("error", m) },
                    onCallRefused: { api in emit("callRefused", api) },
                    onUnservicedApi: { api, advertised in emit("unservicedApi", JSONObject([("api", api), ("advertised", advertised)])) },
                    onReady: { [weak host] in
                        emit("ready", JSONObject([("denied", (host?.policy.deniedRequests ?? []).map { $0.wireName as Any? })]))
                    },
                    showDefaultStates: jsBool(options["showDefaultStates"]) != false,
                    surface: surfaceOpts
                )
            )
            entry = SessionEntry(
                kind: kind,
                surface: session.surface,
                dispose: { await host.dispose() },
                call: { method, args in
                    switch method {
                    case "callFunction": return try await session.callFunction(jsString(arg(args, 0)), jsonText(arg(args, 1)))
                    case "usage": return try await host.usage().toJson()
                    case "branchUsage": return try await host.branchUsage().toJson()
                    case "pressure": return try await host.pressure()
                    case "policy":
                        return JSONObject([
                            ("capabilities", host.policy.capabilities.map { $0.wireName as Any? }),
                            ("denied", host.policy.deniedRequests.map { $0.wireName as Any? }),
                            ("limits", Limits.toJson(host.policy.limits)),
                            ("mayHostChildren", host.policy.mayHostChildren),
                        ])
                    case "spawnChild":
                        let child = try await host.spawnChild(
                            manifest: MiniAppManifests.fromJson(asMap(arg(args, 0)) ?? JSONObject()),
                            source: jsString(arg(args, 1) ?? ""),
                            grant: jsTruthy(arg(args, 2)) ? grantOf(arg(args, 2)) : nil
                        )
                        return JSONObject([("machineId", child.machineId)])
                    case "pause":
                        try await host.governor.pause()
                        return nil
                    case "resume":
                        try await host.governor.resumeExecution()
                        return nil
                    case "terminate":
                        try await host.governor.terminate()
                        return nil
                    default: throw SessionException("superapp session has no method \(method)")
                    }
                },
                viewportChanged: { session.viewportChanged() }
            )
        case "stream":
            let session = StreamSession(
                surfaceId,
                StreamSessionOptions(
                    initialStylesheet: asMap(options["initialStylesheet"]),
                    onCommand: { c in emit("command", c.toJson()) },
                    onStreamDone: { emit("streamDone", nil) },
                    onError: { m in emit("error", m) },
                    defaultAnimationDurationMs: jsNumber(options["defaultAnimationDurationMs"]),
                    defaultAnimationCurve: options["defaultAnimationCurve"] as? String,
                    surface: surfaceOpts
                )
            )
            if let request = asMap(options["request"]) { session.connect(fetchRequestOf(request)) }
            entry = SessionEntry(
                kind: kind,
                surface: session.surface,
                dispose: { session.dispose() },
                call: { method, args in
                    switch method {
                    case "push":
                        session.push(arg(args, 0))
                        return nil
                    case "error":
                        session.error(arg(args, 0))
                        return nil
                    case "done":
                        session.done()
                        return nil
                    case "connect":
                        session.connect(fetchRequestOf(asMap(arg(args, 0)) ?? JSONObject()))
                        return nil
                    default: throw SessionException("stream session has no method \(method)")
                    }
                },
                viewportChanged: { session.surface.viewportChanged() }
            )
        case "nextjs":
            var auth: NextjsAuthConfig?
            if let am = asMap(options["auth"]) {
                auth = nextjsAuthConfig(
                    store: jsBool(am["persist"]) == false ? InMemoryTokenStore() : PlatformTokenStore(jsString(am["namespace"] ?? "elpian")),
                    loginRoute: am["loginRoute"] as? String,
                    refreshRoute: am["refreshRoute"] as? String,
                    bearerScheme: am["bearerScheme"] as? String
                )
            }
            let nextHost = copyEngineHost(surfaceHost)
            nextHost.navigate = nil
            var nextSurface = surfaceOpts
            nextSurface.host = nextHost
            let session = try NextjsSession(
                surfaceId,
                NextjsSessionOptions(
                    route: jsString(options["route"] ?? "/"),
                    serverBaseUrl: options["serverBaseUrl"] as? String,
                    endpoint: options["endpoint"] as? String,
                    requestMode: (options["requestMode"] as? String) == "apiEndpoint" ? "apiEndpoint" : "routePath",
                    props: asMap(options["props"]),
                    headers: stringMap(options["headers"]),
                    auth: auth,
                    timeoutMs: jsNumber(options["timeoutMs"]),
                    onScriptExecuted: { r in emit("scriptExecuted", r.toJson()) },
                    onScriptError: { e in emit("scriptError", jsErrorString(e)) },
                    onRouteChanged: { route in emit("routeChanged", route) },
                    onSceneTap: jsBool(options["handleSceneTaps"]) == true ? { p in emit("sceneTap", p) } : nil,
                    surface: nextSurface
                )
            )
            entry = SessionEntry(
                kind: kind,
                surface: session.surface,
                dispose: { await session.dispose() },
                call: { method, args in
                    switch method {
                    case "navigate":
                        session.navigate(jsString(arg(args, 0)), jsBool(arg(args, 1)) == true)
                        return nil
                    case "back": return session.back()
                    case "refresh":
                        session.refresh()
                        return nil
                    case "route": return session.route
                    case "canGoBack": return session.canGoBack
                    default: throw SessionException("nextjs session has no method \(method)")
                    }
                },
                viewportChanged: { session.viewportChanged() }
            )
        case "server":
            let client = ElpianServerClient(
                jsString(options["baseUrl"] ?? ""),
                jsString(options["appId"] ?? ""),
                ElpianNetPolicy.fromManifest(options["netPolicy"]),
                options["authorization"] != nil ? jsString(options["authorization"]) : nil,
                jsNumber(options["timeoutMs"]) ?? 15000
            )
            let session = ServerComponentSession(
                surfaceId,
                ServerComponentOptions(
                    client: client,
                    name: jsString(options["name"] ?? ""),
                    args: asMap(options["args"]) ?? JSONObject(),
                    nativeIslands: stringMap(options["nativeIslands"]),
                    revalidateMs: jsNumber(options["revalidateMs"]),
                    surface: surfaceOpts
                )
            )
            entry = SessionEntry(
                kind: kind,
                surface: session.surface,
                dispose: {
                    session.dispose()
                    client.close()
                },
                call: { method, args in
                    switch method {
                    case "update":
                        session.update(asMap(arg(args, 0)) ?? JSONObject())
                        return nil
                    case "refresh":
                        await session.fetch()
                        return nil
                    case "callAction": return await client.callAction(jsString(arg(args, 0)), asMap(arg(args, 1)) ?? JSONObject()).toJson()
                    case "unresolvedIslands": return session.unresolvedIslands().map { $0 as Any? }
                    default: throw SessionException("server session has no method \(method)")
                    }
                },
                viewportChanged: { session.surface.viewportChanged() }
            )
        case "agent":
            var agentSurfaceOpts = surfaceOpts
            agentSurfaceOpts.document = true
            let surface = ElpianSurface(surfaceId, agentSurfaceOpts)
            if jsTruthy(options["stylesheet"]) { surface.engine.loadStylesheet(options["stylesheet"]) }
            let agent = jsString(options["agent"] ?? "")
            let registry = a2uiRegistry(surface.engine.services)
            registry.defaults = A2UIDefaults(
                baseUrl: jsString(options["baseUrl"] ?? ""),
                appId: jsString(options["appId"] ?? ""),
                headers: stringMap(options["headers"])
            )
            let conversation = registry.conversation("session") {
                A2UIConversation(A2UIConversationOptions(endpoint: registry.endpoint(agent), conversationId: options["conversationId"] as? String))
            }
            let on: (String, @escaping (ElpianEvent) -> Void) -> (String, ElpianEventListener) = { name, fn in (name, fn) }
            let events: [(String, ElpianEventListener)] = [
                on("a2uiText") { e in emit("a2uiText", e.value) },
                on("a2uiAction") { e in emit("a2uiAction", e.value) },
                on("a2uiError") { e in emit("error", (asMap(e.value)?["message"] as? String) ?? "agent error") },
                on("a2uiDone") { e in emit("done", e.value) },
            ]
            surface.setContent(a2uiElement("A2UISurface", JSONObject([
                ("agent", agent),
                ("conversation", "session"),
                ("prompt", options["prompt"] as? String),
                ("chat", jsBool(options["chat"]) != false),
                ("showText", true),
                ("style", JSONObject([("padding", 12.0)])),
            ]), events: events))
            entry = SessionEntry(
                kind: kind,
                surface: surface,
                dispose: {
                    registry.dispose()
                    surface.dispose()
                },
                call: { method, args in
                    switch method {
                    case "send":
                        let id = await conversation.send(jsString(arg(args, 0) ?? "")).conversationId.value()
                        return JSONObject([("conversationId", id)])
                    case "action":
                        let raw = arg(args, 0)
                        let parsed: Any? = (raw as? String).map { JSON.parseOrNil($0) } ?? raw
                        guard let given = asMap(parsed), given["name"] is String else { throw SessionException("action needs a \"name\"") }
                        let action = JSONObject([("timestamp", isoTimestamp(Date().timeIntervalSince1970 * 1000)), ("context", JSONObject())])
                        action.assign(given)
                        let id = await conversation.sendAction(action).conversationId.value()
                        return JSONObject([("conversationId", id)])
                    case "conversation":
                        return conversation.describe()
                    default:
                        throw SessionException("agent session has no method \(method)")
                    }
                },
                viewportChanged: { surface.viewportChanged() }
            )
        default:
            throw SessionException("unknown session kind \"\(kind)\"")
        }
        if entries[surfaceId] == nil { order.append(surfaceId) }
        entries[surfaceId] = entry
    }

    @MainActor
    public func call(_ surfaceId: String, _ method: String, _ args: [Any?]) async throws -> Any? {
        guard let e = entries[surfaceId] else { throw SessionException("no session on surface \"\(surfaceId)\"") }
        return try await e.call(method, args)
    }

    public func dispatchViewEvent(_ surfaceId: String, _ event: ViewEvent) {
        surfaceById(surfaceId)?.dispatchViewEvent(event)
    }

    public func viewportChanged(_ surfaceId: String) {
        if let e = entries[surfaceId] { e.viewportChanged() } else { surfaceById(surfaceId)?.viewportChanged() }
    }

    /** An image finished loading: every surface showing it relayouts. */
    public func imageLoaded(_ src: String, _ width: Double, _ height: Double) {
        for id in order { entries[id]?.surface.imageLoaded(src, width, height) }
    }

    /** Fonts loaded / changed: re-measure text everywhere. */
    public func invalidateText() {
        for id in order {
            guard let e = entries[id] else { continue }
            e.surface.invalidateText()
            e.surface.scheduleRender()
        }
    }

    @MainActor
    public func close(_ surfaceId: String) async {
        guard let e = entries.removeValue(forKey: surfaceId) else { return }
        order.removeAll { $0 == surfaceId }
        await e.dispose()
    }

    @MainActor
    public func closeAll() async {
        for id in order { await close(id) }
    }

    // ---- fire-and-forget forms for hosts on the UI thread (no TS counterpart: TS callers await Promises) ----

    /** [open] on [scope]; a failure is emitted as `error`. */
    @discardableResult
    public func openAsync(_ kind: String, _ surfaceId: String, _ options: JSONObject) -> Task<Void, Never>? {
        scope.launch { [weak self] in
            guard let self = self else { return }
            do {
                try await self.open(kind, surfaceId, options)
            } catch is CancellationError {
                return
            } catch {
                self.emit(surfaceId, "error", errorText(error))
            }
        }
    }

    /** [call] on [scope]; the outcome is emitted as `result` `{requestId, ok, value | error}`. */
    @discardableResult
    public func callAsync(_ surfaceId: String, _ method: String, _ args: [Any?], _ requestId: Any?) -> Task<Void, Never>? {
        scope.launch { [weak self] in
            guard let self = self else { return }
            let payload: JSONObject
            do {
                let value = try await self.call(surfaceId, method, args)
                payload = JSONObject([("requestId", requestId), ("ok", true), ("value", value)])
            } catch is CancellationError {
                return
            } catch {
                payload = JSONObject([("requestId", requestId), ("ok", false), ("error", errorText(error))])
            }
            self.emit(surfaceId, "result", payload)
        }
    }

    @discardableResult
    public func closeAsync(_ surfaceId: String) -> Task<Void, Never>? {
        scope.launch { [weak self] in await self?.close(surfaceId) }
    }

    /** Close every session and stop the registry's scope. */
    @MainActor
    public func shutdown() async {
        await closeAll()
        scope.cancel()
    }
}

/** `args[i]` (nil past the end). */
private func arg(_ args: [Any?], _ i: Int) -> Any? { i < args.count ? flattenOptional(args[i]) : nil }

/** A string as is; any other value as JSON text; nil stays nil. */
private func jsonText(_ v: Any?) -> String? {
    guard let v = flattenOptional(v) else { return nil }
    if let s = v as? String { return s }
    return JSON.stringify(v)
}

/** A JSON object of strings (`String(v)` for each value). */
private func stringMap(_ v: Any?) -> [String: String]? {
    guard let m = asMap(v) else { return nil }
    var out: [String: String] = [:]
    for (k, x) in m { out[k] = jsString(x) }
    return out
}

private func runtimeOf(_ v: Any?) -> RuntimeKind {
    let s = flattenOptional(v) as? String
    return (s == "quickjs" || s == "quickJs") ? .quickjs : (s == "wasm" ? .wasm : .elpian)
}

private func capsOf(_ v: Any?) -> [ElpianCapability] {
    var out: [ElpianCapability] = []
    for x in asArray(v) ?? [] {
        if let c = capabilityFromWireName(jsString(x)), !out.contains(c) { out.append(c) }
    }
    return out
}

private func grantOf(_ v: Any?) -> MiniAppGrant {
    if (flattenOptional(v) as? String) == "trusted" { return MiniAppGrants.trusted }
    guard let m = asMap(v) else { return MiniAppGrants.untrusted }
    let base = (m["base"] as? String) == "trusted" ? MiniAppGrants.trusted : MiniAppGrants.untrusted
    return MiniAppGrant(
        capabilities: asArray(m["capabilities"]) != nil ? capsOf(m["capabilities"]) : base.capabilities,
        limits: asMap(m["limits"]).map { Limits.fromJson($0) } ?? base.limits,
        mayHostChildren: jsBool(m["mayHostChildren"]) ?? base.mayHostChildren,
        allowedApis: asArray(m["allowedApis"]).map { Set($0.map { jsString($0) }) } ?? base.allowedApis
    )
}

/** A `FetchRequest` from its JSON form (`{url, method?, headers?, body?, timeoutMs?}`). */
public func fetchRequestOf(_ j: JSONObject) -> FetchRequest {
    let body: String?
    if let b = flattenOptional(j["body"]) {
        body = (b as? String) ?? JSON.stringify(b)
    } else {
        body = nil
    }
    return FetchRequest(
        url: jsString(j["url"] ?? ""),
        method: (j["method"] as? String) ?? "GET",
        headers: stringMap(j["headers"]) ?? [:],
        body: body,
        timeoutMs: jsNumber(j["timeoutMs"])
    )
}
