import Foundation

/**
 * Scoped re-rendering — ports of flutter/lib/src/scope/{scope_contract,
 * scope_patch,scoped_components}.dart (scope/scope.ts). `render(view, scopeKey)`
 * replaces only the subtree keyed [scopeKey] in the current tree; `Scope`
 * nodes above it get a fresh render token so they rebuild while untouched
 * siblings keep their state.
 *
 * Trees are [JSONObject]s (reference types), so they are patched in place as
 * in TypeScript; a child held as a Swift dictionary is swapped for a
 * [JSONObject] copy in its parent's `children` first.
 */
public enum ScopeContract {
    public static let type = "Scope"
    public static let renderTokenProp = "__scopeRenderToken"
    public static let wrapperKeySuffix = "__scope"

    public static func isScopeNode(_ node: Any?) -> Bool {
        guard let m = asMap(node) else { return false }
        return jsString(m["type"]) == "Scope"
    }
}

private var tokenCounter = 0.0

public enum ScopePatch {
    public static func normalizeKey(_ scopeKey: String?) -> String? {
        guard let scopeKey = scopeKey else { return nil }
        let k = jsTrim(scopeKey)
        return k == "" || k == "null" ? nil : k
    }

    public static func ensureKey(_ json: JSONObject, _ key: String) -> JSONObject {
        if json["key"] != nil && jsString(json["key"]) != "" { return json }
        let out = json.copy()
        out["key"] = key
        return out
    }

    public static func markRerender(_ json: JSONObject) -> JSONObject {
        markTokensInPlace(json)
        return json
    }

    public static func replaceByKey(_ tree: JSONObject, _ targetKey: String, _ replacement: JSONObject) -> Bool {
        var ancestors: [JSONObject] = []
        return replace(tree, targetKey, replacement, &ancestors)
    }

    /** Patch [tree]; falls back to the whole [view] when the key is absent. */
    public static func apply(_ tree: JSONObject?, _ view: JSONObject, _ scopeKey: String?) -> JSONObject {
        guard let key = normalizeKey(scopeKey), let tree = tree else { return markRerender(view) }
        let replacement = markRerender(ensureKey(view, key))
        return replaceByKey(tree, key, replacement) ? tree : view
    }

    /** Like [apply], but returns nil (drop) when the key is absent. */
    public static func applyBounded(_ tree: JSONObject?, _ view: JSONObject, _ scopeKey: String?) -> JSONObject? {
        guard let key = normalizeKey(scopeKey), let tree = tree else { return markRerender(view) }
        let replacement = markRerender(ensureKey(view, key))
        return replaceByKey(tree, key, replacement) ? tree : nil
    }

    private static func replace(_ node: JSONObject, _ targetKey: String, _ replacement: JSONObject, _ scopeAncestors: inout [JSONObject]) -> Bool {
        if node["key"] != nil && jsString(node["key"]) == targetKey {
            node.removeAll()
            node.assign(replacement)
            markNodes(scopeAncestors)
            return true
        }
        let isScope = ScopeContract.isScopeNode(node)
        if isScope { scopeAncestors.append(node) }
        if let children = asArray(node["children"]) {
            for i in children.indices {
                guard let child = mutableChild(node, i) else { continue }
                if replace(child, targetKey, replacement, &scopeAncestors) {
                    if isScope { scopeAncestors.removeLast() }
                    return true
                }
            }
        }
        if isScope { scopeAncestors.removeLast() }
        return false
    }

    private static func markNodes(_ scopeNodes: [JSONObject]) {
        for n in scopeNodes { n["props"] = withToken(n["props"]) }
    }

    private static func markTokensInPlace(_ node: JSONObject) {
        if ScopeContract.isScopeNode(node) { node["props"] = withToken(node["props"]) }
        if let children = asArray(node["children"]) {
            for i in children.indices {
                if let child = mutableChild(node, i) { markTokensInPlace(child) }
            }
        }
    }

    /** `{...(isMap(props) ? props : {}), [renderTokenProp]: ++tokenCounter}`. */
    private static func withToken(_ props: Any?) -> JSONObject {
        let out = asMap(props)?.copy() ?? JSONObject()
        tokenCounter += 1
        out[ScopeContract.renderTokenProp] = tokenCounter
        return out
    }

    /** `node.children[i]` as a patchable [JSONObject] (nil when it is not a map). */
    private static func mutableChild(_ node: JSONObject, _ i: Int) -> JSONObject? {
        guard var children = asArray(node["children"]), i < children.count else { return nil }
        let raw = flattenOptional(children[i])
        if let o = raw as? JSONObject { return o }
        guard let copy = asMap(raw) else { return nil }
        children[i] = copy
        node["children"] = children
        return copy
    }
}

/** Wrap each child of [root] in its own `Scope` so it can re-render alone. */
@discardableResult
public func isolateComponentChildren(_ root: JSONObject, _ namespace: String) -> JSONObject {
    guard let children = asArray(root["children"]) else { return root }
    root["children"] = children.enumerated().map { i, c in isolateChild(c, namespace, i) }
    return root
}

public func scopedComponent(_ key: String, _ component: JSONObject) -> JSONObject {
    let target = component.copy()
    target["key"] = target["key"] != nil && jsString(target["key"]) != "" ? target["key"] : key
    return JSONObject([
        ("type", ScopeContract.type),
        ("key", "\(key)\(ScopeContract.wrapperKeySuffix)"),
        ("props", JSONObject()),
        ("children", [target] as [Any?]),
    ])
}

private func isolateChild(_ child: Any?, _ namespace: String, _ index: Int) -> Any? {
    guard let map = asMap(child) else { return child }
    let component = map.copy()
    if (component["type"] as? String) == ScopeContract.type { return component }
    let explicit = component["key"] != nil ? jsString(component["key"]) : ""
    return scopedComponent(explicit != "" ? explicit : "\(namespace)-component-\(index)", component)
}
