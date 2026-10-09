package dev.elpian.core.vm

import dev.elpian.core.platform.Platforms
import dev.elpian.core.platform.platform
import dev.elpian.core.util.Json
import dev.elpian.core.util.JsonMap
import dev.elpian.core.util.isMap
import dev.elpian.core.util.jsString
import kotlin.math.min
import kotlin.math.truncate

/**
 * Governance — ports of flutter/lib/src/vm/governance/{models,governor,
 * host_side_governor,elpian_governor}.dart (vm/governance.ts). The wire format
 * is the JSON documented on rust/src/api/govern.rs.
 */
class ElpianGovernanceException(
    val reason: String,
    val call: String? = null,
) : RuntimeException(
    if (call == null) "ElpianGovernanceException: $reason" else "ElpianGovernanceException: $call failed: $reason",
)

fun decodeGovernanceReply(raw: String, call: String? = null): JsonMap {
    val parsed: Any? = try {
        Json.parse(raw)
    } catch (e: Exception) {
        throw ElpianGovernanceException("malformed reply: $e", call)
    }
    if (!isMap(parsed)) throw ElpianGovernanceException("expected an object, got $raw", call)
    @Suppress("UNCHECKED_CAST")
    val map = parsed as JsonMap
    val error = map["error"]
    if (error is String) throw ElpianGovernanceException(error, call)
    return map
}

// ---------------------------------------------------------------------------
// Limits / usage
// ---------------------------------------------------------------------------

/** Resource limits; null = unbounded on that axis. Numbers are JS numbers (Double). */
data class ElpianLimits(
    val maxInstructions: Double? = null,
    val maxInstructionsPerTurn: Double? = null,
    val maxMemoryBytes: Double? = null,
    val maxStorageBytes: Double? = null,
    val maxCallDepth: Double? = null,
)

object Limits {
    val unlimited: ElpianLimits = ElpianLimits()

    /** `ResourceLimits::sandboxed()`. */
    val sandboxed: ElpianLimits = ElpianLimits(
        maxInstructions = 50_000_000.0,
        maxInstructionsPerTurn = 5_000_000.0,
        maxMemoryBytes = 64.0 * 1024 * 1024,
        maxStorageBytes = 16.0 * 1024 * 1024,
        maxCallDepth = 1024.0,
    )

    fun toJson(l: ElpianLimits): JsonMap = linkedMapOf(
        "maxInstructions" to l.maxInstructions,
        "maxInstructionsPerTurn" to l.maxInstructionsPerTurn,
        "maxMemoryBytes" to l.maxMemoryBytes,
        "maxStorageBytes" to l.maxStorageBytes,
        "maxCallDepth" to l.maxCallDepth,
    )

    fun fromJson(j: Map<String, Any?>): ElpianLimits {
        fun n(v: Any?): Double? = (v as? Number)?.toDouble()
        return ElpianLimits(
            maxInstructions = n(j["maxInstructions"]),
            maxInstructionsPerTurn = n(j["maxInstructionsPerTurn"]),
            maxMemoryBytes = n(j["maxMemoryBytes"]),
            maxStorageBytes = n(j["maxStorageBytes"]),
            maxCallDepth = n(j["maxCallDepth"]),
        )
    }

    /** The tighter of each axis (null = unbounded). */
    fun tightest(a: ElpianLimits, b: ElpianLimits): ElpianLimits {
        fun t(x: Double?, y: Double?): Double? = if (x == null) y else if (y == null) x else min(x, y)
        return ElpianLimits(
            maxInstructions = t(a.maxInstructions, b.maxInstructions),
            maxInstructionsPerTurn = t(a.maxInstructionsPerTurn, b.maxInstructionsPerTurn),
            maxMemoryBytes = t(a.maxMemoryBytes, b.maxMemoryBytes),
            maxStorageBytes = t(a.maxStorageBytes, b.maxStorageBytes),
            maxCallDepth = t(a.maxCallDepth, b.maxCallDepth),
        )
    }
}

/** Resource usage counters (integral values held as JS numbers). */
data class ElpianUsage(
    val instructions: Double,
    val instructionsThisTurn: Double,
    val memoryBytes: Double,
    val peakMemoryBytes: Double,
    val storageBytes: Double,
    val callDepth: Double,
    val peakCallDepth: Double,
) {
    fun toJson(): JsonMap = linkedMapOf(
        "instructions" to instructions,
        "instructionsThisTurn" to instructionsThisTurn,
        "memoryBytes" to memoryBytes,
        "peakMemoryBytes" to peakMemoryBytes,
        "storageBytes" to storageBytes,
        "callDepth" to callDepth,
        "peakCallDepth" to peakCallDepth,
    )
}

