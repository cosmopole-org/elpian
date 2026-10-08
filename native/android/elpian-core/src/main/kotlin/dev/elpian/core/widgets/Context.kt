package dev.elpian.core.widgets

import dev.elpian.core.css.ElementFacts
import dev.elpian.core.engine.ElpianEngine
import dev.elpian.core.events.ElpianEvent
import dev.elpian.core.events.Point
import dev.elpian.core.model.ElpianNode
import dev.elpian.core.render.W

/**
 * The context a widget builder receives while lowering one Elpian node
 * (widgets/context.ts).
 */
data class BuildContext(
    val engine: ElpianEngine,
    /** Event-dispatch id of the nearest ancestor element (for bubbling). */
    val parentId: String?,
    /** Ancestors nearest-first, for descendant/child CSS selectors. */
    val ancestors: List<ElementFacts>,
    /** Stable structural path of this node (used to derive element ids). */
    val path: String,
    /** The element id this node dispatches events as. */
    val elementId: String,
    /** Enclosing `form` element id, for submit collection. */
    val formId: String?,
)

/** A widget builder: Elpian node + lowered children → widget descriptor. */
typealias WidgetBuilder = (node: ElpianNode, children: List<W>, ctx: BuildContext) -> W

/**
 * `makeEvent(type, name, target, extra)`: copy the fields of a TypeScript
 * `Partial<ElpianEvent>` literal onto [this]. A present `value` key marks the
 * event as carrying a value (even a null one), as `'value' in e` does.
 */
@Suppress("UNCHECKED_CAST")
fun ElpianEvent.applyExtra(extra: Map<String, Any?>) {
    for ((k, v) in extra) {
        when (k) {
            "value" -> value = v
            "data" -> data = (v as? Map<String, Any?>) ?: emptyMap()
            "position" -> position = pointOf(v)
            "localPosition" -> localPosition = pointOf(v)
            "delta" -> delta = pointOf(v)
            "velocity" -> velocity = pointOf(v)
            "focalPoint" -> focalPoint = pointOf(v)
            "buttons" -> buttons = (v as? Number)?.toInt()
            "pressure" -> pressure = (v as? Number)?.toDouble()
            "distance" -> distance = (v as? Number)?.toDouble()
            "pointerId" -> pointerId = (v as? Number)?.toInt()
            "key" -> key = v as? String
            "keyCode" -> keyCode = (v as? Number)?.toInt()
            "altKey" -> altKey = v as? Boolean
            "ctrlKey" -> ctrlKey = v as? Boolean
            "shiftKey" -> shiftKey = v as? Boolean
            "metaKey" -> metaKey = v as? Boolean
            "inputType" -> inputType = v as? String
            "scale" -> scale = (v as? Number)?.toDouble()
            "rotation" -> rotation = (v as? Number)?.toDouble()
        }
    }
}

private fun pointOf(v: Any?): Point? = when (v) {
    is Point -> v
    is Map<*, *> -> Point((v["x"] as? Number)?.toDouble() ?: 0.0, (v["y"] as? Number)?.toDouble() ?: 0.0)
    else -> null
}

/** JavaScript `Number(v)` for an event payload (a missing value is `undefined`, hence NaN). */
fun jsNumber(v: Any?): Double = when (v) {
    null -> Double.NaN
    is Number -> v.toDouble()
    is Boolean -> if (v) 1.0 else 0.0
    is String -> v.trim().let { if (it.isEmpty()) 0.0 else it.toDoubleOrNull() ?: Double.NaN }
    else -> Double.NaN
}
