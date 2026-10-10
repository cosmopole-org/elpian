import Foundation

/**
 * One running mini app on one surface — the port of `ElpianVmWidget`
 * (flutter/lib/src/vm/elpian_vm_widget.dart; session/miniapp.ts).
 *
 * It creates the selected runtime, wires every host API (render, DOM,
 * canvas, env, timers, plus host-supplied handlers), runs the program and its
 * entry function, routes UI events to the guest functions named in each
 * node's `events`, applies bounded scope patches, and keeps the guest's host
 * environment (viewport, safe area, page, platform) in sync.
 */
public struct MiniAppOptions {
    public var machineId: String
    public var runtime: RuntimeKind
    /** Elpian source, JS source (QuickJS) or the WASM config JSON. */
    public var code: String?
    public var astJson: String?
    /** Elpian VM bytecode, base64. */
    public var bytecodeBase64: String?
    /** A stylesheet JSON map or CSS text. */
    public var stylesheet: Any?
    public var entryFunction: String?
    public var entryInput: String?
    public var hostHandlers: [String: HostCallHandler]?
    /** Extra host-environment fields merged into `env.get`. */
    public var hostEnvironment: JSONObject?
    public var onPrintln: ((_ message: String) -> Void)?
    public var onUpdateApp: ((_ data: JSONObject) -> Void)?
    public var onError: ((_ message: String) -> Void)?
    /** Consulted before every host call (HostHandler.onAuthorize). */
    public var onAuthorize: ((_ apiName: String) -> Bool)?
    public var onCallRefused: ((_ apiName: String) -> Void)?
    public var onUnservicedApi: ((_ apiName: String, _ advertised: Bool) -> Void)?
    /** Called once the program and entry function have run. */
    public var onReady: (() -> Void)?
    /** Hide Flutter's default loading spinner / error box. */
    public var showDefaultStates: Bool
    public var surface: SurfaceOptions?
    /** A runtime already created (MiniAppHost.mount); the session then neither creates nor disposes it. */
    public var runtimeClient: VmRuntimeClient?

    public init(
        machineId: String,
        runtime: RuntimeKind = .elpian,
        code: String? = nil,
        astJson: String? = nil,
        bytecodeBase64: String? = nil,
        stylesheet: Any? = nil,
        entryFunction: String? = nil,
        entryInput: String? = nil,
        hostHandlers: [String: HostCallHandler]? = nil,
        hostEnvironment: JSONObject? = nil,
        onPrintln: ((_ message: String) -> Void)? = nil,
        onUpdateApp: ((_ data: JSONObject) -> Void)? = nil,
        onError: ((_ message: String) -> Void)? = nil,
        onAuthorize: ((_ apiName: String) -> Bool)? = nil,
        onCallRefused: ((_ apiName: String) -> Void)? = nil,
        onUnservicedApi: ((_ apiName: String, _ advertised: Bool) -> Void)? = nil,
        onReady: (() -> Void)? = nil,
        showDefaultStates: Bool = true,
        surface: SurfaceOptions? = nil,
        runtimeClient: VmRuntimeClient? = nil
    ) {
        self.machineId = machineId
        self.runtime = runtime
        self.code = code
        self.astJson = astJson
        self.bytecodeBase64 = bytecodeBase64
        self.stylesheet = stylesheet
        self.entryFunction = entryFunction
        self.entryInput = entryInput
        self.hostHandlers = hostHandlers
        self.hostEnvironment = hostEnvironment
        self.onPrintln = onPrintln
        self.onUpdateApp = onUpdateApp
        self.onError = onError
        self.onAuthorize = onAuthorize
        self.onCallRefused = onCallRefused
        self.onUnservicedApi = onUnservicedApi
        self.onReady = onReady
        self.showDefaultStates = showDefaultStates
        self.surface = surface
        self.runtimeClient = runtimeClient
    }
}

public final class MiniAppSession {
    public let options: MiniAppOptions
    public let surface: ElpianSurface
    private var runtimeVm: VmRuntimeClient?
    private var timers: VmTimerHostApi?
    private var currentView: JSONObject?
    private var envData = JSONObject()
    private var envDigest: String?
    private var disposed = false
    private var loading = true
    private var errorMessage: String?

    /** Guest calls (events, timers, env sync) run here; cancelled on dispose. */
    public let scope = TaskScope()

    public init(_ surfaceId: String, _ options: MiniAppOptions) {
        self.options = options
        surface = ElpianSurface(surfaceId, options.surface ?? SurfaceOptions())
        if let sheet = flattenOptional(options.stylesheet), (sheet as? String) != "" { engine.loadStylesheet(sheet) }
        showState()
    }

    public var engine: ElpianEngine { surface.engine }

    public var runtime: VmRuntimeClient? { runtimeVm }

    public var error: String? { errorMessage }

    public var isLoading: Bool { loading }

    public var view: JSONObject? { currentView }