val ZERO_USAGE: ElpianUsage = ElpianUsage(
    instructions = 0.0,
    instructionsThisTurn = 0.0,
    memoryBytes = 0.0,
    peakMemoryBytes = 0.0,
    storageBytes = 0.0,
    callDepth = 0.0,
    peakCallDepth = 0.0,
)

fun usageFromJson(j: Map<String, Any?>): ElpianUsage {
    fun n(v: Any?): Double = (v as? Number)?.toDouble()?.let { truncate(it) } ?: 0.0
    return ElpianUsage(
        instructions = n(j["instructions"]),
        instructionsThisTurn = n(j["instructionsThisTurn"]),
        memoryBytes = n(j["memoryBytes"]),
        peakMemoryBytes = n(j["peakMemoryBytes"]),
        storageBytes = n(j["storageBytes"]),
        callDepth = n(j["callDepth"]),
        peakCallDepth = n(j["peakCallDepth"]),
    )
}

/** How much of [limits] [usage] consumed per axis (0..1); unbounded axes absent. */
fun pressureAgainst(usage: ElpianUsage, limits: ElpianLimits): Map<String, Double> {
    val out = LinkedHashMap<String, Double>()
    fun add(axis: String, used: Double, max: Double?) {
        if (max != null && max > 0) out[axis] = used / max
    }
    add("instructions", usage.instructions, limits.maxInstructions)
    add("instructionsPerTurn", usage.instructionsThisTurn, limits.maxInstructionsPerTurn)
    add("memory", usage.memoryBytes, limits.maxMemoryBytes)
    add("storage", usage.storageBytes, limits.maxStorageBytes)
    add("callDepth", usage.callDepth, limits.maxCallDepth)
    return out
}

// ---------------------------------------------------------------------------
// Capabilities / lifecycle / tree
// ---------------------------------------------------------------------------

/** The capabilities, by their wire names (`Capability::as_str`), in the TS `CAPABILITIES` order. */
enum class ElpianCapability(val wireName: String) {
    LOGGING("logging"),
    GPU("gpu"),
    MODULE_IMPORT("module_import"),
    NETWORK("network"),
    STORAGE("storage"),
    CLOCK("clock"),
    RANDOMNESS("randomness"),
    VM_MANAGE("vm_manage"),
    DOM("dom"),
    CANVAS("canvas"),
    RENDER("render"),
    TIMERS("timers"),
    ENVIRONMENT("environment"),
    TASKS("tasks"),
    HOST_MESSAGING("host_messaging"),
    SURFACE("surface"),
    SERVER_CALL("server_call"),
    STATE("state"),
    AGENTS("agents"),
    OTHER("other");

    override fun toString(): String = wireName

    companion object {
        private val byWire = entries.associateBy { it.wireName }

        fun fromWireName(name: String): ElpianCapability? = byWire[name]
    }
}

/** Wire names of `Capability::as_str`. */
val CAPABILITIES: List<ElpianCapability> = ElpianCapability.entries.toList()

fun capabilityFromWireName(name: String): ElpianCapability? = ElpianCapability.fromWireName(name)

class ElpianCapabilities(allowed: Map<ElpianCapability, Boolean>) {
    private val allowed: Map<ElpianCapability, Boolean> = LinkedHashMap(allowed)

    /** Unknown reads as denied — an unrecognised gate must never be a pass. */
    fun allows(c: ElpianCapability): Boolean = allowed[c] ?: false

    val granted: List<ElpianCapability> get() = allowed.filter { it.value }.keys.toList()

    val denied: List<ElpianCapability> get() = allowed.filter { !it.value }.keys.toList()

    fun toJson(): MutableMap<String, Boolean> = LinkedHashMap<String, Boolean>().also { m ->
        for ((k, v) in allowed) m[k.wireName] = v
    }

    companion object {
        fun fromJson(json: Map<String, Any?>): ElpianCapabilities {
            val map = LinkedHashMap<ElpianCapability, Boolean>()
            for ((k, v) in json) {
                val cap = capabilityFromWireName(k)
                if (cap != null && v is Boolean) map[cap] = v
            }
            return ElpianCapabilities(map)
        }
    }
}

