package dev.elpian.core.session

import dev.elpian.core.css.Alignment
import dev.elpian.core.css.M3
import dev.elpian.core.events.ElpianEvent
import dev.elpian.core.host.HostHandler
import dev.elpian.core.host.HostHandlerOptions
import dev.elpian.core.host.VmTimerHostApi
import dev.elpian.core.platform.FetchRequest
import dev.elpian.core.platform.FetchResponse
import dev.elpian.core.platform.platform
import dev.elpian.core.render.w
import dev.elpian.core.scope.ScopeContract
import dev.elpian.core.scope.ScopePatch
import dev.elpian.core.util.Json
import dev.elpian.core.util.JsonMap
import dev.elpian.core.util.asMap
import dev.elpian.core.util.isMap
import dev.elpian.core.util.jsString
import dev.elpian.core.util.stableKey
import dev.elpian.core.vm.ElpianVm
import dev.elpian.core.vm.HostCallHandler
import dev.elpian.core.vm.HostReply
import dev.elpian.core.vm.QuickJsVm
import dev.elpian.core.vm.VmRuntimeClient
import dev.elpian.core.vm.allHostApiNames
import dev.elpian.core.vm.timerApiNames
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlin.random.Random

/**
 * A server-driven page — the port of `NextjsServerWidget`, `NextjsBridge`'s
 * envelope handling, `NextjsAuthConfig` / token stores and
 * `ClientCompRouting` (the Dart files under flutter/lib/src/integrations; session/nextjs.ts).
 *
 * It loads render envelopes from a Next.js (or any Elpian-speaking) server,
 * keeps the previous screen painted while the next route loads, resolves
 * `clientComp` nodes onto persistent QuickJS VMs (each re-rendering only its
 * own scope), runs page scripts (`jsCode` / `vmAstJson`), routes UI events to
 * the right VM, handles `NextjsLink` / `NextjsForm` navigation and
 * submission, server navigation directives, auth token capture, refresh and
 * retry, and the `fetch` / `submit` / `navigate` / `mountFragment` host APIs.
 */

// ============================================================================
// Envelope
// ============================================================================

class NextjsEnvelopeException(message: String) : Exception(message)

data class NextjsRenderEnvelope(
    val component: JsonMap,
    val stylesheet: JsonMap? = null,
    val meta: JsonMap? = null,
    val navigation: JsonMap? = null,
    val clientComponents: JsonMap? = null,
    val jsCode: String? = null,
    val vmAstJson: String? = null,
    val jsEntryFunction: String? = null,
)

fun envelopeFromJson(json: Map<String, Any?>): NextjsRenderEnvelope {
    if (!isMap(json["component"])) throw NextjsEnvelopeException("Next.js payload must contain a \"component\" object that matches Elpian JSON.")
    fun obj(k: String): JsonMap? {
        val v = json[k]
        if (v != null && !isMap(v)) throw NextjsEnvelopeException("\"$k\" must be a JSON object when provided.")
        return v?.asMap()
    }
    fun str(k: String): String? {
        val v = json[k]
        if (v != null && v !is String) throw NextjsEnvelopeException("\"$k\" must be a string when provided.")
        return v as String?
    }
    return NextjsRenderEnvelope(
        component = json["component"].asMap()!!,
        stylesheet = obj("stylesheet"),
        meta = obj("meta"),
        navigation = obj("navigation"),
        clientComponents = obj("clientComponents"),
        jsCode = str("jsCode"),
        vmAstJson = str("vmAstJson"),
        jsEntryFunction = str("jsEntryFunction"),
    )
}

fun buildRouteRequest(route: String, props: Map<String, Any?>? = null, context: Map<String, Any?>? = null): JsonMap {
    val out: JsonMap = linkedMapOf("route" to route)
    if (props != null) out["props"] = props
    if (context != null) out["context"] = context
    return out
}

// ============================================================================
// Auth
// ============================================================================

interface NextjsTokenStore {
    val accessToken: String?
    val refreshToken: String?
    val hasSession: Boolean
    suspend fun ensureReady()
    fun save(access: String? = null, refresh: String? = null)
    fun clear()
}

class InMemoryTokenStore : NextjsTokenStore {
    private var access: String? = null
    private var refresh: String? = null
    override val accessToken: String? get() = access
    override val refreshToken: String? get() = refresh
    override val hasSession: Boolean get() = !access.isNullOrEmpty()

    override suspend fun ensureReady() {}

    override fun save(access: String?, refresh: String?) {
        if (access != null) this.access = access
        if (refresh != null) this.refresh = refresh
    }

    override fun clear() {
        access = null
        refresh = null
    }
}

/** Persisted through the platform's key-value storage (SharedPreferences / UserDefaults / localStorage). */
class PlatformTokenStore(val namespace: String = "elpian") : NextjsTokenStore {
    private var access: String? = null
    private var refresh: String? = null
    private var ready = false
    private val accessKey: String get() = "${namespace}_access_token"
    private val refreshKey: String get() = "${namespace}_refresh_token"
    override val accessToken: String? get() = access
    override val refreshToken: String? get() = refresh
    override val hasSession: Boolean get() = !access.isNullOrEmpty()

    override suspend fun ensureReady() {
        if (ready) return
        ready = true
        try {
            val p = platform()
            access = p.storageGet(accessKey)
            refresh = p.storageGet(refreshKey)
        } catch (_: Exception) {
            // Persistence unavailable: degrade to in-memory.
        }
    }

