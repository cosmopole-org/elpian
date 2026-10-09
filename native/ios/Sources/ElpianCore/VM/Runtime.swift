import Foundation

/**
 * The three guest runtimes behind one client interface — ports of
 * `VmRuntimeClient`, `ElpianVm`, `QuickJsVm` and `WasmVm`
 * (the Dart files under flutter/lib/src/vm; vm/runtime.ts). The protocols live
 * here; the engines are the platform's (see Bindings.swift).
 */

/**
 * A host-call handler's reply: the TS `string | Promise<string>`. [now] is a
 * synchronous reply; [later] an asynchronous one (the work is already running,
 * as a Promise's is). The Elpian VM awaits a [later]; QuickJS and WASM guests
 * call `askHost` synchronously, so they receive `OK` for one.
 */
public enum HostReply {
    case now(String)
    case later(Task<String, Error>)

    public static func of(_ value: String) -> HostReply { .now(value) }

    public static func of(_ task: Task<String, Error>) -> HostReply { .later(task) }

    /** Start [work] at once (on the main actor) and reply with its result later. */
    public static func deferred(_ work: @escaping () async throws -> String) -> HostReply {
        .later(Task { @MainActor in try await work() })
    }
}

public typealias HostCallHandler = (_ apiName: String, _ payload: String) -> HostReply

public enum RuntimeKind: String, CaseIterable, CustomStringConvertible {
    case elpian
    case quickjs
    case wasm

    public var wireName: String { rawValue }
    public var description: String { rawValue }

    public static func fromWireName(_ name: String) -> RuntimeKind? { RuntimeKind(rawValue: name) }
}

public protocol VmRuntimeClient: AnyObject {
    var machineId: String { get }
    var governor: VmGovernor { get }
    func registerHostHandler(_ apiName: String, _ handler: @escaping HostCallHandler)
    func registerHostHandlers(_ handlers: [String: HostCallHandler])
    func setDefaultHostHandler(_ handler: @escaping HostCallHandler)
    func setGlobalHostData(_ data: JSONObject) async throws
    func run() async throws -> String
    func callFunction(_ funcName: String) async throws -> String
    func callFunctionWithInput(_ funcName: String, _ inputJson: String) async throws -> String
    func dispose() async
}

private struct VmExecResult {
    var hasHostCall: Bool
    var hostCallData: String
    var resultValue: String
}

private func parseExecResult(_ raw: String) -> VmExecResult {
    guard let parsed = try? JSON.parse(raw) else { return VmExecResult(hasHostCall: false, hostCallData: "", resultValue: "") }
    let j = asMap(parsed)
    return VmExecResult(
        hasHostCall: jsBool(j?["hasHostCall"]) == true,
        hostCallData: (j?["hostCallData"] as? String) ?? "",
        resultValue: (j?["resultValue"] as? String) ?? ""
    )
}

private func errorResult(_ reason: String) -> String {
    JSON.stringify(JSONObject([
        ("hasHostCall", false),
        ("hostCallData", ""),
        ("resultValue", JSON.stringify(JSONObject([("error", reason)]))),
    ]))
}

private func runtimeLog(_ message: String) {
    // No platform yet: nothing to log to.
    guard hasPlatform() else { return }
    platform().log(.debug, message)
}

/** Shared registry/fallback behaviour of every client. */
open class BaseClient {
    public let machineId: String
    var hostHandlers: [String: HostCallHandler] = [:]
    var fallbackHostHandler: HostCallHandler?
    var globalHostData = JSONObject()

    init(_ machineId: String) {
        self.machineId = machineId
    }

    public func registerHostHandler(_ apiName: String, _ handler: @escaping HostCallHandler) {
        hostHandlers[apiName] = handler
    }

    public func registerHostHandlers(_ handlers: [String: HostCallHandler]) {
        for (k, v) in handlers { hostHandlers[k] = v }
    }

    public func setDefaultHostHandler(_ handler: @escaping HostCallHandler) {
        fallbackHostHandler = handler
    }

