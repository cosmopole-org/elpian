package dev.elpian.core.bridge

import dev.elpian.core.engine.EngineHost
import dev.elpian.core.fullstack.ElpianNetPolicy
import dev.elpian.core.fullstack.ElpianServerClient
import dev.elpian.core.fullstack.ServerComponentOptions
import dev.elpian.core.fullstack.ServerComponentSession
import dev.elpian.core.platform.FetchRequest
import dev.elpian.core.platform.platform
import dev.elpian.core.render.ViewEvent
import dev.elpian.core.scope.ScopePatch
import dev.elpian.core.session.ElpianSurface
import dev.elpian.core.session.InMemoryTokenStore
import dev.elpian.core.session.MiniAppOptions
import dev.elpian.core.session.MiniAppSession
import dev.elpian.core.session.NextjsSession
import dev.elpian.core.session.NextjsSessionOptions
import dev.elpian.core.session.PlatformTokenStore
import dev.elpian.core.session.StreamSession
import dev.elpian.core.session.StreamSessionOptions
import dev.elpian.core.session.SurfaceOptions
import dev.elpian.core.session.copyEngineHost
import dev.elpian.core.session.errorText
import dev.elpian.core.session.nextjsAuthConfig
import dev.elpian.core.session.surfaceById
import dev.elpian.core.superapp.MiniAppGrant
import dev.elpian.core.superapp.MiniAppGrants
import dev.elpian.core.superapp.MiniAppHost
import dev.elpian.core.superapp.MiniAppManifests
import dev.elpian.core.superapp.MountOptions
import dev.elpian.core.util.Json
import dev.elpian.core.util.JsonMap
import dev.elpian.core.util.asMap
import dev.elpian.core.util.deepMerge
import dev.elpian.core.util.isMap
import dev.elpian.core.util.jsString
import dev.elpian.core.vm.ElpianCapability
import dev.elpian.core.vm.Limits
import dev.elpian.core.vm.RuntimeKind
import dev.elpian.core.vm.capabilityFromWireName
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * One registry of the sessions a host app has open, addressed by surface id
 * and driven by JSON (bridge/sessions.ts) — the API every embedding speaks:
 * the Android and iOS hosts and the Expo module.
 *
 * Session kinds:
 *   - `json`      — render Elpian JSON directly (setContent / patch).
 *   - `miniapp`   — a mini app on one of the three runtimes (ElpianVmWidget).
 *   - `superapp`  — a governed third-party mini app (MiniAppHost.launch + mount).
 *   - `stream`    — a view driven by pushed / streamed commands.
 *   - `nextjs`    — a server-driven page (NextjsServerWidget).
 *   - `server`    — a server-rendered component (ServerComponent).
 *
 * Events flow back through the `emit(surface, event, payload)` sink:
 *   ready, error, println, updateApp, routeChanged, scriptExecuted,
 *   scriptError, streamDone, command, sceneTap, callRefused, unservicedApi,
 *   navigate, result (async call results: `{requestId, ok, value | error}`,
 *   from [callAsync]).
 *
 * Payloads are JSON values (maps, lists, strings, Doubles, Booleans, null).
 */
typealias EmitSink = (surface: String, event: String, payload: Any?) -> Unit

class SessionEntry(
    val kind: String,
    val surface: ElpianSurface,
    val dispose: suspend () -> Unit,
    val call: suspend (method: String, args: List<Any?>) -> Any?,
    val viewportChanged: () -> Unit,
)

class SessionException(message: String) : Exception(message)

class SessionRegistry(private val emit: EmitSink) {
    private val entries = LinkedHashMap<String, SessionEntry>()

    /** Where [openAsync] / [callAsync] / [closeAsync] run; cancelled by [shutdown]. */
    val scope: CoroutineScope = CoroutineScope(SupervisorJob() + platform().dispatcher)

    fun has(surfaceId: String): Boolean = entries.containsKey(surfaceId)

    fun get(surfaceId: String): SessionEntry? = entries[surfaceId]

