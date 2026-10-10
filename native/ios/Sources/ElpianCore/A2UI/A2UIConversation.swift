import Foundation

/**
 * `A2UIConversation` (a2ui/conversation.ts) — one conversation with one
 * agent: the A2UI processor holding its surfaces, the transcript of prose,
 * UI-local state, and the agent transport. Turns (`send(message)`,
 * `sendAction(action)`) run one at a time; each carries the conversation id,
 * the `sendDataModel` surfaces' data models and the client's supported
 * catalogs. Without an endpoint a conversation renders static A2UI messages
 * ([ingest]) and actions are only reported to listeners.
 *
 * Everything runs on the main thread (the platform delivers stream callbacks
 * there); a turn starts on the next turn of the platform's scheduler, as the
 * TypeScript promise chain does.
 */
public enum A2UIConversationEvent {
    case conversation(conversationId: String)
    /** `role`: `agent` or `user`. */
    case text(text: String, role: String)
    case status(state: String, tool: String?)
    case error(message: String, error: A2UIError?)
    case done(stopReason: String, conversationId: String?)
    case action(A2UIClientAction)
    /** Surfaces, transcript or busy state changed: render again. */
    case changed
}

public typealias A2UIConversationListener = (A2UIConversationEvent) -> Void

public struct A2UITranscriptEntry {
    /** `agent` or `user`. */
    public let role: String
    public let text: String
}

/** A value that arrives once (the TypeScript `Promise`), awaited on the main actor. */
public final class A2UIPromise<T> {
    private var result: T?
    private var waiters: [(T) -> Void] = []

    public init() {}

    public var isResolved: Bool { result != nil }

    /** The value once resolved. */
    public var current: T? { result }

    public func resolve(_ value: T) {
        if result != nil { return }
        result = value
        let w = waiters
        waiters = []
        for f in w { f(value) }
    }

    /** Run [fn] with the value (now when already resolved). */
    public func then(_ fn: @escaping (T) -> Void) {
        if let r = result { fn(r) } else { waiters.append(fn) }
    }

    @MainActor
    public func value() async -> T {
        if let r = result { return r }
        return await withCheckedContinuation { (c: CheckedContinuation<T, Never>) in
            then { c.resume(returning: $0) }
        }
    }
}

public struct A2UITurnResult: Equatable {
    public let conversationId: String?
    public let stopReason: String
}

public struct A2UITurn {
    /** Resolves once the agent named the conversation (or the turn ended without one). */
    public let conversationId: A2UIPromise<String?>
    /** Resolves when the turn ends, with its stop reason. */
    public let done: A2UIPromise<A2UITurnResult>
}

public struct A2UIConversationOptions {
    public var endpoint: AgentEndpoint?
    public var conversationId: String?
    public var processor: A2UIProcessorOptions

    public init(endpoint: AgentEndpoint? = nil, conversationId: String? = nil, processor: A2UIProcessorOptions = A2UIProcessorOptions()) {
        self.endpoint = endpoint
        self.conversationId = conversationId
        self.processor = processor
    }
}

public final class A2UIConversation {
    public let processor: A2UIProcessor
    public let ui = A2UIUiState()
    public private(set) var transcript: [A2UITranscriptEntry] = []
    public var endpoint: AgentEndpoint?
    public var conversationId: String?
    /** A turn is streaming. */
    public private(set) var busy = false
    public private(set) var status: (state: String, tool: String?)?
    /** The `prompt` of an embedding widget was sent (once per conversation). */
    public var prompted = false
    private var listeners: [(id: Int, fn: A2UIConversationListener)] = []
    private var nextListener = 0
    private var queue: [(@escaping () -> Void) -> Void] = []
    private var running = false
    private var cancel: (() -> Void)?
    private var staticKey: String?
    private var disposed = false

    public init(_ options: A2UIConversationOptions = A2UIConversationOptions()) {
        endpoint = options.endpoint
        conversationId = options.conversationId
        processor = A2UIProcessor(options.processor)
        processor.on { [weak self] e in
            guard let self = self else { return }
            switch e {
            case .error(let error):
                self.emit(.error(message: error.message, error: error))
            case .action(let action):
                self.emit(.action(action))
                if self.endpoint != nil { self.sendAction(action.toJson()) }
            case .surfaceDeleted(let surfaceId):
                self.ui.clearSurface(surfaceId)
                self.emit(.changed)
            default:
                self.emit(.changed)
            }
        }
    }

    @discardableResult
    public func on(_ listener: @escaping A2UIConversationListener) -> () -> Void {
        let id = nextListener
        nextListener += 1
        listeners.append((id, listener))
        return { [weak self] in self?.listeners.removeAll { $0.id == id } }
    }

    private func emit(_ event: A2UIConversationEvent) {
        for l in listeners { l.fn(event) }
    }