    /** The built-ins every runtime answers when no handler is registered. */
    func builtin(_ label: String, _ apiName: String, _ payload: String) -> String {
        switch apiName {
        case "println":
            runtimeLog("\(label)[\(machineId)]: \(payload)")
            return Typed.OK_RESPONSE
        case "env.get":
            return JSON.stringify(JSONObject([("type", "object"), ("data", JSONObject([("value", globalHostData)]))]))
        case "stringify":
            return JSON.stringify(JSONObject([("type", "string"), ("data", JSONObject([("value", payload)]))]))
        default:
            runtimeLog("\(label): Unhandled host call: \(apiName)")
            return Typed.OK_RESPONSE
        }
    }

    /** A synchronous guest's view of a host call: an async reply cannot reach it (flutter_js `sendMessage` contract). */
    func syncReply(_ handler: HostCallHandler, _ apiName: String, _ payload: String) -> String {
        switch handler(apiName, payload) {
        case .now(let v): return v
        case .later: return Typed.OK_RESPONSE
        }
    }
}

// ============================================================================
// Elpian VM
// ============================================================================

public final class ElpianVm: BaseClient, VmRuntimeClient {
    private var cbCounter: Int64 = 0
    private var running = false
    public let elpianGovernor: ElpianVmGovernor
    public var governor: VmGovernor { elpianGovernor }

    public static let treeGovernor = ElpianTreeGovernor()

    public init(machineId: String) {
        elpianGovernor = ElpianVmGovernor(machineId)
        super.init(machineId)
    }

    public static func binding() -> ElpianVmBinding? { hasPlatform() ? platform().elpianVm : nil }

    public static var isRuntimeAvailable: Bool { binding()?.isAvailable() ?? false }

    public static var lastApiError: String { binding()?.lastError() ?? "no Elpian VM binding on this platform" }

    public static func initialize() async throws {
        try binding()?.initialize()
    }

    private static func require() throws -> ElpianVmBinding {
        guard let b = binding(), b.isAvailable() else { throw ElpianError("Elpian VM runtime unavailable: \(lastApiError)") }
        return b
    }

    public static func fromAst(_ machineId: String, _ astJson: String) async throws -> ElpianVm? {
        try require().createFromAst(machineId, astJson) ? ElpianVm(machineId: machineId) : nil
    }

    public static func fromCode(_ machineId: String, _ code: String) async throws -> ElpianVm? {
        try require().createFromCode(machineId, code) ? ElpianVm(machineId: machineId) : nil
    }

    /** [bytecodeBase64] as base64 (the TS bridges are string-typed; the C binding takes bytes). */
    public static func fromBytecode(_ machineId: String, base64 bytecodeBase64: String) async throws -> ElpianVm? {
        try await fromBytecode(machineId, try Bytes.base64Decode(bytecodeBase64))
    }

    public static func fromBytecode(_ machineId: String, _ bytecode: [UInt8]) async throws -> ElpianVm? {
        try require().createFromBytecode(machineId, bytecode) ? ElpianVm(machineId: machineId) : nil
    }

    public static func validateAst(_ astJson: String) async throws -> Bool {
        try binding()?.validateAst(astJson) ?? false
    }

    public var isRunning: Bool { running }

    public func setGlobalHostData(_ data: JSONObject) async throws {
        globalHostData = data.copy()
    }

    public func run() async throws -> String {
        running = true
        defer { running = false }
        let b = ElpianVm.binding()
        return try await loop(try b?.execute(machineId) ?? errorResult("native_lib_not_loaded"))
    }

    public func callFunction(_ funcName: String) async throws -> String {
        running = true
        defer { running = false }
        cbCounter += 1
        let cb = cbCounter
        let b = ElpianVm.binding()
        return try await loop(try b?.executeFunc(machineId, funcName, cb) ?? errorResult("native_lib_not_loaded"))
    }

    public func callFunctionWithInput(_ funcName: String, _ inputJson: String) async throws -> String {
        running = true
        defer { running = false }
        cbCounter += 1
        let cb = cbCounter
        let b = ElpianVm.binding()
        return try await loop(try b?.executeFuncWithInput(machineId, funcName, inputJson, cb) ?? errorResult("native_lib_not_loaded"))
    }

    public func deliverHostMessage(_ messageJson: String) async throws -> String {
        cbCounter += 1
        let cb = cbCounter
        let b = ElpianVm.binding()
        return try await loop(try b?.deliverHostMessage(machineId, messageJson, cb) ?? errorResult("native_lib_not_loaded"))
    }

