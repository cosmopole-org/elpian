package dev.elpian.core.host

import dev.elpian.core.canvas.CanvasCommand
import dev.elpian.core.canvas.commandFromJson
import dev.elpian.core.canvas.isCanvasCommandType
import dev.elpian.core.engine.ElpianServices
import dev.elpian.core.util.JsonMap
import dev.elpian.core.util.Typed
import dev.elpian.core.util.asHostArgs
import dev.elpian.core.util.coerceJsonMap
import dev.elpian.core.util.jsString
import dev.elpian.core.util.normalizedArgs
import dev.elpian.core.util.parseVmPayload
import dev.elpian.core.util.toNumber
import dev.elpian.core.util.unwrapHostArgs
import dev.elpian.core.vm.HostCallHandler
import dev.elpian.core.vm.HostReply
import dev.elpian.core.vm.allHostApiNames
import dev.elpian.core.vm.canvasApiNames
import dev.elpian.core.vm.domApiNames

/**
 * Services a guest's host calls (host/host-handler.ts) — a port of
 * `HostHandler` (flutter/lib/src/vm/host_handler.dart). Every runtime (Elpian
 * VM, QuickJS, WASM) funnels `askHost(api, payload)` here; replies are typed
 * JSON envelopes (`{"type", "data": {"value"}}`).
 */
typealias RenderHostCallback = (viewJson: JsonMap, scopeKey: String?) -> Unit

class HostHandlerOptions(
    val onRender: RenderHostCallback? = null,
    val onUpdateApp: ((updateData: JsonMap) -> Unit)? = null,
    val onPrintln: ((message: String) -> Unit)? = null,
    val onGetEnvironment: (() -> JsonMap)? = null,
    /** A guest reached for an API this handler does not implement. */
    val onUnservicedApi: ((apiName: String, advertised: Boolean) -> Unit)? = null,
    /** Consulted before every call; return false to refuse it. */
    val onAuthorize: ((apiName: String) -> Boolean)? = null,
    /** [onAuthorize] refused a call. */
    val onCallRefused: ((apiName: String) -> Unit)? = null,
    val log: ((message: String) -> Unit)? = null,
)

class HostHandler(val services: ElpianServices, val options: HostHandlerOptions = HostHandlerOptions()) {
    val dom: ElpianDOM get() = services.dom

    private fun scoped(id: String): String = services.scopeId(id)

    private fun log(message: String) {
        options.log?.invoke(message)
    }

    /** This handler as a runtime's synchronous [HostCallHandler]. */
    fun asHostCallHandler(): HostCallHandler = { apiName, payload -> HostReply.of(handleHostCall(apiName, payload)) }

    fun handleHostCall(apiName: String, payload: String): String {
        val onAuthorize = options.onAuthorize
        if (onAuthorize != null && !onAuthorize(apiName)) {
            options.onCallRefused?.invoke(apiName)
            log("HostHandler[${services.appId}]: $apiName refused by policy")
            // The typed null the VM produces for a denied capability.
            return Typed.NULL
        }
        if (apiName in domApiNames) return handleDomApi(apiName, payload)
        if (apiName in canvasApiNames) return handleCanvasApi(apiName, payload)
        return when (apiName) {
            "render" -> handleRender(payload)
            "updateApp" -> handleUpdateApp(payload)
            "println" -> handlePrintln(payload)
            "env.get" -> handleEnvGet()
            "stringify" -> Typed.response("string", payload)
            else -> unserviced(apiName)
        }
    }

    private fun unserviced(apiName: String): String {
        val known = apiName in allHostApiNames
        options.onUnservicedApi?.invoke(apiName, known)
        log(
            if (known) "HostHandler: $apiName is advertised by the VM but not serviced here; returning null"
            else "HostHandler: unknown host API $apiName; returning null",
        )
        return Typed.NULL
    }

    fun handleRender(payload: String): String {
        try {
            val args = asHostArgs(parseVmPayload(payload))
            val viewArg = args.firstOrNull()
            val scopeKey = if (args.size > 1) asNullableString(args[1]) else null
            val viewJson = coerceJsonMap(viewArg)
            if (viewJson != null) options.onRender?.invoke(viewJson, scopeKey)
            else if (viewArg is String) options.onRender?.invoke(linkedMapOf("type" to "Text", "props" to linkedMapOf<String, Any?>("text" to viewArg)), scopeKey)
        } catch (e: Exception) {
            log("HostHandler: render error: $e")
        }
        return Typed.OK
    }

    @Suppress("UNCHECKED_CAST")
    fun handleUpdateApp(payload: String): String {
        try {
            val parsed = unwrapHostArgs(parseVmPayload(payload))
            if (parsed is Map<*, *>) options.onUpdateApp?.invoke(LinkedHashMap(parsed as Map<String, Any?>))
        } catch (e: Exception) {
            log("HostHandler: updateApp error: $e")
        }
        return Typed.OK
    }

