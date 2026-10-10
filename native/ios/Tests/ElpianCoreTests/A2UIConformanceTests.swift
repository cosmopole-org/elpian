import XCTest
@testable import ElpianCore

/**
 * The vendored A2UI conformance suites (a2ui/conformance/json) against the
 * Swift renderer — the port of native/web/test/a2ui/conformance.test.mjs, with
 * the same applicability and the same v1.0 → v0.9.1 translation ([fromV1]).
 * Skipped, with the reason recorded: node_resolution (its `test_data/node`
 * fixtures are not vendored, and it asserts web_core's reactive-node
 * identity/emission model), cases with inline custom catalogs (this renderer
 * ships the basic catalog).
 */
final class A2UIConformanceTests: XCTestCase {
    static var passed = 0
    static var skipped: [String] = []

    override class func tearDown() {
        print("A2UI conformance: \(passed) cases passed, \(skipped.count) skipped")
        for s in skipped { print("  skipped \(s)") }
        super.tearDown()
    }

    private func skip(_ name: String, _ reason: String) { A2UIConformanceTests.skipped.append("\(name): \(reason)") }
    private func pass() { A2UIConformanceTests.passed += 1 }

    private func expectError(_ block: () throws -> Void, _ expected: JSONObject, _ where_: String) {
        do {
            try block()
            XCTFail("\(where_): expected \(jsString(expected["category"])) error")
        } catch {
            guard let e = error as? A2UIError else { return XCTFail("\(where_): not an A2UIError: \(error)") }
            if let c = expected["category"] as? String { XCTAssertEqual(e.category.rawValue, c, where_) }
            if let m = expected["message"] as? String { XCTAssertTrue(e.message.contains(m), "\(where_): \"\(e.message)\" should contain \"\(m)\"") }
        }
    }

    // ------------------------------------------------------------------------
    // v1.0 → v0.9.1 translation
    // ------------------------------------------------------------------------

    private func renameKeys(_ v: Any?) -> Any? {
        if let a = asArray(v) { return a.map { renameKeys($0) } as [Any?] }
        if let o = asMap(v) {
            let out = JSONObject()
            for (k, x) in o { out[k == "@call" ? "call" : k == "@path" ? "path" : k] = renameKeys(x) }
            return out
        }
        return flattenOptional(v)
    }

    private func fromV1(_ messages: [Any?]) -> [Any?] {
        var out: [Any?] = []
        for raw in messages {
            let m = asMap(renameKeys(raw))!
            if let cs0 = asMap(m["createSurface"]) {
                let cs = cs0.copy()
                let dataModel = cs.has("dataModel") ? cs["dataModel"] : nil
                let hasData = cs.has("dataModel")
                let components = cs["components"]
                cs.removeValue(forKey: "dataModel")
                cs.removeValue(forKey: "components")
                if (cs["catalogId"] as? String) == "basic" { cs["catalogId"] = BASIC_CATALOG_ID }
                let sid = cs["surfaceId"]
                out.append(JSONObject([("version", "v0.9.1"), ("createSurface", cs)]))
                if hasData {
                    out.append(JSONObject([("version", "v0.9.1"), ("updateDataModel", JSONObject([("surfaceId", sid), ("path", "/"), ("value", dataModel)]))]))
                }
                if components != nil {
                    out.append(JSONObject([("version", "v0.9.1"), ("updateComponents", JSONObject([("surfaceId", sid), ("components", components)]))]))
                }
            } else {
                let rest = JSONObject([("version", "v0.9.1")])
                for (k, x) in m where k != "version" { rest[k] = x }
                out.append(rest)
            }
        }
        return out
    }

    private func payloads(_ c: JSONObject) -> [Any?] {
        (asArray(c["steps"]) ?? []).flatMap { asArray(asMap($0)?["payload"]) ?? [] }
    }

    // ------------------------------------------------------------------------
    // data_model
    // ------------------------------------------------------------------------

