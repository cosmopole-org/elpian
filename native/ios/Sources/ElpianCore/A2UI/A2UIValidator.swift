import Foundation

/**
 * Client-side validation of server-to-client messages (a2ui/validator.ts).
 *
 * - [validateMessage] checks one message against the envelope schema and the
 *   catalog's component / function tables (types, enums, required and unknown
 *   properties, binding path syntax, function-call nesting, `formatString`
 *   templates, data nesting).
 * - [A2UIValidator] validates batches statefully and, in strict mode, also
 *   checks the component graph each batch leaves behind: a `root` exists,
 *   no duplicate ids in one message, no self references, dangling
 *   references or cycles, every component is reachable from `root`, and the
 *   tree is at most [MAX_NESTING] deep.
 *
 * Issues are [A2UIError]s of category `ValidationError` whose `path` is a
 * JSON Pointer into the message (the protocol's `VALIDATION_FAILED` shape).
 */
public let SUPPORTED_VERSIONS: [String] = ["v0.9", "v0.9.1"]
public let MESSAGE_KINDS: [String] = ["createSurface", "updateComponents", "updateDataModel", "deleteSurface"]
/** Deepest component tree / data value accepted. */
public let MAX_NESTING = 50
/** Deepest nesting of function calls inside one dynamic value. */
public let MAX_CALL_DEPTH = 5

private func obj(_ v: Any?) -> JSONObject? { flattenOptional(v) as? JSONObject }
private func isStr(_ v: Any?) -> Bool { flattenOptional(v) is String }
private func isNum(_ v: Any?) -> Bool { jsNumber(flattenOptional(v)) != nil }
private func isBoolean(_ v: Any?) -> Bool { jsBool(flattenOptional(v)) != nil }

private final class Issues {
    var list: [A2UIError] = []
    let surfaceId: String?
    init(_ surfaceId: String?) { self.surfaceId = surfaceId }
    func add(_ path: String, _ issue: A2UIIssueCode, _ message: String) {
        list.append(A2UIError(.ValidationError, message, surfaceId: surfaceId, path: path.isEmpty ? "/" : path, issue: issue))
    }
}

/** The message kind ([MESSAGE_KINDS]) of [msg], or nil. */
public func messageKind(_ msg: Any?) -> String? {
    guard let m = obj(msg) else { return nil }
    for k in MESSAGE_KINDS where m.has(k) { return k }
    return nil
}

/** The surface a message addresses, when it names one. */
public func messageSurfaceId(_ msg: Any?) -> String? {
    guard let kind = messageKind(msg), let m = obj(msg), let body = obj(m[kind]) else { return nil }
    return body["surfaceId"] as? String
}