enum class ElpianRunState(val wireName: String) {
    RUNNING("running"),
    PAUSE_REQUESTED("pause_requested"),
    PAUSED("paused"),
    TERMINATE_REQUESTED("terminate_requested"),
    TERMINATED("terminated");

    override fun toString(): String = wireName

    companion object {
        fun fromWireName(name: Any?): ElpianRunState? = entries.firstOrNull { it.wireName == name }
    }
}

data class ElpianVmState(
    val state: ElpianRunState,
    val trapReason: String?,
    val processing: Boolean,
) {
    fun toJson(): JsonMap = linkedMapOf("state" to state.wireName, "trapReason" to trapReason, "processing" to processing)
}

fun vmStateFromJson(j: Map<String, Any?>): ElpianVmState {
    val s = ElpianRunState.fromWireName(j["state"]) ?: ElpianRunState.TERMINATED
    val tr = j["trapReason"]
    val r = if (tr is String && tr.isNotEmpty()) tr else null
    return ElpianVmState(state = s, trapReason = r, processing = j["processing"] == true)
}

fun isDead(s: ElpianVmState): Boolean = s.state == ElpianRunState.TERMINATED || s.state == ElpianRunState.TERMINATE_REQUESTED

fun isTrapped(s: ElpianVmState): Boolean = !s.trapReason.isNullOrEmpty()

data class ElpianVmTree(
    val parent: String?,
    val children: List<String>,
    val subtree: List<String>,
) {
    fun toJson(): JsonMap = linkedMapOf("parent" to parent, "children" to children, "subtree" to subtree)
}

private fun stringList(v: Any?): List<String> = if (v is List<*>) v.map { jsString(it) } else emptyList()

@Suppress("UNCHECKED_CAST")
private fun mapOrEmpty(v: Any?): Map<String, Any?> = if (isMap(v)) v as Map<String, Any?> else emptyMap()

fun treeFromJson(j: Map<String, Any?>): ElpianVmTree {
    val p = j["parent"]
    return ElpianVmTree(parent = p as? String, children = stringList(j["children"]), subtree = stringList(j["subtree"]))
}

data class ElpianBudgetViolation(
    val machineId: String,
    val axis: String,
    val destroyed: List<String>,
)

data class ElpianVmSnapshot(
    val machineId: String,
    val state: ElpianVmState,
    val limits: ElpianLimits,
    val usage: ElpianUsage,
    val subtreeUsage: ElpianUsage,
    val localCapabilities: ElpianCapabilities,
    val effectiveCapabilities: ElpianCapabilities,
    val tree: ElpianVmTree,
)

fun snapshotFromJson(j: Map<String, Any?>): ElpianVmSnapshot = ElpianVmSnapshot(
    machineId = jsString(j["machineId"] ?: ""),
    state = vmStateFromJson(mapOrEmpty(j["state"])),
    limits = Limits.fromJson(mapOrEmpty(j["limits"])),
    usage = usageFromJson(mapOrEmpty(j["usage"])),
    subtreeUsage = usageFromJson(mapOrEmpty(j["subtreeUsage"])),
    localCapabilities = ElpianCapabilities.fromJson(mapOrEmpty(j["localCapabilities"])),
    effectiveCapabilities = ElpianCapabilities.fromJson(mapOrEmpty(j["effectiveCapabilities"])),
    tree = treeFromJson(mapOrEmpty(j["tree"])),
)

// ---------------------------------------------------------------------------
// Governor interfaces
// ---------------------------------------------------------------------------

data class GovernanceSupport(
    val capabilities: Boolean,
    val instructionBudget: Boolean,
    val memoryBudget: Boolean,
    val storageBudget: Boolean,
    val lifecycle: Boolean,
    val hierarchy: Boolean,
)

val FULL_SUPPORT: GovernanceSupport = GovernanceSupport(capabilities = true, instructionBudget = true, memoryBudget = true, storageBudget = true, lifecycle = true, hierarchy = true)
val NO_SUPPORT: GovernanceSupport = GovernanceSupport(capabilities = false, instructionBudget = false, memoryBudget = false, storageBudget = false, lifecycle = false, hierarchy = false)

fun canSandboxUntrustedCode(s: GovernanceSupport): Boolean = s.capabilities && s.instructionBudget

