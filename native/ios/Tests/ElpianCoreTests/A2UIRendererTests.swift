import XCTest
@testable import ElpianCore

/**
 * The port of native/web/test/a2ui/renderer.test.mjs: the basic catalog
 * examples through processor + lowering + reconcile + layout, the catalog
 * table against catalog.json, functions, two-way binding, Tabs / Modal
 * state, the transport's chunk-split NDJSON decoding, a conversation against
 * a fake agent stream, the A2UISurface widget with the agent host APIs, and
 * the reconciler's keyed-removal regression.
 */
@MainActor
final class A2UIRendererTests: XCTestCase {
    private var platform: A2UITestPlatform!
    private let utc = TimeZone(secondsFromGMT: 0)!

    override func setUp() async throws {
        platform = A2UITestPlatform()
        setPlatform(platform)
    }

    override func tearDown() async throws {
        await platform.drain()
        // Surfaces set the global CSS environment; restore the default other suites assume.
        CssEnvironment.update(viewportWidth: 1280, viewportHeight: 800, safeArea: .zero, rootFontSize: 16, devicePixelRatio: 1)
    }

    private func hooks(_ p: A2UIProcessor, _ log: Box<[(String, Any?)]>) -> LoweringHooks {
        LoweringHooks(
            write: { sid, path, value in
                log.value.append(("write", value))
                p.setData(sid, path, value)
            },
            action: { sid, id, action, scope in log.value.append(("action", p.dispatchAction(sid, id, action, scope))) },
            invalidate: { log.value.append(("invalidate", nil)) },
            error: { e in log.value.append(("error", e.message)) }
        )
    }

    // ------------------------------------------------------------------------
    // Catalog
    // ------------------------------------------------------------------------

    func testBasicCatalogTableMatchesCatalogJson() async {
        let json = A2UIFiles.catalog
        XCTAssertEqual(BASIC_CATALOG.id, json["catalogId"] as? String)
        let comps = asMap(json["components"])!
        XCTAssertEqual(BASIC_COMPONENTS.keys.sorted(), comps.keys.sorted())
        for (name, raw) in comps {
            let allOf = asArray(asMap(raw)?["allOf"])!.compactMap { asMap($0) }
            let own = allOf.first { asMap($0["properties"])?.has("component") == true }!
            let props = asMap(own["properties"])!.keys.filter { $0 != "component" }
            let checkable = allOf.contains { ($0["$ref"] as? String)?.hasSuffix("Checkable") == true }
            let spec = BASIC_COMPONENTS[name]!
            XCTAssertEqual(spec.propNames.filter { $0 != "checks" }.sorted(), props.sorted(), name)
            XCTAssertEqual(spec.props["checks"] != nil, checkable, "\(name) checks")
            let required = (asArray(own["required"]) ?? []).map { jsString($0) }.filter { $0 != "component" }
            XCTAssertEqual(spec.required.sorted(), required.sorted(), "\(name) required")
            for p in props {
                if let e = asArray(asMap(asMap(own["properties"])?[p])?["enum"]) {
                    XCTAssertEqual(spec.props[p]?.enumValues?.sorted(), e.map { jsString($0) }.sorted(), "\(name).\(p)")
                }
            }
        }
        XCTAssertEqual(COMMON_PROPS.keys.sorted(), ["accessibility", "component", "id", "weight"])
        let fns = asMap(json["functions"])!
        XCTAssertEqual(BASIC_FUNCTION_SPECS.keys.sorted(), fns.keys.sorted())
        for (name, raw) in fns {
            let schema = asMap(asMap(raw)?["properties"])!
            XCTAssertEqual(BASIC_FUNCTION_SPECS[name]!.argNames.sorted(), asMap(asMap(schema["args"])?["properties"])!.keys.sorted(), name)
            XCTAssertEqual(BASIC_FUNCTION_SPECS[name]!.returnType.rawValue, asMap(schema["returnType"])?["const"] as? String, name)
        }
        let iconSchema = asMap(asArray(asMap(comps["Icon"])?["allOf"])?[2])
        let iconEnum = asArray(asMap(asArray(asMap(asMap(iconSchema?["properties"])?["name"])?["oneOf"])?[0])?["enum"])!
        XCTAssertEqual(ICON_NAMES.sorted(), iconEnum.map { jsString($0) }.sorted())
    }

