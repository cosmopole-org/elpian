import Foundation

/**
 * ElpianEngine — the Swift twin of `elpian_engine.dart` + `ElpianServices`
 * (engine/engine.ts).
 *
 * `render(node)` resolves each element's cascaded style, honours
 * `display: none`, lowers the node through its registered widget builder,
 * and wraps event-bearing elements in a gesture region registered with the
 * event dispatcher — exactly the steps of the Flutter `_render`. The result is
 * a widget-descriptor tree the render owner reconciles and lays out.
 */
public final class ElpianServices {
    public let appId: String
    public let events = EventDispatcher()
    public let stylesheets = StylesheetManager()
    public let canvasContexts = CanvasContextStore()
    public let canvas = CanvasExecutor()
    public let dom = ElpianDOM()
    /** Widget builders by node type (insertion-ordered). */
    public private(set) var registry: [String: WidgetBuilder] = [:]
    public private(set) var registryOrder: [String] = []

    public init(appId: String = "default") {
        self.appId = appId
    }

    /** `registry.set(type, builder)`. */
    public func setBuilder(_ type: String, _ builder: @escaping WidgetBuilder) {
        if registry[type] == nil { registryOrder.append(type) }
        registry[type] = builder
    }

    /** Namespace a guest-chosen id so mini apps never collide (`appId::id`). */
    public func scopeId(_ id: String) -> String { "\(appId)::\(id)" }

    public func dispose() {
        events.clear()
        events.bus.removeAllEventListeners()
        stylesheets.clear()
        canvasContexts.clearAll()
        canvas.clear()
        dom.clear()
    }
}

/**
 * Callbacks from rendered content back into the hosting session. Every
 * callback is optional (nil = the host does not offer it).
 */
public final class EngineHost {
    /** A link (`a href`, `NextjsLink`) was activated. */
    public var navigate: ((_ href: String, _ replace: Bool) -> Void)?
    /** Open an external URL. */
    public var openUrl: ((_ url: String) -> Void)?
    /** A tap on a clickable Scene3D (ElpianSceneTaps). */
    public var sceneTap: ((_ props: JSONObject) -> Void)?
    /** `NextjsForm` submission; returns an error message or nil. */
    public var submitForm: ((_ action: String, _ values: JSONObject) async throws -> String?)?
    /** The Godot transport for new Scene3D surfaces. */
    public var godotBinding: (() -> GodotBinding?)?
    /** Base URL for relative resource paths (ElpianResources.baseUrl). */
    public var baseUrl: (() -> String?)?
    /** The id of the drag target (DragTarget element) under a global point. */
    public var hitTestDragTarget: ((_ x: Double, _ y: Double) -> String?)?
    /** Request a re-render (element state changed). */
    public var invalidate: (() -> Void)?
    /** Move input focus to the control rendered for the element with HTML id [id]. */
    public var focus: ((_ id: String) -> Void)?
    public var log: ((_ level: String, _ message: String) -> Void)?

    public init(
        navigate: ((_ href: String, _ replace: Bool) -> Void)? = nil,
        openUrl: ((_ url: String) -> Void)? = nil,
        sceneTap: ((_ props: JSONObject) -> Void)? = nil,
        submitForm: ((_ action: String, _ values: JSONObject) async throws -> String?)? = nil,
        godotBinding: (() -> GodotBinding?)? = nil,
        baseUrl: (() -> String?)? = nil,
        hitTestDragTarget: ((_ x: Double, _ y: Double) -> String?)? = nil,
        invalidate: (() -> Void)? = nil,
        focus: ((_ id: String) -> Void)? = nil,
        log: ((_ level: String, _ message: String) -> Void)? = nil
    ) {
        self.navigate = navigate
        self.openUrl = openUrl
        self.sceneTap = sceneTap
        self.submitForm = submitForm
        self.godotBinding = godotBinding
        self.baseUrl = baseUrl
        self.hitTestDragTarget = hitTestDragTarget
        self.invalidate = invalidate
        self.focus = focus
        self.log = log
    }
}

public final class SceneEntry {
    public let controller: GodotSceneController
    public var sceneKey: String?
    public var attached: Bool

    public init(_ controller: GodotSceneController, _ sceneKey: String?, _ attached: Bool) {
        self.controller = controller
        self.sceneKey = sceneKey
        self.attached = attached
    }
}

