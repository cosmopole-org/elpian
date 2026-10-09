import Foundation

/**
 * Governance — ports of flutter/lib/src/vm/governance/{models,governor,
 * host_side_governor,elpian_governor}.dart (vm/governance.ts). The wire format
 * is the JSON documented on rust/src/api/govern.rs.
 */
public struct ElpianGovernanceException: Error, CustomStringConvertible {
    public let reason: String
    public let call: String?

    public init(_ reason: String, call: String? = nil) {
        self.reason = reason
        self.call = call
    }

    public var description: String {
        if let call = call { return "ElpianGovernanceException: \(call) failed: \(reason)" }
        return "ElpianGovernanceException: \(reason)"
    }
}

public func decodeGovernanceReply(_ raw: String, call: String? = nil) throws -> JSONObject {
    let parsed: Any?
    do {
        parsed = try JSON.parse(raw)
    } catch {
        throw ElpianGovernanceException("malformed reply: \(error)", call: call)
    }
    guard let map = asMap(parsed) else { throw ElpianGovernanceException("expected an object, got \(raw)", call: call) }
    if let error = map["error"] as? String { throw ElpianGovernanceException(error, call: call) }
    return map
}

// ---------------------------------------------------------------------------
// Limits / usage
// ---------------------------------------------------------------------------

/** Resource limits; nil = unbounded on that axis. Numbers are JS numbers (Double). */
public struct ElpianLimits: Equatable {
    public var maxInstructions: Double?
    public var maxInstructionsPerTurn: Double?
    public var maxMemoryBytes: Double?
    public var maxStorageBytes: Double?
    public var maxCallDepth: Double?

    public init(maxInstructions: Double? = nil, maxInstructionsPerTurn: Double? = nil, maxMemoryBytes: Double? = nil,
                maxStorageBytes: Double? = nil, maxCallDepth: Double? = nil) {
        self.maxInstructions = maxInstructions
        self.maxInstructionsPerTurn = maxInstructionsPerTurn
        self.maxMemoryBytes = maxMemoryBytes
        self.maxStorageBytes = maxStorageBytes
        self.maxCallDepth = maxCallDepth
    }
}

public enum Limits {
    public static let unlimited = ElpianLimits()

    /** `ResourceLimits::sandboxed()`. */
    public static let sandboxed = ElpianLimits(
        maxInstructions: 50_000_000,
        maxInstructionsPerTurn: 5_000_000,
        maxMemoryBytes: 64 * 1024 * 1024,
        maxStorageBytes: 16 * 1024 * 1024,
        maxCallDepth: 1024
    )

    public static func toJson(_ l: ElpianLimits) -> JSONObject {
        JSONObject([
            ("maxInstructions", l.maxInstructions),
            ("maxInstructionsPerTurn", l.maxInstructionsPerTurn),
            ("maxMemoryBytes", l.maxMemoryBytes),
            ("maxStorageBytes", l.maxStorageBytes),
            ("maxCallDepth", l.maxCallDepth),
        ])
    }

    public static func fromJson(_ j: JSONObject) -> ElpianLimits {
        ElpianLimits(
            maxInstructions: jsNumber(j["maxInstructions"]),
            maxInstructionsPerTurn: jsNumber(j["maxInstructionsPerTurn"]),
            maxMemoryBytes: jsNumber(j["maxMemoryBytes"]),
            maxStorageBytes: jsNumber(j["maxStorageBytes"]),
            maxCallDepth: jsNumber(j["maxCallDepth"])
        )
    }

    /** The tighter of each axis (nil = unbounded). */
    public static func tightest(_ a: ElpianLimits, _ b: ElpianLimits) -> ElpianLimits {
        func t(_ x: Double?, _ y: Double?) -> Double? {
            guard let x = x else { return y }
            guard let y = y else { return x }
            return min(x, y)
        }
        return ElpianLimits(
            maxInstructions: t(a.maxInstructions, b.maxInstructions),
            maxInstructionsPerTurn: t(a.maxInstructionsPerTurn, b.maxInstructionsPerTurn),
            maxMemoryBytes: t(a.maxMemoryBytes, b.maxMemoryBytes),
            maxStorageBytes: t(a.maxStorageBytes, b.maxStorageBytes),
            maxCallDepth: t(a.maxCallDepth, b.maxCallDepth)
        )
    }
}

