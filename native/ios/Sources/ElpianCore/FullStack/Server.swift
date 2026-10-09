import Foundation

/**
 * Full-stack mini apps — ports of flutter/lib/src/fullstack/{server_client,
 * server_component}.dart (fullstack/server.ts): a mini app calling its own
 * server functions (`server.call`, `server.render`), brokered client
 * networking (`net.fetch` through the host's proxy under an
 * `ElpianNetPolicy`), streamed components, and server-rendered components
 * with islands.
 *
 * Islands are either lowering functions (props + server-rendered children →
 * widget) or host-registered native components (UIView / Android View / DOM
 * element / React Native component) rendered through the `native` view kind.
 */
public final class ElpianNetPolicy {
    /** `closed`, `open` or `brokered`. */
    public let mode: String
    public let allowlist: [String]

    private init(_ mode: String, _ allowlist: [String]) {
        self.mode = mode
        self.allowlist = allowlist
    }

    public static let closed = ElpianNetPolicy("closed", [])
    public static let open = ElpianNetPolicy("open", [])

    public static func brokered(_ allowlist: [String]) -> ElpianNetPolicy { ElpianNetPolicy("brokered", allowlist) }

    public static func fromManifest(_ value: Any?) -> ElpianNetPolicy {
        if (flattenOptional(value) as? String) == "open" { return open }
        if let m = asMap(value) {
            let allow = asArray(m["allow"]) ?? []
            return brokered(allow.compactMap { flattenOptional($0) as? String })
        }
        return closed
    }

    public func allows(_ url: String) -> Bool {
        if mode == "closed" { return false }
        if mode == "open" { return true }
        guard let host = hostOf(url), !host.isEmpty else { return false }
        return allowlist.contains { matches($0.lowercased(), host.lowercased()) }
    }
}

private func matches(_ entry: String, _ host: String) -> Bool {
    if entry.hasPrefix("*.") {
        let suffix = jsSubstring(entry, 2)
        let hl = jsLength(host)
        let sl = jsLength(suffix)
        return host != suffix && hl > sl && host.hasSuffix(suffix) && jsSubstring(host, hl - sl - 1, hl - sl) == "."
    }
    return host == entry
}