/** Schema-level validation of one server-to-client message ([requireVersion]: insist on the `version` field). */
public func validateMessage(_ msg: Any?, _ catalog: A2UICatalog, requireVersion: Bool = true) -> [A2UIError] {
    let issues = Issues(messageSurfaceId(msg))
    guard let m = obj(msg) else {
        issues.add("/", .type_mismatch, "A message must be a JSON object")
        return issues.list
    }
    if !m.has("version") {
        if requireVersion { issues.add("/version", .missing_field, "The \"version\" field is required") }
    } else if !(isStr(m["version"]) && SUPPORTED_VERSIONS.contains(m["version"] as! String)) {
        issues.add("/version", .invalid_value, "Unsupported version \(JSON.stringify(m["version"])) (expected v0.9 or v0.9.1)")
    }
    let kinds = MESSAGE_KINDS.filter { m.has($0) }
    if kinds.count != 1 {
        issues.add("/", kinds.isEmpty ? .missing_field : .invalid_value, "A message must contain exactly one of \(MESSAGE_KINDS.joined(separator: ", "))")
        return issues.list
    }
    let kind = kinds[0]
    for k in m.keys where k != "version" && k != kind { issues.add("/\(k)", .unknown_field, "Unknown message field \"\(k)\"") }
    let base = "/\(kind)"
    guard let body = obj(m[kind]) else {
        issues.add(base, .type_mismatch, "\"\(kind)\" must be an object")
        return issues.list
    }
    let allowed: [String: [String]] = [
        "createSurface": ["surfaceId", "catalogId", "theme", "sendDataModel"],
        "updateComponents": ["surfaceId", "components"],
        "updateDataModel": ["surfaceId", "path", "value"],
        "deleteSurface": ["surfaceId"],
    ]
    for k in body.keys where !allowed[kind]!.contains(k) { issues.add("\(base)/\(k)", .unknown_field, "Unknown field \"\(k)\" in \(kind)") }
    requireString(issues, body, "surfaceId", base)
    switch kind {
    case "createSurface":
        requireString(issues, body, "catalogId", base)
        if body.has("theme") { validateTheme(issues, body["theme"], "\(base)/theme") }
        if body.has("sendDataModel") && !isBoolean(body["sendDataModel"]) {
            issues.add("\(base)/sendDataModel", .type_mismatch, "\"sendDataModel\" must be a boolean")
        }
    case "updateComponents":
        if !body.has("components") {
            issues.add("\(base)/components", .missing_field, "\"components\" is required")
        } else if let comps = asArray(body["components"]) {
            if comps.isEmpty { issues.add("\(base)/components", .invalid_value, "\"components\" must not be empty") }
            for (i, c) in comps.enumerated() { validateComponent(issues, c, catalog, "\(base)/components/\(i)") }
        } else {
            issues.add("\(base)/components", .type_mismatch, "\"components\" must be a list")
        }
    case "updateDataModel":
        if body.has("path") {
            if let p = flattenOptional(body["path"]) as? String {
                if !isValidPointerSyntax(p) { issues.add("\(base)/path", .invalid_value, "Invalid path syntax: \"\(p)\"") }
            } else {
                issues.add("\(base)/path", .type_mismatch, "\"path\" must be a string")
            }
        }
        if body.has("value") && depthOf(body["value"]) > MAX_NESTING {
            issues.add("\(base)/value", .limit, "Global recursion limit exceeded: the value nests deeper than \(MAX_NESTING) levels")
        }
    default:
        break
    }
    return issues.list
}

private func requireString(_ issues: Issues, _ body: JSONObject, _ key: String, _ base: String) {
    if !body.has(key) {
        issues.add("\(base)/\(key)", .missing_field, "\"\(key)\" is required")
    } else if !isStr(body[key]) {
        issues.add("\(base)/\(key)", .type_mismatch, "\"\(key)\" must be a string")
    }
}

private let HEX_COLOR = JSRegex("^#[0-9a-fA-F]{6}$")

private func validateTheme(_ issues: Issues, _ theme: Any?, _ path: String) {
    guard let t = obj(theme) else {
        issues.add(path, .type_mismatch, "\"theme\" must be an object")
        return
    }
    if t.has("primaryColor") && !((t["primaryColor"] as? String).map { HEX_COLOR.test($0) } ?? false) {
        issues.add("\(path)/primaryColor", .invalid_value, "\"primaryColor\" must be a hex color like #00BFFF")
    }
    for k in ["iconUrl", "agentDisplayName"] where t.has(k) && !isStr(t[k]) {
        issues.add("\(path)/\(k)", .type_mismatch, "\"\(k)\" must be a string")
    }
}

private func depthOf(_ value: Any?) -> Int {
    let v = flattenOptional(value)
    var children: [Any?]
    if let a = asArray(v) {
        children = a
    } else if let o = v as? JSONObject {
        children = o.values
    } else {
        return 0
    }
    var m = 0
    for c in children { m = max(m, depthOf(c)) }
    return m + 1
}

