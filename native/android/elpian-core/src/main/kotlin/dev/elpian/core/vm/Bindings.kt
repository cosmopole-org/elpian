package dev.elpian.core.vm

/**
 * The sandbox engines the platform provides (vm/bindings.ts). The core owns
 * every runtime protocol (host-call loop, `askHost` bridge, WASM memory ABI,
 * governance); the engines are native:
 *
 *  - Elpian VM — the Rust runtime's C ABI (`elpian_*`) through JNI.
 *  - JS guests — an isolated QuickJS context per mini app (as flutter_js on
 *    Android).
 *  - WASM guests — Chicory, a pure-JVM WebAssembly runtime.
 */
interface ElpianVmBinding {
    fun isAvailable(): Boolean
    fun lastError(): String?
    fun init()
    fun createFromAst(machineId: String, astJson: String): Boolean
    fun createFromCode(machineId: String, code: String): Boolean
    fun createFromBytecode(machineId: String, bytecode: ByteArray): Boolean
    fun validateAst(astJson: String): Boolean
    /** Each returns the `VmExecResult` JSON (`hasHostCall`, `hostCallData`, `resultValue`). */
    fun execute(machineId: String): String
    fun executeFunc(machineId: String, funcName: String, cbId: Long): String
    fun executeFuncWithInput(machineId: String, funcName: String, inputJson: String, cbId: Long): String
    fun continueExecution(machineId: String, inputJson: String): String
    fun deliverHostMessage(machineId: String, messageJson: String, cbId: Long): String
    fun destroy(machineId: String): Boolean
    fun exists(machineId: String): Boolean
    /**
     * A governance export by its C name (`elpian_usage`, `elpian_set_limits`, …)
     * with string / long arguments; the raw JSON reply, or null when the loaded
     * runtime does not export it.
     */
    fun governance(symbol: String, args: List<Any>): String?
}

/** One isolated guest JS engine. */
interface JsSandbox {
    /** Install `__elpianHostCall(apiName, payload)` → [handler]'s string reply. */
    fun setHostCallHandler(handler: (apiName: String, payload: String) -> String)
    /** Evaluate [code]; the completion value stringified. Throws on a guest error. */
    fun evaluate(code: String): String
    fun dispose()
}

interface JsSandboxFactory {
    fun create(machineId: String): JsSandbox
}

/** Imported-function callback: numbers in, numbers out. */
typealias WasmImportHandler = (module: String, name: String, args: List<Long>) -> List<Long>

interface WasmInstanceHandle {
    fun hasExport(name: String): Boolean
    fun call(exportName: String, args: List<Long>): List<Long>
    fun memoryLength(memoryExport: String): Long
    fun memoryRead(memoryExport: String, ptr: Long, length: Int): ByteArray
    fun memoryWrite(memoryExport: String, ptr: Long, bytes: ByteArray)
    fun dispose()
}

interface WasmEngine {
    /** Compile and instantiate [bytes], binding every function import to [onImport]. */
    fun instantiate(bytes: ByteArray, onImport: WasmImportHandler): WasmInstanceHandle
}
