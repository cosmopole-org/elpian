package dev.elpian.core.events

import dev.elpian.core.model.ElpianNode
import java.time.Instant

/**
 * The Elpian event model — a port of `event_system.dart` and
 * `event_dispatcher.dart`: capture → target → bubble over the registered
 * nodes, then the global handler (where sessions route into the VM).
 */
enum class EventPhase { none, capturing, atTarget, bubbling }

data class Point(val x: Double, val y: Double)

/** `ElpianEventType` camelCase names. */
val ELPIAN_EVENT_TYPES = listOf(
    "click", "doubleClick", "longPress", "tap", "tapDown", "tapUp", "tapCancel",
    "pointerDown", "pointerUp", "pointerMove", "pointerEnter", "pointerExit", "pointerHover", "pointerCancel",
    "dragStart", "drag", "dragEnd", "dragEnter", "dragLeave", "dragOver", "drop",
    "focus", "blur", "focusIn", "focusOut", "input", "change", "submit", "keyDown", "keyUp", "keyPress",
    "scroll", "reset", "select", "resize", "load", "unload", "touchStart", "touchMove", "touchEnd", "touchCancel",
    "swipeLeft", "swipeRight", "swipeUp", "swipeDown", "pinchStart", "pinchUpdate", "pinchEnd",
    "scaleStart", "scaleUpdate", "scaleEnd", "rotateStart", "rotateUpdate", "rotateEnd", "custom",
)

class ElpianEvent(
    /** The wire name `events` maps are keyed by (`click`, `doubletap`, …). */
    val type: String,
    val eventType: String,
    val target: String?,
    var currentTarget: String? = target,
    val timestamp: Long = System.currentTimeMillis(),
    var phase: EventPhase = EventPhase.none,
    var data: Map<String, Any?> = emptyMap(),
) {
    var position: Point? = null
    var localPosition: Point? = null
    var delta: Point? = null
    var buttons: Int? = null
    var pressure: Double? = null
    var distance: Double? = null
    var pointerId: Int? = null
    var key: String? = null
    var keyCode: Int? = null
    var altKey: Boolean? = null
    var ctrlKey: Boolean? = null
    var shiftKey: Boolean? = null
    var metaKey: Boolean? = null
    /** Set when the event carries a value (an input event), even a null one. */
    var hasValue = false
    var value: Any? = null
        set(v) {
            field = v
            hasValue = true
        }
    var inputType: String? = null
    var velocity: Point? = null
    var scale: Double? = null
    var rotation: Double? = null
    var focalPoint: Point? = null
    var propagationStopped = false
    var immediatePropagationStopped = false
    var defaultPrevented = false

    fun stopPropagation() {
        propagationStopped = true
    }

    fun preventDefault() {
        defaultPrevented = true
    }

    fun copyFor(currentTarget: String, phase: EventPhase): ElpianEvent {
        val e = ElpianEvent(type, eventType, target, currentTarget, timestamp, phase, data)
        e.position = position; e.localPosition = localPosition; e.delta = delta; e.buttons = buttons
        e.pressure = pressure; e.distance = distance; e.pointerId = pointerId; e.key = key; e.keyCode = keyCode
        e.altKey = altKey; e.ctrlKey = ctrlKey; e.shiftKey = shiftKey; e.metaKey = metaKey
        if (hasValue) e.value = value
        e.inputType = inputType; e.velocity = velocity; e.scale = scale; e.rotation = rotation; e.focalPoint = focalPoint
        e.propagationStopped = propagationStopped; e.immediatePropagationStopped = immediatePropagationStopped; e.defaultPrevented = defaultPrevented
        return e
    }

    val kind: String
        get() = when {
            key != null -> "keyboard"
            velocity != null || focalPoint != null || scale != null -> "gesture"
            position != null -> "pointer"
            hasValue -> "input"
            else -> "base"
        }

    /** The JSON delivered to guest handlers (`_eventToJson`). */
    fun toJson(): MutableMap<String, Any?> {
        val base = linkedMapOf<String, Any?>(
            "type" to type,
            "eventType" to eventType,
            "target" to target,
            "currentTarget" to currentTarget,
            "timestamp" to Instant.ofEpochMilli(timestamp).toString(),
            "phase" to phase.name,
            "data" to data,
        )
        when (kind) {
            "pointer" -> {
                val p = position!!
                base["position"] = mapOf("x" to p.x, "y" to p.y)
                base["localPosition"] = mapOf("x" to (localPosition?.x ?: p.x), "y" to (localPosition?.y ?: p.y))
                base["delta"] = mapOf("x" to (delta?.x ?: 0.0), "y" to (delta?.y ?: 0.0))
                base["buttons"] = buttons ?: 0
                base["pressure"] = pressure ?: 1.0
                base["distance"] = distance ?: 0.0
                base["pointerId"] = pointerId ?: 0
            }
            "keyboard" -> {
                base["key"] = key
                base["keyCode"] = keyCode ?: 0
                base["altKey"] = altKey == true
                base["ctrlKey"] = ctrlKey == true
                base["shiftKey"] = shiftKey == true
                base["metaKey"] = metaKey == true
            }
            "input" -> {
                base["value"] = value
                base["inputType"] = inputType
            }
            "gesture" -> {
                base["velocity"] = mapOf("x" to (velocity?.x ?: 0.0), "y" to (velocity?.y ?: 0.0))
                base["scale"] = scale ?: 1.0
                base["rotation"] = rotation ?: 0.0
                base["focalPoint"] = mapOf("x" to (focalPoint?.x ?: 0.0), "y" to (focalPoint?.y ?: 0.0))
            }
        }
        return base
    }
}

