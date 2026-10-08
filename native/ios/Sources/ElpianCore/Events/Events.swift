import Foundation

/**
 * The Elpian event model — a port of `event_system.dart` and
 * `event_dispatcher.dart` (events/events.ts).
 *
 * Events travel DOM-style: capturing from the root to the target, at the
 * target, then bubbling back up; a node's `events` map names the guest
 * function to call for an event type (`{"click": "onClick"}`). After a
 * dispatch completes (or propagation stops) the global handler sees the
 * event — that is where sessions route it into the VM.
 */
public enum EventPhase: String {
    case none, capturing, atTarget, bubbling
}

/** `ElpianEventType` — the camelCase name of each event kind. */
public let ElpianEventType: [String] = [
    "click", "doubleClick", "longPress", "tap", "tapDown", "tapUp", "tapCancel",
    "pointerDown", "pointerUp", "pointerMove", "pointerEnter", "pointerExit", "pointerHover", "pointerCancel",
    "dragStart", "drag", "dragEnd", "dragEnter", "dragLeave", "dragOver", "drop",
    "focus", "blur", "focusIn", "focusOut",
    "input", "change", "submit",
    "keyDown", "keyUp", "keyPress",
    "scroll", "reset", "select", "resize", "load", "unload",
    "touchStart", "touchMove", "touchEnd", "touchCancel",
    "swipeLeft", "swipeRight", "swipeUp", "swipeDown",
    "pinchStart", "pinchUpdate", "pinchEnd", "scaleStart", "scaleUpdate", "scaleEnd",
    "rotateStart", "rotateUpdate", "rotateEnd", "custom",
]

public struct Point: Equatable, Hashable, JSONSerializable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func toJSON() -> Any? { JSONObject([("x", x), ("y", y)]) }
}

public enum EventKind: String {
    case base, pointer, keyboard, input, gesture
}

public final class ElpianEvent {
    /** The wire name the `events` map is keyed by (`click`, `doubletap`, `pointerdown` …). */
    public let type: String
    /** One of [ElpianEventType]. */
    public let eventType: String
    public let target: String?
    public var currentTarget: String?
    /** Milliseconds since the epoch (`Date.now()`). */
    public let timestamp: Double
    public var phase: EventPhase
    public var data: JSONObject
    // Pointer
    public var position: Point?
    public var localPosition: Point?
    public var delta: Point?
    public var buttons: Int?
    public var pressure: Double?
    public var distance: Double?
    public var pointerId: Int?
    // Keyboard
    public var key: String?
    public var keyCode: Int?
    public var altKey: Bool?
    public var ctrlKey: Bool?
    public var shiftKey: Bool?
    public var metaKey: Bool?
    // Input
    /** Set when the event carries a value (an input event), even a null one (`'value' in e`). */
    public private(set) var hasValue = false
    public var value: Any? {
        didSet { hasValue = true }
    }
    public var inputType: String?
    public var isComposing: Bool?
    // Gesture
    public var velocity: Point?
    public var scale: Double?
    public var rotation: Double?
    public var focalPoint: Point?
    // Propagation flags
    public var propagationStopped = false
    public var immediatePropagationStopped = false
    public var defaultPrevented = false

    public init(
        type: String,
        eventType: String,
        target: String?,
        currentTarget: String? = nil,
        timestamp: Double = Date().timeIntervalSince1970 * 1000,
        phase: EventPhase = .none,
        data: JSONObject = JSONObject()
    ) {
        self.type = type
        self.eventType = eventType
        self.target = target
        self.currentTarget = currentTarget ?? target
        self.timestamp = timestamp
        self.phase = phase
        self.data = data
    }

    public func stopPropagation() {
        propagationStopped = true
    }

    public func stopImmediatePropagation() {
        propagationStopped = true
        immediatePropagationStopped = true
    }

    public func preventDefault() {
        defaultPrevented = true
    }

