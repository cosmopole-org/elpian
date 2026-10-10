import Foundation

/**
 * The A2UI message processor — pure state, no UI (a2ui/processor.ts).
 *
 * It applies server-to-client messages to surfaces:
 *
 * - `createSurface` registers a surface with its catalog (unknown catalog ids
 *   are an error), theme and `sendDataModel` flag; creating an existing
 *   surface is an error;
 * - `updateComponents` upserts the flat adjacency list. Components arriving
 *   before `root` are buffered: a surface is renderable once `root` exists;
 * - `updateDataModel` writes (or, with no / null value, deletes) a JSON
 *   Pointer path of the surface's data model; path `/` replaces it;
 * - `deleteSurface` removes the surface.
 *
 * Inputs write back through [setData] (two-way binding), and interactions go
 * through [dispatchAction], which resolves an `action.event` into the
 * client-to-server `action` (name, surfaceId, sourceComponentId, ISO
 * timestamp, resolved context) and emits it, or runs an `action.functionCall`
 * locally. Listeners observe every change, action and error.
 *
 * A component is a [JSONObject] with at least `id` and `component`.
 */

/** The protocol version this renderer speaks. */
public let A2UI_VERSION = "v0.9.1"

public enum ValidationMode: String {
    case strict, lenient, off
}

public struct A2UIProcessorOptions {
    /** Catalogs this client supports (default: the basic catalog). */
    public var catalogs: [A2UICatalog]?
    /**
     * `strict` rejects a message with any schema issue; `lenient` (default)
     * reports issues but still applies what it can (unknown components render
     * as placeholders); `off` skips schema validation.
     */
    public var validation: ValidationMode?
    /** How dynamic values are evaluated (locale, time zone, openUrl…). */
    public var host: EvaluationHost

    public init(catalogs: [A2UICatalog]? = nil, validation: ValidationMode? = nil, host: EvaluationHost = EvaluationHost()) {
        self.catalogs = catalogs
        self.validation = validation
        self.host = host
    }

    public init(locale: String, timeZone: TimeZone? = nil) {
        self.init(host: EvaluationHost(locale: locale, timeZone: timeZone))
    }
}

/** The client-to-server `action` payload. */
public struct A2UIClientAction {
    public var name: String
    public var surfaceId: String
    public var sourceComponentId: String
    public var timestamp: String
    public var context: JSONObject
    /** Carried through when the action defines one (conformance `userMessage`). */
    public var userMessage: String?

    public init(name: String, surfaceId: String, sourceComponentId: String, timestamp: String, context: JSONObject, userMessage: String? = nil) {
        self.name = name
        self.surfaceId = surfaceId
        self.sourceComponentId = sourceComponentId
        self.timestamp = timestamp
        self.context = context
        self.userMessage = userMessage
    }

    public func toJson() -> JSONObject {
        let out = JSONObject([
            ("name", name), ("surfaceId", surfaceId), ("sourceComponentId", sourceComponentId), ("timestamp", timestamp), ("context", context),
        ])
        if let u = userMessage { out["userMessage"] = u }
        return out
    }
}

public enum A2UIProcessorEvent {
    case surfaceCreated(surfaceId: String)
    /** `reason`: `components`, `data` or `local`. */
    case surfaceUpdated(surfaceId: String, reason: String)
    case surfaceDeleted(surfaceId: String)
    case action(A2UIClientAction)
    case error(A2UIError)
}

public typealias A2UIProcessorListener = (A2UIProcessorEvent) -> Void

public final class A2UISurfaceModel {
    public let id: String
    public let catalog: A2UICatalog
    /** The catalog id exactly as `createSurface` named it. */
    public let catalogId: String
    public let theme: JSONObject
    public let sendDataModel: Bool
    private let host: EvaluationHost
    public var components = A2UIOrderedMap<JSONObject>()
    public let dataModel = DataModel()
    /** Bumped on every change (components, data, local writes). */
    public var version = 0

    public init(_ id: String, _ catalog: A2UICatalog, _ catalogId: String, _ theme: JSONObject, _ sendDataModel: Bool, _ host: EvaluationHost) {
        self.id = id
        self.catalog = catalog
        self.catalogId = catalogId
        self.theme = theme
        self.sendDataModel = sendDataModel
        self.host = host
    }

    /** The `root` component, once it has arrived. */
    public var root: JSONObject? { components["root"] }