private let HOST_OF = JSRegex(#"^[a-zA-Z][\w+.-]*://(?:[^@/?#]*@)?(\[[^\]]+\]|[^:/?#]+)"#)

private func hostOf(_ url: String) -> String? { HOST_OF.exec(url)?[1] ?? nil }

public struct ServerCallResult {
    public var result: Any?
    public var error: String?

    public init(result: Any? = nil, error: String? = nil) {
        self.result = result
        self.error = error
    }

    public func toJson() -> JSONObject { error != nil ? JSONObject([("error", error)]) : JSONObject([("result", result)]) }
}

public struct ServerRenderResult {
    public var payload: JSONObject?
    public var error: String?

    public init(payload: JSONObject? = nil, error: String? = nil) {
        self.payload = payload
        self.error = error
    }
}

/** Receives a streamed component's frames. */
public protocol ServerStreamSink: AnyObject {
    func onFrame(_ frame: Any?)
    func onError(_ message: String)
    func onDone()
}

/** Splits a streamed component's body into NDJSON frames. */
private final class FrameReader: StreamHandlers {
    private let sink: ServerStreamSink
    private let appId: String
    private var buffer = ""
    var finish: () -> Void = {}

    init(_ sink: ServerStreamSink, _ appId: String) {
        self.sink = sink
        self.appId = appId
    }

    private func emit(_ line: String) {
        guard let d = try? JSON.parse(line) else {
            // A bad line is skipped; the stream keeps going.
            platform().log(.debug, "ElpianServerClient: \(appId) dropped an unparseable stream line")
            return
        }
        if let m = asMap(d), (m["action"] as? String) == "error" {
            sink.onError(jsString(m["message"] ?? "the stream failed"))
        } else {
            sink.onFrame(d)
        }
    }

    func onChunk(_ text: String) {
        // Chunk boundaries fall anywhere, including mid-line.
        buffer += text
        while true {
            let i = jsIndexOf(buffer, "\n")
            if i < 0 { break }
            let line = jsTrim(jsSubstring(buffer, 0, i))
            buffer = jsSubstring(buffer, i + 1)
            if !line.isEmpty { emit(line) }
        }
    }

    func onDone() {
        let tail = jsTrim(buffer)
        if !tail.isEmpty { emit(tail) }
        finish()
    }

    func onError(_ message: String) {
        sink.onError(
            TIME.test(message) ? "the stream timed out"
                : STATUS.test(message) ? "the stream could not be opened"
                : "the stream failed"
        )
        finish()
    }
}

private let TIME = JSRegex("time", ignoreCase: true)
private let STATUS = JSRegex("status|HTTP", ignoreCase: true)

/** Forwards a streamed component's frames to a stream session. */
private final class SessionSink: ServerStreamSink {
    weak var session: StreamSession?
    init(_ session: StreamSession) { self.session = session }
    func onFrame(_ frame: Any?) { session?.push(frame) }
    func onError(_ message: String) { session?.error(message) }
    func onDone() { session?.done() }
}

public final class ElpianServerClient {
    public let baseUrl: String
    public let appId: String
    public let netPolicy: ElpianNetPolicy
    public let authorization: String?
    public let timeoutMs: Double
    private var closed = false
    private var cancels: [Int: () -> Void] = [:]
    private var nextCancel = 0

    /** Where asynchronous host calls run; cancelled on [close]. */
    public let scope = TaskScope()

    public init(_ baseUrl: String, _ appId: String, _ netPolicy: ElpianNetPolicy = .closed, _ authorization: String? = nil, _ timeoutMs: Double = 15000) {
        self.baseUrl = baseUrl
        self.appId = appId
        self.netPolicy = netPolicy
        self.authorization = authorization
        self.timeoutMs = timeoutMs
    }

    /** Host handlers for a mini app runtime: `server.call`, `server.render`, `net.fetch`. */
    public var hostHandlers: [String: HostCallHandler] {
        [
            "server.call": deferred { c, p in await c.invoke(p, false) },
            "server.render": deferred { c, p in await c.invoke(p, true) },
            "net.fetch": deferred { c, p in await c.clientFetch(p) },
        ]
    }

    /** A handler that starts [work] on [scope] and replies with its result later. */
    private func deferred(_ work: @escaping @MainActor (ElpianServerClient, String) async -> String) -> HostCallHandler {
        { [weak self] _, p in
            guard let self = self else { return HostReply.of("null") }
            return HostReply.of(self.scope.async { [weak self] () async throws -> String in
                guard let self = self else { return "null" }
                return await work(self, p)
            })
        }
    }

    private func headers() -> [String: String] {
        var h = ["content-type": "application/json"]
        if let a = authorization, !a.isEmpty { h["authorization"] = a }
        return h
    }

    private func post(_ url: String, _ body: Any?) async throws -> FetchResponse {
        try await platform().fetch(FetchRequest(url: url, method: "POST", headers: headers(), body: JSON.stringify(body), timeoutMs: timeoutMs))
    }

    @MainActor
    private func invoke(_ payload: String, _ render: Bool) async -> String {
        let args = positional(payload)
        guard let name = (args.first ?? nil).flatMap({ flattenOptional($0) as? String }), !name.isEmpty else { return "null" }
        let body: Any? = args.count > 1 ? args[1] : JSONObject()
        let path = render ? "render" : "fn"
        // Percent-encoded so a guest-chosen name cannot change the path's shape.
        let url = "\(baseUrl)/apps/\(encodeURIComponent(appId))/\(path)/\(encodeURIComponent(name))"
        do {
            let res = try await post(url, body)
            if res.status != 200 { return typedError(errorMessage(res.body) ?? "the call failed") }
            let decoded = asMap(try JSON.parse(res.body))
            if let d = decoded, jsBool(d["ok"]) == true { return JSON.stringify(d["result"]) }
            return typedError(errorMessage(res.body) ?? "the call failed")
        } catch is CancellationError {
            return typedError("the call failed")
        } catch {
            let text = "\(error)"
            if TIMED_OUT.test(text) { return typedError("the server did not answer in time") }
            if UNREACHABLE.test(text) { return typedError("the server could not be reached") }
            platform().log(.warn, "ElpianServerClient: \(appId)/\(path) failed: \(error)")
            return typedError("the call failed")
        }
    }

    @MainActor
    private func clientFetch(_ payload: String) async -> String {
        guard let url = (positional(payload).first ?? nil).flatMap({ flattenOptional($0) as? String }) else { return "null" }
        // Refused locally without a round trip; the server would refuse it too.
        if !netPolicy.allows(url) { return typedError("the request was not permitted") }
        // Allowed requests still go through the host's broker (one policy, one audit trail).
        do {
            let res = try await post("\(baseUrl)/apps/\(appId)/proxy", JSONObject([("url", url)]))
            if res.status != 200 { return typedError("the request was not permitted") }
            if let d = asMap(try JSON.parse(res.body)), jsBool(d["ok"]) == true { return JSON.stringify(d["result"]) }
        } catch {
            /* fall through */
        }
        return typedError("the request was not permitted")
    }

    @MainActor
    public func renderComponent(_ name: String, _ args: JSONObject) async -> ServerRenderResult {
        let raw = await invoke(JSON.stringify([name, args] as [Any?]), true)
        if let m = asMap(try? JSON.parse(raw)) {
            if m["error"] != nil { return ServerRenderResult(error: errorOf(m["error"])) }
            return ServerRenderResult(payload: m)
        }
        return ServerRenderResult(error: "the server returned no payload")
    }

    @MainActor
    public func callAction(_ name: String, _ args: JSONObject) async -> ServerCallResult {
        let raw = await invoke(JSON.stringify([name, args] as [Any?]), false)
        do {
            let d = try JSON.parse(raw)
            if let m = asMap(d), m["error"] != nil { return ServerCallResult(error: errorOf(m["error"])) }
            return ServerCallResult(result: d)
        } catch {
            return ServerCallResult(error: "the call failed")
        }
    }

    /**
     * Stream a component: newline-delimited frames, each a stream command
     * (`{"action":"error"}` frames surface as errors). Returns a canceller.
     */
    @discardableResult
    public func streamComponent(_ name: String, _ args: JSONObject, _ sink: ServerStreamSink) -> () -> Void {
        if closed {
            sink.onError("the stream could not be opened")
            sink.onDone()
            return {}
        }
        let id = nextCancel
        nextCancel += 1
        var finished = false
        let reader = FrameReader(sink, appId)
        reader.finish = { [weak self] in
            if finished { return }
            finished = true
            self?.cancels.removeValue(forKey: id)
            sink.onDone()
        }
        let cancelStream = platform().fetchStream(
            FetchRequest(
                url: "\(baseUrl)/apps/\(encodeURIComponent(appId))/stream/\(encodeURIComponent(name))",
                method: "POST",
                headers: headers(),
                body: JSON.stringify(args),
                timeoutMs: timeoutMs
            ),
            reader
        )
        let cancel: () -> Void = {
            cancelStream()
            reader.finish()
        }
        if !finished { cancels[id] = cancel }
        return cancel
    }

    /** Show a streamed component on a surface (ElpianStreamWidget over streamComponent). */
    public func mountStream(_ surfaceId: String, _ name: String, _ args: JSONObject, _ options: StreamSessionOptions = StreamSessionOptions()) -> StreamSession {
        let session = StreamSession(surfaceId, options)
        let cancel = streamComponent(name, args, SessionSink(session))
        session.beforeDispose = { cancel() }
        return session
    }

    public func close() {
        closed = true
        let all = Array(cancels.values)
        for c in all { c() }
        scope.cancel()
    }
}

private let TIMED_OUT = JSRegex("timed? ?out", ignoreCase: true)
private let UNREACHABLE = JSRegex("network|connect|resolve|unreachable", ignoreCase: true)

private func errorOf(_ e: Any?) -> String {
    if let m = asMap(e) { return jsString(m["message"] ?? "the call failed") }
    return jsString(e)
}

private func positional(_ payload: String) -> [Any?] {
    guard let d = try? JSON.parse(payload) else { return [] }
    if let a = asArray(d) { return a }
    return [d]
}

private func errorMessage(_ body: String) -> String? {
    asMap(try? JSON.parse(body))?["error"] as? String
}

private func typedError(_ message: String) -> String {
    JSON.stringify(JSONObject([("error", JSONObject([("code", "unavailable"), ("message", message)]))]))
}

// ============================================================================
// ServerComponent
// ============================================================================

/** Builds an island from its props; server-rendered children arrive as `#children`. */
public typealias IslandBuilder = (_ props: JSONObject) -> W

public struct ServerComponentOptions {
    public var client: ElpianServerClient
    public var name: String
    public var args: JSONObject?
    /** Lowering-function islands. */
    public var islandBuilders: [String: IslandBuilder]?
    /** Islands rendered by host-registered native components, by island name → component name. */
    public var nativeIslands: [String: String]?
    /** Re-fetch interval (ms). */
    public var revalidateMs: Double?
    public var pending: W?
    public var errorBuilder: ((_ message: String) -> W)?
    public var surface: SurfaceOptions?

    public init(client: ElpianServerClient, name: String, args: JSONObject? = nil, islandBuilders: [String: IslandBuilder]? = nil,
                nativeIslands: [String: String]? = nil, revalidateMs: Double? = nil, pending: W? = nil,
                errorBuilder: ((_ message: String) -> W)? = nil, surface: SurfaceOptions? = nil) {
        self.client = client
        self.name = name
        self.args = args
        self.islandBuilders = islandBuilders
        self.nativeIslands = nativeIslands
        self.revalidateMs = revalidateMs
        self.pending = pending
        self.errorBuilder = errorBuilder
        self.surface = surface
    }
}

public final class ServerComponentSession {
    public let surface: ElpianSurface
    private var options: ServerComponentOptions
    private var payload: JSONObject?
    private var error: String?
    private var loading = true
    private var generation = 0
    private var timer: Int?
    private var disposed = false
    private var stylesheetKey: String?

    /** Fetches run here; cancelled on dispose. */
    public let scope = TaskScope()

    public init(_ surfaceId: String, _ options: ServerComponentOptions) {
        self.options = options
        surface = ElpianSurface(surfaceId, options.surface ?? SurfaceOptions())
        registerIslands()
        scope.launch { [weak self] in await self?.fetch() }
        scheduleRevalidation()
    }

    private func registerIslands() {
        let engine = surface.engine
        for (name, build) in options.islandBuilders ?? [:] {
            engine.registerWidget(name) { node, children, _ in
                let props = node.props.copy()
                if !children.isEmpty { props["#children"] = children }
                return build(props)
            }
        }
        for (name, component) in options.nativeIslands ?? [:] {
            engine.registerWidget(name) { node, children, _ in
                let onEvent: (ViewEvent) -> Void = { _ in }
                return w(
                    "native",
                    [
                        "component": component,
                        "componentProps": node.props.copy(),
                        "width": node.style?.width,
                        "height": node.style?.height,
                        "onEvent": onEvent,
                    ],
                    children
                )
            }
        }
    }

    /**
     * Change name/args/revalidation (didUpdateWidget). [next] holds the
     * changed fields by option name (`name`, `args`, `islandBuilders`,
     * `nativeIslands`, `revalidateMs`, `pending`, `errorBuilder`), as the TS
     * `Partial<ServerComponentOptions>` does.
     */
    public func update(_ next: JSONObject) {
        let prev = options
        var o = prev
        if next.has("name") { o.name = next["name"].map { jsString($0) } ?? prev.name }
        if next.has("args") { o.args = asMap(next["args"]) }
        if next.has("islandBuilders") { o.islandBuilders = next["islandBuilders"] as? [String: IslandBuilder] }
        if next.has("nativeIslands") {
            o.nativeIslands = asMap(next["nativeIslands"]).map { m in
                var out: [String: String] = [:]
                for (k, v) in m { out[k] = jsString(v) }
                return out
            }
        }
        if next.has("revalidateMs") { o.revalidateMs = jsNumber(next["revalidateMs"]) }
        if next.has("pending") { o.pending = next["pending"] as? W }
        if next.has("errorBuilder") { o.errorBuilder = next["errorBuilder"] as? (String) -> W }
        options = o
        registerIslands()
        let nextName = next["name"]
        let nextArgs = next["args"]
        if (nextName != nil && jsString(nextName) != prev.name) || (nextArgs != nil && !sameArgs(prev.args ?? JSONObject(), asMap(nextArgs) ?? JSONObject())) {
            scope.launch { [weak self] in await self?.fetch() }
        }
        if next.has("revalidateMs") && jsNumber(next["revalidateMs"]) != prev.revalidateMs { scheduleRevalidation() }
    }

    private func scheduleRevalidation() {
        if let t = timer { platform().clearTimeout(t) }
        timer = nil
        guard let interval = options.revalidateMs, interval > 0 else { return }
        var tick: (() -> Void)!
        tick = { [weak self] in
            guard let self = self, !self.disposed else { return }
            self.timer = platform().setTimeout(tick, interval)
            self.scope.launch { [weak self] in await self?.fetch() }
        }
        timer = platform().setTimeout(tick, interval)
    }

    @MainActor
    public func fetch() async {
        generation += 1
        let gen = generation
        // Only the first fetch shows the pending state; revalidation keeps the screen.
        if payload == nil {
            loading = true
            paint()
        }
        let result = await options.client.renderComponent(options.name, options.args ?? JSONObject())
        if disposed || gen != generation { return }
        loading = false
        if let e = result.error {
            error = e
        } else {
            // A failed revalidation keeps content that is already showing.
            error = nil
            payload = result.payload
        }
        paint()
    }

    /** Islands the payload declares that no builder handles. */
    public func unresolvedIslands() -> [String] {
        guard let declared = asMap(payload?["clientComponents"]) else { return [] }
        return declared.keys.filter { k in options.islandBuilders?[k] == nil && options.nativeIslands?[k] == nil }
    }

    private func paint() {
        if disposed { return }
        let s = surface
        func errorBox(_ m: String) -> W {
            options.errorBuilder?(m)
                ?? w("padding", ["padding": EdgeInsets(top: 12, right: 12, bottom: 12, left: 12)],
                     child: w("text", ["text": m, "style": TextStyle(color: 0xffb3261e)]))
        }
        guard let p = payload else {
            if let err = error {
                s.setOverlay(errorBox(err))
            } else if loading {
                s.setOverlay(options.pending ?? loadingIndicator())
            } else {
                s.setContent(nil)
            }
            return
        }
        guard let component = asMap(p["component"]) else {
            s.setOverlay(errorBox("the server component returned no component tree"))
            return
        }
        if let sheet = asMap(p["stylesheet"]) {
            let key = stableKey(sheet)
            if key != stylesheetKey {
                stylesheetKey = key
                s.engine.loadStylesheet(sheet)
            }
        }
        s.setContent(component)
    }

    public func dispose() {
        disposed = true
        if let t = timer { platform().clearTimeout(t) }
        scope.cancel()
        surface.dispose()
    }
}

/** `b[k] === a[k]` for every key: value equality for primitives, identity for objects. */
private func sameArgs(_ a: JSONObject, _ b: JSONObject) -> Bool {
    if a.count != b.count { return false }
    for k in a.keys {
        let x = flattenOptional(a[k])
        let y = flattenOptional(b[k])
        if x == nil || y == nil {
            if !(x == nil && y == nil && b.has(k)) { return false }
            continue
        }
        if let bx = jsBool(x) {
            if jsBool(y) != bx { return false }
        } else if let nx = jsNumber(x) {
            if jsNumber(y) != nx { return false }
        } else if let sx = x as? String {
            if (y as? String) != sx { return false }
        } else if !(type(of: x!) is AnyClass && type(of: y!) is AnyClass && (x! as AnyObject) === (y! as AnyObject)) {
            return false
        }
    }
    return true
}
