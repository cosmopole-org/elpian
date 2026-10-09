import Foundation

/**
 * A server-driven page — the port of `NextjsServerWidget`, `NextjsBridge`'s
 * envelope handling, `NextjsAuthConfig` / token stores and
 * `ClientCompRouting` (the Dart files under flutter/lib/src/integrations; session/nextjs.ts).
 *
 * It loads render envelopes from a Next.js (or any Elpian-speaking) server,
 * keeps the previous screen painted while the next route loads, resolves
 * `clientComp` nodes onto persistent QuickJS VMs (each re-rendering only its
 * own scope), runs page scripts (`jsCode` / `vmAstJson`), routes UI events to
 * the right VM, handles `NextjsLink` / `NextjsForm` navigation and
 * submission, server navigation directives, auth token capture, refresh and
 * retry, and the `fetch` / `submit` / `navigate` / `mountFragment` host APIs.
 */

// ============================================================================
// Envelope
// ============================================================================

public struct NextjsEnvelopeException: MessageError, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { "Error: \(message)" }
}

public struct NextjsRenderEnvelope {
    public var component: JSONObject
    public var stylesheet: JSONObject?
    public var meta: JSONObject?
    public var navigation: JSONObject?
    public var clientComponents: JSONObject?
    public var jsCode: String?
    public var vmAstJson: String?
    public var jsEntryFunction: String?

    public init(component: JSONObject, stylesheet: JSONObject? = nil, meta: JSONObject? = nil, navigation: JSONObject? = nil,
                clientComponents: JSONObject? = nil, jsCode: String? = nil, vmAstJson: String? = nil, jsEntryFunction: String? = nil) {
        self.component = component
        self.stylesheet = stylesheet
        self.meta = meta
        self.navigation = navigation
        self.clientComponents = clientComponents
        self.jsCode = jsCode
        self.vmAstJson = vmAstJson
        self.jsEntryFunction = jsEntryFunction
    }
}

public func envelopeFromJson(_ json: JSONObject) throws -> NextjsRenderEnvelope {
    guard let component = asMap(json["component"]) else {
        throw NextjsEnvelopeException("Next.js payload must contain a \"component\" object that matches Elpian JSON.")
    }
    func obj(_ k: String) throws -> JSONObject? {
        guard let v = flattenOptional(json[k]) else { return nil }
        guard let m = asMap(v) else { throw NextjsEnvelopeException("\"\(k)\" must be a JSON object when provided.") }
        return m
    }
    func str(_ k: String) throws -> String? {
        guard let v = flattenOptional(json[k]) else { return nil }
        guard let s = v as? String else { throw NextjsEnvelopeException("\"\(k)\" must be a string when provided.") }
        return s
    }
    return NextjsRenderEnvelope(
        component: component,
        stylesheet: try obj("stylesheet"),
        meta: try obj("meta"),
        navigation: try obj("navigation"),
        clientComponents: try obj("clientComponents"),
        jsCode: try str("jsCode"),
        vmAstJson: try str("vmAstJson"),
        jsEntryFunction: try str("jsEntryFunction")
    )
}

public func buildRouteRequest(_ route: String, props: JSONObject? = nil, context: JSONObject? = nil) -> JSONObject {
    let out = JSONObject([("route", route)])
    if let p = props { out["props"] = p }
    if let c = context { out["context"] = c }
    return out
}

// ============================================================================
// Auth
// ============================================================================

public protocol NextjsTokenStore: AnyObject {
    var accessToken: String? { get }
    var refreshToken: String? { get }
    var hasSession: Bool { get }
    func ensureReady() async
    func save(access: String?, refresh: String?)
    func clear()
}

public final class InMemoryTokenStore: NextjsTokenStore {
    private var access: String?
    private var refresh: String?

    public init() {}

    public var accessToken: String? { access }
    public var refreshToken: String? { refresh }
    public var hasSession: Bool { !(access ?? "").isEmpty }

    public func ensureReady() async {}

    public func save(access: String? = nil, refresh: String? = nil) {
        if let a = access { self.access = a }
        if let r = refresh { self.refresh = r }
    }

    public func clear() {
        access = nil
        refresh = nil
    }
}

/** Persisted through the platform's key-value storage (UserDefaults / SharedPreferences / localStorage). */
public final class PlatformTokenStore: NextjsTokenStore {
    public let namespace: String
    private var access: String?
    private var refresh: String?
    private var ready = false

    public init(_ namespace: String = "elpian") {
        self.namespace = namespace
    }

    private var accessKey: String { "\(namespace)_access_token" }
    private var refreshKey: String { "\(namespace)_refresh_token" }
    public var accessToken: String? { access }
    public var refreshToken: String? { refresh }
    public var hasSession: Bool { !(access ?? "").isEmpty }

    public func ensureReady() async {
        if ready { return }
        ready = true
        // Persistence unavailable (no platform): degrade to in-memory.
        guard hasPlatform() else { return }
        let p = platform()
        access = p.storageGet(accessKey)
        refresh = p.storageGet(refreshKey)
    }

    public func save(access: String? = nil, refresh: String? = nil) {
        let p = platform()
        if let a = access {
            self.access = a
            p.storageSet(accessKey, a)
        }
        if let r = refresh {
            self.refresh = r
            p.storageSet(refreshKey, r)
        }
    }

    public func clear() {
        let p = platform()
        access = nil
        refresh = nil
        p.storageSet(accessKey, nil)
        p.storageSet(refreshKey, nil)
    }
}

public struct NextjsAuthConfig {
    public var store: NextjsTokenStore
    public var loginRoute: String
    public var refreshRoute: String
    public var bearerScheme: String

    public init(store: NextjsTokenStore, loginRoute: String, refreshRoute: String, bearerScheme: String) {
        self.store = store
        self.loginRoute = loginRoute
        self.refreshRoute = refreshRoute
        self.bearerScheme = bearerScheme
    }
}

