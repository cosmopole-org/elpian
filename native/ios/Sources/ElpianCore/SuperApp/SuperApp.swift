import Foundation

/**
 * Hosting third-party mini apps — ports of flutter/lib/src/superapp/
 * {mini_app,mini_app_host}.dart (superapp/superapp.ts): manifests, grants,
 * the resolved policy, the host-call gate, nested mini apps and metering.
 * `MiniAppHost.mount` adds what the Flutter host does by embedding a widget:
 * rendering the app on a native surface with the policy enforced on every
 * host call.
 */
public struct MiniAppManifest {
    public var id: String
    public var name: String
    public var version: String
    public var entrypoint: String
    public var runtime: RuntimeKind
    public var requestedCapabilities: [ElpianCapability]
    public var requestedLimits: ElpianLimits?
    public var allowsChildren: Bool
    public var metadata: JSONObject

    public init(id: String, name: String, version: String = "0.0.0", entrypoint: String = "main", runtime: RuntimeKind = .elpian,
                requestedCapabilities: [ElpianCapability] = [], requestedLimits: ElpianLimits? = nil, allowsChildren: Bool = false,
                metadata: JSONObject = JSONObject()) {
        self.id = id
        self.name = name
        self.version = version
        self.entrypoint = entrypoint
        self.runtime = runtime
        // A set in insertion order.
        var caps: [ElpianCapability] = []
        for c in requestedCapabilities where !caps.contains(c) { caps.append(c) }
        self.requestedCapabilities = caps
        self.requestedLimits = requestedLimits
        self.allowsChildren = allowsChildren
        self.metadata = metadata
    }
}

public enum MiniAppManifests {
    public static func create(id: String, name: String, version: String = "0.0.0", entrypoint: String = "main", runtime: RuntimeKind = .elpian,
                              requestedCapabilities: [ElpianCapability] = [], requestedLimits: ElpianLimits? = nil,
                              allowsChildren: Bool = false, metadata: JSONObject = JSONObject()) -> MiniAppManifest {
        MiniAppManifest(id: id, name: name, version: version, entrypoint: entrypoint, runtime: runtime, requestedCapabilities: requestedCapabilities,
                        requestedLimits: requestedLimits, allowsChildren: allowsChildren, metadata: metadata)
    }

    public static func fromJson(_ json: JSONObject) -> MiniAppManifest {
        var caps: [ElpianCapability] = []
        // Unknown capability names are dropped: that can only narrow the request.
        for raw in asArray(json["requestedCapabilities"]) ?? [] {
            if let c = capabilityFromWireName(jsString(raw)), !caps.contains(c) { caps.append(c) }
        }
        let r = json["runtime"] as? String
        let runtime: RuntimeKind = (r == "quickJs" || r == "quickjs") ? .quickjs : (r == "wasm" ? .wasm : .elpian)
        let id = json["id"] as? String
        let name = json["name"] as? String
        return MiniAppManifest(
            id: id ?? "",
            name: name ?? id ?? "Untitled",
            version: (json["version"] as? String) ?? "0.0.0",
            entrypoint: (json["entrypoint"] as? String) ?? "main",
            runtime: runtime,
            requestedCapabilities: caps,
            requestedLimits: asMap(json["requestedLimits"]).map { Limits.fromJson($0) },
            allowsChildren: jsBool(json["allowsChildren"]) == true,
            metadata: asMap(json["metadata"]) ?? JSONObject()
        )
    }

    public static func toJson(_ m: MiniAppManifest) -> JSONObject {
        let out = JSONObject([
            ("id", m.id),
            ("name", m.name),
            ("version", m.version),
            ("entrypoint", m.entrypoint),
            ("runtime", m.runtime == .quickjs ? "quickJs" : m.runtime.wireName),
            ("requestedCapabilities", m.requestedCapabilities.map { $0.wireName as Any? }),
        ])
        if let l = m.requestedLimits { out["requestedLimits"] = Limits.toJson(l) }
        out["allowsChildren"] = m.allowsChildren
        if !m.metadata.isEmpty { out["metadata"] = m.metadata }
        return out
    }

