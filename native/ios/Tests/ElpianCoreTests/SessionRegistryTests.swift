import XCTest
@testable import ElpianCore

/** A JS sandbox that runs nothing: [script] maps each evaluated snippet to host calls and a result. */
private final class ScriptedSandbox: JsSandbox {
    let script: (_ code: String, _ host: (String, String) -> String) -> String
    var handler: ((String, String) -> String)?
    var evaluated: [String] = []
    var disposed = false

    init(_ script: @escaping (_ code: String, _ host: (String, String) -> String) -> String) {
        self.script = script
    }

    func setHostCallHandler(_ handler: @escaping (String, String) -> String) { self.handler = handler }

    func evaluate(_ code: String) throws -> String {
        evaluated.append(code)
        return script(code, handler!)
    }

    func dispose() { disposed = true }
}

/** The main thread's run loop as the tests drive it: queued timers and frames run when [drain] is awaited. */
private final class SessionFakePlatform: Platform, JsSandboxFactory {
    let name = "fake"
    var commits: [(String, [ViewOp])] = []
    var logs: [String] = []
    private var frames: [(Int, (Double) -> Void)] = []
    private var nextFrame = 1
    private var clock = 0.0
    var timers: [(handle: Int, at: Double, fn: () -> Void)] = []
    private var nextTimer = 1
    var streamHandlers: StreamHandlers?
    var streamRequest: FetchRequest?
    var streamCancelled = false
    var fetches: [FetchRequest] = []
    var fetchHandler: (FetchRequest) -> FetchResponse = { _ in FetchResponse(status: 404, headers: [:], body: "") }
    var sandboxScript: (_ code: String, _ host: (String, String) -> String) -> String = { _, _ in "undefined" }
    var sandboxes: [ScriptedSandbox] = []
    var storage: [String: String] = [:]

    func now() -> Double { clock }
    func setTimeout(_ callback: @escaping () -> Void, _ ms: Double) -> Int {
        let h = nextTimer
        nextTimer += 1
        timers.append((h, clock + ms, callback))
        return h
    }
    func clearTimeout(_ handle: Int) { timers.removeAll { $0.handle == handle } }
    func requestFrame(_ callback: @escaping (Double) -> Void) -> Int {
        let h = nextFrame
        nextFrame += 1
        frames.append((h, callback))
        return h
    }
    func cancelFrame(_ handle: Int) { frames.removeAll { $0.0 == handle } }
    func commit(_ surface: String, _ ops: [ViewOp]) { commits.append((surface, ops)) }
    /** Each character is half the font size wide; lines are 1.2 em. */
    func measureText(_ spec: TextSpec, _ maxWidth: Double) -> TextMetrics {
        let fs = spec.spans.first?.style.fontSize ?? 14
        let chars = spec.spans.reduce(0) { $0 + jsLength($1.text) }
        let natural = Double(chars) * fs * 0.5
        let lines: Double = maxWidth == INF || natural <= maxWidth ? 1 : (natural / maxWidth).rounded(.up)
        return TextMetrics(width: min(natural, maxWidth), height: lines * fs * 1.2, baseline: fs * 0.8,
                           lineCount: lines.isFinite ? Int(lines) : Int.max, didExceedMaxLines: false)
    }
    func viewport(_ surface: String) -> Viewport {
        Viewport(width: 400, height: 300, devicePixelRatio: 2, safeArea: .zero, locale: "en-US", platform: "ios", isWeb: false, darkMode: false,
                 textScale: 1, href: "https://app.test:8080/home?q=a+b&x=1#top")
    }
    func log(_ level: LogLevel, _ message: String) { logs.append("\(level.rawValue): \(message)") }
    func fetch(_ request: FetchRequest) async throws -> FetchResponse {
        fetches.append(request)
        return fetchHandler(request)
    }
    func fetchStream(_ request: FetchRequest, _ handlers: StreamHandlers) -> () -> Void {
        streamRequest = request
        streamHandlers = handlers
        return { [weak self] in self?.streamCancelled = true }
    }
    func storageGet(_ key: String) -> String? { storage[key] }
    func storageSet(_ key: String, _ value: String?) { storage[key] = value }
    var jsSandbox: JsSandboxFactory? { self }

