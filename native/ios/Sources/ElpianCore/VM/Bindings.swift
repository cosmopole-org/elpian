import Foundation

/**
 * The sandboxes the platform provides to the core (vm/bindings.ts). The core
 * owns every runtime's protocol (host-call loop, `askHost` bridge, WASM
 * memory ABI, governance); the engines are the platform's. On iOS:
 *
 *  - Elpian VM — the Rust runtime's C ABI (`elpian_*`, rust/crates/elpian-ffi),
 *    linked statically.
 *  - JS guests — an isolated JavaScriptCore context per mini app.
 *  - WASM guests — a native WebAssembly runtime.
 *
 * The native engines answer synchronously (the TypeScript `MaybePromise`
 * covers both forms; the Swift core uses the synchronous one, as the Kotlin
 * core does). Errors are thrown.
 */

/** The Elpian VM C ABI, one method per export the Flutter FFI layer binds. */
public protocol ElpianVmBinding: AnyObject {
    /** Whether the runtime library is loaded. */
    func isAvailable() -> Bool
    /** The last load/call error, for diagnostics (`ElpianVmApi.lastError`). */
    func lastError() -> String?
    func initialize() throws
    func createFromAst(_ machineId: String, _ astJson: String) throws -> Bool
    func createFromCode(_ machineId: String, _ code: String) throws -> Bool
    /** Bytecode as raw bytes (the TypeScript bridge passes base64 text). */
    func createFromBytecode(_ machineId: String, _ bytecode: [UInt8]) throws -> Bool
    func validateAst(_ astJson: String) throws -> Bool
    /** Each returns the `VmExecResult` JSON (`hasHostCall`, `hostCallData`, `resultValue`). */
    func execute(_ machineId: String) throws -> String
    func executeFunc(_ machineId: String, _ funcName: String, _ cbId: Int64) throws -> String
    func executeFuncWithInput(_ machineId: String, _ funcName: String, _ inputJson: String, _ cbId: Int64) throws -> String
    func continueExecution(_ machineId: String, _ inputJson: String) throws -> String
    func deliverHostMessage(_ machineId: String, _ messageJson: String, _ cbId: Int64) throws -> String
    func destroy(_ machineId: String) throws -> Bool
    func exists(_ machineId: String) throws -> Bool
    /**
     * A governance export by its C name (`elpian_usage`, `elpian_set_limits`, …)
     * with string / number / boolean arguments. Returns the raw JSON reply, or
     * nil when the loaded runtime does not export it.
     */
    func governance(_ symbol: String, _ args: [Any]) throws -> String?
}

/** One isolated guest JS engine. */
public protocol JsSandbox: AnyObject {
    /**
     * Install the host bridge: the sandbox defines a synchronous
     * `__elpianHostCall(apiName, payloadJson)` global that calls [handler] and
     * returns its string reply.
     */
    func setHostCallHandler(_ handler: @escaping (_ apiName: String, _ payload: String) -> String)
    /** Evaluate [code]; returns the completion value stringified (flutter_js `stringResult`). Throws on a guest error. */
    func evaluate(_ code: String) throws -> String
    func dispose()
}

public protocol JsSandboxFactory: AnyObject {
    func create(_ machineId: String) throws -> JsSandbox
}

/** Imported-function callback: numbers in, numbers out. */
public typealias WasmImportHandler = (_ module: String, _ name: String, _ args: [Int64]) -> [Int64]

public protocol WasmInstanceHandle: AnyObject {
    func hasExport(_ name: String) -> Bool
    func call(_ exportName: String, _ args: [Int64]) throws -> [Int64]
    func memoryLength(_ memoryExport: String) -> Int64
    func memoryRead(_ memoryExport: String, _ ptr: Int64, _ length: Int) throws -> [UInt8]
    func memoryWrite(_ memoryExport: String, _ ptr: Int64, _ bytes: [UInt8]) throws
    func dispose()
}

public protocol WasmEngine: AnyObject {
    /**
     * Compile and instantiate [bytes]. Every function import is bound to
     * [onImport]; the instance is returned once its start function has run.
     */
    func instantiate(_ bytes: [UInt8], _ onImport: @escaping WasmImportHandler) throws -> WasmInstanceHandle
}

/** The sandbox engines a platform offers (absent ones make that runtime unavailable). */
public struct RuntimeBindings {
    public var elpianVm: ElpianVmBinding?
    public var jsSandbox: JsSandboxFactory?
    public var wasm: WasmEngine?

    public init(elpianVm: ElpianVmBinding? = nil, jsSandbox: JsSandboxFactory? = nil, wasm: WasmEngine? = nil) {
        self.elpianVm = elpianVm
        self.jsSandbox = jsSandbox
        self.wasm = wasm
    }
}
