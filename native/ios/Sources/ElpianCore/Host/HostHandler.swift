import Foundation

/**
 * Services a guest's host calls (host/host-handler.ts) — a port of
 * `HostHandler` (flutter/lib/src/vm/host_handler.dart). Every runtime (Elpian
 * VM, QuickJS, WASM) funnels `askHost(api, payload)` here; replies are typed
 * JSON envelopes (`{"type", "data": {"value"}}`).
 *
 * The TypeScript handlers wrap their bodies in try/catch to log and answer
 * `OK` on a throwing DOM or canvas call; the Swift DOM and canvas stores do not
 * throw, so every path answers directly.
 */
public typealias RenderHostCallback = (_ viewJson: JSONObject, _ scopeKey: String?) -> Void

public struct HostHandlerOptions {
    public var onRender: RenderHostCallback?
    public var onUpdateApp: ((_ updateData: JSONObject) -> Void)?
    public var onPrintln: ((_ message: String) -> Void)?
    public var onGetEnvironment: (() -> JSONObject)?
    /** A guest reached for an API this handler does not implement. */
    public var onUnservicedApi: ((_ apiName: String, _ advertised: Bool) -> Void)?
    /** Consulted before every call; return false to refuse it. */
    public var onAuthorize: ((_ apiName: String) -> Bool)?
    /** [onAuthorize] refused a call. */
    public var onCallRefused: ((_ apiName: String) -> Void)?
    public var log: ((_ message: String) -> Void)?

    public init(
        onRender: RenderHostCallback? = nil,
        onUpdateApp: ((_ updateData: JSONObject) -> Void)? = nil,
        onPrintln: ((_ message: String) -> Void)? = nil,
        onGetEnvironment: (() -> JSONObject)? = nil,
        onUnservicedApi: ((_ apiName: String, _ advertised: Bool) -> Void)? = nil,
        onAuthorize: ((_ apiName: String) -> Bool)? = nil,
        onCallRefused: ((_ apiName: String) -> Void)? = nil,
        log: ((_ message: String) -> Void)? = nil
    ) {
        self.onRender = onRender
        self.onUpdateApp = onUpdateApp
        self.onPrintln = onPrintln
        self.onGetEnvironment = onGetEnvironment
        self.onUnservicedApi = onUnservicedApi
        self.onAuthorize = onAuthorize
        self.onCallRefused = onCallRefused
        self.log = log
    }
}

public final class HostHandler {
    public let services: ElpianServices
    public let options: HostHandlerOptions

    public init(services: ElpianServices, options: HostHandlerOptions = HostHandlerOptions()) {
        self.services = services
        self.options = options
    }

    public var dom: ElpianDOM { services.dom }

    private func scoped(_ id: String) -> String { services.scopeId(id) }

    private func log(_ message: String) {
        options.log?(message)
    }

    /** This handler as a runtime's synchronous [HostCallHandler]. */
    public func asHostCallHandler() -> HostCallHandler {
        return { [self] apiName, payload in self.handleHostCallReply(apiName, payload) }
    }

    /**
     * Service one host call as a runtime reply. Most APIs answer synchronously;
     * the agent APIs (`agent.send`, `agent.action`, `a2ui.dataModel`) answer
     * later, once the agent named the conversation (the TypeScript handler's
     * Promise).
     */
    public func handleHostCallReply(_ apiName: String, _ payload: String) -> HostReply {
        guard AGENT_API_NAMES.contains(apiName) else { return .now(handleHostCall(apiName, payload)) }
        if let onAuthorize = options.onAuthorize, !onAuthorize(apiName) {
            options.onCallRefused?(apiName)
            log("HostHandler[\(services.appId)]: \(apiName) refused by policy")
            return .now(Typed.NULL_RESPONSE)
        }
        let services = self.services
        return HostReply.deferred { await handleAgentHostCall(services, apiName, payload) }
    }