    override fun save(access: String?, refresh: String?) {
        val p = platform()
        if (access != null) {
            this.access = access
            p.storageSet(accessKey, access)
        }
        if (refresh != null) {
            this.refresh = refresh
            p.storageSet(refreshKey, refresh)
        }
    }

    override fun clear() {
        val p = platform()
        access = null
        refresh = null
        p.storageSet(accessKey, null)
        p.storageSet(refreshKey, null)
    }
}

data class NextjsAuthConfig(
    val store: NextjsTokenStore,
    val loginRoute: String,
    val refreshRoute: String,
    val bearerScheme: String,
)

fun nextjsAuthConfig(
    store: NextjsTokenStore? = null,
    loginRoute: String? = null,
    refreshRoute: String? = null,
    bearerScheme: String? = null,
): NextjsAuthConfig = NextjsAuthConfig(
    store = store ?: PlatformTokenStore(),
    loginRoute = loginRoute ?: "/auth",
    refreshRoute = refreshRoute ?: "/auth/refresh",
    bearerScheme = bearerScheme ?: "Bearer",
)

// ============================================================================
// Client-component handler routing
// ============================================================================

object ClientCompRouting {
    const val separator = "::"

    fun namespaced(mountId: String, fn: String): String = "$mountId::$fn"

    data class Route(val mountId: String, val fn: String)

    fun parse(handler: String): Route? {
        val idx = handler.indexOf("::")
        if (idx <= 0) return null
        return Route(handler.substring(0, idx), handler.substring(idx + 2))
    }

    /** Prefix every un-namespaced handler in [node] with [mountId] (in place). */
    fun namespaceHandlers(node: JsonMap, mountId: String): JsonMap {
        val events = node["events"]
        if (isMap(events)) {
            val ns: JsonMap = LinkedHashMap()
            for ((k, v) in events.asMap()!!) ns[k] = if (v is String && v.isNotEmpty() && !v.contains("::")) namespaced(mountId, v) else v
            node["events"] = ns
        }
        val children = node["children"]
        if (children is List<*>) {
            val list = children as? MutableList<Any?>
            for ((i, c) in children.withIndex()) {
                if (!isMap(c)) continue
                if (c is MutableMap<*, *>) {
                    @Suppress("UNCHECKED_CAST")
                    namespaceHandlers(c as JsonMap, mountId)
                } else {
                    // A read-only map is swapped for a mutable copy so the edit lands in place.
                    val copy = c.asMap()!!
                    namespaceHandlers(copy, mountId)
                    if (list != null) list[i] = copy
                }
            }
        }
        return node
    }
}

// ============================================================================
// Session
// ============================================================================

/** The loader's `{ props, headers }`. */
data class NextjsLoadOptions(val props: Map<String, Any?>? = null, val headers: Map<String, String>? = null)

typealias NextjsPayloadLoader = suspend (route: String, opts: NextjsLoadOptions) -> JsonMap

/** `onScriptExecuted`'s `{ route, kind, output }`; kind is `js` or `vmAst`. */
data class NextjsScriptResult(val route: String, val kind: String, val output: String) {
    fun toJson(): JsonMap = linkedMapOf("route" to route, "kind" to kind, "output" to output)
}

class NextjsSessionOptions(
    val route: String,
    val serverBaseUrl: String? = null,
    val endpoint: String? = null,
    /** `routePath` or `apiEndpoint`. */
    val requestMode: String = "routePath",
    val loader: NextjsPayloadLoader? = null,
    val props: Map<String, Any?>? = null,
    val headers: Map<String, String>? = null,
    val auth: NextjsAuthConfig? = null,
    val timeoutMs: Double? = null,
    val onScriptExecuted: ((result: NextjsScriptResult) -> Unit)? = null,
    val onScriptError: ((error: Throwable) -> Unit)? = null,
    /** The route changed (for host back-stack / URL sync). */
    val onRouteChanged: ((route: String) -> Unit)? = null,
    /** A tap on a clickable Scene3D node not handled by the page VM. */
    val onSceneTap: ((props: Map<String, Any?>) -> Unit)? = null,
    val surface: SurfaceOptions? = null,
)

private class LiveClientComp(
    val mountId: String,
    val vm: VmRuntimeClient,
    val style: JsonMap?,
    var timer: VmTimerHostApi?,
    var latest: JsonMap?,
    var dirty: Boolean,
)

private const val HOST_OK = "{\"type\":\"i16\",\"data\":{\"value\":1}}"

private data class PackedScript(val jsCode: String, val jsEntryFunction: String)

class NextjsSession(surfaceId: String, val options: NextjsSessionOptions) {
    val surface: ElpianSurface
    private var currentRoute: String = options.route
    private val history = ArrayList<String>()
    private var lastScriptSignature: String? = null
    private var scriptRendered: JsonMap? = null
    private var lastEnvelopeComponent: JsonMap? = null
    private var previousComponent: JsonMap? = null
    private val clientComponentCache = HashMap<String, JsonMap>()
    private var pageVm: VmRuntimeClient? = null
    private var pageTimers: VmTimerHostApi? = null
    private val liveComps = LinkedHashMap<String, LiveClientComp>()
    private var compSeq = 0
    private var loadGeneration = 0
    private var payload: JsonMap? = null
    private var loadError: Throwable? = null
    private var loading = true
    private var lastStylesheetKey: String? = null
    private var disposed = false

    /** Loads, scripts and guest calls run here; cancelled on dispose. */
    val scope: CoroutineScope = CoroutineScope(SupervisorJob() + platform().dispatcher)