    /** `{...event, currentTarget, phase}`. */
    public func copyFor(_ currentTarget: String, _ phase: EventPhase) -> ElpianEvent {
        let e = ElpianEvent(type: type, eventType: eventType, target: target, currentTarget: currentTarget, timestamp: timestamp, phase: phase, data: data)
        e.position = position
        e.localPosition = localPosition
        e.delta = delta
        e.buttons = buttons
        e.pressure = pressure
        e.distance = distance
        e.pointerId = pointerId
        e.key = key
        e.keyCode = keyCode
        e.altKey = altKey
        e.ctrlKey = ctrlKey
        e.shiftKey = shiftKey
        e.metaKey = metaKey
        if hasValue { e.value = value }
        e.inputType = inputType
        e.isComposing = isComposing
        e.velocity = velocity
        e.scale = scale
        e.rotation = rotation
        e.focalPoint = focalPoint
        e.propagationStopped = propagationStopped
        e.immediatePropagationStopped = immediatePropagationStopped
        e.defaultPrevented = defaultPrevented
        return e
    }

    /** `eventKind`. */
    public var kind: EventKind {
        if key != nil { return .keyboard }
        if velocity != nil || focalPoint != nil || scale != nil { return .gesture }
        if position != nil { return .pointer }
        if hasValue { return .input }
        return .base
    }

    /** The event JSON delivered to guest handlers (`_eventToJson` in elpian_vm_widget.dart). */
    public func toJson() -> JSONObject {
        let base = JSONObject([
            ("type", type),
            ("eventType", eventType),
            ("target", target),
            ("currentTarget", currentTarget),
            ("timestamp", isoTimestamp(timestamp)),
            ("phase", phase.rawValue),
            ("data", data),
        ])
        switch kind {
        case .pointer:
            let p = position!
            base["position"] = JSONObject([("x", p.x), ("y", p.y)])
            base["localPosition"] = JSONObject([("x", localPosition?.x ?? p.x), ("y", localPosition?.y ?? p.y)])
            base["delta"] = JSONObject([("x", delta?.x ?? 0), ("y", delta?.y ?? 0)])
            base["buttons"] = Double(buttons ?? 0)
            base["pressure"] = pressure ?? 1
            base["distance"] = distance ?? 0
            base["pointerId"] = Double(pointerId ?? 0)
        case .keyboard:
            base["key"] = key
            base["keyCode"] = Double(keyCode ?? 0)
            base["altKey"] = altKey == true
            base["ctrlKey"] = ctrlKey == true
            base["shiftKey"] = shiftKey == true
            base["metaKey"] = metaKey == true
        case .input:
            base["value"] = value
            base["inputType"] = inputType
        case .gesture:
            base["velocity"] = JSONObject([("x", velocity?.x ?? 0), ("y", velocity?.y ?? 0)])
            base["scale"] = scale ?? 1
            base["rotation"] = rotation ?? 0
            base["focalPoint"] = JSONObject([("x", focalPoint?.x ?? 0), ("y", focalPoint?.y ?? 0)])
        case .base:
            break
        }
        return base
    }
}

/** `new Date(ms).toISOString()` — `2026-01-02T03:04:05.678Z`. */
public func isoTimestamp(_ ms: Double) -> String {
    let totalMs = Int64(ms.rounded(.down))
    var secs = totalMs >= 0 ? totalMs / 1000 : (totalMs - 999) / 1000
    let millis = Int(totalMs - secs * 1000)
    var days = secs >= 0 ? secs / 86400 : (secs - 86399) / 86400
    secs -= days * 86400
    let hh = Int(secs / 3600), mm = Int((secs % 3600) / 60), ss = Int(secs % 60)
    // Civil-from-days (Howard Hinnant).
    days += 719_468
    let era = (days >= 0 ? days : days - 146_096) / 146_097
    let doe = days - era * 146_097
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
    var y = yoe + era * 400
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    let d = doy - (153 * mp + 2) / 5 + 1
    let m = mp < 10 ? mp + 3 : mp - 9
    if m <= 2 { y += 1 }
    func pad(_ v: Int, _ n: Int) -> String {
        let s = String(v)
        return String(repeating: "0", count: max(0, n - s.count)) + s
    }
    let year = y >= 0 && y <= 9999 ? pad(Int(y), 4) : (y < 0 ? "-" : "+") + pad(Int(abs(y)), 6)
    return "\(year)-\(pad(Int(m), 2))-\(pad(Int(d), 2))T\(pad(hh, 2)):\(pad(mm, 2)):\(pad(ss, 2)).\(pad(millis, 3))Z"
}