/** Validate one component definition against [catalog]. */
private func validateComponent(_ issues: Issues, _ component: Any?, _ catalog: A2UICatalog, _ base: String) {
    guard let c = obj(component) else {
        issues.add(base, .type_mismatch, "A component must be an object")
        return
    }
    requireString(issues, c, "id", base)
    if !c.has("component") {
        issues.add("\(base)/component", .missing_field, "\"component\" is required")
        return
    }
    guard let type = flattenOptional(c["component"]) as? String else {
        issues.add("\(base)/component", .type_mismatch, "\"component\" must be a string")
        return
    }
    guard let spec = catalog.components[type] else {
        issues.add("\(base)/component", .invalid_value, "Unknown component type \"\(type)\"")
        return
    }
    for (k, v) in c {
        if k == "id" || k == "component" { continue }
        guard let ps = spec.props[k] ?? COMMON_PROPS[k] else {
            issues.add("\(base)/\(k)", .unknown_field, "Unknown property \"\(k)\" on \(type)")
            continue
        }
        checkKind(issues, v, ps.kind, "\(base)/\(k)", catalog)
        if let e = ps.enumValues, let s = flattenOptional(v) as? String, !e.contains(s) {
            issues.add("\(base)/\(k)", .invalid_value, "\"\(k)\" must be one of \(e.joined(separator: ", "))")
        }
    }
    for r in spec.required where !c.has(r) { issues.add("\(base)/\(r)", .missing_field, "\(type) requires \"\(r)\"") }
}

private func isBindingShape(_ v: Any?) -> Bool {
    guard let o = obj(v) else { return false }
    return o.has("path") && o.count == 1
}

private func checkBinding(_ issues: Issues, _ v: Any?, _ path: String) {
    let p = obj(v)?["path"]
    if let s = flattenOptional(p) as? String {
        if !isValidPointerSyntax(s) { issues.add("\(path)/path", .invalid_value, "Invalid path syntax: \"\(s)\"") }
    } else {
        issues.add("\(path)/path", .type_mismatch, "A binding \"path\" must be a string")
    }
}

