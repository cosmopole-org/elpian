import Foundation

/**
 * The two Promise idioms the TypeScript core uses without awaiting, mapped
 * onto the platform's main-thread scheduling:
 *
 *  - [scheduleMicrotask] — `queueMicrotask(fn)`: run after the current turn.
 *  - [launchDetached] — calling an `async` function without awaiting it
 *    (`void promise`): the work starts on its own and failures are dropped
 *    (or reported) as an unhandled rejection would be.
 */

/**
 * `queueMicrotask`: run [fn] after the current turn through the platform's
 * scheduler. Without an installed platform there is no event loop to defer
 * to, so [fn] runs at once.
 */
public func scheduleMicrotask(_ fn: @escaping () -> Void) {
    guard hasPlatform() else {
        fn()
        return
    }
    _ = platform().setTimeout(fn, 0)
}

/**
 * Start [block] without awaiting it, on the main actor (the core's single
 * thread). Errors go to [onError] when given and are dropped otherwise.
 */
public func launchDetached(_ block: @escaping () async throws -> Void, onError: ((Error) -> Void)? = nil) {
    Task { @MainActor in
        do {
            try await block()
        } catch {
            onError?(error)
        }
    }
}

/** A plain error carrying a message (the TypeScript `new Error(message)`). */
public struct ElpianError: MessageError, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { "Error: \(message)" }
}

/** An error whose JavaScript `e.message` is [message]. */
public protocol MessageError: Error {
    var message: String { get }
}

extension JSONError: MessageError {}

/** `e instanceof Error ? e.message : String(e)`. */
public func errorText(_ e: Any?) -> String {
    guard let e = flattenOptional(e) else { return "null" }
    if let m = e as? MessageError { return m.message }
    if let s = e as? String { return s }
    if e is Error, let c = e as? CustomStringConvertible { return c.description }
    return jsString(e)
}

/** JavaScript's `String(e)` for an `Error`: `Error: message`. */
public func jsErrorString(_ e: Any?) -> String { "Error: \(errorText(e))" }

/**
 * A one-shot signal awaited on the main actor (a Kotlin
 * `CompletableDeferred<Unit>` / a Promise resolved once).
 */
public final class AsyncLatch {
    private var completed = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public var isCompleted: Bool { completed }

    public func complete() {
        if completed { return }
        completed = true
        let w = waiters
        waiters = []
        for c in w { c.resume() }
    }

    @MainActor
    public func wait() async {
        if completed { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            if completed { c.resume() } else { waiters.append(c) }
        }
    }
}

/**
 * The tasks one owner (a session, a surface, a client) started — the Kotlin
 * core's `CoroutineScope(SupervisorJob() + dispatcher)`. Every task runs on
 * the main actor; [cancel] cancels the running ones and stops new ones from
 * starting, and a task cancelled before it began never runs its body (as a
 * cancelled coroutine never starts).
 */
public final class TaskScope {
    private let lock = NSLock()
    private var cancellers: [Int: () -> Void] = [:]
    private var nextId = 0
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /** Start [block] on the main actor without awaiting it; nil once the scope is cancelled. */
    @discardableResult
    public func launch(_ block: @escaping @MainActor () async -> Void) -> Task<Void, Never>? {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { return nil }
        let id = nextId
        nextId += 1
        let task = Task { @MainActor [weak self] in
            if !Task.isCancelled { await block() }
            self?.finished(id)
        }
        cancellers[id] = { task.cancel() }
        return task
    }

    /** Start [block] on the main actor and hand back its task (a Kotlin `async`). */
    public func async<T>(_ block: @escaping @MainActor () async throws -> T) -> Task<T, Error> {
        lock.lock()
        defer { lock.unlock() }
        let id = nextId
        nextId += 1
        let task = Task { @MainActor [weak self] () async throws -> T in
            defer { self?.finished(id) }
            try Task.checkCancellation()
            return try await block()
        }
        if cancelled { task.cancel() } else { cancellers[id] = { task.cancel() } }
        return task
    }

    private func finished(_ id: Int) {
        lock.lock()
        cancellers.removeValue(forKey: id)
        lock.unlock()
    }

    /** Cancel every running task; later [launch]es do nothing. */
    public func cancel() {
        lock.lock()
        cancelled = true
        let running = Array(cancellers.values)
        cancellers.removeAll()
        lock.unlock()
        for c in running { c() }
    }
}
