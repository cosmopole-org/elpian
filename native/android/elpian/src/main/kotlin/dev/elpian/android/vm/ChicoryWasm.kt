package dev.elpian.android.vm

import com.dylibso.chicory.runtime.HostFunction
import com.dylibso.chicory.runtime.ImportValues
import com.dylibso.chicory.runtime.Instance
import com.dylibso.chicory.runtime.Memory
import com.dylibso.chicory.wasm.Parser
import com.dylibso.chicory.wasm.types.ExternalType
import com.dylibso.chicory.wasm.types.FunctionImport
import com.dylibso.chicory.wasm.types.FunctionType
import com.dylibso.chicory.wasm.types.ValType
import com.dylibso.chicory.wasm.types.Value
import dev.elpian.core.vm.WasmEngine
import dev.elpian.core.vm.WasmImportHandler
import dev.elpian.core.vm.WasmInstanceHandle

/**
 * WASM guests on Chicory, a pure-JVM WebAssembly interpreter — no native code,
 * so it runs unchanged on every ABI and in JVM unit tests.
 *
 * Mirrors the web host's `WebWasmEngine` (native/web/src/runtimes.ts): every
 * function import is bound to the core's handler, non-function imports are
 * left to the module, and memory is addressed by export name with a fallback
 * to the first exported memory.
 *
 * Values cross as the numbers they denote, as a JS host would see them: i32 is
 * sign-extended, i64 passes through, and f32 / f64 are converted to and from
 * their numeric value (truncated to an integer, since the handler's numbers
 * are longs).
 */
class ChicoryWasmEngine : WasmEngine {
    override fun instantiate(bytes: ByteArray, onImport: WasmImportHandler): WasmInstanceHandle {
        val module = Parser.parse(bytes)
        val imports = ImportValues.builder()
        val section = module.importSection()
        for (i in 0 until section.importCount()) {
            val imp = section.getImport(i)
            if (imp.importType() != ExternalType.FUNCTION || imp !is FunctionImport) continue
            val type = module.typeSection().getType(imp.typeIndex())
            val moduleName = imp.module()
            val name = imp.name()
            imports.addFunction(
                HostFunction(moduleName, name, type) { _, args ->
                    val decoded = ArrayList<Long>(args.size)
                    for (j in args.indices) decoded.add(decode(type.params()[j], args[j]))
                    val out = onImport(moduleName, name, decoded)
                    val returns = type.returns()
                    LongArray(returns.size) { k -> encode(returns[k], out.getOrElse(k) { 0L }) }
                },
            )
        }
        val instance = Instance.builder(module).withImportValues(imports.build()).build()
        return ChicoryInstance(instance)
    }

    internal companion object {
        /** A raw Chicory slot → the number it denotes. */
        fun decode(type: ValType, raw: Long): Long = when (type) {
            ValType.I32 -> raw.toInt().toLong()
            ValType.F32 -> Value.longToFloat(raw).toLong()
            ValType.F64 -> Value.longToDouble(raw).toLong()
            else -> raw
        }

        /** A number → the raw Chicory slot for [type]. */
        fun encode(type: ValType, value: Long): Long = when (type) {
            ValType.I32 -> value.toInt().toLong()
            ValType.F32 -> Value.floatToLong(value.toFloat())
            ValType.F64 -> Value.doubleToLong(value.toDouble())
            else -> value
        }
    }
}

private class ChicoryInstance(private var instance: Instance?) : WasmInstanceHandle {
    private val exportTypes: Map<String, ExternalType>
    private val functionTypes = HashMap<String, FunctionType>()

    init {
        val section = instance!!.module().exportSection()
        val map = LinkedHashMap<String, ExternalType>()
        for (i in 0 until section.exportCount()) {
            val e = section.getExport(i)
            map[e.name()] = e.exportType()
        }
        exportTypes = map
    }

    private fun live(): Instance = instance ?: throw IllegalStateException("WASM instance is disposed.")

    override fun hasExport(name: String): Boolean = instance != null && exportTypes.containsKey(name)

    override fun call(exportName: String, args: List<Long>): List<Long> {
        val inst = live()
        if (exportTypes[exportName] != ExternalType.FUNCTION) throw IllegalStateException("WASM function export not found: $exportName")
        val type = functionTypes.getOrPut(exportName) { inst.exportType(exportName) }
        val params = type.params()
        val raw = LongArray(params.size) { i -> ChicoryWasmEngine.encode(params[i], args.getOrElse(i) { 0L }) }
        val out = inst.export(exportName).apply(*raw) ?: return emptyList()
        val returns = type.returns()
        return List(minOf(out.size, returns.size)) { i -> ChicoryWasmEngine.decode(returns[i], out[i]) }
    }

    private fun memory(name: String): Memory {
        val inst = live()
        if (exportTypes[name] == ExternalType.MEMORY) return inst.exports().memory(name)
        val any = exportTypes.entries.firstOrNull { it.value == ExternalType.MEMORY }
            ?: throw IllegalStateException("WASM memory export not found: $name")
        return inst.exports().memory(any.key)
    }

    override fun memoryLength(memoryExport: String): Long = memory(memoryExport).pages().toLong() * Memory.PAGE_SIZE

    override fun memoryRead(memoryExport: String, ptr: Long, length: Int): ByteArray {
        val mem = memory(memoryExport)
        checkRange(mem, ptr, length.toLong())
        return mem.readBytes(ptr.toInt(), length)
    }

    override fun memoryWrite(memoryExport: String, ptr: Long, bytes: ByteArray) {
        val mem = memory(memoryExport)
        checkRange(mem, ptr, bytes.size.toLong())
        mem.write(ptr.toInt(), bytes)
    }

    private fun checkRange(mem: Memory, ptr: Long, length: Long) {
        val size = mem.pages().toLong() * Memory.PAGE_SIZE
        if (ptr < 0 || length < 0 || ptr + length > size) throw IndexOutOfBoundsException("WASM memory access out of range (ptr=$ptr len=$length size=$size)")
    }

    override fun dispose() {
        instance = null
        functionTypes.clear()
    }
}
