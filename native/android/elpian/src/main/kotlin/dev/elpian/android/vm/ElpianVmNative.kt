package dev.elpian.android.vm

/**
 * The JNI face of the Rust Elpian VM (`libelpian_vm.so`, built by
 * `scripts/build-rust.sh` from rust/crates/elpian-ffi with the `jni` feature).
 *
 * Three entry points cover the whole C ABI (see rust/crates/elpian-ffi/src/jni.rs):
 *
 *  - [nativeCall] runs any `elpian_*` export by name with its arguments as a JSON
 *    array (dispatch.rs). Integer-returning exports answer `"true"`/`"false"`,
 *    string-returning ones their JSON; null means no export has that name.
 *  - [nativeCreateFromBytecode] — bytecode does not travel as JSON.
 *  - [nativeLastError] — the per-thread error slot (empty when none).
 *
 * The library is loaded lazily on first use; a missing or broken `.so`
 * (UnsatisfiedLinkError, SecurityException…) leaves [isLoaded] false and the
 * reason in [loadError] instead of crashing the app.
 */
object ElpianVmNative {
    const val LIBRARY = "elpian_vm"

    @Volatile private var state: Int = 0 // 0 = not tried, 1 = loaded, -1 = failed

    @Volatile var loadError: String? = null
        private set

    /** Load the library once; whether it is usable. */
    val isLoaded: Boolean
        get() {
            if (state == 0) load()
            return state == 1
        }

    @Synchronized
    private fun load() {
        if (state != 0) return
        state = try {
            System.loadLibrary(LIBRARY)
            1
        } catch (e: UnsatisfiedLinkError) {
            loadError = "lib$LIBRARY.so is not loadable: ${e.message}"
            -1
        } catch (e: SecurityException) {
            loadError = "lib$LIBRARY.so may not be loaded: ${e.message}"
            -1
        }
    }

    @JvmStatic external fun nativeCall(symbol: String, argsJson: String): String?

    @JvmStatic external fun nativeCreateFromBytecode(id: String, bytes: ByteArray): Boolean

    @JvmStatic external fun nativeLastError(): String
}