    func create(_ machineId: String) throws -> JsSandbox {
        let s = ScriptedSandbox { [weak self] code, host in self?.sandboxScript(code, host) ?? "undefined" }
        sandboxes.append(s)
        return s
    }

    /** Run main-actor tasks, due timers (without advancing the clock) and pending frames until idle. */
    @MainActor
    func drain() async {
        for _ in 0..<100 {
            for _ in 0..<20 { await Task.yield() }
            let due = timers.filter { $0.at <= clock }
            timers.removeAll { t in due.contains { $0.handle == t.handle } }
            for t in due { t.fn() }
            let f = frames
            frames.removeAll()
            if !f.isEmpty { clock += 16 }
            for (_, cb) in f { cb(clock) }
            if due.isEmpty && f.isEmpty {
                for _ in 0..<20 { await Task.yield() }
                if timers.filter({ $0.at <= clock }).isEmpty && frames.isEmpty { return }
            }
        }
    }

    func allOps(_ surface: String) -> [ViewOp] { commits.filter { $0.0 == surface }.flatMap { $0.1 } }
}

private func json(_ text: String) -> JSONObject { asMap(try! JSON.parse(text))! }

@MainActor
final class SessionRegistryTests: XCTestCase {
    private var platform: SessionFakePlatform!
    private var registry: SessionRegistry!
    private var events: [(surface: String, event: String, payload: Any?)] = []

    override func setUp() async throws {
        platform = SessionFakePlatform()
        setPlatform(platform)
        events = []
        registry = SessionRegistry(emit: { [weak self] surface, event, payload in self?.events.append((surface, event, payload)) })
    }

    override func tearDown() async throws {
        await registry.shutdown()
        await platform.drain()
    }

    private func open(_ kind: String, _ surface: String, _ options: JSONObject) async throws {
        try await registry.open(kind, surface, options)
        await platform.drain()
    }

    @discardableResult
    private func call(_ surface: String, _ method: String, _ args: Any?...) async throws -> Any? {
        let r = try await registry.call(surface, method, args)
        await platform.drain()
        return r
    }

    private func texts(_ surface: String) -> [String] {
        platform.allOps(surface).compactMap { op -> String? in
            let props: ViewProps?
            switch op {
            case .create(_, _, _, _, let p): props = p
            case .update(_, let p): props = p
            default: props = nil
            }
            return (props?["text"] as? TextSpec)?.spans.map { $0.text }.joined()
        }
    }

    private func find(_ surface: String, _ pred: (RenderObject) -> Bool) -> RenderObject? {
        var hit: RenderObject?
        surfaceById(surface)?.owner.root?.visit { if hit == nil && pred($0) { hit = $0 } }
        return hit
    }

    private func failure(_ block: () async throws -> Void) async -> String? {
        do {
            try await block()
            return nil
        } catch {
            return errorText(error)
        }
    }