public func nextjsAuthConfig(store: NextjsTokenStore? = nil, loginRoute: String? = nil, refreshRoute: String? = nil,
                             bearerScheme: String? = nil) -> NextjsAuthConfig {
    NextjsAuthConfig(
        store: store ?? PlatformTokenStore(),
        loginRoute: loginRoute ?? "/auth",
        refreshRoute: refreshRoute ?? "/auth/refresh",
        bearerScheme: bearerScheme ?? "Bearer"
    )
}

// ============================================================================
// Client-component handler routing
// ============================================================================

public enum ClientCompRouting {
    public static let separator = "::"

    public static func namespaced(_ mountId: String, _ fn: String) -> String { "\(mountId)::\(fn)" }

    public struct Route: Equatable {
        public var mountId: String
        public var fn: String
    }

    public static func parse(_ handler: String) -> Route? {
        let idx = jsIndexOf(handler, "::")
        if idx <= 0 { return nil }
        return Route(mountId: jsSubstring(handler, 0, idx), fn: jsSubstring(handler, idx + 2))
    }

    /** Prefix every un-namespaced handler in [node] with [mountId] (in place). */
    @discardableResult
    public static func namespaceHandlers(_ node: JSONObject, _ mountId: String) -> JSONObject {
        if let events = asMap(node["events"]) {
            let ns = JSONObject()
            for (k, v) in events {
                if let s = v as? String, !s.isEmpty, !s.contains("::") { ns[k] = namespaced(mountId, s) } else { ns[k] = v }
            }
            node["events"] = ns
        }
        if var children = asArray(node["children"]) {
            var replaced = false
            for (i, c) in children.enumerated() {
                guard let m = asMap(c) else { continue }
                namespaceHandlers(m, mountId)
                // A Swift dictionary child is swapped for the edited object so the edit lands in place.
                if !(flattenOptional(c) is JSONObject) {
                    children[i] = m
                    replaced = true
                }
            }
            if replaced { node["children"] = children }
        }
        return node
    }
}

// ============================================================================
// Session
// ============================================================================

/** The loader's `{ props, headers }`. */
public struct NextjsLoadOptions {
    public var props: JSONObject?
    public var headers: [String: String]?

    public init(props: JSONObject? = nil, headers: [String: String]? = nil) {
        self.props = props
        self.headers = headers
    }
}

public typealias NextjsPayloadLoader = (_ route: String, _ opts: NextjsLoadOptions) async throws -> JSONObject

/** `onScriptExecuted`'s `{ route, kind, output }`; kind is `js` or `vmAst`. */
public struct NextjsScriptResult {
    public var route: String
    public var kind: String
    public var output: String

    public func toJson() -> JSONObject { JSONObject([("route", route), ("kind", kind), ("output", output)]) }
}

public struct NextjsSessionOptions {
    public var route: String
    public var serverBaseUrl: String?
    public var endpoint: String?
    /** `routePath` or `apiEndpoint`. */
    public var requestMode: String
    public var loader: NextjsPayloadLoader?
    public var props: JSONObject?
    public var headers: [String: String]?
    public var auth: NextjsAuthConfig?
    public var timeoutMs: Double?
    public var onScriptExecuted: ((_ result: NextjsScriptResult) -> Void)?
    public var onScriptError: ((_ error: Error) -> Void)?
    /** The route changed (for host back-stack / URL sync). */
    public var onRouteChanged: ((_ route: String) -> Void)?
    /** A tap on a clickable Scene3D node not handled by the page VM. */
    public var onSceneTap: ((_ props: JSONObject) -> Void)?
    public var surface: SurfaceOptions?

    public init(route: String, serverBaseUrl: String? = nil, endpoint: String? = nil, requestMode: String = "routePath",
                loader: NextjsPayloadLoader? = nil, props: JSONObject? = nil, headers: [String: String]? = nil,
                auth: NextjsAuthConfig? = nil, timeoutMs: Double? = nil,
                onScriptExecuted: ((_ result: NextjsScriptResult) -> Void)? = nil, onScriptError: ((_ error: Error) -> Void)? = nil,
                onRouteChanged: ((_ route: String) -> Void)? = nil, onSceneTap: ((_ props: JSONObject) -> Void)? = nil,
                surface: SurfaceOptions? = nil) {
        self.route = route
        self.serverBaseUrl = serverBaseUrl
        self.endpoint = endpoint
        self.requestMode = requestMode
        self.loader = loader
        self.props = props
        self.headers = headers
        self.auth = auth
        self.timeoutMs = timeoutMs
        self.onScriptExecuted = onScriptExecuted
        self.onScriptError = onScriptError
        self.onRouteChanged = onRouteChanged
        self.onSceneTap = onSceneTap
        self.surface = surface
    }
}

private final class LiveClientComp {
    let mountId: String
    let vm: VmRuntimeClient
    let style: JSONObject?
    var timer: VmTimerHostApi?
    var latest: JSONObject?
    var dirty: Bool

    init(_ mountId: String, _ vm: VmRuntimeClient, _ style: JSONObject?) {
        self.mountId = mountId
        self.vm = vm
        self.style = style
        dirty = false
    }
}

private let HOST_OK = #"{"type":"i16","data":{"value":1}}"#

private struct PackedScript {
    var jsCode: String
    var jsEntryFunction: String
}

private func nowMillis() -> Int { Int(Date().timeIntervalSince1970 * 1000) }

