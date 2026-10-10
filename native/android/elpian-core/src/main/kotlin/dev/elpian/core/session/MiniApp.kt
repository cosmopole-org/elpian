package dev.elpian.core.session

import dev.elpian.core.engine.ElpianEngine
import dev.elpian.core.events.ElpianEvent
import dev.elpian.core.host.HostHandler
import dev.elpian.core.host.HostHandlerOptions
import dev.elpian.core.host.VmTimerHostApi
import dev.elpian.core.platform.platform
import dev.elpian.core.scope.ScopePatch
import dev.elpian.core.util.Json
import dev.elpian.core.util.JsonMap
import dev.elpian.core.util.Typed
import dev.elpian.core.vm.ElpianVm
import dev.elpian.core.vm.HostCallHandler
import dev.elpian.core.vm.HostReply
import dev.elpian.core.vm.QuickJsVm
import dev.elpian.core.vm.RuntimeKind
import dev.elpian.core.vm.VmRuntimeClient
import dev.elpian.core.vm.WasmVm
import dev.elpian.core.vm.allHostApiNames
import dev.elpian.core.vm.initializeRuntime
import dev.elpian.core.vm.timerApiNames
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * One running mini app on one surface — the port of `ElpianVmWidget`
 * (flutter/lib/src/vm/elpian_vm_widget.dart; session/miniapp.ts).
 *
 * It creates the selected runtime, wires every host API (render, DOM,
 * canvas, env, timers, plus host-supplied handlers), runs the program and its
 * entry function, routes UI events to the guest functions named in each
 * node's `events`, applies bounded scope patches, and keeps the guest's host
 * environment (viewport, safe area, page, platform) in sync.
 */
class MiniAppOptions(
    val machineId: String,
    val runtime: RuntimeKind = RuntimeKind.ELPIAN,
    /** Elpian source, JS source (QuickJS) or the WASM config JSON. */
    val code: String? = null,
    val astJson: String? = null,
    /** Elpian VM bytecode, base64. */
    val bytecodeBase64: String? = null,
    /** A stylesheet JSON map or CSS text. */
    val stylesheet: Any? = null,
    val entryFunction: String? = null,
    val entryInput: String? = null,
    val hostHandlers: Map<String, HostCallHandler>? = null,
    /** Extra host-environment fields merged into `env.get`. */
    val hostEnvironment: Map<String, Any?>? = null,
    val onPrintln: ((message: String) -> Unit)? = null,
    val onUpdateApp: ((data: JsonMap) -> Unit)? = null,
    val onError: ((message: String) -> Unit)? = null,
    /** Consulted before every host call (HostHandler.onAuthorize). */
    val onAuthorize: ((apiName: String) -> Boolean)? = null,
    val onCallRefused: ((apiName: String) -> Unit)? = null,
    val onUnservicedApi: ((apiName: String, advertised: Boolean) -> Unit)? = null,
    /** Called once the program and entry function have run. */
    val onReady: (() -> Unit)? = null,
    /** Hide Flutter's default loading spinner / error box. */
    val showDefaultStates: Boolean = true,
    val surface: SurfaceOptions? = null,
    /** A runtime already created (MiniAppHost.mount); the session then neither creates nor disposes it. */
    val runtimeClient: VmRuntimeClient? = null,
)

class MiniAppSession(surfaceId: String, val options: MiniAppOptions) {
    val surface: ElpianSurface = ElpianSurface(surfaceId, options.surface ?: SurfaceOptions())
    private var runtimeVm: VmRuntimeClient? = null
    private var timers: VmTimerHostApi? = null
    private var currentView: JsonMap? = null
    private var envData: JsonMap = LinkedHashMap()
    private var envDigest: String? = null
    private var disposed = false
    private var loading = true
    private var errorMessage: String? = null

    /** Guest calls (events, timers, env sync) run here; cancelled on dispose. */
    val scope: CoroutineScope = CoroutineScope(SupervisorJob() + platform().dispatcher)

    init {
        if (options.stylesheet != null && options.stylesheet != "") engine.loadStylesheet(options.stylesheet)
        showState()
    }

    val engine: ElpianEngine get() = surface.engine

    val runtime: VmRuntimeClient? get() = runtimeVm

    val error: String? get() = errorMessage

    val isLoading: Boolean get() = loading

    val view: JsonMap? get() = currentView

