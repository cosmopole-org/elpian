import Foundation

/**
 * A surface: one engine rendering into one platform container
 * (session/surface.ts).
 *
 * It is the native counterpart of a mounted Flutter widget subtree. It
 * re-renders Elpian JSON through the engine, reconciles the widget
 * descriptors into the render tree, and lets the render owner lay out,
 * animate and commit view operations. Sessions (mini apps, streams, Next.js
 * pages) put content on a surface; the platform delivers viewport changes,
 * image loads and view events back to it.
 */
public struct SurfaceOptions {
    /** Share services (stylesheets, events, canvas contexts) with another engine. */
    public var services: ElpianServices?
    /** An existing engine (e.g. one with custom widgets registered). */
    public var engine: ElpianEngine?
    /** Render the content as a scrolling document (`wrapAsDocument`). */
    public var document: Bool
    /** Hooks the content can call back into (navigation, forms…); nil fields are not offered. */
    public var host: EngineHost?

    public init(services: ElpianServices? = nil, engine: ElpianEngine? = nil, document: Bool = false, host: EngineHost? = nil) {
        self.services = services
        self.engine = engine
        self.document = document
        self.host = host
    }
}

/** `{ ...a, ...b }` for engine hosts: every hook [b] offers overrides [a]'s. */
public func mergeEngineHost(_ a: EngineHost?, _ b: EngineHost?) -> EngineHost {
    let out = copyEngineHost(a)
    guard let b = b else { return out }
    if let v = b.navigate { out.navigate = v }
    if let v = b.openUrl { out.openUrl = v }
    if let v = b.sceneTap { out.sceneTap = v }
    if let v = b.submitForm { out.submitForm = v }
    if let v = b.godotBinding { out.godotBinding = v }
    if let v = b.baseUrl { out.baseUrl = v }
    if let v = b.hitTestDragTarget { out.hitTestDragTarget = v }
    if let v = b.invalidate { out.invalidate = v }
    if let v = b.focus { out.focus = v }
    if let v = b.log { out.log = v }
    return out
}

/** A shallow copy (`{ ...host }`). */
public func copyEngineHost(_ h: EngineHost?) -> EngineHost {
    EngineHost(
        navigate: h?.navigate,
        openUrl: h?.openUrl,
        sceneTap: h?.sceneTap,
        submitForm: h?.submitForm,
        godotBinding: h?.godotBinding,
        baseUrl: h?.baseUrl,
        hitTestDragTarget: h?.hitTestDragTarget,
        invalidate: h?.invalidate,
        focus: h?.focus,
        log: h?.log
    )
}

private let surfacesLock = NSLock()
private var surfaces: [String: ElpianSurface] = [:]

/** The surface registered under [id] (platform events are routed by it). */
public func surfaceById(_ id: String) -> ElpianSurface? {
    surfacesLock.lock()
    defer { surfacesLock.unlock() }
    return surfaces[id]
}

/** The platform's log level for an engine-host level name. */
func logLevel(_ name: String) -> LogLevel { LogLevel(rawValue: name) ?? .info }

public final class ElpianSurface {
    public let id: String
    public let engine: ElpianEngine
    public let owner: RenderOwner
    private var content: JSONObject?
    private var overlay: W?
    private var renderScheduled = false
    private var disposed = false
    private let document: Bool
    private let hostHooks: EngineHost
    private var lastViewport = ""

    /** Where the surface's deferred work runs (main-actor tasks); cancelled on dispose. */
    public let scope = TaskScope()

    /** Wraps the lowered content each render (e.g. the stream's AnimatedSwitcher). */
    public var decorate: ((_ content: W) -> W)?

    public init(_ id: String, _ options: SurfaceOptions = SurfaceOptions()) {
        self.id = id
        document = options.document
        let hooks = copyEngineHost(options.host)
        hostHooks = hooks
        let host = copyEngineHost(hooks)
        // The hooks below reach the surface once it is initialised; until then they have no target.
        weak var weakSelf: ElpianSurface?
        host.invalidate = {
            hooks.invalidate?()
            weakSelf?.scheduleRender()
        }
        host.focus = { htmlId in
            if let f = hooks.focus { f(htmlId) } else { _ = weakSelf?.focus(htmlId) }
        }
        host.hitTestDragTarget = { x, y in hooks.hitTestDragTarget?(x, y) ?? weakSelf?.hitTestDragTarget(x, y) }
        host.log = { level, message in
            if let l = hooks.log { l(level, message) } else { platform().log(logLevel(level), message) }
        }
        if let given = options.engine {
            engine = given
            engine.host = mergeEngineHost(engine.host, host)
        } else {
            engine = ElpianEngine(services: options.services ?? ElpianServices(appId: id), host: host)
        }
        owner = RenderOwner(surface: id, platform: platform())
        weakSelf = self
        surfacesLock.lock()
        surfaces[id] = self
        surfacesLock.unlock()
        syncEnvironment()
    }

    public var isDisposed: Bool { disposed }

    public var currentContent: JSONObject? { content }

