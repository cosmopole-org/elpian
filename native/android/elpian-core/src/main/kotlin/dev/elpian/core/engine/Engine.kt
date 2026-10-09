package dev.elpian.core.engine

import dev.elpian.core.canvas.CanvasContextStore
import dev.elpian.core.canvas.CanvasExecutor
import dev.elpian.core.css.CSSParser
import dev.elpian.core.css.CSSStyle
import dev.elpian.core.css.ElementFacts
import dev.elpian.core.css.StyleMap
import dev.elpian.core.css.StylesheetManager
import dev.elpian.core.events.ElpianEvent
import dev.elpian.core.events.EventDispatcher
import dev.elpian.core.events.Point
import dev.elpian.core.events.makeEvent
import dev.elpian.core.godot.GodotBinding
import dev.elpian.core.godot.GodotSceneController
import dev.elpian.core.godot.MockGodotBinding
import dev.elpian.core.godot.SceneDsl
import dev.elpian.core.godot.launchDetached
import dev.elpian.core.host.ElpianDOM
import dev.elpian.core.model.ElpianNode
import dev.elpian.core.render.ViewEvent
import dev.elpian.core.render.W
import dev.elpian.core.render.w
import dev.elpian.core.util.jsString
import dev.elpian.core.util.stableKey
import dev.elpian.core.widgets.BuildContext
import dev.elpian.core.widgets.WidgetBuilder
import dev.elpian.core.widgets.registerDefaultWidgets
import kotlin.math.abs

/**
 * ElpianEngine — the Kotlin twin of `elpian_engine.dart` + `ElpianServices`
 * (engine/engine.ts).
 *
 * `render(node)` resolves each element's cascaded style, honours
 * `display: none`, lowers the node through its registered widget builder,
 * and wraps event-bearing elements in a gesture region registered with the
 * event dispatcher — exactly the steps of the Flutter `_render`. The result is
 * a widget-descriptor tree the render owner reconciles and lays out.
 */
class ElpianServices(val appId: String = "default") {
    val events = EventDispatcher()
    val stylesheets = StylesheetManager()
    val canvasContexts = CanvasContextStore()
    val canvas = CanvasExecutor()
    val dom = ElpianDOM()
    val registry: MutableMap<String, WidgetBuilder> = LinkedHashMap()

    /** Namespace a guest-chosen id so mini apps never collide (`appId::id`). */
    fun scopeId(id: String): String = "$appId::$id"

