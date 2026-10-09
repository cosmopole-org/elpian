import Foundation

/**
 * AnimationController and ImplicitValue — the two animation primitives the
 * render objects use (animation/controller.ts).
 *
 * Controllers tick from the owner's frame clock (the platform's vsync), so
 * every animation on a surface advances in lock-step and stops scheduling
 * frames when idle — the same model as Flutter's Ticker.
 */
public enum AnimationStatus: String {
    case dismissed, forward, reverse, completed
}

/**
 * The completion of one controller run — the TypeScript core's Promise.
 * Observe it with [then] or `await completion.wait()`.
 */
public final class AnimationCompletion {
    private var done = false
    private var callbacks: [() -> Void] = []

    public init() {}

    public var isCompleted: Bool { done }

    @discardableResult
    public func then(_ fn: @escaping () -> Void) -> AnimationCompletion {
        if done { fn() } else { callbacks.append(fn) }
        return self
    }

    /** Suspend until the run finishes (or is stopped / superseded). */
    public func wait() async {
        if done { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.then { cont.resume() }
        }
    }

    func complete() {
        if done { return }
        done = true
        let cbs = callbacks
        callbacks.removeAll()
        for cb in cbs { cb() }
    }
}

/** Flutter `AnimationController`: a 0..1 value driven over [duration] ms. */
public final class AnimationController: Ticker {
    public var value: Double
    public private(set) var status: AnimationStatus = .dismissed
    public var duration: Double
    public var reverseDuration: Double?
    private weak var owner: RenderOwner?
    private var from = 0.0
    private var to = 1.0
    private var startTime: Double?
    private var running = false
    private var repeating = false
    private var reverseOnRepeat = false
    private var completer: AnimationCompletion?
    private var listeners: [(id: Int, fn: () -> Void)] = []
    private var statusListeners: [(id: Int, fn: (AnimationStatus) -> Void)] = []
    private var nextListenerId = 1

    public init(_ duration: Double, initial: Double = 0, reverseDuration: Double? = nil) {
        self.duration = duration
        self.value = initial
        self.reverseDuration = reverseDuration
    }

    public func attach(_ owner: RenderOwner) {
        self.owner = owner
        if running { owner.addTicker(self) }
    }

    public func detach() {
        owner?.removeTicker(self)
        owner = nil
    }

    /** Returns a token for [removeListener]. */
    @discardableResult
    public func addListener(_ fn: @escaping () -> Void) -> Int {
        let id = nextListenerId
        nextListenerId += 1
        listeners.append((id, fn))
        return id
    }

    public func removeListener(_ token: Int) {
        listeners.removeAll { $0.id == token }
    }

    @discardableResult
    public func addStatusListener(_ fn: @escaping (AnimationStatus) -> Void) -> Int {
        let id = nextListenerId
        nextListenerId += 1
        statusListeners.append((id, fn))
        return id
    }

    public func removeStatusListener(_ token: Int) {
        statusListeners.removeAll { $0.id == token }
    }

    private func setStatus(_ s: AnimationStatus) {
        if status == s { return }
        status = s
        for l in statusListeners { l.fn(s) }
    }

    public var isAnimating: Bool { running }

    private func start(_ target: Double) -> AnimationCompletion {
        from = value
        to = target
        startTime = nil
        running = true
        setStatus(target >= from ? .forward : .reverse)
        owner?.addTicker(self)
        completer?.complete()
        let c = AnimationCompletion()
        completer = c
        return c
    }

    @discardableResult
    public func forward(from: Double? = nil) -> AnimationCompletion {
        repeating = false
        if let f = from { value = f }
        return start(1)
    }

    @discardableResult
    public func reverse(from: Double? = nil) -> AnimationCompletion {
        repeating = false
        if let f = from { value = f }
        return start(0)
    }

    @discardableResult
    public func animateTo(_ target: Double) -> AnimationCompletion {
        repeating = false
        return start(target)
    }

    /** Loop 0→1 forever (ping-pong when [reverse]). */
    public func repeatAnimation(reverse: Bool = false) {
        repeating = true
        reverseOnRepeat = reverse
        from = value >= 1 ? 0 : value
        to = 1
        startTime = nil
        running = true
        setStatus(.forward)
        owner?.addTicker(self)
    }

    public func stop() {
        running = false
        repeating = false
        owner?.removeTicker(self)
        completer?.complete()
        completer = nil
    }

    public func reset(_ value: Double = 0) {
        stop()
        self.value = value
        setStatus(.dismissed)
        notify()
    }

    private func notify() {
        for l in listeners { l.fn() }
    }

    public func tick(_ now: Double) -> Bool {
        if !running { return false }
        if startTime == nil { startTime = now }
        let goingBack = to < from
        let d = max(1, goingBack && reverseDuration != nil ? reverseDuration! : duration)
        let span = abs(to - from)
        let total = d * span
        let elapsed = now - startTime!
        let t = total <= 0 ? 1 : min(1, elapsed / total)
        value = from + (to - from) * t
        notify()
        if t < 1 { return true }
        if repeating {
            if reverseOnRepeat {
                let next: Double = to >= 1 ? 0 : 1
                from = value
                to = next
                setStatus(next == 1 ? .forward : .reverse)
            } else {
                from = 0
                to = 1
                value = 0
            }
            startTime = now
            return true
        }
        running = false
        setStatus(to >= 1 ? .completed : .dismissed)
        completer?.complete()
        completer = nil
        return false
    }
}

public typealias Lerp<T> = (T, T, Double) -> T

public let lerpNumber: Lerp<Double> = { a, b, t in a + (b - a) * t }

/**
 * An implicitly animated value (the engine of Flutter's `AnimatedFoo`
 * widgets): setting a new target animates from the current value over the
 * configured duration and curve; without a duration it jumps.
 */
public final class ImplicitValue<T> {
    private var controller: AnimationController?
    private var value: T
    private var begin: T
    private var end: T
    private var curve: Curve = Curves.linear
    private let lerp: Lerp<T>
    private let equals: (T, T) -> Bool
    private let onChange: () -> Void

    public init(_ value: T, lerp: @escaping Lerp<T>, equals: @escaping (T, T) -> Bool, onChange: @escaping () -> Void) {
        self.value = value
        self.begin = value
        self.end = value
        self.lerp = lerp
        self.equals = equals
        self.onChange = onChange
    }

    public var current: T { value }
    public var target: T { end }
    public var animating: Bool { controller?.isAnimating ?? false }

    /** Set a new target; animate when [duration] > 0 and an owner is attached. */
    public func set(_ target: T, duration: Double?, curve: Curve?, owner: RenderOwner?) {
        if equals(target, end) { return }
        guard let duration = duration, duration > 0, let owner = owner else {
            controller?.stop()
            begin = target
            end = target
            value = target
            onChange()
            return
        }
        begin = value
        end = target
        self.curve = curve ?? Curves.linear
        let c: AnimationController
        if let existing = controller {
            c = existing
        } else {
            c = AnimationController(duration)
            controller = c
            c.addListener { [unowned self, unowned c] in
                let t = self.curve(c.value)
                self.value = self.lerp(self.begin, self.end, t)
                self.onChange()
            }
        }
        c.duration = duration
        c.attach(owner)
        c.forward(from: 0)
    }

    /** Jump without animating (initial configuration). */
    public func jump(_ v: T) {
        controller?.stop()
        begin = v
        end = v
        value = v
    }

    public func dispose() {
        controller?.detach()
        controller?.stop()
    }
}