    /** Open a session of [kind] on [surfaceId] (closing any session already there). */
    suspend fun open(kind: String, surfaceId: String, options: Map<String, Any?>) {
        close(surfaceId)
        val emit: (String, Any?) -> Unit = { event, payload -> this.emit(surfaceId, event, payload) }
        val surfaceHost = EngineHost(
            openUrl = { url -> platform().openUrl(url) },
            sceneTap = { props -> emit("sceneTap", props) },
            baseUrl = { options["baseUrl"] as? String },
            navigate = { href, replace -> emit("navigate", linkedMapOf("href" to href, "replace" to replace)) },
        )
        val surfaceOpts = SurfaceOptions(document = options["document"] == true, host = surfaceHost)
        val entry: SessionEntry
        when (kind) {
            "json" -> {
                val surface = ElpianSurface(surfaceId, surfaceOpts)
                if (truthy(options["stylesheet"])) surface.engine.loadStylesheet(options["stylesheet"])
                if (isMap(options["view"])) surface.setContent(options["view"].asMap())
                entry = SessionEntry(
                    kind = kind,
                    surface = surface,
                    dispose = { surface.dispose() },
                    viewportChanged = { surface.viewportChanged() },
                    call = { method, args ->
                        when (method) {
                            "setContent" -> {
                                surface.setContent(if (isMap(args.getOrNull(0))) args[0].asMap() else null)
                                null
                            }
                            "patch" -> {
                                // A scoped render, bounded like the VM's.
                                val view = args.getOrNull(0).asMap() ?: throw SessionException("patch requires a view object")
                                val next = ScopePatch.applyBounded(surface.currentContent, view, args.getOrNull(1)?.let { jsString(it) })
                                if (next != null) surface.setContent(next)
                                next != null
                            }
                            "merge" -> {
                                surface.setContent(deepMerge(surface.currentContent ?: LinkedHashMap(), args.getOrNull(0).asMap() ?: LinkedHashMap()))
                                null
                            }
                            "loadStylesheet" -> {
                                surface.engine.loadStylesheet(args.getOrNull(0))
                                surface.scheduleRender()
                                null
                            }
                            "clearStylesheets" -> {
                                surface.engine.clearStylesheets()
                                surface.scheduleRender()
                                null
                            }
                            else -> throw SessionException("json session has no method $method")
                        }
                    },
                )
            }
            "miniapp" -> {
                val ast = options["ast"]
                val session = MiniAppSession(
                    surfaceId,
                    MiniAppOptions(
                        machineId = jsString(options["machineId"] ?: surfaceId),
                        runtime = runtimeOf(options["runtime"]),
                        code = options["code"] as? String,
                        astJson = (options["astJson"] as? String) ?: (if (isMap(ast)) Json.stringify(ast) else null),
                        bytecodeBase64 = options["bytecodeBase64"] as? String,
                        stylesheet = options["stylesheet"],
                        entryFunction = options["entryFunction"] as? String,
                        entryInput = jsonText(options["entryInput"]),
                        hostEnvironment = if (isMap(options["hostEnvironment"])) options["hostEnvironment"].asMap() else null,
                        showDefaultStates = options["showDefaultStates"] != false,
                        onPrintln = { m -> emit("println", m) },
                        onUpdateApp = { d -> emit("updateApp", d) },
                        onError = { m -> emit("error", m) },
                        onReady = { emit("ready", null) },
                        onCallRefused = { api -> emit("callRefused", api) },
                        onUnservicedApi = { api, advertised -> emit("unservicedApi", linkedMapOf("api" to api, "advertised" to advertised)) },
                        surface = surfaceOpts,
                    ),
                )
                entry = SessionEntry(
                    kind = kind,
                    surface = session.surface,
                    dispose = { session.dispose() },
                    viewportChanged = { session.viewportChanged() },
                    call = { method, args ->
                        val gov = session.runtime?.governor
                        when (method) {
                            "callFunction" -> session.callFunction(jsString(args.getOrNull(0)), jsonText(args.getOrNull(1)))
                            "usage" -> gov?.usage()?.toJson()
                            "state" -> gov?.state()?.toJson()
                            "pause" -> gov?.pause()?.let { null }
                            "resume" -> gov?.resumeExecution()?.let { null }
                            "terminate" -> gov?.terminate()?.let { null }
                            "setLimits" -> gov?.setLimits(Limits.fromJson(args.getOrNull(0).asMap() ?: LinkedHashMap()))?.let { null }
                            "sandbox" -> gov?.sandbox(capsOf(args.getOrNull(0)))?.let { null }
                            "view" -> session.view
                            else -> throw SessionException("miniapp session has no method $method")
                        }
                    },
                )
                session.scope.launch { session.start() }
            }
            "superapp" -> {
                val manifest = MiniAppManifests.fromJson(options["manifest"].asMap() ?: LinkedHashMap())
                val grant = grantOf(options["grant"])
                val host = try {
                    MiniAppHost.launch(manifest = manifest, grant = grant, source = jsString(options["source"] ?: ""))
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    emit("error", errorText(e))
                    null
                } ?: return
                val session = host.mount(
                    surfaceId,
                    MountOptions(
                        stylesheet = options["stylesheet"],
                        entryInput = jsonText(options["entryInput"]),
                        showDefaultStates = options["showDefaultStates"] != false,
                        onPrintln = { m -> emit("println", m) },
                        onUpdateApp = { d -> emit("updateApp", d) },
                        onError = { m -> emit("error", m) },
                        onReady = { emit("ready", linkedMapOf("denied" to host.policy.deniedRequests.map { it.wireName })) },
                        onCallRefused = { api -> emit("callRefused", api) },
                        onUnservicedApi = { api, advertised -> emit("unservicedApi", linkedMapOf("api" to api, "advertised" to advertised)) },
                        surface = surfaceOpts,
                    ),
                )
                entry = SessionEntry(
                    kind = kind,
                    surface = session.surface,
                    dispose = { host.dispose() },
                    viewportChanged = { session.viewportChanged() },
                    call = { method, args ->
                        when (method) {
                            "callFunction" -> session.callFunction(jsString(args.getOrNull(0)), jsonText(args.getOrNull(1)))
                            "usage" -> host.usage().toJson()
                            "branchUsage" -> host.branchUsage().toJson()
                            "pressure" -> LinkedHashMap<String, Any?>(host.pressure())
                            "policy" -> linkedMapOf(
                                "capabilities" to host.policy.capabilities.map { it.wireName },
                                "denied" to host.policy.deniedRequests.map { it.wireName },
                                "limits" to Limits.toJson(host.policy.limits),
                                "mayHostChildren" to host.policy.mayHostChildren,
                            )
                            "spawnChild" -> {
                                val child = host.spawnChild(
                                    manifest = MiniAppManifests.fromJson(args.getOrNull(0).asMap() ?: LinkedHashMap()),
                                    source = jsString(args.getOrNull(1) ?: ""),
                                    grant = if (truthy(args.getOrNull(2))) grantOf(args[2]) else null,
                                )
                                linkedMapOf("machineId" to child.machineId)
                            }
                            "pause" -> host.governor.pause().let { null }
                            "resume" -> host.governor.resumeExecution().let { null }
                            "terminate" -> host.governor.terminate().let { null }
                            else -> throw SessionException("superapp session has no method $method")
                        }
                    },
                )
            }
            "stream" -> {
                val session = StreamSession(
                    surfaceId,
                    StreamSessionOptions(
                        initialStylesheet = if (isMap(options["initialStylesheet"])) options["initialStylesheet"].asMap() else null,
                        defaultAnimationDurationMs = (options["defaultAnimationDurationMs"] as? Number)?.toDouble(),
                        defaultAnimationCurve = options["defaultAnimationCurve"] as? String,
                        onCommand = { c -> emit("command", c.toJson()) },
                        onStreamDone = { emit("streamDone", null) },
                        onError = { m -> emit("error", m) },
                        surface = surfaceOpts,
                    ),
                )
                if (isMap(options["request"])) session.connect(fetchRequestOf(options["request"].asMap()!!))
                entry = SessionEntry(
                    kind = kind,
                    surface = session.surface,
                    dispose = { session.dispose() },
                    viewportChanged = { session.surface.viewportChanged() },
                    call = { method, args ->
                        when (method) {
                            "push" -> {
                                session.push(args.getOrNull(0))
                                null
                            }
                            "error" -> {
                                session.error(args.getOrNull(0))
                                null
                            }
                            "done" -> {
                                session.done()
                                null
                            }
                            "connect" -> {
                                session.connect(fetchRequestOf(args.getOrNull(0).asMap() ?: LinkedHashMap()))
                                null
                            }
                            else -> throw SessionException("stream session has no method $method")
                        }
                    },
                )
            }
            "nextjs" -> {
                val a = options["auth"]
                val auth = if (isMap(a)) {
                    val am = a.asMap()!!
                    nextjsAuthConfig(
                        store = if (am["persist"] == false) InMemoryTokenStore() else PlatformTokenStore(jsString(am["namespace"] ?: "elpian")),
                        loginRoute = am["loginRoute"] as? String,
                        refreshRoute = am["refreshRoute"] as? String,
                        bearerScheme = am["bearerScheme"] as? String,
                    )
                } else null
                val nextHost = copyEngineHost(surfaceHost)
                nextHost.navigate = null
                val headers = options["headers"]
                val session = NextjsSession(
                    surfaceId,
                    NextjsSessionOptions(
                        route = jsString(options["route"] ?: "/"),
                        serverBaseUrl = options["serverBaseUrl"] as? String,
                        endpoint = options["endpoint"] as? String,
                        requestMode = if (options["requestMode"] == "apiEndpoint") "apiEndpoint" else "routePath",
                        props = if (isMap(options["props"])) options["props"].asMap() else null,
                        headers = if (isMap(headers)) headers.asMap()!!.entries.associate { (k, v) -> k to jsString(v) } else null,
                        auth = auth,
                        timeoutMs = (options["timeoutMs"] as? Number)?.toDouble(),
                        onScriptExecuted = { r -> emit("scriptExecuted", r.toJson()) },
                        onScriptError = { e -> emit("scriptError", jsErrorText(e)) },
                        onRouteChanged = { route -> emit("routeChanged", route) },
                        onSceneTap = if (options["handleSceneTaps"] == true) ({ p -> emit("sceneTap", p) }) else null,
                        surface = surfaceOpts.copy(host = nextHost),
                    ),
                )
                entry = SessionEntry(
                    kind = kind,
                    surface = session.surface,
                    dispose = { session.dispose() },
                    viewportChanged = { session.viewportChanged() },
                    call = { method, args ->
                        when (method) {
                            "navigate" -> {
                                session.navigate(jsString(args.getOrNull(0)), args.getOrNull(1) == true)
                                null
                            }
                            "back" -> session.back()
                            "refresh" -> {
                                session.refresh()
                                null
                            }
                            "route" -> session.route
                            "canGoBack" -> session.canGoBack
                            else -> throw SessionException("nextjs session has no method $method")
                        }
                    },
                )
            }
            "server" -> {
                val client = ElpianServerClient(
                    jsString(options["baseUrl"] ?: ""),
                    jsString(options["appId"] ?: ""),
                    ElpianNetPolicy.fromManifest(options["netPolicy"]),
                    if (options["authorization"] != null) jsString(options["authorization"]) else null,
                    (options["timeoutMs"] as? Number)?.toDouble() ?: 15000.0,
                )
                val islands = options["nativeIslands"]
                val session = ServerComponentSession(
                    surfaceId,
                    ServerComponentOptions(
                        client = client,
                        name = jsString(options["name"] ?: ""),
                        args = if (isMap(options["args"])) options["args"].asMap() else LinkedHashMap(),
                        nativeIslands = if (isMap(islands)) islands.asMap()!!.entries.associate { (k, v) -> k to jsString(v) } else null,
                        revalidateMs = (options["revalidateMs"] as? Number)?.toDouble(),
                        surface = surfaceOpts,
                    ),
                )
                entry = SessionEntry(
                    kind = kind,
                    surface = session.surface,
                    dispose = {
                        session.dispose()
                        client.close()
                    },
                    viewportChanged = { session.surface.viewportChanged() },
                    call = { method, args ->
                        when (method) {
                            "update" -> {
                                session.update(args.getOrNull(0).asMap() ?: LinkedHashMap())
                                null
                            }
                            "refresh" -> session.fetch().let { null }
                            "callAction" -> client.callAction(jsString(args.getOrNull(0)), args.getOrNull(1).asMap() ?: LinkedHashMap()).toJson()
                            "unresolvedIslands" -> session.unresolvedIslands()
                            else -> throw SessionException("server session has no method $method")
                        }
                    },
                )
            }
            else -> throw SessionException("unknown session kind \"$kind\"")
        }
        entries[surfaceId] = entry
    }

