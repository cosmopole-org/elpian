package dev.elpian.core.superapp

import dev.elpian.core.engine.ElpianServices
import dev.elpian.core.host.HostHandler
import dev.elpian.core.host.HostHandlerOptions
import dev.elpian.core.host.RenderHostCallback
import dev.elpian.core.session.MiniAppOptions
import dev.elpian.core.session.MiniAppSession
import dev.elpian.core.session.SurfaceOptions
import dev.elpian.core.util.JsonMap
import dev.elpian.core.util.asMap
import dev.elpian.core.util.isMap
import dev.elpian.core.util.jsString
import dev.elpian.core.vm.CAPABILITIES
import dev.elpian.core.vm.ElpianCapability
import dev.elpian.core.vm.ElpianLimits
import dev.elpian.core.vm.ElpianUsage
import dev.elpian.core.vm.ElpianVm
import dev.elpian.core.vm.HostCallHandler
import dev.elpian.core.vm.Limits
import dev.elpian.core.vm.QuickJsVm
import dev.elpian.core.vm.RuntimeKind
import dev.elpian.core.vm.VmGovernor
import dev.elpian.core.vm.VmRuntimeClient
import dev.elpian.core.vm.WasmVm
import dev.elpian.core.vm.capabilityFor
import dev.elpian.core.vm.capabilityFromWireName
import dev.elpian.core.vm.pressureAgainst

/**
 * Hosting third-party mini apps — ports of flutter/lib/src/superapp/
 * {mini_app,mini_app_host}.dart (superapp/superapp.ts): manifests, grants,
 * the resolved policy, the host-call gate, nested mini apps and metering.
 * `MiniAppHost.mount` adds what the Flutter host does by embedding a widget:
 * rendering the app on a native surface with the policy enforced on every
 * host call.
 */
data class MiniAppManifest(
    val id: String,
    val name: String,
    val version: String = "0.0.0",
    val entrypoint: String = "main",
    val runtime: RuntimeKind = RuntimeKind.ELPIAN,
    val requestedCapabilities: Set<ElpianCapability> = emptySet(),
    val requestedLimits: ElpianLimits? = null,
    val allowsChildren: Boolean = false,
    val metadata: JsonMap = LinkedHashMap(),
)

object MiniAppManifests {
    fun create(
        id: String,
        name: String,
        version: String = "0.0.0",
        entrypoint: String = "main",
        runtime: RuntimeKind = RuntimeKind.ELPIAN,
        requestedCapabilities: Set<ElpianCapability> = emptySet(),
        requestedLimits: ElpianLimits? = null,
        allowsChildren: Boolean = false,
        metadata: JsonMap = LinkedHashMap(),
    ): MiniAppManifest = MiniAppManifest(id, name, version, entrypoint, runtime, requestedCapabilities, requestedLimits, allowsChildren, metadata)

    fun fromJson(json: Map<String, Any?>): MiniAppManifest {
        val caps = LinkedHashSet<ElpianCapability>()
        // Unknown capability names are dropped: that can only narrow the request.
        val raws = json["requestedCapabilities"] as? List<*> ?: emptyList<Any?>()
        for (raw in raws) {
            val c = capabilityFromWireName(jsString(raw))
            if (c != null) caps.add(c)
        }
        val r = json["runtime"]
        val runtime = if (r == "quickJs" || r == "quickjs") RuntimeKind.QUICKJS else if (r == "wasm") RuntimeKind.WASM else RuntimeKind.ELPIAN
        val id = json["id"]
        val name = json["name"]
        val version = json["version"]
        val entrypoint = json["entrypoint"]
        return MiniAppManifest(
            id = if (id is String) id else "",
            name = if (name is String) name else if (id is String) id else "Untitled",
            version = if (version is String) version else "0.0.0",
            entrypoint = if (entrypoint is String) entrypoint else "main",
            runtime = runtime,
            requestedCapabilities = caps,
            requestedLimits = if (isMap(json["requestedLimits"])) Limits.fromJson(json["requestedLimits"].asMap()!!) else null,
            allowsChildren = json["allowsChildren"] == true,
            metadata = if (isMap(json["metadata"])) json["metadata"].asMap()!! else LinkedHashMap(),
        )
    }

    fun toJson(m: MiniAppManifest): JsonMap {
        val out: JsonMap = linkedMapOf(
            "id" to m.id,
            "name" to m.name,
            "version" to m.version,
            "entrypoint" to m.entrypoint,
            "runtime" to (if (m.runtime == RuntimeKind.QUICKJS) "quickJs" else m.runtime.wireName),
            "requestedCapabilities" to m.requestedCapabilities.map { it.wireName },
        )
        m.requestedLimits?.let { out["requestedLimits"] = Limits.toJson(it) }
        out["allowsChildren"] = m.allowsChildren
        if (m.metadata.isNotEmpty()) out["metadata"] = m.metadata
        return out
    }