public final class NextjsSession {
    public let options: NextjsSessionOptions
    public private(set) var surface: ElpianSurface!
    private var currentRoute: String
    private var history: [String] = []
    private var lastScriptSignature: String?
    private var scriptRendered: JSONObject?
    private var lastEnvelopeComponent: JSONObject?
    private var previousComponent: JSONObject?
    private var clientComponentCache: [String: JSONObject] = [:]
    private var pageVm: VmRuntimeClient?
    private var pageTimers: VmTimerHostApi?
    private var liveComps: [String: LiveClientComp] = [:]
    private var liveOrder: [String] = []
    private var compSeq = 0
    private var loadGeneration = 0
    private var payload: JSONObject?
    private var loadError: Error?
    private var loading = true
    private var lastStylesheetKey: String?
    private var disposed = false

    /** Loads, scripts and guest calls run here; cancelled on dispose. */
    public let scope = TaskScope()

    public init(_ surfaceId: String, _ options: NextjsSessionOptions) throws {
        if options.loader == nil && (options.serverBaseUrl ?? "").isEmpty {
            throw ElpianError("Either provide loader or serverBaseUrl for automatic Next.js loading.")
        }
        self.options = options
        currentRoute = options.route
        // Server-relative resources ("/icons/x.png") resolve against the server ORIGIN.
        let origin = originOf(options.serverBaseUrl)
        var given = options.surface ?? SurfaceOptions()
        let host = copyEngineHost(given.host)
        let givenBaseUrl = given.host?.baseUrl
        host.navigate = { [weak self] href, replace in self?.navigate(href, replace) }
        host.submitForm = { [weak self] action, values in await self?.handleFormSubmit(action, values) }
        host.sceneTap = { [weak self] props in
            guard let self = self else { return }
            self.scope.launch { [weak self] in await self?.dispatchSceneTap(props) }
        }
        host.baseUrl = { givenBaseUrl?() ?? origin }
        given.document = true
        given.host = host
        surface = ElpianSurface(surfaceId, given)
        surface.engine.services.events.onGlobalEvent { [weak self] e in
            guard let self = self else { return }
            self.scope.launch { [weak self] in await self?.routeEvent(e) }
        }
        scope.launch { [weak self] in await self?.load() }
    }

    public var route: String { currentRoute }

    public var canGoBack: Bool { !history.isEmpty }

    // ---------------------------------------------------------------------------
    // Navigation
    // ---------------------------------------------------------------------------

    public func navigate(_ route: String, _ replace: Bool = false) {
        if currentRoute == route && !replace { return }
        scope.launch { [weak self] in await self?.disposePageVm() }
        if !replace { history.append(currentRoute) }
        currentRoute = route
        beginReload()
    }

    @discardableResult
    public func back() -> Bool {
        if history.isEmpty { return false }
        scope.launch { [weak self] in await self?.disposePageVm() }
        currentRoute = history.removeLast()
        beginReload()
        return true
    }

    public func refresh() {
        scope.launch { [weak self] in await self?.disposePageVm() }
        beginReload()
    }

    private func beginReload() {
        // Keep the screen just rendered as the loading backdrop.
        previousComponent = scriptRendered ?? lastEnvelopeComponent ?? previousComponent
        scriptRendered = nil
        lastEnvelopeComponent = nil
        lastScriptSignature = nil
        options.onRouteChanged?(currentRoute)
        scope.launch { [weak self] in await self?.load() }
    }

    private func applyServerNavigation(_ nav: JSONObject?) {
        guard let nav = nav, !nav.isEmpty else { return }
        if jsBool(nav["back"]) == true {
            microtask { $0.back() }
            return
        }
        if jsBool(nav["refresh"]) == true {
            microtask { $0.refresh() }
            return
        }
        let to = nav["redirectTo"] != nil ? jsString(nav["redirectTo"]) : ""
        if !to.isEmpty {
            let replace = jsBool(nav["replace"]) == true
            if to != currentRoute || replace { microtask { $0.navigate(to, replace) } }
        }
    }

    // ---------------------------------------------------------------------------
    // Loading
    // ---------------------------------------------------------------------------