    public func handleHostCall(_ apiName: String, _ payload: String) -> String {
        if let onAuthorize = options.onAuthorize, !onAuthorize(apiName) {
            options.onCallRefused?(apiName)
            log("HostHandler[\(services.appId)]: \(apiName) refused by policy")
            // The typed null the VM produces for a denied capability.
            return Typed.NULL_RESPONSE
        }
        // Synchronous callers: the turn starts and the answer carries what is known now (see handleHostCallReply).
        if AGENT_API_NAMES.contains(apiName) { return handleAgentHostCallNow(services, apiName, payload) }
        if HostApiCatalog.domApiNames.contains(apiName) { return handleDomApi(apiName, payload) }
        if HostApiCatalog.canvasApiNames.contains(apiName) { return handleCanvasApi(apiName, payload) }
        switch apiName {
        case "render": return handleRender(payload)
        case "updateApp": return handleUpdateApp(payload)
        case "println": return handlePrintln(payload)
        case "env.get": return handleEnvGet()
        case "stringify": return Typed.makeResponse("string", payload)
        default: return unserviced(apiName)
        }
    }

    private func unserviced(_ apiName: String) -> String {
        let known = HostApiCatalog.allHostApiNames.contains(apiName)
        options.onUnservicedApi?(apiName, known)
        log(known
            ? "HostHandler: \(apiName) is advertised by the VM but not serviced here; returning null"
            : "HostHandler: unknown host API \(apiName); returning null")
        return Typed.NULL_RESPONSE
    }

    public func handleRender(_ payload: String) -> String {
        let args = asHostArgs(parseVmPayload(payload))
        let viewArg = args.first ?? nil
        let scopeKey = args.count > 1 ? asNullableString(args[1]) : nil
        if let viewJson = coerceJsonMap(viewArg) {
            options.onRender?(viewJson, scopeKey)
        } else if let s = flattenOptional(viewArg) as? String {
            options.onRender?(JSONObject([("type", "Text"), ("props", JSONObject([("text", s)]))]), scopeKey)
        }
        return Typed.OK_RESPONSE
    }

    public func handleUpdateApp(_ payload: String) -> String {
        let parsed = unwrapHostArgs(parseVmPayload(payload))
        if let m = asMap(parsed) { options.onUpdateApp?(m) }
        return Typed.OK_RESPONSE
    }

    public func handlePrintln(_ payload: String) -> String {
        let parsed = unwrapHostArgs(parseVmPayload(payload))
        options.onPrintln?((flattenOptional(parsed) as? String) ?? payload)
        return Typed.OK_RESPONSE
    }

    public func handleEnvGet() -> String {
        Typed.makeResponse("object", options.onGetEnvironment?() ?? JSONObject())
    }

    // ---------------------------------------------------------------------------
    // dom.*
    // ---------------------------------------------------------------------------

