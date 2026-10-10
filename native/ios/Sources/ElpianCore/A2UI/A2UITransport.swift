import Foundation

/**
 * The agent transport (a2ui/transport.ts): `POST <baseUrl>/apps/<app>/agent/<agent>`,
 * answered with NDJSON (`application/x-ndjson`, one JSON object per line),
 * read incrementally through the platform's `fetchStream`. Chunk boundaries
 * fall anywhere — mid-line, several lines at once — and the decoder
 * reassembles lines across them.
 *
 * Response lines (the Elpian agent contract):
 *   {"type":"conversation","conversationId":"…"}          always first
 *   {"version":"v0.9.1","createSurface":{…}}               A2UI messages, verbatim
 *   {"type":"text","text":"…"}                             the agent's prose
 *   {"type":"status","state":"working"|"tool","tool":"…"}  progress
 *   {"type":"error","message":"…"}
 *   {"type":"done","stopReason":"end_turn"|…}              always last
 */

/** Where an agent lives. */
public struct AgentEndpoint {
    public var baseUrl: String
    public var appId: String
    public var agent: String
    public var headers: [String: String]?
    public var timeoutMs: Double?

    public init(baseUrl: String, appId: String, agent: String, headers: [String: String]? = nil, timeoutMs: Double? = nil) {
        self.baseUrl = baseUrl
        self.appId = appId
        self.agent = agent
        self.headers = headers
        self.timeoutMs = timeoutMs
    }
}

/** The request body of one agent turn. */
public struct AgentRequestBody {
    public var conversationId: String?
    public var message: String?
    public var action: JSONObject?
    /** `{version?, surfaces}` (a2uiClientDataModel). */
    public var dataModel: JSONObject?
    /** `capabilities.supportedCatalogIds`. */
    public var supportedCatalogIds: [String]?

    public init(conversationId: String? = nil, message: String? = nil, action: JSONObject? = nil, dataModel: JSONObject? = nil,
                supportedCatalogIds: [String]? = nil) {
        self.conversationId = conversationId
        self.message = message
        self.action = action
        self.dataModel = dataModel
        self.supportedCatalogIds = supportedCatalogIds
    }

    public func toJson() -> JSONObject {
        let out = JSONObject()
        if let m = message { out["message"] = m }
        if let a = action { out["action"] = a }
        if let ids = supportedCatalogIds { out["capabilities"] = JSONObject([("supportedCatalogIds", ids.map { $0 as Any? })]) }
        if let c = conversationId { out["conversationId"] = c }
        if let d = dataModel { out["dataModel"] = d }
        return out
    }
}

public enum AgentStreamLine {
    case a2ui(JSONObject)
    case conversation(conversationId: String)
    case text(String)
    case status(state: String, tool: String?)
    case error(String)
    case done(stopReason: String)
}

private let TRAILING_SLASHES = JSRegex("/+$")

/** `<baseUrl>/apps/<app>/agent/<agent>` (names percent-encoded). */
public func agentUrl(_ endpoint: AgentEndpoint) -> String {
    "\(TRAILING_SLASHES.replace(endpoint.baseUrl, with: ""))/apps/\(encodeURIComponent(endpoint.appId))/agent/\(encodeURIComponent(endpoint.agent))"
}

/** Classify one decoded response line (nil for lines this client does not know). */
public func classifyLine(_ value: Any?) -> AgentStreamLine? {
    guard let v = flattenOptional(value) as? JSONObject else { return nil }
    if messageKind(v) != nil { return .a2ui(v) }
    switch v["type"] as? String {
    case "conversation":
        guard let id = v["conversationId"] as? String else { return nil }
        return .conversation(conversationId: id)
    case "text":
        if let t = v["text"] as? String { return .text(t) }
        return .text(v["text"] == nil ? "" : jsString(v["text"]))
    case "status":
        return .status(state: v["state"] == nil ? "working" : jsString(v["state"]), tool: v["tool"] as? String)
    case "error":
        return .error((v["message"] as? String) ?? "the agent failed")
    case "done":
        return .done(stopReason: (v["stopReason"] as? String) ?? "end_turn")
    default:
        return nil
    }
}