    /** Replace the rendered Elpian JSON (nil clears the surface). */
    public func setContent(_ json: JSONObject?) {
        content = json
        overlay = nil
        scheduleRender()
    }

    /** Show a lowered widget instead of content (loading / error states). */
    public func setOverlay(_ widget: W?) {
        overlay = widget
        scheduleRender()
    }

    /** Re-render on the next main-actor turn (coalesces bursts of state changes). */
    public func scheduleRender() {
        if renderScheduled || disposed { return }
        renderScheduled = true
        scope.launch { [weak self] in
            guard let self = self else { return }
            self.renderScheduled = false
            self.renderNow()
        }
    }

    /** Lower and reconcile now; the owner commits on the next frame. */
    public func renderNow() {
        if disposed { return }
        syncEnvironment()
        var widget: W? = overlay
        if widget == nil, let c = content {
            var out = engine.renderFromJson(c)
            if document { out = engine.wrapAsDocument(out, c) }
            if let d = decorate { out = d(out) }
            widget = out
        }
        guard let lowered = widget else {
            if let root = owner.root {
                root.detach()
                owner.root = nil
            }
            owner.requestVisualUpdate()
            return
        }
        owner.root = reconcileRoot(owner.root, lowered, owner)
        owner.requestVisualUpdate()
    }

    /** The platform reports a new size, safe area, text scale or theme. */
    public func viewportChanged() {
        if syncEnvironment() { renderNow() } else { owner.requestVisualUpdate() }
    }

    @discardableResult
    private func syncEnvironment() -> Bool {
        let vp = platform().viewport(id)
        let s = vp.safeArea
        let key = "\(vp.width),\(vp.height),\(s.top),\(s.right),\(s.bottom),\(s.left),\(vp.devicePixelRatio),\(vp.textScale),\(vp.darkMode)"
        if key == lastViewport { return false }
        lastViewport = key
        CssEnvironment.update(viewportWidth: vp.width, viewportHeight: vp.height, safeArea: vp.safeArea, devicePixelRatio: vp.devicePixelRatio)
        engine.services.stylesheets.darkMode = vp.darkMode
        if owner.textScale != vp.textScale {
            owner.textScale = vp.textScale
            owner.invalidateMeasurements()
        }
        return true
    }

    /** A native view reported an event (tap, change, scroll, load…). */
    public func dispatchViewEvent(_ event: ViewEvent) {
        if disposed { return }
        owner.dispatchViewEvent(event)
    }

    /** An image finished loading (or failed with 0×0). */
    public func imageLoaded(_ src: String, _ width: Double, _ height: Double) {
        owner.imageLoaded(src, width, height)
    }

    /** Fonts changed or text metrics are otherwise stale. */
    public func invalidateText() {
        owner.invalidateMeasurements()
    }

    /** Focus the control rendered for the element with HTML id [htmlId] (`<label for>`). */
    @discardableResult
    public func focus(_ htmlId: String) -> Bool {
        var target: RenderObject?
        owner.root?.visit { ro in
            if target == nil, (ro.props["focusId"] as? String) == htmlId, ro.viewId != nil { target = ro }
        }
        guard let viewId = target?.viewId else { return false }
        owner.compositor.command(viewId, "focus")
        return true
    }

    /** The DragTarget element under a point in surface coordinates. */
    public func hitTestDragTarget(_ x: Double, _ y: Double) -> String? {
        var hit: String?
        owner.root?.visit { ro in
            guard let id = ro.props["dragTargetId"] else { return }
            if (id as? String) == "" || jsBool(id) == false { return }
            let f = owner.compositor.globalFrame(ro)
            if x >= f.x && y >= f.y && x <= f.x + f.width && y <= f.y + f.height { hit = jsString(id) }
        }
        return hit
    }

    public func dispose() {
        if disposed { return }
        disposed = true
        surfacesLock.lock()
        if surfaces[id] === self { surfaces.removeValue(forKey: id) }
        surfacesLock.unlock()
        scope.cancel()
        owner.dispose()
        engine.dispose()
    }
}

/** The red/orange diagnostic box Flutter shows for VM and render errors. */
public func messageBox(_ message: String, _ color: Color) -> W {
    let tint: Color = (0x1a << 24) | (color & 0xffffff)
    // Container(padding: 16, color: color @ 10%, child: Text(message, color)).
    return w(
        "decorated",
        ["decoration": BoxDecoration(color: tint)],
        child: w("padding", ["padding": EdgeInsets(top: 16, right: 16, bottom: 16, left: 16)],
                 child: w("text", ["text": message, "style": TextStyle(color: color)]))
    )
}

/** `Center(CircularProgressIndicator())`. */
public func loadingIndicator() -> W {
    w(
        "align",
        ["alignment": Alignment(x: 0, y: 0)],
        child: w(
            "control",
            [
                "kind": "progress",
                "view": JSONObject([
                    ("variant", "circular"),
                    ("value", nil),
                    ("strokeWidth", 4.0),
                    ("colors", JSONObject([("indicator", M3.primary), ("track", nil)])),
                ]),
            ]
        )
    )
}
