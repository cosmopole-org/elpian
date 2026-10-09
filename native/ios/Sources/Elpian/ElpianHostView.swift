#if canImport(UIKit)
import UIKit
#if !ELPIAN_SINGLE_MODULE
import ElpianCore
#endif

/**
 * A view that hosts one Elpian session: `json`, `miniapp`, `superapp`,
 * `stream`, `nextjs` or `server` (see the core's SessionRegistry for each
 * kind's options and methods — the same as the web host's `mountElpian` and
 * Android's ElpianHostView).
 *
 * Session events (`ready`, `error`, `println`, `updateApp`, `routeChanged`,
 * `result`, …) reach [on] listeners; [onAnyEvent] receives all of them, with
 * payloads as JSON-compatible values (see [onAnyEventJson] for strings, which
 * bridges such as React Native use).
 */
public final class ElpianHostView: UIView {
    /** The surface id the core addresses this view by. */
    public let surfaceId: String

    /** The root the core's views are rendered into. */
    public let surface = ElpianSurfaceView(frame: .zero)

    /** Close the session when the view leaves the window (default true). */
    public var closeOnDetach = true

    private var listeners: [String: [(Int, (Any?) -> Void)]] = [:]
    private var anyListeners: [(Int, (String, Any?) -> Void)] = []
    private var nextListener = 1
    private var opened = false
    private var attached = false

    public override init(frame: CGRect) {
        let platform = Elpian.install()
        surfaceId = Elpian.newSurfaceId()
        super.init(frame: frame)
        surface.frame = bounds
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(surface)
        Elpian.register(surfaceId, self)
        let id = surfaceId
        platform.attachSurface(id, surface) { event in Elpian.registry.dispatchViewEvent(id, event) }
        attached = true
        surface.onSizeChanged = { [weak self] _ in self?.viewportChanged() }
        surface.onInsetsChanged = { [weak self] in self?.viewportChanged() }
        surface.onTraitsChanged = { [weak self] in self?.viewportChanged() }
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func viewportChanged() {
        if opened { Elpian.registry.viewportChanged(surfaceId) }
    }

    // ------------------------------------------------------------------
    // Sessions
    // ------------------------------------------------------------------

    /**
     * Open a session of [kind] with [options] (closing any open one first).
     * [done] receives nil on success or the failure.
     */
    public func open(kind: String, options: [String: Any?] = [:], done: ((Error?) -> Void)? = nil) {
        open(kind: kind, json: JSONObject(options), done: done)
    }

    private func open(kind: String, json options: JSONObject, done: ((Error?) -> Void)?) {
        ensureAttached()
        let id = surfaceId
        let wasOpen = opened
        opened = true
        Task { @MainActor in
            var failure: Error?
            do {
                if wasOpen { try? await Elpian.registry.close(id) }
                try await Elpian.registry.open(kind, id, options)
            } catch {
                self.deliver("error", JSONObject([("message", "\(error)")]))
                failure = error
            }
            done?(failure)
        }
    }

    /** [open] with options as a JSON object string. */
    public func openJson(kind: String, optionsJson: String?, done: ((Error?) -> Void)? = nil) {
        let options = asMap(JSON.parseOrNil(optionsJson)) ?? JSONObject()
        open(kind: kind, json: options, done: done)
    }

    /** Call a session method (navigate, push, callFunction, usage, …). */
    @MainActor
    public func call(_ method: String, args: [Any?] = []) async throws -> Any? {
        try await Elpian.registry.call(surfaceId, method, args)
    }

    /** [call] with a callback. */
    public func call(_ method: String, args: [Any?], callback: @escaping (Result<Any?, Error>) -> Void) {
        let id = surfaceId
        Task { @MainActor in
            do {
                callback(.success(try await Elpian.registry.call(id, method, args)))
            } catch {
                callback(.failure(error))
            }
        }
    }

    /** [call] with JSON arguments (an array) and a JSON result — the shape bridges use. */
    public func callJson(method: String, argsJson: String?, callback: @escaping (_ ok: Bool, _ valueJson: String) -> Void) {
        let parsed = JSON.parseOrNil(argsJson)
        let args: [Any?] = parsed == nil ? [] : (asArray(parsed) ?? [parsed])
        call(method, args: args) { r in
            switch r {
            case .success(let v): callback(true, JSON.stringify(v))
            case .failure(let e): callback(false, JSON.stringify("\(e)"))
            }
        }
    }

    /** Close the session (the view stays usable for another [open]). */
    public func close(done: (() -> Void)? = nil) {
        if !opened {
            done?()
            return
        }
        opened = false
        let id = surfaceId
        Task { @MainActor in
            try? await Elpian.registry.close(id)
            done?()
        }
    }

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------

    /** Listen for session [event]; returns a remover. */
    @discardableResult
    public func on(_ event: String, listener: @escaping (Any?) -> Void) -> () -> Void {
        let token = nextListener
        nextListener += 1
        listeners[event, default: []].append((token, listener))
        return { [weak self] in self?.listeners[event]?.removeAll { $0.0 == token } }
    }

    /** Listen for every session event; returns a remover. */
    @discardableResult
    public func onAnyEvent(_ listener: @escaping (_ event: String, _ payload: Any?) -> Void) -> () -> Void {
        let token = nextListener
        nextListener += 1
        anyListeners.append((token, listener))
        return { [weak self] in self?.anyListeners.removeAll { $0.0 == token } }
    }

    /** [onAnyEvent] with the payload serialized as JSON. */
    @discardableResult
    public func onAnyEventJson(_ listener: @escaping (_ event: String, _ payloadJson: String) -> Void) -> () -> Void {
        onAnyEvent { event, payload in listener(event, JSON.stringify(payload)) }
    }

    func deliver(_ event: String, _ payload: Any?) {
        for (_, l) in listeners[event] ?? [] { l(payload) }
        for (_, l) in anyListeners { l(event, payload) }
    }

    // ------------------------------------------------------------------
    // View lifecycle
    // ------------------------------------------------------------------

    private func ensureAttached() {
        if attached { return }
        Elpian.register(surfaceId, self)
        let id = surfaceId
        Elpian.platform.attachSurface(id, surface) { event in Elpian.registry.dispatchViewEvent(id, event) }
        attached = true
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            ensureAttached()
            viewportChanged()
        } else if closeOnDetach {
            dispose()
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        surface.frame = bounds
    }

    public override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        viewportChanged()
    }

    public override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        viewportChanged()
    }

    /** Close the session and release the surface (re-attaching the view or [open] re-creates it). */
    public func dispose() {
        let wasOpen = opened
        opened = false
        if !attached { return }
        attached = false
        let id = surfaceId
        let platform = Elpian.platform
        if wasOpen {
            // The registry outlives this view; finish the close there, then release the surface.
            Task { @MainActor in
                try? await Elpian.registry.close(id)
                platform.detachSurface(id)
                Elpian.unregister(id)
            }
        } else {
            platform.detachSurface(id)
            Elpian.unregister(id)
        }
    }
}
#endif