    /** hasHostCall → handle → continueExecution, until the VM yields a value. */
    private func loop(_ raw: String) async throws -> String {
        var result = parseExecResult(raw)
        let binding = ElpianVm.binding()
        while result.hasHostCall, let b = binding {
            var apiName = ""
            var payload = ""
            do {
                guard let data = try JSON.parse(result.hostCallData) else {
                    throw ElpianError("Cannot read properties of null (reading 'apiName')")
                }
                let m = asMap(data)
                apiName = jsString(m?["apiName"] ?? "")
                // Typed JSON payloads (Victor) and pre-serialised ones (legacy VM).
                let p = m?["payload"]
                payload = (p as? String) ?? JSON.stringify(p)
            } catch {
                runtimeLog("ElpianVm: malformed host call: \(error)")
            }
            let response: String
            do {
                response = try await handle(apiName, payload)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                runtimeLog("ElpianVm: Host call error for \(apiName): \(error)")
                response = JSON.stringify(JSONObject([("type", "string"), ("data", JSONObject([("value", "error: \(error)")]))]))
            }
            result = parseExecResult(try b.continueExecution(machineId, response))
        }
        return result.resultValue
    }

    private func handle(_ apiName: String, _ payload: String) async throws -> String {
        if let h = hostHandlers[apiName] ?? fallbackHostHandler {
            switch h(apiName, payload) {
            case .now(let v): return v
            case .later(let task): return try await task.value
            }
        }
        return builtin("ElpianVm", apiName, payload)
    }

    public func dispose() async {
        _ = try? ElpianVm.binding()?.destroy(machineId)
    }
}

// ============================================================================
// QuickJS (JS guest sandbox)
// ============================================================================

/** The guest-side `askHost` — byte-for-byte the bootstrap `QuickJsVm` installs. */
public let ASK_HOST_BOOTSTRAP = """

globalThis.askHost = function(apiName) {
  var args = Array.prototype.slice.call(arguments, 1);
  var payload = '';
  if (args.length === 1) {
    payload = args[0];
  } else if (args.length > 1) {
    payload = args;
  }
  var encoded = typeof payload === 'string' ? payload : JSON.stringify(payload);
  return __elpianHostCall(String(apiName), encoded === undefined ? 'null' : encoded);
};

"""

public final class QuickJsVm: BaseClient, VmRuntimeClient {
    private var sandbox: JsSandbox?
    private var bootCode: String?
    private var disposed = false
    public private(set) var hostGovernor: HostSideGovernor!
    public var governor: VmGovernor { hostGovernor }

    init(machineId: String) {
        super.init(machineId)
        hostGovernor = HostSideGovernor(machineId, enforcesInstructions: false, hooks: GovernorHooks(onTerminate: { [weak self] in self?.disposeNow() }))
    }

    public static var isRuntimeAvailable: Bool { hasPlatform() && platform().jsSandbox != nil }

    public static func fromCode(_ machineId: String, _ code: String) async throws -> QuickJsVm {
        guard hasPlatform(), let factory = platform().jsSandbox else {
            throw ElpianError("QuickJS runtime unavailable: the platform provides no JS sandbox")
        }
        let vm = QuickJsVm(machineId: machineId)
        let sandbox = try factory.create(machineId)
        vm.sandbox = sandbox
        sandbox.setHostCallHandler { [weak vm] api, payload in vm?.dispatchHostCall(api, payload) ?? Typed.NULL_RESPONSE }
        _ = try sandbox.evaluate(ASK_HOST_BOOTSTRAP)
        vm.bootCode = code
        return vm
    }

    public static func fromAst() async throws -> QuickJsVm {
        throw ElpianError("QuickJS runtime expects JavaScript source in `code`; AST JSON is only supported by the Elpian runtime.")
    }

    public func setGlobalHostData(_ data: JSONObject) async throws {
        globalHostData = data.copy()
        guard let sandbox = sandbox else { return }
        let encoded = JSON.quote(JSON.stringify(globalHostData))
        _ = try sandbox.evaluate("""
        (function() {
          var __env = JSON.parse(\(encoded));
          globalThis.__ELPIAN_HOST_ENV__ = __env;
          globalThis.ELPIAN_HOST_ENV = __env;
          globalThis.getElpianHostEnv = function() { return globalThis.__ELPIAN_HOST_ENV__; };
        })();
        """)
    }