interface VmGovernor {
    val governanceSupport: GovernanceSupport
    suspend fun setLimits(limits: ElpianLimits)
    suspend fun getLimits(): ElpianLimits
    suspend fun usage(): ElpianUsage
    suspend fun subtreeUsage(): ElpianUsage
    suspend fun setCapability(capability: ElpianCapability, allowed: Boolean)
    suspend fun sandbox(granted: Iterable<ElpianCapability>)
    suspend fun localCapabilities(): ElpianCapabilities
    suspend fun effectiveCapabilities(): ElpianCapabilities
    suspend fun allowsApi(apiName: String): Boolean
    suspend fun state(): ElpianVmState
    suspend fun pause()
    suspend fun resumeExecution()
    suspend fun terminate()
}

interface VmTreeGovernor {
    suspend fun adopt(parentId: String, childId: String)
    suspend fun tree(machineId: String): ElpianVmTree
    suspend fun pauseTree(machineId: String): List<String>
    suspend fun terminateTree(machineId: String): List<String>
    suspend fun destroyTree(machineId: String): List<String>
    suspend fun enforceTreeBudgets(): List<ElpianBudgetViolation>
    suspend fun snapshot(machineId: String): ElpianVmSnapshot
}

// ---------------------------------------------------------------------------
// HostSideGovernor — QuickJS / WASM
// ---------------------------------------------------------------------------

/** Lifecycle hooks a [HostSideGovernor] fires into its runtime. */
data class GovernorHooks(
    val onTerminate: (() -> Unit)? = null,
    val onPause: (() -> Unit)? = null,
    val onResume: (() -> Unit)? = null,
)

/**
 * Governance enforced at the host-call seam, for the backends that give the
 * host no other one (QuickJS, WASM).
 */
class HostSideGovernor(
    val machineId: String,
    private val enforcesInstructions: Boolean,
    private val hooks: GovernorHooks = GovernorHooks(),
) : VmGovernor {
    private var limits: ElpianLimits = Limits.unlimited
    private var currentUsage: ElpianUsage = ZERO_USAGE.copy()
    private var runState: ElpianRunState = ElpianRunState.RUNNING
    private var reason: String? = null
    private val caps = LinkedHashMap<ElpianCapability, Boolean>()
    private var defaultAllow = true

    override val governanceSupport: GovernanceSupport
        get() = GovernanceSupport(capabilities = true, instructionBudget = enforcesInstructions, memoryBudget = false, storageBudget = false, lifecycle = true, hierarchy = false)

    val trapReason: String? get() = reason

    /** Gate and meter one host call; returns the refusal reason or null. */
    fun checkAndCharge(apiName: String, bytes: Int = 0): String? {
        if (runState != ElpianRunState.RUNNING) return "instance is ${runState.wireName}"
        val capability = capabilityFromWireName(capabilityFor(apiName)) ?: ElpianCapability.OTHER
        if (!allows(capability)) return "capability ${capability.wireName} is denied"
        val next = currentUsage.instructions + 1
        val max = limits.maxInstructions
        if (max != null && next > max) {
            trap("host-call limit exceeded (${Json.formatNumber(max)})")
            return reason
        }
        val nextBytes = currentUsage.storageBytes + bytes
        val maxBytes = limits.maxStorageBytes
        if (maxBytes != null && nextBytes > maxBytes) {
            trap("host-byte limit exceeded (${Json.formatNumber(maxBytes)})")
            return reason
        }
        currentUsage = currentUsage.copy(instructions = next, instructionsThisTurn = currentUsage.instructionsThisTurn + 1, storageBytes = nextBytes)
        return null
    }

    fun chargeInstructions(steps: Double) {
        currentUsage = currentUsage.copy(
            instructions = currentUsage.instructions + steps,
            instructionsThisTurn = currentUsage.instructionsThisTurn + steps,
        )
        val max = limits.maxInstructions
        if (max != null && currentUsage.instructions > max) trap("instruction limit exceeded (${Json.formatNumber(max)})")
    }

    fun beginTurn() {
        currentUsage = currentUsage.copy(instructionsThisTurn = 0.0)
    }

    private fun trap(reason: String) {
        if (this.reason == null) this.reason = reason
        runState = ElpianRunState.TERMINATED
        hooks.onTerminate?.invoke()
    }

    private fun allows(c: ElpianCapability): Boolean = caps[c] ?: defaultAllow

    override suspend fun setLimits(limits: ElpianLimits) {
        this.limits = limits.copy()
    }

    override suspend fun getLimits(): ElpianLimits = limits.copy()

    override suspend fun usage(): ElpianUsage = currentUsage.copy()

    override suspend fun subtreeUsage(): ElpianUsage = currentUsage.copy()

    override suspend fun setCapability(capability: ElpianCapability, allowed: Boolean) {
        caps[capability] = allowed
    }

    override suspend fun sandbox(granted: Iterable<ElpianCapability>) {
        caps.clear()
        defaultAllow = false
        for (c in granted) caps[c] = true
    }

    override suspend fun localCapabilities(): ElpianCapabilities {
        val out = LinkedHashMap<ElpianCapability, Boolean>()
        for (c in CAPABILITIES) out[c] = allows(c)
        return ElpianCapabilities(out)
    }

    override suspend fun effectiveCapabilities(): ElpianCapabilities = localCapabilities()

    override suspend fun allowsApi(apiName: String): Boolean =
        allows(capabilityFromWireName(capabilityFor(apiName)) ?: ElpianCapability.OTHER)

    override suspend fun state(): ElpianVmState = ElpianVmState(state = runState, trapReason = reason, processing = false)

    override suspend fun pause() {
        if (runState == ElpianRunState.RUNNING) {
            runState = ElpianRunState.PAUSED
            hooks.onPause?.invoke()
        }
    }

    override suspend fun resumeExecution() {
        if (runState == ElpianRunState.PAUSED) {
            runState = ElpianRunState.RUNNING
            hooks.onResume?.invoke()
        }
    }

    override suspend fun terminate() {
        runState = ElpianRunState.TERMINATED
        hooks.onTerminate?.invoke()
    }
}