    /** Whether the surface can render (components are buffered until `root` exists). */
    public var isReady: Bool { components.has("root") }

    /** An evaluation context scoped to [scope]. */
    public func context(_ scope: String = "/") -> DataContext {
        DataContext(dataModel, catalog, scope, host)
    }
}

public final class A2UIProcessor {
    private var surfaceMap = A2UIOrderedMap<A2UISurfaceModel>()
    private var listeners: [(id: Int, fn: A2UIProcessorListener)] = []
    private var nextListener = 0
    public let options: A2UIProcessorOptions
    public let catalogs: [A2UICatalog]
    public let validation: ValidationMode

    public init(_ options: A2UIProcessorOptions = A2UIProcessorOptions()) {
        self.options = options
        catalogs = options.catalogs ?? [BASIC_CATALOG]
        validation = options.validation ?? .lenient
    }

    /** Catalog ids this client supports (for `a2uiClientCapabilities`). */
    public var supportedCatalogIds: [String] { catalogs.map { $0.id } }

    public func catalogFor(_ catalogId: String) -> A2UICatalog? {
        catalogs.first { $0.id == catalogId || $0.aliases.contains(catalogId) }
    }

    @discardableResult
    public func on(_ listener: @escaping A2UIProcessorListener) -> () -> Void {
        let id = nextListener
        nextListener += 1
        listeners.append((id, listener))
        return { [weak self] in self?.listeners.removeAll { $0.id == id } }
    }

    private func emit(_ event: A2UIProcessorEvent) {
        for l in listeners { l.fn(event) }
    }

    @discardableResult
    private func report(_ error: A2UIError) -> A2UIError {
        emit(.error(error))
        return error
    }

    /** Surfaces in creation order. */
    public var surfaces: [A2UISurfaceModel] { surfaceMap.values }

    public func surface(_ surfaceId: String) -> A2UISurfaceModel? { surfaceMap[surfaceId] }

    /** Apply several messages; returns every error. */
    @discardableResult
    public func processAll(_ messages: [Any?]) -> [A2UIError] {
        var out: [A2UIError] = []
        for m in messages { out += process(m) }
        return out
    }

    /** Apply one server-to-client message; returns its errors (also emitted). */
    @discardableResult
    public func process(_ message: Any?) -> [A2UIError] {
        guard let kind = messageKind(message), let msg = flattenOptional(message) as? JSONObject else {
            return [report(A2UIError(.ValidationError, "Not an A2UI message: expected one of createSurface, updateComponents, updateDataModel, deleteSurface", path: "/"))]
        }
        let body = flattenOptional(msg[kind]) as? JSONObject
        let surfaceId = body?["surfaceId"] as? String
        var errors: [A2UIError] = []
        if validation != .off {
            let catalog = surfaceId.flatMap { surfaceMap[$0]?.catalog }
            let issues = validateMessage(message, catalog ?? catalogs[0], requireVersion: validation == .strict)
            for e in issues { errors.append(report(e)) }
            if !issues.isEmpty && validation == .strict { return errors }
        }
        guard let sid = surfaceId, let b = body else {
            if errors.isEmpty { errors.append(report(A2UIError(.ValidationError, "\(kind) requires a \"surfaceId\"", path: "/\(kind)/surfaceId"))) }
            return errors
        }
        func fail(_ message: String, _ path: String? = nil) -> [A2UIError] {
            errors.append(report(A2UIError(.ValidationError, message, surfaceId: sid, path: path ?? "/\(kind)")))
            return errors
        }
        switch kind {
        case "createSurface":
            if surfaceMap.has(sid) { return fail("Surface \"\(sid)\" already exists; delete it before creating it again") }
            let catalogId = (b["catalogId"] as? String) ?? ""
            guard let catalog = catalogFor(catalogId) else {
                return fail("Unsupported catalog \"\(catalogId)\" (supported: \(supportedCatalogIds.joined(separator: ", ")))", "/createSurface/catalogId")
            }
            let theme = (b["theme"] as? JSONObject)?.copy() ?? JSONObject()
            surfaceMap[sid] = A2UISurfaceModel(sid, catalog, catalogId, theme, jsBool(b["sendDataModel"]) == true, options.host)
            emit(.surfaceCreated(surfaceId: sid))
            return errors
        case "updateComponents":
            guard let surface = surfaceMap[sid] else { return fail("Surface \"\(sid)\" has not been created") }
            guard let comps = asArray(b["components"]) else { return errors }
            for raw in comps {
                guard let c = flattenOptional(raw) as? JSONObject, let id = c["id"] as? String, c["component"] is String else { continue }
                surface.components[id] = cloneJson(c) as? JSONObject
            }
            surface.version += 1
            emit(.surfaceUpdated(surfaceId: sid, reason: "components"))
            return errors
        case "updateDataModel":
            guard let surface = surfaceMap[sid] else { return fail("Surface \"\(sid)\" has not been created") }
            let path = (b["path"] as? String) ?? "/"
            do {
                // An omitted or null value removes the key (list slots become null).
                if let value = b["value"] {
                    try surface.dataModel.set(path, value)
                } else {
                    try surface.dataModel.delete(path)
                }
            } catch {
                let e = asA2UIError(error)
                errors.append(report(A2UIError(e.category == .DataError ? .DataError : .ValidationError, e.message, surfaceId: sid, path: "/updateDataModel/path")))
                return errors
            }
            surface.version += 1
            emit(.surfaceUpdated(surfaceId: sid, reason: "data"))
            return errors
        case "deleteSurface":
            guard let surface = surfaceMap[sid] else { return fail("Surface \"\(sid)\" does not exist") }
            surface.dataModel.dispose()
            surfaceMap.remove(sid)
            emit(.surfaceDeleted(surfaceId: sid))
            return errors
        default:
            return errors
        }
    }

