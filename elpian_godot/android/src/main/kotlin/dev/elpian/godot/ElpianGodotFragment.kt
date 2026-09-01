package dev.elpian.godot

import android.content.Context
import org.godotengine.godot.Godot
import org.godotengine.godot.GodotFragment
import org.godotengine.godot.plugin.GodotPlugin
import java.io.File

/**
 * The embedded Godot engine as an Android Fragment. Loads the op-sink project
 * (`embed.pck`, shipped in assets) via `--main-pack` and registers
 * [ElpianGodotBridge] so the OpSink scene can pull queued ops.
 *
 * Ported from Victor unchanged in substance — this part of the design is
 * host-agnostic.
 */
class ElpianGodotFragment : GodotFragment() {

    override fun getCommandLine(): MutableList<String> {
        val ctx = context ?: return mutableListOf()
        return mutableListOf("--main-pack", extractPck(ctx).absolutePath)
    }

    override fun getHostPlugins(engine: Godot): MutableSet<GodotPlugin> =
        mutableSetOf(ElpianGodotBridge(engine))

    companion object {
        /**
         * Godot reads `--main-pack` from the filesystem, not from APK assets, so
         * copy the packed project out to the app's files dir.
         *
         * ALWAYS overwrite: `filesDir` survives an install-over, so a conditional
         * copy risks serving a stale pck from a previous build forever. The pck is
         * a few KB — copying every launch is negligible and removes the doubt.
         */
        private fun extractPck(ctx: Context): File {
            val out = File(ctx.filesDir, "elpian-embed.pck")
            ctx.assets.open("godot/embed.pck").use { input ->
                out.outputStream().use { input.copyTo(it) }
            }
            return out
        }
    }
}