    fun validate(m: MiniAppManifest): String? {
        if (m.id.isEmpty()) return "a mini app must declare an id"
        // `::` namespaces resources; allowing it would let one app forge another's.
        if (m.id.contains("::")) return "a mini app id may not contain \"::\""
        if (m.entrypoint.isEmpty()) return "a mini app must declare an entrypoint"
        return null
    }
}

data class MiniAppGrant(
    val capabilities: Set<ElpianCapability>,
    val limits: ElpianLimits,
    val mayHostChildren: Boolean,
    val allowedApis: Set<String>?,
)

object MiniAppGrants {
    /** Render-only: no network, storage, clock, randomness or nested apps. */
    val untrusted: MiniAppGrant
        get() = MiniAppGrant(
            linkedSetOf(ElpianCapability.RENDER, ElpianCapability.DOM, ElpianCapability.CANVAS, ElpianCapability.SURFACE, ElpianCapability.LOGGING),
            Limits.sandboxed,
            mayHostChildren = false,
            allowedApis = null,
        )

    val trusted: MiniAppGrant
        get() = MiniAppGrant(LinkedHashSet(CAPABILITIES), Limits.unlimited, mayHostChildren = true, allowedApis = null)
}

class MiniAppPolicy private constructor(
    val manifest: MiniAppManifest,
    val grant: MiniAppGrant,
    val capabilities: Set<ElpianCapability>,
    val limits: ElpianLimits,
    val mayHostChildren: Boolean,
    val deniedRequests: Set<ElpianCapability>,
) {
    fun allowsApi(apiName: String, capability: ElpianCapability): Boolean {
        if (capability !in capabilities) return false
        return grant.allowedApis == null || apiName in grant.allowedApis
    }

    companion object {
        fun resolve(manifest: MiniAppManifest, grant: MiniAppGrant): MiniAppPolicy {
            val requested = if (manifest.requestedCapabilities.isEmpty()) grant.capabilities else manifest.requestedCapabilities
            val allowed = requested.filterTo(LinkedHashSet()) { it in grant.capabilities }
            val denied = requested.filterTo(LinkedHashSet()) { it !in grant.capabilities }
            return MiniAppPolicy(
                manifest,
                grant,
                allowed,
                tightest(manifest.requestedLimits, grant.limits),
                manifest.allowsChildren && grant.mayHostChildren && ElpianCapability.VM_MANAGE in allowed,
                denied,
            )
        }

        fun tightest(a: ElpianLimits?, b: ElpianLimits): ElpianLimits = if (a == null) b else Limits.tightest(a, b)
    }
}

class MiniAppException(val appId: String, val reason: String) : Exception("MiniAppException($appId): $reason")

/** [MiniAppOptions] without what the host decides (machine id, runtime, sources, the runtime client, authorization). */
class MountOptions(
    val stylesheet: Any? = null,
    val entryFunction: String? = null,
    val entryInput: String? = null,
    val hostHandlers: Map<String, HostCallHandler>? = null,
    val hostEnvironment: Map<String, Any?>? = null,
    val onPrintln: ((message: String) -> Unit)? = null,
    val onUpdateApp: ((data: JsonMap) -> Unit)? = null,
    val onError: ((message: String) -> Unit)? = null,
    val onCallRefused: ((apiName: String) -> Unit)? = null,
    val onUnservicedApi: ((apiName: String, advertised: Boolean) -> Unit)? = null,
    val onReady: (() -> Unit)? = null,
    val showDefaultStates: Boolean = true,
    val surface: SurfaceOptions? = null,
)