    func testEveryCatalogIconMapsToAMaterialIcon() async {
        for name in ICON_NAMES {
            XCTAssertNotNil(MATERIAL_ICON_CODEPOINTS[materialIconName(name)], "\(name) → \(materialIconName(name))")
        }
    }

    // ------------------------------------------------------------------------
    // Examples
    // ------------------------------------------------------------------------

    func testAllBasicCatalogExamplesProcessLowerAndLayOut() async {
        let all = A2UIFiles.examples()
        XCTAssertEqual(all.count, 43)
        var n = 0
        for example in all {
            let file = example.file
            let messages = asArray(example.json["messages"]) ?? []
            let processor = A2UIProcessor(A2UIProcessorOptions(validation: .strict, host: EvaluationHost(locale: "en-US", timeZone: utc)))
            let errors = processor.processAll(messages)
            XCTAssertEqual(errors.map { "\($0.path ?? ""): \($0.message)" }, [], "\(file) processing errors")
            // The whole batch also passes strict topology validation
            // (incremental examples replace placeholders, leaving them unreachable — allowed).
            let topology = A2UIValidator(BASIC_CATALOG, strict: true).validateBatch(messages).map { $0.message }
            let orphanRe = JSRegex("^Component '(.+)' is not reachable")
            let orphans = Set(topology.compactMap { (orphanRe.exec($0)?[1]) ?? nil })
            XCTAssertEqual(topology.filter { !$0.contains("is not reachable") }, [], "\(file) topology")
            XCTAssertFalse(processor.surfaces.isEmpty, file)
            for surface in processor.surfaces {
                XCTAssertTrue(surface.isReady, "\(file) \(surface.id) has a root")
                let log = Box<[(String, Any?)]>([])
                let result = lowerSurface(surface, LoweringOptions(hooks: hooks(processor, log), state: A2UIUiState(), expandAll: true))
                XCTAssertEqual(result.placeholders.map { $0.reason }, [], "\(file) placeholders")
                XCTAssertEqual(log.value.filter { $0.0 == "error" }.map { jsString($0.1) }, [], "\(file) evaluation errors")
                // Every component is lowered — except a template whose list is empty.
                let lowered = Set(result.lowered.map { String($0.split(separator: "@", maxSplits: 1)[0]) })
                for id in surface.components.keys where !lowered.contains(id) && !orphans.contains(id) {
                    let asTemplate = surface.components.values.contains { asMap($0["children"])?["componentId"] as? String == id }
                    XCTAssertTrue(asTemplate, "\(file): \(id) was not lowered")
                }
                n += 1
                let s = ElpianSurface("a2ui-example-\(n)")
                s.setContent(result.node)
                s.renderNow()
                let ops = s.owner.flush(0)
                XCTAssertFalse(ops.isEmpty, "\(file) committed view ops")
                XCTAssertGreaterThan(s.owner.root?.size.height ?? 0, 0, "\(file) laid out with height")
                var types = Set<String>()
                a2uiWalk(result.node) { types.insert(jsString($0["type"])) }
                for t in types { XCTAssertNotNil(s.engine.services.registry[t], "\(file): lowered to unregistered widget \(t)") }
                XCTAssertFalse(platform.logs.contains { $0.contains("render error") || $0.contains("Unknown widget") }, platform.logs.joined(separator: "\n"))
                s.dispose()
            }
        }
    }

    // ------------------------------------------------------------------------
    // Binding, checks, actions; Tabs and Modal
    // ------------------------------------------------------------------------

