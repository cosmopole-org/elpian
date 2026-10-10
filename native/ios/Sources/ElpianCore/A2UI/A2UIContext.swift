import Foundation

/**
 * `DataContext` — evaluation of dynamic values within a data scope
 * (a2ui/context.ts).
 *
 * A dynamic value is a literal, a data binding `{ "path": "…" }` or a function
 * call `{ "call": "…", "args": {…}, "returnType": "…" }`. Paths are absolute
 * (`/user/name`) or relative to the context's scope (the template item a
 * component was instantiated for, e.g. `/users/0`). Function arguments are
 * evaluated recursively — lists element by element — before the function runs.
 */
public struct EvaluationHost {
    /** BCP 47 locale for formatting (default `en-US`). */
    public var locale: String?
    /** The zone dates are read and formatted in (default: the device's). */
    public var timeZone: TimeZone?
    /** Base for relative URLs (`openUrl`). */
    public var baseUrl: String?
    /** Perform `openUrl` (already validated to be http/https). */
    public var openUrl: ((String) -> Void)?
    /** Observe a function call before it runs (tests, tracing). */
    public var onCall: ((_ name: String, _ args: JSONObject) -> Void)?

    public init(locale: String? = nil, timeZone: TimeZone? = nil, baseUrl: String? = nil, openUrl: ((String) -> Void)? = nil,
                onCall: ((_ name: String, _ args: JSONObject) -> Void)? = nil) {
        self.locale = locale
        self.timeZone = timeZone
        self.baseUrl = baseUrl
        self.openUrl = openUrl
        self.onCall = onCall
    }
}

/** `{ "path": "…" }` and nothing else. */
public func isBinding(_ v: Any?) -> Bool {
    guard let o = flattenOptional(v) as? JSONObject else { return false }
    return o["path"] is String && o.keys.allSatisfy { $0 == "path" }
}

/** The path of a binding, or nil when [v] is not one. */
public func bindingPathOf(_ v: Any?) -> String? {
    isBinding(v) ? (flattenOptional(v) as! JSONObject)["path"] as? String : nil
}

/** `{ "call": "…", "args"?: {…}, "returnType"?: "…" }`. */
public func isFunctionCall(_ v: Any?) -> Bool {
    guard let o = flattenOptional(v) as? JSONObject else { return false }
    return o["call"] is String && o.keys.allSatisfy { $0 == "call" || $0 == "args" || $0 == "returnType" }
}

public final class DataContext {
    public let model: DataModel
    public let catalog: A2UICatalog
    /** The data scope relative paths resolve against (`/` at the root). */
    public let scope: String
    public let host: EvaluationHost

    public init(_ model: DataModel, _ catalog: A2UICatalog, _ scope: String = "/", _ host: EvaluationHost = EvaluationHost()) {
        self.model = model
        self.catalog = catalog
        self.scope = scope
        self.host = host
    }

    public var locale: String { host.locale ?? "en-US" }

    public var timeZone: TimeZone { host.timeZone ?? .current }

    /** A context scoped to [scope] (an absolute pointer). */
    public func child(_ scope: String) -> DataContext {
        DataContext(model, catalog, scope, host)
    }

    public func resolvePath(_ path: String) -> String {
        ElpianCore.resolvePath(path, scope)
    }

    public func read(_ path: String) throws -> Any? {
        try model.get(resolvePath(path))
    }

    public func write(_ path: String, _ value: Any?) throws {
        try model.set(resolvePath(path), value)
    }

    /** The absolute path a binding writes to, or nil when [value] is not a binding. */
    public func bindingPath(_ value: Any?) -> String? {
        bindingPathOf(value).map { resolvePath($0) }
    }

    /** Evaluate a dynamic property value (literal lists stay literal). */
    public func evaluate(_ value: Any?) throws -> Any? {
        if let p = bindingPathOf(value) { return try read(p) }
        if isFunctionCall(value), let o = flattenOptional(value) as? JSONObject {
            return try call(jsString(o["call"]), asMap(o["args"]) ?? JSONObject())
        }
        return flattenOptional(value)
    }

    /** Evaluate and coerce to a string (`''` for null). */
    public func string(_ value: Any?) throws -> String {
        stringifyValue(try evaluate(value))
    }

    /** Evaluate and coerce to a number (nil when not numeric). */
    public func number(_ value: Any?) throws -> Double? {
        let v = try evaluate(value)
        if let n = jsNumber(v) { return n.isFinite ? n : nil }
        if let s = v as? String, !jsTrim(s).isEmpty {
            let n = jsToNumber(s)
            return n.isFinite ? n : nil
        }
        return nil
    }