/** Resource usage counters (integral values held as JS numbers). */
public struct ElpianUsage: Equatable {
    public var instructions: Double
    public var instructionsThisTurn: Double
    public var memoryBytes: Double
    public var peakMemoryBytes: Double
    public var storageBytes: Double
    public var callDepth: Double
    public var peakCallDepth: Double

    public init(instructions: Double, instructionsThisTurn: Double, memoryBytes: Double, peakMemoryBytes: Double,
                storageBytes: Double, callDepth: Double, peakCallDepth: Double) {
        self.instructions = instructions
        self.instructionsThisTurn = instructionsThisTurn
        self.memoryBytes = memoryBytes
        self.peakMemoryBytes = peakMemoryBytes
        self.storageBytes = storageBytes
        self.callDepth = callDepth
        self.peakCallDepth = peakCallDepth
    }

    public func toJson() -> JSONObject {
        JSONObject([
            ("instructions", instructions),
            ("instructionsThisTurn", instructionsThisTurn),
            ("memoryBytes", memoryBytes),
            ("peakMemoryBytes", peakMemoryBytes),
            ("storageBytes", storageBytes),
            ("callDepth", callDepth),
            ("peakCallDepth", peakCallDepth),
        ])
    }
}

public let ZERO_USAGE = ElpianUsage(instructions: 0, instructionsThisTurn: 0, memoryBytes: 0, peakMemoryBytes: 0, storageBytes: 0,
                                    callDepth: 0, peakCallDepth: 0)

public func usageFromJson(_ j: JSONObject) -> ElpianUsage {
    func n(_ v: Any?) -> Double { jsNumber(v).map { jsTrunc($0) } ?? 0 }
    return ElpianUsage(
        instructions: n(j["instructions"]),
        instructionsThisTurn: n(j["instructionsThisTurn"]),
        memoryBytes: n(j["memoryBytes"]),
        peakMemoryBytes: n(j["peakMemoryBytes"]),
        storageBytes: n(j["storageBytes"]),
        callDepth: n(j["callDepth"]),
        peakCallDepth: n(j["peakCallDepth"])
    )
}