private func checkKind(_ issues: Issues, _ value: Any?, _ kind: PropKind, _ path: String, _ catalog: A2UICatalog) {
    let v = flattenOptional(value)
    func dynamic(_ literal: (Any?) -> Bool, _ what: String) {
        if literal(v) { return }
        if isBindingShape(v) { return checkBinding(issues, v, path) }
        if let o = obj(v), o.has("call") { return checkCall(issues, o, path, catalog) }
        issues.add(path, .type_mismatch, "Expected \(what), a {\"path\"} binding or a function call")
    }
    switch kind {
    case .any:
        if isBindingShape(v) {
            checkBinding(issues, v, path)
        } else if let o = obj(v), o.has("call") {
            checkCall(issues, o, path, catalog)
        }
    case .DynamicString:
        dynamic({ isStr($0) }, "a string")
    case .DynamicNumber:
        dynamic({ isNum($0) }, "a number")
    case .DynamicBoolean:
        dynamic({ isBoolean($0) }, "a boolean")
    case .DynamicStringList:
        dynamic({ x in asArray(x).map { $0.allSatisfy { isStr($0) } } ?? false }, "a list of strings")
    case .DynamicValue:
        dynamic({ x in isStr(x) || isNum(x) || isBoolean(x) || asArray(x) != nil }, "a value")
    case .DynamicBooleanList:
        guard let a = asArray(v) else { return issues.add(path, .type_mismatch, "Expected a list") }
        if a.count < 2 { issues.add(path, .invalid_value, "Expected at least two values") }
        for (i, x) in a.enumerated() { checkKind(issues, x, .DynamicBoolean, "\(path)/\(i)", catalog) }
    case .ComponentId:
        if !isStr(v) { issues.add(path, .type_mismatch, "Expected a component id (string)") }
    case .ChildList:
        if let a = asArray(v) {
            for (i, x) in a.enumerated() where !isStr(x) { issues.add("\(path)/\(i)", .type_mismatch, "Expected a component id (string)") }
        } else if let o = obj(v) {
            for k in o.keys where k != "componentId" && k != "path" { issues.add("\(path)/\(k)", .unknown_field, "Unknown template field \"\(k)\"") }
            if !o.has("componentId") {
                issues.add("\(path)/componentId", .missing_field, "A child template requires \"componentId\"")
            } else if !isStr(o["componentId"]) {
                issues.add("\(path)/componentId", .type_mismatch, "\"componentId\" must be a string")
            }
            if !o.has("path") {
                issues.add("\(path)/path", .missing_field, "A child template requires \"path\"")
            } else {
                checkBinding(issues, o, path)
            }
        } else {
            issues.add(path, .invalid_value, "Expected a list of component ids or a {componentId, path} template")
        }
    case .Action:
        if let o = obj(v), o.count == 1, let e = obj(o["event"]) {
            if !isStr(e["name"]) { issues.add("\(path)/event/name", e.has("name") ? .type_mismatch : .missing_field, "An event requires a \"name\" string") }
            for k in e.keys where k != "name" && k != "context" { issues.add("\(path)/event/\(k)", .unknown_field, "Unknown event field \"\(k)\"") }
            if e.has("context") {
                if let ctx = obj(e["context"]) {
                    for (k, x) in ctx { checkKind(issues, x, .any, "\(path)/event/context/\(k)", catalog) }
                } else {
                    issues.add("\(path)/event/context", .type_mismatch, "An event \"context\" must be an object")
                }
            }
        } else if let o = obj(v), o.count == 1, let fc = obj(o["functionCall"]) {
            checkCall(issues, fc, "\(path)/functionCall", catalog)
        } else {
            issues.add(path, .invalid_value, "An action must be {\"event\": {\"name\", \"context\"}} or {\"functionCall\": {...}}")
        }
    case .Checks:
        guard let a = asArray(v) else { return issues.add(path, .type_mismatch, "\"checks\" must be a list") }
        for (i, raw) in a.enumerated() {
            let p = "\(path)/\(i)"
            guard let check = obj(raw) else {
                issues.add(p, .type_mismatch, "A check must be an object")
                continue
            }
            if !isStr(check["message"]) {
                issues.add("\(p)/message", check.has("message") ? .type_mismatch : .missing_field, "A check requires a \"message\" string")
            }
            if check.has("condition") {
                checkKind(issues, check["condition"], .DynamicBoolean, "\(p)/condition", catalog)
            } else if let call = check["call"] as? String {
                checkCall(issues, JSONObject([("call", call), ("args", check["args"] ?? JSONObject())]), p, catalog)
            } else {
                issues.add("\(p)/condition", .missing_field, "A check requires a \"condition\"")
            }
        }
    case .Accessibility:
        guard let o = obj(v) else { return issues.add(path, .type_mismatch, "\"accessibility\" must be an object") }
        for k in ["label", "description"] where o.has(k) { checkKind(issues, o[k], .DynamicString, "\(path)/\(k)", catalog) }
    case .IconName:
        if let s = v as? String {
            if !ICON_NAMES.contains(s) { issues.add(path, .invalid_value, "Unknown icon name \"\(s)\"") }
        } else if let o = obj(v), o.has("svgPath") {
            if !isStr(o["svgPath"]) || o.count != 1 { issues.add(path, .invalid_value, "An icon must be {\"svgPath\": \"…\"}") }
        } else if isBindingShape(v) {
            checkBinding(issues, v, path)
        } else {
            issues.add(path, .type_mismatch, "Expected an icon name, {\"svgPath\"} or a binding")
        }
    case .TabList:
        guard let a = asArray(v), !a.isEmpty else { return issues.add(path, .invalid_value, "\"tabs\" must be a non-empty list") }
        for (i, raw) in a.enumerated() {
            let p = "\(path)/\(i)"
            guard let t = obj(raw) else {
                issues.add(p, .type_mismatch, "A tab must be an object")
                continue
            }
            if !t.has("title") {
                issues.add("\(p)/title", .missing_field, "A tab requires \"title\"")
            } else {
                checkKind(issues, t["title"], .DynamicString, "\(p)/title", catalog)
            }
            if !isStr(t["child"]) { issues.add("\(p)/child", t.has("child") ? .type_mismatch : .missing_field, "A tab requires a \"child\" id") }
            for k in t.keys where k != "title" && k != "child" { issues.add("\(p)/\(k)", .unknown_field, "Unknown tab field \"\(k)\"") }
        }
    case .OptionList:
        guard let a = asArray(v) else { return issues.add(path, .type_mismatch, "\"options\" must be a list") }
        for (i, raw) in a.enumerated() {
            let p = "\(path)/\(i)"
            guard let o = obj(raw) else {
                issues.add(p, .type_mismatch, "An option must be an object")
                continue
            }
            if !o.has("label") {
                issues.add("\(p)/label", .missing_field, "An option requires \"label\"")
            } else {
                checkKind(issues, o["label"], .DynamicString, "\(p)/label", catalog)
            }
            if !isStr(o["value"]) { issues.add("\(p)/value", o.has("value") ? .type_mismatch : .missing_field, "An option requires a \"value\" string") }
        }
    case .string:
        if !isStr(v) { issues.add(path, .type_mismatch, "Expected a string") }
    case .number:
        if !isNum(v) { issues.add(path, .type_mismatch, "Expected a number") }
    case .boolean:
        if !isBoolean(v) { issues.add(path, .type_mismatch, "Expected a boolean") }
    }
}