private let EVENT_GESTURES: [String: String] = [
    "click": "tap",
    "tap": "tap",
    "doubletap": "doubletap",
    "dblclick": "doubletap",
    "longpress": "longpress",
    "contextmenu": "longpress",
    "tapdown": "tapdown",
    "tapup": "tapup",
    "tapcancel": "tapcancel",
    "drag": "pan",
    "dragstart": "pan",
    "dragend": "pan",
    "swipeleft": "swipe",
    "swiperight": "swipe",
    "swipeup": "swipe",
    "swipedown": "swipe",
    "pointerdown": "pointer",
    "pointerup": "pointer",
    "pointermove": "pointer",
    "pointercancel": "pointer",
    "pointerenter": "hover",
    "pointerexit": "hover",
    "pointerhover": "hover",
    "mouseenter": "hover",
    "mouseleave": "hover",
    "keydown": "key",
    "keyup": "key",
    "keypress": "key",
    "focus": "focus",
    "blur": "focus",
    "scalestart": "scale",
    "scaleupdate": "scale",
    "scaleend": "scale",
    "pinchstart": "scale",
    "pinchupdate": "scale",
    "pinchend": "scale",
    "rotatestart": "scale",
    "rotateupdate": "scale",
    "rotateend": "scale",
    "scroll": "scroll",
]

private let EVENT_TYPE_NAMES: [String: String] = [
    "click": "click",
    "tap": "tap",
    "doubletap": "doubleClick",
    "longpress": "longPress",
    "tapdown": "tapDown",
    "tapup": "tapUp",
    "tapcancel": "tapCancel",
    "pointerdown": "pointerDown",
    "pointerup": "pointerUp",
    "pointermove": "pointerMove",
    "pointerenter": "pointerEnter",
    "pointerexit": "pointerExit",
    "pointerhover": "pointerHover",
    "pointercancel": "pointerCancel",
    "dragstart": "dragStart",
    "drag": "drag",
    "dragend": "dragEnd",
    "dragenter": "dragEnter",
    "dragleave": "dragLeave",
    "dragover": "dragOver",
    "drop": "drop",
    "focus": "focus",
    "blur": "blur",
    "input": "input",
    "change": "change",
    "submit": "submit",
    "keydown": "keyDown",
    "keyup": "keyUp",
    "keypress": "keyPress",
    "scroll": "scroll",
    "swipeleft": "swipeLeft",
    "swiperight": "swipeRight",
    "swipeup": "swipeUp",
    "swipedown": "swipeDown",
    "scalestart": "scaleStart",
    "scaleupdate": "scaleUpdate",
    "scaleend": "scaleEnd",
    "pinchstart": "pinchStart",
    "pinchupdate": "pinchUpdate",
    "pinchend": "pinchEnd",
    "rotatestart": "rotateStart",
    "rotateupdate": "rotateUpdate",
    "rotateend": "rotateEnd",
    "load": "load",
    "select": "select",
    "reset": "reset",
    "resize": "resize",
]

/** The Elpian event type name (`ElpianEventType`) of a DOM-style event name. */
public func eventTypeFor(_ name: String) -> String { EVENT_TYPE_NAMES[name] ?? "custom" }

private let ABSOLUTE_URL = JSRegex("^(https?:|data:|blob:|asset:|file:|content:)", ignoreCase: true)
private let ORIGIN = JSRegex("^[a-z]+://[^/]+", ignoreCase: true)
private let TRAILING_SLASHES = JSRegex("/+$")

public final class ElpianEngine {
    public let services: ElpianServices
    public var host: EngineHost

    /** Per-element state that survives re-renders (details open, select value …). */
    private var state: [String: Any] = [:]
    private var stateOrder: [String] = []
    private var seen = Set<String>()
    private var scenes: [String: SceneEntry] = [:]
    private var sceneOrder: [String] = []
    /** Nodes registered with the dispatcher this render. */
    private var registered: [String] = []
    private var registeredSet = Set<String>()
    private var previousRegistered: [String] = []