/**
 * Newline-delimited JSON decoding across arbitrary chunk boundaries. Blank
 * lines are skipped; a line that is not JSON is reported and skipped.
 */
public final class NdjsonDecoder {
    /** Pending bytes (UTF-8), so a `\r\n` pair split across chunks is still a line end. */
    private var buffer: [UInt8] = []
    private let onBadLine: ((String) -> Void)?

    public init(_ onBadLine: ((String) -> Void)? = nil) {
        self.onBadLine = onBadLine
    }

    /** Feed a chunk; returns the complete values it finished. */
    public func push(_ chunk: String) -> [Any?] {
        buffer.append(contentsOf: Array(chunk.utf8))
        var out: [Any?] = []
        while let i = buffer.firstIndex(of: 10) {
            let line = Array(buffer[0..<i])
            buffer.removeSubrange(0...i)
            decode(line, &out)
        }
        return out
    }

    /** The stream ended: decode a final unterminated line. */
    public func end() -> [Any?] {
        var out: [Any?] = []
        let rest = buffer
        buffer = []
        decode(rest, &out)
        return out
    }

    private func decode(_ raw: [UInt8], _ out: inout [Any?]) {
        var bytes = raw
        if bytes.last == 13 { bytes.removeLast() }
        let line = jsTrim(String(decoding: bytes, as: UTF8.self))
        if line.isEmpty { return }
        do {
            out.append(try JSON.parse(line))
        } catch {
            onBadLine?(line)
        }
    }
}

public struct AgentStreamSink {
    public var onLine: (AgentStreamLine) -> Void
    /** Transport-level failure (no connection, HTTP error, unparseable line). */
    public var onError: (String) -> Void
    /** The response ended (after any error). */
    public var onClose: () -> Void

    public init(onLine: @escaping (AgentStreamLine) -> Void, onError: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        self.onLine = onLine
        self.onError = onError
        self.onClose = onClose
    }
}

private final class AgentStreamHandlers: StreamHandlers {
    let decoder: NdjsonDecoder
    let sink: AgentStreamSink
    var closed = false

    init(_ sink: AgentStreamSink) {
        self.sink = sink
        decoder = NdjsonDecoder { _ in sink.onError("the agent sent an unreadable line") }
    }

    func deliver(_ values: [Any?]) {
        for v in values {
            if let line = classifyLine(v) { sink.onLine(line) }
        }
    }

    func close() {
        if closed { return }
        closed = true
        sink.onClose()
    }

    func onChunk(_ text: String) {
        if !closed { deliver(decoder.push(text)) }
    }

    func onDone() {
        if closed { return }
        deliver(decoder.end())
        close()
    }

    func onError(_ message: String) {
        if closed { return }
        deliver(decoder.end())
        sink.onError(message.isEmpty ? "the agent could not be reached" : message)
        close()
    }
}

/** Start one agent turn; returns a canceller. */
@discardableResult
public func openAgentStream(_ endpoint: AgentEndpoint, _ body: AgentRequestBody, _ sink: AgentStreamSink) -> () -> Void {
    let handlers = AgentStreamHandlers(sink)
    var headers = ["content-type": "application/json", "accept": "application/x-ndjson"]
    for (k, v) in endpoint.headers ?? [:] { headers[k] = v }
    let request = FetchRequest(url: agentUrl(endpoint), method: "POST", headers: headers, body: JSON.stringify(body.toJson()),
                               timeoutMs: endpoint.timeoutMs ?? 300000)
    let cancel = platform().fetchStream(request, handlers)
    return {
        handlers.closed = true
        cancel()
    }
}