class MiniAppHost private constructor(
    val policy: MiniAppPolicy,
    val runtime: VmRuntimeClient,
    val parent: MiniAppHost?,
) {
    val machineId: String = runtime.machineId
    val engineServices: ElpianServices = ElpianServices(machineId)
    private val kids = ArrayList<MiniAppHost>()
    private var disposed = false
    private var sessions = ArrayList<MiniAppSession>()

    val id: String get() = policy.manifest.id

    val governor: VmGovernor get() = runtime.governor

    val children: List<MiniAppHost> get() = kids.toList()

    val isDisposed: Boolean get() = disposed

    companion object {
        suspend fun launch(
            manifest: MiniAppManifest,
            grant: MiniAppGrant,
            source: String,
            parent: MiniAppHost? = null,
            machineIdOverride: String? = null,
        ): MiniAppHost {
            val invalid = MiniAppManifests.validate(manifest)
            if (invalid != null) throw MiniAppException(manifest.id, invalid)
            val policy = MiniAppPolicy.resolve(manifest, grant)
            val machineId = machineIdOverride ?: (if (parent == null) manifest.id else "${parent.machineId}.${manifest.id}")
            val runtime = startRuntime(manifest, source, machineId)
            val host = MiniAppHost(policy, runtime, parent)
            // Adopt first: the child's effective capabilities are clipped to its
            // ancestors, so the grants applied next can only narrow further.
            if (parent != null) ElpianVm.treeGovernor.adopt(parent.machineId, machineId)
            host.governor.sandbox(policy.capabilities)
            host.governor.setLimits(policy.limits)
            return host
        }
    }

    /** A HostHandler whose every call passes this app's policy first. */
    fun createHostHandler(
        onRender: RenderHostCallback? = null,
        onUpdateApp: ((d: JsonMap) -> Unit)? = null,
        onPrintln: ((m: String) -> Unit)? = null,
        onGetEnvironment: (() -> JsonMap)? = null,
        onCallRefused: ((api: String) -> Unit)? = null,
    ): HostHandler = HostHandler(
        engineServices,
        HostHandlerOptions(
            onRender = onRender,
            onUpdateApp = onUpdateApp,
            onPrintln = onPrintln,
            onGetEnvironment = onGetEnvironment,
            onCallRefused = onCallRefused,
            onAuthorize = { api -> authorizes(api) },
        ),
    )

    fun authorizes(apiName: String): Boolean {
        val capability = capabilityFromWireName(capabilityFor(apiName)) ?: ElpianCapability.OTHER
        return policy.allowsApi(apiName, capability)
    }

    /**
     * Render this mini app on the platform surface [surfaceId]: runs the
     * program and its manifest entrypoint, with this app's policy gating every
     * host call.
     */
    suspend fun mount(surfaceId: String, options: MountOptions = MountOptions()): MiniAppSession {
        if (disposed) throw MiniAppException(id, "cannot mount a disposed app")
        val session = MiniAppSession(
            surfaceId,
            MiniAppOptions(
                machineId = machineId,
                runtime = policy.manifest.runtime,
                stylesheet = options.stylesheet,
                entryFunction = options.entryFunction ?: policy.manifest.entrypoint,
                entryInput = options.entryInput,
                hostHandlers = options.hostHandlers,
                hostEnvironment = options.hostEnvironment,
                onPrintln = options.onPrintln,
                onUpdateApp = options.onUpdateApp,
                onError = options.onError,
                onAuthorize = { api -> authorizes(api) },
                onCallRefused = options.onCallRefused,
                onUnservicedApi = options.onUnservicedApi,
                onReady = options.onReady,
                showDefaultStates = options.showDefaultStates,
                surface = (options.surface ?: SurfaceOptions()).copy(services = engineServices),
                runtimeClient = runtime,
            ),
        )
        sessions.add(session)
        session.start()
        return session
    }

    suspend fun spawnChild(manifest: MiniAppManifest, source: String, grant: MiniAppGrant? = null): MiniAppHost {
        if (disposed) throw MiniAppException(id, "cannot spawn a child from a disposed app")
        if (!policy.mayHostChildren) {
            throw MiniAppException(
                id,
                "this mini app is not permitted to host children — it needs `allowsChildren` in its manifest, `mayHostChildren` in its grant, and the vm_manage capability",
            )
        }
        val child = launch(manifest = manifest, grant = narrow(grant), source = source, parent = this)
        kids.add(child)
        return child
    }

    private fun narrow(requested: MiniAppGrant?): MiniAppGrant {
        val p = policy
        val base = requested ?: MiniAppGrant(p.capabilities, p.limits, p.mayHostChildren, p.grant.allowedApis)
        return MiniAppGrant(
            capabilities = base.capabilities.filterTo(LinkedHashSet()) { it in p.capabilities },
            limits = MiniAppPolicy.tightest(base.limits, p.limits),
            mayHostChildren = base.mayHostChildren && p.mayHostChildren,
            allowedApis = intersectApis(base.allowedApis, p.grant.allowedApis),
        )
    }

    suspend fun usage(): ElpianUsage = governor.usage()

    suspend fun branchUsage(): ElpianUsage = governor.subtreeUsage()

    suspend fun pressure(): Map<String, Double> = pressureAgainst(branchUsage(), policy.limits)

    suspend fun dispose() {
        if (disposed) return
        disposed = true
        for (child in kids.toList()) child.dispose()
        kids.clear()
        for (s in sessions) s.dispose()
        sessions = ArrayList()
        try {
            runtime.dispose()
        } finally {
            engineServices.dispose()
        }
    }
}

private suspend fun startRuntime(manifest: MiniAppManifest, source: String, machineId: String): VmRuntimeClient = when (manifest.runtime) {
    RuntimeKind.ELPIAN -> {
        ElpianVm.initialize()
        ElpianVm.fromCode(machineId, source)
            ?: throw MiniAppException(manifest.id, "the Elpian runtime could not start it: ${ElpianVm.lastApiError}")
    }
    RuntimeKind.QUICKJS -> QuickJsVm.fromCode(machineId, source)
    RuntimeKind.WASM -> WasmVm.fromCode(machineId, source)
}

private fun intersectApis(a: Set<String>?, b: Set<String>?): Set<String>? {
    if (a == null) return b
    if (b == null) return a
    return a.filterTo(LinkedHashSet()) { it in b }
}