    fun handlePrintln(payload: String): String {
        val parsed = unwrapHostArgs(parseVmPayload(payload))
        options.onPrintln?.invoke(if (parsed is String) parsed else payload)
        return Typed.OK
    }

    fun handleEnvGet(): String = Typed.response("object", options.onGetEnvironment?.invoke() ?: LinkedHashMap<String, Any?>())

    // ---------------------------------------------------------------------------
    // dom.*
    // ---------------------------------------------------------------------------

    @Suppress("UNCHECKED_CAST")
    private fun handleDomApi(apiName: String, payload: String): String {
        try {
            val args = normalizedArgs(payload)
            val dom = this.dom
            fun s(k: String): String = if (args[k] == null) "" else jsString(args[k])
            fun el(key: String = "id"): ElpianElement? = elementFromArgs(args, key)
            when (apiName) {
                "dom.createElement" -> {
                    val classes = (args["classes"] as? List<*>)?.map { jsString(it) }
                    return Typed.response(
                        "object",
                        encodeElement(dom.createElement(args["tagName"]?.let { jsString(it) } ?: "div", id = args["id"]?.let { jsString(it) }, classes = classes)),
                    )
                }
                "dom.getElementById" -> return Typed.response("object", encodeElement(dom.getElementById(s("id"))))
                "dom.getElementsByClassName" -> return Typed.response("array", encodeElements(dom.getElementsByClassName(s("className"))))
                "dom.getElementsByTagName" -> return Typed.response("array", encodeElements(dom.getElementsByTagName(s("tagName"))))
                "dom.querySelector" -> return Typed.response("object", encodeElement(dom.querySelector(s("selector"))))
                "dom.querySelectorAll" -> return Typed.response("array", encodeElements(dom.querySelectorAll(s("selector"))))
                "dom.removeElement" -> {
                    el()?.let { dom.removeElement(it) }
                    return Typed.OK
                }
                "dom.clear" -> {
                    dom.clear()
                    return Typed.OK
                }
                "dom.setTextContent" -> {
                    el()?.let { it.textContent = args["text"]?.let { t -> jsString(t) } }
                    return Typed.OK
                }
                "dom.setInnerHtml" -> {
                    el()?.let { it.innerHTML = args["html"]?.let { h -> jsString(h) } }
                    return Typed.OK
                }
                "dom.setAttribute" -> {
                    el()?.setAttribute(s("name"), args["value"])
                    return Typed.OK
                }
                "dom.getAttribute" -> return Typed.response("string", jsString(el()?.getAttribute(s("name")) ?: ""))
                "dom.removeAttribute" -> {
                    el()?.removeAttribute(s("name"))
                    return Typed.OK
                }
                "dom.hasAttribute" -> return Typed.response("bool", el()?.hasAttribute(s("name")) ?: false)
                "dom.setStyle" -> {
                    el()?.setStyle(s("property"), args["value"])
                    return Typed.OK
                }
                "dom.getStyle" -> return Typed.response("string", jsString(el()?.getStyle(s("property")) ?: ""))
                "dom.setStyleObject" -> {
                    el()?.setStyleObject(args["styles"] as? Map<String, Any?> ?: emptyMap())
                    return Typed.OK
                }
                "dom.addClass" -> {
                    el()?.addClass(s("className"))
                    return Typed.OK
                }
                "dom.removeClass" -> {
                    el()?.removeClass(s("className"))
                    return Typed.OK
                }
                "dom.hasClass" -> return Typed.response("bool", el()?.hasClass(s("className")) ?: false)
                "dom.toggleClass" -> {
                    el()?.toggleClass(s("className"))
                    return Typed.OK
                }
                "dom.appendChild" -> {
                    val parent = el("parentId")
                    val child = el("childId")
                    if (parent != null && child != null) parent.appendChild(child)
                    return Typed.OK
                }
                "dom.insertBefore" -> {
                    val parent = el("parentId")
                    val child = el("newChildId")
                    if (parent != null && child != null) parent.insertBefore(child, el("referenceChildId"))
                    return Typed.OK
                }
                "dom.removeChild" -> {
                    val parent = el("parentId")
                    val child = el("childId")
                    if (parent != null && child != null) parent.removeChild(child)
                    return Typed.OK
                }
                "dom.replaceChild" -> {
                    val parent = el("parentId")
                    val fresh = el("newChildId")
                    val old = el("oldChildId")
                    if (parent != null && fresh != null && old != null) parent.replaceChild(fresh, old)
                    return Typed.OK
                }
                "dom.addEventListener" -> {
                    val e = el()
                    val event = s("event")
                    val callback = args["callback"]?.let { jsString(it) }
                    if (e != null && callback != null) {
                        e.addEventListener(event) { data ->
                            val update = linkedMapOf<String, Any?>("domEvent" to callback, "elementId" to e.id, "event" to event)
                            if (data != null) update["data"] = data
                            options.onUpdateApp?.invoke(update)
                        }
                    }
                    return Typed.OK
                }
                "dom.removeEventListener" -> {
                    el()?.removeEventListener(s("event"))
                    return Typed.OK
                }
                "dom.dispatchEvent" -> {
                    el()?.dispatchEvent(s("event"), args["data"])
                    return Typed.OK
                }
                "dom.toJson" -> {
                    val e = el()
                    return Typed.response("object", e?.toJson() ?: LinkedHashMap<String, Any?>())
                }
                "dom.getAllElements" -> return Typed.response("array", encodeElements(dom.allElements))
            }
            return Typed.OK
        } catch (e: Exception) {
            log("HostHandler: dom API error ($apiName): $e")
            return Typed.OK
        }
    }