    func testDataModel() throws {
        for c in A2UIFiles.conformance("data_model") {
            let name = jsString(c["name"])
            let model = DataModel(c.has("initial") ? c["initial"] : JSONObject())
            var notified: [String] = []
            for p in asArray(c["watch"]) ?? [] {
                let path = jsString(p)
                try model.watch(path) { _, _ in notified.append(path) }
            }
            for raw in asArray(c["steps"]) ?? [] {
                let step = asMap(raw)!
                notified.removeAll()
                let where_ = "\(name) \(JSON.stringify(step))"
                let op = jsString(step["op"])
                let path = jsString(step["path"] ?? "/")
                if let expected = asMap(step["expect_error"]) {
                    expectError({
                        switch op {
                        case "get": _ = try model.get(path)
                        case "delete": try model.delete(path)
                        default: try model.set(path, step["value"])
                        }
                    }, expected, where_)
                    continue
                }
                switch op {
                case "get":
                    let v = try model.get(path)
                    if step.has("expect") { XCTAssertTrue(jsonEqual(v, step["expect"]), "\(where_): got \(JSON.stringify(v))") }
                    // Absent: no value, or a null padding slot (Swift cannot tell them apart).
                    if jsBool(step["expect_absent"]) == true { XCTAssertNil(v, where_) }
                    if (step["expect_type"] as? String) == "list" { XCTAssertNotNil(asArray(v), where_) }
                    if (step["expect_type"] as? String) == "object" { XCTAssertTrue(v is JSONObject, where_) }
                case "set":
                    // A missing `value` is the TypeScript `undefined`: a delete.
                    if step.has("value") { try model.set(path, step["value"]) } else { try model.delete(path) }
                case "delete":
                    try model.delete(path)
                case "dispose":
                    model.dispose()
                default:
                    XCTFail("unknown op \(op)")
                }
                if let exp = asArray(step["expect_notified"]) {
                    XCTAssertEqual(notified.sorted(), exp.map { jsString($0) }.sorted(), where_)
                }
                for (p, v) in asMap(step["expect_values"]) ?? JSONObject() {
                    let got = try model.get(p)
                    XCTAssertTrue(jsonEqual(got, v), "\(where_) at \(p): \(JSON.stringify(got))")
                }
            }
            pass()
        }
    }

    // ------------------------------------------------------------------------
    // data_context
    // ------------------------------------------------------------------------

    func testDataContext() {
        for c in A2UIFiles.conformance("data_context") {
            XCTAssertEqual(c["action"] as? String, "resolve_path")
            let args = asMap(c["args"])!
            XCTAssertEqual(resolvePath(jsString(args["path"]), args["contextPath"] as? String), c["expect"] as? String, jsString(c["name"]))
            pass()
        }
    }

    // ------------------------------------------------------------------------
    // expressions
    // ------------------------------------------------------------------------

    private func rootText(_ messages: [Any?], _ where_: String) -> String {
        let p = A2UIProcessor(A2UIProcessorOptions(validation: .strict))
        let errors = p.processAll(messages)
        XCTAssertEqual(errors.map { $0.message }, [], where_)
        guard let s = p.surfaces.first, let root = s.components["root"] else {
            XCTFail("\(where_): no root")
            return ""
        }
        return (try? s.context().string(root["text"])) ?? "<error>"
    }

    func testExpressions() throws {
        for c in A2UIFiles.conformance("expressions") {
            let name = jsString(c["name"])
            switch jsString(c["action"]) {
            case "parse_expression_template":
                let input = jsString(c["input"])
                if let e = asMap(c["expect_error"]) {
                    expectError({ _ = try parseExpressionTemplate(input) }, e, name)
                } else {
                    let got = try parseExpressionTemplate(input)
                    XCTAssertTrue(jsonEqual(got, c["expect"]), "\(name): \(JSON.stringify(got)) != \(JSON.stringify(c["expect"]))")
                }
            case "validate":
                let messages = fromV1(payloads(c))
                let expected = (asArray(c["steps"]) ?? []).compactMap { asMap(asMap($0)?["expectError"]) }.first
                if let exp = expected {
                    let issues = messages.flatMap { validateMessage($0, BASIC_CATALOG) }
                    XCTAssertTrue(issues.contains { $0.category.rawValue == jsString(exp["category"]) && $0.message.contains(jsString(exp["message"])) },
                                  "\(name): \(issues.map { $0.message })")
                } else {
                    let expect = asMap(asMap(asMap(asMap(asMap(c["expect"])?["surfaces"])?["main"])?["components"])?["root"])
                    XCTAssertEqual(rootText(messages, name), expect?["text"] as? String, name)
                }
            default:
                XCTFail("unexpected action \(jsString(c["action"]))")
            }
            pass()
        }
    }

    // ------------------------------------------------------------------------
    // data_deletion
    // ------------------------------------------------------------------------