fun makeEvent(type: String, eventType: String, target: String?, init: ElpianEvent.() -> Unit = {}): ElpianEvent =
    ElpianEvent(type, eventType, target).apply(init)

typealias ElpianEventListener = (ElpianEvent) -> Unit

open class EventTarget {
    private class Config(val listener: ElpianEventListener, val capture: Boolean, val once: Boolean)
    private val listeners = LinkedHashMap<String, MutableList<Config>>()

    fun addEventListener(type: String, listener: ElpianEventListener, capture: Boolean = false, once: Boolean = false) {
        listeners.getOrPut(type) { ArrayList() }.add(Config(listener, capture, once))
    }

    fun removeEventListener(type: String, listener: ElpianEventListener) {
        val list = listeners[type] ?: return
        list.removeAll { it.listener === listener }
        if (list.isEmpty()) listeners.remove(type)
    }

    fun removeAllEventListeners(type: String? = null) {
        if (type != null) listeners.remove(type) else listeners.clear()
    }

    fun dispatchEvent(event: ElpianEvent): Boolean {
        val list = listeners[event.type] ?: return !event.defaultPrevented
        val remove = ArrayList<Config>()
        for (c in list.toList()) {
            if (c.capture && event.phase != EventPhase.capturing) continue
            if (!c.capture && event.phase == EventPhase.capturing) continue
            try {
                c.listener(event)
            } catch (e: Exception) {
                System.err.println("Error in event listener: $e")
            }
            if (c.once) remove.add(c)
            if (event.immediatePropagationStopped) break
        }
        if (remove.isNotEmpty()) list.removeAll(remove)
        return !event.defaultPrevented
    }

    fun hasEventListener(type: String): Boolean = (listeners[type]?.size ?: 0) > 0

    fun getListenerCount(type: String? = null): Int = if (type != null) listeners[type]?.size ?: 0 else listeners.values.sumOf { it.size }
}

class EventBus : EventTarget() {
    fun broadcast(event: ElpianEvent) {
        dispatchEvent(event)
    }
}

class EventDispatcher {
    private val nodes = HashMap<String, ElpianNode>()
    private val parents = HashMap<String, String?>()
    val bus = EventBus()
    var globalEventHandler: ElpianEventListener? = null
    private val nativeHandlers = HashMap<String, MutableMap<String, ElpianEventListener>>()

    fun registerNode(id: String, node: ElpianNode, parentId: String?) {
        nodes[id] = node
        parents[id] = parentId
    }