    /** Form id → field name → value reader, in registration order. */
    private var formFields: [String: [(name: String, read: () -> Any?)]] = [:]
    /** `<map name>` → its `<area>` nodes, collected before each render. */
    public var imageMaps: [String: [ElpianNode]] = [:]
    /** `<datalist id>` → its option values (feeds `<input list>` suggestions). */
    public var datalists: [String: [String]] = [:]

    private var dragTarget: String?

    public init(services: ElpianServices? = nil, host: EngineHost = EngineHost()) {
        self.services = services ?? ElpianServices()
        self.host = host
        registerDefaultWidgets(self)
    }

    // ---------------------------------------------------------------------------
    // Configuration
    // ---------------------------------------------------------------------------

    public func registerWidget(_ type: String, _ builder: @escaping WidgetBuilder) {
        services.setBuilder(type, builder)
    }

    /** Register every builder of an ordered `(type, builder)` list. */
    public func registerWidgets(_ builders: [(String, WidgetBuilder)]) {
        for (k, v) in builders { services.setBuilder(k, v) }
    }

    /** Register every builder of a dictionary (its iteration order). */
    public func registerWidgets(_ builders: [String: WidgetBuilder]) {
        for (k, v) in builders { services.setBuilder(k, v) }
    }

    /** A JSON stylesheet map or CSS text. */
    public func loadStylesheet(_ sheet: Any?) {
        services.stylesheets.load(sheet)
    }

    public func clearStylesheets() {
        services.stylesheets.clear()
    }

    public func resolveUrl(_ src: String) -> String {
        if src.isEmpty || ABSOLUTE_URL.test(src) { return src }
        guard let base = host.baseUrl?(), !base.isEmpty else { return src }
        if src.hasPrefix("//") { return (base.hasPrefix("https") ? "https:" : "http:") + src }
        if src.hasPrefix("/") {
            let origin = ORIGIN.exec(base)?[0] ?? base
            return origin + src
        }
        return TRAILING_SLASHES.replace(base, with: "") + "/" + src
    }

    // ---------------------------------------------------------------------------
    // Element state
    // ---------------------------------------------------------------------------

    /**
     * State for [elementId], created by [initial] on first use; kept while the
     * element renders. A state of another kind left at the same id (the
     * element changed type under a stable key) is replaced.
     */
    public func stateFor<T>(_ elementId: String, _ initial: () -> T) -> T {
        seen.insert(elementId)
        if let existing = state[elementId] as? T { return existing }
        let created = initial()
        if state[elementId] == nil { stateOrder.append(elementId) }
        state[elementId] = created
        return created
    }

    /** Merge [patch] into the map state of [elementId] and request a re-render. */
    public func setState(_ elementId: String, _ patch: JSONObject) {
        let next = (state[elementId] as? JSONObject)?.copy() ?? JSONObject()
        next.assign(patch)
        if state[elementId] == nil { stateOrder.append(elementId) }
        state[elementId] = next
        host.invalidate?()
    }

    /** The raw state stored for [elementId] (nil when none). */
    public func stateOf(_ elementId: String) -> Any? { state[elementId] }

    // ---------------------------------------------------------------------------
    // Rendering
    // ---------------------------------------------------------------------------

    public func renderFromJson(_ json: JSONObject) -> W { render(ElpianNode.fromJson(json)) }

    public func render(_ root: ElpianNode) -> W {
        seen = Set()
        formFields = [:]
        imageMaps = collectMaps(root)
        datalists = collectDatalists(root)
        previousRegistered = registered
        registered = []
        registeredSet = Set()
        let ctx = BuildContext(engine: self, parentId: nil, ancestors: [], path: "r", elementId: "r", formId: nil)
        let result = renderNode(root, ctx, 0)
        collectGarbage()
        return result
    }

    private func collectGarbage() {
        for id in stateOrder where !seen.contains(id) { state.removeValue(forKey: id) }
        stateOrder = stateOrder.filter { state[$0] != nil }
        for id in sceneOrder where !seen.contains(id) {
            scenes[id]?.controller.dispose()
            scenes.removeValue(forKey: id)
        }
        sceneOrder = sceneOrder.filter { scenes[$0] != nil }
        for id in previousRegistered where !registeredSet.contains(id) { services.events.unregisterNode(id) }
    }