    /** Create the runtime, wire the host APIs, run the program and the entry function. */
    suspend fun start() {
        val o = options
        val kind = o.runtime
        try {
            var vm: VmRuntimeClient? = o.runtimeClient
            if (vm != null) {
                // Provided by the host: already created and governed.
            } else if (kind == RuntimeKind.ELPIAN) {
                initializeRuntime(kind)
                vm = when {
                    !o.bytecodeBase64.isNullOrEmpty() -> ElpianVm.fromBytecode(o.machineId, o.bytecodeBase64)
                    o.code != null -> ElpianVm.fromCode(o.machineId, o.code)
                    o.astJson != null -> ElpianVm.fromAst(o.machineId, o.astJson)
                    else -> null
                }
                if (vm == null) {
                    val detail = ElpianVm.lastApiError
                    return fail(if (detail.isNotEmpty()) "Failed to create VM: $detail" else "Failed to create VM")
                }
            } else if (kind == RuntimeKind.QUICKJS) {
                initializeRuntime(kind)
                if (o.code == null) return fail("QuickJS runtime requires `code` (JavaScript source).")
                vm = QuickJsVm.fromCode(o.machineId, o.code)
            } else {
                if (o.code == null) return fail("WASM runtime requires `code` (WASM config JSON).")
                vm = WasmVm.fromCode(o.machineId, o.code)
            }
            if (disposed) {
                if (o.runtimeClient == null) vm.dispose()
                return
            }
            runtimeVm = vm

            // Every UI event goes to the guest function named in node.events.
            engine.services.events.onGlobalEvent { event -> scope.launch { routeEventToVm(event) } }

            val handler = HostHandler(
                engine.services,
                HostHandlerOptions(
                    onRender = { view, scopeKey -> applyRender(view, scopeKey) },
                    onUpdateApp = { data ->
                        o.onUpdateApp?.invoke(data)
                        if (o.entryFunction != null) scope.launch { callEntryFunction() }
                    },
                    onPrintln = o.onPrintln ?: { m -> platform().log("info", "[${o.machineId}] $m") },
                    onGetEnvironment = { envData },
                    onAuthorize = o.onAuthorize,
                    onCallRefused = o.onCallRefused,
                    onUnservicedApi = o.onUnservicedApi,
                    log = { m -> platform().log("debug", m) },
                ),
            )

            timers?.dispose()
            val runtimeVm = vm
            val t = VmTimerHostApi(
                { fn, input ->
                    if (!disposed) {
                        if (input == null) runtimeVm.callFunction(fn) else runtimeVm.callFunctionWithInput(fn, input)
                    }
                },
                { m -> platform().log("warn", "ElpianMiniApp: $m") },
            )
            timers = t

            val handlers = LinkedHashMap<String, HostCallHandler>()
            for (api in allHostApiNames) handlers[api] = { name, payload -> handler.handleHostCallReply(name, payload) }
            for (api in timerApiNames) handlers[api] = { name, payload -> HostReply.of(t.handle(name, payload)) }
            o.hostHandlers?.let { handlers.putAll(it) }
            vm.registerHostHandlers(handlers)
            syncHostEnvironment(true)

            vm.run()
            if (o.entryFunction != null) callEntryFunction()
            loading = false
            showState()
            o.onReady?.invoke()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            fail(errorText(e))
        }
    }

    private fun fail(message: String) {
        errorMessage = message
        loading = false
        options.onError?.invoke(message)
        showState()
    }

    private fun showState() {
        if (disposed) return
        val defaults = options.showDefaultStates
        val err = errorMessage
        if (err != null) {
            surface.setOverlay(if (defaults) messageBox("VM Error: $err", 0xfff44336.toInt()) else null)
            return
        }
        if (loading && currentView == null) {
            surface.setOverlay(if (defaults) loadingIndicator() else null)
            return
        }
        surface.setContent(currentView)
    }

    private fun applyRender(view: JsonMap, scopeKey: String?) {
        // Bounded scope patch: a scoped render whose key is missing is dropped.
        val next = ScopePatch.applyBounded(currentView, view, scopeKey)
        if (next == null) {
            platform().log("debug", "ElpianMiniApp: scoped render targeted missing scope \"$scopeKey\"; keeping current view.")
            return
        }
        currentView = next
        if (errorMessage == null) surface.setContent(next)
        scope.launch { syncHostEnvironment(false) }
    }

    private suspend fun routeEventToVm(event: ElpianEvent) {
        val vm = runtimeVm
        if (vm == null || disposed) return
        val nodeId = event.currentTarget
        if (nodeId.isNullOrEmpty()) return
        val handler = engine.services.events.getNode(nodeId)?.events?.get(event.type)
        if (handler !is String || handler.isEmpty()) return
        // Typed JSON input so every runtime decodes event arguments the same way.
        val payload = Json.stringify(Typed.toTyped(event.toJson()))
        try {
            vm.callFunctionWithInput(handler, payload)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            try {
                vm.callFunction(handler)
            } catch (fallback: CancellationException) {
                throw fallback
            } catch (fallback: Exception) {
                platform().log("warn", "ElpianMiniApp: Error calling event handler \"$handler\": ${jsErrorString(e)}; fallback failed: ${jsErrorString(fallback)}")
            }
        }
    }