    public func boolean(_ value: Any?) throws -> Bool {
        toBool(try evaluate(value))
    }

    /** Evaluate to a list of strings (non-lists become `[]`, a lone string `[s]`). */
    public func stringList(_ value: Any?) throws -> [String] {
        let v = try evaluate(value)
        if let a = asArray(v) { return a.compactMap { flattenOptional($0) }.map { stringifyValue($0) } }
        if let s = v as? String, !s.isEmpty { return [s] }
        return []
    }

    /** Evaluate a function argument: bindings, calls, and lists of them. */
    public func argument(_ value: Any?) throws -> Any? {
        if let a = asArray(value) { return try a.map { try argument($0) } as [Any?] }
        return try evaluate(value)
    }

    /** Call catalog function [name] with unevaluated [args]. */
    public func call(_ name: String, _ args: JSONObject) throws -> Any? {
        guard let impl = catalog.implementations[name] else { throw expressionError("Unknown function \"\(name)\"") }
        let resolved = JSONObject()
        for (k, v) in args { resolved[k] = try argument(v) }
        host.onCall?(name, resolved)
        return try impl(resolved, ContextFunctions(self))
    }

    /**
     * Evaluate without throwing: expression errors (unknown function, bad
     * template) yield [fallback] and are reported to [onError].
     */
    public func safe<T>(_ fn: () throws -> T, _ fallback: T, _ onError: ((A2UIError) -> Void)? = nil) -> T {
        do {
            return try fn()
        } catch {
            onError?(asA2UIError(error))
            return fallback
        }
    }
}

private struct ContextFunctions: FunctionContext {
    let ctx: DataContext

    init(_ ctx: DataContext) { self.ctx = ctx }

    var locale: String { ctx.locale }
    var timeZone: TimeZone { ctx.timeZone }
    var baseUrl: String? { ctx.host.baseUrl }
    var openUrl: ((String) -> Void)? { ctx.host.openUrl }
    func read(_ path: String) throws -> Any? { try ctx.read(path) }
    func call(_ name: String, _ args: JSONObject) throws -> Any? { try ctx.call(name, args) }
}

/**
 * Run a component's `checks` and return the messages of those that fail. A
 * check is `{ condition, message }`; the protocol document's shorthand
 * `{ call, args, message }` is accepted too.
 */
public func evaluateChecks(_ checks: Any?, _ ctx: DataContext, _ onError: ((A2UIError) -> Void)? = nil) -> [String] {
    guard let list = asArray(checks) else { return [] }
    var failures: [String] = []
    for raw in list {
        guard let check = flattenOptional(raw) as? JSONObject else { continue }
        let condition: Any?
        if check.has("condition") {
            condition = check["condition"]
        } else if let call = check["call"] as? String {
            condition = JSONObject([("call", call), ("args", check["args"] ?? JSONObject())])
        } else {
            condition = true
        }
        let ok = ctx.safe({ try ctx.boolean(condition) }, false, onError)
        if !ok { failures.append((check["message"] as? String) ?? "Invalid value") }
    }
    return failures
}

/** An `action.event` with its context resolved. */
public struct ResolvedEvent {
    public let name: String
    public let context: JSONObject
    public let userMessage: String?
}

/**
 * Resolve an `Action`: `{ event: { name, context } }` (also the v0.9 shorthand
 * `{ name, context }`) becomes a [ResolvedEvent] with every context value
 * evaluated now; `{ functionCall }` runs locally and yields nil.
 */
public func resolveAction(_ action: Any?, _ ctx: DataContext) throws -> ResolvedEvent? {
    guard let a = flattenOptional(action) as? JSONObject else { throw expressionError("Action must be an object") }
    if let fc = a["functionCall"] as? JSONObject {
        guard let call = fc["call"] as? String else { throw expressionError("functionCall needs a \"call\" name") }
        _ = try ctx.call(call, (fc["args"] as? JSONObject) ?? JSONObject())
        return nil
    }
    let event: JSONObject? = (a["event"] as? JSONObject) ?? (a["name"] is String ? a : nil)
    guard let e = event, let name = e["name"] as? String else { throw expressionError("Action needs an \"event\" with a \"name\"") }
    let context = JSONObject()
    if let c = e["context"] as? JSONObject {
        for (k, v) in c { context[k] = try ctx.evaluate(v) }
    }
    return ResolvedEvent(name: name, context: context, userMessage: e["userMessage"] as? String)
}
