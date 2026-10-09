import Foundation

/**
 * The render owner: one per mounted surface (render/owner.ts). It owns the
 * render tree's root, schedules frames, drives tickers (animations), runs
 * layout, and hands the compositor's view operations to the platform.
 */
public protocol Ticker: AnyObject {
    /** Advance to [nowMs]; return false once finished (it is then removed). */
    func tick(_ nowMs: Double) -> Bool
}

/** Callbacks from the render tree back into the session. */
public struct OwnerHooks {
    /** A gesture/control event for the Elpian element [elementId]. */
    public var onElementEvent: ((_ elementId: String, _ event: ViewEvent, _ ro: RenderObject) -> Void)?
    /** Navigation requested by a link (`a`, `NextjsLink`). */
    public var onNavigate: ((_ href: String, _ replace: Bool) -> Void)?
    /** A tap on a clickable Scene3D surface. */
    public var onSceneTap: ((_ props: JSONObject) -> Void)?
    /** A native form-ish submit (NextjsForm). */
    public var onFormSubmit: ((_ action: String, _ values: JSONObject) async -> String?)?
    /** Called after each committed frame. */
    public var onFrameCommitted: ((_ ops: Int) -> Void)?
    public var log: ((_ message: String) -> Void)?

    public init(
        onElementEvent: ((String, ViewEvent, RenderObject) -> Void)? = nil,
        onNavigate: ((String, Bool) -> Void)? = nil,
        onSceneTap: ((JSONObject) -> Void)? = nil,
        onFormSubmit: ((String, JSONObject) async -> String?)? = nil,
        onFrameCommitted: ((Int) -> Void)? = nil,
        log: ((String) -> Void)? = nil
    ) {
        self.onElementEvent = onElementEvent
        self.onNavigate = onNavigate
        self.onSceneTap = onSceneTap
        self.onFormSubmit = onFormSubmit
        self.onFrameCommitted = onFrameCommitted
        self.log = log
    }
}

/** Render objects that animate in from another object's rect (Hero). */
public protocol HeroFlight: AnyObject {
    func flyFrom(_ rect: Rect, _ owner: RenderOwner)
}

public final class RenderOwner {
    public var root: RenderObject?
    public private(set) var compositor: Compositor!
    public let surface: String
    public let platform: Platform
    public var hooks: OwnerHooks
    private var tickers: [Ticker] = []
    private var frameHandle: Int?
    private var dirtyPaint: [ObjectIdentifier: RenderObject] = [:]
    private var needsFrame = false
    private var disposed = false
    private var textCache: [String: TextMetrics] = [:]
    private var nextViewId = 1
    /** When set, the root lays out with these constraints (document mode measures content with an unbounded height). */
    public var rootConstraints: Constraints?
    /** Monotonic frame clock (ms) as of the last tick. */
    public var frameTime = 0.0
    /** Accessibility text scale. */
    public var textScale = 1.0

    public init(surface: String, platform: Platform, hooks: OwnerHooks = OwnerHooks()) {
        self.surface = surface
        self.platform = platform
        self.hooks = hooks
        self.compositor = Compositor(self)
    }

    public func allocateViewId() -> Int {
        let id = nextViewId
        nextViewId += 1
        return id
    }

    // ---------------------------------------------------------------------------
    // Scheduling
    // ---------------------------------------------------------------------------

    public func requestVisualUpdate() {
        if disposed { return }
        needsFrame = true
        if frameHandle != nil { return }
        frameHandle = platform.requestFrame { [weak self] t in
            guard let self = self else { return }
            self.frameHandle = nil
            self.flush(t)
        }
    }

    public func markPaintDirty(_ ro: RenderObject) {
        dirtyPaint[ObjectIdentifier(ro)] = ro
        requestVisualUpdate()
    }

    public func addTicker(_ ticker: Ticker) {
        if !tickers.contains(where: { $0 === ticker }) { tickers.append(ticker) }
        requestVisualUpdate()
    }

    public func removeTicker(_ ticker: Ticker) {
        tickers.removeAll { $0 === ticker }
    }

    public var hasActiveTickers: Bool { !tickers.isEmpty }

