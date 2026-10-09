import XCTest
@testable import ElpianCore

/**
 * Lowering Elpian trees through the engine's widget builders (the Swift port of
 * LoweringTest.kt): the emitted widget descriptors, their registration with the
 * reconciler, a reconcile + layout pass, and the host handler.
 */
final class LoweringTests: XCTestCase {
    private func json(_ text: String) -> JSONObject {
        asMap(try! JSON.parse(text))!
    }

    private func walk(_ w: W, _ out: inout [W]) {
        out.append(w)
        for c in w.c ?? [] { walk(c, &out) }
    }

    private func walk(_ w: W) -> [W] {
        var out: [W] = []
        walk(w, &out)
        return out
    }

    private func types(_ w: W) -> [String] { walk(w).map { $0.t } }

    private var owners: [RenderOwner] = []

    private func owner() -> RenderOwner {
        let o = RenderOwner(surface: "s", platform: TextFakePlatform())
        owners.append(o)
        return o
    }

    func testHtmlDivWithInlineCssLowersToBoxModel() {
        let engine = ElpianEngine()
        let tree = engine.renderFromJson(json("""
        {"type": "div", "props": {"style": {"padding": "8px", "backgroundColor": "#ff0000", "borderRadius": "4px"}},
         "children": [
           {"type": "p", "props": {"text": "Hello "}, "children": [{"type": "strong", "props": {"text": "world"}}]},
           {"type": "span", "props": {"text": "tail", "style": {"color": "#00ff00"}}}
         ]}
        """))
        // Container order: padding inside decoration.
        XCTAssertEqual(tree.t, "decorated")
        let decoration = tree.p["decoration"] as? BoxDecoration
        XCTAssertEqual(decoration?.color, 0xffff0000)
        XCTAssertNotNil(decoration?.radius)
        XCTAssertEqual(tree.c?.count, 1)
        let pad = tree.c![0]
        XCTAssertEqual(pad.t, "padding")
        XCTAssertEqual(pad.p["padding"] as? EdgeInsets, EdgeInsets(top: 8, right: 8, bottom: 8, left: 8))
        // Block flow: a column stretching its children.
        XCTAssertEqual(pad.c?.count, 1)
        let flex = pad.c![0]
        XCTAssertEqual(flex.t, "flex")
        XCTAssertEqual(flex.p.s("direction"), "column")
        XCTAssertEqual(flex.c?.count, 2)
        // The paragraph becomes one rich text of spans, wrapped in its 8px vertical margin.
        let texts = walk(flex).filter { $0.t == "text" }
        let rich = texts.first { $0.p["spans"] != nil }!
        let spans = rich.p["spans"] as! [SpanInput]
        XCTAssertEqual(spans.map { $0.text }, ["Hello ", "world"])
        XCTAssertEqual(spans[1].style?.fontWeight, 700)
        XCTAssertTrue(walk(flex.c![0]).contains { $0.t == "padding" && ($0.p["padding"] as? EdgeInsets) == EdgeInsets(top: 8, right: 0, bottom: 8, left: 0) })
        // The span keeps its colour.
        let tail = texts.first { $0.p.s("text") == "tail" }!
        XCTAssertEqual((tail.p["style"] as? TextStyle)?.color, 0xff00ff00)
    }

