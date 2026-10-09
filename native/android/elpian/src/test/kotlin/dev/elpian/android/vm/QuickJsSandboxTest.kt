package dev.elpian.android.vm

import org.junit.Assume.assumeTrue
import org.junit.BeforeClass
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/**
 * The QuickJS sandbox on the JVM. The published wrapper ships Android
 * libraries only, so these run when `ELPIAN_QUICKJS_JVM_LIB` points at a host
 * build of the same wrapper (HarlonWang/quickjs-wrapper at the pinned tag,
 * `wrapper-java/src/main/CMakeLists.txt` → `libquickjs-java-wrapper.so`), and
 * are skipped otherwise.
 */
class QuickJsSandboxTest {
    companion object {
        private var loaded = false

        @BeforeClass
        @JvmStatic
        fun load() {
            val path = System.getenv("ELPIAN_QUICKJS_JVM_LIB") ?: return
            if (!File(path).isFile) return
            System.load(path)
            loaded = true
        }
    }

    private fun sandbox(): QuickJsSandbox {
        assumeTrue("ELPIAN_QUICKJS_JVM_LIB not set", loaded)
        return QuickJsSandbox("test")
    }

    @Test
    fun completionValuesAreStringifiedLikeTheWebHost() {
        val js = sandbox()
        assertEquals("2", js.evaluate("1 + 1"))
        assertEquals("1.5", js.evaluate("1.5"))
        assertEquals("hi", js.evaluate("'hi'"))
        assertEquals("true", js.evaluate("true"))
        assertEquals("""{"a":1,"b":[1,"x",null]}""", js.evaluate("({a: 1, b: [1, 'x', null]})"))
        assertEquals("""[1,2]""", js.evaluate("[1, 2]"))
        assertEquals("undefined", js.evaluate("undefined"))
        assertEquals("undefined", js.evaluate("var x = 5"))
        assertEquals("undefined", js.evaluate("(function () {})"))
        js.dispose()
    }

    @Test
    fun topLevelLexicalDeclarationsAreGlobalAndObjectsSurvive() {
        val js = sandbox()
        assertEquals("""{"v":3}""", js.evaluate("const k = {v: 3};\nclass C { m() { return k.v * 2; } }\nk"))
        assertEquals("3", js.evaluate("k.v"))
        assertEquals("6", js.evaluate("new C().m()"))
        assertEquals("""{"n":6}""", js.evaluate("function f() { return {n: new C().m()}; }\nf();"))
        js.dispose()
    }

    @Test
    fun hostCallsReachTheHandler() {
        val js = sandbox()
        val seen = mutableListOf<Pair<String, String>>()
        js.setHostCallHandler { api, payload ->
            seen.add(api to payload)
            """{"echo":"$api"}"""
        }
        assertEquals("""{"echo":"ping"}""", js.evaluate("__elpianHostCall('ping', JSON.stringify({x: 1}))"))
        assertEquals("""{"echo":""}""", js.evaluate("__elpianHostCall(undefined, 42)"))
        assertEquals(listOf("ping" to """{"x":1}""", "" to "42"), seen)
        js.setHostCallHandler { _, _ -> error("boom") }
        assertEquals("""{"type":"null","data":{"value":null}}""", js.evaluate("__elpianHostCall('a', 'b')"))
        js.dispose()
    }

    @Test
    fun pendingJobsRunAfterEveryEvaluationIncludingFailedOnes() {
        val js = sandbox()
        assertEquals("0", js.evaluate("globalThis.r = 0; Promise.resolve().then(() => { r = 7; }); r"))
        assertEquals("7", js.evaluate("r"))
        val e = assertFailsWith<IllegalStateException> {
            js.evaluate("Promise.resolve().then(() => { globalThis.q = 1; }); throw new Error('boom');")
        }
        assertTrue(e.message!!.contains("boom"), e.message)
        assertEquals("1", js.evaluate("q"))
        js.dispose()
    }

    /** The two documented gaps: JS null arrives as Java null, and an unhandled rejection costs the completion value. */
    @Test
    fun knownMarshallingLimits() {
        val js = sandbox()
        assertEquals("undefined", js.evaluate("null"))
        assertEquals("""{"v":null}""", js.evaluate("({v: null})"))
        assertEquals("undefined", js.evaluate("Promise.reject(new Error('x')); 5"))
        assertEquals("5", js.evaluate("5"))
        js.dispose()
    }

    @Test
    fun guestErrorsThrow() {
        val js = sandbox()
        val e = assertFailsWith<IllegalStateException> { js.evaluate("nope()") }
        assertTrue(e.message!!.startsWith("QuickJS eval error:"), e.message)
        assertFailsWith<IllegalStateException> { js.evaluate("let = = 1") }
        js.dispose()
        assertEquals("", js.evaluate("1"))
    }
}
