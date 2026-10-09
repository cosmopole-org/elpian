package dev.elpian.android

import android.content.ComponentCallbacks2
import android.content.Context
import android.content.res.Configuration
import dev.elpian.android.godot.AndroidGodotBinding
import dev.elpian.android.godot.GodotSurfaceHost
import dev.elpian.android.platform.AndroidPlatform
import dev.elpian.android.vm.AndroidElpianVm
import dev.elpian.android.vm.ChicoryWasmEngine
import dev.elpian.android.vm.QuickJsSandboxFactory
import dev.elpian.core.bridge.SessionRegistry
import dev.elpian.core.platform.Platforms

/** Which engines and services the Android host installs. */
data class ElpianOptions(
    /** Prefix for SharedPreferences keys (per-app storage isolation). */
    val storagePrefix: String = "",
    /** The deep link / app URL reported to mini apps. */
    val href: String? = null,
    /** The Elpian VM (`libelpian_vm.so`, see scripts/build-rust.sh). */
    val elpianVm: Boolean = true,
    /** QuickJS guests (JavaScript mini apps). */
    val quickJs: Boolean = true,
    /** WebAssembly guests (Chicory). */
    val wasm: Boolean = true,
    /** Godot `Scene3D` (live when the Godot engine is bundled, see godot/README.md). */
    val godot: Boolean = true,
)

/**
 * The Android host of Elpian mini apps: the Kotlin core (`dev.elpian.core`)
 * laid out and rendered to native Views, with the Elpian VM, QuickJS, WASM
 * and Godot engines. No JavaScript glue — JS only runs inside QuickJS guests.
 *
 *     Elpian.install(context)
 *     val view = ElpianHostView(context)
 *     view.open("miniapp", mapOf("runtime" to "quickjs", "code" to code, "entryFunction" to "main"))
 *     view.on("println") { println(it) }
 */
object Elpian {
    val coreVersion: String get() = dev.elpian.core.ElpianCore.VERSION

    private var platform_: AndroidPlatform? = null
    private var registry_: SessionRegistry? = null
    private val hosts = HashMap<String, ElpianHostView>()
    private var nextSurface = 1

    val isInstalled: Boolean get() = platform_ != null

    /** The installed platform (installing with defaults on first use). */
    fun platform(context: Context): AndroidPlatform = install(context)

    internal val registry: SessionRegistry get() = registry_ ?: error("Elpian.install(context) has not been called")

    /** Install the Android platform once (idempotent; must run on the main thread). */
    @Synchronized
    fun install(context: Context, options: ElpianOptions = ElpianOptions()): AndroidPlatform {
        platform_?.let { return it }
        lateinit var platform: AndroidPlatform
        val godot = if (options.godot) AndroidGodotBinding(GodotSurfaceHost { platform.godotSurfaceContainer(it) }) else null
        platform = AndroidPlatform(
            context,
            godot = godot,
            elpianVm = if (options.elpianVm) AndroidElpianVm() else null,
            jsSandbox = if (options.quickJs) QuickJsSandboxFactory() else null,
            wasm = if (options.wasm) ChicoryWasmEngine() else null,
            storagePrefix = options.storagePrefix,
            href = options.href,
        )
        Platforms.install(platform)
        val registry = SessionRegistry { surface, event, payload -> hosts[surface]?.deliver(event, payload) }
        platform.onImageLoaded { src, w, h -> registry.imageLoaded(src, w.toDouble(), h.toDouble()) }
        platform.context.registerComponentCallbacks(object : ComponentCallbacks2 {
            private var fontScale = context.resources.configuration.fontScale
            override fun onConfigurationChanged(newConfig: Configuration) {
                if (newConfig.fontScale != fontScale) {
                    fontScale = newConfig.fontScale
                    platform.invalidateText()
                    registry.invalidateText()
                }
                for (id in hosts.keys) registry.viewportChanged(id)
            }
            @Deprecated("Deprecated in Java")
            override fun onLowMemory() = platform.images.trim()
            override fun onTrimMemory(level: Int) {
                if (level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW) platform.images.trim()
            }
        })
        platform_ = platform
        registry_ = registry
        return platform
    }

    internal fun newSurfaceId(): String = "elpian-${nextSurface++}"

    internal fun register(id: String, host: ElpianHostView) {
        hosts[id] = host
    }

    internal fun unregister(id: String) {
        hosts.remove(id)
    }
}