    func testDataDeletion() {
        for c in A2UIFiles.conformance("data_deletion") {
            let name = jsString(c["name"])
            let p = A2UIProcessor(A2UIProcessorOptions(validation: .strict))
            let errors = p.processAll(fromV1(payloads(c)))
            XCTAssertEqual(errors.map { $0.message }, [], name)
            for (sid, exp) in asMap(asMap(c["expect"])?["surfaces"]) ?? JSONObject() {
                let got = p.dataModel(sid)
                XCTAssertTrue(jsonEqual(got, asMap(exp)?["dataModel"]), "\(name): \(JSON.stringify(got))")
            }
            pass()
        }
    }

    // ------------------------------------------------------------------------
    // actions
    // ------------------------------------------------------------------------

    func testActions() {
        for c in A2UIFiles.conformance("actions") {
            let name = jsString(c["name"])
            let p = A2UIProcessor()
            let sid = (c["surfaceId"] as? String) ?? "main"
            p.process(JSONObject([("version", "v0.9.1"), ("createSurface", JSONObject([("surfaceId", sid), ("catalogId", BASIC_CATALOG_ID)]))]))
            if c.has("dataModel") {
                p.process(JSONObject([("version", "v0.9.1"), ("updateDataModel", JSONObject([("surfaceId", sid), ("path", "/"), ("value", c["dataModel"])]))]))
            }
            var emitted: [A2UIClientAction] = []
            p.on { e in if case .action(let a) = e { emitted.append(a) } }
            guard let action = p.dispatchAction(sid, "btn", c["actionPayload"], (c["scope"] as? String) ?? "/") else {
                XCTFail(name)
                continue
            }
            XCTAssertEqual(emitted.count, 1, name)
            XCTAssertEqual(action.surfaceId, sid)
            XCTAssertEqual(action.sourceComponentId, "btn")
            XCTAssertNotNil(ISO8601DateFormatter.withFractions.date(from: action.timestamp), action.timestamp)
            let exp = asMap(c["expectDispatched"])!
            XCTAssertEqual(action.name, exp["name"] as? String, name)
            XCTAssertTrue(jsonEqual(action.context, asMap(exp["context"]) ?? JSONObject()), "\(name): \(JSON.stringify(action.context))")
            if let u = exp["userMessage"] as? String { XCTAssertEqual(action.userMessage, u, name) }
            pass()
        }
    }

    // ------------------------------------------------------------------------
    // accessibility
    // ------------------------------------------------------------------------

    /** The v1.0 `surface` shorthand → v0.9.1 components. */
    private func a11yComponents(_ surface: JSONObject) -> [Any?] {
        var comps: [Any?] = []
        func conv(_ id: String, _ c: JSONObject) {
            let out = JSONObject([("id", id)])
            for (k, v) in asMap(renameKeys(c))! where k != "id" { out[k] = v }
            out.removeValue(forKey: "components")
            if (out["component"] as? String) == "Container" {
                out["component"] = "Column"
                out["children"] = out["child"] != nil ? [out["child"]] as [Any?] : [Any?]()
                out.removeValue(forKey: "child")
            }
            if (out["component"] as? String) == "Button", let title = out["title"] as? String {
                comps.append(JSONObject([("id", "\(id)__label"), ("component", "Text"), ("text", title)]))
                out["child"] = "\(id)__label"
                out["action"] = JSONObject([("event", JSONObject([("name", "press")]))])
                out.removeValue(forKey: "title")
            }
            if (out["component"] as? String) == "CheckBox", out.has("checked") {
                out["value"] = out["checked"]
                out.removeValue(forKey: "checked")
            }
            if (out["component"] as? String) == "ChoicePicker", out.has("selectedIndex") {
                let i = Int(jsNumber(out["selectedIndex"]) ?? 0)
                out["value"] = [asMap(asArray(out["options"])?[i])?["value"]] as [Any?]
                out.removeValue(forKey: "selectedIndex")
            }
            comps.append(out)
        }
        conv(jsString(surface["id"]), surface)
        for (id, c) in asMap(surface["components"]) ?? JSONObject() { conv(id, asMap(c)!) }
        return comps
    }

    func testAccessibility() {
        for c in A2UIFiles.conformance("accessibility") {
            let name = jsString(c["name"])
            let p = A2UIProcessor(A2UIProcessorOptions(validation: .off))
            p.process(JSONObject([("version", "v0.9.1"), ("createSurface", JSONObject([("surfaceId", "s"), ("catalogId", BASIC_CATALOG_ID)]))]))
            p.process(JSONObject([("version", "v0.9.1"), ("updateComponents", JSONObject([("surfaceId", "s"), ("components", a11yComponents(asMap(c["surface"])!))]))]))
            let s = p.surface("s")!
            for (id, exp) in asMap(asMap(c["assertions"])?["accessibilityTree"]) ?? JSONObject() {
                let node = describeAccessibility(s, s.components[id]!).toJson()
                for (k, v) in asMap(exp)! {
                    if let b = asMap(v), b.has("path") {
                        XCTAssertEqual(asMap(node["bindings"])?[k] as? String, b["path"] as? String, "\(name) \(id).\(k)")
                    } else {
                        XCTAssertTrue(jsonEqual(node[k], v), "\(name) \(id).\(k): \(JSON.stringify(node[k]))")
                    }
                }
            }
            pass()
        }
    }