    init {
        if (options.loader == null && options.serverBaseUrl.isNullOrEmpty()) {
            throw IllegalArgumentException("Either provide loader or serverBaseUrl for automatic Next.js loading.")
        }
        // Server-relative resources ("/icons/x.png") resolve against the server ORIGIN.
        val origin = originOf(options.serverBaseUrl)
        val given = options.surface ?: SurfaceOptions()
        val host = copyEngineHost(given.host)
        val givenBaseUrl = given.host?.baseUrl
        host.navigate = { href, replace -> navigate(href, replace) }
        host.submitForm = { action, values -> handleFormSubmit(action, values) }
        host.sceneTap = { props -> scope.launch { dispatchSceneTap(props) } }
        host.baseUrl = { givenBaseUrl?.invoke() ?: origin }
        surface = ElpianSurface(surfaceId, given.copy(document = true, host = host))
        surface.engine.services.events.onGlobalEvent { e -> scope.launch { routeEvent(e) } }
        scope.launch { load() }
    }

    val route: String get() = currentRoute

    val canGoBack: Boolean get() = history.isNotEmpty()

    // ---------------------------------------------------------------------------
    // Navigation
    // ---------------------------------------------------------------------------

    fun navigate(route: String, replace: Boolean = false) {
        if (currentRoute == route && !replace) return
        scope.launch { disposePageVm() }
        if (!replace) history.add(currentRoute)
        currentRoute = route
        beginReload()
    }

    fun back(): Boolean {
        if (history.isEmpty()) return false
        scope.launch { disposePageVm() }
        currentRoute = history.removeAt(history.size - 1)
        beginReload()
        return true
    }

    fun refresh() {
        scope.launch { disposePageVm() }
        beginReload()
    }

    private fun beginReload() {
        // Keep the screen just rendered as the loading backdrop.
        previousComponent = scriptRendered ?: lastEnvelopeComponent ?: previousComponent
        scriptRendered = null
        lastEnvelopeComponent = null
        lastScriptSignature = null
        options.onRouteChanged?.invoke(currentRoute)
        scope.launch { load() }
    }

    private fun applyServerNavigation(nav: Map<String, Any?>?) {
        if (nav.isNullOrEmpty()) return
        if (nav["back"] == true) {
            microtask { back() }
            return
        }
        if (nav["refresh"] == true) {
            microtask { refresh() }
            return
        }
        val to = if (nav["redirectTo"] != null) jsString(nav["redirectTo"]) else ""
        if (to.isNotEmpty()) {
            val replace = nav["replace"] == true
            if (to != currentRoute || replace) microtask { navigate(to, replace) }
        }
    }

    // ---------------------------------------------------------------------------
    // Loading
    // ---------------------------------------------------------------------------

    private suspend fun load() {
        val generation = ++loadGeneration
        loading = true
        loadError = null
        paint()
        try {
            val p = loadPayload()
            if (generation != loadGeneration || disposed) return
            payload = p
            loading = false
            onPayload()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (generation != loadGeneration || disposed) return
            loading = false
            loadError = e
            paint()
        }
    }

    private suspend fun loadPayload(): JsonMap {
        disposeClientComps()
        compSeq = 0
        options.auth?.store?.ensureReady()
        val loader: NextjsPayloadLoader = options.loader ?: { r, o -> httpLoader(r, o) }
        var p = loader(currentRoute, NextjsLoadOptions(options.props, options.headers))
        captureAuth(p)
        val auth = options.auth
        if (auth != null && options.loader == null) {
            val nav = p["navigation"]
            if (isMap(nav) && jsString(nav.asMap()!!["redirectTo"] ?: "") == auth.loginRoute && !auth.store.refreshToken.isNullOrEmpty()) {
                if (tryRefresh()) {
                    p = httpLoader(currentRoute, NextjsLoadOptions(options.props, options.headers))
                    captureAuth(p)
                }
            }
        }
        val envelope = envelopeFromJson(p)
        val component = resolveClientComponentNodes(envelope.component, envelope.clientComponents)
        val out: JsonMap = LinkedHashMap(p)
        out["component"] = component
        return out
    }

    private fun onPayload() {
        val p = payload ?: return
        val envelope = try {
            envelopeFromJson(p)
        } catch (e: Exception) {
            loadError = e
            paint()
            return
        }
        lastEnvelopeComponent = envelope.component
        triggerScriptExecution(envelope)
        applyServerNavigation(envelope.navigation)
        val sheet = envelope.stylesheet
        if (sheet != null) {
            val key = stableKey(sheet)
            if (key != lastStylesheetKey) {
                lastStylesheetKey = key
                surface.engine.loadStylesheet(sheet)
            }
        }
        paint()
    }

