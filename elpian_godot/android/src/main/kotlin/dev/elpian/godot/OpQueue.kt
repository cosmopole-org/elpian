package dev.elpian.godot

import org.json.JSONArray

/**
 * The one shared point between the Flutter platform thread (which pushes ops)
 * and the Godot render thread (which drains them each frame).
 *
 * Victor's React Native port needed a C++/JNI queue because JSI is a C++ API.
 * Flutter's method channels arrive on the platform thread, so the queue can live
 * in Kotlin — the whole JNI layer drops out of the adaptation, which is one
 * fewer moving part and one fewer ABI to keep in step.
 *
 * Ops are enqueued fire-and-forget: handles are allocated on the Dart side, so
 * nothing blocks on the engine. Reads that genuinely need a value ([request])
 * park a reply slot the sink fills on its next drain.
 */
object OpQueue {
    private val lock = Any()
    private val pending = ArrayDeque<String>()

    // Diagnostics, surfaced through the `stats` channel method. If pushed > 0 but
    // polls == 0 the Godot side never ran its drain (the OpSink scene or the
    // GDExtension is not up) — that is the first thing to check on a blank
    // viewport.
    private var pushed = 0L
    private var polls = 0L
    private var drained = 0L

    /** Latest replies keyed by request id, filled by the sink. */
    private val replies = HashMap<Int, String>()

    /** Queue one JSON message (`{"op":…}`, `{"ops":[…]}`, `{"mount":…}`). */
    fun push(message: String) {
        synchronized(lock) {
            pending.addLast(message)
            pushed++
        }
    }

    /**
     * Drain everything queued, as a JSON array. Called by the Godot-side
     * [ElpianGodotBridge.pollOps] once per frame.
     *
     * Returns an empty string rather than "[]" when idle so the sink can skip
     * parsing entirely on the overwhelmingly common empty frame.
     */
    fun drain(): String {
        synchronized(lock) {
            polls++
            if (pending.isEmpty()) return ""
            val array = JSONArray()
            while (pending.isNotEmpty()) {
                array.put(org.json.JSONTokener(pending.removeFirst()).nextValue())
                drained++
            }
            return array.toString()
        }
    }

    /** The sink hands back a reply for a request the Dart side is awaiting. */
    fun putReply(requestId: Int, payload: String) {
        synchronized(lock) { replies[requestId] = payload }
    }

    /** Take a reply if it has arrived. */
    fun takeReply(requestId: Int): String? =
        synchronized(lock) { replies.remove(requestId) }

    fun stats(): Map<String, Any> = synchronized(lock) {
        mapOf(
            "pushed" to pushed,
            "polls" to polls,
            "drained" to drained,
            "queued" to pending.size,
            "awaiting" to replies.size,
        )
    }
}
