package dev.elpian.core.model

import dev.elpian.core.css.CSSStyle
import dev.elpian.core.util.JsonMap
import dev.elpian.core.util.jsString

/**
 * One element of a mini app's view tree, as the guest sends it
 * (`{type, key, props, events, children}`). A top-level `style` is folded
 * into `props.style`, as in Flutter's `ElpianNode.fromJson`; [style] holds the
 * resolved cascade once the engine computed it. `events` values are guest
 * function names, or host lambdas `(ElpianEvent) -> Unit`.
 */
class ElpianNode(
    val type: String,
    val props: JsonMap,
    val children: List<ElpianNode>,
    val key: String?,
    val events: Map<String, Any?>?,
    var style: CSSStyle? = null,
) {
    fun copy(style: CSSStyle? = this.style): ElpianNode = ElpianNode(type, props, children, key, events, style)

    /** The classes of the node (`className` as a string or a list). */
    val classes: List<String>?
        get() = when (val cn = props["className"]) {
            is String -> cn.split(Regex("\\s+")).filter { it.isNotEmpty() }
            is List<*> -> cn.map { jsString(it) }
            else -> null
        }

    /** The text the node carries (`props.text` / `props.data`). */
    val text: String
        get() = (props["text"] ?: props["data"])?.let { jsString(it) } ?: ""

    fun toJson(): JsonMap {
        val out = linkedMapOf<String, Any?>("type" to type, "props" to props, "children" to children.map { it.toJson() })
        if (key != null) out["key"] = key
        if (events != null) out["events"] = events.filterValues { it !is Function<*> }
        return out
    }

    companion object {
        fun fromJson(json: Map<String, Any?>): ElpianNode {
            val props = LinkedHashMap<String, Any?>()
            (json["props"] as? Map<*, *>)?.forEach { (k, v) -> props[k.toString()] = v }
            if (json["style"] != null && props["style"] == null) props["style"] = json["style"]
            for (k in listOf("className", "class", "text", "id")) if (json[k] != null && props[k] == null) props[k] = json[k]
            if (props["class"] != null && props["className"] == null) props["className"] = props["class"]
            val children = ArrayList<ElpianNode>()
            for (child in json["children"] as? List<*> ?: emptyList<Any?>()) {
                @Suppress("UNCHECKED_CAST")
                when (child) {
                    is Map<*, *> -> children.add(fromJson(child as Map<String, Any?>))
                    is String, is Number -> children.add(ElpianNode("#text", linkedMapOf("text" to jsString(child)), emptyList(), null, null))
                }
            }
            @Suppress("UNCHECKED_CAST")
            return ElpianNode(
                type = json["type"]?.let { jsString(it) } ?: "div",
                props = props,
                children = children,
                key = json["key"]?.let { jsString(it) },
                events = json["events"] as? Map<String, Any?>,
            )
        }
    }
}