    func testTwoWayBindingChecksAndActionsOnAForm() async {
        let p = A2UIProcessor()
        p.processAll([
            a2uiJson(##"{"version": "v0.9.1", "createSurface": {"surfaceId": "f", "catalogId": "\##(BASIC_CATALOG_ID)", "theme": {"primaryColor": "#00BFFF"}}}"##),
            a2uiJson(#"""
            {"version": "v0.9.1", "updateComponents": {"surfaceId": "f", "components": [
              {"id": "root", "component": "Column", "children": ["name", "echo", "go"]},
              {"id": "name", "component": "TextField", "label": "Name", "value": {"path": "/form/name"},
               "checks": [{"condition": {"call": "required", "args": {"value": {"path": "/form/name"}}}, "message": "Required"}]},
              {"id": "echo", "component": "Text", "text": {"call": "formatString", "args": {"value": "Hi ${/form/name}"}, "returnType": "string"}},
              {"id": "go_label", "component": "Text", "text": "Go"},
              {"id": "go", "component": "Button", "child": "go_label", "variant": "primary",
               "action": {"event": {"name": "submit", "context": {"name": {"path": "/form/name"}}}},
               "checks": [{"condition": {"call": "required", "args": {"value": {"path": "/form/name"}}}, "message": "Required"}]}
            ]}}
            """#),
        ])
        let log = Box<[(String, Any?)]>([])
        let state = A2UIUiState()
        let lower = { lowerSurface(p.surface("f")!, LoweringOptions(hooks: self.hooks(p, log), state: state)).node }
        var tree = lower()
        let button = a2uiFind(tree) { $0["type"] as? String == "Button" }
        XCTAssertEqual(a2uiProps(button)["disabled"] as? Bool, true, "disabled while the check fails")
        XCTAssertEqual(asMap(a2uiProps(button)["style"])?["backgroundColor"] as? String, "#00BFFF", "theme primary color")
        a2uiFire(a2uiFind(tree) { $0["type"] as? String == "TextField" }, "input", value: "Ada")
        XCTAssertTrue(jsonEqual(p.dataModel("f"), a2uiJson(#"{"form": {"name": "Ada"}}"#)))
        tree = lower()
        XCTAssertEqual(a2uiProps(a2uiFind(tree) { $0["type"] as? String == "TextField" })["value"] as? String, "Ada")
        XCTAssertNotNil(a2uiFind(tree) { $0["type"] as? String == "Text" && a2uiProps($0)["text"] as? String == "Hi Ada" })
        let enabled = a2uiFind(tree) { $0["type"] as? String == "Button" }
        XCTAssertEqual(a2uiProps(enabled)["disabled"] as? Bool, false)
        a2uiFire(enabled, "click")
        guard let action = log.value.first(where: { $0.0 == "action" })?.1 as? A2UIClientAction else { return XCTFail("no action") }
        XCTAssertEqual(action.name, "submit")
        XCTAssertEqual(action.surfaceId, "f")
        XCTAssertEqual(action.sourceComponentId, "go")
        XCTAssertTrue(jsonEqual(action.context, a2uiJson(#"{"name": "Ada"}"#)))
        // A server update re-renders the bound field.
        p.process(a2uiJson(#"{"version": "v0.9.1", "updateDataModel": {"surfaceId": "f", "path": "/form/name", "value": "Grace"}}"#))
        XCTAssertEqual(a2uiProps(a2uiFind(lower()) { $0["type"] as? String == "TextField" })["value"] as? String, "Grace")
    }

    func testTabsAndModalKeepUiState() async {
        let p = A2UIProcessor()
        p.processAll(asArray(A2UIFiles.example("36_modal.json")["messages"]) ?? [])
        let s = p.surfaces[0]
        let state = A2UIUiState()
        let log = Box<[(String, Any?)]>([])
        let tree = lowerSurface(s, LoweringOptions(hooks: hooks(p, log), state: state))
        XCTAssertEqual(tree.node["type"] as? String, "Column", "no overlay while closed")
        a2uiFire(a2uiFind(tree.node) { $0["type"] as? String == "Button" }, "click")
        let open = lowerSurface(s, LoweringOptions(hooks: hooks(p, log), state: state))
        XCTAssertEqual(open.node["type"] as? String, "ConstrainedBox", "the dialog overlays the surface")
        let barrier = a2uiFind(open.node) { ($0["key"] as? String)?.hasSuffix("/barrier") == true }
        a2uiFire(barrier, "click")
        XCTAssertEqual(lowerSurface(s, LoweringOptions(hooks: hooks(p, log), state: state)).node["type"] as? String, "Column", "closed by the barrier")
    }

    // ------------------------------------------------------------------------
    // Functions
    // ------------------------------------------------------------------------

    func testFunctionsFormattingAndValidation() async throws {
        let p = A2UIProcessor(A2UIProcessorOptions(locale: "en-US", timeZone: utc))
        p.process(a2uiJson(#"{"version": "v0.9.1", "createSurface": {"surfaceId": "s", "catalogId": "\#(BASIC_CATALOG_ID)"}}"#))
        let ctx = p.surface("s")!.context()
        func call(_ name: String, _ args: String) throws -> Any? { try ctx.call(name, a2uiJson(args)) }
        XCTAssertEqual(try call("formatNumber", #"{"value": 1234.5, "decimals": 2}"#) as? String, "1,234.50")
        XCTAssertEqual(try call("formatNumber", #"{"value": 1234.5, "decimals": 0, "grouping": false}"#) as? String, "1235")
        XCTAssertEqual(try call("formatCurrency", #"{"value": 49.99, "currency": "EUR"}"#) as? String, "€49.99")
        XCTAssertEqual(try call("formatDate", #"{"value": "2026-02-02T15:17:00Z", "format": "EEEE, MMM d 'at' h:mm a"}"#) as? String, "Monday, Feb 2 at 3:17 PM")
        var dc = DateComponents()
        dc.year = 2026
        dc.month = 1
        dc.day = 16
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        XCTAssertEqual(formatDatePattern(cal.date(from: dc)!, "yyyy-MM-dd EEE MMMM yy", "en-US", utc), "2026-01-16 Fri January 26")
        XCTAssertEqual(try call("pluralize", #"{"value": 1, "one": "item", "other": "items"}"#) as? String, "item")
        XCTAssertEqual(try call("pluralize", #"{"value": 3, "one": "item", "other": "items"}"#) as? String, "items")
        XCTAssertEqual(try call("pluralize", #"{"value": 0, "zero": "none", "other": "items"}"#) as? String, "none")
        XCTAssertEqual(try call("required", #"{"value": []}"#) as? Bool, false)
        XCTAssertEqual(try call("email", #"{"value": "a@b.co"}"#) as? Bool, true)
        XCTAssertEqual(try call("length", #"{"value": "abc", "min": 4}"#) as? Bool, false)
        XCTAssertEqual(try call("numeric", #"{"value": "5", "min": 1, "max": 10}"#) as? Bool, true)
        XCTAssertEqual(try call("regex", #"{"value": "12345", "pattern": "^[0-9]{5}$"}"#) as? Bool, true)
        XCTAssertEqual(try call("and", #"{"values": [true, {"call": "not", "args": {"value": false}}]}"#) as? Bool, true)
        XCTAssertEqual(try call("or", #"{"values": [false, false]}"#) as? Bool, false)
        XCTAssertThrowsError(try call("openUrl", #"{"url": "javascript:alert(1)"}"#)) { XCTAssertTrue(errorText($0).contains("not allowed")) }
        XCTAssertThrowsError(try call("nope", "{}")) { XCTAssertTrue(errorText($0).contains("Unknown function")) }
    }

    // ------------------------------------------------------------------------
    // Transport
    // ------------------------------------------------------------------------

    func testNdjsonDecodingSurvivesArbitraryChunkSplits() async {
        let lines: [Any?] = [
            a2uiJson(#"{"type": "conversation", "conversationId": "c1"}"#),
            a2uiJson(#"{"version": "v0.9.1", "createSurface": {"surfaceId": "s", "catalogId": "\#(BASIC_CATALOG_ID)"}}"#),
            a2uiJson(#"{"type": "text", "text": "héllo — ünïcode ✓"}"#),
            a2uiJson(#"{"type": "done", "stopReason": "end_turn"}"#),
        ]
        let text = lines.map { JSON.stringify($0) }.joined(separator: "\n") + "\n"
        let chars = Array(text)
        for size in [1, 2, 3, 7, 13, chars.count] {
            let d = NdjsonDecoder()
            var out: [Any?] = []
            var i = 0
            while i < chars.count {
                out += d.push(String(chars[i..<min(chars.count, i + size)]))
                i += size
            }
            out += d.end()
            XCTAssertTrue(jsonEqual(out, lines), "chunk size \(size)")
        }
        // A final line without a newline and a CRLF line (split between \r and \n too).
        let d = NdjsonDecoder()
        XCTAssertTrue(jsonEqual(d.push("{\"a\":1}\r"), [Any?]()))
        XCTAssertTrue(jsonEqual(d.push("\n{\"b\""), [a2uiJson(#"{"a": 1}"#)]))
        XCTAssertTrue(jsonEqual(d.push(":2}"), [Any?]()))
        XCTAssertTrue(jsonEqual(d.end(), [a2uiJson(#"{"b": 2}"#)]))
        // A bad line is reported and skipped.
        var bad: [String] = []
        let d2 = NdjsonDecoder { bad.append($0) }
        XCTAssertTrue(jsonEqual(d2.push("nope\n{\"c\":3}\n"), [a2uiJson(#"{"c": 3}"#)]))
        XCTAssertEqual(bad, ["nope"])
    }

    func testAConversationStreamsATurnFromAFakeAgent() async {
        let body = [
            "{\"type\":\"conversation\",\"conversationId\":\"conv-1\"}\n{\"version\":\"v0.9.1\",\"createSurface\":{\"surfaceId\":\"s\",\"catalogId\":\"\(BASIC_CATALOG_ID)\",\"sendDataModel\":true}}\n",
            "{\"version\":\"v0.9.1\",\"updateComponents\":{\"surfaceId\":\"s\",\"components\":[{\"id\":\"root\",\"component\":\"Text\",\"text\":{\"path\":\"/greeting\"}}]}}\n{\"version\":\"v0.9",
            ".1\",\"updateDataModel\":{\"surfaceId\":\"s\",\"path\":\"/greeting\",\"value\":\"Hello\"}}\n{\"type\":\"text\",\"text\":\"Here you go\"}\n{\"type\":\"done\",\"stopReason\":\"end_turn\"}\n",
        ]
        platform.streamScript = { _ in A2UIStreamScript(chunks: body) }
        let conv = A2UIConversation(A2UIConversationOptions(endpoint: AgentEndpoint(baseUrl: "http://agent.test/", appId: "shop", agent: "assistant")))
        var events: [String] = []
        conv.on { e in
            switch e {
            case .done: events.append("done")
            case .text: events.append("text")
            case .conversation: events.append("conversation")
            default: break
            }
        }
        let turn = conv.send("hi")
        await platform.drain()
        let id = await turn.conversationId.value()
        XCTAssertEqual(id, "conv-1")
        let done = await turn.done.value()
        XCTAssertEqual(done, A2UITurnResult(conversationId: "conv-1", stopReason: "end_turn"))
        XCTAssertEqual(platform.requests[0].url, "http://agent.test/apps/shop/agent/assistant")
        XCTAssertEqual(platform.requests[0].method, "POST")
        XCTAssertTrue(jsonEqual(JSON.parseOrNil(platform.requests[0].body), a2uiJson(#"{"message": "hi", "capabilities": {"supportedCatalogIds": ["\#(BASIC_CATALOG_ID)"]}}"#)))
        XCTAssertEqual(asMap(conv.dataModel("s"))?["greeting"] as? String, "Hello")
        XCTAssertEqual(conv.transcript.map { "\($0.role):\($0.text)" }, ["user:hi", "agent:Here you go"])
        XCTAssertTrue(events.contains("done") && events.contains("text") && events.contains("conversation"))
        // The next turn carries the conversation id and the sendDataModel surface.
        platform.streamScript = { _ in A2UIStreamScript(chunks: ["{\"type\":\"done\",\"stopReason\":\"end_turn\"}"]) }
        let second = conv.sendAction(a2uiJson(#"{"name": "x", "surfaceId": "s", "sourceComponentId": "root", "timestamp": "2026-01-01T00:00:00.000Z", "context": {}}"#))
        await platform.drain()
        _ = await second.done.value()
        let sent = asMap(JSON.parseOrNil(platform.requests[1].body))!
        XCTAssertEqual(sent["conversationId"] as? String, "conv-1")
        XCTAssertEqual(asMap(sent["action"])?["name"] as? String, "x")
        XCTAssertTrue(jsonEqual(sent["dataModel"], a2uiJson(#"{"version": "v0.9.1", "surfaces": {"s": {"greeting": "Hello"}}}"#)))
        // A transport failure ends the turn with an error.
        platform.streamScript = { _ in A2UIStreamScript(chunks: [], error: "HTTP status 500") }
        let failed = conv.send("again")
        await platform.drain()
        let failedResult = await failed.done.value()
        XCTAssertEqual(failedResult.stopReason, "error")
    }

    // ------------------------------------------------------------------------
    // Widget and host APIs
    // ------------------------------------------------------------------------

    func testA2UISurfaceWidgetStaticMessagesEventsAndAgentHostApis() async throws {
        let messages = asArray(A2UIFiles.example("00_interactive-button.json")["messages"]) ?? []
        var got: [Any?] = []
        let listener: ElpianEventListener = { e in got.append(e.value) }
        let surface = ElpianSurface("a2ui-widget")
        surface.setContent(a2uiElement("A2UISurface", JSONObject([("messages", messages)]), key: "w", events: [("a2uiAction", listener)]))
        surface.renderNow()
        _ = surface.owner.flush(0)
        let reg = a2uiRegistry(surface.engine.services)
        let conv = try XCTUnwrap(reg.get("static:w"))
        XCTAssertEqual(conv.processor.surfaces.count, 1)
        let s = conv.processor.surfaces[0]
        let button = try XCTUnwrap(s.components.values.first { $0["component"] as? String == "Button" })
        conv.processor.dispatchAction(s.id, jsString(button["id"]), button["action"])
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(asMap(got.first ?? nil)?["sourceComponentId"] as? String, jsString(button["id"]))
        // Host APIs share the registry.
        let handler = HostHandler(services: surface.engine.services)
        let model = asMap(JSON.parseOrNil(handler.handleHostCall("a2ui.dataModel", JSON.stringify(JSONObject([("conversation", "static:w"), ("surfaceId", s.id)])))))
        XCTAssertTrue(["object", "null"].contains(model?["type"] as? String ?? ""))
        reg.defaults = A2UIDefaults(baseUrl: "http://agent.test", appId: "shop")
        platform.streamScript = { _ in A2UIStreamScript(chunks: ["{\"type\":\"conversation\",\"conversationId\":\"c9\"}\n{\"type\":\"done\",\"stopReason\":\"end_turn\"}\n"]) }
        // The guest SDK's shape: one object inside the argument list.
        guard case .later(let task) = handler.handleHostCallReply("agent.send", #"[{"agent": "assistant", "message": "hello"}]"#) else {
            return XCTFail("agent.send answers later")
        }
        await platform.drain()
        let sent = asMap(JSON.parseOrNil(try await task.value))
        XCTAssertTrue(jsonEqual(asMap(sent?["data"])?["value"], a2uiJson(#"{"conversationId": "c9", "conversation": "agent:assistant"}"#)))
        XCTAssertEqual(platform.requests.last?.url, "http://agent.test/apps/shop/agent/assistant")
        XCTAssertEqual(asMap(JSON.parseOrNil(platform.requests.last?.body))?["message"] as? String, "hello")
        // agent.action fills timestamp and context.
        platform.streamScript = { _ in A2UIStreamScript(chunks: ["{\"type\":\"done\",\"stopReason\":\"end_turn\"}\n"]) }
        guard case .later(let actionTask) = handler.handleHostCallReply("agent.action", #"{"agent": "assistant", "action": {"name": "refresh"}}"#) else {
            return XCTFail("agent.action answers later")
        }
        await platform.drain()
        _ = try await actionTask.value
        let action = asMap(asMap(JSON.parseOrNil(platform.requests.last?.body))?["action"])
        XCTAssertEqual(action?["name"] as? String, "refresh")
        XCTAssertNotNil(action?["timestamp"] as? String)
        XCTAssertTrue(action?["context"] is JSONObject)
        // A refused capability answers null.
        let refusing = HostHandler(services: surface.engine.services, options: HostHandlerOptions(onAuthorize: { _ in false }))
        guard case .now(let refused) = refusing.handleHostCallReply("agent.send", #"{"agent": "assistant", "message": "x"}"#) else { return XCTFail() }
        XCTAssertEqual(refused, Typed.NULL_RESPONSE)
        surface.dispose()
    }

    // ------------------------------------------------------------------------
    // Engine fixes
    // ------------------------------------------------------------------------

    func testReconcilerRemovingAKeyedMiddleChildKeepsTheBottomRunIntact() async {
        // Regression: the bottom run was reconciled against the old middle's objects
        // (the A2UI chat row collapsed to 0x0 when the busy indicator went away).
        let surface = ElpianSurface("reconcile")
        func view(_ busy: Bool) -> JSONObject {
            var children: [JSONObject] = [a2uiJson(#"{"type": "Text", "key": "a", "props": {"text": "a"}}"#)]
            if busy { children.append(a2uiJson(#"{"type": "LinearProgressIndicator", "key": "busy"}"#)) }
            children.append(a2uiJson(#"{"type": "Text", "key": "b", "props": {"text": "b"}}"#))
            children.append(a2uiJson(#"{"type": "Row", "key": "chat", "children": [{"type": "Expanded", "children": [{"type": "TextField", "key": "in", "props": {"hint": "x"}}]}]}"#))
            return JSONObject([("type", "Column"), ("children", children.map { $0 as Any? })])
        }
        for busy in [false, true, false] {
            surface.setContent(view(busy))
            surface.renderNow()
            _ = surface.owner.flush(0)
        }
        var input: RenderObject?
        surface.owner.root?.visit { ro in
            if ro.type == "control" && ro.props["kind"] as? String == "textInput" { input = ro }
        }
        XCTAssertGreaterThan(input?.size.width ?? 0, 0)
        XCTAssertGreaterThan(input?.size.height ?? 0, 0)
        surface.dispose()
    }

    func testTextFieldFollowsValuePropAndHorizontalListViewIsARow() async {
        let engine = ElpianEngine()
        func field(_ value: String) -> W {
            engine.renderFromJson(a2uiJson(#"{"type": "TextField", "key": "tf", "props": {"value": "\#(value)"}}"#))
        }
        func valueOf(_ w: W) -> String? {
            var out: String?
            func visit(_ x: W) {
                if x.t == "control", let v = x.p["view"] as? JSONObject { out = v["value"] as? String }
                for c in x.c ?? [] { visit(c) }
            }
            visit(w)
            return out
        }
        XCTAssertEqual(valueOf(field("a")), "a")
        XCTAssertEqual(valueOf(field("b")), "b", "a changed value prop wins")
        let list = engine.renderFromJson(a2uiJson(#"{"type": "ListView", "props": {"scrollDirection": "horizontal"}, "children": [{"type": "Text", "props": {"text": "x"}}]}"#))
        var flex: W?
        func find(_ x: W) {
            if flex == nil && x.t == "flex" { flex = x }
            for c in x.c ?? [] { find(c) }
        }
        find(list)
        XCTAssertEqual(flex?.p["direction"] as? String, "row")
    }
}

/** A mutable box captured by closures. */
final class Box<T> {
    var value: T
    init(_ value: T) { self.value = value }
}
