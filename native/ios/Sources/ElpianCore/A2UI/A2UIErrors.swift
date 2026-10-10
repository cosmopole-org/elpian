import Foundation

/**
 * A2UI errors (a2ui/errors.ts). Every failure the renderer reports carries a
 * category (the conformance suites' `expect_error.category`) and, for
 * validation failures, the protocol's standard error shape:
 *
 * ```json
 * { "code": "VALIDATION_FAILED", "surfaceId": "s1", "path": "/components/0/text", "message": "…" }
 * ```
 *
 * Elpian's A2UI renderer — the Swift port of the reference implementation in
 * native/web/src/a2ui (same module split, names and tests):
 *
 *   A2UIPointer / A2UIDataModel     JSON Pointers and the surface data model
 *   A2UIExpressions                 the `formatString` template language
 *   A2UIFunctions / A2UICatalog     the basic catalog's functions and component table
 *   A2UIContext                     dynamic values, checks and actions in a data scope
 *   A2UIValidator                   message schema + component-graph validation
 *   A2UIProcessor                   surfaces from server-to-client messages
 *   A2UILowering / A2UIMarkdown     a surface → Elpian nodes
 *   A2UIAccessibility               per-component semantics
 *   A2UITransport                   the NDJSON agent stream
 *   A2UIConversation                processor + transport + transcript for one agent
 *   A2UIElpian                      the A2UISurface widget, registry and host APIs
 */
public enum A2UIErrorCategory: String {
    case DataError, ParseError, ValidationError, ExpressionError, TransportError
}

/** Machine-readable cause of a schema issue (`missing_field`, `invalid_value`, …). */
public enum A2UIIssueCode: String {
    case missing_field, invalid_value, type_mismatch, unknown_field, topology, limit
}

public struct A2UIError: MessageError, CustomStringConvertible {
    public let category: A2UIErrorCategory
    public let message: String
    public let surfaceId: String?
    public let path: String?
    public let issue: A2UIIssueCode?

    public init(_ category: A2UIErrorCategory, _ message: String, surfaceId: String? = nil, path: String? = nil, issue: A2UIIssueCode? = nil) {
        self.category = category
        self.message = message
        self.surfaceId = surfaceId
        self.path = path
        self.issue = issue
    }

    /** The error's `name` (its category), as the TypeScript `Error.name`. */
    public var name: String { category.rawValue }

    public var description: String { "\(category.rawValue): \(message)" }

    /** A copy with other details (`{...e.details, …}`). */
    public func with(surfaceId: String?? = nil, path: String?? = nil, issue: A2UIIssueCode?? = nil) -> A2UIError {
        A2UIError(category, message, surfaceId: surfaceId ?? self.surfaceId, path: path ?? self.path, issue: issue ?? self.issue)
    }

    /** The client→server `error` payload (A2UI's standard shape). */
    public func toWire() -> JSONObject {
        if category == .ValidationError {
            return JSONObject([("code", "VALIDATION_FAILED"), ("surfaceId", surfaceId ?? ""), ("path", path ?? "/"), ("message", message)])
        }
        let base = category.rawValue.hasSuffix("Error") ? String(category.rawValue.dropLast(5)) : category.rawValue
        return JSONObject([("code", base.uppercased() + "_ERROR"), ("surfaceId", surfaceId ?? ""), ("message", message)])
    }
}

public func dataError(_ message: String) -> A2UIError { A2UIError(.DataError, message) }

public func parseError(_ message: String) -> A2UIError { A2UIError(.ParseError, message) }

public func expressionError(_ message: String) -> A2UIError { A2UIError(.ExpressionError, message) }

/** Any thrown error as an [A2UIError] (non-A2UI errors become expression errors). */
public func asA2UIError(_ e: Error) -> A2UIError {
    if let a = e as? A2UIError { return a }
    return expressionError(errorText(e))
}

/**
 * An insertion-ordered string-keyed map with JavaScript `Map` semantics
 * (unlike [JSONObject], integer-like keys keep their insertion order).
 */
public struct A2UIOrderedMap<V> {
    public private(set) var keys: [String] = []
    private var storage: [String: V] = [:]

    public init() {}

    public var count: Int { keys.count }
    public var isEmpty: Bool { keys.isEmpty }

    public subscript(key: String) -> V? {
        get { storage[key] }
        set {
            if let v = newValue {
                if storage[key] == nil { keys.append(key) }
                storage[key] = v
            } else {
                remove(key)
            }
        }
    }

    public func has(_ key: String) -> Bool { storage[key] != nil }

    public mutating func remove(_ key: String) {
        guard storage.removeValue(forKey: key) != nil else { return }
        keys.removeAll { $0 == key }
    }

    public mutating func removeAll() {
        keys.removeAll()
        storage.removeAll()
    }

    public var values: [V] { keys.map { storage[$0]! } }

    public var entries: [(key: String, value: V)] { keys.map { ($0, storage[$0]!) } }
}