private func callDepth(_ value: Any?) -> Int {
    let v = flattenOptional(value)
    if let a = asArray(v) { return a.map(callDepth).max() ?? 0 }
    guard let o = obj(v) else { return 0 }
    let inner = (obj(o["args"])?.values ?? []).map(callDepth).max() ?? 0
    return o["call"] is String ? inner + 1 : (o.values.map(callDepth).max() ?? 0)
}

private let RETURN_TYPES = ["string", "number", "boolean", "array", "object", "any", "void"]

private func checkCall(_ issues: Issues, _ v: JSONObject, _ path: String, _ catalog: A2UICatalog) {
    if callDepth(v) > MAX_CALL_DEPTH {
        issues.add(path, .limit, "functionCall depth exceeds the maximum of \(MAX_CALL_DEPTH)")
        return
    }
    guard let name = flattenOptional(v["call"]) as? String else { return issues.add("\(path)/call", .type_mismatch, "\"call\" must be a function name") }
    for k in v.keys where k != "call" && k != "args" && k != "returnType" { issues.add("\(path)/\(k)", .unknown_field, "Unknown function-call field \"\(k)\"") }
    guard let spec = catalog.functions[name] else { return issues.add("\(path)/call", .invalid_value, "Unknown function \"\(name)\"") }
    if v.has("returnType") && !((v["returnType"] as? String).map { RETURN_TYPES.contains($0) } ?? false) {
        issues.add("\(path)/returnType", .invalid_value, "Invalid returnType \(JSON.stringify(v["returnType"]))")
    }
    let argsValue: Any? = v.has("args") ? flattenOptional(v["args"]) : JSONObject()
    guard let args = obj(argsValue) else { return issues.add("\(path)/args", .type_mismatch, "\"args\" must be an object") }
    for (k, x) in args {
        guard let kind = spec.args[k] else {
            issues.add("\(path)/args/\(k)", .unknown_field, "\(name)() has no argument \"\(k)\"")
            continue
        }
        checkKind(issues, x, kind, "\(path)/args/\(k)", catalog)
    }
    for r in spec.required where !args.has(r) { issues.add("\(path)/args/\(r)", .missing_field, "\(name)() requires \"\(r)\"") }
    if let anyOf = spec.anyOf, !anyOf.contains(where: { $0.allSatisfy { args.has($0) } }) {
        issues.add("\(path)/args", .missing_field, "\(name)() requires one of \(anyOf.map { $0.joined(separator: "+") }.joined(separator: " or "))")
    }
    if name == "formatString", let s = args["value"] as? String {
        do {
            _ = try parseExpressionTemplate(s)
        } catch {
            issues.add("\(path)/args/value", .invalid_value, errorText(error))
        }
    }
}

/** A surface's components as the validator tracks them. */
public struct SurfaceShape {
    public var components = A2UIOrderedMap<JSONObject>()
}

/**
 * Stateful batch validation (the conformance `validate` action): each batch
 * is checked against the state the previous accepted batches left; a batch
 * with issues changes nothing.
 */
public final class A2UIValidator {
    public let catalog: A2UICatalog
    public let strict: Bool
    public let requireVersion: Bool
    private var surfaces = A2UIOrderedMap<SurfaceShape>()