    /** Put the current state on the surface (FutureBuilder.build). */
    private fun paint() {
        if (disposed) return
        val s = surface
        if (loading) {
            val fallback = previousComponent
            if (fallback != null) {
                // The previous screen with a thin progress bar on top.
                s.decorate = { content ->
                    w(
                        "stack",
                        mapOf("fit" to "loose"),
                        listOf(
                            content,
                            w(
                                "positioned",
                                mapOf("top" to 0.0, "left" to 0.0, "right" to 0.0),
                                w(
                                    "control",
                                    mapOf(
                                        "kind" to "progress",
                                        "view" to linkedMapOf<String, Any?>(
                                            "variant" to "linear",
                                            "value" to null,
                                            "strokeWidth" to 2.0,
                                            "colors" to linkedMapOf<String, Any?>("indicator" to M3.primary, "track" to M3.secondaryContainer),
                                        ),
                                    ),
                                ),
                            ),
                        ),
                    )
                }
                s.setContent(fallback)
            } else {
                s.decorate = null
                s.setOverlay(loadingIndicator())
            }
            return
        }
        s.decorate = null
        val err = loadError
        if (err != null) {
            s.setOverlay(
                w(
                    "align",
                    mapOf("alignment" to Alignment(0.0, 0.0)),
                    w("text", mapOf("text" to "Next.js payload error on \"$currentRoute\": ${errorText(err)}", "align" to "center")),
                ),
            )
            return
        }
        if (payload == null) {
            s.setOverlay(w("align", mapOf("alignment" to Alignment(0.0, 0.0)), w("text", mapOf("text" to "Next.js payload was empty."))))
            return
        }
        foldClientCompRenders()
        s.setContent(scriptRendered ?: lastEnvelopeComponent)
    }

    // ---------------------------------------------------------------------------
    // HTTP
    // ---------------------------------------------------------------------------

    private fun buildUrl(route: String): String {
        val base = (options.serverBaseUrl ?: "").replace(TRAILING_SLASHES, "")
        if (route.startsWith("http://") || route.startsWith("https://")) return route
        if (route.isEmpty() || route == "/") return base
        return "$base${if (route.startsWith("/")) route else "/$route"}"
    }

    private fun authHeaders(): Map<String, String> {
        val a = options.auth
        val t = a?.store?.accessToken
        return if (!t.isNullOrEmpty()) mapOf("authorization" to "${a.bearerScheme} $t") else emptyMap()
    }

    private suspend fun request(req: FetchRequest): FetchResponse =
        platform().fetch(if (req.timeoutMs == null) req.copy(timeoutMs = (options.timeoutMs ?: 120000.0).toLong()) else req)

    private suspend fun httpLoader(route: String, o: NextjsLoadOptions): JsonMap {
        if (options.serverBaseUrl.isNullOrEmpty()) throw IllegalStateException("serverBaseUrl is required when no custom loader is provided.")
        if (options.requestMode == "routePath") {
            val url = buildUrl(route)
            val headers = LinkedHashMap<String, String>()
            headers["accept"] = "application/vnd.elpian+json, application/json"
            headers["x-elpian-route"] = route
            if (!o.props.isNullOrEmpty()) headers["x-elpian-props"] = Json.stringify(o.props)
            headers.putAll(authHeaders())
            o.headers?.let { headers.putAll(it) }
            val res = request(FetchRequest(url = url, method = "GET", headers = headers))
            if (res.status < 200 || res.status >= 300) throw IllegalStateException("Next.js route $url returned HTTP ${res.status}: ${res.body}")
            val decoded = Json.parse(res.body)
            if (!isMap(decoded)) throw IllegalStateException("Next.js route response must decode to a JSON object.")
            return decoded.asMap()!!
        }
        val url = buildUrl(options.endpoint ?: "/api/elpian-render")
        val headers = LinkedHashMap<String, String>()
        headers["content-type"] = "application/json"
        headers.putAll(authHeaders())
        o.headers?.let { headers.putAll(it) }
        val res = request(FetchRequest(url = url, method = "POST", headers = headers, body = Json.stringify(buildRouteRequest(route, o.props))))
        if (res.status < 200 || res.status >= 300) throw IllegalStateException("Next.js endpoint $url returned HTTP ${res.status}: ${res.body}")
        val decoded = Json.parse(res.body)
        if (!isMap(decoded)) throw IllegalStateException("Next.js payload must decode to a JSON object.")
        return decoded.asMap()!!
    }

    private suspend fun postJson(route: String, body: Any?): JsonMap {
        val headers = LinkedHashMap<String, String>()
        headers["content-type"] = "application/json"
        headers["accept"] = "application/vnd.elpian+json, application/json"
        headers["x-elpian-route"] = route
        headers.putAll(authHeaders())
        options.headers?.let { headers.putAll(it) }
        val res = request(FetchRequest(url = buildUrl(route), method = "POST", headers = headers, body = Json.stringify(body)))
        val decoded = Json.parse(res.body)
        if (!isMap(decoded)) throw IllegalStateException("Action response must decode to a JSON object.")
        return decoded.asMap()!!
    }

    private fun captureAuth(envelope: Map<String, Any?>) {
        val a = options.auth ?: return
        val meta = envelope["meta"]
        if (!isMap(meta)) return
        val m = meta.asMap()!!
        if (m["clearAuth"] == true) {
            a.store.clear()
            return
        }
        if (m.containsKey("auth")) {
            val auth = m["auth"]
            if (isMap(auth)) {
                val am = auth.asMap()!!
                a.store.save(
                    access = am["accessToken"]?.let { jsString(it) },
                    refresh = am["refreshToken"]?.let { jsString(it) },
                )
            } else if (auth == null) {
                a.store.clear()
            }
        }
    }

    private suspend fun tryRefresh(): Boolean {
        val a = options.auth ?: return false
        val rt = a.store.refreshToken
        if (rt.isNullOrEmpty()) return false
        try {
            val env = postJson(a.refreshRoute, linkedMapOf("refreshToken" to rt))
            val meta = env["meta"]
            val auth = if (isMap(meta)) meta.asMap()!!["auth"] else null
            if (isMap(auth) && auth.asMap()!!["accessToken"] != null) {
                val am = auth.asMap()!!
                a.store.save(access = jsString(am["accessToken"]), refresh = am["refreshToken"]?.let { jsString(it) })
                return true
            }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            /* fall through */
        }
        a.store.clear()
        return false
    }

