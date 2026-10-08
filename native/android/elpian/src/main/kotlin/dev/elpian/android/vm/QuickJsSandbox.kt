package dev.elpian.android.vm

import app.cash.quickjs.QuickJs
import app.cash.quickjs.QuickJsException
import dev.elpian.core.util.Json
import dev.elpian.core.vm.JsSandbox
import dev.elpian.core.vm.JsSandboxFactory

/**
 * JS guests on an embedded QuickJS (`app.cash.quickjs:quickjs-android`): one
 * isolated [QuickJs] runtime + context per mini app, with
 * `__elpianHostCall(api, payload)` as the only way out — the same contract as
 * the web host's `WebQuickJs` (native/web/src/runtimes.ts).
 */
class QuickJsSandboxFactory : JsSandboxFactory {
    override fun create(machineId: String): JsSandbox = QuickJsSandbox(machineId)
}

/**
 * The Kotlin object behind `__elpianHostCall`. Bound with [QuickJs.set], which
 * exposes an interface's methods on a global object; must stay public with
 * String-only signatures (the binding's marshalling limits).
 */
interface ElpianJsHost {
    fun call(api: String, payload: String): String
}

class QuickJsSandbox(private val machineId: String) : JsSandbox {
    private var quickJs: QuickJs? = QuickJs.create()

    @Volatile
    private var handler: (String, String) -> String = { _, _ -> DEFAULT_REPLY }

    init {
        val js = quickJs!!
        js.set(HOST_OBJECT, ElpianJsHost::class.java, object : ElpianJsHost {
            override fun call(api: String, payload: String): String = try {
                handler(api, payload)
            } catch (_: Throwable) {
                NULL_REPLY
            }
        })
        js.evaluate(
            """globalThis.__elpianHostCall = function (api, payload) {
  try {
    return $HOST_OBJECT.call(String(api == null ? '' : api), String(payload == null ? '' : payload));
  } catch (e) {
    return '$NULL_REPLY';
  }
};""",
            "elpian-host.js",
        )
    }

    override fun setHostCallHandler(handler: (apiName: String, payload: String) -> String) {
        this.handler = handler
    }

    /**
     * Evaluate [code] as a global script; the completion value stringified as
     * the web host does: a string as is, `undefined` → `"undefined"`, anything
     * else as JSON.
     *
     * The binding only marshals primitives back to Java, so the completion
     * value is stringified inside the guest by running the code through an
     * indirect (global) `eval`. That is identical to a script except for
     * top-level `let` / `const` / `class` declarations, which `eval` keeps
     * local to the evaluation; code declaring them at top level is therefore
     * run as a real script, whose primitive completion value is formatted
     * here (an object completion value cannot cross and reads `undefined`).
     */
    override fun evaluate(code: String): String {
        val js = quickJs ?: return ""
        val file = "$machineId.js"
        try {
            if (TOP_LEVEL_LEXICAL.containsMatchIn(code)) {
                return format(js.evaluate(code, file))
            }
            val wrapped =
                "(function () { var v = (0, eval)(${Json.quote(code)}); " +
                    "if (typeof v === 'string') return v; if (v === undefined) return 'undefined'; " +
                    "var s = JSON.stringify(v); return s === undefined ? 'undefined' : s; })()"
            return format(js.evaluate(wrapped, file))
        } catch (e: QuickJsException) {
            throw IllegalStateException("QuickJS eval error: ${e.message}", e)
        }
    }

    override fun dispose() {
        val js = quickJs ?: return
        quickJs = null
        js.close()
    }

    private fun format(value: Any?): String = when (value) {
        null -> "undefined"
        is String -> value
        is Boolean -> if (value) "true" else "false"
        is Number -> Json.stringify(value)
        else -> value.toString()
    }

    private companion object {
        const val HOST_OBJECT = "__elpianHost"
        const val DEFAULT_REPLY = """{"type":"i16","data":{"value":0}}"""
        const val NULL_REPLY = """{"type":"null","data":{"value":null}}"""
        /** An unindented `let` / `const` / `class` statement: a top-level lexical declaration. */
        val TOP_LEVEL_LEXICAL = Regex("""(?m)^(let|const|class)\s""")
    }
}