    @MainActor
    private func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        loading = true
        loadError = nil
        paint()
        do {
            let p = try await loadPayload()
            if generation != loadGeneration || disposed { return }
            payload = p
            loading = false
            onPayload()
        } catch is CancellationError {
            return
        } catch {
            if generation != loadGeneration || disposed { return }
            loading = false
            loadError = error
            paint()
        }
    }

    private func defaultLoader() -> NextjsPayloadLoader {
        options.loader ?? { [weak self] r, o in
            guard let self = self else { throw CancellationError() }
            return try await self.httpLoader(r, o)
        }
    }

    @MainActor
    private func loadPayload() async throws -> JSONObject {
        await disposeClientComps()
        compSeq = 0
        await options.auth?.store.ensureReady()
        let loader = defaultLoader()
        var p = try await loader(currentRoute, NextjsLoadOptions(props: options.props, headers: options.headers))
        captureAuth(p)
        if let auth = options.auth, options.loader == nil {
            if let nav = asMap(p["navigation"]), jsString(nav["redirectTo"] ?? "") == auth.loginRoute, !(auth.store.refreshToken ?? "").isEmpty {
                if await tryRefresh() {
                    p = try await httpLoader(currentRoute, NextjsLoadOptions(props: options.props, headers: options.headers))
                    captureAuth(p)
                }
            }
        }
        let envelope = try envelopeFromJson(p)
        let component = await resolveClientComponentNodes(envelope.component, envelope.clientComponents)
        let out = p.copy()
        out["component"] = component
        return out
    }

    private func onPayload() {
        guard let p = payload else { return }
        let envelope: NextjsRenderEnvelope
        do {
            envelope = try envelopeFromJson(p)
        } catch {
            loadError = error
            paint()
            return
        }
        lastEnvelopeComponent = envelope.component
        triggerScriptExecution(envelope)
        applyServerNavigation(envelope.navigation)
        if let sheet = envelope.stylesheet {
            let key = stableKey(sheet)
            if key != lastStylesheetKey {
                lastStylesheetKey = key
                surface.engine.loadStylesheet(sheet)
            }
        }
        paint()
    }

    /** Put the current state on the surface (FutureBuilder.build). */
    private func paint() {
        if disposed { return }
        let s = surface!
        if loading {
            if let fallback = previousComponent {
                // The previous screen with a thin progress bar on top.
                s.decorate = { content in
                    w(
                        "stack",
                        ["fit": "loose"],
                        [
                            content,
                            w(
                                "positioned",
                                ["top": 0.0, "left": 0.0, "right": 0.0],
                                child: w(
                                    "control",
                                    [
                                        "kind": "progress",
                                        "view": JSONObject([
                                            ("variant", "linear"),
                                            ("value", nil),
                                            ("strokeWidth", 2.0),
                                            ("colors", JSONObject([("indicator", M3.primary), ("track", M3.secondaryContainer)])),
                                        ]),
                                    ]
                                )
                            ),
                        ]
                    )
                }
                s.setContent(fallback)
            } else {
                s.decorate = nil
                s.setOverlay(loadingIndicator())
            }
            return
        }
        s.decorate = nil
        if let err = loadError {
            s.setOverlay(
                w(
                    "align",
                    ["alignment": Alignment(x: 0, y: 0)],
                    child: w("text", ["text": "Next.js payload error on \"\(currentRoute)\": \(errorText(err))", "align": "center"])
                )
            )
            return
        }
        if payload == nil {
            s.setOverlay(w("align", ["alignment": Alignment(x: 0, y: 0)], child: w("text", ["text": "Next.js payload was empty."])))
            return
        }
        foldClientCompRenders()
        s.setContent(scriptRendered ?? lastEnvelopeComponent)
    }

    // ---------------------------------------------------------------------------
    // HTTP
    // ---------------------------------------------------------------------------

    private func buildUrl(_ route: String) -> String {
        let base = TRAILING_SLASHES.replace(options.serverBaseUrl ?? "", with: "")
        if route.hasPrefix("http://") || route.hasPrefix("https://") { return route }
        if route.isEmpty || route == "/" { return base }
        return base + (route.hasPrefix("/") ? route : "/\(route)")
    }

    private func authHeaders() -> [String: String] {
        guard let a = options.auth, let t = a.store.accessToken, !t.isEmpty else { return [:] }
        return ["authorization": "\(a.bearerScheme) \(t)"]
    }

    private func request(_ req: FetchRequest) async throws -> FetchResponse {
        var r = req
        if r.timeoutMs == nil { r.timeoutMs = options.timeoutMs ?? 120000 }
        return try await platform().fetch(r)
    }

    private func httpLoader(_ route: String, _ o: NextjsLoadOptions) async throws -> JSONObject {
        if (options.serverBaseUrl ?? "").isEmpty { throw ElpianError("serverBaseUrl is required when no custom loader is provided.") }
        if options.requestMode == "routePath" {
            let url = buildUrl(route)
            var headers: [String: String] = [:]
            headers["accept"] = "application/vnd.elpian+json, application/json"
            headers["x-elpian-route"] = route
            if let props = o.props, !props.isEmpty { headers["x-elpian-props"] = JSON.stringify(props) }
            for (k, v) in authHeaders() { headers[k] = v }
            for (k, v) in o.headers ?? [:] { headers[k] = v }
            let res = try await request(FetchRequest(url: url, method: "GET", headers: headers))
            if res.status < 200 || res.status >= 300 { throw ElpianError("Next.js route \(url) returned HTTP \(res.status): \(res.body)") }
            guard let decoded = asMap(try JSON.parse(res.body)) else { throw ElpianError("Next.js route response must decode to a JSON object.") }
            return decoded
        }
        let url = buildUrl(options.endpoint ?? "/api/elpian-render")
        var headers: [String: String] = [:]
        headers["content-type"] = "application/json"
        for (k, v) in authHeaders() { headers[k] = v }
        for (k, v) in o.headers ?? [:] { headers[k] = v }
        let res = try await request(FetchRequest(url: url, method: "POST", headers: headers, body: JSON.stringify(buildRouteRequest(route, props: o.props))))
        if res.status < 200 || res.status >= 300 { throw ElpianError("Next.js endpoint \(url) returned HTTP \(res.status): \(res.body)") }
        guard let decoded = asMap(try JSON.parse(res.body)) else { throw ElpianError("Next.js payload must decode to a JSON object.") }
        return decoded
    }

    private func postJson(_ route: String, _ body: Any?) async throws -> JSONObject {
        var headers: [String: String] = [:]
        headers["content-type"] = "application/json"
        headers["accept"] = "application/vnd.elpian+json, application/json"
        headers["x-elpian-route"] = route
        for (k, v) in authHeaders() { headers[k] = v }
        for (k, v) in options.headers ?? [:] { headers[k] = v }
        let res = try await request(FetchRequest(url: buildUrl(route), method: "POST", headers: headers, body: JSON.stringify(body)))
        guard let decoded = asMap(try JSON.parse(res.body)) else { throw ElpianError("Action response must decode to a JSON object.") }
        return decoded
    }

    private func captureAuth(_ envelope: JSONObject) {
        guard let a = options.auth, let m = asMap(envelope["meta"]) else { return }
        if jsBool(m["clearAuth"]) == true {
            a.store.clear()
            return
        }
        if m.has("auth") {
            let auth = m["auth"]
            if let am = asMap(auth) {
                a.store.save(
                    access: am["accessToken"] != nil ? jsString(am["accessToken"]) : nil,
                    refresh: am["refreshToken"] != nil ? jsString(am["refreshToken"]) : nil
                )
            } else if auth == nil {
                a.store.clear()
            }
        }
    }

    private func tryRefresh() async -> Bool {
        guard let a = options.auth, let rt = a.store.refreshToken, !rt.isEmpty else { return false }
        do {
            let env = try await postJson(a.refreshRoute, JSONObject([("refreshToken", rt)]))
            if let meta = asMap(env["meta"]), let am = asMap(meta["auth"]), am["accessToken"] != nil {
                a.store.save(access: jsString(am["accessToken"]), refresh: am["refreshToken"] != nil ? jsString(am["refreshToken"]) : nil)
                return true
            }
        } catch is CancellationError {
            return false
        } catch {
            /* fall through */
        }
        a.store.clear()
        return false
    }

    private func handleFormSubmit(_ action: String, _ values: JSONObject) async -> String? {
        do {
            let env = try await postJson(action, values)
            captureAuth(env)
            if let nav = asMap(env["navigation"]), !nav.isEmpty {
                applyServerNavigation(nav)
                return nil
            }
            if let inline = firstText(env["component"]) { return inline }
            if let c = asMap(env["component"]) { setScriptRendered(c) }
            return nil
        } catch is CancellationError {
            return nil
        } catch {
            return "Request failed: \(errorText(error))"
        }
    }

    // ---------------------------------------------------------------------------
    // Client components
    // ---------------------------------------------------------------------------

    @MainActor
    private func resolveClientComponentNodes(_ node: JSONObject, _ packed: JSONObject?) async -> JSONObject {
        let type = jsString(node["type"] ?? "")
        if type == "clientComp" || type == "client-component" {
            if let resolved = await resolveClientComponentNode(node, packed) { return resolved }
            return JSONObject([("type", "Text"), ("props", JSONObject([("text", "Failed to execute client component jsCode")]))])
        }
        if let children = asArray(node["children"]) {
            var out: [Any?] = []
            for c in children {
                if let m = asMap(c) { out.append(await resolveClientComponentNodes(m, packed)) } else { out.append(c) }
            }
            let copy = node.copy()
            copy["children"] = out
            return copy
        }
        return node
    }

    @MainActor
    private func resolveClientComponentNode(_ node: JSONObject, _ packed: JSONObject?) async -> JSONObject? {
        let props = asMap(node["props"])?.copy() ?? JSONObject()
        var jsCode: String? = node["jsCode"] != nil ? jsString(node["jsCode"]) : (props["jsCode"] != nil ? jsString(props["jsCode"]) : nil)
        var entry = jsString(node["jsEntryFunction"] ?? props["jsEntryFunction"] ?? "MainComponent")
        if (jsCode ?? "").isEmpty {
            let p = findPackedScript(node, props, packed)
            jsCode = p?.jsCode
            entry = p?.jsEntryFunction ?? entry
        }
        if (jsCode ?? "").isEmpty && !(options.serverBaseUrl ?? "").isEmpty {
            let f = await fetchClientComponentScript(node, props)
            jsCode = f?.jsCode
            entry = f?.jsEntryFunction ?? entry
        }
        guard let code = jsCode, !code.isEmpty else { return nil }
        return await mountClientComponent(code, entry, props, node["style"])
    }

    @MainActor
    private func mountClientComponent(_ jsCode: String, _ entryFunction: String, _ props: JSONObject, _ style: Any?) async -> JSONObject? {
        let mountId = "cc\(compSeq)"
        compSeq += 1
        let machineId = "nextjs-\(mountId)-\(nowMillis())\(Int.random(in: 0..<1000))"
        let vm: QuickJsVm
        do {
            vm = try await QuickJsVm.fromCode(machineId, jsCode)
        } catch {
            platform().log(.warn, "NextjsSession: clientComp \"\(mountId)\" create failed: \(jsErrorString(error))")
            return nil
        }
        let record = LiveClientComp(mountId, vm, asMap(style))
        setLive(record)

        var firstDone = false
        let firstRender = AsyncLatch()
        let handler = HostHandler(
            services: surface.engine.services,
            options: HostHandlerOptions(
                onRender: { [weak self] view, _ in
                    record.latest = ClientCompRouting.namespaceHandlers(view, mountId)
                    if !firstDone {
                        firstDone = true
                        firstRender.complete()
                    } else {
                        record.dirty = true
                        self?.paint()
                    }
                },
                onPrintln: { m in platform().log(.info, "NextjsSession[\(mountId)]: \(m)") }
            )
        )
        let timer = VmTimerHostApi({ [weak vm] fn, input in
            guard let vm = vm else { return }
            if let input = input { _ = try await vm.callFunctionWithInput(fn, input) } else { _ = try await vm.callFunction(fn) }
        }, onError: { m in platform().log(.warn, "NextjsSession[\(mountId) timer]: \(m)") })
        record.timer = timer
        vm.registerHostHandlers(hostHandlers(handler, timer) { [weak record] in record?.vm })
        do {
            _ = try await vm.run()
            _ = try await vm.callFunctionWithInput(entryFunction, JSON.stringify(props))
            var timeout: Int?
            if !firstRender.isCompleted {
                timeout = platform().setTimeout({
                    platform().log(.warn, "NextjsSession: clientComp \"\(mountId)\" first render timed out")
                    firstRender.complete()
                }, 3000)
            }
            await firstRender.wait()
            if let t = timeout { platform().clearTimeout(t) }
        } catch {
            if !(error is CancellationError) {
                platform().log(.warn, "NextjsSession: clientComp \"\(mountId)\" exec failed: \(jsErrorString(error))")
            }
            removeLive(mountId)
            await disposeComp(record)
            return nil
        }
        record.dirty = false
        return JSONObject([
            ("type", ScopeContract.type),
            ("key", "\(mountId)__scope"),
            ("props", JSONObject()),
            ("children", [compContent(record)] as [Any?]),
        ])
    }

    private func setLive(_ r: LiveClientComp) {
        if liveComps[r.mountId] == nil { liveOrder.append(r.mountId) }
        liveComps[r.mountId] = r
    }

    private func removeLive(_ mountId: String) {
        liveComps.removeValue(forKey: mountId)
        liveOrder.removeAll { $0 == mountId }
    }

    private func compContent(_ record: LiveClientComp) -> JSONObject {
        let node = (record.latest ?? JSONObject([("type", "div")])).copy()
        node["key"] = record.mountId
        if let style = record.style {
            if let own = asMap(node["style"]) {
                let merged = style.copy()
                merged.assign(own)
                node["style"] = merged
            } else {
                node["style"] = style
            }
        }
        return node
    }

    private func foldClientCompRenders() {
        if liveComps.isEmpty { return }
        guard let tree = scriptRendered ?? lastEnvelopeComponent else { return }
        var any = false
        for id in liveOrder {
            guard let r = liveComps[id], r.dirty, r.latest != nil else { continue }
            if ScopePatch.replaceByKey(tree, r.mountId, compContent(r)) {
                r.dirty = false
                any = true
            }
        }
        if any { scriptRendered = tree }
    }

    @MainActor
    private func disposeClientComps() async {
        let comps = liveOrder.compactMap { liveComps[$0] }
        liveComps.removeAll()
        liveOrder.removeAll()
        for c in comps { await disposeComp(c) }
    }

    private func findPackedScript(_ node: JSONObject, _ props: JSONObject, _ packed: JSONObject?) -> PackedScript? {
        guard let packed = packed, !packed.isEmpty else { return nil }
        for key in lookupKeys(node, props) {
            if let p = normalizePacked(packed[key]) { return p }
        }
        let values = packed.values
        return values.count == 1 ? normalizePacked(values[0]) : nil
    }

    @MainActor
    private func fetchClientComponentScript(_ node: JSONObject, _ props: JSONObject) async -> PackedScript? {
        let keys = lookupKeys(node, props)
        for k in keys {
            if let c = clientComponentCache[k], let p = normalizePacked(c) { return p }
        }
        do {
            var headers: [String: String] = [:]
            headers["content-type"] = "application/json"
            headers["accept"] = "application/json"
            for (k, v) in authHeaders() { headers[k] = v }
            for (k, v) in options.headers ?? [:] { headers[k] = v }
            let res = try await request(
                FetchRequest(
                    url: buildUrl(options.endpoint ?? "/api/elpian-client-component"),
                    method: "POST",
                    headers: headers,
                    body: JSON.stringify(JSONObject([("route", currentRoute), ("lookupKeys", keys.map { $0 as Any? }), ("componentNode", node)]))
                )
            )
            if res.status < 200 || res.status >= 300 { return nil }
            guard let d = asMap(try JSON.parse(res.body)) else { return nil }
            if let cc = asMap(d["clientComponents"]) {
                for (k, v) in cc {
                    if let m = asMap(v) {
                        clientComponentCache[k] = m.copy()
                    } else if let s = v as? String {
                        clientComponentCache[k] = JSONObject([("jsCode", s)])
                    }
                }
            }
            if let direct = normalizePacked(d) {
                for k in keys { clientComponentCache[k] = JSONObject([("jsCode", direct.jsCode), ("jsEntryFunction", direct.jsEntryFunction)]) }
                return direct
            }
            for k in keys {
                if let c = clientComponentCache[k], let p = normalizePacked(c) { return p }
            }
        } catch {
            /* resolved inline or not at all */
        }
        return nil
    }

    // ---------------------------------------------------------------------------
    // Page scripts
    // ---------------------------------------------------------------------------

    private func triggerScriptExecution(_ envelope: NextjsRenderEnvelope) {
        if (envelope.jsCode ?? "").isEmpty && (envelope.vmAstJson ?? "").isEmpty { return }
        let signature = "\(currentRoute)|\(envelope.jsEntryFunction ?? "MainComponent")|\(envelope.jsCode ?? "")|\(envelope.vmAstJson ?? "")"
        if lastScriptSignature == signature { return }
        lastScriptSignature = signature
        scope.launch { [weak self] in await self?.executeEnvelopeScripts(envelope) }
    }

    @MainActor
    private func executeEnvelopeScripts(_ envelope: NextjsRenderEnvelope) async {
        do {
            if let js = envelope.jsCode, !js.isEmpty { try await runPageScript(js, envelope.jsEntryFunction ?? "MainComponent") }
            if let ast = envelope.vmAstJson, !ast.isEmpty {
                try await ElpianVm.initialize()
                guard let vm = try await ElpianVm.fromAst("nextjs-ast-\(nowMillis())", ast) else {
                    throw ElpianError("Failed to create Elpian VM from AST payload.")
                }
                vm.registerHostHandler("render") { [weak self] _, payload in
                    self?.setScriptRendered(decodeRenderPayload(payload))
                    return HostReply.of(HOST_OK)
                }
                do {
                    let output = try await vm.run()
                    setScriptRendered(decodeRenderPayload(output))
                    options.onScriptExecuted?(NextjsScriptResult(route: currentRoute, kind: "vmAst", output: output))
                } catch {
                    await vm.dispose()
                    throw error
                }
                await vm.dispose()
            }
        } catch is CancellationError {
            return
        } catch {
            options.onScriptError?(error)
            platform().log(.warn, "NextjsSession script execution error: \(jsErrorString(error))")
        }
    }

    @MainActor
    private func runPageScript(_ jsCode: String, _ entryFunction: String) async throws {
        await disposePageVm()
        let vm = try await QuickJsVm.fromCode("nextjs-page-\(nowMillis())", jsCode)
        pageVm = vm
        let handler = HostHandler(
            services: surface.engine.services,
            options: HostHandlerOptions(
                onRender: { [weak self] view, scopeKey in self?.applyClientRender(view, scopeKey) },
                onPrintln: { m in platform().log(.info, "NextjsSession[page]: \(m)") }
            )
        )
        let timers = VmTimerHostApi({ [weak self, weak vm] fn, input in
            guard let self = self, let vm = vm, self.pageVm != nil else { return }
            if let input = input { _ = try await vm.callFunctionWithInput(fn, input) } else { _ = try await vm.callFunction(fn) }
        }, onError: { m in platform().log(.warn, "NextjsSession[page timer]: \(m)") })
        pageTimers = timers
        vm.registerHostHandlers(hostHandlers(handler, timers) { [weak self] in self?.pageVm })
        _ = try await vm.run()
        if !entryFunction.isEmpty {
            let initial = try await vm.callFunction(entryFunction)
            // Only a returned component tree seeds the render (pollers return null).
            if let seeded = decodeRenderPayload(initial), seeded["type"] != nil, scriptRendered == nil { setScriptRendered(seeded) }
        }
        options.onScriptExecuted?(NextjsScriptResult(route: currentRoute, kind: "js", output: ""))
    }

    private func hostHandlers(_ handler: HostHandler, _ timers: VmTimerHostApi, _ vm: @escaping () -> VmRuntimeClient?) -> [String: HostCallHandler] {
        var out: [String: HostCallHandler] = [:]
        for api in HostApiCatalog.allHostApiNames { out[api] = { n, p in HostReply.of(handler.handleHostCall(n, p)) } }
        for api in HostApiCatalog.timerApiNames { out[api] = { n, p in HostReply.of(timers.handle(n, p)) } }
        // Async work is started and acknowledged at once: guests call askHost
        // synchronously and receive results through their onData/onResult callbacks.
        out["fetch"] = { [weak self] _, p in
            let target = vm()
            self?.scope.launch { [weak self] in await self?.hostFetch(target, p) }
            return HostReply.of(HOST_OK)
        }
        out["submit"] = { [weak self] _, p in
            let target = vm()
            self?.scope.launch { [weak self] in await self?.hostSubmit(target, p) }
            return HostReply.of(HOST_OK)
        }
        out["navigate"] = { [weak self] _, p in HostReply.of(self?.hostNavigate(p) ?? HOST_OK) }
        out["mountFragment"] = { [weak self] _, p in
            let target = vm()
            self?.scope.launch { [weak self] in await self?.hostMountFragment(target, p) }
            return HostReply.of(HOST_OK)
        }
        return out
    }

    @MainActor
    private func hostFetch(_ vm: VmRuntimeClient?, _ payload: String) async {
        do {
            let args = firstArgMap(payload)
            let route = args["route"] != nil ? jsString(args["route"]) : ""
            if route.isEmpty { return }
            let envelope = try await defaultLoader()(route, NextjsLoadOptions(headers: options.headers))
            let onData = args["onData"] != nil ? jsString(args["onData"]) : ""
            if !onData.isEmpty, let vm = vm { _ = try await vm.callFunctionWithInput(onData, JSON.stringify(envelope)) }
        } catch is CancellationError {
            return
        } catch {
            platform().log(.warn, "NextjsSession[fetch]: \(jsErrorString(error))")
        }
    }

    @MainActor
    private func hostSubmit(_ vm: VmRuntimeClient?, _ payload: String) async {
        do {
            let args = firstArgMap(payload)
            let route = args["route"] != nil ? jsString(args["route"]) : ""
            if route.isEmpty { return }
            let env = try await postJson(route, args["body"])
            captureAuth(env)
            if let nav = asMap(env["navigation"]), !nav.isEmpty { applyServerNavigation(nav) }
            let onResult = args["onResult"] != nil ? jsString(args["onResult"]) : ""
            if !onResult.isEmpty, let vm = vm { _ = try await vm.callFunctionWithInput(onResult, JSON.stringify(env)) }
        } catch is CancellationError {
            return
        } catch {
            platform().log(.warn, "NextjsSession[submit]: \(jsErrorString(error))")
        }
    }

    @MainActor
    private func hostMountFragment(_ vm: VmRuntimeClient?, _ payload: String) async {
        do {
            let args = firstArgMap(payload)
            let route = args["route"] != nil ? jsString(args["route"]) : ""
            if route.isEmpty { return }
            let scopeKey: String? = args["scopeKey"] != nil ? jsString(args["scopeKey"]) : nil
            let envelope = try await defaultLoader()(route, NextjsLoadOptions(headers: options.headers))
            captureAuth(envelope)
            if let nav = asMap(envelope["navigation"]), !nav.isEmpty { applyServerNavigation(nav) }
            if let component = asMap(envelope["component"]) {
                let resolved = await resolveClientComponentNodes(component, asMap(envelope["clientComponents"]))
                applyClientRender(resolved, scopeKey)
            }
            let onData = args["onData"] != nil ? jsString(args["onData"]) : ""
            if !onData.isEmpty, let vm = vm { _ = try await vm.callFunctionWithInput(onData, JSON.stringify(envelope)) }
        } catch is CancellationError {
            return
        } catch {
            platform().log(.warn, "NextjsSession[mountFragment]: \(jsErrorString(error))")
        }
    }

    private func hostNavigate(_ payload: String) -> String {
        let nav = firstArgMap(payload)
        if !nav.isEmpty { applyServerNavigation(nav) }
        return HOST_OK
    }

    private func applyClientRender(_ view: JSONObject, _ scopeKey: String?) {
        if disposed { return }
        guard let key = ScopePatch.normalizeKey(scopeKey) else {
            setScriptRendered(view)
            return
        }
        guard let next = ScopePatch.applyBounded(scriptRendered ?? lastEnvelopeComponent, view, key) else {
            platform().log(.debug, "NextjsSession: scoped render targeted missing scope \"\(key)\"; keeping current screen.")
            return
        }
        setScriptRendered(next)
    }

    private func setScriptRendered(_ component: JSONObject?) {
        guard let component = component, !disposed else { return }
        scriptRendered = component
        if !loading { paint() }
    }

    @MainActor
    private func disposePageVm() async {
        pageTimers?.dispose()
        pageTimers = nil
        let vm = pageVm
        pageVm = nil
        // Best effort.
        await vm?.dispose()
    }

    // ---------------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------------

    @MainActor
    private func routeEvent(_ event: ElpianEvent) async {
        guard let nodeId = event.currentTarget, !nodeId.isEmpty else { return }
        guard let handler = surface.engine.services.events.getNode(nodeId)?.events?[event.type] as? String, !handler.isEmpty else { return }
        // `<mountId>::<fn>` belongs to a live client component; otherwise the page VM.
        let r = ClientCompRouting.parse(handler)
        let target: VmRuntimeClient? = r != nil ? liveComps[r!.mountId]?.vm : pageVm
        let fn = r?.fn ?? handler
        guard let vm = target else { return }
        let input = JSONObject([("type", event.type)])
        if let pos = event.position {
            input["x"] = pos.x
            input["y"] = pos.y
        } else if event.hasValue {
            input["value"] = event.value
        }
        do {
            _ = try await vm.callFunctionWithInput(fn, JSON.stringify(input))
        } catch is CancellationError {
            return
        } catch {
            do {
                _ = try await vm.callFunction(fn)
            } catch is CancellationError {
                return
            } catch {
                platform().log(.warn, "NextjsSession: event handler \"\(handler)\" failed: \(jsErrorString(error))")
            }
        }
    }

    @MainActor
    private func dispatchSceneTap(_ props: JSONObject) async {
        if let onSceneTap = options.onSceneTap {
            onSceneTap(props)
            return
        }
        if let vm = pageVm {
            do {
                _ = try await vm.callFunctionWithInput("__onSceneTap", JSON.stringify(props))
                return
            } catch is CancellationError {
                return
            } catch {
                /* fall through to navigation */
            }
        }
        if let href = props["panelHref"] as? String, !href.isEmpty { navigate(href) }
    }

    public func viewportChanged() {
        surface.viewportChanged()
    }

    @MainActor
    public func dispose() async {
        if disposed { return }
        disposed = true
        loadGeneration += 1
        await disposePageVm()
        await disposeClientComps()
        surface.dispose()
        scope.cancel()
    }

    /** `scheduleMicrotask`: run [fn] on the next main-actor turn. */
    private func microtask(_ fn: @escaping (NextjsSession) -> Void) {
        scope.launch { [weak self] in
            guard let self = self else { return }
            fn(self)
        }
    }
}