    suspend fun call(surfaceId: String, method: String, args: List<Any?>): Any? {
        val e = entries[surfaceId] ?: throw SessionException("no session on surface \"$surfaceId\"")
        return e.call(method, args)
    }

    fun dispatchViewEvent(surfaceId: String, event: ViewEvent) {
        surfaceById(surfaceId)?.dispatchViewEvent(event)
    }

    fun viewportChanged(surfaceId: String) {
        val e = entries[surfaceId]
        if (e != null) e.viewportChanged() else surfaceById(surfaceId)?.viewportChanged()
    }

    /** An image finished loading: every surface showing it relayouts. */
    fun imageLoaded(src: String, width: Double, height: Double) {
        for (e in entries.values) e.surface.imageLoaded(src, width, height)
    }

    /** Fonts loaded / changed: re-measure text everywhere. */
    fun invalidateText() {
        for (e in entries.values) {
            e.surface.invalidateText()
            e.surface.scheduleRender()
        }
    }

    suspend fun close(surfaceId: String) {
        val e = entries.remove(surfaceId) ?: return
        e.dispose()
    }

    suspend fun closeAll() {
        for (id in entries.keys.toList()) close(id)
    }

    // ---- fire-and-forget forms for hosts on the UI thread (no TS counterpart: TS callers await Promises) ----