    private suspend fun handleFormSubmit(action: String, values: Map<String, Any?>): String? {
        return try {
            val env = postJson(action, values)
            captureAuth(env)
            val nav = env["navigation"]
            if (isMap(nav) && nav.asMap()!!.isNotEmpty()) {
                applyServerNavigation(nav.asMap())
                return null
            }
            val inline = firstText(env["component"])
            if (inline != null) return inline
            if (isMap(env["component"])) setScriptRendered(env["component"].asMap())
            null
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            "Request failed: ${errorText(e)}"
        }
    }

    // ---------------------------------------------------------------------------
    // Client components
    // ---------------------------------------------------------------------------

    private suspend fun resolveClientComponentNodes(node: JsonMap, packed: JsonMap?): JsonMap {
        val type = jsString(node["type"] ?: "")
        if (type == "clientComp" || type == "client-component") {
            return resolveClientComponentNode(node, packed)
                ?: linkedMapOf("type" to "Text", "props" to linkedMapOf<String, Any?>("text" to "Failed to execute client component jsCode"))
        }
        val children = node["children"]
        if (children is List<*>) {
            val out = ArrayList<Any?>()
            for (c in children) out.add(if (isMap(c)) resolveClientComponentNodes(c.asMap()!!, packed) else c)
            val copy: JsonMap = LinkedHashMap(node)
            copy["children"] = out
            return copy
        }
        return node
    }

    private suspend fun resolveClientComponentNode(node: JsonMap, packed: JsonMap?): JsonMap? {
        val props: JsonMap = if (isMap(node["props"])) LinkedHashMap(node["props"].asMap()!!) else LinkedHashMap()
        var jsCode: String? = when {
            node["jsCode"] != null -> jsString(node["jsCode"])
            props["jsCode"] != null -> jsString(props["jsCode"])
            else -> null
        }
        var entry = jsString(node["jsEntryFunction"] ?: props["jsEntryFunction"] ?: "MainComponent")
        if (jsCode.isNullOrEmpty()) {
            val p = findPackedScript(node, props, packed)
            jsCode = p?.jsCode
            entry = p?.jsEntryFunction ?: entry
        }
        if (jsCode.isNullOrEmpty() && !options.serverBaseUrl.isNullOrEmpty()) {
            val f = fetchClientComponentScript(node, props)
            jsCode = f?.jsCode
            entry = f?.jsEntryFunction ?: entry
        }
        if (jsCode.isNullOrEmpty()) return null
        return mountClientComponent(jsCode, entry, props, node["style"])
    }