@MainActor
private func disposeComp(_ c: LiveClientComp) async {
    c.timer?.dispose()
    c.timer = nil
    // Best effort.
    await c.vm.dispose()
}

private let LOOKUP_FIELDS = ["clientComponentKey", "componentKey", "componentId", "id", "name", "path", "componentPath", "module"]

private func lookupKeys(_ node: JSONObject, _ props: JSONObject) -> [String] {
    var keys: [String] = []
    for src in [node, props] {
        for f in LOOKUP_FIELDS {
            let t = src[f] != nil ? jsTrim(jsString(src[f])) : ""
            if !t.isEmpty && !keys.contains(t) { keys.append(t) }
        }
    }
    if keys.isEmpty { keys.append("anon-\(hashString(stableKey(node)))-\(hashString(stableKey(props)))") }
    return keys
}

/** `(Math.imul(31, h) + charCode) | 0`, then `Math.abs`. */
private func hashString(_ s: String) -> Int64 {
    var h: Int32 = 0
    for ch in s.utf16 { h = (31 &* h) &+ Int32(ch) }
    return abs(Int64(h))
}

private func normalizePacked(_ raw: Any?) -> PackedScript? {
    let raw = flattenOptional(raw)
    if let s = raw as? String, !jsTrim(s).isEmpty { return PackedScript(jsCode: jsTrim(s), jsEntryFunction: "MainComponent") }
    if let m = asMap(raw) {
        let js = m["jsCode"] != nil ? jsString(m["jsCode"]) : ""
        if jsTrim(js).isEmpty { return nil }
        let entry = m["jsEntryFunction"] != nil ? jsString(m["jsEntryFunction"]) : ""
        return PackedScript(jsCode: js, jsEntryFunction: entry.isEmpty ? "MainComponent" : entry)
    }
    return nil
}