    /** [open] on [scope]; a failure is emitted as `error`. */
    fun openAsync(kind: String, surfaceId: String, options: Map<String, Any?>): Job = scope.launch {
        try {
            open(kind, surfaceId, options)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            emit(surfaceId, "error", errorText(e))
        }
    }

    /** [call] on [scope]; the outcome is emitted as `result` `{requestId, ok, value | error}`. */
    fun callAsync(surfaceId: String, method: String, args: List<Any?>, requestId: Any?): Job = scope.launch {
        val payload: JsonMap = try {
            linkedMapOf("requestId" to requestId, "ok" to true, "value" to call(surfaceId, method, args))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            linkedMapOf("requestId" to requestId, "ok" to false, "error" to errorText(e))
        }
        emit(surfaceId, "result", payload)
    }

    fun closeAsync(surfaceId: String): Job = scope.launch { close(surfaceId) }

    /** Close every session and stop the registry's scope. */
    suspend fun shutdown() {
        closeAll()
        scope.cancel()
    }
}

private fun truthy(v: Any?): Boolean = when (v) {
    null -> false
    is Boolean -> v
    is String -> v.isNotEmpty()
    is Number -> v.toDouble() != 0.0 && !v.toDouble().isNaN()
    else -> true
}

/** A string as is; any other value as JSON text; null stays null. */
private fun jsonText(v: Any?): String? = when (v) {
    null -> null
    is String -> v
    else -> Json.stringify(v)
}