    /** Create the runtime, wire the host APIs, run the program and the entry function. */
    @MainActor
    public func start() async {
        let o = options
        let kind = o.runtime
        do {
            let vm: VmRuntimeClient
            if let given = o.runtimeClient {
                // Provided by the host: already created and governed.
                vm = given
            } else if kind == .elpian {
                try await initializeRuntime(kind)
                var created: VmRuntimeClient?
                if let b = o.bytecodeBase64, !b.isEmpty {
                    created = try await ElpianVm.fromBytecode(o.machineId, base64: b)
                } else if let c = o.code {
                    created = try await ElpianVm.fromCode(o.machineId, c)
                } else if let a = o.astJson {
                    created = try await ElpianVm.fromAst(o.machineId, a)
                }
                guard let c = created else {
                    let detail = ElpianVm.lastApiError
                    return fail(!detail.isEmpty ? "Failed to create VM: \(detail)" : "Failed to create VM")
                }
                vm = c
            } else if kind == .quickjs {
                try await initializeRuntime(kind)
                guard let code = o.code else { return fail("QuickJS runtime requires `code` (JavaScript source).") }
                vm = try await QuickJsVm.fromCode(o.machineId, code)
            } else {
                guard let code = o.code else { return fail("WASM runtime requires `code` (WASM config JSON).") }
                vm = try await WasmVm.fromCode(o.machineId, code)
            }
            if disposed {
                if o.runtimeClient == nil { await vm.dispose() }
                return
            }
            runtimeVm = vm

            // Every UI event goes to the guest function named in node.events.
            engine.services.events.onGlobalEvent { [weak self] event in
                guard let self = self else { return }
                self.scope.launch { [weak self] in await self?.routeEventToVm(event) }
            }

            let handler = HostHandler(
                services: engine.services,
                options: HostHandlerOptions(
                    onRender: { [weak self] view, scopeKey in self?.applyRender(view, scopeKey) },
                    onUpdateApp: { [weak self] data in
                        guard let self = self else { return }
                        o.onUpdateApp?(data)
                        if o.entryFunction != nil { self.scope.launch { [weak self] in await self?.callEntryFunction() } }
                    },
                    onPrintln: o.onPrintln ?? { m in platform().log(.info, "[\(o.machineId)] \(m)") },
                    onGetEnvironment: { [weak self] in self?.envData ?? JSONObject() },
                    onUnservicedApi: o.onUnservicedApi,
                    onAuthorize: o.onAuthorize,
                    onCallRefused: o.onCallRefused,
                    log: { m in platform().log(.debug, m) }
                )
            )

            timers?.dispose()
            let t = VmTimerHostApi({ [weak self, weak vm] fn, input in
                guard let self = self, let vm = vm, !self.disposed else { return }
                if let input = input { _ = try await vm.callFunctionWithInput(fn, input) } else { _ = try await vm.callFunction(fn) }
            }, onError: { m in platform().log(.warn, "ElpianMiniApp: \(m)") })
            timers = t

            var handlers: [String: HostCallHandler] = [:]
            for api in HostApiCatalog.allHostApiNames { handlers[api] = { name, payload in handler.handleHostCallReply(name, payload) } }
            // The agent APIs answer asynchronously (also when a catalog does not list them).
            for api in AGENT_API_NAMES { handlers[api] = { name, payload in handler.handleHostCallReply(name, payload) } }
            for api in HostApiCatalog.timerApiNames { handlers[api] = { name, payload in HostReply.of(t.handle(name, payload)) } }
            if let extra = o.hostHandlers { for (k, v) in extra { handlers[k] = v } }
            vm.registerHostHandlers(handlers)
            await syncHostEnvironment(true)

            _ = try await vm.run()
            if o.entryFunction != nil { await callEntryFunction() }
            loading = false
            showState()
            o.onReady?()
        } catch is CancellationError {
            return
        } catch {
            fail(errorText(error))
        }
    }

    private func fail(_ message: String) {
        errorMessage = message
        loading = false
        options.onError?(message)
        showState()
    }

    private func showState() {
        if disposed { return }
        let defaults = options.showDefaultStates
        if let err = errorMessage {
            surface.setOverlay(defaults ? messageBox("VM Error: \(err)", 0xfff44336) : nil)
            return
        }
        if loading && currentView == nil {
            surface.setOverlay(defaults ? loadingIndicator() : nil)
            return
        }
        surface.setContent(currentView)
    }

    private func applyRender(_ view: JSONObject, _ scopeKey: String?) {
        // Bounded scope patch: a scoped render whose key is missing is dropped.
        guard let next = ScopePatch.applyBounded(currentView, view, scopeKey) else {
            platform().log(.debug, "ElpianMiniApp: scoped render targeted missing scope \"\(scopeKey ?? "null")\"; keeping current view.")
            return
        }
        currentView = next
        if errorMessage == nil { surface.setContent(next) }
        scope.launch { [weak self] in await self?.syncHostEnvironment(false) }
    }