    func testFlutterColumnRowContainerText() {
        let engine = ElpianEngine()
        let tree = engine.renderFromJson(json("""
        {"type": "Column", "style": {"justifyContent": "center", "alignItems": "stretch", "gap": 4},
         "children": [
           {"type": "Row", "style": {"justifyContent": "space-between"}, "children": [
             {"type": "Text", "props": {"text": "a", "maxLines": 2}},
             {"type": "Container", "props": {"width": 20, "height": 10, "padding": 2, "decoration": {"backgroundColor": "blue"}}}
           ]},
           {"type": "Text", "props": {"text": "b"}, "style": {"fontSize": 20}}
         ]}
        """))
        XCTAssertEqual(tree.t, "flex")
        XCTAssertEqual(tree.p.s("direction"), "column")
        XCTAssertEqual(tree.p.s("mainAxisAlignment"), "center")
        XCTAssertEqual(tree.p.s("crossAxisAlignment"), "stretch")
        XCTAssertEqual(tree.p.d("gap"), 4)
        let row = tree.c![0]
        XCTAssertEqual(row.p.s("direction"), "row")
        XCTAssertEqual(row.p.s("mainAxisAlignment"), "spaceBetween")
        let a = row.c![0]
        XCTAssertEqual(a.t, "text")
        XCTAssertEqual(a.p.s("text"), "a")
        XCTAssertEqual(a.p.d("maxLines"), 2)
        // Container(width, height, padding, decoration) without a child: constrained → decorated → padding.
        let box = row.c![1]
        XCTAssertEqual(types(box), ["constrained", "decorated", "padding"])
        XCTAssertEqual(box.p.d("width"), 20)
        XCTAssertEqual(box.p.d("height"), 10)
        let b = tree.c![1]
        XCTAssertEqual((b.p["style"] as? TextStyle)?.fontSize, 20)
    }

    func testStylesheetEventsKeysAndDisplayNone() {
        let engine = ElpianEngine()
        engine.loadStylesheet(".card { padding: 12px; } .gone { display: none; }")
        let tree = engine.renderFromJson(json("""
        {"type": "section", "key": "root", "children": [
          {"type": "div", "props": {"className": "card"}, "events": {"click": "onCard"}, "children": [{"type": "Text", "props": {"text": "x"}}]},
          {"type": "div", "props": {"className": "gone"}}
        ]}
        """))
        XCTAssertEqual(tree.k, "root")
        let all = walk(tree)
        let gesture = all.first { $0.t == "gesture" }!
        XCTAssertEqual(gesture.p["gestures"] as? [String], ["tap"])
        XCTAssertEqual(gesture.p.s("cursor"), "pointer")
        XCTAssertTrue(gesture.k!.hasPrefix("ev:"))
        XCTAssertTrue(all.contains { $0.t == "padding" && ($0.p["padding"] as? EdgeInsets) == EdgeInsets(top: 12, right: 12, bottom: 12, left: 12) })
        XCTAssertTrue(all.contains { $0.t == "constrained" && $0.p.d("width") == 0 && $0.p.d("height") == 0 && $0.c == nil })

        // A tap reaches the guest handler through the dispatcher.
        var received: [String] = []
        engine.services.events.onGlobalEvent { received.append("\($0.type)@\($0.target ?? "")") }
        let onEvent = gesture.p["onEvent"] as! (ViewEvent) -> Void
        onEvent(ViewEvent(id: 1, type: "tap", x: 1, y: 2))
        XCTAssertEqual(received.count, 1)
        XCTAssertTrue(received[0].hasPrefix("click@"))
    }