    public init(_ catalog: A2UICatalog, strict: Bool = false, requireVersion: Bool = true) {
        self.catalog = catalog
        self.strict = strict
        self.requireVersion = requireVersion
    }

    public func validateBatch(_ messages: [Any?]) -> [A2UIError] {
        var issues: [A2UIError] = []
        for (i, m) in messages.enumerated() {
            for e in validateMessage(m, catalog, requireVersion: requireVersion) {
                issues.append(e.with(path: .some("/\(i)\(e.path == "/" ? "" : e.path ?? "")")))
            }
        }
        if !issues.isEmpty { return issues }
        var next = surfaces
        var touched: [String] = []
        for (i, m) in messages.enumerated() {
            let kind = messageKind(m)!
            let body = obj(obj(m)![kind])!
            let sid = jsString(body["surfaceId"])
            func fail(_ message: String, _ path: String? = nil) {
                issues.append(A2UIError(.ValidationError, message, surfaceId: sid, path: path ?? "/\(i)/\(kind)", issue: .topology))
            }
            switch kind {
            case "createSurface":
                if next.has(sid) { fail("Surface \"\(sid)\" already exists") } else { next[sid] = SurfaceShape() }
            case "deleteSurface":
                next.remove(sid)
            case "updateComponents":
                guard var s = next[sid] else {
                    fail("Surface \"\(sid)\" has not been created")
                    continue
                }
                var seen = Set<String>()
                for (j, raw) in (asArray(body["components"]) ?? []).enumerated() {
                    guard let c = obj(raw) else { continue }
                    let id = jsString(c["id"])
                    if strict && seen.contains(id) {
                        fail("Duplicate component ID \"\(id)\" in one updateComponents message", "/\(i)/updateComponents/components/\(j)/id")
                    }
                    seen.insert(id)
                    s.components[id] = c
                }
                next[sid] = s
                if !touched.contains(sid) { touched.append(sid) }
            case "updateDataModel":
                if !next.has(sid) { fail("Surface \"\(sid)\" has not been created") }
            default:
                break
            }
        }
        if strict { for sid in touched { issues += topology(sid, next[sid] ?? SurfaceShape()) } }
        if issues.isEmpty { surfaces = next }
        return issues
    }

    /** Graph checks for one surface's component map. */
    public func topology(_ surfaceId: String, _ surface: SurfaceShape) -> [A2UIError] {
        var out: [A2UIError] = []
        func fail(_ message: String, _ path: String = "/") {
            out.append(A2UIError(.ValidationError, message, surfaceId: surfaceId, path: path, issue: .topology))
        }
        let comps = surface.components
        if comps.isEmpty { return out }
        if !comps.has("root") {
            fail("Missing root component: surface \"\(surfaceId)\" has no component with id \"root\"")
            return out
        }
        for (id, c) in comps.entries {
            for ref in childReferences(c, catalog) {
                if ref.id == id {
                    fail("Self-reference detected: component \"\(id)\" references itself (\(ref.prop))")
                } else if !comps.has(ref.id) {
                    fail("Dangling reference: component \"\(id)\" references non-existent component '\(ref.id)' (\(ref.prop))")
                }
            }
        }
        if !out.isEmpty { return out }
        var reached = Set<String>()
        var stack: [String] = []
        var cycle: [String]?
        var tooDeep = false
        func visit(_ id: String) {
            if cycle != nil || tooDeep { return }
            if let at = stack.firstIndex(of: id) {
                cycle = Array(stack[at...]) + [id]
                return
            }
            if stack.count + 1 > MAX_NESTING {
                tooDeep = true
                return
            }
            reached.insert(id)
            stack.append(id)
            for ref in childReferences(comps[id]!, catalog) where comps.has(ref.id) { visit(ref.id) }
            stack.removeLast()
        }
        visit("root")
        if let c = cycle {
            fail("Circular reference detected. Circular component reference: \(c.joined(separator: " -> "))")
        } else if tooDeep {
            fail("Global recursion limit exceeded: the component tree is deeper than \(MAX_NESTING) levels")
        } else {
            for id in comps.keys where !reached.contains(id) { fail("Component '\(id)' is not reachable from 'root'") }
        }
        return out
    }
}