    /** Hooks the lowering uses for this conversation's surfaces. */
    public func loweringHooks(_ invalidate: @escaping () -> Void) -> LoweringHooks {
        LoweringHooks(
            write: { [weak self] surfaceId, path, value in self?.processor.setData(surfaceId, path, value) },
            action: { [weak self] surfaceId, componentId, action, scope in
                self?.processor.dispatchAction(surfaceId, componentId, action, scope)
            },
            invalidate: invalidate,
            error: { [weak self] error in self?.emit(.error(message: error.message, error: error)) }
        )
    }

    /** Render static A2UI messages (no agent). */
    @discardableResult
    public func ingest(_ messages: [Any?]) -> [A2UIError] {
        processor.processAll(messages)
    }

    /** Static messages from a widget prop: re-applied from scratch when they change. */
    public func syncStatic(_ messages: [Any?], _ key: String) {
        if key == staticKey { return }
        staticKey = key
        processor.reset()
        ingest(messages)
    }

    /** Send a user message to the agent. */
    @discardableResult
    public func send(_ message: String) -> A2UITurn {
        transcript.append(A2UITranscriptEntry(role: "user", text: message))
        emit(.text(text: message, role: "user"))
        return turn(message: message, action: nil)
    }

    /** Send a client-to-server `action` to the agent. */
    @discardableResult
    public func sendAction(_ action: JSONObject) -> A2UITurn {
        turn(message: nil, action: action.copy())
    }

    /** The current data model of [surfaceId] (a copy), or nil. */
    public func dataModel(_ surfaceId: String) -> Any? {
        processor.dataModel(surfaceId)
    }

    /** A JSON summary (session `conversation()`). */
    public func describe() -> JSONObject {
        JSONObject([
            ("conversationId", conversationId),
            ("busy", busy),
            ("surfaces", processor.surfaces.map { s -> Any? in
                JSONObject([("surfaceId", s.id), ("catalogId", s.catalogId), ("components", Double(s.components.count)), ("ready", s.isReady)])
            }),
            ("transcript", transcript.map { t -> Any? in JSONObject([("role", t.role), ("text", t.text)]) }),
        ])
    }

    private func pump() {
        if running || queue.isEmpty { return }
        running = true
        let job = queue.removeFirst()
        scheduleMicrotask { [weak self] in
            job {
                guard let self = self else { return }
                self.running = false
                self.pump()
            }
        }
    }

    private func turn(message: String?, action: JSONObject?) -> A2UITurn {
        let idPromise = A2UIPromise<String?>()
        let donePromise = A2UIPromise<A2UITurnResult>()
        queue.append { [weak self] next in
            guard let self = self else {
                idPromise.resolve(nil)
                donePromise.resolve(A2UITurnResult(conversationId: nil, stopReason: "error"))
                next()
                return
            }
            var finished = false
            let finish: (String) -> Void = { [weak self] stopReason in
                guard let self = self, !finished else { return }
                finished = true
                idPromise.resolve(self.conversationId)
                self.busy = false
                self.status = nil
                self.cancel = nil
                self.emit(.done(stopReason: stopReason, conversationId: self.conversationId))
                self.emit(.changed)
                donePromise.resolve(A2UITurnResult(conversationId: self.conversationId, stopReason: stopReason))
                next()
            }
            if self.disposed { return finish("error") }
            guard let endpoint = self.endpoint else {
                self.emit(.error(message: "this conversation has no agent endpoint", error: nil))
                return finish("error")
            }
            var body = AgentRequestBody(message: message, action: action, supportedCatalogIds: self.processor.supportedCatalogIds)
            if let id = self.conversationId { body.conversationId = id }
            if let dm = self.processor.clientDataModel() { body.dataModel = dm }
            self.busy = true
            self.status = (state: "working", tool: nil)
            self.emit(.changed)
            var stopReason: String?
            self.cancel = openAgentStream(endpoint, body, AgentStreamSink(
                onLine: { [weak self] line in
                    if case .done(let r) = line { stopReason = r }
                    self?.handleLine(line)
                    if case .conversation(let id) = line { idPromise.resolve(id) }
                },
                onError: { [weak self] message in self?.emit(.error(message: message, error: nil)) },
                onClose: { finish(stopReason ?? "error") }
            ))
        }
        pump()
        return A2UITurn(conversationId: idPromise, done: donePromise)
    }

    /** Apply one response line (exposed for transports other than HTTP). */
    public func handleLine(_ line: AgentStreamLine) {
        switch line {
        case .a2ui(let message):
            processor.process(message)
        case .conversation(let id):
            conversationId = id
            emit(.conversation(conversationId: id))
        case .text(let text):
            transcript.append(A2UITranscriptEntry(role: "agent", text: text))
            emit(.text(text: text, role: "agent"))
            emit(.changed)
        case .status(let state, let tool):
            status = (state: state, tool: tool)
            emit(.status(state: state, tool: tool))
            emit(.changed)
        case .error(let message):
            emit(.error(message: message, error: nil))
        case .done:
            break
        }
    }

    public func dispose() {
        disposed = true
        cancel?()
        cancel = nil
        listeners.removeAll()
    }
}