    /** Resolve the cascaded style of [node] (stylesheet + `@media` + inline + `!important`). */
    public func resolveStyle(_ node: ElpianNode, _ ancestors: [ElementFacts]) -> CSSStyle? {
        let inline = asMap(node.props["style"])
        let sheets = services.stylesheets
        if sheets.hasRules {
            let computed = sheets.getComputedStyleMap(factsOf(node), ancestors: ancestors, inlineStyles: inline)
            return computed.isEmpty ? nil : CSSParser.parse(computed)
        }
        if let inline = inline { return CSSParser.parse(sheets.substituteVariables(inline)) }
        return nil
    }

    public func factsOf(_ node: ElpianNode) -> ElementFacts {
        ElementFacts(tagName: node.type, id: node.key ?? (node.props["id"] as? String), classes: node.classes, attributes: node.props)
    }

    public func renderNode(_ node: ElpianNode, _ parentCtx: BuildContext, _ index: Int) -> W {
        let path = "\(parentCtx.path)/\(index)"
        let htmlId = node.props["id"] as? String
        let elementId = node.key ?? ((htmlId != nil && !htmlId!.isEmpty) ? "#\(htmlId!)" : "\(path):\(node.type)")
        seen.insert(elementId)

        if node.type == "#text" {
            return w("text", ["text": jsString(node.props["text"] ?? "")])
        }

        guard let builder = services.registry[node.type] else {
            host.log?("warn", "Unknown widget type \"\(node.type)\"")
            return w(
                "decorated",
                ["decoration": BoxDecoration(color: 0x33f44336)],
                child: w("padding", ["padding": EdgeInsets(top: 8, right: 8, bottom: 8, left: 8)], child: w("text", ["text": "Unknown widget: \(node.type)"]))
            )
        }

        let style = resolveStyle(node, parentCtx.ancestors) ?? node.style
        let styled = style !== node.style ? node.copy(style: .some(style)) : node

        if style?.display == "none" { return w("constrained", ["width": 0.0, "height": 0.0]) }

        let hasEvents = !(node.events?.isEmpty ?? true)
        if hasEvents || node.key != nil {
            services.events.registerNode(elementId, styled, parentCtx.parentId)
            if !registeredSet.contains(elementId) {
                registeredSet.insert(elementId)
                registered.append(elementId)
            }
        }

        let facts = factsOf(node)
        let ctx = BuildContext(
            engine: self,
            parentId: hasEvents || node.key != nil ? elementId : parentCtx.parentId,
            ancestors: [facts] + parentCtx.ancestors,
            path: path,
            elementId: elementId,
            formId: node.type == "form" || node.type == "NextjsForm" ? elementId : parentCtx.formId
        )

        // Resolve children's styles up-front so layout builders (HtmlDiv) can read them.
        let childNodes: [ElpianNode] = styled.children.map { child in
            if child.type == "#text" { return child }
            let childStyle = resolveStyle(child, ctx.ancestors) ?? child.style
            return childStyle !== child.style ? child.copy(style: .some(childStyle)) : child
        }
        let withChildren = ElpianNode(type: styled.type, props: styled.props, children: childNodes, key: styled.key, events: styled.events, style: styled.style)
        let children = childNodes.enumerated().map { i, child in renderNode(child, ctx, i) }

        var result = builder(withChildren, children, ctx.with(elementId: elementId))

        if hasEvents {
            result = wrapEvents(withChildren, elementId, result)
        }
        if let key = node.key, result.k == nil { result = W(result.t, result.p, result.c, key) }
        return result
    }

    /** `EventEnabledWidget`: a gesture region recognising what the node listens for. */
    public func wrapEvents(_ node: ElpianNode, _ elementId: String, _ child: W) -> W {
        var gestures: [String] = []
        func add(_ g: String) { if !gestures.contains(g) { gestures.append(g) } }
        for name in node.events?.keys ?? [] {
            let g = EVENT_GESTURES[name.lowercased()]
            if let g = g { add(g) }
            if g == "key" { add("focus") }
        }
        if gestures.isEmpty { return child }
        let listensTap = gestures.contains("tap")
        return w(
            "gesture",
            [
                "gestures": gestures,
                "cursor": listensTap ? (node.style?.cursor ?? "pointer") : node.style?.cursor,
                "focusable": gestures.contains("key") || gestures.contains("focus"),
                "onEvent": { (event: ViewEvent) in self.handleGesture(elementId, node, event) },
            ],
            child: child,
            "ev:\(elementId)"
        )
    }