    private suspend fun mountClientComponent(jsCode: String, entryFunction: String, props: JsonMap, style: Any?): JsonMap? {
        val mountId = "cc${compSeq++}"
        val machineId = "nextjs-$mountId-${System.currentTimeMillis()}${Random.nextInt(1000)}"
        val vm: QuickJsVm = try {
            QuickJsVm.fromCode(machineId, jsCode)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            platform().log("warn", "NextjsSession: clientComp \"$mountId\" create failed: ${jsErrorString(e)}")
            return null
        }
        val record = LiveClientComp(mountId, vm, if (isMap(style)) style.asMap() else null, timer = null, latest = null, dirty = false)
        liveComps[mountId] = record

        var firstDone = false
        val firstRender = CompletableDeferred<Unit>()
        val handler = HostHandler(
            surface.engine.services,
            HostHandlerOptions(
                onRender = { view, _ ->
                    record.latest = ClientCompRouting.namespaceHandlers(view, mountId)
                    if (!firstDone) {
                        firstDone = true
                        firstRender.complete(Unit)
                    } else {
                        record.dirty = true
                        paint()
                    }
                },
                onPrintln = { m -> platform().log("info", "NextjsSession[$mountId]: $m") },
            ),
        )
        val timer = VmTimerHostApi(
            { fn, input -> if (input == null) vm.callFunction(fn) else vm.callFunctionWithInput(fn, input) },
            { m -> platform().log("warn", "NextjsSession[$mountId timer]: $m") },
        )
        record.timer = timer
        vm.registerHostHandlers(hostHandlers(handler, timer) { record.vm })
        try {
            vm.run()
            vm.callFunctionWithInput(entryFunction, Json.stringify(props))
            var timeout: Int? = null
            if (!firstRender.isCompleted) {
                timeout = platform().setTimeout(3000.0) {
                    platform().log("warn", "NextjsSession: clientComp \"$mountId\" first render timed out")
                    firstRender.complete(Unit)
                }
            }
            firstRender.await()
            timeout?.let { platform().clearTimeout(it) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            platform().log("warn", "NextjsSession: clientComp \"$mountId\" exec failed: ${jsErrorString(e)}")
            liveComps.remove(mountId)
            disposeComp(record)
            return null
        }
        record.dirty = false
        return linkedMapOf(
            "type" to ScopeContract.type,
            "key" to "${mountId}__scope",
            "props" to LinkedHashMap<String, Any?>(),
            "children" to mutableListOf<Any?>(compContent(record)),
        )
    }

    private fun compContent(record: LiveClientComp): JsonMap {
        val node: JsonMap = LinkedHashMap(record.latest ?: linkedMapOf<String, Any?>("type" to "div"))
        node["key"] = record.mountId
        val style = record.style
        if (style != null) {
            val own = node["style"]
            node["style"] = if (isMap(own)) LinkedHashMap(style).also { it.putAll(own.asMap()!!) } else style
        }
        return node
    }

    private fun foldClientCompRenders() {
        if (liveComps.isEmpty()) return
        val tree = scriptRendered ?: lastEnvelopeComponent ?: return
        var any = false
        for (r in liveComps.values) {
            if (!r.dirty || r.latest == null) continue
            if (ScopePatch.replaceByKey(tree, r.mountId, compContent(r))) {
                r.dirty = false
                any = true
            }
        }
        if (any) scriptRendered = tree
    }

    private suspend fun disposeClientComps() {
        val comps = liveComps.values.toList()
        liveComps.clear()
        for (c in comps) disposeComp(c)
    }

    private fun findPackedScript(node: JsonMap, props: JsonMap, packed: JsonMap?): PackedScript? {
        if (packed.isNullOrEmpty()) return null
        for (key in lookupKeys(node, props)) {
            val p = normalizePacked(packed[key])
            if (p != null) return p
        }
        val values = packed.values.toList()
        return if (values.size == 1) normalizePacked(values[0]) else null
    }

    private suspend fun fetchClientComponentScript(node: JsonMap, props: JsonMap): PackedScript? {
        val keys = lookupKeys(node, props)
        for (k in keys) {
            val c = clientComponentCache[k]
            val p = if (c != null) normalizePacked(c) else null
            if (p != null) return p
        }
        try {
            val headers = LinkedHashMap<String, String>()
            headers["content-type"] = "application/json"
            headers["accept"] = "application/json"
            headers.putAll(authHeaders())
            options.headers?.let { headers.putAll(it) }
            val res = request(
                FetchRequest(
                    url = buildUrl(options.endpoint ?: "/api/elpian-client-component"),
                    method = "POST",
                    headers = headers,
                    body = Json.stringify(linkedMapOf("route" to currentRoute, "lookupKeys" to keys, "componentNode" to node)),
                ),
            )
            if (res.status < 200 || res.status >= 300) return null
            val decoded = Json.parse(res.body)
            if (!isMap(decoded)) return null
            val d = decoded.asMap()!!
            val cc = d["clientComponents"]
            if (isMap(cc)) {
                for ((k, v) in cc.asMap()!!) {
                    if (isMap(v)) clientComponentCache[k] = LinkedHashMap(v.asMap()!!)
                    else if (v is String) clientComponentCache[k] = linkedMapOf("jsCode" to v)
                }
            }
            val direct = normalizePacked(d)
            if (direct != null) {
                for (k in keys) clientComponentCache[k] = linkedMapOf("jsCode" to direct.jsCode, "jsEntryFunction" to direct.jsEntryFunction)
                return direct
            }
            for (k in keys) {
                val c = clientComponentCache[k]
                val p = if (c != null) normalizePacked(c) else null
                if (p != null) return p
            }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            /* resolved inline or not at all */
        }
        return null
    }

    // ---------------------------------------------------------------------------
    // Page scripts
    // ---------------------------------------------------------------------------

    private fun triggerScriptExecution(envelope: NextjsRenderEnvelope) {
        if (envelope.jsCode.isNullOrEmpty() && envelope.vmAstJson.isNullOrEmpty()) return
        val signature = "$currentRoute|${envelope.jsEntryFunction ?: "MainComponent"}|${envelope.jsCode ?: ""}|${envelope.vmAstJson ?: ""}"
        if (lastScriptSignature == signature) return
        lastScriptSignature = signature
        scope.launch { executeEnvelopeScripts(envelope) }
    }

    private suspend fun executeEnvelopeScripts(envelope: NextjsRenderEnvelope) {
        try {
            if (!envelope.jsCode.isNullOrEmpty()) runPageScript(envelope.jsCode, envelope.jsEntryFunction ?: "MainComponent")
            if (!envelope.vmAstJson.isNullOrEmpty()) {
                ElpianVm.initialize()
                val vm = ElpianVm.fromAst("nextjs-ast-${System.currentTimeMillis()}", envelope.vmAstJson)
                    ?: throw IllegalStateException("Failed to create Elpian VM from AST payload.")
                vm.registerHostHandler("render") { _, payload ->
                    setScriptRendered(decodeRenderPayload(payload))
                    HostReply.of(HOST_OK)
                }
                try {
                    val output = vm.run()
                    setScriptRendered(decodeRenderPayload(output))
                    options.onScriptExecuted?.invoke(NextjsScriptResult(currentRoute, "vmAst", output))
                } finally {
                    vm.dispose()
                }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            options.onScriptError?.invoke(e)
            platform().log("warn", "NextjsSession script execution error: ${jsErrorString(e)}")
        }
    }

    private suspend fun runPageScript(jsCode: String, entryFunction: String) {
        disposePageVm()
        val vm = QuickJsVm.fromCode("nextjs-page-${System.currentTimeMillis()}", jsCode)
        pageVm = vm
        val handler = HostHandler(
            surface.engine.services,
            HostHandlerOptions(
                onRender = { view, scopeKey -> applyClientRender(view, scopeKey) },
                onPrintln = { m -> platform().log("info", "NextjsSession[page]: $m") },
            ),
        )
        val timers = VmTimerHostApi(
            { fn, input ->
                if (pageVm != null) {
                    if (input == null) vm.callFunction(fn) else vm.callFunctionWithInput(fn, input)
                }
            },
            { m -> platform().log("warn", "NextjsSession[page timer]: $m") },
        )
        pageTimers = timers
        vm.registerHostHandlers(hostHandlers(handler, timers) { pageVm })
        vm.run()
        if (entryFunction.isNotEmpty()) {
            val initial = vm.callFunction(entryFunction)
            // Only a returned component tree seeds the render (pollers return null).
            val seeded = decodeRenderPayload(initial)
            if (seeded != null && seeded["type"] != null && scriptRendered == null) setScriptRendered(seeded)
        }
        options.onScriptExecuted?.invoke(NextjsScriptResult(currentRoute, "js", ""))
    }

    private fun hostHandlers(handler: HostHandler, timers: VmTimerHostApi, vm: () -> VmRuntimeClient?): Map<String, HostCallHandler> {
        val out = LinkedHashMap<String, HostCallHandler>()
        for (api in allHostApiNames) out[api] = { n, p -> HostReply.of(handler.handleHostCall(n, p)) }
        for (api in timerApiNames) out[api] = { n, p -> HostReply.of(timers.handle(n, p)) }
        // Async work is started and acknowledged at once: guests call askHost
        // synchronously and receive results through their onData/onResult callbacks.
        out["fetch"] = { _, p ->
            val target = vm()
            scope.launch { hostFetch(target, p) }
            HostReply.of(HOST_OK)
        }
        out["submit"] = { _, p ->
            val target = vm()
            scope.launch { hostSubmit(target, p) }
            HostReply.of(HOST_OK)
        }
        out["navigate"] = { _, p -> HostReply.of(hostNavigate(p)) }
        out["mountFragment"] = { _, p ->
            val target = vm()
            scope.launch { hostMountFragment(target, p) }
            HostReply.of(HOST_OK)
        }
        return out
    }

    private suspend fun hostFetch(vm: VmRuntimeClient?, payload: String) {
        try {
            val args = firstArgMap(payload)
            val route = if (args["route"] != null) jsString(args["route"]) else ""
            if (route.isEmpty()) return
            val loader: NextjsPayloadLoader = options.loader ?: { r, o -> httpLoader(r, o) }
            val envelope = loader(route, NextjsLoadOptions(headers = options.headers))
            val onData = if (args["onData"] != null) jsString(args["onData"]) else ""
            if (onData.isNotEmpty() && vm != null) vm.callFunctionWithInput(onData, Json.stringify(envelope))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            platform().log("warn", "NextjsSession[fetch]: ${jsErrorString(e)}")
        }
    }

    private suspend fun hostSubmit(vm: VmRuntimeClient?, payload: String) {
        try {
            val args = firstArgMap(payload)
            val route = if (args["route"] != null) jsString(args["route"]) else ""
            if (route.isEmpty()) return
            val env = postJson(route, args["body"])
            captureAuth(env)
            val nav = env["navigation"]
            if (isMap(nav) && nav.asMap()!!.isNotEmpty()) applyServerNavigation(nav.asMap())
            val onResult = if (args["onResult"] != null) jsString(args["onResult"]) else ""
            if (onResult.isNotEmpty() && vm != null) vm.callFunctionWithInput(onResult, Json.stringify(env))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            platform().log("warn", "NextjsSession[submit]: ${jsErrorString(e)}")
        }
    }

    private suspend fun hostMountFragment(vm: VmRuntimeClient?, payload: String) {
        try {
            val args = firstArgMap(payload)
            val route = if (args["route"] != null) jsString(args["route"]) else ""
            if (route.isEmpty()) return
            val scopeKey = if (args["scopeKey"] != null) jsString(args["scopeKey"]) else null
            val loader: NextjsPayloadLoader = options.loader ?: { r, o -> httpLoader(r, o) }
            val envelope = loader(route, NextjsLoadOptions(headers = options.headers))
            captureAuth(envelope)
            val nav = envelope["navigation"]
            if (isMap(nav) && nav.asMap()!!.isNotEmpty()) applyServerNavigation(nav.asMap())
            val component = envelope["component"]
            if (isMap(component)) {
                val cc = envelope["clientComponents"]
                val resolved = resolveClientComponentNodes(component.asMap()!!, if (isMap(cc)) cc.asMap() else null)
                applyClientRender(resolved, scopeKey)
            }
            val onData = if (args["onData"] != null) jsString(args["onData"]) else ""
            if (onData.isNotEmpty() && vm != null) vm.callFunctionWithInput(onData, Json.stringify(envelope))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            platform().log("warn", "NextjsSession[mountFragment]: ${jsErrorString(e)}")
        }
    }

    private fun hostNavigate(payload: String): String {
        try {
            val nav = firstArgMap(payload)
            if (nav.isNotEmpty()) applyServerNavigation(nav)
        } catch (e: Exception) {
            platform().log("warn", "NextjsSession[page navigate]: ${jsErrorString(e)}")
        }
        return HOST_OK
    }

    private fun applyClientRender(view: JsonMap, scopeKey: String?) {
        if (disposed) return
        val key = ScopePatch.normalizeKey(scopeKey)
        if (key == null) {
            setScriptRendered(view)
            return
        }
        val next = ScopePatch.applyBounded(scriptRendered ?: lastEnvelopeComponent, view, key)
        if (next == null) {
            platform().log("debug", "NextjsSession: scoped render targeted missing scope \"$key\"; keeping current screen.")
            return
        }
        setScriptRendered(next)
    }

    private fun setScriptRendered(component: JsonMap?) {
        if (component == null || disposed) return
        scriptRendered = component
        if (!loading) paint()
    }

    private suspend fun disposePageVm() {
        pageTimers?.dispose()
        pageTimers = null
        val vm = pageVm
        pageVm = null
        if (vm != null) {
            try {
                vm.dispose()
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                /* best effort */
            }
        }
    }

    // ---------------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------------

    private suspend fun routeEvent(event: ElpianEvent) {
        val nodeId = event.currentTarget
        if (nodeId.isNullOrEmpty()) return
        val handler = surface.engine.services.events.getNode(nodeId)?.events?.get(event.type)
        if (handler !is String || handler.isEmpty()) return
        // `<mountId>::<fn>` belongs to a live client component; otherwise the page VM.
        val r = ClientCompRouting.parse(handler)
        val vm = if (r != null) liveComps[r.mountId]?.vm else pageVm
        val fn = r?.fn ?: handler
        if (vm == null) return
        val input: JsonMap = linkedMapOf("type" to event.type)
        val pos = event.position
        if (pos != null) {
            input["x"] = pos.x
            input["y"] = pos.y
        } else if (event.hasValue) {
            input["value"] = event.value
        }
        try {
            vm.callFunctionWithInput(fn, Json.stringify(input))
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            try {
                vm.callFunction(fn)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                platform().log("warn", "NextjsSession: event handler \"$handler\" failed: ${jsErrorString(e)}")
            }
        }
    }

    private suspend fun dispatchSceneTap(props: Map<String, Any?>) {
        val onSceneTap = options.onSceneTap
        if (onSceneTap != null) {
            onSceneTap(props)
            return
        }
        val vm = pageVm
        if (vm != null) {
            try {
                vm.callFunctionWithInput("__onSceneTap", Json.stringify(props))
                return
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                /* fall through to navigation */
            }
        }
        val href = props["panelHref"]
        if (href is String && href.isNotEmpty()) navigate(href)
    }

    fun viewportChanged() {
        surface.viewportChanged()
    }

    suspend fun dispose() {
        if (disposed) return
        disposed = true
        loadGeneration++
        disposePageVm()
        disposeClientComps()
        surface.dispose()
        scope.cancel()
    }

    /** `scheduleMicrotask`: run [fn] on the next dispatch. */
    private fun microtask(fn: () -> Unit) {
        scope.launch { fn() }
    }
}

private suspend fun disposeComp(c: LiveClientComp) {
    c.timer?.dispose()
    c.timer = null
    try {
        c.vm.dispose()
    } catch (e: CancellationException) {
        throw e
    } catch (_: Exception) {
        /* best effort */
    }
}

private val LOOKUP_FIELDS = listOf("clientComponentKey", "componentKey", "componentId", "id", "name", "path", "componentPath", "module")

private fun lookupKeys(node: Map<String, Any?>, props: Map<String, Any?>): List<String> {
    val keys = LinkedHashSet<String>()
    for (src in listOf(node, props)) {
        for (f in LOOKUP_FIELDS) {
            val t = if (src[f] != null) jsString(src[f]).trim() else ""
            if (t.isNotEmpty()) keys.add(t)
        }
    }
    if (keys.isEmpty()) keys.add("anon-${hashString(stableKey(node))}-${hashString(stableKey(props))}")
    return keys.toList()
}

/** `(Math.imul(31, h) + charCode) | 0`, then `Math.abs`. */
private fun hashString(s: String): Long {
    var h = 0
    for (ch in s) h = 31 * h + ch.code
    return Math.abs(h.toLong())
}

private fun normalizePacked(raw: Any?): PackedScript? {
    if (raw is String && raw.isNotBlank()) return PackedScript(raw.trim(), "MainComponent")
    if (isMap(raw)) {
        val m = raw.asMap()!!
        val js = if (m["jsCode"] != null) jsString(m["jsCode"]) else ""
        if (js.isBlank()) return null
        val entry = if (m["jsEntryFunction"] != null) jsString(m["jsEntryFunction"]) else ""
        return PackedScript(js, entry.ifEmpty { "MainComponent" })
    }
    return null
}

private fun decodeRenderPayload(payload: String): JsonMap? {
    try {
        val d = Json.parse(payload)
        if (isMap(d)) {
            val m = d.asMap()!!
            return if (isMap(m["component"])) m["component"].asMap() else m
        }
    } catch (_: Exception) {
        /* plain string */
    }
    return null
}

private fun firstArgMap(payload: String): JsonMap {
    var parsed: Any? = try {
        Json.parse(payload)
    } catch (_: Exception) {
        return LinkedHashMap()
    }
    if (parsed is List<*> && parsed.isNotEmpty()) parsed = parsed[0]
    if (parsed is String) {
        parsed = try {
            Json.parse(parsed)
        } catch (_: Exception) {
            return LinkedHashMap()
        }
    }
    return if (isMap(parsed)) parsed.asMap()!! else LinkedHashMap()
}

private fun firstText(node: Any?): String? {
    if (!isMap(node)) return null
    val m = node.asMap()!!
    val props = m["props"]
    if (isMap(props)) {
        val t = props.asMap()!!["text"]
        if (t is String && t.trim().length > 2 && !t.contains("✕")) return t
    }
    val children = m["children"]
    if (children is List<*>) {
        for (c in children) {
            val r = firstText(c)
            if (r != null) return r
        }
    }
    return null
}

private val ORIGIN = Regex("^([a-zA-Z][\\w+.-]*://[^/?#]+)")
private val TRAILING_SLASHES = Regex("/+$")

private fun originOf(url: String?): String? {
    if (url.isNullOrEmpty()) return null
    return ORIGIN.find(url)?.groupValues?.get(1)
}
