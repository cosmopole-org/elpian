package dev.elpian.android.vm

import com.dylibso.chicory.wasm.types.ValType
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ChicoryWasmEngineTest {
    /**
     * (module
     *   (import "env" "host" (func $host (param i32 i32) (result i32)))
     *   (memory (export "memory") 1)
     *   (func (export "add") (param i32 i32) (result i32) local.get 0 local.get 1 call $host)
     *   (func (export "neg") (param i32) (result i32) i32.const 0 local.get 0 i32.sub))
     */
    private val module = bytes(
        0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
        // types: (i32 i32)->i32, (i32)->i32
        0x01, 0x0c, 0x02, 0x60, 0x02, 0x7f, 0x7f, 0x01, 0x7f, 0x60, 0x01, 0x7f, 0x01, 0x7f,
        // import env.host : type 0
        0x02, 0x0c, 0x01, 0x03, 0x65, 0x6e, 0x76, 0x04, 0x68, 0x6f, 0x73, 0x74, 0x00, 0x00,
        // functions: type 0, type 1
        0x03, 0x03, 0x02, 0x00, 0x01,
        // memory: min 1 page
        0x05, 0x03, 0x01, 0x00, 0x01,
        // exports: memory, add (func 1), neg (func 2)
        0x07, 0x16, 0x03,
        0x06, 0x6d, 0x65, 0x6d, 0x6f, 0x72, 0x79, 0x02, 0x00,
        0x03, 0x61, 0x64, 0x64, 0x00, 0x01,
        0x03, 0x6e, 0x65, 0x67, 0x00, 0x02,
        // code
        0x0a, 0x12, 0x02,
        0x08, 0x00, 0x20, 0x00, 0x20, 0x01, 0x10, 0x00, 0x0b,
        0x07, 0x00, 0x41, 0x00, 0x20, 0x00, 0x6b, 0x0b,
    )

    @Test
    fun importsReachTheHandlerAndResultsComeBack() {
        val calls = mutableListOf<Triple<String, String, List<Long>>>()
        val inst = ChicoryWasmEngine().instantiate(module) { m, n, args ->
            calls.add(Triple(m, n, args))
            listOf(args[0] * 10 + args[1])
        }
        assertEquals(listOf(42L), inst.call("add", listOf(4L, 2L)))
        assertEquals(listOf(Triple("env", "host", listOf(4L, 2L))), calls)
        // i32 results are sign-extended, like a JS host's numbers.
        assertEquals(listOf(-7L), inst.call("neg", listOf(7L)))
        // A negative i32 argument reaches the import as the signed value.
        inst.call("add", listOf(-1L, 0L))
        assertEquals(listOf(-1L, 0L), calls.last().third)
    }

    @Test
    fun exportsAndMemory() {
        val inst = ChicoryWasmEngine().instantiate(module) { _, _, _ -> listOf(0L) }
        assertTrue(inst.hasExport("add"))
        assertTrue(inst.hasExport("memory"))
        assertFalse(inst.hasExport("missing"))
        assertEquals(65536L, inst.memoryLength("memory"))
        val data = "héllo".toByteArray()
        inst.memoryWrite("memory", 100, data)
        assertContentEquals(data, inst.memoryRead("memory", 100, data.size))
        // An unknown memory name falls back to the first exported memory.
        assertContentEquals(data, inst.memoryRead("mem", 100, data.size))
        assertFailsWith<IndexOutOfBoundsException> { inst.memoryRead("memory", 65530, 10) }
        assertFailsWith<IllegalStateException> { inst.call("memory", emptyList()) }
        inst.dispose()
        assertFalse(inst.hasExport("add"))
    }

    @Test
    fun floatValuesCrossAsNumbers() {
        assertEquals(3L, ChicoryWasmEngine.decode(ValType.F64, ChicoryWasmEngine.encode(ValType.F64, 3L)))
        assertEquals(-5L, ChicoryWasmEngine.decode(ValType.F32, ChicoryWasmEngine.encode(ValType.F32, -5L)))
        assertEquals(-1L, ChicoryWasmEngine.decode(ValType.I32, 0xffffffffL))
        assertEquals(Long.MIN_VALUE, ChicoryWasmEngine.decode(ValType.I64, Long.MIN_VALUE))
    }

    private fun bytes(vararg v: Int) = ByteArray(v.size) { v[it].toByte() }
}