    /** Translate a platform gesture into Elpian events and dispatch them. */
    public func handleGesture(_ elementId: String, _ node: ElpianNode, _ event: ViewEvent) {
        let events = node.events ?? JSONObject()
        func has(_ name: String) -> Bool { events.has(name) }
        let pos: Point? = event.x.map { Point(x: $0, y: event.y ?? 0) }
        let local: Point? = event.localX.map { Point(x: $0, y: event.localY ?? 0) } ?? pos
        func dispatch(_ type: String, _ configure: ((ElpianEvent) -> Void)? = nil) {
            services.events.dispatchEvent(makeEvent(type, eventTypeFor(type), elementId, configure), elementId)
        }
        let zero = Point(x: 0, y: 0)
        switch event.type {
        case "tap":
            if has("tap") { dispatch("tap") { e in if let p = pos { e.position = p; e.localPosition = local } } }
            if has("click") { dispatch("click") { e in if let p = pos { e.position = p; e.localPosition = local } } }
        case "doubletap":
            dispatch(has("dblclick") && !has("doubletap") ? "dblclick" : "doubletap")
        case "longpress":
            dispatch(has("contextmenu") && !has("longpress") ? "contextmenu" : "longpress") { e in
                if let p = pos { e.position = p; e.localPosition = local }
            }
        case "tapdown", "tapup":
            dispatch(event.type) { e in e.position = pos ?? zero; e.localPosition = local ?? zero }
        case "tapcancel":
            dispatch("tapcancel")
        case "dragstart":
            if has("dragstart") { dispatch("dragstart") { e in e.position = pos ?? zero; e.localPosition = local ?? zero } }
        case "drag":
            if has("drag") {
                dispatch("drag") { e in
                    e.position = pos ?? zero
                    e.localPosition = local ?? zero
                    e.delta = Point(x: event.dx ?? 0, y: event.dy ?? 0)
                }
            }
        case "dragend":
            if has("dragend") { dispatch("dragend") { e in e.position = zero; e.localPosition = zero } }
        case "swipe":
            let vx = event.vx ?? 0
            let vy = event.vy ?? 0
            let dir = event.direction ?? (abs(vx) > abs(vy) ? (vx < 0 ? "left" : "right") : vy < 0 ? "up" : "down")
            let name = "swipe\(dir)"
            if has(name) {
                dispatch(name) { e in
                    e.velocity = Point(x: vx, y: vy)
                    e.scale = 1
                    e.rotation = 0
                    e.focalPoint = zero
                }
            }
        case "pointerdown", "pointerup", "pointermove", "pointercancel", "pointerenter", "pointerexit", "pointerhover":
            let alias: String
            if event.type == "pointerenter" && !has("pointerenter") && has("mouseenter") {
                alias = "mouseenter"
            } else if event.type == "pointerexit" && !has("pointerexit") && has("mouseleave") {
                alias = "mouseleave"
            } else {
                alias = event.type
            }
            if has(alias) {
                dispatch(alias) { e in
                    e.position = pos ?? zero
                    e.localPosition = local ?? zero
                    e.delta = Point(x: event.dx ?? 0, y: event.dy ?? 0)
                    e.buttons = event.buttons ?? 0
                    e.pressure = event.pressure ?? 1
                    e.pointerId = event.pointerId ?? 0
                }
            }
        case "keydown", "keyup", "keypress":
            if has(event.type) {
                dispatch(event.type) { e in
                    e.key = event.key ?? ""
                    e.keyCode = event.keyCode ?? 0
                    e.altKey = event.altKey == true
                    e.ctrlKey = event.ctrlKey == true
                    e.shiftKey = event.shiftKey == true
                    e.metaKey = event.metaKey == true
                }
            }
        case "focus", "blur":
            if has(event.type) { dispatch(event.type) }
        case "scalestart", "scaleupdate", "scaleend":
            let suffix = String(event.type.dropFirst(5))
            for prefix in ["scale", "pinch", "rotate"] where has(prefix + suffix) {
                dispatch(prefix + suffix) { e in
                    e.velocity = Point(x: event.vx ?? 0, y: event.vy ?? 0)
                    e.scale = event.scale ?? 1
                    e.rotation = event.rotation ?? 0
                    e.focalPoint = pos ?? zero
                }
            }
        case "scroll":
            if has("scroll") { dispatch("scroll") { e in e.data = JSONObject([("scrollX", event.scrollX ?? 0), ("scrollY", event.scrollY ?? 0)]) } }
        default:
            if has(event.type) {
                dispatch(event.type) { e in
                    e.value = event.value
                    e.data = asMap(event.data) ?? JSONObject()
                }
            }
        }
    }