public func eventKind(_ e: ElpianEvent) -> EventKind { e.kind }
public func eventToJson(_ e: ElpianEvent) -> JSONObject { e.toJson() }
public func stopPropagation(_ e: ElpianEvent) { e.stopPropagation() }
public func preventDefault(_ e: ElpianEvent) { e.preventDefault() }

/** `makeEvent(type, eventType, target, extra)` — [configure] sets the extra fields. */
public func makeEvent(_ type: String, _ eventType: String, _ target: String?, _ configure: ((ElpianEvent) -> Void)? = nil) -> ElpianEvent {
    let e = ElpianEvent(type: type, eventType: eventType, target: target)
    configure?(e)
    return e
}

public typealias ElpianEventListener = (ElpianEvent) -> Void

/**
 * `ElpianEventTarget`. Swift closures have no identity, so
 * [addEventListener] returns a token that [removeEventListener] takes.
 */
open class EventTarget {
    private struct ListenerConfig {
        let id: Int
        let listener: ElpianEventListener
        let capture: Bool
        let once: Bool
    }

    private var listeners: [String: [ListenerConfig]] = [:]
    private var nextListenerId = 1

    public init() {}

    @discardableResult
    public func addEventListener(_ type: String, _ listener: @escaping ElpianEventListener, capture: Bool = false, once: Bool = false) -> Int {
        let id = nextListenerId
        nextListenerId += 1
        listeners[type, default: []].append(ListenerConfig(id: id, listener: listener, capture: capture, once: once))
        return id
    }

    public func removeEventListener(_ type: String, _ token: Int) {
        guard var list = listeners[type] else { return }
        list.removeAll { $0.id == token }
        if list.isEmpty { listeners.removeValue(forKey: type) } else { listeners[type] = list }
    }

    public func removeAllEventListeners(_ type: String? = nil) {
        if let type = type { listeners.removeValue(forKey: type) } else { listeners.removeAll() }
    }

    @discardableResult
    public func dispatchEvent(_ event: ElpianEvent) -> Bool {
        guard let list = listeners[event.type], !list.isEmpty else { return !event.defaultPrevented }
        var remove = Set<Int>()
        for config in list {
            if config.capture && event.phase != .capturing { continue }
            if !config.capture && event.phase == .capturing { continue }
            config.listener(event)
            if config.once { remove.insert(config.id) }
            if event.immediatePropagationStopped { break }
        }
        if !remove.isEmpty, let current = listeners[event.type] {
            listeners[event.type] = current.filter { !remove.contains($0.id) }
        }
        return !event.defaultPrevented
    }

    public func hasEventListener(_ type: String) -> Bool { (listeners[type]?.count ?? 0) > 0 }

    public func getListenerCount(_ type: String? = nil) -> Int {
        if let type = type { return listeners[type]?.count ?? 0 }
        return listeners.values.reduce(0) { $0 + $1.count }
    }
}

public final class EventBus: EventTarget {
    public func broadcast(_ event: ElpianEvent) {
        dispatchEvent(event)
    }

    @discardableResult
    public func subscribe(_ type: String, _ listener: @escaping ElpianEventListener) -> Int {
        addEventListener(type, listener)
    }

    public func unsubscribe(_ type: String, _ token: Int) {
        removeEventListener(type, token)
    }
}

/**
 * `EventDispatcher`: knows every event-bearing node and its parent, runs the
 * capture / target / bubble phases, and finally hands the event to the
 * global handler.
 */
public final class EventDispatcher {
    private var nodes: [String: ElpianNode] = [:]
    private var parents: [String: String?] = [:]
    public let bus = EventBus()
    public var globalEventHandler: ElpianEventListener?
    /** Host-side listeners attached to a node (`(event) -> Void` values in `events`). */
    private var nativeHandlers: [String: [String: ElpianEventListener]] = [:]

    public init() {}

    public func registerNode(_ id: String, _ node: ElpianNode, _ parentId: String?) {
        nodes[id] = node
        parents[id] = .some(parentId)
    }

