import XCTest
@testable import ElpianCore

/**
 * The `agent` session kind end to end on a fake platform whose fetchStream
 * streams an agent response (split mid-line): the surface renders, a TextField
 * is filled through a platform ViewEvent, a Button is tapped, the POSTed
 * action body carries the typed value and the sendDataModel surface, and the
 * agent's follow-up re-renders the surface. Also: a `miniapp` session hands
 * its `baseUrl` / `appId` to the A2UI registry.
 */
@MainActor
final class A2UISessionTests: XCTestCase {
    private var platform: A2UITestPlatform!
    private var registry: SessionRegistry!
    private var events: [(surface: String, event: String, payload: Any?)] = []

    override func setUp() async throws {
        platform = A2UITestPlatform()
        setPlatform(platform)
        events = []
        registry = SessionRegistry(emit: { [weak self] surface, event, payload in self?.events.append((surface, event, payload)) })
    }

    override func tearDown() async throws {
        await registry.shutdown()
        await platform.drain()
        // Surfaces set the global CSS environment; restore the default other suites assume.
        CssEnvironment.update(viewportWidth: 1280, viewportHeight: 800, safeArea: .zero, rootFontSize: 16, devicePixelRatio: 1)
    }

    private func texts(_ surface: String) -> [String] {
        var out: [String] = []
        surfaceById(surface)?.owner.root?.visit { ro in
            if ro.type == "text", let t = ro.props["text"] as? String { out.append(t) }
            if ro.type == "text", let spans = ro.props["spans"] as? [SpanInput] { out.append(spans.map { $0.text }.joined()) }
        }
        return out
    }

    private func find(_ surface: String, _ pred: (RenderObject) -> Bool) -> RenderObject? {
        var hit: RenderObject?
        surfaceById(surface)?.owner.root?.visit { if hit == nil && pred($0) { hit = $0 } }
        return hit
    }

    private static let firstResponse: [String] = [
        "{\"type\":\"conversation\",\"conversationId\":\"conv-7\"}\n{\"version\":\"v0.9.1\",\"createSurface\":{\"surfaceId\":\"form\",\"catalogId\":\"\(BASIC_CATALOG_ID)\",\"sendDataModel\":true}}\n{\"version\":\"v0.9.1\",\"updateComp",
        "onents\":{\"surfaceId\":\"form\",\"components\":[{\"id\":\"root\",\"component\":\"Column\",\"children\":[\"name\",\"go\",\"greet\"]},"
            + "{\"id\":\"name\",\"component\":\"TextField\",\"label\":\"Your name\",\"value\":{\"path\":\"/name\"}},"
            + "{\"id\":\"go_label\",\"component\":\"Text\",\"text\":\"Greet me\"},"
            + "{\"id\":\"go\",\"component\":\"Button\",\"child\":\"go_label\",\"variant\":\"primary\",\"action\":{\"event\":{\"name\":\"greet\",\"context\":{\"who\":{\"path\":\"/name\"}}}}},"
            + "{\"id\":\"greet\",\"component\":\"Text\",\"text\":{\"path\":\"/greeting\"}}]}}\n",
        "{\"type\":\"text\",\"text\":\"Tell me your name\"}\n{\"type\":\"done\",\"stopReason\":\"end_turn\"}\n",
    ]

