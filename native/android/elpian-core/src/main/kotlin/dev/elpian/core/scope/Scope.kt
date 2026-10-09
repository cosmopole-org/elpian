package dev.elpian.core.scope

import dev.elpian.core.util.JsonMap
import dev.elpian.core.util.asMap
import dev.elpian.core.util.isMap
import dev.elpian.core.util.jsString

/**
 * Scoped re-rendering — ports of flutter/lib/src/scope/{scope_contract,
 * scope_patch,scoped_components}.dart (scope/scope.ts). `render(view, scopeKey)`
 * replaces only the subtree keyed [scopeKey] in the current tree; `Scope`
 * nodes above it get a fresh render token so they rebuild while untouched
 * siblings keep their state.
 */
object ScopeContract {
    const val type = "Scope"
    const val renderTokenProp = "__scopeRenderToken"
    const val wrapperKeySuffix = "__scope"

    fun isScopeNode(node: Any?): Boolean = node is Map<*, *> && jsString(node["type"]) == "Scope"
}

object ScopePatch {
    private var tokenCounter = 0.0

    fun normalizeKey(scopeKey: String?): String? {
        if (scopeKey == null) return null
        val k = scopeKey.trim()
        return if (k == "" || k == "null") null else k
    }

    fun ensureKey(json: JsonMap, key: String): JsonMap {
        if (json["key"] != null && jsString(json["key"]) != "") return json
        return LinkedHashMap(json).also { it["key"] = key }
    }

    fun markRerender(json: JsonMap): JsonMap {
        markTokensInPlace(json)
        return json
    }

    fun replaceByKey(tree: JsonMap, targetKey: String, replacement: JsonMap): Boolean = replace(tree, targetKey, replacement, ArrayList())

    /** Patch [tree]; falls back to the whole [view] when the key is absent. */
    fun apply(tree: JsonMap?, view: JsonMap, scopeKey: String?): JsonMap {
        val key = normalizeKey(scopeKey)
        if (key == null || tree == null) return markRerender(view)
        val replacement = markRerender(ensureKey(view, key))
        return if (replaceByKey(tree, key, replacement)) tree else view
    }

    /** Like [apply], but returns null (drop) when the key is absent. */
    fun applyBounded(tree: JsonMap?, view: JsonMap, scopeKey: String?): JsonMap? {
        val key = normalizeKey(scopeKey)
        if (key == null || tree == null) return markRerender(view)
        val replacement = markRerender(ensureKey(view, key))
        return if (replaceByKey(tree, key, replacement)) tree else null
    }

    private fun replace(node: JsonMap, targetKey: String, replacement: JsonMap, scopeAncestors: MutableList<JsonMap>): Boolean {
        if (node["key"] != null && jsString(node["key"]) == targetKey) {
            node.clear()
            node.putAll(replacement)
            markNodes(scopeAncestors)
            return true
        }
        val isScope = ScopeContract.isScopeNode(node)
        if (isScope) scopeAncestors.add(node)
        val children = node["children"]
        if (children is List<*>) {
            for (child in children) {
                if (!isMap(child)) continue
                if (replace(mutableChild(children, child), targetKey, replacement, scopeAncestors)) {
                    if (isScope) scopeAncestors.removeAt(scopeAncestors.size - 1)
                    return true
                }
            }
        }
        if (isScope) scopeAncestors.removeAt(scopeAncestors.size - 1)
        return false
    }

    private fun markNodes(scopeNodes: List<JsonMap>) {
        for (n in scopeNodes) n["props"] = withToken(n["props"])
    }

    private fun markTokensInPlace(node: Any?) {
        if (node !is MutableMap<*, *>) return
        @Suppress("UNCHECKED_CAST")
        val map = node as JsonMap
        if (ScopeContract.isScopeNode(map)) map["props"] = withToken(map["props"])
        val children = map["children"]
        if (children is List<*>) for (c in children) markTokensInPlace(c)
    }

    /** `{...(isMap(props) ? props : {}), [renderTokenProp]: ++tokenCounter}`. */
    private fun withToken(props: Any?): JsonMap {
        val out = LinkedHashMap<String, Any?>()
        if (props is Map<*, *>) for ((k, v) in props) out[k.toString()] = v
        out[ScopeContract.renderTokenProp] = ++tokenCounter
        return out
    }

    /**
     * Children are patched in place, as in TypeScript; a read-only map in a
     * mutable list is swapped for a mutable copy first.
     */
    @Suppress("UNCHECKED_CAST")
    private fun mutableChild(children: List<*>, child: Any?): JsonMap {
        if (child is MutableMap<*, *>) return child as JsonMap
        val copy = child.asMap()!!
        if (children is MutableList<*>) {
            val list = children as MutableList<Any?>
            val i = list.indexOfFirst { it === child }
            if (i >= 0) list[i] = copy
        }
        return copy
    }
}

/** Wrap each child of [root] in its own `Scope` so it can re-render alone. */
fun isolateComponentChildren(root: JsonMap, namespace: String): JsonMap {
    val children = root["children"] as? List<*> ?: return root
    root["children"] = children.mapIndexed { i, c -> isolateChild(c, namespace, i) }.toMutableList()
    return root
}

fun scopedComponent(key: String, component: Map<String, Any?>): JsonMap {
    val target: JsonMap = LinkedHashMap(component)
    target["key"] = if (target["key"] != null && jsString(target["key"]) != "") target["key"] else key
    return linkedMapOf(
        "type" to ScopeContract.type,
        "key" to "$key${ScopeContract.wrapperKeySuffix}",
        "props" to LinkedHashMap<String, Any?>(),
        "children" to mutableListOf<Any?>(target),
    )
}

private fun isolateChild(child: Any?, namespace: String, index: Int): Any? {
    if (!isMap(child)) return child
    val component: JsonMap = LinkedHashMap(child.asMap()!!)
    if (component["type"] == ScopeContract.type) return component
    val explicit = if (component["key"] != null) jsString(component["key"]) else ""
    return scopedComponent(if (explicit != "") explicit else "$namespace-component-$index", component)
}
