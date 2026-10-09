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
public struct ElpianError: Error, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { "Error: \(message)" }
}