    private suspend fun callEntryFunction() {
        val vm = runtimeVm
        val fn = options.entryFunction
        if (vm == null || fn.isNullOrEmpty()) return
        try {
            val input = options.entryInput
            if (input != null) vm.callFunctionWithInput(fn, input) else vm.callFunction(fn)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            platform().log("warn", "ElpianMiniApp: Error calling $fn: ${jsErrorString(e)}")
        }
    }

    /** Call a guest function (ElpianVmController.callFunction). */
    suspend fun callFunction(funcName: String, input: String? = null): String {
        val vm = runtimeVm ?: return ""
        return if (input != null) vm.callFunctionWithInput(funcName, input) else vm.callFunction(funcName)
    }

    /** The platform reports a viewport / safe-area / theme change. */
    fun viewportChanged() {
        surface.viewportChanged()
        scope.launch { syncHostEnvironment(true) }
    }

    private suspend fun syncHostEnvironment(force: Boolean) {
        val next = buildHostEnvironment()
        val digest = Json.stringify(next)
        val changed = digest != envDigest
        if (changed) {
            envDigest = digest
            envData = next
        }
        val vm = runtimeVm
        if (vm == null || (!changed && !force)) return
        try {
            vm.setGlobalHostData(envData)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            platform().log("warn", "ElpianMiniApp: failed to sync host env: ${jsErrorString(e)}")
        }
    }

    private fun buildHostEnvironment(): JsonMap {
        val vp = platform().viewport(surface.id)
        val href = vp.href ?: ""
        var page: JsonMap = linkedMapOf(
            "href" to href, "scheme" to "", "host" to "", "port" to null, "path" to "", "query" to "",
            "queryParameters" to LinkedHashMap<String, Any?>(), "fragment" to "",
        )
        val m = HREF.find(href)
        if (m != null) {
            val g = m.groups
            val query = g[5]?.value ?: ""
            val params = LinkedHashMap<String, Any?>()
            for (part in query.split("&")) {
                if (part.isEmpty()) continue
                val i = part.indexOf('=')
                val k = decodeURIComponentSafe(if (i < 0) part else part.substring(0, i))
                params[k] = decodeURIComponentSafe(if (i < 0) "" else part.substring(i + 1))
            }
            page = linkedMapOf(
                "href" to href,
                "scheme" to g[1]!!.value,
                "host" to (g[2]?.value ?: ""),
                "port" to g[3]?.value?.toDouble(),
                "path" to (g[4]?.value ?: ""),
                "query" to query,
                "queryParameters" to params,
                "fragment" to (g[6]?.value ?: ""),
            )
        }
        val out: JsonMap = linkedMapOf(
            "machineId" to options.machineId,
            "runtime" to runtimeName(options.runtime),
            "viewport" to linkedMapOf<String, Any?>(
                "width" to vp.width,
                "height" to vp.height,
                "devicePixelRatio" to vp.devicePixelRatio,
                "orientation" to (if (vp.width >= vp.height) "landscape" else "portrait"),
            ),
            "screen" to linkedMapOf<String, Any?>("physicalWidth" to vp.width * vp.devicePixelRatio, "physicalHeight" to vp.height * vp.devicePixelRatio),
            "safeArea" to linkedMapOf<String, Any?>("top" to vp.safeArea.top, "right" to vp.safeArea.right, "bottom" to vp.safeArea.bottom, "left" to vp.safeArea.left),
            "page" to page,
            "platform" to linkedMapOf<String, Any?>("isWeb" to vp.isWeb, "defaultTargetPlatform" to vp.platform, "locale" to vp.locale),
        )
        options.hostEnvironment?.let { out.putAll(it) }
        return out
    }

    suspend fun dispose() {
        if (disposed) return
        disposed = true
        timers?.dispose()
        timers = null
        val vm = runtimeVm
        runtimeVm = null
        surface.dispose()
        scope.cancel()
        if (options.runtimeClient == null) vm?.dispose()
    }
}

private val HREF = Regex("^([a-zA-Z][\\w+.-]*):(?://([^/?#:]*)(?::(\\d+))?)?([^?#]*)(?:\\?([^#]*))?(?:#(.*))?$")

/** `ElpianRuntime.name` in Dart. */
fun runtimeName(kind: RuntimeKind): String = if (kind == RuntimeKind.QUICKJS) "quickJs" else kind.wireName

private fun decodeURIComponentSafe(s: String): String = try {
    // `decodeURIComponent(s.replace(/\+/g, ' '))`; URLDecoder maps `+` to a space itself.
    java.net.URLDecoder.decode(s, Charsets.UTF_8)
} catch (_: Exception) {
    s
}
