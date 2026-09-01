import Foundation

/// The op queue — the one shared point between the Flutter platform thread
/// (which pushes) and the display-link drain (which hands batches to Godot).
///
/// The Swift twin of Android's `OpQueue.kt`, and deliberately the same shape:
/// same message envelopes, same diagnostics, same reply-slot mechanism. Victor's
/// React Native port shared one C++ queue across both platforms because JSI is a
/// C++ API; a Flutter method channel lands in Swift/Kotlin directly, so each
/// platform keeps a small native queue and the C++ layer disappears.
final class GodotOpQueue {
    static let shared = GodotOpQueue()

    private let lock = NSLock()
    private var pending: [String] = []
    private var replies: [Int: String] = [:]

    // Diagnostics, surfaced through the `stats` channel method. pushed > 0 with
    // polls == 0 means the drain never ran — the first thing to check on a blank
    // viewport.
    private var pushed = 0
    private var polls = 0
    private var drained = 0

    private init() {}

    /// Queue one JSON message (`{"ops":[…]}`, `{"mount":…}`, `{"release":…}`).
    func push(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        pending.append(message)
        pushed += 1
    }

    /// Drain everything queued, as a JSON array string.
    ///
    /// Returns "" rather than "[]" when idle so the per-frame drain can skip
    /// parsing entirely on the overwhelmingly common empty frame.
    func drain() -> String {
        lock.lock(); defer { lock.unlock() }
        polls += 1
        if pending.isEmpty { return "" }
        let joined = pending.joined(separator: ",")
        drained += pending.count
        pending.removeAll(keepingCapacity: true)
        return "[\(joined)]"
    }

    /// The engine hands back a reply for a request the Dart side is awaiting.
    func putReply(_ requestId: Int, _ payload: String) {
        lock.lock(); defer { lock.unlock() }
        replies[requestId] = payload
    }

    func takeReply(_ requestId: Int) -> String? {
        lock.lock(); defer { lock.unlock() }
        return replies.removeValue(forKey: requestId)
    }

    func stats() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return [
            "pushed": pushed,
            "polls": polls,
            "drained": drained,
            "queued": pending.count,
            "awaiting": replies.count,
        ]
    }
}
