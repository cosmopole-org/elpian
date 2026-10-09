#if canImport(UIKit)
import UIKit
#if !ELPIAN_SINGLE_MODULE
import ElpianCore
#endif

/**
 * The seam a linked Godot 4 iOS runtime plugs into — the same plain function
 * hooks as the Flutter plugin's `GodotRuntimeHost` (godot/ios/Classes), so a
 * runtime pod written for one serves both and this package takes no build
 * dependency on it. A host app (or the runtime) sets:
 *
 *     ElpianGodotRuntime.attach  = { view, surfaceId in /* render into `view` */ }
 *     ElpianGodotRuntime.opSink  = { batchJson in /* exec_op_json on each op */ }
 *     ElpianGodotRuntime.release = { surfaceId in /* tear down the viewport */ }
 *
 * and calls `ElpianGodotRuntime.reply(requestId, payload)` for awaited batches
 * and `ElpianGodotRuntime.signal(callbackId, argsJson)` when a connected
 * signal fires.
 */
public enum ElpianGodotRuntime {
    /** Receives each drained op batch as a JSON array string. */
    public static var opSink: ((String) -> Void)?
    /** Called when a surface appears, so the runtime can render into the view. */
    public static var attach: ((UIView, Int) -> Void)?
    /** Called when a surface is released. */
    public static var release: ((Int) -> Void)?

    /** A linked runtime answers an awaited batch. */
    public static func reply(_ requestId: Int, _ payload: String) {
        IOSGodotOpQueue.shared.putReply(requestId, payload)
    }

    /** A linked runtime reports a connected signal. */
    public static func signal(_ callbackId: Int, _ argsJson: String) {
        DispatchQueue.main.async { IOSGodotBinding.signalTarget?(callbackId, argsJson) }
    }

    /** Whether a runtime is linked (the op sink is installed). */
    public static var isLinked: Bool { opSink != nil }
}

/**
 * The op queue between the core (which pushes) and the display-link drain
 * (which hands batches to Godot) — the Swift twin of the plugin's
 * `IOSGodotOpQueue` / Android's `OpQueue.kt`: the same message envelopes
 * (`{"ops":[…]}`, `{"ops":[…],"req":n}`, `{"mount":…,"node":…}`,
 * `{"release":…}`), diagnostics and reply slots.
 */
final class IOSGodotOpQueue {
    static let shared = IOSGodotOpQueue()

    private let lock = NSLock()
    private var pending: [String] = []
    private var replies: [Int: String] = [:]
    private var pushed = 0
    private var polls = 0
    private var drained = 0

    func push(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        pending.append(message)
        pushed += 1
    }

    /** Everything queued as a JSON array string, or "" when idle. */
    func drain() -> String {
        lock.lock(); defer { lock.unlock() }
        polls += 1
        if pending.isEmpty { return "" }
        let joined = pending.joined(separator: ",")
        drained += pending.count
        pending.removeAll(keepingCapacity: true)
        return "[\(joined)]"
    }

    func putReply(_ requestId: Int, _ payload: String) {
        lock.lock(); defer { lock.unlock() }
        replies[requestId] = payload
    }

    func takeReply(_ requestId: Int) -> String? {
        lock.lock(); defer { lock.unlock() }
        return replies.removeValue(forKey: requestId)
    }

    func stats() -> JSONObject {
        lock.lock(); defer { lock.unlock() }
        return JSONObject([
            ("pushed", Double(pushed)),
            ("polls", Double(polls)),
            ("drained", Double(drained)),
            ("queued", Double(pending.count)),
            ("awaiting", Double(replies.count)),
        ])
    }
}

/**
 * The embedded Godot 4 engine as the Scene3D backend (AndroidGodotBinding.kt,
 * native/web/src/godot.ts): the core's op batches go through [IOSGodotOpQueue],
 * a CADisplayLink pushes them into the linked runtime each frame (iOS pushes,
 * Android pulls — the protocol is identical), `scene3d` views host the
 * runtime's viewport through [GodotSurfaceProvider]. Without a linked runtime
 * [isLive] is false and the core shows the Scene3D placeholder. Awaited
 * replies time out after [REPLY_TIMEOUT] with one `null` per op.
 */