    /** Run a frame now: tick animations, lay out, composite and commit. */
    @discardableResult
    public func flush(_ time: Double? = nil) -> [ViewOp] {
        if disposed { return [] }
        let timeMs = time ?? platform.now()
        frameTime = timeMs
        needsFrame = false
        for ticker in tickers {
            let alive = ticker.tick(timeMs)
            if !alive { tickers.removeAll { $0 === ticker } }
        }
        var ops: [ViewOp]
        if let root = root {
            let vp = platform.viewport(surface)
            let constraints = rootConstraints ?? tight(vp.width, vp.height)
            root.layout(constraints)
            updateHeroes(root)
            ops = compositor.composite(root)
        } else {
            ops = compositor.clear()
        }
        dirtyPaint.removeAll()
        if !ops.isEmpty { platform.commit(surface, ops) }
        hooks.onFrameCommitted?(ops.count)
        if !tickers.isEmpty || needsFrame { requestVisualUpdate() }
        return ops
    }

    // ---------------------------------------------------------------------------
    // Hero flights
    // ---------------------------------------------------------------------------

    private var heroes: [String: (ro: RenderObject, rect: Rect)] = [:]

    /** A hero whose tag now belongs to a different object flies from the old rect. */
    private func updateHeroes(_ root: RenderObject) {
        var next: [String: (ro: RenderObject, rect: Rect)] = [:]
        root.visit { ro in
            guard ro.type == "hero", let tag = ro.props["tag"] else { return }
            next[jsString(tag)] = (ro, compositor.globalFrame(ro))
        }
        for (tag, entry) in next {
            if let prev = heroes[tag], prev.ro !== entry.ro, let flight = entry.ro as? HeroFlight {
                flight.flyFrom(prev.rect, self)
            }
        }
        if !next.isEmpty || !heroes.isEmpty { heroes = next }
    }

    // ---------------------------------------------------------------------------
    // Measurement
    // ---------------------------------------------------------------------------

    public func measureText(_ spec: TextSpec, _ maxWidth: Double) -> TextMetrics {
        let width = maxWidth.isFinite ? max(0, jsRound(maxWidth * 100) / 100) : INF
        let key = (width.isFinite ? jsNumberToString(width) : "Infinity") + "|" + stableKey(spec)
        if let hit = textCache[key] { return hit }
        let metrics = platform.measureText(spec, width)
        if textCache.count > 4000 { textCache.removeAll() }
        textCache[key] = metrics
        return metrics
    }

    /** Fonts or the viewport changed: everything must be re-measured. */
    public func invalidateMeasurements() {
        textCache.removeAll()
        root?.visit { $0.needsLayout = true }
        requestVisualUpdate()
    }

    // ---------------------------------------------------------------------------
    // Images
    // ---------------------------------------------------------------------------

    private enum ImageState {
        case known(Size)
        case pending
        case error
    }

    private var imageSizes: [String: ImageState] = [:]

    /** Natural size of [src], or nil while unknown (a load is requested). */
    public func imageSize(_ src: String) -> Size? {
        let known = imageSizes[src]
        if case .known(let size)? = known { return size }
        if known == nil {
            if let direct = platform.imageSize(src) {
                imageSizes[src] = .known(direct)
                return direct
            }
            imageSizes[src] = .pending
            platform.preloadImage(src)
        }
        return nil
    }

    /** The platform finished decoding [src]; images showing it re-lay out. */
    public func imageLoaded(_ src: String, _ width: Double, _ height: Double) {
        if width > 0 && height > 0 {
            imageSizes[src] = .known(Size(width: width, height: height))
        } else {
            imageSizes[src] = .error
        }
        root?.visit { ro in
            if ro.type == "image" && (ro.props["src"] as? String) == src { ro.markNeedsLayout() }
        }
    }

    // ---------------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------------

    /** Route a platform event to the render object owning [event.id]. */
    public func dispatchViewEvent(_ event: ViewEvent) {
        guard let ro = compositor.objectFor(event.id) else { return }
        ro.handleViewEvent(event)
    }

    public func dispose() {
        if disposed { return }
        if let handle = frameHandle { platform.cancelFrame(handle) }
        frameHandle = nil
        tickers.removeAll()
        let ops = compositor.clear()
        if !ops.isEmpty { platform.commit(surface, ops) }
        root?.detach()
        root = nil
        disposed = true
    }

    public var isDisposed: Bool { disposed }
}