    public static func validate(_ m: MiniAppManifest) -> String? {
        if m.id.isEmpty { return "a mini app must declare an id" }
        // `::` namespaces resources; allowing it would let one app forge another's.
        if m.id.contains("::") { return "a mini app id may not contain \"::\"" }
        if m.entrypoint.isEmpty { return "a mini app must declare an entrypoint" }
        return nil
    }
}

public struct MiniAppGrant {
    /** A set in insertion order. */
    public var capabilities: [ElpianCapability]
    public var limits: ElpianLimits
    public var mayHostChildren: Bool
    /** nil = every API its capabilities cover. */
    public var allowedApis: Set<String>?

    public init(capabilities: [ElpianCapability], limits: ElpianLimits, mayHostChildren: Bool, allowedApis: Set<String>?) {
        var caps: [ElpianCapability] = []
        for c in capabilities where !caps.contains(c) { caps.append(c) }
        self.capabilities = caps
        self.limits = limits
        self.mayHostChildren = mayHostChildren
        self.allowedApis = allowedApis
    }
}

public enum MiniAppGrants {
    /** Render-only: no network, storage, clock, randomness or nested apps. */
    public static var untrusted: MiniAppGrant {
        MiniAppGrant(capabilities: [.render, .dom, .canvas, .surface, .logging], limits: Limits.sandboxed, mayHostChildren: false, allowedApis: nil)
    }

    public static var trusted: MiniAppGrant {
        MiniAppGrant(capabilities: CAPABILITIES, limits: Limits.unlimited, mayHostChildren: true, allowedApis: nil)
    }
}

public final class MiniAppPolicy {
    public let manifest: MiniAppManifest
    public let grant: MiniAppGrant
    public let capabilities: [ElpianCapability]
    public let limits: ElpianLimits
    public let mayHostChildren: Bool
    public let deniedRequests: [ElpianCapability]

    private init(_ manifest: MiniAppManifest, _ grant: MiniAppGrant, _ capabilities: [ElpianCapability], _ limits: ElpianLimits,
                 _ mayHostChildren: Bool, _ deniedRequests: [ElpianCapability]) {
        self.manifest = manifest
        self.grant = grant
        self.capabilities = capabilities
        self.limits = limits
        self.mayHostChildren = mayHostChildren
        self.deniedRequests = deniedRequests
    }

    public func allowsApi(_ apiName: String, _ capability: ElpianCapability) -> Bool {
        if !capabilities.contains(capability) { return false }
        guard let allowed = grant.allowedApis else { return true }
        return allowed.contains(apiName)
    }

    public static func resolve(_ manifest: MiniAppManifest, _ grant: MiniAppGrant) -> MiniAppPolicy {
        let requested = manifest.requestedCapabilities.isEmpty ? grant.capabilities : manifest.requestedCapabilities
        let allowed = requested.filter { grant.capabilities.contains($0) }
        let denied = requested.filter { !grant.capabilities.contains($0) }
        return MiniAppPolicy(
            manifest,
            grant,
            allowed,
            tightest(manifest.requestedLimits, grant.limits),
            manifest.allowsChildren && grant.mayHostChildren && allowed.contains(.vmManage),
            denied
        )
    }

    public static func tightest(_ a: ElpianLimits?, _ b: ElpianLimits) -> ElpianLimits {
        guard let a = a else { return b }
        return Limits.tightest(a, b)
    }
}

public struct MiniAppException: MessageError, CustomStringConvertible {
    public let appId: String
    public let reason: String

    public init(_ appId: String, _ reason: String) {
        self.appId = appId
        self.reason = reason
    }

    public var message: String { "MiniAppException(\(appId)): \(reason)" }
    public var description: String { message }
}

/** [MiniAppOptions] without what the host decides (machine id, runtime, sources, the runtime client, authorization). */
public struct MountOptions {
    public var stylesheet: Any?
    public var entryFunction: String?
    public var entryInput: String?
    public var hostHandlers: [String: HostCallHandler]?
    public var hostEnvironment: JSONObject?
    public var onPrintln: ((_ message: String) -> Void)?
    public var onUpdateApp: ((_ data: JSONObject) -> Void)?
    public var onError: ((_ message: String) -> Void)?
    public var onCallRefused: ((_ apiName: String) -> Void)?
    public var onUnservicedApi: ((_ apiName: String, _ advertised: Bool) -> Void)?
    public var onReady: (() -> Void)?
    public var showDefaultStates: Bool
    public var surface: SurfaceOptions?