private func decodeRenderPayload(_ payload: String) -> JSONObject? {
    // A plain string is not a render payload.
    guard let m = asMap(try? JSON.parse(payload)) else { return nil }
    return asMap(m["component"]) ?? m
}

private func firstArgMap(_ payload: String) -> JSONObject {
    guard var parsed = (try? JSON.parse(payload)) ?? nil else { return JSONObject() }
    if let a = asArray(parsed), !a.isEmpty { parsed = a[0] ?? NSNull() }
    if let s = parsed as? String {
        guard let p = (try? JSON.parse(s)) ?? nil else { return JSONObject() }
        parsed = p
    }
    return asMap(parsed) ?? JSONObject()
}

private func firstText(_ node: Any?) -> String? {
    guard let m = asMap(node) else { return nil }
    if let props = asMap(m["props"]), let t = props["text"] as? String, jsLength(jsTrim(t)) > 2, !t.contains("✕") { return t }
    if let children = asArray(m["children"]) {
        for c in children {
            if let r = firstText(c) { return r }
        }
    }
    return nil
}

private let ORIGIN = JSRegex(#"^([a-zA-Z][\w+.-]*://[^/?#]+)"#)
private let TRAILING_SLASHES = JSRegex("/+$")

private func originOf(_ url: String?) -> String? {
    guard let url = url, !url.isEmpty else { return nil }
    return ORIGIN.exec(url)?[1] ?? nil
}
