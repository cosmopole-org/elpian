import Foundation

/**
 * The context a widget builder receives while lowering one Elpian node
 * (widgets/context.ts).
 */
public struct BuildContext {
    public let engine: ElpianEngine
    /** Event-dispatch id of the nearest ancestor element (for bubbling). */
    public var parentId: String?
    /** Ancestors nearest-first, for descendant/child CSS selectors. */
    public var ancestors: [ElementFacts]
    /** Stable structural path of this node (used to derive element ids). */
    public var path: String
    /** The element id this node dispatches events as. */
    public var elementId: String
    /** Enclosing `form` element id, for submit collection. */
    public var formId: String?

    public init(engine: ElpianEngine, parentId: String?, ancestors: [ElementFacts], path: String, elementId: String, formId: String?) {
        self.engine = engine
        self.parentId = parentId
        self.ancestors = ancestors
        self.path = path
        self.elementId = elementId
        self.formId = formId
    }

    /** `{...ctx, elementId}`. */
    public func with(elementId: String) -> BuildContext {
        var c = self
        c.elementId = elementId
        return c
    }
}

/** A widget builder: Elpian node + lowered children → widget descriptor. */
public typealias WidgetBuilder = (_ node: ElpianNode, _ children: [W], _ ctx: BuildContext) -> W

public extension ElpianEvent {
    /**
     * `makeEvent(type, name, target, extra)`: copy the fields of a TypeScript
     * `Partial<ElpianEvent>` literal onto this event. A present `value` key
     * marks the event as carrying a value (even a null one), as `'value' in e`
     * does.
     */
    func applyExtra(_ extra: JSONObject) {
        for (k, v) in extra {
            switch k {
            case "value": value = v
            case "data": data = asMap(v) ?? JSONObject()
            case "position": position = pointOf(v)
            case "localPosition": localPosition = pointOf(v)
            case "delta": delta = pointOf(v)
            case "velocity": velocity = pointOf(v)
            case "focalPoint": focalPoint = pointOf(v)
            case "buttons": buttons = jsNumber(v).map { Int($0) }
            case "pressure": pressure = jsNumber(v)
            case "distance": distance = jsNumber(v)
            case "pointerId": pointerId = jsNumber(v).map { Int($0) }
            case "key": key = v as? String
            case "keyCode": keyCode = jsNumber(v).map { Int($0) }
            case "altKey": altKey = jsBool(v)
            case "ctrlKey": ctrlKey = jsBool(v)
            case "shiftKey": shiftKey = jsBool(v)
            case "metaKey": metaKey = jsBool(v)
            case "inputType": inputType = v as? String
            case "scale": scale = jsNumber(v)
            case "rotation": rotation = jsNumber(v)
            default: break
            }
        }
    }
}

private func pointOf(_ v: Any?) -> Point? {
    let value = flattenOptional(v)
    if let p = value as? Point { return p }
    if let m = asMap(value) { return Point(x: jsNumber(m["x"]) ?? 0, y: jsNumber(m["y"]) ?? 0) }
    return nil
}

/** JavaScript `Number(v)` for an event payload (a missing value is `undefined`, hence NaN). */
public func eventNumber(_ v: Any?) -> Double {
    guard let value = flattenOptional(v) else { return .nan }
    return jsToNumber(value)
}

/** JavaScript `a === b` for JSON-shaped values (objects compare by identity). */
public func jsStrictEquals(_ a: Any?, _ b: Any?) -> Bool {
    let x = flattenOptional(a)
    let y = flattenOptional(b)
    if x == nil || y == nil { return x == nil && y == nil }
    if let bx = jsBool(x) { return jsBool(y) == bx }
    if jsBool(y) != nil { return false }
    if let nx = jsNumber(x) {
        guard let ny = jsNumber(y) else { return false }
        return nx == ny
    }
    if let sx = x as? String { return (y as? String) == sx }
    if let ox = x, let oy = y, type(of: ox) is AnyClass, type(of: oy) is AnyClass { return (ox as AnyObject) === (oy as AnyObject) }
    return false
}