    func testEveryEmittedTypeIsRegisteredAndReconciles() {
        let engine = ElpianEngine()
        let tree = engine.renderFromJson(json("""
        {"type": "div", "children": [
          {"type": "h1", "props": {"text": "Title"}},
          {"type": "ul", "children": [{"type": "li", "props": {"text": "one"}}, {"type": "li", "props": {"text": "two"}}]},
          {"type": "ol", "children": [{"type": "li", "props": {"text": "first"}}]},
          {"type": "table", "children": [{"type": "tr", "children": [{"type": "th", "props": {"text": "h"}}, {"type": "td", "props": {"text": "d"}}]}]},
          {"type": "form", "children": [
            {"type": "input", "props": {"name": "q", "placeholder": "Search"}},
            {"type": "input", "props": {"type": "checkbox", "name": "c"}},
            {"type": "input", "props": {"type": "range", "name": "r"}},
            {"type": "select", "children": [{"type": "option", "props": {"value": "a", "text": "A"}}]},
            {"type": "textarea"},
            {"type": "button", "props": {"text": "Go"}}
          ]},
          {"type": "details", "children": [{"type": "summary", "props": {"text": "More"}}, {"type": "p", "props": {"text": "hidden"}}]},
          {"type": "img", "props": {"src": "a.png"}},
          {"type": "progress", "props": {"value": 0.5}},
          {"type": "pre", "props": {"text": "code"}},
          {"type": "blockquote", "props": {"text": "quote"}},
          {"type": "hr"},
          {"type": "div", "props": {"style": {"display": "grid", "gridTemplateColumns": "1fr 1fr"}}, "children": [{"type": "span", "props": {"text": "g1"}}, {"type": "span", "props": {"text": "g2"}}]},
          {"type": "div", "props": {"style": {"position": "relative"}}, "children": [{"type": "span", "props": {"text": "abs", "style": {"position": "absolute", "top": "0px"}}}]},
          {"type": "div", "props": {"style": {"display": "flex", "opacity": 0.5, "transform": "rotate(10deg)", "overflow": "hidden"}}, "children": [{"type": "span", "props": {"text": "f"}}]},
          {"type": "Card", "children": [{"type": "Text", "props": {"text": "card"}}]},
          {"type": "Scaffold", "children": [{"type": "AppBar", "props": {"title": "App"}}, {"type": "Center", "children": [{"type": "Icon", "props": {"icon": "home"}}]}]},
          {"type": "Stack", "children": [{"type": "Positioned", "style": {"top": 1}, "children": [{"type": "Badge", "props": {"label": "3"}}]}]},
          {"type": "ListView", "children": [{"type": "Chip", "props": {"label": "chip"}}, {"type": "Divider"}]},
          {"type": "Wrap", "children": [{"type": "Switch"}, {"type": "Slider"}, {"type": "Checkbox"}, {"type": "Radio"}]},
          {"type": "AnimatedContainer", "style": {"width": 10, "backgroundColor": "red"}},
          {"type": "FadeTransition", "children": [{"type": "Text", "props": {"text": "fade"}}]},
          {"type": "Shimmer"},
          {"type": "MathExpression", "props": {"expression": "x^2 + \\\\alpha"}},
          {"type": "NextjsLink", "props": {"href": "/a", "text": "link"}},
          {"type": "NextjsForm", "props": {"fields": [{"name": "email", "type": "text"}, {"name": "ok", "type": "checkbox"}]}}
        ]}
        """))
        let registered = registeredRenderObjectTypes()
        let unknown = Set(types(tree)).subtracting(registered)
        XCTAssertTrue(unknown.isEmpty, "unregistered render object types: \(unknown)")
        XCTAssertFalse(walk(tree).contains { node in
            guard node.t == "decorated", let inner = node.c?.first, node.c?.count == 1, let leaf = inner.c?.first, inner.c?.count == 1 else { return false }
            return (leaf.p.s("text") ?? "").hasPrefix("Unknown widget")
        })

        let math = walk(tree).first { $0.t == "text" && ($0.p.s("text") ?? "").contains("α") }
        XCTAssertEqual(math?.p.s("text"), "x² + α")

        // The tree builds render objects and lays out.
        let root = reconcileRoot(nil, engine.wrapAsDocument(tree, JSONObject([("type", "div")])), owner())
        root.layout(tight(400, 800))
        XCTAssertEqual(root.size.width, 400)
    }

    func testBlockLayoutStacksChildren() {
        let engine = ElpianEngine()
        let tree = engine.renderFromJson(json("""
        {"type": "div", "props": {"style": {"padding": "10px"}}, "children": [
          {"type": "div", "props": {"style": {"height": "20px", "backgroundColor": "red"}}},
          {"type": "div", "props": {"style": {"height": "30px", "width": "50%"}}}
        ]}
        """))
        let root = reconcileRoot(nil, tree, owner())
        root.layout(Constraints(minWidth: 0, maxWidth: 300, minHeight: 0, maxHeight: INF))
        XCTAssertEqual(root.size.width, 300)
        XCTAssertEqual(root.size.height, 70)
    }

