import Foundation

/**
 * `ElpianNode` — one element of a mini app's view tree, as the guest sends it:
 *
 * ```json
 * { "type": "div", "key": "card", "props": { "className": "x", "style": {…} },
 *   "events": { "click": "onCardClick" }, "children": [ … ] }
 * ```
 *
 * A top-level `style` is folded into `props.style`, as in Flutter's
 * `ElpianNode.fromJson`. [style] holds the resolved cascade once the engine
 * has computed it. `events` values are guest function names, or host
 * closures `(ElpianEvent) -> Void` ([ElpianEventListener]).
 */
public final class ElpianNode {
    public var type: String
    public var props: JSONObject
    public var children: [ElpianNode]
    public var key: String?
    public var events: JSONObject?
    public var style: CSSStyle?

    public init(type: String, props: JSONObject, children: [ElpianNode] = [], key: String? = nil, events: JSONObject? = nil, style: CSSStyle? = nil) {
        self.type = type
        self.props = props
        self.children = children
        self.key = key
        self.events = events
        self.style = style
    }

    /** `copyNode(node, patch)`: a shallow copy with some fields replaced. */
    public func copy(
        type: String? = nil,
        props: JSONObject? = nil,
        children: [ElpianNode]? = nil,
        key: String?? = nil,
        events: JSONObject?? = nil,
        style: CSSStyle?? = nil
    ) -> ElpianNode {
        ElpianNode(
            type: type ?? self.type,
            props: props ?? self.props,
            children: children ?? self.children,
            key: key ?? self.key,
            events: events ?? self.events,
            style: style ?? self.style
        )
    }

    /** `nodeFromJson`. */
    public static func fromJson(_ json: JSONObject) -> ElpianNode {
        let props: JSONObject = asMap(json["props"])?.copy() ?? JSONObject()
        if json["style"] != nil && props["style"] == nil { props["style"] = json["style"] }
        // Elpian JSON sometimes carries `className`/`text` at the top level.
        for k in ["className", "class", "text", "id"] {
            if json[k] != nil && props[k] == nil { props[k] = json[k] }
        }
        if props["class"] != nil && props["className"] == nil { props["className"] = props["class"] }
        let rawChildren = asArray(json["children"]) ?? []
        var children: [ElpianNode] = []
        for raw in rawChildren {
            let child = flattenOptional(raw)
            if let m = asMap(child) {
                children.append(fromJson(m))
            } else if child is String || jsNumber(child) != nil {
                // Bare text children: an implicit text node.
                children.append(ElpianNode(type: "#text", props: ["text": jsString(child)]))
            }
        }
        let typeValue = json["type"]
        return ElpianNode(
            type: typeValue == nil ? "div" : jsString(typeValue),
            props: props,
            children: children,
            key: json["key"] != nil ? jsString(json["key"]) : nil,
            events: asMap(json["events"]),
            style: nil
        )
    }

    /** `nodeToJson` (host closures in `events` are left out). */
    public func toJson() -> JSONObject {
        let out: JSONObject = ["type": type, "props": props, "children": children.map { $0.toJson() as Any? }]
        if let key = key { out["key"] = key }
        if let events = events {
            let e = JSONObject()
            for (k, v) in events where !(v is ElpianEventListener) { e[k] = v }
            out["events"] = e
        }
        return out
    }

    /** `classesOf`: the classes of a node (`className` as a string or a list). */
    public var classes: [String]? {
        let cn = props["className"]
        if let s = cn as? String { return jsSplitWhitespace(s).filter { !$0.isEmpty } }
        if let a = asArray(cn) { return a.map { jsString($0) } }
        return nil
    }

    /** `textOf`: the text a node carries (`props.text` / `props.data`). */
    public var text: String {
        let t = props["text"] ?? props["data"]
        return t == nil ? "" : jsString(t)
    }
}

public func nodeFromJson(_ json: JSONObject) -> ElpianNode { ElpianNode.fromJson(json) }
public func nodeToJson(_ node: ElpianNode) -> JSONObject { node.toJson() }
public func classesOf(_ node: ElpianNode) -> [String]? { node.classes }
public func textOf(_ node: ElpianNode) -> String { node.text }