    /** A local write through a two-way binding (an input changed). */
    public func setData(_ surfaceId: String, _ path: String, _ value: Any?) {
        guard let surface = surfaceMap[surfaceId] else { return }
        do {
            try surface.dataModel.set(path, value)
        } catch {
            let e = asA2UIError(error)
            report(A2UIError(e.category, e.message, surfaceId: surfaceId, path: path))
            return
        }
        surface.version += 1
        emit(.surfaceUpdated(surfaceId: surfaceId, reason: "local"))
    }

    /** The surface's current data model (a copy). */
    public func dataModel(_ surfaceId: String) -> Any? {
        surfaceMap[surfaceId]?.dataModel.snapshot()
    }

    /**
     * The `a2uiClientDataModel` metadata: the models of the surfaces created
     * with `sendDataModel: true`, or nil when there are none.
     */
    public func clientDataModel() -> JSONObject? {
        let surfaces = JSONObject()
        var any = false
        for s in surfaceMap.values where s.sendDataModel {
            surfaces[s.id] = s.dataModel.snapshot()
            any = true
        }
        return any ? JSONObject([("version", A2UI_VERSION), ("surfaces", surfaces)]) : nil
    }

    /**
     * The user interacted with [componentId]: resolve its [action] in [scope].
     * An `event` becomes an [A2UIClientAction], emitted and returned; a
     * `functionCall` runs locally (returns nil). Failures are reported and
     * return nil.
     */
    @discardableResult
    public func dispatchAction(_ surfaceId: String, _ componentId: String, _ action: Any?, _ scope: String = "/", now: Date = Date()) -> A2UIClientAction? {
        guard let surface = surfaceMap[surfaceId] else { return nil }
        do {
            guard let event = try resolveAction(action, surface.context(scope)) else {
                surface.version += 1
                emit(.surfaceUpdated(surfaceId: surfaceId, reason: "local"))
                return nil
            }
            let out = A2UIClientAction(name: event.name, surfaceId: surfaceId, sourceComponentId: componentId,
                                       timestamp: isoTimestamp(now.timeIntervalSince1970 * 1000), context: event.context, userMessage: event.userMessage)
            emit(.action(out))
            return out
        } catch {
            let e = asA2UIError(error)
            report(A2UIError(e.category, e.message, surfaceId: surfaceId, path: nil))
            return nil
        }
    }

    /** Remove every surface. */
    public func reset() {
        for id in surfaceMap.keys {
            surfaceMap[id]?.dataModel.dispose()
            surfaceMap.remove(id)
            emit(.surfaceDeleted(surfaceId: id))
        }
    }
}

/** The client-to-server message carrying [action]. */
public func clientActionMessage(_ action: A2UIClientAction) -> JSONObject {
    JSONObject([("version", A2UI_VERSION), ("action", action.toJson())])
}