    func testHostHandlerRendersAndServicesCanvasContexts() {
        let services = ElpianServices(appId: "app")
        var rendered: JSONObject?
        let handler = HostHandler(services: services, options: HostHandlerOptions(onRender: { view, _ in rendered = view }))
        _ = handler.handleHostCall("render", "[{\"type\": \"div\", \"children\": []}]")
        XCTAssertEqual(rendered?.s("type"), "div")
        let created = handler.handleHostCall("canvas.ctx.create", "{\"id\": \"c1\", \"width\": 10, \"height\": 20}")
        XCTAssertTrue(created.contains("c1"))
        _ = handler.handleHostCall("canvas.ctx.addCommand", "{\"id\": \"c1\", \"command\": {\"type\": \"fillRect\", \"params\": {\"x\": 0, \"y\": 0, \"width\": 5, \"height\": 5}}}")
        XCTAssertEqual(services.canvasContexts["app::c1"]?.commands.count, 1)

        let engine = ElpianEngine(services: services)
        let tree = engine.renderFromJson(json("{\"type\": \"CachedCanvas\", \"props\": {\"contextId\": \"c1\"}}"))
        XCTAssertEqual(tree.t, "canvas")
        XCTAssertEqual(tree.p.d("width"), 10)
        XCTAssertEqual(Alignment(x: 0, y: 0), Alignment.center)
    }

    // ---- beyond the Kotlin suite ----

    func testFormSubmitCollectsNamedFields() {
        let engine = ElpianEngine()
        let tree = engine.renderFromJson(json("""
        {"type": "form", "key": "f", "events": {"submit": "onSubmit"}, "children": [
          {"type": "input", "props": {"name": "q", "value": "hello"}},
          {"type": "input", "props": {"type": "checkbox", "name": "c", "checked": true}},
          {"type": "input", "props": {"type": "hidden", "name": "h", "value": "x"}}
        ]}
        """))
        XCTAssertFalse(walk(tree).isEmpty)
        var submitted: JSONObject?
        engine.services.events.onGlobalEvent { e in if e.type == "submit" { submitted = asMap(e.data["values"]) } }
        engine.submitForm("f")
        XCTAssertEqual(submitted.map { JSON.stringify($0) }, "{\"q\":\"hello\",\"c\":\"on\",\"h\":\"x\"}")
    }

    func testElementStateSurvivesRendersAndIsCollected() {
        let engine = ElpianEngine()
        let doc = json("""
        {"type": "div", "children": [{"type": "details", "key": "d", "children": [{"type": "summary", "props": {"text": "S"}}, {"type": "p", "props": {"text": "body"}}]}]}
        """)
        var invalidated = 0
        engine.host.invalidate = { invalidated += 1 }
        var tree = engine.renderFromJson(doc)
        XCTAssertFalse(walk(tree).contains { $0.p.s("text") == "body" })
        let header = walk(tree).first { $0.t == "gesture" && $0.p.s("role") == "button" }!
        (header.p["onEvent"] as! (ViewEvent) -> Void)(ViewEvent(id: 1, type: "tap"))
        XCTAssertEqual(invalidated, 1)
        tree = engine.renderFromJson(doc)
        XCTAssertTrue(walk(tree).contains { $0.p.s("text") == "body" })
        _ = engine.renderFromJson(json("{\"type\": \"div\"}"))
        XCTAssertNil(engine.stateOf("d"))
    }

    func testMathSanitizer() {
        let s = sanitizeMath("\\frac{1}{2} \\input{x}")
        XCTAssertTrue(s.sanitized)
        XCTAssertEqual(s.value, "\\frac{1}{2} \\text{blocked}{x}")
        XCTAssertEqual(renderMathToUnicode(s.value), "(1)/(2) blockedx")
        XCTAssertEqual(renderMathToUnicode("a_{12} \\leq b^n"), "a₁₂ ≤ bⁿ")
    }

    func testResolveUrlAndUnknownWidget() {
        let engine = ElpianEngine(host: EngineHost(baseUrl: { "https://example.com/app/" }))
        XCTAssertEqual(engine.resolveUrl("img/a.png"), "https://example.com/app/img/a.png")
        XCTAssertEqual(engine.resolveUrl("/x.png"), "https://example.com/x.png")
        XCTAssertEqual(engine.resolveUrl("//cdn.test/y.png"), "https:" + "//cdn.test/y.png")
        XCTAssertEqual(engine.resolveUrl("data:image/png;base64,AA"), "data:image/png;base64,AA")
        let tree = engine.renderFromJson(json("{\"type\": \"NoSuchWidget\"}"))
        XCTAssertEqual(types(tree), ["decorated", "padding", "text"])
        XCTAssertEqual(tree.c?[0].c?[0].p.s("text"), "Unknown widget: NoSuchWidget")
    }

