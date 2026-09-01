package dev.elpian.godot

import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot

/**
 * A Godot plugin registered with the embedded engine so the OpSink scene can
 * pull the 3D ops the Flutter side queued.
 *
 * Adapted from Victor's `ElpianGodotBridge`, minus the JNI hop: the queue is
 * plain Kotlin here (see [OpQueue]), so `pollOps` reads it directly.
 */
class ElpianGodotBridge(godot: Godot) : GodotPlugin(godot) {
    override fun getPluginName(): String = "ElpianGodotBridge"

    /** Drain this frame's ops as a JSON array (empty string when idle). */
    @UsedByGodot
    fun pollOps(): String = OpQueue.drain()

    /** The sink returns a reply for an op the Dart side is awaiting. */
    @UsedByGodot
    fun reply(requestId: Int, payload: String) = OpQueue.putReply(requestId, payload)

    /**
     * Diagnostics: the OpSink reports its built-scene summary here (~1/sec).
     * Surfaced through the plugin's `stats` method to diagnose a blank viewport.
     */
    @UsedByGodot
    fun report(summary: String) {
        lastReport = summary
    }

    companion object {
        @Volatile
        @JvmStatic
        var lastReport: String = ""
    }
}