/** A governor that refuses to pretend: every tightening call throws. */
class UnenforcedGovernor(val reason: String) : VmGovernor {
    override val governanceSupport: GovernanceSupport = NO_SUPPORT

    private fun unavailable(call: String): Nothing = throw ElpianGovernanceException(reason, call)

    override suspend fun setLimits(limits: ElpianLimits) {
        unavailable("setLimits")
    }

    override suspend fun getLimits(): ElpianLimits = Limits.unlimited

    override suspend fun usage(): ElpianUsage = ZERO_USAGE.copy()

    override suspend fun subtreeUsage(): ElpianUsage = ZERO_USAGE.copy()

    override suspend fun setCapability(capability: ElpianCapability, allowed: Boolean) {
        unavailable("setCapability")
    }

    override suspend fun sandbox(granted: Iterable<ElpianCapability>) {
        unavailable("sandbox")
    }

    override suspend fun localCapabilities(): ElpianCapabilities = ElpianCapabilities(emptyMap())

    override suspend fun effectiveCapabilities(): ElpianCapabilities = ElpianCapabilities(emptyMap())

    override suspend fun allowsApi(apiName: String): Boolean = false

    override suspend fun state(): ElpianVmState = ElpianVmState(state = ElpianRunState.TERMINATED, trapReason = null, processing = false)

    override suspend fun pause() {}

    override suspend fun resumeExecution() {}

    override suspend fun terminate() {}
}

// ---------------------------------------------------------------------------
// Elpian VM governance (runtime-enforced)
// ---------------------------------------------------------------------------

private fun binding(): ElpianVmBinding? = if (Platforms.isInstalled) platform().elpianVm else null

private suspend fun govCall(symbol: String, args: List<Any>): String {
    val b = binding()
    if (b == null || !b.isAvailable()) {
        val le = b?.lastError()
        throw ElpianGovernanceException("the Elpian runtime is not available${if (!le.isNullOrEmpty()) ": $le" else ""}", symbol)
    }
    return b.governance(symbol, args)
        ?: throw ElpianGovernanceException("the loaded runtime does not export $symbol — rebuild it", symbol)
}

private suspend fun govObj(symbol: String, args: List<Any>): JsonMap = decodeGovernanceReply(govCall(symbol, args), symbol)

private suspend fun govList(symbol: String, args: List<Any>): List<Any?> {
    val raw = govCall(symbol, args)
    val decoded: Any? = try {
        Json.parse(raw)
    } catch (e: Exception) {
        throw ElpianGovernanceException("malformed reply: $e", symbol)
    }
    if (decoded is List<*>) return decoded.toList()
    if (decoded is Map<*, *>) {
        val error = decoded["error"]
        if (error is String) throw ElpianGovernanceException(error, symbol)
    }
    throw ElpianGovernanceException("expected an array, got $raw", symbol)
}

@Volatile
private var governanceProbe: Boolean? = null