    public init(stylesheet: Any? = nil, entryFunction: String? = nil, entryInput: String? = nil, hostHandlers: [String: HostCallHandler]? = nil,
                hostEnvironment: JSONObject? = nil, onPrintln: ((_ message: String) -> Void)? = nil,
                onUpdateApp: ((_ data: JSONObject) -> Void)? = nil, onError: ((_ message: String) -> Void)? = nil,
                onCallRefused: ((_ apiName: String) -> Void)? = nil, onUnservicedApi: ((_ apiName: String, _ advertised: Bool) -> Void)? = nil,
                onReady: (() -> Void)? = nil, showDefaultStates: Bool = true, surface: SurfaceOptions? = nil) {
        self.stylesheet = stylesheet
        self.entryFunction = entryFunction
        self.entryInput = entryInput
        self.hostHandlers = hostHandlers
        self.hostEnvironment = hostEnvironment
        self.onPrintln = onPrintln
        self.onUpdateApp = onUpdateApp
        self.onError = onError
        self.onCallRefused = onCallRefused
        self.onUnservicedApi = onUnservicedApi
        self.onReady = onReady
        self.showDefaultStates = showDefaultStates
        self.surface = surface
    }
}

public final class MiniAppHost {
    public let policy: MiniAppPolicy
    public let runtime: VmRuntimeClient
    public private(set) weak var parent: MiniAppHost?
    public let machineId: String
    public let engineServices: ElpianServices
    private var kids: [MiniAppHost] = []
    private var disposed = false
    private var sessions: [MiniAppSession] = []

    private init(_ policy: MiniAppPolicy, _ runtime: VmRuntimeClient, _ parent: MiniAppHost?) {
        self.policy = policy
        self.runtime = runtime
        self.parent = parent
        machineId = runtime.machineId
        engineServices = ElpianServices(appId: machineId)
    }

    public var id: String { policy.manifest.id }

    public var governor: VmGovernor { runtime.governor }

    public var children: [MiniAppHost] { kids }

    public var isDisposed: Bool { disposed }

    @MainActor
    public static func launch(manifest: MiniAppManifest, grant: MiniAppGrant, source: String, parent: MiniAppHost? = nil,
                              machineIdOverride: String? = nil) async throws -> MiniAppHost {
        if let invalid = MiniAppManifests.validate(manifest) { throw MiniAppException(manifest.id, invalid) }
        let policy = MiniAppPolicy.resolve(manifest, grant)
        let machineId = machineIdOverride ?? (parent == nil ? manifest.id : "\(parent!.machineId).\(manifest.id)")
        let runtime = try await startRuntime(manifest, source, machineId)
        let host = MiniAppHost(policy, runtime, parent)
        // Adopt first: the child's effective capabilities are clipped to its
        // ancestors, so the grants applied next can only narrow further.
        if let p = parent { try await ElpianVm.treeGovernor.adopt(p.machineId, machineId) }
        try await host.governor.sandbox(policy.capabilities)
        try await host.governor.setLimits(policy.limits)
        return host
    }

    /** A HostHandler whose every call passes this app's policy first. */
    public func createHostHandler(onRender: RenderHostCallback? = nil, onUpdateApp: ((_ d: JSONObject) -> Void)? = nil,
                                  onPrintln: ((_ m: String) -> Void)? = nil, onGetEnvironment: (() -> JSONObject)? = nil,
                                  onCallRefused: ((_ api: String) -> Void)? = nil) -> HostHandler {
        HostHandler(
            services: engineServices,
            options: HostHandlerOptions(
                onRender: onRender,
                onUpdateApp: onUpdateApp,
                onPrintln: onPrintln,
                onGetEnvironment: onGetEnvironment,
                onAuthorize: { [weak self] api in self?.authorizes(api) ?? false },
                onCallRefused: onCallRefused
            )
        )
    }