    // ---------------------------------------------------------------------------
    // Forms and image maps
    // ---------------------------------------------------------------------------

    /** `<label for>`: focus the control of the element with HTML id [id]. */
    public func focusElement(_ id: String) {
        host.focus?(id)
    }

    /** A named form control reports its current value through [read]. */
    public func registerFormField(_ formId: String?, _ name: String?, _ read: @escaping () -> Any?) {
        guard let formId = formId, !formId.isEmpty, let name = name, !name.isEmpty else { return }
        var fields = formFields[formId] ?? []
        if let i = fields.firstIndex(where: { $0.name == name }) {
            fields[i] = (name, read)
        } else {
            fields.append((name, read))
        }
        formFields[formId] = fields
    }

    public func formValues(_ formId: String) -> JSONObject {
        let out = JSONObject()
        for field in formFields[formId] ?? [] { out[field.name] = field.read() }
        return out
    }

    /** Submit [formId]: the form element receives `submit` with its field values. */
    public func submitForm(_ formId: String) {
        let values = formValues(formId)
        services.events.dispatchEvent(
            makeEvent("submit", "submit", formId) { e in
                e.data = JSONObject([("values", values)])
                e.value = values
            },
            formId
        )
    }

    // ---------------------------------------------------------------------------
    // Drag and drop (Draggable / DragTarget)
    // ---------------------------------------------------------------------------

    private func dispatchTo(_ elementId: String, _ type: String, _ data: JSONObject) {
        services.events.dispatchEvent(makeEvent(type, eventTypeFor(type), elementId) { $0.data = data }, elementId)
    }

    /** A Draggable moved: update DragTarget enter / leave / over. */
    public func dragOver(_ sourceId: String, _ e: ViewEvent, _ data: Any?) {
        let target: String? = e.x != nil ? host.hitTestDragTarget?(e.x!, e.y ?? 0) ?? nil : nil
        if target != dragTarget {
            if let previous = dragTarget { dispatchTo(previous, "dragleave", JSONObject([("data", data), ("source", sourceId)])) }
            if let t = target { dispatchTo(t, "dragenter", JSONObject([("data", data), ("source", sourceId)])) }
            dragTarget = target
        }
        if let t = target { dispatchTo(t, "dragover", JSONObject([("data", data), ("source", sourceId), ("x", e.x), ("y", e.y)])) }
        dispatchTo(sourceId, "drag", JSONObject([("x", e.x), ("y", e.y)]))
    }

    /** A Draggable was released: the target under the pointer accepts it. */
    public func dropAt(_ sourceId: String, _ e: ViewEvent, _ data: Any?) {
        let target: String? = e.x != nil ? host.hitTestDragTarget?(e.x!, e.y ?? 0) ?? nil : nil
        if let t = target {
            dispatchTo(t, "drop", JSONObject([("data", data), ("source", sourceId)]))
            dispatchTo(t, "accept", JSONObject([("data", data), ("source", sourceId)]))
        }
        dispatchTo(sourceId, "dragend", JSONObject([("accepted", target != nil), ("target", target)]))
        if let previous = dragTarget, previous != target {
            dispatchTo(previous, "dragleave", JSONObject([("data", data), ("source", sourceId)]))
        }
        dragTarget = nil
    }

    // ---------------------------------------------------------------------------
    // Scene3D
    // ---------------------------------------------------------------------------