    @MainActor
    private func routeEventToVm(_ event: ElpianEvent) async {
        guard let vm = runtimeVm, !disposed else { return }
        guard let nodeId = event.currentTarget, !nodeId.isEmpty else { return }
        guard let handler = engine.services.events.getNode(nodeId)?.events?[event.type] as? String, !handler.isEmpty else { return }
        // Typed JSON input so every runtime decodes event arguments the same way.
        let payload = JSON.stringify(Typed.toTypedVmValue(event.toJson()))
        do {
            _ = try await vm.callFunctionWithInput(handler, payload)
        } catch is CancellationError {
            return
        } catch {
            do {
                _ = try await vm.callFunction(handler)
            } catch is CancellationError {
                return
            } catch let fallback {
                platform().log(.warn, "ElpianMiniApp: Error calling event handler \"\(handler)\": \(jsErrorString(error)); fallback failed: \(jsErrorString(fallback))")
            }
        }
    }

    @MainActor
    private func callEntryFunction() async {
        guard let vm = runtimeVm, let fn = options.entryFunction, !fn.isEmpty else { return }
        do {
            if let input = options.entryInput { _ = try await vm.callFunctionWithInput(fn, input) } else { _ = try await vm.callFunction(fn) }
        } catch is CancellationError {
            return
        } catch {
            platform().log(.warn, "ElpianMiniApp: Error calling \(fn): \(jsErrorString(error))")
        }
    }

    /** Call a guest function (ElpianVmController.callFunction). */
    @MainActor
    public func callFunction(_ funcName: String, _ input: String? = nil) async throws -> String {
        guard let vm = runtimeVm else { return "" }
        if let input = input { return try await vm.callFunctionWithInput(funcName, input) }
        return try await vm.callFunction(funcName)
    }

    /** The platform reports a viewport / safe-area / theme change. */
    public func viewportChanged() {
        surface.viewportChanged()
        scope.launch { [weak self] in await self?.syncHostEnvironment(true) }
    }

    @MainActor
    private func syncHostEnvironment(_ force: Bool) async {
        let next = buildHostEnvironment()
        let digest = JSON.stringify(next)
        let changed = digest != envDigest
        if changed {
            envDigest = digest
            envData = next
        }
        guard let vm = runtimeVm, changed || force else { return }
        do {
            try await vm.setGlobalHostData(envData)
        } catch is CancellationError {
            return
        } catch {
            platform().log(.warn, "ElpianMiniApp: failed to sync host env: \(jsErrorString(error))")
        }
    }

    private func buildHostEnvironment() -> JSONObject {
        let vp = platform().viewport(surface.id)
        let href = vp.href ?? ""
        var page = JSONObject([
            ("href", href), ("scheme", ""), ("host", ""), ("port", nil), ("path", ""), ("query", ""),
            ("queryParameters", JSONObject()), ("fragment", ""),
        ])
        if let g = HREF.exec(href) {
            let query = g[5] ?? ""
            let params = JSONObject()
            for part in jsSplit(query, "&") {
                if part.isEmpty { continue }
                let i = jsIndexOf(part, "=")
                let k = decodeURIComponentSafe(i < 0 ? part : jsSubstring(part, 0, i))
                params[k] = decodeURIComponentSafe(i < 0 ? "" : jsSubstring(part, i + 1))
            }
            page = JSONObject([
                ("href", href),
                ("scheme", g[1] ?? ""),
                ("host", g[2] ?? ""),
                ("port", g[3].flatMap { Double($0) }),
                ("path", g[4] ?? ""),
                ("query", query),
                ("queryParameters", params),
                ("fragment", g[6] ?? ""),
            ])
        }
        let out = JSONObject([
            ("machineId", options.machineId),
            ("runtime", runtimeName(options.runtime)),
            ("viewport", JSONObject([
                ("width", vp.width),
                ("height", vp.height),
                ("devicePixelRatio", vp.devicePixelRatio),
                ("orientation", vp.width >= vp.height ? "landscape" : "portrait"),
            ])),
            ("screen", JSONObject([("physicalWidth", vp.width * vp.devicePixelRatio), ("physicalHeight", vp.height * vp.devicePixelRatio)])),
            ("safeArea", JSONObject([("top", vp.safeArea.top), ("right", vp.safeArea.right), ("bottom", vp.safeArea.bottom), ("left", vp.safeArea.left)])),
            ("page", page),
            ("platform", JSONObject([("isWeb", vp.isWeb), ("defaultTargetPlatform", vp.platform), ("locale", vp.locale)])),
        ])
        out.assign(options.hostEnvironment)
        return out
    }

    @MainActor
    public func dispose() async {
        if disposed { return }
        disposed = true
        timers?.dispose()
        timers = nil
        let vm = runtimeVm
        runtimeVm = nil
        surface.dispose()
        scope.cancel()
        if options.runtimeClient == nil { await vm?.dispose() }
    }
}

private let HREF = JSRegex(#"^([a-zA-Z][\w+.-]*):(?://([^/?#:]*)(?::(\d+))?)?([^?#]*)(?:\?([^#]*))?(?:#(.*))?$"#)

/** `ElpianRuntime.name` in Dart. */
public func runtimeName(_ kind: RuntimeKind) -> String { kind == .quickjs ? "quickJs" : kind.wireName }

/** `decodeURIComponent(s.replace(/\+/g, ' '))`, the input itself when malformed. */
private func decodeURIComponentSafe(_ s: String) -> String {
    s.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? s
}