/** How much of [limits] [usage] consumed per axis (0..1); unbounded axes absent. Values are Doubles. */
public func pressureAgainst(_ usage: ElpianUsage, _ limits: ElpianLimits) -> JSONObject {
    let out = JSONObject()
    func add(_ axis: String, _ used: Double, _ max: Double?) {
        if let max = max, max > 0 { out[axis] = used / max }
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
public enum ElpianCapability: String, CaseIterable, CustomStringConvertible {
    case logging
    case gpu
    case moduleImport = "module_import"
    case network
    case storage
    case clock
    case randomness
    case vmManage = "vm_manage"
    case dom
    case canvas
    case render
    case timers
    case environment
    case tasks
    case hostMessaging = "host_messaging"
    case surface
    case serverCall = "server_call"
    case state
    case agents
    case other

    public var wireName: String { rawValue }
    public var description: String { rawValue }
}

/** Wire names of `Capability::as_str`. */
public let CAPABILITIES: [ElpianCapability] = ElpianCapability.allCases

public func capabilityFromWireName(_ name: String) -> ElpianCapability? { ElpianCapability(rawValue: name) }

public final class ElpianCapabilities: Equatable {
    /** Entries in insertion order. */
    private let entries: [(ElpianCapability, Bool)]

    public init(_ allowed: [(ElpianCapability, Bool)]) {
        var seen: [ElpianCapability: Int] = [:]
        var out: [(ElpianCapability, Bool)] = []
        for (k, v) in allowed {
            if let i = seen[k] { out[i].1 = v } else {
                seen[k] = out.count
                out.append((k, v))
            }
        }
        entries = out
    }

    public static func fromJson(_ json: JSONObject) -> ElpianCapabilities {
        var map: [(ElpianCapability, Bool)] = []
        for (k, v) in json {
            if let cap = capabilityFromWireName(k), let b = jsBool(v) { map.append((cap, b)) }
        }
        return ElpianCapabilities(map)
    }

    /** Unknown reads as denied — an unrecognised gate must never be a pass. */
    public func allows(_ c: ElpianCapability) -> Bool { entries.first { $0.0 == c }?.1 ?? false }

    public var granted: [ElpianCapability] { entries.filter { $0.1 }.map { $0.0 } }

    public var denied: [ElpianCapability] { entries.filter { !$0.1 }.map { $0.0 } }

    public func toJson() -> JSONObject {
        let m = JSONObject()
        for (k, v) in entries { m[k.wireName] = v }
        return m
    }

    public static func == (a: ElpianCapabilities, b: ElpianCapabilities) -> Bool {
        a.entries.count == b.entries.count && zip(a.entries, b.entries).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
    }
}

public enum ElpianRunState: String, CaseIterable, CustomStringConvertible {
    case running
    case pauseRequested = "pause_requested"
    case paused
    case terminateRequested = "terminate_requested"
    case terminated

    public var wireName: String { rawValue }
    public var description: String { rawValue }

    public static func fromWireName(_ name: Any?) -> ElpianRunState? {
        guard let s = flattenOptional(name) as? String else { return nil }
        return ElpianRunState(rawValue: s)
    }
}

public struct ElpianVmState: Equatable {
    public var state: ElpianRunState
    public var trapReason: String?
    public var processing: Bool

    public init(state: ElpianRunState, trapReason: String?, processing: Bool) {
        self.state = state
        self.trapReason = trapReason
        self.processing = processing
    }

    public func toJson() -> JSONObject {
        JSONObject([("state", state.wireName), ("trapReason", trapReason), ("processing", processing)])
    }
}

public func vmStateFromJson(_ j: JSONObject) -> ElpianVmState {
    let s = ElpianRunState.fromWireName(j["state"]) ?? .terminated
    var r: String?
    if let tr = j["trapReason"] as? String, !tr.isEmpty { r = tr }
    return ElpianVmState(state: s, trapReason: r, processing: jsBool(j["processing"]) == true)
}

public func isDead(_ s: ElpianVmState) -> Bool { s.state == .terminated || s.state == .terminateRequested }

public func isTrapped(_ s: ElpianVmState) -> Bool { !(s.trapReason ?? "").isEmpty }

public struct ElpianVmTree: Equatable {
    public var parent: String?
    public var children: [String]
    public var subtree: [String]

    public init(parent: String?, children: [String], subtree: [String]) {
        self.parent = parent
        self.children = children
        self.subtree = subtree
    }

    public func toJson() -> JSONObject {
        JSONObject([("parent", parent), ("children", children.map { $0 as Any? }), ("subtree", subtree.map { $0 as Any? })])
    }
}

private func stringList(_ v: Any?) -> [String] {
    guard let a = asArray(v) else { return [] }
    return a.map { jsString($0) }
}

private func mapOrEmpty(_ v: Any?) -> JSONObject { asMap(v) ?? JSONObject() }

public func treeFromJson(_ j: JSONObject) -> ElpianVmTree {
    ElpianVmTree(parent: j["parent"] as? String, children: stringList(j["children"]), subtree: stringList(j["subtree"]))
}

public struct ElpianBudgetViolation: Equatable {
    public var machineId: String
    public var axis: String
    public var destroyed: [String]

    public init(machineId: String, axis: String, destroyed: [String]) {
        self.machineId = machineId
        self.axis = axis
        self.destroyed = destroyed
    }
}

public struct ElpianVmSnapshot {
    public var machineId: String
    public var state: ElpianVmState
    public var limits: ElpianLimits
    public var usage: ElpianUsage
    public var subtreeUsage: ElpianUsage
    public var localCapabilities: ElpianCapabilities
    public var effectiveCapabilities: ElpianCapabilities
    public var tree: ElpianVmTree
}

public func snapshotFromJson(_ j: JSONObject) -> ElpianVmSnapshot {
    ElpianVmSnapshot(
        machineId: jsString(j["machineId"] ?? ""),
        state: vmStateFromJson(mapOrEmpty(j["state"])),
        limits: Limits.fromJson(mapOrEmpty(j["limits"])),
        usage: usageFromJson(mapOrEmpty(j["usage"])),
        subtreeUsage: usageFromJson(mapOrEmpty(j["subtreeUsage"])),
        localCapabilities: ElpianCapabilities.fromJson(mapOrEmpty(j["localCapabilities"])),
        effectiveCapabilities: ElpianCapabilities.fromJson(mapOrEmpty(j["effectiveCapabilities"])),
        tree: treeFromJson(mapOrEmpty(j["tree"]))
    )
}

// ---------------------------------------------------------------------------
// Governor interfaces
// ---------------------------------------------------------------------------

public struct GovernanceSupport: Equatable {
    public var capabilities: Bool
    public var instructionBudget: Bool
    public var memoryBudget: Bool
    public var storageBudget: Bool
    public var lifecycle: Bool
    public var hierarchy: Bool

    public init(capabilities: Bool, instructionBudget: Bool, memoryBudget: Bool, storageBudget: Bool, lifecycle: Bool, hierarchy: Bool) {
        self.capabilities = capabilities
        self.instructionBudget = instructionBudget
        self.memoryBudget = memoryBudget
        self.storageBudget = storageBudget
        self.lifecycle = lifecycle
        self.hierarchy = hierarchy
    }
}

public let FULL_SUPPORT = GovernanceSupport(capabilities: true, instructionBudget: true, memoryBudget: true, storageBudget: true, lifecycle: true, hierarchy: true)
public let NO_SUPPORT = GovernanceSupport(capabilities: false, instructionBudget: false, memoryBudget: false, storageBudget: false, lifecycle: false, hierarchy: false)

public func canSandboxUntrustedCode(_ s: GovernanceSupport) -> Bool { s.capabilities && s.instructionBudget }

public protocol VmGovernor: AnyObject {
    var governanceSupport: GovernanceSupport { get }
    func setLimits(_ limits: ElpianLimits) async throws
    func getLimits() async throws -> ElpianLimits
    func usage() async throws -> ElpianUsage
    func subtreeUsage() async throws -> ElpianUsage
    func setCapability(_ capability: ElpianCapability, _ allowed: Bool) async throws
    func sandbox(_ granted: [ElpianCapability]) async throws
    func localCapabilities() async throws -> ElpianCapabilities
    func effectiveCapabilities() async throws -> ElpianCapabilities
    func allowsApi(_ apiName: String) async throws -> Bool
    func state() async throws -> ElpianVmState
    func pause() async throws
    func resumeExecution() async throws
    func terminate() async throws
}

public protocol VmTreeGovernor: AnyObject {
    func adopt(_ parentId: String, _ childId: String) async throws
    func tree(_ machineId: String) async throws -> ElpianVmTree
    func pauseTree(_ machineId: String) async throws -> [String]
    func terminateTree(_ machineId: String) async throws -> [String]
    func destroyTree(_ machineId: String) async throws -> [String]
    func enforceTreeBudgets() async throws -> [ElpianBudgetViolation]
    func snapshot(_ machineId: String) async throws -> ElpianVmSnapshot
}

// ---------------------------------------------------------------------------
// HostSideGovernor — QuickJS / WASM
// ---------------------------------------------------------------------------

/** Lifecycle hooks a [HostSideGovernor] fires into its runtime. */
public struct GovernorHooks {
    public var onTerminate: (() -> Void)?
    public var onPause: (() -> Void)?
    public var onResume: (() -> Void)?

    public init(onTerminate: (() -> Void)? = nil, onPause: (() -> Void)? = nil, onResume: (() -> Void)? = nil) {
        self.onTerminate = onTerminate
        self.onPause = onPause
        self.onResume = onResume
    }
}

/**
 * Governance enforced at the host-call seam, for the backends that give the
 * host no other one (QuickJS, WASM).
 */
public final class HostSideGovernor: VmGovernor {
    public let machineId: String
    private let enforcesInstructions: Bool
    private let hooks: GovernorHooks
    private var limits = Limits.unlimited
    private var currentUsage = ZERO_USAGE
    private var runState = ElpianRunState.running
    private var reason: String?
    private var caps: [ElpianCapability: Bool] = [:]
    private var defaultAllow = true

    public init(_ machineId: String, enforcesInstructions: Bool, hooks: GovernorHooks = GovernorHooks()) {
        self.machineId = machineId
        self.enforcesInstructions = enforcesInstructions
        self.hooks = hooks
    }

    public var governanceSupport: GovernanceSupport {
        GovernanceSupport(capabilities: true, instructionBudget: enforcesInstructions, memoryBudget: false, storageBudget: false, lifecycle: true, hierarchy: false)
    }

    public var trapReason: String? { reason }

    /** Gate and meter one host call; returns the refusal reason or nil. */
    public func checkAndCharge(_ apiName: String, _ bytes: Int = 0) -> String? {
        if runState != .running { return "instance is \(runState.wireName)" }
        let capability = capabilityFromWireName(HostApiCatalog.capabilityFor(apiName)) ?? .other
        if !allows(capability) { return "capability \(capability.wireName) is denied" }
        let next = currentUsage.instructions + 1
        if let max = limits.maxInstructions, next > max {
            trap("host-call limit exceeded (\(JSON.formatNumber(max)))")
            return reason
        }
        let nextBytes = currentUsage.storageBytes + Double(bytes)
        if let maxBytes = limits.maxStorageBytes, nextBytes > maxBytes {
            trap("host-byte limit exceeded (\(JSON.formatNumber(maxBytes)))")
            return reason
        }
        currentUsage.instructions = next
        currentUsage.instructionsThisTurn += 1
        currentUsage.storageBytes = nextBytes
        return nil
    }

    public func chargeInstructions(_ steps: Double) {
        currentUsage.instructions += steps
        currentUsage.instructionsThisTurn += steps
        if let max = limits.maxInstructions, currentUsage.instructions > max {
            trap("instruction limit exceeded (\(JSON.formatNumber(max)))")
        }
    }

    public func beginTurn() {
        currentUsage.instructionsThisTurn = 0
    }

    private func trap(_ reason: String) {
        if self.reason == nil { self.reason = reason }
        runState = .terminated
        hooks.onTerminate?()
    }

    private func allows(_ c: ElpianCapability) -> Bool { caps[c] ?? defaultAllow }

    public func setLimits(_ limits: ElpianLimits) async throws {
        self.limits = limits
    }

    public func getLimits() async throws -> ElpianLimits { limits }

    public func usage() async throws -> ElpianUsage { currentUsage }

    public func subtreeUsage() async throws -> ElpianUsage { currentUsage }

    public func setCapability(_ capability: ElpianCapability, _ allowed: Bool) async throws {
        caps[capability] = allowed
    }

    public func sandbox(_ granted: [ElpianCapability]) async throws {
        caps.removeAll()
        defaultAllow = false
        for c in granted { caps[c] = true }
    }

    public func localCapabilities() async throws -> ElpianCapabilities {
        ElpianCapabilities(CAPABILITIES.map { ($0, allows($0)) })
    }

    public func effectiveCapabilities() async throws -> ElpianCapabilities { try await localCapabilities() }

    public func allowsApi(_ apiName: String) async throws -> Bool {
        allows(capabilityFromWireName(HostApiCatalog.capabilityFor(apiName)) ?? .other)
    }

    public func state() async throws -> ElpianVmState { ElpianVmState(state: runState, trapReason: reason, processing: false) }

    public func pause() async throws {
        if runState == .running {
            runState = .paused
            hooks.onPause?()
        }
    }

    public func resumeExecution() async throws {
        if runState == .paused {
            runState = .running
            hooks.onResume?()
        }
    }

    public func terminate() async throws {
        runState = .terminated
        hooks.onTerminate?()
    }
}

/** A governor that refuses to pretend: every tightening call throws. */
public final class UnenforcedGovernor: VmGovernor {
    public let reason: String

    public init(_ reason: String) {
        self.reason = reason
    }

    public var governanceSupport: GovernanceSupport { NO_SUPPORT }

    private func unavailable(_ call: String) -> ElpianGovernanceException { ElpianGovernanceException(reason, call: call) }

    public func setLimits(_ limits: ElpianLimits) async throws { throw unavailable("setLimits") }

    public func getLimits() async throws -> ElpianLimits { Limits.unlimited }

    public func usage() async throws -> ElpianUsage { ZERO_USAGE }

    public func subtreeUsage() async throws -> ElpianUsage { ZERO_USAGE }

    public func setCapability(_ capability: ElpianCapability, _ allowed: Bool) async throws { throw unavailable("setCapability") }

    public func sandbox(_ granted: [ElpianCapability]) async throws { throw unavailable("sandbox") }

    public func localCapabilities() async throws -> ElpianCapabilities { ElpianCapabilities([]) }

    public func effectiveCapabilities() async throws -> ElpianCapabilities { ElpianCapabilities([]) }

    public func allowsApi(_ apiName: String) async throws -> Bool { false }

    public func state() async throws -> ElpianVmState { ElpianVmState(state: .terminated, trapReason: nil, processing: false) }

    public func pause() async throws {}

    public func resumeExecution() async throws {}

    public func terminate() async throws {}
}

// ---------------------------------------------------------------------------
// Elpian VM governance (runtime-enforced)
// ---------------------------------------------------------------------------

private func governanceBinding() -> ElpianVmBinding? { hasPlatform() ? platform().elpianVm : nil }

private func govCall(_ symbol: String, _ args: [Any]) throws -> String {
    guard let b = governanceBinding(), b.isAvailable() else {
        let le = governanceBinding()?.lastError()
        let suffix = (le?.isEmpty == false) ? ": \(le!)" : ""
        throw ElpianGovernanceException("the Elpian runtime is not available\(suffix)", call: symbol)
    }
    guard let reply = try b.governance(symbol, args) else {
        throw ElpianGovernanceException("the loaded runtime does not export \(symbol) — rebuild it", call: symbol)
    }
    return reply
}

private func govObj(_ symbol: String, _ args: [Any]) throws -> JSONObject {
    try decodeGovernanceReply(govCall(symbol, args), call: symbol)
}

private func govList(_ symbol: String, _ args: [Any]) throws -> [Any?] {
    let raw = try govCall(symbol, args)
    let decoded: Any?
    do {
        decoded = try JSON.parse(raw)
    } catch {
        throw ElpianGovernanceException("malformed reply: \(error)", call: symbol)
    }
    if let a = asArray(decoded) { return a }
    if let m = asMap(decoded), let error = m["error"] as? String { throw ElpianGovernanceException(error, call: symbol) }
    throw ElpianGovernanceException("expected an array, got \(raw)", call: symbol)
}

private var governanceProbe: Bool?

/** Whether the loaded runtime carries the governance surface (probed once). */
public func elpianGovernanceAvailable() async -> Bool {
    if let p = governanceProbe { return p }
    guard let b = governanceBinding(), b.isAvailable() else { return false }
    let probe: Bool
    do {
        probe = try b.governance("elpian_usage", ["__elpian_probe__"]) != nil
    } catch {
        probe = false
    }
    governanceProbe = probe
    return probe
}

/** Forget the cached probe (a different runtime was installed — tests). */
public func resetElpianGovernanceProbe() {
    governanceProbe = nil
}

public final class ElpianVmGovernor: VmGovernor {
    public let machineId: String

    public init(_ machineId: String) {
        self.machineId = machineId
    }

    public var governanceSupport: GovernanceSupport {
        if let b = governanceBinding(), b.isAvailable(), governanceProbe != false { return FULL_SUPPORT }
        return NO_SUPPORT
    }

    public func setLimits(_ limits: ElpianLimits) async throws {
        _ = try govObj("elpian_set_limits", [machineId, JSON.stringify(Limits.toJson(limits))])
    }

    public func getLimits() async throws -> ElpianLimits { Limits.fromJson(try govObj("elpian_limits", [machineId])) }

    public func usage() async throws -> ElpianUsage { usageFromJson(try govObj("elpian_usage", [machineId])) }

    public func subtreeUsage() async throws -> ElpianUsage { usageFromJson(try govObj("elpian_subtree_usage", [machineId])) }

    public func chargeStorage(_ deltaBytes: Int64) async throws {
        _ = try govObj("elpian_charge_storage", [machineId, deltaBytes])
    }

    public func setCapability(_ capability: ElpianCapability, _ allowed: Bool) async throws {
        _ = try govObj("elpian_set_capability", [machineId, capability.wireName, Int64(allowed ? 1 : 0)])
    }

    public func setCapabilities(_ changes: [(ElpianCapability, Bool)]) async throws {
        let wire = JSONObject()
        for (k, v) in changes { wire[k.wireName] = v }
        _ = try govObj("elpian_set_capabilities", [machineId, JSON.stringify(wire)])
    }

    public func sandbox(_ granted: [ElpianCapability]) async throws {
        _ = try govObj("elpian_sandbox_capabilities", [machineId, JSON.stringify(granted.map { $0.wireName as Any? })])
    }

    public func localCapabilities() async throws -> ElpianCapabilities {
        ElpianCapabilities.fromJson(try govObj("elpian_local_capabilities", [machineId]))
    }

    public func effectiveCapabilities() async throws -> ElpianCapabilities {
        ElpianCapabilities.fromJson(try govObj("elpian_effective_capabilities", [machineId]))
    }

    public func allowsApi(_ apiName: String) async throws -> Bool {
        jsBool(try govObj("elpian_capability_allows", [machineId, apiName])["allowed"]) == true
    }

    public func state() async throws -> ElpianVmState { vmStateFromJson(try govObj("elpian_state", [machineId])) }

    public func pause() async throws {
        _ = try govObj("elpian_pause", [machineId])
    }

    public func resumeExecution() async throws {
        _ = try govObj("elpian_resume", [machineId])
    }

    public func terminate() async throws {
        _ = try govObj("elpian_terminate", [machineId])
    }
}

public final class ElpianTreeGovernor: VmTreeGovernor {
    public init() {}

    public var isAvailable: Bool {
        guard let b = governanceBinding() else { return false }
        return b.isAvailable()
    }

    public func adopt(_ parentId: String, _ childId: String) async throws {
        _ = try govObj("elpian_adopt", [parentId, childId])
    }

    public func tree(_ machineId: String) async throws -> ElpianVmTree { treeFromJson(try govObj("elpian_tree", [machineId])) }

    private func affected(_ reply: JSONObject) -> [String] { stringList(reply["affected"]) }

    public func pauseTree(_ machineId: String) async throws -> [String] { affected(try govObj("elpian_pause_tree", [machineId])) }

    public func terminateTree(_ machineId: String) async throws -> [String] { affected(try govObj("elpian_terminate_tree", [machineId])) }

    public func destroyTree(_ machineId: String) async throws -> [String] { affected(try govObj("elpian_destroy_tree", [machineId])) }

    public func enforceTreeBudgets() async throws -> [ElpianBudgetViolation] {
        try govList("elpian_enforce_tree_budgets", []).compactMap { entry in
            guard let j = asMap(entry) else { return nil }
            return ElpianBudgetViolation(
                machineId: jsString(j["machineId"] ?? ""),
                axis: jsString(j["axis"] ?? "unknown"),
                destroyed: stringList(j["destroyed"])
            )
        }
    }

    public func snapshot(_ machineId: String) async throws -> ElpianVmSnapshot { snapshotFromJson(try govObj("elpian_snapshot", [machineId])) }
}
