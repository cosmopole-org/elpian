package dev.elpian.core.vm

import dev.elpian.core.platform.platform
import dev.elpian.core.util.Bytes
import dev.elpian.core.util.Json
import dev.elpian.core.util.JsonMap
import dev.elpian.core.util.Typed
import dev.elpian.core.util.isMap
import dev.elpian.core.util.jsString
import kotlinx.coroutines.Deferred
import kotlin.math.min

/**
 * The three guest runtimes behind one client interface — ports of
 * `VmRuntimeClient`, `ElpianVm`, `QuickJsVm` and `WasmVm`
 * (the Dart files under flutter/lib/src/vm; vm/runtime.ts). The protocols live here; the
 * engines are the platform's (see Bindings.kt).
 */

/**
 * A host-call handler's reply: the TS `string | Promise<string>`. [Now] is a
 * synchronous reply; [Later] an asynchronous one (the work is already running,
 * as a Promise's is). The Elpian VM awaits a [Later]; QuickJS and WASM guests
 * call `askHost` synchronously, so they receive `OK` for one.
 */
sealed class HostReply {
    class Now(val value: String) : HostReply()

    class Later(val value: Deferred<String>) : HostReply()

    companion object {
        fun of(value: String): HostReply = Now(value)

        fun of(value: Deferred<String>): HostReply = Later(value)
    }
}

typealias HostCallHandler = (apiName: String, payload: String) -> HostReply

enum class RuntimeKind(val wireName: String) {
    ELPIAN("elpian"),
    QUICKJS("quickjs"),
    WASM("wasm");

    override fun toString(): String = wireName

    companion object {
        fun fromWireName(name: String): RuntimeKind? = entries.firstOrNull { it.wireName == name }
    }
}

interface VmRuntimeClient {
    val machineId: String
    val governor: VmGovernor
    fun registerHostHandler(apiName: String, handler: HostCallHandler)
    fun registerHostHandlers(handlers: Map<String, HostCallHandler>)
    fun setDefaultHostHandler(handler: HostCallHandler)
    suspend fun setGlobalHostData(data: Map<String, Any?>)
    suspend fun run(): String
    suspend fun callFunction(funcName: String): String
    suspend fun callFunctionWithInput(funcName: String, inputJson: String): String
    suspend fun dispose()
}

private class VmExecResult(
    val hasHostCall: Boolean,
    val hostCallData: String,
    val resultValue: String,
)

private fun parseExecResult(raw: String): VmExecResult = try {
    val j = Json.parse(raw) as? Map<*, *>
    VmExecResult(
        hasHostCall = j?.get("hasHostCall") == true,
        hostCallData = (j?.get("hostCallData") as? String) ?: "",
        resultValue = (j?.get("resultValue") as? String) ?: "",
    )
} catch (_: Exception) {
    VmExecResult(hasHostCall = false, hostCallData = "", resultValue = "")
}

private fun errorResult(reason: String): String =
    Json.stringify(linkedMapOf("hasHostCall" to false, "hostCallData" to "", "resultValue" to Json.stringify(linkedMapOf("error" to reason))))

private fun log(message: String) {
    try {
        platform().log("debug", message)
    } catch (_: Exception) {
        /* no platform yet */
    }
}

/** Shared registry/fallback behaviour of every client. */
abstract class BaseClient(override val machineId: String) : VmRuntimeClient {
    protected val hostHandlers = LinkedHashMap<String, HostCallHandler>()
    protected var fallbackHostHandler: HostCallHandler? = null
    protected var globalHostData: JsonMap = LinkedHashMap()

    override fun registerHostHandler(apiName: String, handler: HostCallHandler) {
        hostHandlers[apiName] = handler
    }

    override fun registerHostHandlers(handlers: Map<String, HostCallHandler>) {
        for ((k, v) in handlers) hostHandlers[k] = v
    }

    override fun setDefaultHostHandler(handler: HostCallHandler) {
        fallbackHostHandler = handler
    }

    /** The built-ins every runtime answers when no handler is registered. */
    protected fun builtin(label: String, apiName: String, payload: String): String = when (apiName) {
        "println" -> {
            log("$label[$machineId]: $payload")
            Typed.OK
        }
        "env.get" -> Json.stringify(linkedMapOf("type" to "object", "data" to linkedMapOf("value" to globalHostData)))
        "stringify" -> Json.stringify(linkedMapOf("type" to "string", "data" to linkedMapOf("value" to payload)))
        else -> {
            log("$label: Unhandled host call: $apiName")
            Typed.OK
        }
    }
}

// ============================================================================
// Elpian VM
// ============================================================================