    private func handleDomApi(_ apiName: String, _ payload: String) -> String {
        let args = normalizedArgs(payload)
        let dom = self.dom
        func s(_ k: String) -> String { args[k] == nil ? "" : jsString(args[k]) }
        func el(_ key: String = "id") -> ElpianElement? { elementFromArgs(args, key) }
        switch apiName {
        case "dom.createElement":
            let classes = asArray(args["classes"])?.map { jsString($0) }
            let tagName = args["tagName"] != nil ? jsString(args["tagName"]) : "div"
            let id = args["id"] != nil ? jsString(args["id"]) : nil
            return Typed.makeResponse("object", encodeElement(dom.createElement(tagName, id: id, classes: classes)))
        case "dom.getElementById":
            return Typed.makeResponse("object", encodeElement(dom.getElementById(s("id"))))
        case "dom.getElementsByClassName":
            return Typed.makeResponse("array", encodeElements(dom.getElementsByClassName(s("className"))))
        case "dom.getElementsByTagName":
            return Typed.makeResponse("array", encodeElements(dom.getElementsByTagName(s("tagName"))))
        case "dom.querySelector":
            return Typed.makeResponse("object", encodeElement(dom.querySelector(s("selector"))))
        case "dom.querySelectorAll":
            return Typed.makeResponse("array", encodeElements(dom.querySelectorAll(s("selector"))))
        case "dom.removeElement":
            if let e = el() { dom.removeElement(e) }
            return Typed.OK_RESPONSE
        case "dom.clear":
            dom.clear()
            return Typed.OK_RESPONSE
        case "dom.setTextContent":
            if let e = el() { e.textContent = args["text"] != nil ? jsString(args["text"]) : nil }
            return Typed.OK_RESPONSE
        case "dom.setInnerHtml":
            if let e = el() { e.innerHTML = args["html"] != nil ? jsString(args["html"]) : nil }
            return Typed.OK_RESPONSE
        case "dom.setAttribute":
            el()?.setAttribute(s("name"), args["value"])
            return Typed.OK_RESPONSE
        case "dom.getAttribute":
            return Typed.makeResponse("string", jsString(el()?.getAttribute(s("name")) ?? ""))
        case "dom.removeAttribute":
            el()?.removeAttribute(s("name"))
            return Typed.OK_RESPONSE
        case "dom.hasAttribute":
            return Typed.makeResponse("bool", el()?.hasAttribute(s("name")) ?? false)
        case "dom.setStyle":
            el()?.setStyle(s("property"), args["value"])
            return Typed.OK_RESPONSE
        case "dom.getStyle":
            return Typed.makeResponse("string", jsString(el()?.getStyle(s("property")) ?? ""))
        case "dom.setStyleObject":
            el()?.setStyleObject(asMap(args["styles"]) ?? JSONObject())
            return Typed.OK_RESPONSE
        case "dom.addClass":
            el()?.addClass(s("className"))
            return Typed.OK_RESPONSE
        case "dom.removeClass":
            el()?.removeClass(s("className"))
            return Typed.OK_RESPONSE
        case "dom.hasClass":
            return Typed.makeResponse("bool", el()?.hasClass(s("className")) ?? false)
        case "dom.toggleClass":
            el()?.toggleClass(s("className"))
            return Typed.OK_RESPONSE
        case "dom.appendChild":
            if let parent = el("parentId"), let child = el("childId") { parent.appendChild(child) }
            return Typed.OK_RESPONSE
        case "dom.insertBefore":
            if let parent = el("parentId"), let child = el("newChildId") { parent.insertBefore(child, el("referenceChildId")) }
            return Typed.OK_RESPONSE
        case "dom.removeChild":
            if let parent = el("parentId"), let child = el("childId") { parent.removeChild(child) }
            return Typed.OK_RESPONSE
        case "dom.replaceChild":
            if let parent = el("parentId"), let fresh = el("newChildId"), let old = el("oldChildId") { parent.replaceChild(fresh, old) }
            return Typed.OK_RESPONSE
        case "dom.addEventListener":
            let event = s("event")
            let callback = args["callback"] != nil ? jsString(args["callback"]) : nil
            if let e = el(), let cb = callback {
                let onUpdateApp = options.onUpdateApp
                let elementId = e.id
                e.addEventListener(event) { data in
                    let update = JSONObject([("domEvent", cb), ("elementId", elementId), ("event", event)])
                    if let d = flattenOptional(data) { update["data"] = d }
                    onUpdateApp?(update)
                }
            }
            return Typed.OK_RESPONSE
        case "dom.removeEventListener":
            el()?.removeEventListener(s("event"))
            return Typed.OK_RESPONSE
        case "dom.dispatchEvent":
            el()?.dispatchEvent(s("event"), args["data"])
            return Typed.OK_RESPONSE
        case "dom.toJson":
            return Typed.makeResponse("object", el()?.toJson() ?? JSONObject())
        case "dom.getAllElements":
            return Typed.makeResponse("array", encodeElements(dom.allElements))
        default:
            return Typed.OK_RESPONSE
        }
    }

    private func elementFromArgs(_ args: JSONObject, _ key: String) -> ElpianElement? {
        let raw = args[key] ?? args["selector"]
        let id = raw == nil ? "" : jsString(raw)
        if id.isEmpty { return nil }
        return dom.getElementById(id) ?? dom.querySelector(id)
    }