    public func unregisterNode(_ id: String) {
        nodes.removeValue(forKey: id)
        parents.removeValue(forKey: id)
    }

    public func getNode(_ id: String) -> ElpianNode? { nodes[id] }

    public func addNodeHandler(_ id: String, _ type: String, _ listener: @escaping ElpianEventListener) {
        nativeHandlers[id, default: [:]][type] = listener
    }

    private func chain(_ elementId: String) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        var current: String? = elementId
        while let c = current, !seen.contains(c) {
            seen.insert(c)
            out.append(c)
            current = parents[c] ?? nil
        }
        return out
    }

    public func dispatchEvent(_ original: ElpianEvent, _ elementId: String) {
        var event = original
        let chain = self.chain(elementId)
        if chain.isEmpty {
            globalEventHandler?(event)
            return
        }
        // Capturing: root → target (exclusive).
        var i = chain.count - 1
        while i > 0 {
            if let node = nodes[chain[i]] {
                let capturing = event.copyFor(chain[i], .capturing)
                dispatchToNode(chain[i], node, capturing)
                if capturing.propagationStopped {
                    globalEventHandler?(capturing)
                    return
                }
            }
            i -= 1
        }
        // At target.
        if let targetNode = nodes[elementId] {
            let atTarget = event.copyFor(elementId, .atTarget)
            dispatchToNode(elementId, targetNode, atTarget)
            if atTarget.propagationStopped {
                globalEventHandler?(atTarget)
                return
            }
            event = atTarget
        }
        // Bubbling: target → root.
        for k in 1..<max(1, chain.count) {
            guard let node = nodes[chain[k]] else { continue }
            let bubbling = event.copyFor(chain[k], .bubbling)
            dispatchToNode(chain[k], node, bubbling)
            if bubbling.propagationStopped {
                globalEventHandler?(bubbling)
                return
            }
        }
        bus.broadcast(event)
        globalEventHandler?(event)
    }

    /** Every node on the path that declares a handler for [event]'s type, nearest first. */
    public func handlersAlongPath(_ event: ElpianEvent, _ elementId: String) -> [(nodeId: String, handler: Any)] {
        var out: [(nodeId: String, handler: Any)] = []
        for id in chain(elementId) {
            if let handler = nodes[id]?.events?[event.type] { out.append((id, handler)) }
        }
        return out
    }

    private func dispatchToNode(_ id: String, _ node: ElpianNode, _ event: ElpianEvent) {
        if let native = nativeHandlers[id]?[event.type] { native(event) }
        if let handler = node.events?[event.type] as? ElpianEventListener { handler(event) }
    }

    public func onGlobalEvent(_ listener: @escaping ElpianEventListener) {
        globalEventHandler = listener
    }

    @discardableResult
    public func onEventType(_ type: String, _ listener: @escaping ElpianEventListener) -> Int {
        bus.addEventListener(type, listener)
    }

    // Convenience dispatchers (mirroring the Dart API).
    public func dispatchClick(_ id: String, _ position: Point? = nil) {
        dispatchEvent(makeEvent("click", "click", id) { e in
            if let p = position {
                e.position = p
                e.localPosition = p
            }
        }, id)
    }

    public func dispatchChange(_ id: String, _ value: Any?) {
        dispatchEvent(makeEvent("change", "change", id) { $0.value = value }, id)
    }

    public func dispatchInput(_ id: String, _ value: Any?) {
        dispatchEvent(makeEvent("input", "input", id) { $0.value = value }, id)
    }

    public func dispatchSubmit(_ id: String, _ data: JSONObject = JSONObject()) {
        dispatchEvent(makeEvent("submit", "submit", id) { $0.data = data }, id)
    }

    public func dispatchFocus(_ id: String) {
        dispatchEvent(makeEvent("focus", "focus", id), id)
    }

    public func dispatchBlur(_ id: String) {
        dispatchEvent(makeEvent("blur", "blur", id), id)
    }

    public func clear() {
        nodes.removeAll()
        parents.removeAll()
        nativeHandlers.removeAll()
    }

    public func getStats() -> (nodes: Int, parents: Int) { (nodes.count, parents.count) }
}
