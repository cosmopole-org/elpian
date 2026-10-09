#if canImport(UIKit) && canImport(JavaScriptCore)
import Foundation
import JavaScriptCore
#if !ELPIAN_SINGLE_MODULE
import ElpianCore
#endif

/**
 * JS guests on JavaScriptCore: one isolated JSContext (in its own virtual
 * machine) per mini app, with `__elpianHostCall(api, payload)` as the only way
 * out — the contract of the web host's `WebQuickJs` (native/web/src/runtimes.ts)
 * and Android's QuickJsSandbox. Promise jobs (microtasks) are drained by
 * JavaScriptCore itself when each evaluation returns to the host.
 *
 * A context is used from the thread that drives the core (the main thread).
 */
public final class JSCoreSandboxFactory: JsSandboxFactory {
    public init() {}

    public func create(_ machineId: String) throws -> JsSandbox {
        guard let s = JSCoreSandbox(machineId: machineId) else {
            throw PlatformError("JavaScriptCore could not create a context for \(machineId)")
        }
        return s
    }
}

public final class JSCoreSandbox: JsSandbox {
    static let defaultReply = "{\"type\":\"i16\",\"data\":{\"value\":0}}"
    static let nullReply = "{\"type\":\"null\",\"data\":{\"value\":null}}"

    private let machineId: String
    private var context: JSContext?
    private var handler: (String, String) -> String = { _, _ in JSCoreSandbox.defaultReply }
    /** `(v) => string`: the web host's stringification of a completion value, run in the guest. */
    private let stringifyFn: JSValue
    private var pendingException: JSValue?

    init?(machineId: String) {
        self.machineId = machineId
        let vm = JSVirtualMachine()
        let ctx: JSContext = JSContext(virtualMachine: vm)
        ctx.name = machineId
        context = ctx
        // `__elpianHostCall` coerces its arguments like the web host
        // (`String(dump(h) ?? '')`) and is the only binding the guest sees;
        // the native callback stays inside the installer's closure.
        let install: JSValue? = ctx.evaluateScript("""
        (function (native) {
          globalThis.__elpianHostCall = function (api, payload) {
            return native(api == null ? '' : String(api), payload == null ? '' : String(payload));
          };
        })
        """, withSourceURL: URL(string: "elpian-host.js"))
        let fnValue: JSValue? = ctx.evaluateScript("""
        (function (v) {
          if (typeof v === 'string') return v;
          if (v === undefined) return 'undefined';
          var s = JSON.stringify(v);
          return s === undefined ? 'undefined' : s;
        })
        """, withSourceURL: URL(string: "elpian-stringify.js"))
        guard let fn = fnValue, fn.isObject else { return nil }
        stringifyFn = fn
        let native: @convention(block) (String, String) -> String = { [weak self] api, payload in
            guard let self = self else { return JSCoreSandbox.nullReply }
            return self.handler(api, payload)
        }
        _ = install?.call(withArguments: [unsafeBitCast(native, to: AnyObject.self)])
        ctx.exceptionHandler = { [weak self] _, exception in
            self?.pendingException = exception
        }
    }

    public func setHostCallHandler(_ handler: @escaping (_ apiName: String, _ payload: String) -> String) {
        self.handler = handler
    }

    /**
     * Evaluate [code] as a global script and stringify its completion value as
     * the web host does: a string as is, `undefined` → `"undefined"`, anything
     * else `JSON.stringify`'d in the guest. A thrown error becomes a Swift error.
     */
    public func evaluate(_ code: String) throws -> String {
        guard let ctx = context else { return "" }
        pendingException = nil
        let value: JSValue? = ctx.evaluateScript(code, withSourceURL: URL(string: "\(machineId).js"))
        if let ex = pendingException {
            pendingException = nil
            throw PlatformError("QuickJS eval error: \(describe(ex))")
        }
        guard let v = value else { return "undefined" }
        if v.isString {
            let str: String? = v.toString()
            return str ?? ""
        }
        if v.isUndefined { return "undefined" }
        pendingException = nil
        let s: JSValue? = stringifyFn.call(withArguments: [v])
        if pendingException != nil {
            pendingException = nil
            return "undefined"
        }
        let out: String? = s?.toString()
        return out ?? "undefined"
    }

    private func describe(_ ex: JSValue) -> String {
        let message: JSValue? = ex.isObject ? ex.objectForKeyedSubscript("message") : nil
        if let msg = message, !msg.isUndefined {
            let nameValue: JSValue? = ex.objectForKeyedSubscript("name")
            let name: String? = nameValue.flatMap { $0.isUndefined ? nil : $0.toString() }
            let text: String? = msg.toString()
            return "\(name ?? "Error"): \(text ?? "")"
        }
        let whole: String? = ex.toString()
        return whole ?? "unknown error"
    }

    public func dispose() {
        context?.exceptionHandler = nil
        context = nil
    }
}
#endif