/** Whether the loaded runtime carries the governance surface (probed once). */
suspend fun elpianGovernanceAvailable(): Boolean {
    governanceProbe?.let { return it }
    val b = binding()
    if (b == null || !b.isAvailable()) return false
    val probe = try {
        b.governance("elpian_usage", listOf("__elpian_probe__")) != null
    } catch (_: Exception) {
        false
    }
    governanceProbe = probe
    return probe
}

class ElpianVmGovernor(val machineId: String) : VmGovernor {
    override val governanceSupport: GovernanceSupport
        get() {
            val b = binding()
            return if (b != null && b.isAvailable() && governanceProbe != false) FULL_SUPPORT else NO_SUPPORT
        }

    override suspend fun setLimits(limits: ElpianLimits) {
        govObj("elpian_set_limits", listOf(machineId, Json.stringify(Limits.toJson(limits))))
    }

    override suspend fun getLimits(): ElpianLimits = Limits.fromJson(govObj("elpian_limits", listOf(machineId)))

    override suspend fun usage(): ElpianUsage = usageFromJson(govObj("elpian_usage", listOf(machineId)))

    override suspend fun subtreeUsage(): ElpianUsage = usageFromJson(govObj("elpian_subtree_usage", listOf(machineId)))

    suspend fun chargeStorage(deltaBytes: Long) {
        govObj("elpian_charge_storage", listOf(machineId, deltaBytes))
    }

    override suspend fun setCapability(capability: ElpianCapability, allowed: Boolean) {
        govObj("elpian_set_capability", listOf(machineId, capability.wireName, if (allowed) 1L else 0L))
    }

    suspend fun setCapabilities(changes: Map<ElpianCapability, Boolean>) {
        val wire = LinkedHashMap<String, Any?>()
        for ((k, v) in changes) wire[k.wireName] = v
        govObj("elpian_set_capabilities", listOf(machineId, Json.stringify(wire)))
    }

    override suspend fun sandbox(granted: Iterable<ElpianCapability>) {
        govObj("elpian_sandbox_capabilities", listOf(machineId, Json.stringify(granted.map { it.wireName })))
    }

    override suspend fun localCapabilities(): ElpianCapabilities =
        ElpianCapabilities.fromJson(govObj("elpian_local_capabilities", listOf(machineId)))

    override suspend fun effectiveCapabilities(): ElpianCapabilities =
        ElpianCapabilities.fromJson(govObj("elpian_effective_capabilities", listOf(machineId)))

    override suspend fun allowsApi(apiName: String): Boolean =
        govObj("elpian_capability_allows", listOf(machineId, apiName))["allowed"] == true

    override suspend fun state(): ElpianVmState = vmStateFromJson(govObj("elpian_state", listOf(machineId)))

    override suspend fun pause() {
        govObj("elpian_pause", listOf(machineId))
    }

    override suspend fun resumeExecution() {
        govObj("elpian_resume", listOf(machineId))
    }

    override suspend fun terminate() {
        govObj("elpian_terminate", listOf(machineId))
    }
}

class ElpianTreeGovernor : VmTreeGovernor {
    val isAvailable: Boolean
        get() {
            val b = binding()
            return b != null && b.isAvailable()
        }

    override suspend fun adopt(parentId: String, childId: String) {
        govObj("elpian_adopt", listOf(parentId, childId))
    }

    override suspend fun tree(machineId: String): ElpianVmTree = treeFromJson(govObj("elpian_tree", listOf(machineId)))

    private fun affected(reply: Map<String, Any?>): List<String> = stringList(reply["affected"])

    override suspend fun pauseTree(machineId: String): List<String> = affected(govObj("elpian_pause_tree", listOf(machineId)))

    override suspend fun terminateTree(machineId: String): List<String> = affected(govObj("elpian_terminate_tree", listOf(machineId)))

    override suspend fun destroyTree(machineId: String): List<String> = affected(govObj("elpian_destroy_tree", listOf(machineId)))

    override suspend fun enforceTreeBudgets(): List<ElpianBudgetViolation> =
        govList("elpian_enforce_tree_budgets", emptyList())
            .filter { isMap(it) }
            .map {
                val j = mapOrEmpty(it)
                ElpianBudgetViolation(
                    machineId = jsString(j["machineId"] ?: ""),
                    axis = jsString(j["axis"] ?: "unknown"),
                    destroyed = stringList(j["destroyed"]),
                )
            }

    override suspend fun snapshot(machineId: String): ElpianVmSnapshot = snapshotFromJson(govObj("elpian_snapshot", listOf(machineId)))
}
