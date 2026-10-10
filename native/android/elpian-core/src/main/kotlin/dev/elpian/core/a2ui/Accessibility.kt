package dev.elpian.core.a2ui

import dev.elpian.core.util.JsonMap

/**
 * The accessibility semantics of an A2UI surface (a2ui/accessibility.ts): per
 * component its role, label, description and state, from the component's
 * `accessibility` attributes or inferred from its visible content (a button's
 * child text, an input's label, an image's description). The lowering applies
 * these to Elpian's semantics (button labels, image alt text); the
 * conformance `accessibility_check` cases read this tree directly.
 */
class A2UIAccessibilityNode(
    val id: String,
    val role: String,
    var label: String? = null,
    var description: String? = null,
    var checked: Boolean? = null,
    var live: String? = null,
    var hidden: Boolean? = null,
    /** For bound attributes: the data path each one reads (`label`, `description`, `hidden`, `live`). */
    var bindings: Map<String, String>? = null,
) {
    /** The node as JSON (absent attributes omitted). */
    fun toJson(): JsonMap {
        val out: JsonMap = linkedMapOf("id" to id, "role" to role)
        label?.let { out["label"] = it }
        description?.let { out["description"] = it }
        checked?.let { out["checked"] = it }
        live?.let { out["live"] = it }
        hidden?.let { out["hidden"] = it }
        bindings?.let { out["bindings"] = LinkedHashMap(it) }
        return out
    }
}

private val ROLES: Map<String, String> = mapOf(
    "Text" to "text",
    "Image" to "img",
    "Icon" to "img",
    "Video" to "video",
    "AudioPlayer" to "audio",
    "Row" to "group",
    "Column" to "group",
    "List" to "list",
    "Card" to "group",
    "Tabs" to "tablist",
    "Modal" to "dialog",
    "Divider" to "separator",
    "Button" to "button",
    "TextField" to "textbox",
    "CheckBox" to "checkbox",
    "Slider" to "slider",
    "DateTimeInput" to "textbox",
)

private val LABELLED_INPUTS = setOf("TextField", "CheckBox", "ChoicePicker", "Slider", "DateTimeInput")

fun accessibilityRole(c: A2UIComponent): String {
    if (c["component"] == "ChoicePicker") return if (c["variant"] == "multipleSelection") "group" else "radiogroup"
    return ROLES[c["component"]] ?: "generic"
}

/** Semantics for one component (in the surface's root data scope). */
fun describeAccessibility(surface: A2UISurfaceModel, c: A2UIComponent, scope: String = "/"): A2UIAccessibilityNode {
    val ctx = surface.context(scope)
    fun text(v: Any?): String = ctx.safe("") { plainText(parseMarkdown(ctx.string(v))) }
    val node = A2UIAccessibilityNode(c["id"].toString(), accessibilityRole(c))
    val bindings = LinkedHashMap<String, String>()
    val a = c["accessibility"] as? Map<*, *> ?: emptyMap<String, Any?>()
    for (attr in listOf("label", "description", "live", "hidden")) {
        if (!a.containsKey(attr)) continue
        val v = a[attr]
        if (isBinding(v)) bindings[attr] = ctx.resolvePath((v as Map<*, *>)["path"] as String)
        val value = ctx.safe<Any?>(null) { ctx.evaluate(v) }
        if (attr == "hidden") {
            if (value != null) node.hidden = value == true
        } else if (value != null && value != "") {
            val s = if (value is String) value else stringifyValue(value)
            when (attr) {
                "label" -> node.label = s
                "description" -> node.description = s
                "live" -> node.live = s
            }
        }
    }
    if (node.label == null && !bindings.containsKey("label")) {
        var inferred = ""
        val type = c["component"]
        if (type == "Button") {
            val child = (c["child"] as? String)?.let { surface.components[it] }
            if (child?.get("component") == "Text") inferred = text(child["text"])
            else if (c["title"] is String) inferred = c["title"] as String
        } else if (type in LABELLED_INPUTS) inferred = text(c["label"])
        else if (type == "Image") inferred = text(c["description"])
        else if (type == "Text") inferred = text(c["text"])
        if (inferred.isNotEmpty()) node.label = inferred
    }
    if (c["component"] == "CheckBox") node.checked = ctx.safe(false) { ctx.boolean(c["value"]) }
    if (bindings.isNotEmpty()) node.bindings = bindings
    return node
}

/** Semantics of every component of [surface], by component id. */
fun accessibilityTree(surface: A2UISurfaceModel): Map<String, A2UIAccessibilityNode> {
    val out = LinkedHashMap<String, A2UIAccessibilityNode>()
    for (c in surface.components.values) out[c["id"].toString()] = describeAccessibility(surface, c)
    return out
}
