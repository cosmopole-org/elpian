package dev.elpian.android.godot

import android.content.Context
import android.content.ContextWrapper
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.fragment.app.Fragment
import androidx.fragment.app.FragmentActivity
import dev.elpian.core.platform.GodotPlatformBinding
import dev.elpian.core.util.Json
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull
import java.lang.reflect.Method

/** Where the renderer hosts a `Scene3D` surface's engine viewport. */
fun interface GodotSurfaceHost {
    /** The view group laid out where surface [surfaceId] sits, or null when it is not on screen. */
    fun surfaceContainer(surfaceId: Int): ViewGroup?
}

/**
 * The embedded Godot 4 engine as the Scene3D backend — the same op-queue
 * protocol as the Flutter plugin (godot/android: `OpQueue`,
 * `ElpianGodotBridge`, `ElpianGodotFragment`), whose sources this module
 * compiles in when Godot is enabled (see elpian/build.gradle.kts):
 *
 *  - `{"ops":[…]}` fire-and-forget batches, `{"ops":[…],"req":n}` batches whose
 *    results the OpSink scene hands back through `ElpianGodotBridge.reply`;
 *  - `{"mount":surfaceId,"node":handle}` / `{"release":surfaceId}`;
 *  - the OpSink drains the queue once per engine frame (`pollOps`).
 *
 * The engine classes are reached by reflection, so this compiles and runs
 * without the Godot library: [isLive] is then false and the core shows the
 * Scene3D placeholder. Awaited replies time out after [REPLY_TIMEOUT_MS] with
 * one `null` per op, like the web host (native/web/src/godot.ts).
 */
class AndroidGodotBinding(private val surfaceHost: GodotSurfaceHost) : GodotPlatformBinding {

    private val queue: QueueAccess? = QueueAccess.load()
    private val engineClasses: Boolean = classExists("org.godotengine.godot.Godot") && classExists(FRAGMENT_CLASS)
    private val main = Handler(Looper.getMainLooper())

    @Volatile private var nextRequest = 1
    @Volatile private var signalHandler: ((Long, String) -> Unit)? = null
    private val awaiting = java.util.concurrent.atomic.AtomicInteger(0)
    private val mounted = HashMap<Int, Mounted>()

    private class Mounted(val frame: FrameLayout, val fragment: Any)

    override val isLive: Boolean get() = queue != null && engineClasses

    override fun post(opsJson: String) {
        queue?.push("""{"ops":$opsJson}""")
    }

    override suspend fun send(opsJson: String): String {
        val count = (Json.parseOrNull(opsJson) as? List<*>)?.size ?: 0
        val timedOut = Json.stringify(List(count) { null })
        val q = queue ?: return timedOut
        val id = synchronized(this) { nextRequest++ }
        awaiting.incrementAndGet()
        try {
            q.push("""{"ops":$opsJson,"req":$id}""")
            // A reply that never arrives must not wedge the caller.
            val reply = withTimeoutOrNull(REPLY_TIMEOUT_MS) {
                var r: String? = q.takeReply(id)
                while (r == null) {
                    delay(REPLY_POLL_MS)
                    r = q.takeReply(id)
                }
                r
            } ?: return timedOut
            return if (Json.parseOrNull(reply) is List<*>) reply else "[]"
        } finally {
            awaiting.decrementAndGet()
        }
    }

    override fun mountSurface(surfaceId: Int, mountHandle: Long) {
        queue?.push(Json.stringify(linkedMapOf("mount" to surfaceId, "node" to mountHandle)))
        if (isLive) onMain { attach(surfaceId) }
    }

    override fun releaseSurface(surfaceId: Int) {
        queue?.push(Json.stringify(linkedMapOf("release" to surfaceId)))
        if (isLive) onMain { detach(surfaceId) }
    }

    override fun setSignalHandler(handler: ((callbackId: Long, argsJson: String) -> Unit)?) {
        signalHandler = handler
    }

    /**
     * Hand a connected signal's callback to the core. The engine-side relay
     * (the Flutter plugin's `SignalRelay`) has no sender in the OpSink yet; a
     * bridge that reports signals calls this.
     */
    fun deliverSignal(callbackId: Long, argsJson: String) {
        val h = signalHandler ?: return
        onMain { h(callbackId, argsJson) }
    }