    public func authorizes(_ apiName: String) -> Bool {
        let capability = capabilityFromWireName(HostApiCatalog.capabilityFor(apiName)) ?? .other
        return policy.allowsApi(apiName, capability)
    }

    /**
     * Render this mini app on the platform surface [surfaceId]: runs the
     * program and its manifest entrypoint, with this app's policy gating every
     * host call.
     */
    @MainActor
    public func mount(_ surfaceId: String, _ options: MountOptions = MountOptions()) async throws -> MiniAppSession {
        if disposed { throw MiniAppException(id, "cannot mount a disposed app") }
        var surface = options.surface ?? SurfaceOptions()
        surface.services = engineServices
        let session = MiniAppSession(
            surfaceId,
            MiniAppOptions(
                machineId: machineId,
                runtime: policy.manifest.runtime,
                stylesheet: options.stylesheet,
                entryFunction: options.entryFunction ?? policy.manifest.entrypoint,
                entryInput: options.entryInput,
                hostHandlers: options.hostHandlers,
                hostEnvironment: options.hostEnvironment,
                onPrintln: options.onPrintln,
                onUpdateApp: options.onUpdateApp,
                onError: options.onError,
                onAuthorize: { [weak self] api in self?.authorizes(api) ?? false },
                onCallRefused: options.onCallRefused,
                onUnservicedApi: options.onUnservicedApi,
                onReady: options.onReady,
                showDefaultStates: options.showDefaultStates,
                surface: surface,
                runtimeClient: runtime
            )
        )
        sessions.append(session)
        await session.start()
        return session
    }

    @MainActor
    public func spawnChild(manifest: MiniAppManifest, source: String, grant: MiniAppGrant? = nil) async throws -> MiniAppHost {
        if disposed { throw MiniAppException(id, "cannot spawn a child from a disposed app") }
        if !policy.mayHostChildren {
            throw MiniAppException(
                id,
                "this mini app is not permitted to host children — it needs `allowsChildren` in its manifest, `mayHostChildren` in its grant, and the vm_manage capability"
            )
        }
        let child = try await MiniAppHost.launch(manifest: manifest, grant: narrow(grant), source: source, parent: self)
        kids.append(child)
        return child
    }

    private func narrow(_ requested: MiniAppGrant?) -> MiniAppGrant {
        let p = policy
        let base = requested ?? MiniAppGrant(capabilities: p.capabilities, limits: p.limits, mayHostChildren: p.mayHostChildren, allowedApis: p.grant.allowedApis)
        return MiniAppGrant(
            capabilities: base.capabilities.filter { p.capabilities.contains($0) },
            limits: MiniAppPolicy.tightest(base.limits, p.limits),
            mayHostChildren: base.mayHostChildren && p.mayHostChildren,
            allowedApis: intersectApis(base.allowedApis, p.grant.allowedApis)
        )
    }

    public func usage() async throws -> ElpianUsage { try await governor.usage() }

    public func branchUsage() async throws -> ElpianUsage { try await governor.subtreeUsage() }

    public func pressure() async throws -> JSONObject { pressureAgainst(try await branchUsage(), policy.limits) }

    @MainActor
    public func dispose() async {
        if disposed { return }
        disposed = true
        for child in kids { await child.dispose() }
        kids.removeAll()
        for s in sessions { await s.dispose() }
        sessions = []
        await runtime.dispose()
        engineServices.dispose()
    }
}

@MainActor
private func startRuntime(_ manifest: MiniAppManifest, _ source: String, _ machineId: String) async throws -> VmRuntimeClient {
    switch manifest.runtime {
    case .elpian:
        try await ElpianVm.initialize()
        guard let vm = try await ElpianVm.fromCode(machineId, source) else {
            throw MiniAppException(manifest.id, "the Elpian runtime could not start it: \(ElpianVm.lastApiError)")
        }
        return vm
    case .quickjs:
        return try await QuickJsVm.fromCode(machineId, source)
    case .wasm:
        return try await WasmVm.fromCode(machineId, source)
    }
}

private func intersectApis(_ a: Set<String>?, _ b: Set<String>?) -> Set<String>? {
    guard let a = a else { return b }
    guard let b = b else { return a }
    return a.intersection(b)
}