class ElpianVm(machineId: String) : BaseClient(machineId) {
    private var cbCounter = 0L
    private var running = false
    override val governor: ElpianVmGovernor = ElpianVmGovernor(machineId)

    companion object {
        val treeGovernor: ElpianTreeGovernor = ElpianTreeGovernor()

        fun binding(): ElpianVmBinding? = platform().elpianVm

        val isRuntimeAvailable: Boolean get() = binding()?.isAvailable() ?: false

        val lastApiError: String get() = binding()?.lastError() ?: "no Elpian VM binding on this platform"

        suspend fun initialize() {
            binding()?.init()
        }

        private fun require(): ElpianVmBinding {
            val b = binding()
            if (b == null || !b.isAvailable()) throw IllegalStateException("Elpian VM runtime unavailable: $lastApiError")
            return b
        }

        suspend fun fromAst(machineId: String, astJson: String): ElpianVm? =
            if (require().createFromAst(machineId, astJson)) ElpianVm(machineId) else null

        suspend fun fromCode(machineId: String, code: String): ElpianVm? =
            if (require().createFromCode(machineId, code)) ElpianVm(machineId) else null

        /** [bytecodeBase64] as base64 (the TS bridges are string-typed; the JNI binding takes bytes). */
        suspend fun fromBytecode(machineId: String, bytecodeBase64: String): ElpianVm? =
            fromBytecode(machineId, Bytes.base64(bytecodeBase64))

        suspend fun fromBytecode(machineId: String, bytecode: ByteArray): ElpianVm? =
            if (require().createFromBytecode(machineId, bytecode)) ElpianVm(machineId) else null

        suspend fun validateAst(astJson: String): Boolean = binding()?.validateAst(astJson) ?: false
    }

    val isRunning: Boolean get() = running

    override suspend fun setGlobalHostData(data: Map<String, Any?>) {
        globalHostData = LinkedHashMap(data)
    }

    override suspend fun run(): String {
        running = true
        try {
            val b = binding()
            return loop(b?.execute(machineId) ?: errorResult("native_lib_not_loaded"))
        } finally {
            running = false
        }
    }

    override suspend fun callFunction(funcName: String): String {
        running = true
        val cb = ++cbCounter
        try {
            val b = binding()
            return loop(b?.executeFunc(machineId, funcName, cb) ?: errorResult("native_lib_not_loaded"))
        } finally {
            running = false
        }
    }

    override suspend fun callFunctionWithInput(funcName: String, inputJson: String): String {
        running = true
        val cb = ++cbCounter
        try {
            val b = binding()
            return loop(b?.executeFuncWithInput(machineId, funcName, inputJson, cb) ?: errorResult("native_lib_not_loaded"))
        } finally {
            running = false
        }
    }

    suspend fun deliverHostMessage(messageJson: String): String {
        val cb = ++cbCounter
        val b = binding()
        return loop(b?.deliverHostMessage(machineId, messageJson, cb) ?: errorResult("native_lib_not_loaded"))
    }

    /** hasHostCall → handle → continueExecution, until the VM yields a value. */
    private suspend fun loop(raw: String): String {
        var result = parseExecResult(raw)
        val b = binding()
        while (result.hasHostCall && b != null) {
            var apiName = ""
            var payload = ""
            try {
                val data = Json.parse(result.hostCallData)
                    ?: throw IllegalStateException("Cannot read properties of null (reading 'apiName')")
                val m = data as? Map<*, *>
                apiName = jsString(m?.get("apiName") ?: "")
                // Typed JSON payloads (Victor) and pre-serialised ones (legacy VM).
                val p = m?.get("payload")
                payload = if (p is String) p else Json.stringify(p)
            } catch (e: Exception) {
                log("ElpianVm: malformed host call: $e")
            }
            val response: String = try {
                handle(apiName, payload)
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                log("ElpianVm: Host call error for $apiName: $e")
                Json.stringify(linkedMapOf("type" to "string", "data" to linkedMapOf("value" to "error: $e")))
            }
            result = parseExecResult(b.continueExecution(machineId, response))
        }
        return result.resultValue
    }

    private suspend fun handle(apiName: String, payload: String): String {
        val h = hostHandlers[apiName] ?: fallbackHostHandler
        if (h != null) {
            return when (val r = h(apiName, payload)) {
                is HostReply.Now -> r.value
                is HostReply.Later -> r.value.await()
            }
        }
        return builtin("ElpianVm", apiName, payload)
    }

    override suspend fun dispose() {
        binding()?.destroy(machineId)
    }
}