    // ------------------------------------------------------------------------
    // validator_v0_9 and composition_constraints
    // ------------------------------------------------------------------------

    private func dotted(_ path: String?) -> String {
        // `/0/createSurface/surfaceId` → `messages.0.createSurface.surfaceId`
        "messages" + (path ?? "").components(separatedBy: "/").filter { !$0.isEmpty }.map { ".\($0)" }.joined()
    }

    private func checkExpected(_ issues: [A2UIError], _ expected: Any?, _ where_: String) {
        XCTAssertFalse(issues.isEmpty, "\(where_): expected an error")
        if let s = expected as? String {
            XCTAssertTrue(issues.contains { $0.message.contains(s) }, "\(where_): \(issues.map { $0.message }) should mention \"\(s)\"")
            return
        }
        guard let exp = asMap(expected) else { return }
        if let cat = exp["category"] as? String { XCTAssertTrue(issues.allSatisfy { $0.category.rawValue == cat }, where_) }
        if let m = exp["message"] as? String { XCTAssertTrue(issues.contains { $0.message.contains(m) }, "\(where_): \(issues.map { $0.message })") }
        for raw in asArray(exp["details"]) ?? [] {
            let d = asMap(raw)!
            XCTAssertTrue(issues.contains { dotted($0.path) == jsString(d["path"]) && $0.issue?.rawValue == jsString(d["code"]) },
                          "\(where_): no issue at \(jsString(d["path"])) (\(jsString(d["code"]))); got \(issues.map { "\(dotted($0.path)) \($0.issue?.rawValue ?? "")" })")
        }
    }

    func testValidatorV09() {
        for c in A2UIFiles.conformance("validator_v0_9") {
            let name = jsString(c["name"])
            if c.has("catalog") {
                skip(name, "inline custom catalog (only the basic catalog is built in)")
                continue
            }
            let v = A2UIValidator(BASIC_CATALOG, strict: jsBool(c["strictMode"]) == true, requireVersion: true)
            for (i, raw) in (asArray(c["steps"]) ?? []).enumerated() {
                let step = asMap(raw)!
                let issues = v.validateBatch(asArray(step["messages"]) ?? [])
                if step.has("expectError") {
                    checkExpected(issues, step["expectError"], "\(name) step \(i)")
                } else {
                    XCTAssertEqual(issues.map { $0.message }, [], "\(name) step \(i)")
                }
            }
            XCTAssertFalse(c.has("expectError"), "\(name): case-level expectError not handled")
            pass()
        }
    }

    func testCompositionConstraints() {
        for c in A2UIFiles.conformance("composition_constraints") {
            let name = jsString(c["name"])
            if asMap(c["catalog"])?.has("catalogSchema") == true {
                skip(name, "v1.0 allowedParents/allowedChildren on an inline custom catalog")
                continue
            }
            let p = A2UIProcessor(A2UIProcessorOptions(validation: .strict))
            XCTAssertEqual(p.processAll(fromV1(payloads(c))).map { $0.message }, [], name)
            let v = A2UIValidator(BASIC_CATALOG, strict: true)
            XCTAssertEqual(v.validateBatch(fromV1(payloads(c))).map { $0.message }, [], name)
            for (sid, exp) in asMap(asMap(c["expect"])?["surfaces"]) ?? JSONObject() {
                for (id, comp) in asMap(asMap(exp)?["components"]) ?? JSONObject() {
                    let got = p.surface(sid)!.components[id]!.copy()
                    got.removeValue(forKey: "id")
                    let want = asMap(comp)!.copy()
                    want.removeValue(forKey: "id")
                    XCTAssertTrue(jsonEqual(got, want), "\(name) \(id)")
                }
            }
            pass()
        }
    }

    func testNodeResolution() {
        for c in A2UIFiles.conformance("node_resolution") {
            skip(jsString(c["name"]), "fixtures (test_data/node/*.yaml) are not vendored; asserts web_core reactive-node identity")
        }
    }
}

extension ISO8601DateFormatter {
    static let withFractions: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