    private fun elementFromArgs(args: JsonMap, key: String): ElpianElement? {
        val raw = args[key] ?: args["selector"]
        val id = if (raw == null) "" else jsString(raw)
        if (id.isEmpty()) return null
        return dom.getElementById(id) ?: dom.querySelector(id)
    }

    // ---------------------------------------------------------------------------
    // canvas.*
    // ---------------------------------------------------------------------------

    private fun handleCanvasApi(apiName: String, payload: String): String {
        try {
            if (apiName.startsWith("canvas.ctx.")) return handleCanvasContextApi(apiName, payload)
            val args = normalizedArgs(payload)
            val canvas = services.canvas
            when (apiName) {
                "canvas.clear" -> {
                    canvas.clear()
                    return Typed.OK
                }
                "canvas.getCommands" -> return Typed.response(
                    "array",
                    canvas.commands.map { c ->
                        linkedMapOf<String, Any?>("type" to c.type, "params" to c.params).also { m -> if (c.id != null) m["id"] = c.id }
                    },
                )
                "canvas.addCommand" -> {
                    commandFromArgs(args)?.let { canvas.addCommand(it) }
                    return Typed.OK
                }
                "canvas.addCommands" -> {
                    canvas.addCommands((args["commands"] as? List<*> ?: emptyList<Any?>()).filter { it is Map<*, *> }.map { commandFromJson(it) })
                    return Typed.OK
                }
            }
            val name = apiName.removePrefix("canvas.")
            if (isCanvasCommandType(name)) canvas.addCommand(CanvasCommand(name, args))
            return Typed.OK
        } catch (e: Exception) {
            log("HostHandler: canvas API error ($apiName): $e")
            return Typed.OK
        }
    }

    private fun handleCanvasContextApi(apiName: String, payload: String): String {
        val args = normalizedArgs(payload)
        val store = services.canvasContexts
        val id = args["id"]?.let { jsString(it) }
        fun ctx() = if (id == null) null else store[scoped(id)]
        when (apiName) {
            "canvas.ctx.create" -> {
                val created = store.create(
                    id = if (id.isNullOrEmpty()) null else scoped(id),
                    width = toNumber(args["width"]) ?: 0.0,
                    height = toNumber(args["height"]) ?: 0.0,
                )
                // The guest's own id: later calls scope it again on the way in.
                return Typed.response("string", id ?: created.id)
            }
            "canvas.ctx.dispose" -> {
                if (!id.isNullOrEmpty()) store.dispose(scoped(id))
                return Typed.OK
            }
            "canvas.ctx.clear" -> {
                ctx()?.clear()
                return Typed.OK
            }
            "canvas.ctx.setSize" -> {
                val c = ctx()
                if (c != null) c.setSize(toNumber(args["width"]) ?: c.width, toNumber(args["height"]) ?: c.height)
                return Typed.OK
            }
            "canvas.ctx.addCommand" -> {
                val c = ctx()
                val json = args["command"] ?: args
                if (c != null && json is Map<*, *>) c.addCommand(commandFromJson(json))
                return Typed.OK
            }
            "canvas.ctx.addCommands" -> {
                val c = ctx()
                val commands = args["commands"]
                if (c != null && commands is List<*>) c.addCommands(commands.filter { it is Map<*, *> }.map { commandFromJson(it) })
                return Typed.OK
            }
        }
        return Typed.OK
    }
}

@Suppress("UNCHECKED_CAST")
private fun commandFromArgs(args: JsonMap): CanvasCommand? {
    val t = args["type"]?.let { jsString(it) }
    if (t.isNullOrEmpty() || !isCanvasCommandType(t)) return null
    val params = (args["params"] as? Map<String, Any?>)?.let { LinkedHashMap(it) } ?: LinkedHashMap()
    return CanvasCommand(t, params, args["id"]?.let { jsString(it) })
}

private fun encodeElement(e: ElpianElement?): JsonMap? = e?.encode()

private fun encodeElements(list: List<ElpianElement>): List<JsonMap> = list.map { it.encode() }

private fun asNullableString(value: Any?): String? {
    if (value == null) return null
    val s = jsString(value).trim()
    return if (s == "" || s == "null") null else s
}