    func testAgentSessionRendersFillsATextFieldTapsAButtonAndRerenders() async throws {
        platform.streamScript = { request in
            let body = asMap(JSON.parseOrNil(request.body)) ?? JSONObject()
            if body.has("action") {
                return A2UIStreamScript(chunks: [
                    "{\"type\":\"conversation\",\"conversationId\":\"conv-7\"}\n{\"version\":\"v0.9.1\",\"updateDataModel\":{\"surfaceId\":\"form\",\"path\":\"/greeting\",\"value\":\"Hello, Ada!\"}}\n",
                    "{\"type\":\"done\",\"stopReason\":\"end_turn\"}\n",
                ])
            }
            return A2UIStreamScript(chunks: A2UISessionTests.firstResponse)
        }
        try await registry.open("agent", "agent1", JSONObject([
            ("baseUrl", "http://agents.test/"), ("appId", "shop"), ("agent", "assistant"), ("prompt", "hi"),
        ]))
        await platform.drain()

        XCTAssertEqual(platform.requests.count, 1)
        XCTAssertEqual(platform.requests[0].url, "http://agents.test/apps/shop/agent/assistant")
        XCTAssertTrue(jsonEqual(JSON.parseOrNil(platform.requests[0].body),
                                a2uiJson(#"{"message": "hi", "capabilities": {"supportedCatalogIds": ["\#(BASIC_CATALOG_ID)"]}}"#)))
        XCTAssertTrue(texts("agent1").contains("Your name"), "\(texts("agent1"))")
        XCTAssertTrue(texts("agent1").contains("Tell me your name"), "the prose is shown")
        XCTAssertTrue(events.contains { $0.event == "a2uiText" && asMap($0.payload)?["text"] as? String == "Tell me your name" })
        XCTAssertTrue(events.contains { $0.event == "done" && asMap($0.payload)?["stopReason"] as? String == "end_turn" })
        let described = try await registry.call("agent1", "conversation", [])
        XCTAssertEqual(asMap(described)?["conversationId"] as? String, "conv-7")

        // Fill the A2UI TextField (not the chat input) through its native view.
        let field = try XCTUnwrap(find("agent1") { ro in
            ro.type == "control" && ro.props["kind"] as? String == "textInput"
                && (ro.props["view"] as? JSONObject)?["placeholder"] as? String != "Message the agent" && ro.viewId != nil
        })
        registry.dispatchViewEvent("agent1", ViewEvent(id: field.viewId!, type: "input", value: "Ada"))
        await platform.drain()
        let conv = try XCTUnwrap(a2uiRegistry(surfaceById("agent1")!.engine.services).get("session"))
        XCTAssertEqual(asMap(conv.dataModel("form"))?["name"] as? String, "Ada")

        // Tap the button.
        let button = try XCTUnwrap(find("agent1") { ro in
            ro.props["role"] as? String == "button" && ro.props["semanticsLabel"] as? String == "Greet me" && ro.viewId != nil
        })
        registry.dispatchViewEvent("agent1", ViewEvent(id: button.viewId!, type: "tap"))
        await platform.drain()

        XCTAssertEqual(platform.requests.count, 2)
        let sent = try XCTUnwrap(asMap(JSON.parseOrNil(platform.requests[1].body)))
        XCTAssertEqual(sent["conversationId"] as? String, "conv-7")
        let action = try XCTUnwrap(asMap(sent["action"]))
        XCTAssertEqual(action["name"] as? String, "greet")
        XCTAssertEqual(action["surfaceId"] as? String, "form")
        XCTAssertEqual(action["sourceComponentId"] as? String, "go")
        XCTAssertNotNil(ISO8601DateFormatter.withFractions.date(from: jsString(action["timestamp"])))
        XCTAssertTrue(jsonEqual(action["context"], a2uiJson(#"{"who": "Ada"}"#)))
        XCTAssertTrue(jsonEqual(sent["dataModel"], a2uiJson(#"{"version": "v0.9.1", "surfaces": {"form": {"name": "Ada"}}}"#)))
        XCTAssertTrue(events.contains { $0.event == "a2uiAction" && asMap($0.payload)?["name"] as? String == "greet" })

        // The follow-up re-rendered the bound Text.
        XCTAssertTrue(texts("agent1").contains("Hello, Ada!"), "\(texts("agent1"))")

        // Methods: send and action.
        platform.streamScript = { _ in A2UIStreamScript(chunks: ["{\"type\":\"done\",\"stopReason\":\"end_turn\"}\n"]) }
        async let sendResult = registry.call("agent1", "send", ["more"])
        await platform.drain()
        let sendValue = try await sendResult
        XCTAssertEqual(asMap(sendValue)?["conversationId"] as? String, "conv-7")
        async let actionResult = registry.call("agent1", "action", [#"{"name": "refresh"}"#])
        await platform.drain()
        let actionValue = try await actionResult
        XCTAssertEqual(asMap(actionValue)?["conversationId"] as? String, "conv-7")
        let last = asMap(asMap(JSON.parseOrNil(platform.requests.last?.body))?["action"])
        XCTAssertEqual(last?["name"] as? String, "refresh")
        XCTAssertTrue(last?["context"] is JSONObject)
        do {
            _ = try await registry.call("agent1", "nope", [])
            XCTFail("unknown method")
        } catch {
            XCTAssertEqual(errorText(error), "agent session has no method nope")
        }
    }

    func testMiniAppSessionHandsBaseUrlAndAppIdToTheA2UIRegistry() async throws {
        try await registry.open("miniapp", "mini1", JSONObject([
            ("code", "fn main() {}"), ("baseUrl", "http://apps.test"), ("appId", "shop"), ("headers", JSONObject([("authorization", "Bearer t")])),
        ]))
        await platform.drain()
        let entry = try XCTUnwrap(registry.get("mini1"))
        let defaults = a2uiRegistry(entry.surface.engine.services).defaults
        XCTAssertEqual(defaults.baseUrl, "http://apps.test")
        XCTAssertEqual(defaults.appId, "shop")
        XCTAssertEqual(defaults.headers?["authorization"], "Bearer t")
        // A2UISurface widgets inside the app reach its agents.
        XCTAssertEqual(a2uiRegistry(entry.surface.engine.services).endpoint("assistant").map { agentUrl($0) }, "http://apps.test/apps/shop/agent/assistant")
        // Without them, nothing is configured.
        try await registry.open("miniapp", "mini2", JSONObject([("code", "fn main() {}")]))
        await platform.drain()
        XCTAssertNil(a2uiRegistry(registry.get("mini2")!.surface.engine.services).endpoint("assistant"))
    }
}