    // ---------------------------------------------------------------------------
    // canvas.*
    // ---------------------------------------------------------------------------

    private func handleCanvasApi(_ apiName: String, _ payload: String) -> String {
        if apiName.hasPrefix("canvas.ctx.") { return handleCanvasContextApi(apiName, payload) }
        let args = normalizedArgs(payload)
        let canvas = services.canvas
        switch apiName {
        case "canvas.clear":
            canvas.clear()
            return Typed.OK_RESPONSE
        case "canvas.getCommands":
            return Typed.makeResponse("array", canvas.commands.map { c -> Any? in
                let m = JSONObject([("type", c.type), ("params", c.params)])
                if let id = c.id { m["id"] = id }
                return m
            })
        case "canvas.addCommand":
            if let cmd = commandFromArgs(args) { canvas.addCommand(cmd) }
            return Typed.OK_RESPONSE
        case "canvas.addCommands":
            canvas.addCommands((asArray(args["commands"]) ?? []).filter { isMap($0) }.map { commandFromJson($0) })
            return Typed.OK_RESPONSE
        default:
            break
        }
        let name = String(apiName.dropFirst("canvas.".count))
        if isCanvasCommandType(name) { canvas.addCommand(CanvasCommand(type: name, params: args)) }
        return Typed.OK_RESPONSE
    }

    private func handleCanvasContextApi(_ apiName: String, _ payload: String) -> String {
        let args = normalizedArgs(payload)
        let store = services.canvasContexts
        let id: String? = args["id"] != nil ? jsString(args["id"]) : nil
        func ctx() -> CanvasContext? { id == nil ? nil : store[scoped(id!)] }
        switch apiName {
        case "canvas.ctx.create":
            let created = store.create(
                id: (id ?? "").isEmpty ? nil : scoped(id!),
                width: toNumber(args["width"]) ?? 0,
                height: toNumber(args["height"]) ?? 0
            )
            // The guest's own id: later calls scope it again on the way in.
            return Typed.makeResponse("string", id ?? created.id)
        case "canvas.ctx.dispose":
            if let i = id, !i.isEmpty { store.dispose(scoped(i)) }
            return Typed.OK_RESPONSE
        case "canvas.ctx.clear":
            ctx()?.clear()
            return Typed.OK_RESPONSE
        case "canvas.ctx.setSize":
            if let c = ctx() { c.setSize(toNumber(args["width"]) ?? c.width, toNumber(args["height"]) ?? c.height) }
            return Typed.OK_RESPONSE
        case "canvas.ctx.addCommand":
            let json = args["command"] ?? args
            if let c = ctx(), isMap(json) { c.addCommand(commandFromJson(json)) }
            return Typed.OK_RESPONSE
        case "canvas.ctx.addCommands":
            if let c = ctx(), let commands = asArray(args["commands"]) { c.addCommands(commands.filter { isMap($0) }.map { commandFromJson($0) }) }
            return Typed.OK_RESPONSE
        default:
            return Typed.OK_RESPONSE
        }
    }
}

private func commandFromArgs(_ args: JSONObject) -> CanvasCommand? {
    let t = args["type"] != nil ? jsString(args["type"]) : nil
    guard let type = t, !type.isEmpty, isCanvasCommandType(type) else { return nil }
    let params = asMap(args["params"])?.copy() ?? JSONObject()
    return CanvasCommand(type: type, params: params, id: args["id"] != nil ? jsString(args["id"]) : nil)
}

private func encodeElement(_ e: ElpianElement?) -> JSONObject? { e?.encode() }

private func encodeElements(_ list: [ElpianElement]) -> [Any?] { list.map { $0.encode() } }

private func asNullableString(_ value: Any?) -> String? {
    guard let v = flattenOptional(value) else { return nil }
    let s = jsTrim(jsString(v))
    return s == "" || s == "null" ? nil : s
}
