package dev.elpian.godot

import android.content.Context
import android.util.Log
import android.view.View
import androidx.fragment.app.FragmentActivity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.json.JSONArray

/**
 * The Flutter side of the embedded-Godot seam.
 *
 * Registers three things, matching `GodotChannels` in `godot_binding.dart`:
 *
 *  * a **method channel** (`elpian/godot/ops`) taking `post` / `batch` /
 *    `mountSurface` / `releaseSurface` / `stats`;
 *  * an **event channel** (`elpian/godot/events`) delivering signal callbacks
 *    back to Dart;
 *  * a **platform view factory** (`elpian/godot/surface`) hosting the engine.
 *
 * Ops are enqueued on [OpQueue] and drained by the Godot render thread — never
 * applied synchronously, so a channel call never blocks on the engine.
 */
class ElpianGodotPlugin :
    FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {

    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private var activity: FragmentActivity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods = MethodChannel(binding.binaryMessenger, CHANNEL_OPS)
        methods.setMethodCallHandler(this)

        events = EventChannel(binding.binaryMessenger, CHANNEL_EVENTS)
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                eventSink = sink
                SignalRelay.sink = { cb, args -> emitSignal(cb, args) }
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
                SignalRelay.sink = null
            }
        })

        binding.platformViewRegistry.registerViewFactory(
            VIEW_TYPE,
            GodotSurfaceFactory { activity },
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        SignalRelay.sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Fire-and-forget: the overwhelmingly common path.
            "post" -> {
                val json = call.arguments as? String
                if (json != null) OpQueue.push("""{"ops":$json}""")
                result.success(null)
            }

            // A batch whose replies the caller awaits. The engine answers on its
            // next frame, so park the request and let the sink fill it in.
            "batch" -> {
                val json = call.arguments as? String
                if (json == null) {
                    result.success("[]")
                    return
                }
                val id = nextRequestId++
                OpQueue.push("""{"ops":$json,"req":$id}""")
                awaitReply(id, result)
            }

            "mountSurface" -> {
                val surfaceId = call.argument<Int>("surfaceId") ?: 0
                val mountNode = call.argument<Int>("mountNode") ?: 0
                OpQueue.push("""{"mount":$surfaceId,"node":$mountNode}""")
                result.success(null)
            }

            "releaseSurface" -> {
                val surfaceId = call.argument<Int>("surfaceId") ?: 0
                OpQueue.push("""{"release":$surfaceId}""")
                result.success(null)
            }

            "stats" -> result.success(
                OpQueue.stats() + mapOf("report" to ElpianGodotBridge.lastReport)
            )

            else -> result.notImplemented()
        }
    }

    /**
     * Poll for a reply the Godot thread will produce, then answer the Dart call.
     *
     * A read is rare (creates and writes need no reply), so a short poll is
     * cheaper and far simpler than threading a completion across the JNI
     * boundary. Gives up after [REPLY_TIMEOUT_MS] rather than wedging the caller
     * when the engine is not running at all.
     */
    private fun awaitReply(requestId: Int, result: MethodChannel.Result) {
        val deadline = System.currentTimeMillis() + REPLY_TIMEOUT_MS
        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        val poll = object : Runnable {
            override fun run() {
                val reply = OpQueue.takeReply(requestId)
                if (reply != null) {
                    result.success(reply)
                    return
                }
                if (System.currentTimeMillis() > deadline) {
                    // Not an error: the surface may simply have no engine yet.
                    result.success("[]")
                    return
                }
                handler.postDelayed(this, REPLY_POLL_MS)
            }
        }
        handler.postDelayed(poll, REPLY_POLL_MS)
    }

    private fun emitSignal(callbackId: Int, argsJson: String) {
        val sink = eventSink ?: return
        val args = try {
            JSONArray(argsJson).let { array ->
                (0 until array.length()).map { array.get(it) }
            }
        } catch (_: Throwable) {
            emptyList<Any>()
        }
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            sink.success(mapOf("cb" to callbackId, "args" to args))
        }
    }

    // ActivityAware — the Godot fragment needs a FragmentActivity to attach to.
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity as? FragmentActivity
        if (activity == null) {
            Log.w(
                TAG,
                "host activity is not a FragmentActivity; Scene3D will show its " +
                    "placeholder. Make MainActivity extend FlutterFragmentActivity.",
            )
        }
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    companion object {
        private const val TAG = "ElpianGodot"
        const val CHANNEL_OPS = "elpian/godot/ops"
        const val CHANNEL_EVENTS = "elpian/godot/events"
        const val VIEW_TYPE = "elpian/godot/surface"
        private const val REPLY_TIMEOUT_MS = 2000L
        private const val REPLY_POLL_MS = 16L
        private var nextRequestId = 1
    }
}

/** Where the Godot side hands signal callbacks back to the plugin. */
object SignalRelay {
    @Volatile
    var sink: ((Int, String) -> Unit)? = null

    /** Called from [ElpianGodotBridge] when the engine fires a connected signal. */
    fun dispatch(callbackId: Int, argsJson: String) {
        sink?.invoke(callbackId, argsJson)
    }
}

/** Creates the platform view that hosts the engine viewport. */
private class GodotSurfaceFactory(
    private val activityProvider: () -> FragmentActivity?,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?> ?: emptyMap()
        val surfaceId = (params["surfaceId"] as? Number)?.toInt() ?: 0
        return GodotSurfaceView(context, surfaceId, activityProvider())
    }
}

/**
 * The platform view Flutter composites where a `Scene3D` sits. The Godot
 * fragment is attached into it once it is in the window.
 */
private class GodotSurfaceView(
    context: Context,
    private val surfaceId: Int,
    private val activity: FragmentActivity?,
) : PlatformView {

    private val container = android.widget.FrameLayout(context).apply {
        id = View.generateViewId()
    }

    private var attached = false

    init {
        container.addOnAttachStateChangeListener(
            object : View.OnAttachStateChangeListener {
                override fun onViewAttachedToWindow(v: View) = attach()
                override fun onViewDetachedFromWindow(v: View) = Unit
            },
        )
    }

    private fun attach() {
        if (attached) return
        val host = activity ?: run {
            Log.w("ElpianGodot", "no FragmentActivity; cannot host Godot")
            return
        }
        attached = true
        try {
            host.supportFragmentManager
                .beginTransaction()
                .replace(container.id, ElpianGodotFragment(), "elpian-godot-$surfaceId")
                .commitAllowingStateLoss()
        } catch (t: Throwable) {
            Log.e("ElpianGodot", "failed to attach GodotFragment", t)
        }
    }

    override fun getView(): View = container

    override fun dispose() {
        OpQueue.push("""{"release":$surfaceId}""")
    }
}