    fun unregisterNode(id: String) {
        nodes.remove(id)
        parents.remove(id)
    }

    fun getNode(id: String): ElpianNode? = nodes[id]

    fun addNodeHandler(id: String, type: String, listener: ElpianEventListener) {
        nativeHandlers.getOrPut(id) { HashMap() }[type] = listener
    }

    private fun chain(elementId: String): List<String> {
        val out = ArrayList<String>()
        val seen = HashSet<String>()
        var current: String? = elementId
        while (current != null && seen.add(current)) {
            out.add(current)
            current = parents[current]
        }
        return out
    }

    fun dispatchEvent(event: ElpianEvent, elementId: String) {
        val chain = chain(elementId)
        if (chain.isEmpty()) {
            globalEventHandler?.invoke(event)
            return
        }
        for (i in chain.size - 1 downTo 1) {
            val node = nodes[chain[i]] ?: continue
            val capturing = event.copyFor(chain[i], EventPhase.capturing)
            dispatchToNode(chain[i], node, capturing)
            if (capturing.propagationStopped) {
                globalEventHandler?.invoke(capturing)
                return
            }
        }
        var current = event
        nodes[elementId]?.let { targetNode ->
            val atTarget = event.copyFor(elementId, EventPhase.atTarget)
            dispatchToNode(elementId, targetNode, atTarget)
            if (atTarget.propagationStopped) {
                globalEventHandler?.invoke(atTarget)
                return
            }
            current = atTarget
        }
        for (i in 1 until chain.size) {
            val node = nodes[chain[i]] ?: continue
            val bubbling = current.copyFor(chain[i], EventPhase.bubbling)
            dispatchToNode(chain[i], node, bubbling)
            if (bubbling.propagationStopped) {
                globalEventHandler?.invoke(bubbling)
                return
            }
        }
        bus.broadcast(current)
        globalEventHandler?.invoke(current)
    }

    /** Every node on the path that declares a handler for [event]'s type, nearest first. */
    fun handlersAlongPath(event: ElpianEvent, elementId: String): List<Pair<String, Any?>> =
        chain(elementId).mapNotNull { id -> nodes[id]?.events?.get(event.type)?.let { id to it } }

    @Suppress("UNCHECKED_CAST")
    private fun dispatchToNode(id: String, node: ElpianNode, event: ElpianEvent) {
        nativeHandlers[id]?.get(event.type)?.let {
            try {
                it(event)
            } catch (e: Exception) {
                System.err.println("Error executing event handler: $e")
            }
        }
        val handler = node.events?.get(event.type)
        if (handler is Function1<*, *>) {
            try {
                (handler as (ElpianEvent) -> Unit)(event)
            } catch (e: Exception) {
                System.err.println("Error executing event handler: $e")
            }
        }
    }

    fun onGlobalEvent(listener: ElpianEventListener) {
        globalEventHandler = listener
    }

    fun onEventType(type: String, listener: ElpianEventListener) = bus.addEventListener(type, listener)

    fun dispatchClick(id: String, position: Point? = null) =
        dispatchEvent(makeEvent("click", "click", id) { if (position != null) { this.position = position; localPosition = position } }, id)

    fun dispatchChange(id: String, value: Any?) = dispatchEvent(makeEvent("change", "change", id) { this.value = value }, id)
    fun dispatchInput(id: String, value: Any?) = dispatchEvent(makeEvent("input", "input", id) { this.value = value }, id)
    fun dispatchSubmit(id: String, data: Map<String, Any?> = emptyMap()) = dispatchEvent(makeEvent("submit", "submit", id) { this.data = data }, id)
    fun dispatchFocus(id: String) = dispatchEvent(makeEvent("focus", "focus", id), id)
    fun dispatchBlur(id: String) = dispatchEvent(makeEvent("blur", "blur", id), id)

    fun clear() {
        nodes.clear()
        parents.clear()
        nativeHandlers.clear()
    }

    val stats: Pair<Int, Int> get() = nodes.size to parents.size
}
