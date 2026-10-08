package dev.elpian.android.vm

import dev.elpian.core.util.Json
import dev.elpian.core.vm.ElpianVmBinding

/**
 * [ElpianVmBinding] over the Rust runtime's JNI bridge ([ElpianVmNative]).
 *
 * Every method goes through the by-name dispatcher, so the JSON shapes, panic
 * containment and error slot are exactly those of a C caller. When the
 * library cannot be loaded the binding reports unavailable, the boolean calls
 * answer false and the execution calls answer the `native_lib_not_loaded`
 * error result in the same shape as the core's own (vm/Runtime.kt).
 */
class AndroidElpianVm(private val native: ElpianVmNative = ElpianVmNative) : ElpianVmBinding {

    override fun isAvailable(): Boolean = native.isLoaded

    override fun lastError(): String? {
        if (!native.isLoaded) return native.loadError
        val e = try {
            native.nativeLastError()
        } catch (t: Throwable) {
            return t.toString()
        }
        return e.ifEmpty { null }
    }

    override fun init() {
        if (native.isLoaded) call("elpian_init", emptyList())
    }

    override fun createFromAst(machineId: String, astJson: String): Boolean = flag("elpian_create_vm_from_ast", machineId, astJson)

    override fun createFromCode(machineId: String, code: String): Boolean = flag("elpian_create_vm_from_code", machineId, code)

    override fun createFromBytecode(machineId: String, bytecode: ByteArray): Boolean =
        native.isLoaded && native.nativeCreateFromBytecode(machineId, bytecode)

    override fun validateAst(astJson: String): Boolean = flag("elpian_validate_ast", astJson)

    override fun execute(machineId: String): String = result("elpian_execute", machineId)

    override fun executeFunc(machineId: String, funcName: String, cbId: Long): String =
        result("elpian_execute_func", machineId, funcName, cbId)

    override fun executeFuncWithInput(machineId: String, funcName: String, inputJson: String, cbId: Long): String =
        result("elpian_execute_func_with_input", machineId, funcName, inputJson, cbId)

    override fun continueExecution(machineId: String, inputJson: String): String =
        result("elpian_continue_execution", machineId, inputJson)

    override fun deliverHostMessage(machineId: String, messageJson: String, cbId: Long): String =
        result("elpian_deliver_host_message", machineId, messageJson, cbId)

    override fun destroy(machineId: String): Boolean = flag("elpian_destroy_vm", machineId)

    override fun exists(machineId: String): Boolean = flag("elpian_vm_exists", machineId)

    override fun governance(symbol: String, args: List<Any>): String? {
        if (!native.isLoaded) return null
        return call(symbol, args)
    }

    // ---------------------------------------------------------------------

    private fun call(symbol: String, args: List<Any?>): String? = native.nativeCall(symbol, Json.stringify(args))

    private fun flag(symbol: String, vararg args: Any): Boolean = native.isLoaded && call(symbol, args.toList()) == "true"

    private fun result(symbol: String, vararg args: Any): String {
        if (!native.isLoaded) return errorResult("native_lib_not_loaded")
        return call(symbol, args.toList()) ?: errorResult("missing_export:$symbol")
    }

    private fun errorResult(reason: String): String =
        Json.stringify(linkedMapOf("hasHostCall" to false, "hostCallData" to "", "resultValue" to Json.stringify(linkedMapOf("error" to reason))))
}