    func testJsonSessionCommitsViewOpsAndAppliesMethods() async throws {
        try await open("json", "s1", JSONObject([("view", json("""
            {"type": "Column", "children": [
              {"type": "Text", "props": {"text": "Hello"}},
              {"type": "Text", "key": "second", "props": {"text": "World"}}
            ]}
            """))]))
        XCTAssertTrue(registry.has("s1"))
        let creates = platform.allOps("s1").filter { if case .create = $0 { return true } else { return false } }
        XCTAssertFalse(creates.isEmpty, "the first frame creates native views")
        XCTAssertEqual(texts("s1"), ["Hello", "World"])

        // A scoped patch replaces only the keyed subtree.
        let patched = try await call("s1", "patch", json(#"{"type": "Text", "props": {"text": "Patched"}}"#), "second")
        XCTAssertEqual(patched as? Bool, true)
        XCTAssertTrue(texts("s1").contains("Patched"))
        // A patch whose scope is missing is dropped.
        let missing = try await call("s1", "patch", json(#"{"type": "Text", "props": {"text": "Nope"}}"#), "missing")
        XCTAssertEqual(missing as? Bool, false)

        try await call("s1", "setContent", json(#"{"type": "Text", "props": {"text": "Replaced"}}"#))
        XCTAssertTrue(platform.allOps("s1").contains { if case .remove = $0 { return true } else { return false } }, "views no longer rendered are removed")
        XCTAssertEqual(texts("s1").last, "Replaced")

        let message = await failure { _ = try await self.registry.call("s1", "nope", []) }
        XCTAssertEqual(message, "json session has no method nope")

        await registry.close("s1")
        XCTAssertFalse(registry.has("s1"))
        XCTAssertNil(surfaceById("s1"))
    }

    func testTapOnNodeWithEventHandlerDispatchesClick() async throws {
        try await open("json", "tap", JSONObject([("view", json("""
            {"type": "div", "props": {"id": "btn"}, "events": {"click": "onPress"}, "children": [{"type": "Text", "props": {"text": "Press"}}]}
            """))]))
        let surface = try XCTUnwrap(surfaceById("tap"))
        var received: [String] = []
        surface.engine.services.events.onGlobalEvent { received.append($0.type) }
        let gesture = try XCTUnwrap(find("tap") { $0.type == "gesture" && $0.viewId != nil }, "event-bearing node has a gesture view")
        registry.dispatchViewEvent("tap", ViewEvent(id: gesture.viewId!, type: "tap", x: 5, y: 5, localX: 5, localY: 5))
        await platform.drain()
        XCTAssertEqual(received, ["click"])
    }

    func testMiniappSessionDrivesTheHostCallProtocol() async throws {
        platform.sandboxScript = { code, host in
            if code == "PROGRAM" {
                _ = host("println", "\"booted\"")
                _ = host("render", #"{"type": "div", "events": {"click": "onTap"}, "children": [{"type": "Text", "props": {"text": "Count 0"}}]}"#)
            } else if code.hasPrefix("main(") {
                _ = host("render", #"{"type": "div", "events": {"click": "onTap"}, "children": [{"type": "Text", "props": {"text": "Count 1"}}]}"#)
            } else if code.hasPrefix("onTap(") {
                _ = host("render", #"{"type": "div", "children": [{"type": "Text", "props": {"text": "Tapped"}}]}"#)
            }
            return "undefined"
        }
        try await open("miniapp", "m1", JSONObject([
            ("runtime", "quickjs"), ("code", "PROGRAM"), ("entryFunction", "main"), ("entryInput", JSONObject([("n", 1.0)])),
        ]))

        XCTAssertEqual(platform.sandboxes.count, 1)
        let sandbox = platform.sandboxes[0]
        // Bootstrap, env sync, program, entry function with its JSON input.
        XCTAssertTrue(sandbox.evaluated.contains("PROGRAM"))
        XCTAssertTrue(sandbox.evaluated.contains { $0.hasPrefix("main(JSON.parse(") && $0.contains(#"\"n\":1"#) })
        XCTAssertTrue(sandbox.evaluated.contains { $0.contains("__ELPIAN_HOST_ENV__") && $0.contains("landscape") })
        XCTAssertTrue(sandbox.evaluated.contains { $0.contains(#"\"queryParameters\":{\"q\":\"a b\",\"x\":\"1\"}"#) && $0.contains(#"\"port\":8080"#) })
        XCTAssertEqual(events.map { "\($0.surface):\($0.event)" }, ["m1:println", "m1:ready"])
        XCTAssertEqual(events[0].payload as? String, "booted")

        let view = try await call("m1", "view") as? JSONObject
        XCTAssertEqual(view?["type"] as? String, "div")
        XCTAssertEqual(texts("m1").last, "Count 1")

        // A tap routes to the guest function named in node.events.
        let gesture = try XCTUnwrap(find("m1") { $0.type == "gesture" && $0.viewId != nil })
        registry.dispatchViewEvent("m1", ViewEvent(id: gesture.viewId!, type: "tap", x: 1, y: 1, localX: 1, localY: 1))
        await platform.drain()
        XCTAssertTrue(sandbox.evaluated.contains { $0.hasPrefix("onTap(JSON.parse(") })
        XCTAssertEqual(texts("m1").last, "Tapped")

        // Governance over the string API.
        let state = try await call("m1", "state") as? JSONObject
        XCTAssertEqual(state?["state"] as? String, "running")
        try await call("m1", "terminate")
        XCTAssertTrue(sandbox.disposed)

        await registry.close("m1")
    }

    func testStreamSessionReadsChunkedNdjsonAndSse() async throws {
        try await open("stream", "st", JSONObject([
            ("request", JSONObject([("url", "https://example.test/stream"), ("method", "POST"), ("body", JSONObject([("a", 1.0)]))])),
        ]))
        XCTAssertEqual(platform.streamRequest?.url, "https://example.test/stream")
        XCTAssertEqual(platform.streamRequest?.body, #"{"a":1}"#)
        let h = try XCTUnwrap(platform.streamHandlers)

        // Chunk boundaries fall mid-line.
        h.onChunk(#"{"action": "setView", "view": {"type": "Text", "props": {"text": "Fir"#)
        h.onChunk("st\"}}}\n")
        await platform.drain()
        XCTAssertEqual(texts("st").last, "First")

        h.onChunk("data: {\"action\": \"patchView\",\n")
        h.onChunk("data:  \"patch\": {\"props\": {\"text\": \"Second\"}}}\n\n")
        h.onChunk(": a comment\nevent: update\n")
        await platform.drain()
        XCTAssertEqual(texts("st").last, "Second")

        h.onChunk("{\"action\": \"bogus\"}\n")
        await platform.drain()
        XCTAssertTrue(events.contains { $0.event == "error" && ($0.payload as? String) == "Unknown stream action: bogus." })
        XCTAssertTrue(texts("st").last?.hasPrefix("Stream Error:") == true)

        // A bare view (no action) is a setView; the error clears.
        h.onChunk(#"{"type": "Text", "props": {"text": "Third"}}"#)
        h.onDone()
        await platform.drain()
        XCTAssertEqual(texts("st").last, "Third")
        XCTAssertTrue(events.contains { $0.event == "streamDone" })
        let commands = events.filter { $0.event == "command" }.map { (($0.payload as? JSONObject)?["action"] as? String) ?? "" }
        XCTAssertEqual(commands, ["setView", "patchView", "bogus", "setView"])

        // Pushed commands work too.
        try await call("st", "push", #"{"action": "setView", "view": {"type": "Text", "props": {"text": "Pushed"}}}"#)
        XCTAssertEqual(texts("st").last, "Pushed")

        await registry.close("st")
        XCTAssertTrue(platform.streamCancelled)
    }

    func testCallAsyncEmitsResults() async throws {
        try await open("json", "a1", JSONObject([("view", json(#"{"type": "Text", "props": {"text": "x"}}"#))]))
        registry.callAsync("a1", "patch", [json(#"{"type": "Text"}"#), "missing"], 7.0)
        registry.callAsync("a1", "unknown", [], 8.0)
        registry.callAsync("nowhere", "x", [], 9.0)
        await platform.drain()
        let results = events.filter { $0.event == "result" }.compactMap { $0.payload as? JSONObject }
        XCTAssertEqual(results.map { jsNumber($0["requestId"]) }, [7.0, 8.0, 9.0])
        XCTAssertEqual(results.map { jsBool($0["ok"]) }, [true, false, false])
        XCTAssertEqual(results[0]["value"] as? Bool, false)
        XCTAssertEqual(results[2]["error"] as? String, "no session on surface \"nowhere\"")
    }

    func testUnknownKindFails() async {
        let message = await failure { try await self.registry.open("bogus", "b", JSONObject()) }
        XCTAssertEqual(message, "unknown session kind \"bogus\"")
    }

    func testSuperappLaunchesUnderItsManifestAndGrant() async throws {
        platform.sandboxScript = { code, host in
            if code == "APP" {
                _ = host("println", "\"hi\"")
            } else if code.hasPrefix("start(") {
                _ = host("render", #"{"type": "Text", "props": {"text": "Super"}}"#)
            }
            return "undefined"
        }
        try await open("superapp", "sa", JSONObject([
            ("manifest", json("""
                {"id": "shop", "name": "Shop", "entrypoint": "start", "runtime": "quickJs",
                 "requestedCapabilities": ["render", "logging", "network", "bogus"]}
                """)),
            ("grant", json(#"{"base": "untrusted", "allowedApis": ["render"]}"#)),
            ("source", "APP"),
            ("entryInput", JSONObject([("x", 1.0)])),
        ]))
        XCTAssertEqual(texts("sa").last, "Super")
        // println is within the logging capability but not in allowedApis: the host gate refuses it.
        XCTAssertEqual(events.filter { $0.event == "callRefused" }.map { $0.payload as? String }, ["println"])
        let ready = try XCTUnwrap(events.first { $0.event == "ready" }?.payload as? JSONObject)
        XCTAssertEqual(JSON.stringify(ready), #"{"denied":["network"]}"#)
        XCTAssertTrue(platform.sandboxes[0].evaluated.contains { $0.hasPrefix("start(JSON.parse(") })

        let policyValue = try await call("sa", "policy")
        let policy = try XCTUnwrap(policyValue as? JSONObject)
        XCTAssertEqual(JSON.stringify(policy["capabilities"]), #"["render","logging"]"#)
        XCTAssertEqual(JSON.stringify(policy["denied"]), #"["network"]"#)
        XCTAssertEqual(jsNumber(asMap(policy["limits"])?["maxCallDepth"]), 1024)
        XCTAssertEqual(policy["mayHostChildren"] as? Bool, false)

        let refused = await failure { _ = try await self.registry.call("sa", "spawnChild", [JSONObject([("id", "kid")]), "X"]) }
        XCTAssertTrue(refused?.contains("not permitted to host children") == true)

        // An invalid manifest is reported, not thrown.
        try await open("superapp", "bad", JSONObject([("manifest", json(#"{"id": "a::b"}"#)), ("source", "")]))
        XCTAssertEqual(events.last?.event, "error")
        XCTAssertEqual(events.last?.payload as? String, "MiniAppException(a::b): a mini app id may not contain \"::\"")
        XCTAssertFalse(registry.has("bad"))

        await registry.close("sa")
        XCTAssertTrue(platform.sandboxes[0].disposed)
    }

    func testNextjsLoadsEnvelopesAndNavigates() async throws {
        platform.fetchHandler = { req in
            let page = req.url.hasSuffix("/about") ? "About" : "Home"
            return FetchResponse(status: 200, headers: [:], body: #"{"component": {"type": "Text", "props": {"text": "\#(page)"}}}"#)
        }
        try await open("nextjs", "n1", JSONObject([("serverBaseUrl", "https://next.test/"), ("route", "/"), ("headers", JSONObject([("x-a", "1")]))]))
        XCTAssertEqual(platform.fetches.first?.url, "https://next.test")
        XCTAssertEqual(platform.fetches.first?.method, "GET")
        XCTAssertEqual(platform.fetches.first?.headers?["x-elpian-route"], "/")
        XCTAssertEqual(platform.fetches.first?.headers?["x-a"], "1")
        XCTAssertEqual(platform.fetches.first?.timeoutMs, 120000)
        XCTAssertEqual(texts("n1").last, "Home")
        let r1 = try await call("n1", "canGoBack")
        XCTAssertEqual(r1 as? Bool, false)

        try await call("n1", "navigate", "/about")
        XCTAssertEqual(platform.fetches.last?.url, "https://next.test/about")
        XCTAssertEqual(texts("n1").last, "About")
        let r2 = try await call("n1", "route")
        XCTAssertEqual(r2 as? String, "/about")
        let r3 = try await call("n1", "canGoBack")
        XCTAssertEqual(r3 as? Bool, true)

        let r4 = try await call("n1", "back")

        XCTAssertEqual(r4 as? Bool, true)
        XCTAssertEqual(texts("n1").last, "Home")
        let r5 = try await call("n1", "back")
        XCTAssertEqual(r5 as? Bool, false)
        XCTAssertEqual(events.filter { $0.event == "routeChanged" }.map { $0.payload as? String }, ["/about", "/"])

        // A server error shows the payload error.
        platform.fetchHandler = { _ in FetchResponse(status: 500, headers: [:], body: "boom") }
        try await call("n1", "refresh")
        XCTAssertEqual(texts("n1").last, "Next.js payload error on \"/\": Next.js route https://next.test returned HTTP 500: boom")
    }

    func testServerComponentRendersAndCallsActions() async throws {
        platform.fetchHandler = { req in
            if req.url == "https://srv.test/apps/demo/render/Card" {
                return FetchResponse(status: 200, headers: [:], body: """
                    {"ok": true, "result": {"component": {"type": "Text", "props": {"text": "Server"}}, "clientComponents": {"Chart": {}, "Map": {}}}}
                    """)
            }
            if req.url == "https://srv.test/apps/demo/fn/like" {
                return FetchResponse(status: 200, headers: [:], body: #"{"ok": true, "result": {"likes": 3}}"#)
            }
            return FetchResponse(status: 403, headers: [:], body: #"{"error": "nope"}"#)
        }
        try await open("server", "sv", JSONObject([
            ("baseUrl", "https://srv.test"), ("appId", "demo"), ("name", "Card"), ("args", JSONObject([("id", 1.0)])),
            ("authorization", "Bearer t"), ("nativeIslands", JSONObject([("Map", "MapView")])),
        ]))
        let render = try XCTUnwrap(platform.fetches.first)
        XCTAssertEqual(render.method, "POST")
        XCTAssertEqual(render.body, #"{"id":1}"#)
        XCTAssertEqual(render.headers?["authorization"], "Bearer t")
        XCTAssertEqual(texts("sv").last, "Server")
        let r6 = try await call("sv", "unresolvedIslands")
        XCTAssertEqual(JSON.stringify(r6), #"["Chart"]"#)

        let liked = try await call("sv", "callAction", "like", JSONObject())
        XCTAssertEqual(JSON.stringify(liked), #"{"result":{"likes":3}}"#)
        let denied = try await call("sv", "callAction", "other", JSONObject())
        XCTAssertEqual(JSON.stringify(denied), #"{"error":"nope"}"#)

        // The brokered net policy refuses hosts outside its allowlist without a round trip.
        let policy = ElpianNetPolicy.fromManifest(json(#"{"allow": ["*.example.com", "api.test"]}"#))
        XCTAssertTrue(policy.allows("https://a.example.com/x"))
        XCTAssertFalse(policy.allows("https://example.com/x"))
        XCTAssertTrue(policy.allows("https://user@API.test:8080/"))
        XCTAssertFalse(policy.allows("https://evil.test"))
        XCTAssertFalse(ElpianNetPolicy.closed.allows("https://api.test"))
    }
}