    /** The scene controller of a Scene3D element, building / replacing its DSL scene. */
    public func sceneFor(_ elementId: String, _ sceneJson: JSONObject?) -> GodotSceneController {
        seen.insert(elementId)
        let entry: SceneEntry
        if let existing = scenes[elementId] {
            entry = existing
        } else {
            let binding = host.godotBinding?() ?? MockGodotBinding()
            entry = SceneEntry(GodotSceneController(binding), nil, false)
            scenes[elementId] = entry
            sceneOrder.append(elementId)
        }
        let key = sceneJson.map { stableKey($0) }
        if let json = sceneJson, key != entry.sceneKey {
            if entry.sceneKey == nil {
                entry.controller.adopt(SceneDsl(entry.controller.godot).build(json))
            } else {
                _ = entry.controller.replaceScene(json)
            }
            entry.sceneKey = key
        }
        if !entry.attached {
            entry.attached = true
            let godot = entry.controller.godot
            launchDetached { await godot.attachSurface() }
        }
        return entry.controller
    }

    /** The Scene3D controllers currently alive, by element id (in creation order). */
    public var sceneControllers: [(id: String, entry: SceneEntry)] {
        sceneOrder.compactMap { id in scenes[id].map { (id, $0) } }
    }

    // ---------------------------------------------------------------------------
    // Documents
    // ---------------------------------------------------------------------------

    /**
     * `wrapAsDocument`: a screen root scrolls vertically like `<body>` unless it
     * is a viewport-locked stage (`position: fixed`, `height: 100vh|100%`, or
     * it embeds a Scene3D).
     */
    public func wrapAsDocument(_ rendered: W, _ root: JSONObject?) -> W {
        guard let root = root, !isViewportLockedRoot(root) else { return rendered }
        return w("scroll", ["axis": "vertical", "stretchCross": true, "fillViewport": true], child: rendered)
    }

    private func isViewportLockedRoot(_ root: JSONObject) -> Bool {
        let props = asMap(root["props"]) ?? JSONObject()
        let className = root["className"] ?? props["className"]
        var classes: [String]?
        if let s = className as? String {
            classes = s.components(separatedBy: " ")
        } else if let a = asArray(className) {
            classes = a.map { jsString($0) }
        }
        let inline = root["style"] ?? props["style"]
        let raw = services.stylesheets.getComputedStyleMap(
            ElementFacts(tagName: jsString(root["type"] ?? "div"), id: root["key"] as? String, classes: classes, attributes: props),
            ancestors: [],
            inlineStyles: asMap(inline)
        )
        if jsString(raw["position"] ?? "") == "fixed" { return true }
        if let hv = raw["height"] {
            let h = jsTrim(jsString(hv))
            if !h.isEmpty && (h.contains("vh") || h == "100%") { return true }
        }
        return containsScene(root, 0)
    }

    public func dispose() {
        for id in sceneOrder { scenes[id]?.controller.dispose() }
        scenes.removeAll()
        sceneOrder.removeAll()
        state.removeAll()
        stateOrder.removeAll()
    }
}

private func collectMaps(_ root: ElpianNode) -> [String: [ElpianNode]] {
    var out: [String: [ElpianNode]] = [:]
    func visit(_ n: ElpianNode) {
        if n.type == "map", let name = n.props["name"] as? String {
            var areas: [ElpianNode] = []
            func collect(_ c: ElpianNode) {
                if c.type == "area" { areas.append(c) }
                c.children.forEach(collect)
            }
            n.children.forEach(collect)
            out[name] = areas
        }
        n.children.forEach(visit)
    }
    visit(root)
    return out
}

private func collectDatalists(_ root: ElpianNode) -> [String: [String]] {
    var out: [String: [String]] = [:]
    func visit(_ n: ElpianNode) {
        if n.type == "datalist", n.props["id"] != nil {
            var values: [String] = []
            for c in n.children where c.type == "option" {
                let v: Any? = c.props["value"] ?? c.props["text"] ?? c.children.map { t in jsString(t.props["text"] ?? "") }.joined()
                if jsString(v) != "" { values.append(jsString(v)) }
            }
            out[jsString(n.props["id"])] = values
        }
        n.children.forEach(visit)
    }
    visit(root)
    return out
}

private func containsScene(_ node: JSONObject, _ depth: Int) -> Bool {
    if depth > 6 { return false }
    let type = node["type"] as? String
    if type == "Scene3D" || type == "scene3d" { return true }
    if let children = asArray(node["children"]) {
        for c in children {
            if let m = asMap(c), containsScene(m, depth + 1) { return true }
        }
    }
    return false
}
