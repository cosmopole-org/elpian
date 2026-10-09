import Foundation

/**
 * `setTimeout` / `setInterval` / `clearTimeout` / `clearInterval` for guests —
 * a port of `VmTimerHostApi` (flutter/lib/src/vm/timer_host_api.dart) via
 * host/timers.ts. Timers run on the platform clock and call back into the
 * guest by function name.
 */
public typealias VmTimerInvoke = (_ funcName: String, _ inputJson: String?) async throws -> Void

private let MAX_DELAY = 2147483648.0 // 2 ** 31

public final class VmTimerHostApi {
    private final class IntervalEntry {
        var handle = 0
    }

    private let invoke: VmTimerInvoke
    private let onError: ((_ message: String) -> Void)?
    private var nextId = 1
    private var timeouts: [Int: Int] = [:]
    private var intervals: [Int: IntervalEntry] = [:]
    private var disposed = false

    public init(_ invoke: @escaping VmTimerInvoke, onError: ((_ message: String) -> Void)? = nil) {
        self.invoke = invoke
        self.onError = onError
    }

    public func handle(_ apiName: String, _ payload: String) -> String {
        switch apiName {
        case "setTimeout": return setTimer(payload, false)
        case "setInterval": return setTimer(payload, true)
        case "clearTimeout", "clearInterval": return clear(payload)
        default: return Typed.OK_RESPONSE
        }
    }

    /** Live timer count (governance usage). */
    public var activeCount: Int { timeouts.count + intervals.count }

    public func dispose() {
        disposed = true
        let p = platform()
        for h in timeouts.values { p.clearTimeout(h) }
        for i in intervals.values { p.clearTimeout(i.handle) }
        timeouts.removeAll()
        intervals.removeAll()
    }

    private func setTimer(_ payload: String, _ repeating: Bool) -> String {
        let args = timerNormalized(payload)
        let handler = flattenOptional(args["handler"]) ?? flattenOptional(args["callback"]) ?? flattenOptional(args["fn"])
        if handler == nil || jsString(handler) == "" { return Typed.OK_RESPONSE }
        let name = jsString(handler)
        let delay = readDelay(args)
        let input = readInputJson(args)
        let id = nextId
        nextId += 1
        let p = platform()
        if repeating {
            // Periodic: re-arm after each tick (Timer.periodic semantics — ticks
            // never pile up while the guest is busy).
            let entry = IntervalEntry()
            var tick: (() -> Void)!
            tick = { [weak self] in
                guard let self = self, !self.disposed, self.intervals[id] != nil else { return }
                entry.handle = p.setTimeout(tick, max(delay, 0))
                self.safeInvoke(name, input)
            }
            entry.handle = p.setTimeout(tick, max(delay, 0))
            intervals[id] = entry
        } else {
            timeouts[id] = p.setTimeout({ [weak self] in
                guard let self = self else { return }
                self.timeouts.removeValue(forKey: id)
                if !self.disposed { self.safeInvoke(name, input) }
            }, delay)
        }
        return Typed.makeResponse("i64", Double(id))
    }

    private func clear(_ payload: String) -> String {
        guard let id = readId(payload) else { return Typed.OK_RESPONSE }
        let p = platform()
        if let t = timeouts[id] {
            p.clearTimeout(t)
            timeouts.removeValue(forKey: id)
        }
        if let i = intervals[id] {
            p.clearTimeout(i.handle)
            intervals.removeValue(forKey: id)
        }
        return Typed.OK_RESPONSE
    }

    /** Fire-and-forget guest call (`void this.safeInvoke(...)`); failures go to [onError]. */
    private func safeInvoke(_ handler: String, _ input: String?) {
        let invoke = self.invoke
        let onError = self.onError
        launchDetached({ try await invoke(handler, input) }, onError: { e in
            onError?("VmTimerHostApi invoke error (\(handler)): \(e)")
        })
    }
}

private func timerParsePayload(_ payload: String) -> Any? {
    if payload.isEmpty { return nil }
    let parsed: Any?
    do {
        parsed = try JSON.parse(payload)
    } catch {
        if jsLength(payload) >= 2 && payload.hasPrefix("\"") && payload.hasSuffix("\"") {
            return jsSubstring(payload, 1, jsLength(payload) - 1)
        }
        return payload
    }
    if let a = asArray(parsed) { return a.isEmpty ? nil : a[0] }
    if let m = asMap(parsed), let data = asMap(m["data"]), data.has("value") { return data["value"] }
    return parsed
}

private func timerNormalized(_ payload: String) -> JSONObject { asMap(timerParsePayload(payload)) ?? JSONObject() }

private let INTEGER = JSRegex("^-?[0-9]+$")

private func readDelay(_ args: JSONObject) -> Double {
    let raw = flattenOptional(args["delay"]) ?? flattenOptional(args["ms"]) ?? flattenOptional(args["interval"])
    var v = 0.0
    if let n = jsNumber(raw) {
        v = jsRound(n)
    } else if let s = raw as? String, INTEGER.test(jsTrim(s)) {
        v = jsParseInt(s, 10)
    }
    return max(0, min(MAX_DELAY, v.isFinite ? v : 0))
}

private func readInputJson(_ args: JSONObject) -> String? {
    if let s = args["inputJson"] as? String { return s }
    if args.has("input") { return JSON.stringify(args["input"]) }
    return nil
}

private func readId(_ payload: String) -> Int? {
    let p = timerParsePayload(payload)
    let v: Any?
    if let m = asMap(p) {
        v = flattenOptional(m["id"]) ?? flattenOptional(m["timerId"]) ?? flattenOptional(m["value"])
    } else {
        v = p
    }
    if let n = jsNumber(v) {
        let r = jsRound(n)
        return r.isFinite && abs(r) < 9.2e18 ? Int(r) : nil
    }
    if let s = v as? String, INTEGER.test(jsTrim(s)) {
        let n = jsParseInt(s, 10)
        return n.isFinite && abs(n) < 9.2e18 ? Int(n) : nil
    }
    return nil
}