    func testWrapAsDocumentSkipsViewportLockedRoots() {
        let engine = ElpianEngine()
        let content = w("constrained")
        XCTAssertEqual(engine.wrapAsDocument(content, JSONObject([("type", "div")])).t, "scroll")
        XCTAssertEqual(engine.wrapAsDocument(content, json("{\"type\": \"div\", \"style\": {\"height\": \"100vh\"}}")).t, "constrained")
        XCTAssertEqual(engine.wrapAsDocument(content, json("{\"type\": \"div\", \"children\": [{\"type\": \"Scene3D\"}]}")).t, "constrained")
        XCTAssertEqual(engine.wrapAsDocument(content, nil).t, "constrained")
    }
}

final class HostHandlerTests: XCTestCase {
    func testPrintlnEnvStringifyAndUnserviced() {
        var printed: [String] = []
        var unserviced: [(String, Bool)] = []
        let handler = HostHandler(services: ElpianServices(appId: "a"), options: HostHandlerOptions(
            onPrintln: { printed.append($0) },
            onGetEnvironment: { JSONObject([("platform", "ios")]) },
            onUnservicedApi: { unserviced.append(($0, $1)) }
        ))
        XCTAssertEqual(handler.handleHostCall("println", "[\"hi\"]"), Typed.OK_RESPONSE)
        XCTAssertEqual(handler.handleHostCall("println", "{\"x\": 1}"), Typed.OK_RESPONSE)
        XCTAssertEqual(printed, ["hi", "{\"x\": 1}"])
        XCTAssertEqual(handler.handleHostCall("env.get", ""), "{\"type\":\"object\",\"data\":{\"value\":{\"platform\":\"ios\"}}}")
        XCTAssertEqual(handler.handleHostCall("stringify", "abc"), "{\"type\":\"string\",\"data\":{\"value\":\"abc\"}}")
        XCTAssertEqual(handler.handleHostCall("no.such.api", ""), Typed.NULL_RESPONSE)
        XCTAssertEqual(unserviced.first?.0, "no.such.api")
        XCTAssertEqual(unserviced.first?.1, false)
    }

    func testRenderOfBareStringAndScopeKey() {
        var got: (JSONObject, String?)?
        let handler = HostHandler(services: ElpianServices(), options: HostHandlerOptions(onRender: { got = ($0, $1) }))
        _ = handler.handleHostCall("render", "[\"hello\", \" scope \"]")
        XCTAssertEqual(got.map { JSON.stringify($0.0) }, "{\"type\":\"Text\",\"props\":{\"text\":\"hello\"}}")
        XCTAssertEqual(got?.1, "scope")
        _ = handler.handleHostCall("render", "[{\"type\": \"div\"}, \"null\"]")
        XCTAssertEqual(got?.0.s("type"), "div")
        XCTAssertNil(got?.1)
    }

    func testPolicyRefusal() {
        var refused: [String] = []
        let handler = HostHandler(services: ElpianServices(), options: HostHandlerOptions(
            onAuthorize: { $0 != "render" },
            onCallRefused: { refused.append($0) }
        ))
        XCTAssertEqual(handler.handleHostCall("render", "[]"), Typed.NULL_RESPONSE)
        XCTAssertEqual(refused, ["render"])
        XCTAssertEqual(handler.handleHostCall("println", "[\"x\"]"), Typed.OK_RESPONSE)
    }

