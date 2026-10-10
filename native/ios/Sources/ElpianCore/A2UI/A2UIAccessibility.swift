import Foundation

/**
 * The accessibility semantics of an A2UI surface (a2ui/accessibility.ts): per
 * component its role, label, description and state, from the component's
 * `accessibility` attributes or inferred from its visible content (a button's
 * child text, an input's label, an image's description). Engines apply these
 * to their native semantics (the lowering sets button labels and image alt
 * text); the conformance `accessibility_check` cases read this tree directly.
 */
public struct A2UIAccessibilityNode {
    public var id: String
    public var role: String
    public var label: String?
    public var description: String?
    public var checked: Bool?
    public var live: String?
    public var hidden: Bool?
    /** For bound attributes: the data path each one reads (`label`, `description`, `hidden`, `live`). */
    public var bindings: [String: String]?

    /** The node as JSON (absent fields left out). */
    public func toJson() -> JSONObject {
        let out = JSONObject([("id", id), ("role", role)])
        if let v = label { out["label"] = v }
        if let v = description { out["description"] = v }
        if let v = checked { out["checked"] = v }
        if let v = live { out["live"] = v }
        if let v = hidden { out["hidden"] = v }
        if let b = bindings {
            let m = JSONObject()
            for k in b.keys.sorted() { m[k] = b[k] }
            out["bindings"] = m
        }
        return out
    }
}

private let ROLES: [String: String] = [
    "Text": "text",
    "Image": "img",
    "Icon": "img",
    "Video": "video",
    "AudioPlayer": "audio",
    "Row": "group",
    "Column": "group",
    "List": "list",
    "Card": "group",
    "Tabs": "tablist",
    "Modal": "dialog",
    "Divider": "separator",
    "Button": "button",
    "TextField": "textbox",
    "CheckBox": "checkbox",
    "Slider": "slider",
    "DateTimeInput": "textbox",
]

public func accessibilityRole(_ c: JSONObject) -> String {
    let type = jsString(c["component"])
    if type == "ChoicePicker" { return (c["variant"] as? String) == "multipleSelection" ? "group" : "radiogroup" }
    return ROLES[type] ?? "generic"
}

/** Semantics for one component (in the surface's root data scope). */
public func describeAccessibility(_ surface: A2UISurfaceModel, _ c: JSONObject, _ scope: String = "/") -> A2UIAccessibilityNode {
    let ctx = surface.context(scope)
    func text(_ v: Any?) -> String { ctx.safe({ plainText(parseMarkdown(try ctx.string(v))) }, "") }
    var node = A2UIAccessibilityNode(id: jsString(c["id"]), role: accessibilityRole(c))
    var bindings: [String: String] = [:]
    let a = (c["accessibility"] as? JSONObject) ?? JSONObject()
    for attr in ["label", "description", "live", "hidden"] {
        guard a.has(attr) else { continue }
        let v = a[attr]
        if let p = bindingPathOf(v) { bindings[attr] = ctx.resolvePath(p) }
        let value = ctx.safe({ try ctx.evaluate(v) }, nil)
        if attr == "hidden" {
            if let x = value { node.hidden = jsBool(x) == true }
        } else if let x = value, !((x as? String)?.isEmpty ?? false) {
            let s = jsString(x)
            switch attr {
            case "label": node.label = s
            case "description": node.description = s
            default: node.live = s
            }
        }
    }
    if node.label == nil && bindings["label"] == nil {
        var inferred = ""
        let type = jsString(c["component"])
        if type == "Button" {
            let child = (c["child"] as? String).flatMap { surface.components[$0] }
            if child.map({ jsString($0["component"]) }) == "Text" {
                inferred = text(child!["text"])
            } else if let t = c["title"] as? String {
                inferred = t
            }
        } else if ["TextField", "CheckBox", "ChoicePicker", "Slider", "DateTimeInput"].contains(type) {
            inferred = text(c["label"])
        } else if type == "Image" {
            inferred = text(c["description"])
        } else if type == "Text" {
            inferred = text(c["text"])
        }
        if !inferred.isEmpty { node.label = inferred }
    }
    if jsString(c["component"]) == "CheckBox" { node.checked = ctx.safe({ try ctx.boolean(c["value"]) }, false) }
    if !bindings.isEmpty { node.bindings = bindings }
    return node
}

/** Semantics of every component of [surface], by component id. */
public func accessibilityTree(_ surface: A2UISurfaceModel) -> [String: A2UIAccessibilityNode] {
    var out: [String: A2UIAccessibilityNode] = [:]
    for c in surface.components.values { out[jsString(c["id"])] = describeAccessibility(surface, c) }
    return out
}