/** `String(e)` for a script error. */
private fun jsErrorText(e: Throwable): String = "Error: ${e.message ?: e.toString()}"

private fun runtimeOf(v: Any?): RuntimeKind =
    if (v == "quickjs" || v == "quickJs") RuntimeKind.QUICKJS else if (v == "wasm") RuntimeKind.WASM else RuntimeKind.ELPIAN

private fun capsOf(v: Any?): Set<ElpianCapability> {
    val out = LinkedHashSet<ElpianCapability>()
    if (v is List<*>) for (x in v) {
        val c = capabilityFromWireName(jsString(x))
        if (c != null) out.add(c)
    }
    return out
}

private fun grantOf(v: Any?): MiniAppGrant {
    if (v == "trusted") return MiniAppGrants.trusted
    if (!isMap(v)) return MiniAppGrants.untrusted
    val m = v.asMap()!!
    val base = if (m["base"] == "trusted") MiniAppGrants.trusted else MiniAppGrants.untrusted
    return MiniAppGrant(
        capabilities = if (m["capabilities"] is List<*>) capsOf(m["capabilities"]) else base.capabilities,
        limits = if (isMap(m["limits"])) Limits.fromJson(m["limits"].asMap()!!) else base.limits,
        mayHostChildren = (m["mayHostChildren"] as? Boolean) ?: base.mayHostChildren,
        allowedApis = (m["allowedApis"] as? List<*>)?.mapTo(LinkedHashSet()) { jsString(it) } ?: base.allowedApis,
    )
}

/** A `FetchRequest` from its JSON form (`{url, method?, headers?, body?, timeoutMs?}`). */
fun fetchRequestOf(j: Map<String, Any?>): FetchRequest {
    val headers = j["headers"]
    return FetchRequest(
        url = jsString(j["url"] ?: ""),
        method = (j["method"] as? String) ?: "GET",
        headers = if (isMap(headers)) headers.asMap()!!.entries.associate { (k, v) -> k to jsString(v) } else emptyMap(),
        body = when (val b = j["body"]) {
            null -> null
            is String -> b
            else -> Json.stringify(b)
        },
        timeoutMs = (j["timeoutMs"] as? Number)?.toLong(),
    )
}