    public func runCode(_ code: String) async throws -> String {
        guard let sandbox = sandbox, !disposed else { return "" }
        hostGovernor.beginTurn()
        return try sandbox.evaluate(code)
    }

    public func run() async throws -> String {
        guard let code = bootCode, !code.isEmpty else { return "" }
        return try await runCode(code)
    }

    public func callFunction(_ funcName: String) async throws -> String { try await runCode("\(funcName)();") }

    public func callFunctionWithInput(_ funcName: String, _ inputJson: String) async throws -> String {
        try await runCode("\(funcName)(JSON.parse(\(JSON.quote(inputJson))));")
    }

    /** The capability gate: every QuickJS host call crosses here. */
    private func dispatchHostCall(_ apiName: String, _ payload: String) -> String {
        if let refusal = hostGovernor.checkAndCharge(apiName, jsLength(payload)) {
            runtimeLog("QuickJs[\(machineId)]: \(apiName) refused — \(refusal)")
            return Typed.NULL_RESPONSE
        }
        if let h = hostHandlers[apiName] ?? fallbackHostHandler {
            // Guests call askHost synchronously; an async handler's reply cannot
            // reach them (same contract as flutter_js `sendMessage`).
            return syncReply(h, apiName, payload)
        }
        return builtin("QuickJsVm", apiName, payload)
    }

    private func disposeNow() {
        if disposed { return }
        disposed = true
        sandbox?.dispose()
        sandbox = nil
    }

    public func dispose() async {
        disposeNow()
    }
}

// ============================================================================
// WASM
// ============================================================================

public struct WasmVmExports: Equatable {
    public var memory: String
    public var alloc: String
    public var dealloc: String
    public var run: String
    public var callFunction: String
    public var callFunctionWithInput: String
    public var getResultPtr: String
    public var getResultLen: String
}

public struct WasmVmConfig: Equatable {
    public var wasmBase64: String?
    public var wasmAssetPath: String?
    public var exports: WasmVmExports
}

public func parseWasmConfig(_ source: String) throws -> WasmVmConfig {
    let parsed = try JSON.parse(source)
    guard let raw = asMap(parsed) else { throw ElpianError("WASM runtime config must be a JSON object.") }
    let e = asMap(raw["exports"]) ?? JSONObject()
    func s(_ v: Any?, _ d: String) -> String { v == nil ? d : jsString(v) }
    return WasmVmConfig(
        wasmBase64: raw["wasmBase64"].map { jsString($0) },
        wasmAssetPath: raw["wasmAssetPath"].map { jsString($0) },
        exports: WasmVmExports(
            memory: s(e["memory"], "memory"),
            alloc: s(e["alloc"], "alloc"),
            dealloc: s(e["dealloc"], "dealloc"),
            run: s(e["run"], "run"),
            callFunction: s(e["callFunction"], "call_function"),
            callFunctionWithInput: s(e["callFunctionWithInput"], "call_function_with_input"),
            getResultPtr: s(e["getResultPtr"], "get_result_ptr"),
            getResultLen: s(e["getResultLen"], "get_result_len")
        )
    )
}

/**
 * A WASM guest. ABI: the module exports `memory`, `alloc(len) -> ptr`,
 * `dealloc(ptr, len)`, `run()`, `call_function(namePtr, nameLen)`,
 * `call_function_with_input(namePtr, nameLen, inputPtr, inputLen)`,
 * `get_result_ptr()` and `get_result_len()` (names overridable through the
 * config's `exports`), and imports
 * `elpian_host_call(apiPtr, apiLen, payloadPtr, payloadLen, outPtr, outCap) -> written`.
 */
public final class WasmVm: BaseClient, VmRuntimeClient {
    private struct WasmString {
        let ptr: Int64
        let length: Int
    }

    private var instance: WasmInstanceHandle?
    private var config: WasmVmConfig?
    private var bootCode: String?
    public private(set) var hostGovernor: HostSideGovernor!
    public var governor: VmGovernor { hostGovernor }

    init(machineId: String) {
        super.init(machineId)
        hostGovernor = HostSideGovernor(machineId, enforcesInstructions: true, hooks: GovernorHooks(onTerminate: { [weak self] in self?.disposeNow() }))
    }