public final class IOSGodotBinding: GodotPlatformBinding, GodotSurfaceProvider {
    static let REPLY_TIMEOUT: TimeInterval = 2.0
    private static let REPLY_POLL_NS: UInt64 = 16_000_000
    static var signalTarget: ((Int, String) -> Void)?

    private let queue = IOSGodotOpQueue.shared
    private var nextRequest = 1
    private var awaiting = 0
    private var link: CADisplayLink?
    private var containers: [Int: UIView] = [:]
    private var mounted = Set<Int>()

    public init() {}

    public var isLive: Bool { ElpianGodotRuntime.isLinked }

    public func post(_ opsJson: String) {
        queue.push("{\"ops\":\(opsJson)}")
        ensureDrain()
    }

    public func send(_ opsJson: String) async throws -> String {
        let count = asArray(JSON.parseOrNil(opsJson))?.count ?? 0
        let timedOut = JSON.stringify([Any?](repeating: nil, count: count))
        if !isLive { return timedOut }
        let id = await MainActor.run { () -> Int in
            let i = nextRequest
            nextRequest += 1
            awaiting += 1
            return i
        }
        defer { Task { @MainActor in self.awaiting -= 1 } }
        queue.push("{\"ops\":\(opsJson),\"req\":\(id)}")
        await MainActor.run { ensureDrain() }
        // A reply that never arrives must not wedge the caller.
        let deadline = Date().addingTimeInterval(IOSGodotBinding.REPLY_TIMEOUT)
        while Date() < deadline {
            if let reply = queue.takeReply(id) {
                return asArray(JSON.parseOrNil(reply)) != nil ? reply : "[]"
            }
            try await Task.sleep(nanoseconds: IOSGodotBinding.REPLY_POLL_NS)
        }
        return timedOut
    }

    public func mountSurface(_ surfaceId: Int, _ mountHandle: Int) {
        queue.push(JSON.stringify(JSONObject([("mount", Double(surfaceId)), ("node", Double(mountHandle))])))
        mounted.insert(surfaceId)
        ensureDrain()
        if let v = containers[surfaceId] { ElpianGodotRuntime.attach?(v, surfaceId) }
    }

    public func releaseSurface(_ surfaceId: Int) {
        queue.push(JSON.stringify(JSONObject([("release", Double(surfaceId))])))
        mounted.remove(surfaceId)
        ElpianGodotRuntime.release?(surfaceId)
        ensureDrain()
    }

    public func setSignalHandler(_ handler: ((_ callbackId: Int, _ argsJson: String) -> Void)?) {
        IOSGodotBinding.signalTarget = handler
    }

    public func stats() async -> JSONObject? {
        let out = queue.stats()
        out["awaiting"] = Double(awaiting)
        out["live"] = isLive
        out["runtimeLinked"] = ElpianGodotRuntime.isLinked
        return out
    }

    // ---- the engine viewport ------------------------------------------------

    /** The view the runtime renders surface [surfaceId] into (made on first use, handed to `attach`). */
    public func surfaceView(_ surfaceId: Int) -> UIView? {
        guard isLive else { return nil }
        if let v = containers[surfaceId] { return v }
        let v = UIView()
        v.backgroundColor = UIColor(red: 0.043, green: 0.071, blue: 0.125, alpha: 1) // #0b1220
        v.clipsToBounds = true
        containers[surfaceId] = v
        ElpianGodotRuntime.attach?(v, surfaceId)
        return v
    }

    public func releaseSurface(_ surfaceId: Int, _ view: UIView) {
        if containers[surfaceId] === view { containers.removeValue(forKey: surfaceId) }
    }

    /** Push queued batches into the runtime once per display frame while it is linked. */
    private func ensureDrain() {
        guard isLive, link == nil else { return }
        let l = CADisplayLink(target: DisplayLinkProxy { [weak self] in self?.drain() }, selector: #selector(DisplayLinkProxy.tick))
        // .common so the drain keeps running while a list scrolls.
        l.add(to: .main, forMode: .common)
        link = l
    }

    private func drain() {
        let json = queue.drain()
        if json.isEmpty { return }
        if let sink = ElpianGodotRuntime.opSink {
            sink(json)
        } else {
            link?.invalidate()
            link = nil
        }
    }

    deinit { link?.invalidate() }
}
#endif