    override suspend fun stats(): Map<String, Any?> {
        val out = LinkedHashMap<String, Any?>()
        queue?.stats()?.let { out.putAll(it) }
        out["awaiting"] = awaiting.get()
        out["live"] = isLive
        out["report"] = queue?.lastReport() ?: ""
        return out
    }

    // ---- the engine viewport ------------------------------------------------

    private fun attach(surfaceId: Int) {
        if (mounted.containsKey(surfaceId)) return
        val container = surfaceHost.surfaceContainer(surfaceId) ?: run {
            Log.w(TAG, "no container for Godot surface $surfaceId")
            return
        }
        val activity = findActivity(container.context) ?: run {
            Log.w(TAG, "the host activity is not a FragmentActivity; Scene3D cannot host Godot")
            return
        }
        try {
            val frame = FrameLayout(container.context).apply { id = View.generateViewId() }
            container.addView(frame, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
            val fragment = Class.forName(FRAGMENT_CLASS).getDeclaredConstructor().newInstance() as Fragment
            activity.supportFragmentManager.beginTransaction()
                .replace(frame.id, fragment, "elpian-godot-$surfaceId")
                .commitAllowingStateLoss()
            mounted[surfaceId] = Mounted(frame, fragment)
        } catch (t: Throwable) {
            Log.e(TAG, "failed to attach the Godot fragment", t)
        }
    }

    private fun detach(surfaceId: Int) {
        val m = mounted.remove(surfaceId) ?: return
        try {
            val activity = findActivity(m.frame.context)
            if (activity != null && !activity.supportFragmentManager.isDestroyed) {
                activity.supportFragmentManager.beginTransaction().remove(m.fragment as Fragment).commitAllowingStateLoss()
            }
        } catch (t: Throwable) {
            Log.e(TAG, "failed to detach the Godot fragment", t)
        }
        (m.frame.parent as? ViewGroup)?.removeView(m.frame)
    }

    private fun onMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) block() else main.post(block)
    }

    /** The op queue and bridge of godot/android, by reflection. */
    private class QueueAccess(
        private val instance: Any,
        private val push: Method,
        private val takeReply: Method,
        private val stats: Method,
        private val lastReport: Method?,
    ) {
        fun push(message: String) {
            push.invoke(instance, message)
        }

        fun takeReply(id: Int): String? = takeReply.invoke(instance, id) as String?

        @Suppress("UNCHECKED_CAST")
        fun stats(): Map<String, Any?> = (stats.invoke(instance) as? Map<String, Any?>) ?: emptyMap()

        fun lastReport(): String = (lastReport?.invoke(null) as? String) ?: ""

        companion object {
            fun load(): QueueAccess? = try {
                val cls = Class.forName(QUEUE_CLASS)
                val instance = cls.getField("INSTANCE").get(null)!!
                val report = try {
                    Class.forName(BRIDGE_CLASS).getMethod("getLastReport")
                } catch (_: Throwable) {
                    null
                }
                QueueAccess(
                    instance,
                    cls.getMethod("push", String::class.java),
                    cls.getMethod("takeReply", Int::class.javaPrimitiveType),
                    cls.getMethod("stats"),
                    report,
                )
            } catch (_: Throwable) {
                null
            }
        }
    }

    companion object {
        private const val TAG = "ElpianGodot"
        const val REPLY_TIMEOUT_MS = 2000L
        private const val REPLY_POLL_MS = 16L
        private const val QUEUE_CLASS = "dev.elpian.godot.OpQueue"
        private const val BRIDGE_CLASS = "dev.elpian.godot.ElpianGodotBridge"
        private const val FRAGMENT_CLASS = "dev.elpian.godot.ElpianGodotFragment"

        private fun classExists(name: String): Boolean = try {
            Class.forName(name, false, AndroidGodotBinding::class.java.classLoader)
            true
        } catch (_: Throwable) {
            false
        }

        private fun findActivity(context: Context): FragmentActivity? {
            var c: Context? = context
            while (c != null) {
                if (c is FragmentActivity) return c
                c = (c as? ContextWrapper)?.baseContext
            }
            return null
        }
    }
}