    public static var isRuntimeAvailable: Bool { hasPlatform() && platform().wasm != nil }

    public static func fromCode(_ machineId: String, _ code: String) async throws -> WasmVm {
        let vm = WasmVm(machineId: machineId)
        vm.bootCode = code
        return vm
    }

    public static func fromAst() async throws -> WasmVm {
        throw ElpianError("WASM runtime expects JSON runtime config in `code`.")
    }

    public func setGlobalHostData(_ data: JSONObject) async throws {
        globalHostData = data.copy()
    }

    public func run() async throws -> String {
        guard let code = bootCode, !code.isEmpty else { return "" }
        try await ensureLoaded(code)
        hostGovernor.beginTurn()
        _ = try require(config!.exports.run, [])
        return try readResult()
    }

    public func callFunction(_ funcName: String) async throws -> String {
        try assertLoaded()
        hostGovernor.beginTurn()
        let fn = try writeString(funcName)
        defer { dealloc(fn) }
        _ = try require(config!.exports.callFunction, [fn.ptr, Int64(fn.length)])
        return try readResult()
    }

    public func callFunctionWithInput(_ funcName: String, _ inputJson: String) async throws -> String {
        try assertLoaded()
        hostGovernor.beginTurn()
        let fn = try writeString(funcName)
        defer { dealloc(fn) }
        let input = try writeString(inputJson)
        defer { dealloc(input) }
        _ = try require(config!.exports.callFunctionWithInput, [fn.ptr, Int64(fn.length), input.ptr, Int64(input.length)])
        return try readResult()
    }

    private func ensureLoaded(_ configJson: String) async throws {
        if instance != nil { return }
        guard hasPlatform(), let engine = platform().wasm else {
            throw ElpianError("WASM runtime unavailable: the platform provides no WebAssembly engine")
        }
        let config = try parseWasmConfig(configJson)
        let bytes = try await loadWasmBytes(config)
        self.config = config
        let inst = try engine.instantiate(bytes) { [weak self] _, name, args in
            self?.onImport(name, args) ?? [0]
        }
        instance = inst
        if !inst.hasExport(config.exports.memory) { throw ElpianError("WASM memory export not found: \(config.exports.memory)") }
    }

    private func onImport(_ name: String, _ args: [Int64]) -> [Int64] {
        if name != "elpian_host_call" || args.count < 6 || instance == nil { return [0] }
        let apiName = readString(args[0], args[1])
        let payload = readString(args[2], args[3])
        return [Int64(writeInto(dispatchHostCall(apiName, payload), args[4], args[5]))]
    }

    private func dispatchHostCall(_ apiName: String, _ payload: String) -> String {
        if let refusal = hostGovernor.checkAndCharge(apiName, jsLength(payload)) {
            runtimeLog("WasmVm[\(machineId)]: \(apiName) refused — \(refusal)")
            return Typed.NULL_RESPONSE
        }
        if let h = hostHandlers[apiName] ?? fallbackHostHandler {
            return syncReply(h, apiName, payload)
        }
        return builtin("WasmVm", apiName, payload)
    }

    private func require(_ name: String, _ args: [Int64]) throws -> [Int64] {
        guard let inst = instance else { throw ElpianError("WASM instance is not loaded.") }
        if !inst.hasExport(name) { throw ElpianError("WASM function export not found: \(name)") }
        return try inst.call(name, args)
    }

    private func writeString(_ text: String) throws -> WasmString {
        let bytes = Bytes.utf8Encode(text)
        let ptr = try require(config!.exports.alloc, [Int64(bytes.count)]).first ?? 0
        if ptr <= 0 { throw ElpianError("WASM alloc returned invalid pointer for length \(bytes.count).") }
        let mem = config!.exports.memory
        if ptr + Int64(bytes.count) > instance!.memoryLength(mem) {
            throw ElpianError("WASM memory write out of range (ptr=\(ptr) len=\(bytes.count)).")
        }
        try instance!.memoryWrite(mem, ptr, bytes)
        return WasmString(ptr: ptr, length: bytes.count)
    }