    fun dispose() {
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
 * callback is optional (null = the host does not offer it).
 */
class EngineHost(
    /** A link (`a href`, `NextjsLink`) was activated. */
    var navigate: ((href: String, replace: Boolean) -> Unit)? = null,
    /** Open an external URL. */
    var openUrl: ((url: String) -> Unit)? = null,
    /** A tap on a clickable Scene3D (ElpianSceneTaps). */
    var sceneTap: ((props: Map<String, Any?>) -> Unit)? = null,
    /** `NextjsForm` submission; returns an error message or null. */
    var submitForm: (suspend (action: String, values: Map<String, Any?>) -> String?)? = null,
    /** The Godot transport for new Scene3D surfaces. */
    var godotBinding: (() -> GodotBinding?)? = null,
    /** Base URL for relative resource paths (ElpianResources.baseUrl). */
    var baseUrl: (() -> String?)? = null,
    /** The id of the drag target (DragTarget element) under a global point. */
    var hitTestDragTarget: ((x: Double, y: Double) -> String?)? = null,
    /** Request a re-render (element state changed). */
    var invalidate: (() -> Unit)? = null,
    /** Move input focus to the control rendered for the element with HTML id [id]. */
    var focus: ((id: String) -> Unit)? = null,
    var log: ((level: String, message: String) -> Unit)? = null,
)

class SceneEntry(val controller: GodotSceneController, var sceneKey: String?, var attached: Boolean)

private val EVENT_GESTURES: Map<String, String> = mapOf(
    "click" to "tap",
    "tap" to "tap",
    "doubletap" to "doubletap",
    "dblclick" to "doubletap",
    "longpress" to "longpress",
    "contextmenu" to "longpress",
    "tapdown" to "tapdown",
    "tapup" to "tapup",
    "tapcancel" to "tapcancel",
    "drag" to "pan",
    "dragstart" to "pan",
    "dragend" to "pan",
    "swipeleft" to "swipe",
    "swiperight" to "swipe",
    "swipeup" to "swipe",
    "swipedown" to "swipe",
    "pointerdown" to "pointer",
    "pointerup" to "pointer",
    "pointermove" to "pointer",
    "pointercancel" to "pointer",
    "pointerenter" to "hover",
    "pointerexit" to "hover",
    "pointerhover" to "hover",
    "mouseenter" to "hover",
    "mouseleave" to "hover",
    "keydown" to "key",
    "keyup" to "key",
    "keypress" to "key",
    "focus" to "focus",
    "blur" to "focus",
    "scalestart" to "scale",
    "scaleupdate" to "scale",
    "scaleend" to "scale",
    "pinchstart" to "scale",
    "pinchupdate" to "scale",
    "pinchend" to "scale",
    "rotatestart" to "scale",
    "rotateupdate" to "scale",
    "rotateend" to "scale",
    "scroll" to "scroll",
)

private val EVENT_TYPE_NAMES: Map<String, String> = mapOf(
    "click" to "click",
    "tap" to "tap",
    "doubletap" to "doubleClick",
    "longpress" to "longPress",
    "tapdown" to "tapDown",
    "tapup" to "tapUp",
    "tapcancel" to "tapCancel",
    "pointerdown" to "pointerDown",
    "pointerup" to "pointerUp",
    "pointermove" to "pointerMove",
    "pointerenter" to "pointerEnter",
    "pointerexit" to "pointerExit",
    "pointerhover" to "pointerHover",
    "pointercancel" to "pointerCancel",
    "dragstart" to "dragStart",
    "drag" to "drag",
    "dragend" to "dragEnd",
    "dragenter" to "dragEnter",
    "dragleave" to "dragLeave",
    "dragover" to "dragOver",
    "drop" to "drop",
    "focus" to "focus",
    "blur" to "blur",
    "input" to "input",
    "change" to "change",
    "submit" to "submit",
    "keydown" to "keyDown",
    "keyup" to "keyUp",
    "keypress" to "keyPress",
    "scroll" to "scroll",
    "swipeleft" to "swipeLeft",
    "swiperight" to "swipeRight",
    "swipeup" to "swipeUp",
    "swipedown" to "swipeDown",
    "scalestart" to "scaleStart",
    "scaleupdate" to "scaleUpdate",
    "scaleend" to "scaleEnd",
    "pinchstart" to "pinchStart",
    "pinchupdate" to "pinchUpdate",
    "pinchend" to "pinchEnd",
    "rotatestart" to "rotateStart",
    "rotateupdate" to "rotateUpdate",
    "rotateend" to "rotateEnd",
    "load" to "load",
    "select" to "select",
    "reset" to "reset",
    "resize" to "resize",
)

fun eventTypeFor(name: String): String = EVENT_TYPE_NAMES[name] ?: "custom"

private val ABSOLUTE_URL = Regex("^(https?:|data:|blob:|asset:|file:|content:)", RegexOption.IGNORE_CASE)
private val ORIGIN = Regex("^[a-z]+://[^/]+", RegexOption.IGNORE_CASE)
private val TRAILING_SLASHES = Regex("/+$")

class ElpianEngine(services: ElpianServices? = null, var host: EngineHost = EngineHost()) {
    val services: ElpianServices = services ?: ElpianServices()

    /** Per-element state that survives re-renders (details open, select value …). */
    @PublishedApi internal val state = LinkedHashMap<String, Any?>()
    @PublishedApi internal var seen = HashSet<String>()
    private val scenes = LinkedHashMap<String, SceneEntry>()
    /** Nodes registered with the dispatcher this render. */
    private var registered = LinkedHashSet<String>()
    private var previousRegistered = LinkedHashSet<String>()

    init {
        registerDefaultWidgets(this)
    }

    // ---------------------------------------------------------------------------
    // Configuration
    // ---------------------------------------------------------------------------

    fun registerWidget(type: String, builder: WidgetBuilder) {
        services.registry[type] = builder
    }

    fun registerWidgets(builders: Map<String, WidgetBuilder>) {
        for ((k, v) in builders) services.registry[k] = v
    }

    /** A JSON stylesheet map or CSS text. */
    fun loadStylesheet(sheet: Any?) {
        services.stylesheets.load(sheet)
    }

    fun clearStylesheets() {
        services.stylesheets.clear()
    }

    fun resolveUrl(src: String): String {
        if (src.isEmpty() || ABSOLUTE_URL.containsMatchIn(src)) return src
        val base = host.baseUrl?.invoke()
        if (base.isNullOrEmpty()) return src
        if (src.startsWith("//")) return (if (base.startsWith("https")) "https:" else "http:") + src
        if (src.startsWith("/")) {
            val origin = ORIGIN.find(base)?.value ?: base
            return origin + src
        }
        return base.replace(TRAILING_SLASHES, "") + "/" + src
    }

    // ---------------------------------------------------------------------------
    // Element state
    // ---------------------------------------------------------------------------

    /**
     * State for [elementId], created by [init] on first use; kept while the
     * element renders. A state of another kind left at the same id (the
     * element changed type under a stable key) is replaced.
     */
    inline fun <reified T> stateFor(elementId: String, init: () -> T): T {
        seen.add(elementId)
        val existing = state[elementId]
        if (existing is T && state.containsKey(elementId)) return existing
        val created = init()
        state[elementId] = created
        return created
    }

    /** Merge [patch] into the map state of [elementId] and request a re-render. */
    fun setState(elementId: String, patch: Map<String, Any?>) {
        @Suppress("UNCHECKED_CAST")
        val current = state[elementId] as? Map<String, Any?> ?: emptyMap()
        state[elementId] = LinkedHashMap(current).also { it.putAll(patch) }
        host.invalidate?.invoke()
    }

    // ---------------------------------------------------------------------------
    // Rendering
    // ---------------------------------------------------------------------------

    fun renderFromJson(json: Map<String, Any?>): W = render(ElpianNode.fromJson(json))

    fun render(root: ElpianNode): W {
        seen = HashSet()
        formFields = LinkedHashMap()
        imageMaps = collectMaps(root)
        datalists = collectDatalists(root)
        previousRegistered = registered
        registered = LinkedHashSet()
        val ctx = BuildContext(engine = this, parentId = null, ancestors = emptyList(), path = "r", elementId = "r", formId = null)
        val result = renderNode(root, ctx, 0)
        collectGarbage()
        return result
    }

    private fun collectGarbage() {
        for (id in state.keys.toList()) if (id !in seen) state.remove(id)
        for ((id, entry) in scenes.entries.toList()) {
            if (id !in seen) {
                entry.controller.dispose()
                scenes.remove(id)
            }
        }
        for (id in previousRegistered) if (id !in registered) services.events.unregisterNode(id)
    }

    /** Resolve the cascaded style of [node] (stylesheet + `@media` + inline + `!important`). */
    @Suppress("UNCHECKED_CAST")
    fun resolveStyle(node: ElpianNode, ancestors: List<ElementFacts>): CSSStyle? {
        val inline = node.props["style"] as? Map<String, Any?>
        val sheets = services.stylesheets
        if (sheets.hasRules) {
            val computed = sheets.getComputedStyleMap(factsOf(node), ancestors, inline)
            return if (computed.isNotEmpty()) CSSParser.parse(computed) else null
        }
        if (inline != null) return CSSParser.parse(sheets.substituteVariables(inline))
        return null
    }

    fun factsOf(node: ElpianNode): ElementFacts = ElementFacts(
        tagName = node.type,
        id = node.key ?: (node.props["id"] as? String),
        classes = node.classes,
        attributes = node.props,
    )

    fun renderNode(node: ElpianNode, parentCtx: BuildContext, index: Int): W {
        val path = "${parentCtx.path}/$index"
        val htmlId = node.props["id"] as? String
        val elementId = node.key ?: (if (!htmlId.isNullOrEmpty()) "#$htmlId" else "$path:${node.type}")
        seen.add(elementId)

        if (node.type == "#text") {
            return w("text", mapOf("text" to jsString(node.props["text"] ?: "")))
        }

        val builder = services.registry[node.type]
        if (builder == null) {
            host.log?.invoke("warn", "Unknown widget type \"${node.type}\"")
            return w(
                "decorated",
                mapOf("decoration" to dev.elpian.core.render.paint.Decoration(color = 0x33f44336)),
                w("padding", mapOf("padding" to dev.elpian.core.css.EdgeInsets(8.0, 8.0, 8.0, 8.0)), w("text", mapOf("text" to "Unknown widget: ${node.type}"))),
            )
        }

        val style = resolveStyle(node, parentCtx.ancestors) ?: node.style
        val styled = if (style !== node.style) node.copy(style = style) else node

        if (style?.display == "none") return w("constrained", mapOf("width" to 0.0, "height" to 0.0))

        val hasEvents = !node.events.isNullOrEmpty()
        if (hasEvents || node.key != null) {
            services.events.registerNode(elementId, styled, parentCtx.parentId)
            registered.add(elementId)
        }

        val facts = factsOf(node)
        val ctx = BuildContext(
            engine = this,
            parentId = if (hasEvents || node.key != null) elementId else parentCtx.parentId,
            ancestors = listOf(facts) + parentCtx.ancestors,
            path = path,
            elementId = elementId,
            formId = if (node.type == "form" || node.type == "NextjsForm") elementId else parentCtx.formId,
        )

        // Resolve children's styles up-front so layout builders (HtmlDiv) can read them.
        val childNodes = styled.children.map { child ->
            if (child.type == "#text") {
                child
            } else {
                val childStyle = resolveStyle(child, ctx.ancestors) ?: child.style
                if (childStyle !== child.style) child.copy(style = childStyle) else child
            }
        }
        val withChildren = ElpianNode(styled.type, styled.props, childNodes, styled.key, styled.events, styled.style)
        val children = childNodes.mapIndexed { i, child -> renderNode(child, ctx, i) }

        var result = builder(withChildren, children, ctx.copy(parentId = ctx.parentId, elementId = elementId))

        if (hasEvents) {
            result = wrapEvents(withChildren, elementId, result)
        }
        if (node.key != null && result.k == null) result = W(result.t, result.p, result.c, node.key)
        return result
    }

    /** `EventEnabledWidget`: a gesture region recognising what the node listens for. */
    fun wrapEvents(node: ElpianNode, elementId: String, child: W): W {
        val gestures = LinkedHashSet<String>()
        for (name in node.events?.keys ?: emptySet()) {
            val g = EVENT_GESTURES[name.lowercase()]
            if (g != null) gestures.add(g)
            if (g == "key") gestures.add("focus")
        }
        if (gestures.isEmpty()) return child
        val listensTap = "tap" in gestures
        return w(
            "gesture",
            mapOf(
                "gestures" to gestures.toList(),
                "cursor" to (if (listensTap) node.style?.cursor ?: "pointer" else node.style?.cursor),
                "focusable" to ("key" in gestures || "focus" in gestures),
                "onEvent" to { event: ViewEvent -> handleGesture(elementId, node, event) },
            ),
            child,
            "ev:$elementId",
        )
    }

    /** Translate a platform gesture into Elpian events and dispatch them. */
    @Suppress("UNCHECKED_CAST")
    fun handleGesture(elementId: String, node: ElpianNode, event: ViewEvent) {
        val events = node.events ?: emptyMap()
        fun has(name: String) = events.containsKey(name)
        val pos = event.x?.let { Point(it, event.y ?: 0.0) }
        val local = event.localX?.let { Point(it, event.localY ?: 0.0) } ?: pos
        fun dispatch(type: String, init: ElpianEvent.() -> Unit = {}) =
            services.events.dispatchEvent(makeEvent(type, eventTypeFor(type), elementId, init), elementId)
        val zero = Point(0.0, 0.0)
        when (event.type) {
            "tap" -> {
                if (has("tap")) dispatch("tap") { if (pos != null) { position = pos; localPosition = local } }
                if (has("click")) dispatch("click") { if (pos != null) { position = pos; localPosition = local } }
            }
            "doubletap" -> dispatch(if (has("dblclick") && !has("doubletap")) "dblclick" else "doubletap")
            "longpress" -> dispatch(if (has("contextmenu") && !has("longpress")) "contextmenu" else "longpress") {
                if (pos != null) { position = pos; localPosition = local }
            }
            "tapdown", "tapup" -> dispatch(event.type) { position = pos ?: zero; localPosition = local ?: zero }
            "tapcancel" -> dispatch("tapcancel")
            "dragstart" -> if (has("dragstart")) dispatch("dragstart") { position = pos ?: zero; localPosition = local ?: zero }
            "drag" -> if (has("drag")) dispatch("drag") {
                position = pos ?: zero
                localPosition = local ?: zero
                delta = Point(event.dx ?: 0.0, event.dy ?: 0.0)
            }
            "dragend" -> if (has("dragend")) dispatch("dragend") { position = zero; localPosition = zero }
            "swipe" -> {
                val vx = event.vx ?: 0.0
                val vy = event.vy ?: 0.0
                val dir = event.direction ?: (if (abs(vx) > abs(vy)) (if (vx < 0) "left" else "right") else if (vy < 0) "up" else "down")
                val name = "swipe$dir"
                if (has(name)) dispatch(name) {
                    velocity = Point(vx, vy)
                    scale = 1.0
                    rotation = 0.0
                    focalPoint = zero
                }
            }
            "pointerdown", "pointerup", "pointermove", "pointercancel", "pointerenter", "pointerexit", "pointerhover" -> {
                val alias = when {
                    event.type == "pointerenter" && !has("pointerenter") && has("mouseenter") -> "mouseenter"
                    event.type == "pointerexit" && !has("pointerexit") && has("mouseleave") -> "mouseleave"
                    else -> event.type
                }
                if (has(alias)) {
                    dispatch(alias) {
                        position = pos ?: zero
                        localPosition = local ?: zero
                        delta = Point(event.dx ?: 0.0, event.dy ?: 0.0)
                        buttons = event.buttons ?: 0
                        pressure = event.pressure ?: 1.0
                        pointerId = event.pointerId ?: 0
                    }
                }
            }
            "keydown", "keyup", "keypress" -> if (has(event.type)) dispatch(event.type) {
                key = event.key ?: ""
                keyCode = event.keyCode ?: 0
                altKey = event.altKey == true
                ctrlKey = event.ctrlKey == true
                shiftKey = event.shiftKey == true
                metaKey = event.metaKey == true
            }
            "focus", "blur" -> if (has(event.type)) dispatch(event.type)
            "scalestart", "scaleupdate", "scaleend" -> {
                val suffix = event.type.substring(5)
                for (prefix in listOf("scale", "pinch", "rotate")) {
                    if (has(prefix + suffix)) dispatch(prefix + suffix) {
                        velocity = Point(event.vx ?: 0.0, event.vy ?: 0.0)
                        scale = event.scale ?: 1.0
                        rotation = event.rotation ?: 0.0
                        focalPoint = pos ?: zero
                    }
                }
            }
            "scroll" -> if (has("scroll")) dispatch("scroll") { data = mapOf("scrollX" to (event.scrollX ?: 0.0), "scrollY" to (event.scrollY ?: 0.0)) }
            else -> if (has(event.type)) dispatch(event.type) {
                value = event.value
                data = event.data as? Map<String, Any?> ?: emptyMap()
            }
        }
    }

    // ---------------------------------------------------------------------------
    // Forms and image maps
    // ---------------------------------------------------------------------------

    private var formFields = LinkedHashMap<String, LinkedHashMap<String, () -> Any?>>()
    /** `<map name>` → its `<area>` nodes, collected before each render. */
    var imageMaps: Map<String, List<ElpianNode>> = emptyMap()
    /** `<datalist id>` → its option values (feeds `<input list>` suggestions). */
    var datalists: Map<String, List<String>> = emptyMap()

    /** `<label for>`: focus the control of the element with HTML id [id]. */
    fun focusElement(id: String) {
        host.focus?.invoke(id)
    }

    /** A named form control reports its current value through [read]. */
    fun registerFormField(formId: String?, name: String?, read: () -> Any?) {
        if (formId.isNullOrEmpty() || name.isNullOrEmpty()) return
        formFields.getOrPut(formId) { LinkedHashMap() }[name] = read
    }

    fun formValues(formId: String): Map<String, Any?> {
        val out = LinkedHashMap<String, Any?>()
        for ((name, read) in formFields[formId] ?: emptyMap<String, () -> Any?>()) out[name] = read()
        return out
    }

    /** Submit [formId]: the form element receives `submit` with its field values. */
    fun submitForm(formId: String) {
        val values = formValues(formId)
        services.events.dispatchEvent(
            makeEvent("submit", "submit", formId) {
                data = mapOf("values" to values)
                value = values
            },
            formId,
        )
    }

    // ---------------------------------------------------------------------------
    // Drag and drop (Draggable / DragTarget)
    // ---------------------------------------------------------------------------

    private var dragTarget: String? = null

    private fun dispatchTo(elementId: String, type: String, data: Map<String, Any?>) {
        services.events.dispatchEvent(makeEvent(type, eventTypeFor(type), elementId) { this.data = data }, elementId)
    }

    /** A Draggable moved: update DragTarget enter / leave / over. */
    fun dragOver(sourceId: String, e: ViewEvent, data: Any?) {
        val target = if (e.x != null) host.hitTestDragTarget?.invoke(e.x, e.y ?: 0.0) else null
        if (target != dragTarget) {
            dragTarget?.let { dispatchTo(it, "dragleave", mapOf("data" to data, "source" to sourceId)) }
            if (target != null) dispatchTo(target, "dragenter", mapOf("data" to data, "source" to sourceId))
            dragTarget = target
        }
        if (target != null) dispatchTo(target, "dragover", mapOf("data" to data, "source" to sourceId, "x" to e.x, "y" to e.y))
        dispatchTo(sourceId, "drag", mapOf("x" to e.x, "y" to e.y))
    }

    /** A Draggable was released: the target under the pointer accepts it. */
    fun dropAt(sourceId: String, e: ViewEvent, data: Any?) {
        val target = if (e.x != null) host.hitTestDragTarget?.invoke(e.x, e.y ?: 0.0) else null
        if (target != null) {
            dispatchTo(target, "drop", mapOf("data" to data, "source" to sourceId))
            dispatchTo(target, "accept", mapOf("data" to data, "source" to sourceId))
        }
        dispatchTo(sourceId, "dragend", mapOf("accepted" to (target != null), "target" to target))
        val previous = dragTarget
        if (previous != null && previous != target) dispatchTo(previous, "dragleave", mapOf("data" to data, "source" to sourceId))
        dragTarget = null
    }

    // ---------------------------------------------------------------------------
    // Scene3D
    // ---------------------------------------------------------------------------

    /** The scene controller of a Scene3D element, building / replacing its DSL scene. */
    fun sceneFor(elementId: String, sceneJson: Map<String, Any?>?): GodotSceneController {
        seen.add(elementId)
        val entry = scenes.getOrPut(elementId) {
            val binding = host.godotBinding?.invoke() ?: MockGodotBinding()
            SceneEntry(GodotSceneController(binding), null, false)
        }
        val key = sceneJson?.let { stableKey(it) }
        if (sceneJson != null && key != entry.sceneKey) {
            if (entry.sceneKey == null) {
                entry.controller.adopt(SceneDsl(entry.controller.godot).build(sceneJson))
            } else {
                entry.controller.replaceScene(sceneJson)
            }
            entry.sceneKey = key
        }
        if (!entry.attached) {
            entry.attached = true
            val godot = entry.controller.godot
            launchDetached { godot.attachSurface() }
        }
        return entry.controller
    }

    /** The Scene3D controllers currently alive, by element id. */
    val sceneControllers: Map<String, SceneEntry> get() = scenes

    // ---------------------------------------------------------------------------
    // Documents
    // ---------------------------------------------------------------------------

    /**
     * `wrapAsDocument`: a screen root scrolls vertically like `<body>` unless it
     * is a viewport-locked stage (`position: fixed`, `height: 100vh|100%`, or
     * it embeds a Scene3D).
     */
    fun wrapAsDocument(rendered: W, root: Map<String, Any?>?): W {
        if (root == null || isViewportLockedRoot(root)) return rendered
        return w("scroll", mapOf("axis" to "vertical", "stretchCross" to true, "fillViewport" to true), rendered)
    }

    @Suppress("UNCHECKED_CAST")
    private fun isViewportLockedRoot(root: Map<String, Any?>): Boolean {
        val props = root["props"] as? Map<String, Any?> ?: emptyMap()
        val className = root["className"] ?: props["className"]
        val classes = when (className) {
            is String -> className.split(" ")
            is List<*> -> className.map { jsString(it) }
            else -> null
        }
        val inline = root["style"] ?: props["style"]
        val raw = services.stylesheets.getComputedStyleMap(
            ElementFacts(tagName = jsString(root["type"] ?: "div"), id = root["key"] as? String, classes = classes, attributes = props),
            emptyList(),
            inline as? StyleMap,
        )
        if (jsString(raw["position"] ?: "") == "fixed") return true
        val h = raw["height"]?.let { jsString(it).trim() }
        if (!h.isNullOrEmpty() && (h.contains("vh") || h == "100%")) return true
        return containsScene(root, 0)
    }

    fun dispose() {
        for (entry in scenes.values) entry.controller.dispose()
        scenes.clear()
        state.clear()
    }
}

private fun collectMaps(root: ElpianNode): Map<String, List<ElpianNode>> {
    val out = LinkedHashMap<String, List<ElpianNode>>()
    fun visit(n: ElpianNode) {
        val name = n.props["name"]
        if (n.type == "map" && name is String) {
            val areas = ArrayList<ElpianNode>()
            fun collect(c: ElpianNode) {
                if (c.type == "area") areas.add(c)
                c.children.forEach { collect(it) }
            }
            n.children.forEach { collect(it) }
            out[name] = areas
        }
        n.children.forEach { visit(it) }
    }
    visit(root)
    return out
}

private fun collectDatalists(root: ElpianNode): Map<String, List<String>> {
    val out = LinkedHashMap<String, List<String>>()
    fun visit(n: ElpianNode) {
        if (n.type == "datalist" && n.props["id"] != null) {
            val values = ArrayList<String>()
            for (c in n.children) {
                if (c.type != "option") continue
                val v = c.props["value"] ?: c.props["text"] ?: c.children.joinToString("") { t -> jsString(t.props["text"] ?: "") }
                if (jsString(v) != "") values.add(jsString(v))
            }
            out[jsString(n.props["id"])] = values
        }
        n.children.forEach { visit(it) }
    }
    visit(root)
    return out
}

@Suppress("UNCHECKED_CAST")
private fun containsScene(node: Map<String, Any?>, depth: Int): Boolean {
    if (depth > 6) return false
    if (node["type"] == "Scene3D" || node["type"] == "scene3d") return true
    val children = node["children"]
    if (children is List<*>) {
        for (c in children) if (c is Map<*, *> && containsScene(c as Map<String, Any?>, depth + 1)) return true
    }
    return false
}

/** Re-exported for hosts wiring a platform Godot binding into [EngineHost.godotBinding]. */
typealias PlatformGodotBinding = dev.elpian.core.godot.PlatformGodotBinding