// ============================================================================
// QuickJS (JS guest sandbox)
// ============================================================================

/** The guest-side `askHost` — byte-for-byte the bootstrap `QuickJsVm` installs. */
const val ASK_HOST_BOOTSTRAP: String = """
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

class QuickJsVm(machineId: String) : BaseClient(machineId) {
    private var sandbox: JsSandbox? = null
    private var bootCode: String? = null
    private var disposed = false
    override val governor: HostSideGovernor = HostSideGovernor(machineId, false, GovernorHooks(onTerminate = { disposeNow() }))

    companion object {
        val isRuntimeAvailable: Boolean get() = platform().jsSandbox != null

        suspend fun fromCode(machineId: String, code: String): QuickJsVm {
            val factory = platform().jsSandbox
                ?: throw IllegalStateException("QuickJS runtime unavailable: the platform provides no JS sandbox")
            val vm = QuickJsVm(machineId)
            val sandbox = factory.create(machineId)
            vm.sandbox = sandbox
            sandbox.setHostCallHandler { api, payload -> vm.dispatchHostCall(api, payload) }
            sandbox.evaluate(ASK_HOST_BOOTSTRAP)
            vm.bootCode = code
            return vm
        }

        suspend fun fromAst(): QuickJsVm =
            throw IllegalStateException("QuickJS runtime expects JavaScript source in `code`; AST JSON is only supported by the Elpian runtime.")
    }

    override suspend fun setGlobalHostData(data: Map<String, Any?>) {
        globalHostData = LinkedHashMap(data)
        val sandbox = sandbox ?: return
        val encoded = Json.quote(Json.stringify(globalHostData))
        sandbox.evaluate(
            """(function() {
  var __env = JSON.parse($encoded);
  globalThis.__ELPIAN_HOST_ENV__ = __env;
  globalThis.ELPIAN_HOST_ENV = __env;
  globalThis.getElpianHostEnv = function() { return globalThis.__ELPIAN_HOST_ENV__; };
})();""",
        )
    }

    suspend fun runCode(code: String): String {
        val sandbox = sandbox
        if (sandbox == null || disposed) return ""
        governor.beginTurn()
        return sandbox.evaluate(code)
    }

    override suspend fun run(): String {
        val code = bootCode
        if (code.isNullOrEmpty()) return ""
        return runCode(code)
    }

    override suspend fun callFunction(funcName: String): String = runCode("$funcName();")

    override suspend fun callFunctionWithInput(funcName: String, inputJson: String): String =
        runCode("$funcName(JSON.parse(${Json.quote(inputJson)}));")

    /** The capability gate: every QuickJS host call crosses here. */
    private fun dispatchHostCall(apiName: String, payload: String): String {
        val refusal = governor.checkAndCharge(apiName, payload.length)
        if (refusal != null) {
            log("QuickJs[$machineId]: $apiName refused — $refusal")
            return Typed.NULL
        }
        val h = hostHandlers[apiName] ?: fallbackHostHandler
        if (h != null) {
            // Guests call askHost synchronously; an async handler's reply cannot
            // reach them (same contract as flutter_js `sendMessage`).
            return when (val r = h(apiName, payload)) {
                is HostReply.Now -> r.value
                is HostReply.Later -> Typed.OK
            }
        }
        return builtin("QuickJsVm", apiName, payload)
    }

    private fun disposeNow() {
        if (disposed) return
        disposed = true
        sandbox?.dispose()
        sandbox = null
    }

    override suspend fun dispose() {
        disposeNow()
    }
}

// ============================================================================
// WASM
// ============================================================================

data class WasmVmExports(
    val memory: String,
    val alloc: String,
    val dealloc: String,
    val run: String,
    val callFunction: String,
    val callFunctionWithInput: String,
    val getResultPtr: String,
    val getResultLen: String,
)

data class WasmVmConfig(
    val wasmBase64: String?,
    val wasmAssetPath: String?,
    val exports: WasmVmExports,
)

fun parseWasmConfig(source: String): WasmVmConfig {
    val raw = Json.parse(source)
    if (!isMap(raw)) throw IllegalArgumentException("WASM runtime config must be a JSON object.")
    raw as Map<*, *>
    val e = (raw["exports"] as? Map<*, *>) ?: emptyMap<String, Any?>()
    fun s(v: Any?, d: String): String = if (v == null) d else jsString(v)
    return WasmVmConfig(
        wasmBase64 = raw["wasmBase64"]?.let { jsString(it) },
        wasmAssetPath = raw["wasmAssetPath"]?.let { jsString(it) },
        exports = WasmVmExports(
            memory = s(e["memory"], "memory"),
            alloc = s(e["alloc"], "alloc"),
            dealloc = s(e["dealloc"], "dealloc"),
            run = s(e["run"], "run"),
            callFunction = s(e["callFunction"], "call_function"),
            callFunctionWithInput = s(e["callFunctionWithInput"], "call_function_with_input"),
            getResultPtr = s(e["getResultPtr"], "get_result_ptr"),
            getResultLen = s(e["getResultLen"], "get_result_len"),
        ),
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
class WasmVm(machineId: String) : BaseClient(machineId) {
    private class WasmString(val ptr: Long, val length: Int)

    private var instance: WasmInstanceHandle? = null
    private var config: WasmVmConfig? = null
    private var bootCode: String? = null
    override val governor: HostSideGovernor = HostSideGovernor(machineId, true, GovernorHooks(onTerminate = { disposeNow() }))

    companion object {
        val isRuntimeAvailable: Boolean get() = platform().wasm != null

        suspend fun fromCode(machineId: String, code: String): WasmVm {
            val vm = WasmVm(machineId)
            vm.bootCode = code
            return vm
        }

        suspend fun fromAst(): WasmVm = throw IllegalStateException("WASM runtime expects JSON runtime config in `code`.")
    }

    override suspend fun setGlobalHostData(data: Map<String, Any?>) {
        globalHostData = LinkedHashMap(data)
    }

    override suspend fun run(): String {
        val code = bootCode
        if (code.isNullOrEmpty()) return ""
        ensureLoaded(code)
        governor.beginTurn()
        require(config!!.exports.run, emptyList())
        return readResult()
    }

    override suspend fun callFunction(funcName: String): String {
        assertLoaded()
        governor.beginTurn()
        val fn = writeString(funcName)
        try {
            require(config!!.exports.callFunction, listOf(fn.ptr, fn.length.toLong()))
            return readResult()
        } finally {
            dealloc(fn)
        }
    }

    override suspend fun callFunctionWithInput(funcName: String, inputJson: String): String {
        assertLoaded()
        governor.beginTurn()
        val fn = writeString(funcName)
        val input = writeString(inputJson)
        try {
            require(config!!.exports.callFunctionWithInput, listOf(fn.ptr, fn.length.toLong(), input.ptr, input.length.toLong()))
            return readResult()
        } finally {
            dealloc(fn)
            dealloc(input)
        }
    }

    private suspend fun ensureLoaded(configJson: String) {
        if (instance != null) return
        val engine = platform().wasm
            ?: throw IllegalStateException("WASM runtime unavailable: the platform provides no WebAssembly engine")
        val config = parseWasmConfig(configJson)
        val bytes = loadWasmBytes(config)
        this.config = config
        val inst = engine.instantiate(bytes) { _, name, args -> onImport(name, args) }
        instance = inst
        if (!inst.hasExport(config.exports.memory)) throw IllegalStateException("WASM memory export not found: ${config.exports.memory}")
    }

    private fun onImport(name: String, args: List<Long>): List<Long> {
        if (name != "elpian_host_call" || args.size < 6 || instance == null) return listOf(0L)
        val apiPtr = args[0]
        val apiLen = args[1]
        val payloadPtr = args[2]
        val payloadLen = args[3]
        val outPtr = args[4]
        val outCap = args[5]
        val apiName = readString(apiPtr, apiLen)
        val payload = readString(payloadPtr, payloadLen)
        return listOf(writeInto(dispatchHostCall(apiName, payload), outPtr, outCap).toLong())
    }

    private fun dispatchHostCall(apiName: String, payload: String): String {
        val refusal = governor.checkAndCharge(apiName, payload.length)
        if (refusal != null) {
            log("WasmVm[$machineId]: $apiName refused — $refusal")
            return Typed.NULL
        }
        val h = hostHandlers[apiName] ?: fallbackHostHandler
        if (h != null) {
            return when (val r = h(apiName, payload)) {
                is HostReply.Now -> r.value
                is HostReply.Later -> Typed.OK
            }
        }
        return builtin("WasmVm", apiName, payload)
    }

    private fun require(name: String, args: List<Long>): List<Long> {
        val inst = instance ?: throw IllegalStateException("WASM instance is not loaded.")
        if (!inst.hasExport(name)) throw IllegalStateException("WASM function export not found: $name")
        return inst.call(name, args)
    }

    private fun writeString(text: String): WasmString {
        val bytes = Bytes.utf8(text)
        val ptr = require(config!!.exports.alloc, listOf(bytes.size.toLong())).firstOrNull() ?: 0L
        if (ptr <= 0) throw IllegalStateException("WASM alloc returned invalid pointer for length ${bytes.size}.")
        val mem = config!!.exports.memory
        if (ptr + bytes.size > instance!!.memoryLength(mem)) throw IllegalStateException("WASM memory write out of range (ptr=$ptr len=${bytes.size}).")
        instance!!.memoryWrite(mem, ptr, bytes)
        return WasmString(ptr, bytes.size)
    }

    private fun writeInto(text: String, ptr: Long, capacity: Long): Int {
        if (capacity <= 0) return 0
        val bytes = Bytes.utf8(text)
        val length = min(bytes.size.toLong(), capacity).toInt()
        val mem = config!!.exports.memory
        if (ptr < 0 || ptr + length > instance!!.memoryLength(mem)) return 0
        instance!!.memoryWrite(mem, ptr, if (length == bytes.size) bytes else bytes.copyOf(length))
        return length
    }

    private fun readString(ptr: Long, len: Long): String {
        if (len <= 0) return ""
        val mem = config!!.exports.memory
        if (ptr < 0 || ptr + len > instance!!.memoryLength(mem)) return ""
        return Bytes.utf8(instance!!.memoryRead(mem, ptr, len.toInt()))
    }

    private fun readResult(): String {
        val ptr = require(config!!.exports.getResultPtr, emptyList()).firstOrNull() ?: 0L
        val len = require(config!!.exports.getResultLen, emptyList()).firstOrNull() ?: 0L
        if (ptr <= 0 || len <= 0) return ""
        return readString(ptr, len)
    }

    private fun dealloc(text: WasmString) {
        val name = config?.exports?.dealloc
        val inst = instance
        if (name.isNullOrEmpty() || inst == null || !inst.hasExport(name)) return
        inst.call(name, listOf(text.ptr, text.length.toLong()))
    }

    private fun assertLoaded() {
        if (instance == null || config == null) throw IllegalStateException("WASM runtime is not initialized. Call run() first.")
    }

    private fun disposeNow() {
        instance?.dispose()
        instance = null
        config = null
    }

    override suspend fun dispose() {
        disposeNow()
    }
}

/** The module bytes from the config: inline base64, or a bundled asset. */
suspend fun loadWasmBytes(config: WasmVmConfig): ByteArray {
    if (!config.wasmBase64.isNullOrEmpty()) return Bytes.base64(config.wasmBase64)
    if (config.wasmAssetPath.isNullOrEmpty()) throw IllegalStateException("WASM config must provide either `wasmBase64` or `wasmAssetPath`.")
    // Every Kotlin platform can load bundled assets (`Platform.loadAsset` is
    // mandatory), so the TS "This platform cannot load bundled assets." branch
    // has no counterpart here.
    return platform().loadAsset(config.wasmAssetPath)
}

// ============================================================================
// Factory
// ============================================================================

fun isRuntimeAvailable(kind: RuntimeKind): Boolean = when (kind) {
    RuntimeKind.ELPIAN -> ElpianVm.isRuntimeAvailable
    RuntimeKind.QUICKJS -> QuickJsVm.isRuntimeAvailable
    RuntimeKind.WASM -> WasmVm.isRuntimeAvailable
}

suspend fun initializeRuntime(kind: RuntimeKind) {
    if (kind == RuntimeKind.ELPIAN) ElpianVm.initialize()
}

/** Where a runtime's program comes from (`createRuntime`'s `source`). */
data class RuntimeSource(
    val code: String? = null,
    val astJson: String? = null,
    val bytecodeBase64: String? = null,
)

/**
 * Create a client from source the way `ElpianVmWidget` does: `code` (JS for
 * QuickJS, the JSON config for WASM, Elpian source for the VM) or an AST.
 */
suspend fun createRuntime(kind: RuntimeKind, machineId: String, source: RuntimeSource): VmRuntimeClient? = when (kind) {
    RuntimeKind.ELPIAN -> when {
        !source.bytecodeBase64.isNullOrEmpty() -> ElpianVm.fromBytecode(machineId, source.bytecodeBase64)
        !source.astJson.isNullOrEmpty() -> ElpianVm.fromAst(machineId, source.astJson)
        source.code != null -> ElpianVm.fromCode(machineId, source.code)
        else -> null
    }
    RuntimeKind.QUICKJS -> if (source.code == null) QuickJsVm.fromAst() else QuickJsVm.fromCode(machineId, source.code)
    RuntimeKind.WASM -> if (source.code == null) WasmVm.fromAst() else WasmVm.fromCode(machineId, source.code)
}