    private func writeInto(_ text: String, _ ptr: Int64, _ capacity: Int64) -> Int {
        if capacity <= 0 { return 0 }
        let bytes = Bytes.utf8Encode(text)
        let length = Int(min(Int64(bytes.count), capacity))
        let mem = config!.exports.memory
        if ptr < 0 || ptr + Int64(length) > instance!.memoryLength(mem) { return 0 }
        do {
            try instance!.memoryWrite(mem, ptr, Array(bytes.prefix(length)))
        } catch {
            return 0
        }
        return length
    }

    private func readString(_ ptr: Int64, _ len: Int64) -> String {
        if len <= 0 { return "" }
        let mem = config!.exports.memory
        if ptr < 0 || ptr + len > instance!.memoryLength(mem) { return "" }
        guard let bytes = try? instance!.memoryRead(mem, ptr, Int(len)) else { return "" }
        return Bytes.utf8Decode(bytes)
    }

    private func readResult() throws -> String {
        let ptr = try require(config!.exports.getResultPtr, []).first ?? 0
        let len = try require(config!.exports.getResultLen, []).first ?? 0
        if ptr <= 0 || len <= 0 { return "" }
        return readString(ptr, len)
    }

    private func dealloc(_ text: WasmString) {
        guard let name = config?.exports.dealloc, !name.isEmpty, let inst = instance, inst.hasExport(name) else { return }
        _ = try? inst.call(name, [text.ptr, Int64(text.length)])
    }

    private func assertLoaded() throws {
        if instance == nil || config == nil { throw ElpianError("WASM runtime is not initialized. Call run() first.") }
    }

    private func disposeNow() {
        instance?.dispose()
        instance = nil
        config = nil
    }

    public func dispose() async {
        disposeNow()
    }
}

/** The module bytes from the config: inline base64, or a bundled asset. */
public func loadWasmBytes(_ config: WasmVmConfig) async throws -> [UInt8] {
    if let b64 = config.wasmBase64, !b64.isEmpty { return try Bytes.base64Decode(b64) }
    guard let path = config.wasmAssetPath, !path.isEmpty else {
        throw ElpianError("WASM config must provide either `wasmBase64` or `wasmAssetPath`.")
    }
    let text: String
    do {
        text = try await platform().loadAsset(path, .base64)
    } catch is PlatformUnsupported {
        throw ElpianError("This platform cannot load bundled assets.")
    }
    return try Bytes.base64Decode(text)
}

// ============================================================================
// Factory
// ============================================================================

public func isRuntimeAvailable(_ kind: RuntimeKind) -> Bool {
    switch kind {
    case .elpian: return ElpianVm.isRuntimeAvailable
    case .quickjs: return QuickJsVm.isRuntimeAvailable
    case .wasm: return WasmVm.isRuntimeAvailable
    }
}

public func initializeRuntime(_ kind: RuntimeKind) async throws {
    if kind == .elpian { try await ElpianVm.initialize() }
}

/** Where a runtime's program comes from (`createRuntime`'s `source`). */
public struct RuntimeSource {
    public var code: String?
    public var astJson: String?
    public var bytecodeBase64: String?

    public init(code: String? = nil, astJson: String? = nil, bytecodeBase64: String? = nil) {
        self.code = code
        self.astJson = astJson
        self.bytecodeBase64 = bytecodeBase64
    }
}

/**
 * Create a client from source the way `ElpianVmWidget` does: `code` (JS for
 * QuickJS, the JSON config for WASM, Elpian source for the VM) or an AST.
 */
public func createRuntime(_ kind: RuntimeKind, _ machineId: String, _ source: RuntimeSource) async throws -> VmRuntimeClient? {
    switch kind {
    case .elpian:
        if let b = source.bytecodeBase64, !b.isEmpty { return try await ElpianVm.fromBytecode(machineId, base64: b) }
        if let a = source.astJson, !a.isEmpty { return try await ElpianVm.fromAst(machineId, a) }
        if let c = source.code { return try await ElpianVm.fromCode(machineId, c) }
        return nil
    case .quickjs:
        guard let c = source.code else { return try await QuickJsVm.fromAst() }
        return try await QuickJsVm.fromCode(machineId, c)
    case .wasm:
        guard let c = source.code else { return try await WasmVm.fromAst() }
        return try await WasmVm.fromCode(machineId, c)
    }
}