    func testDomApis() {
        var updates: [String] = []
        let services = ElpianServices()
        let handler = HostHandler(services: services, options: HostHandlerOptions(onUpdateApp: { updates.append(JSON.stringify($0)) }))
        let created = handler.handleHostCall("dom.createElement", "{\"tagName\": \"div\", \"id\": \"box\", \"classes\": [\"a\"]}")
        XCTAssertTrue(created.hasPrefix("{\"type\":\"object\""))
        _ = handler.handleHostCall("dom.createElement", "{\"tagName\": \"span\", \"id\": \"kid\"}")
        _ = handler.handleHostCall("dom.appendChild", "{\"parentId\": \"box\", \"childId\": \"kid\"}")
        XCTAssertEqual(services.dom.getElementById("box")?.children.count, 1)
        _ = handler.handleHostCall("dom.setAttribute", "{\"id\": \"box\", \"name\": \"role\", \"value\": \"main\"}")
        XCTAssertEqual(handler.handleHostCall("dom.getAttribute", "{\"id\": \"box\", \"name\": \"role\"}"), Typed.makeResponse("string", "main"))
        XCTAssertEqual(handler.handleHostCall("dom.hasClass", "{\"id\": \"box\", \"className\": \"a\"}"), Typed.makeResponse("bool", true))
        _ = handler.handleHostCall("dom.toggleClass", "{\"id\": \"box\", \"className\": \"a\"}")
        XCTAssertEqual(handler.handleHostCall("dom.hasClass", "{\"id\": \"box\", \"className\": \"a\"}"), Typed.makeResponse("bool", false))
        _ = handler.handleHostCall("dom.setStyle", "{\"id\": \"box\", \"property\": \"color\", \"value\": \"red\"}")
        XCTAssertEqual(handler.handleHostCall("dom.getStyle", "{\"id\": \"box\", \"property\": \"color\"}"), Typed.makeResponse("string", "red"))
        _ = handler.handleHostCall("dom.addEventListener", "{\"id\": \"box\", \"event\": \"click\", \"callback\": \"onBox\"}")
        _ = handler.handleHostCall("dom.dispatchEvent", "{\"id\": \"box\", \"event\": \"click\", \"data\": 7}")
        XCTAssertEqual(updates, ["{\"domEvent\":\"onBox\",\"elementId\":\"box\",\"event\":\"click\",\"data\":7}"])
        XCTAssertEqual(handler.handleHostCall("dom.getElementById", "{\"id\": \"missing\"}"), Typed.makeResponse("object", nil))
    }

    func testCanvasApis() {
        let services = ElpianServices()
        let handler = HostHandler(services: services)
        _ = handler.handleHostCall("canvas.addCommand", "{\"type\": \"fillRect\", \"params\": {\"x\": 1}, \"id\": \"r\"}")
        _ = handler.handleHostCall("canvas.addCommand", "{\"type\": \"notACommand\"}")
        _ = handler.handleHostCall("canvas.fillRect", "{\"x\": 2}")
        XCTAssertEqual(services.canvas.commands.count, 2)
        XCTAssertEqual(
            handler.handleHostCall("canvas.getCommands", ""),
            "{\"type\":\"array\",\"data\":{\"value\":[{\"type\":\"fillRect\",\"params\":{\"x\":1},\"id\":\"r\"},{\"type\":\"fillRect\",\"params\":{\"x\":2}}]}}"
        )
        _ = handler.handleHostCall("canvas.clear", "")
        XCTAssertEqual(services.canvas.commands.count, 0)

        _ = handler.handleHostCall("canvas.ctx.create", "{\"id\": \"k\", \"width\": 4, \"height\": 5}")
        let ctx = services.canvasContexts["default::k"]!
        _ = handler.handleHostCall("canvas.ctx.setSize", "{\"id\": \"k\", \"width\": 8}")
        XCTAssertEqual(ctx.width, 8)
        XCTAssertEqual(ctx.height, 5)
        _ = handler.handleHostCall("canvas.ctx.addCommands", "{\"id\": \"k\", \"commands\": [{\"type\": \"fillRect\"}, 3, {\"type\": \"clearRect\"}]}")
        XCTAssertEqual(ctx.commands.count, 2)
        _ = handler.handleHostCall("canvas.ctx.dispose", "{\"id\": \"k\"}")
        XCTAssertNil(services.canvasContexts["default::k"])
    }

    func testAsHostCallHandler() {
        let handler = HostHandler(services: ElpianServices())
        let fn = handler.asHostCallHandler()
        if case let .now(reply) = fn("stringify", "x") {
            XCTAssertEqual(reply, Typed.makeResponse("string", "x"))
        } else {
            XCTFail("expected a synchronous reply")
        }
    }
}
