package dev.elpian.android.vm

import com.whl.quickjs.android.QuickJSLoader
import com.whl.quickjs.wrapper.JSCallFunction
import com.whl.quickjs.wrapper.JSFunction
import com.whl.quickjs.wrapper.JSObject
import com.whl.quickjs.wrapper.QuickJSContext
import dev.elpian.core.util.Json
import dev.elpian.core.util.jsString
import dev.elpian.core.vm.JsSandbox
import dev.elpian.core.vm.JsSandboxFactory

/**
 * JS guests on an embedded QuickJS (`wang.harlon.quickjs:wrapper-android`):
 * one isolated runtime + context per mini app, with
 * `__elpianHostCall(api, payload)` as the only way out — the contract of the
 * web host's `WebQuickJs` (native/web/src/runtimes.ts).
 *
 * A context is bound to the thread that created it; the core drives every
 * sandbox from its platform dispatcher (the UI thread).
 */
class QuickJsSandboxFactory : JsSandboxFactory {
    override fun create(machineId: String): JsSandbox {
        QuickJsLibrary.ensureLoaded()
        return QuickJsSandbox(machineId)
    }
}

internal object QuickJsLibrary {
    @Volatile private var loaded = false

    @Synchronized
    fun ensureLoaded() {
        if (loaded) return
        QuickJSLoader.init()
        loaded = true
    }
}

class QuickJsSandbox(private val machineId: String) : JsSandbox {
    private var context: QuickJSContext? = QuickJSContext.create()

    @Volatile
    private var handler: (String, String) -> String = { _, _ -> DEFAULT_REPLY }

    /** `(v) => string`: the web host's stringification of a completion value, run in the guest. */
    private val stringifyFn: JSFunction

    init {
        val ctx = context!!
        // `__elpianHostCall` coerces its arguments like the web host
        // (`String(dump(h) ?? '')`) and is the only binding the guest sees;
        // the native callback stays inside the installer's closure.
        val install = ctx.evaluate(
            """(function (native) {
  globalThis.__elpianHostCall = function (api, payload) {
    return native(api == null ? '' : String(api), payload == null ? '' : String(payload));
  };
})""",
            "elpian-host.js",
        ) as JSFunction
        try {
            install.call(
                JSCallFunction { args ->
                    try {
                        handler(arg(args, 0), arg(args, 1))
                    } catch (_: Throwable) {
                        NULL_REPLY
                    }
                },
            )
        } finally {
            install.release()
        }
        stringifyFn = ctx.evaluate(
            """(function (v) {
  if (typeof v === 'string') return v;
  if (v === undefined) return 'undefined';
  var s = JSON.stringify(v);
  return s === undefined ? 'undefined' : s;
})""",
            "elpian-stringify.js",
        ) as JSFunction
    }

    override fun setHostCallHandler(handler: (apiName: String, payload: String) -> String) {
        this.handler = handler
    }

    /**
     * Evaluate [code] as a global script and stringify its completion value as
     * the web host does: a string as is, `undefined` → `"undefined"`, anything
     * else `JSON.stringify`'d in the guest. Pending promise jobs run after
     * every evaluation, including a failed one; a failing job or an unhandled
     * rejection is the guest's problem, as on the web.
     */
    override fun evaluate(code: String): String {
        val ctx = context ?: return ""
        val value: Any? = try {
            ctx.evaluate(code, "$machineId.js")
        } catch (e: Throwable) {
            if (isJobFailure(e)) {
                // The script itself completed; only the job drain that follows
                // it reported a rejection. The completion value is gone with it.
                return "undefined"
            }
            runJobs(ctx)
            throw IllegalStateException("QuickJS eval error: ${e.message}", e)
        }
        return stringify(value)
    }

    override fun dispose() {
        val ctx = context ?: return
        context = null
        try {
            stringifyFn.release()
        } catch (_: Throwable) {
        }
        ctx.destroy()
    }

    // ---------------------------------------------------------------------

    /** A completion value as the binding marshalled it → the web host's string. */
    private fun stringify(value: Any?): String = when (value) {
        // JS null and undefined both arrive as Java null.
        null -> "undefined"
        is String -> value
        is Boolean -> if (value) "true" else "false"
        is Int, is Long -> value.toString()
        is Number -> Json.formatNumber(value.toDouble())
        // ArrayBuffer: JSON.stringify gives "{}".
        is ByteArray -> "{}"
        is JSObject -> try {
            stringifyFn.call(value) as? String ?: "undefined"
        } finally {
            value.release()
        }
        else -> value.toString()
    }

    /** Drain pending jobs (the binding runs them at the end of every call); failures are ignored. */
    private fun runJobs(ctx: QuickJSContext) {
        try {
            ctx.evaluate("void 0", "elpian-jobs.js")
        } catch (_: Throwable) {
        }
    }

    private fun isJobFailure(e: Throwable): Boolean = e.message?.startsWith(UNHANDLED_REJECTION) == true

    private fun arg(args: Array<out Any?>, i: Int): String {
        val v = args.getOrNull(i) ?: return ""
        return if (v is JSObject) {
            try {
                v.toString()
            } finally {
                v.release()
            }
        } else {
            jsString(v)
        }
    }

    private companion object {
        const val DEFAULT_REPLY = """{"type":"i16","data":{"value":0}}"""
        const val NULL_REPLY = """{"type":"null","data":{"value":null}}"""
        const val UNHANDLED_REJECTION = "UnhandledPromiseRejectionException"
    }
}
