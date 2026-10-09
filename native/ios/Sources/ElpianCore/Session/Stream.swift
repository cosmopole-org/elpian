import Foundation

/**
 * A view driven by a stream of commands — the port of `ElpianStreamWidget`
 * (flutter/lib/src/stream/elpian_stream_widget.dart; session/stream.ts).
 * Commands are pushed in (`push`), or read from a streaming HTTP response
 * (`connect`, NDJSON or server-sent events) through the platform.
 */
public struct ElpianStreamCommand {
    public var action: String
    public var view: JSONObject?
    public var patch: JSONObject?
    public var stylesheet: JSONObject?
    public var animate: Bool?
    public var animationDurationMs: Double?
    public var animationCurve: String?

    public init(action: String, view: JSONObject? = nil, patch: JSONObject? = nil, stylesheet: JSONObject? = nil, animate: Bool? = nil,
                animationDurationMs: Double? = nil, animationCurve: String? = nil) {
        self.action = action
        self.view = view
        self.patch = patch
        self.stylesheet = stylesheet
        self.animate = animate
        self.animationDurationMs = animationDurationMs
        self.animationCurve = animationCurve
    }

    public func toJson() -> JSONObject {
        JSONObject([
            ("action", action),
            ("view", view),
            ("patch", patch),
            ("stylesheet", stylesheet),
            ("animate", animate),
            ("animationDurationMs", animationDurationMs),
            ("animationCurve", animationCurve),
        ])
    }
}

public struct StreamCommandException: MessageError, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { "Error: \(message)" }
}

/** JavaScript's `typeof` for a JSON value. */
func jsTypeOf(_ v: Any?) -> String {
    guard let v = flattenOptional(v) else { return "object" }
    if v is String { return "string" }
    if jsBool(v) != nil { return "boolean" }
    if jsNumber(v) != nil { return "number" }
    return "object"
}

public func streamCommandFromDynamic(_ data: Any?) throws -> ElpianStreamCommand {
    let data = flattenOptional(data)
    if let s = data as? String { return try streamCommandFromDynamic(try JSON.parse(s)) }
    guard let m = asMap(data) else {
        throw StreamCommandException("Unsupported stream payload type: \(data == nil ? "null" : jsTypeOf(data)).")
    }
    if m.has("type") && !m.has("action") { return ElpianStreamCommand(action: "setView", view: m) }
    let action = m["action"] != nil ? jsString(m["action"]) : ""
    if action.isEmpty { throw StreamCommandException("Stream command must contain a non-empty \"action\".") }
    func map(_ v: Any?) throws -> JSONObject? {
        guard let v = flattenOptional(v) else { return nil }
        if let o = asMap(v) { return o }
        throw StreamCommandException("Expected a JSON object, got \(jsTypeOf(v)).")
    }
    func bool(_ v: Any?) throws -> Bool? {
        guard let v = flattenOptional(v) else { return nil }
        if let b = jsBool(v) { return b }
        if let s = v as? String {
            let t = jsTrim(s).lowercased()
            if t == "true" || t == "false" { return t == "true" }
        }
        throw StreamCommandException("Expected a bool, got \(jsTypeOf(v)).")
    }
    func int(_ v: Any?) throws -> Double? {
        guard let v = flattenOptional(v) else { return nil }
        if let n = jsNumber(v) { return n.isFinite ? jsTrunc(n) : n }
        if let s = v as? String {
            let n = jsParseInt(s, 10)
            return n.isNaN ? nil : n
        }
        throw StreamCommandException("Expected an int, got \(jsTypeOf(v)).")
    }
    return ElpianStreamCommand(
        action: action,
        view: try map(m["view"]),
        patch: try map(m["patch"]),
        stylesheet: try map(m["stylesheet"]),
        animate: try bool(m["animate"]),
        animationDurationMs: try int(m["animationDurationMs"]),
        animationCurve: m["animationCurve"] != nil ? jsString(m["animationCurve"]) : nil
    )
}

private let CURVES: Set<String> = ["linear", "easeIn", "easeOut", "easeInOut", "fastOutSlowIn", "bounceIn", "bounceOut"]

public struct StreamSessionOptions {
    public var initialStylesheet: JSONObject?
    public var onCommand: ((_ command: ElpianStreamCommand) -> Void)?
    public var onStreamDone: (() -> Void)?
    public var onError: ((_ message: String) -> Void)?
    public var defaultAnimationDurationMs: Double?
    public var defaultAnimationCurve: String?
    public var surface: SurfaceOptions?

    public init(initialStylesheet: JSONObject? = nil, onCommand: ((_ command: ElpianStreamCommand) -> Void)? = nil,
                onStreamDone: (() -> Void)? = nil, onError: ((_ message: String) -> Void)? = nil,
                defaultAnimationDurationMs: Double? = nil, defaultAnimationCurve: String? = nil, surface: SurfaceOptions? = nil) {
        self.initialStylesheet = initialStylesheet
        self.onCommand = onCommand
        self.onStreamDone = onStreamDone
        self.onError = onError
        self.defaultAnimationDurationMs = defaultAnimationDurationMs
        self.defaultAnimationCurve = defaultAnimationCurve
        self.surface = surface
    }
}

/** Splits a streamed body into lines (NDJSON or server-sent events) and pushes each command. */
private final class StreamLineReader: StreamHandlers {
    private weak var session: StreamSession?
    private var buffer = ""
    private var sse: [String] = []

    init(_ session: StreamSession) { self.session = session }

    private func line(_ raw: String) {
        guard let session = session else { return }
        let l = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
        if l.hasPrefix("data:") {
            var d = jsSubstring(l, 5)
            if d.hasPrefix(" ") { d.removeFirst() }
            sse.append(d)
            return
        }
        if l == "" {
            if !sse.isEmpty {
                let payload = sse.joined(separator: "\n")
                sse = []
                if !jsTrim(payload).isEmpty { session.push(payload) }
            }
            return
        }
        if l.hasPrefix(":") || SSE_FIELD.test(l) { return }
        if !jsTrim(l).isEmpty { session.push(l) }
    }

    func onChunk(_ text: String) {
        buffer += text
        while true {
            let i = jsIndexOf(buffer, "\n")
            if i < 0 { break }
            let l = jsSubstring(buffer, 0, i)
            buffer = jsSubstring(buffer, i + 1)
            line(l)
        }
    }

    func onDone() {
        if !buffer.isEmpty { line(buffer) }
        line("")
        buffer = ""
        session?.done()
    }

    func onError(_ message: String) {
        session?.error(message)
    }
}

open class StreamSession {
    public let options: StreamSessionOptions
    public let surface: ElpianSurface
    private var currentView: JSONObject?
    private var errorMessage: String?
    private var version = 0
    private var activeDuration = 0.0
    private var activeCurve = "linear"
    private var cancel: (() -> Void)?

    /** Run before the surface is disposed (e.g. `ElpianServerClient.mountStream` cancelling its stream). */
    public var beforeDispose: (() -> Void)?

    public init(_ surfaceId: String, _ options: StreamSessionOptions = StreamSessionOptions()) {
        self.options = options
        surface = ElpianSurface(surfaceId, options.surface ?? SurfaceOptions())
        if let sheet = options.initialStylesheet { surface.engine.loadStylesheet(sheet) }
        // AnimatedSwitcher(KeyedSubtree(ValueKey(version))) around the content.
        surface.decorate = { [weak self] content in
            guard let self = self else { return content }
            return w(
                "animatedSwitcher",
                ["duration": self.activeDuration, "curve": self.activeCurve, "transitionType": "fade"],
                [w("proxy", Props(), [content], "v\(self.version)")]
            )
        }
        refresh()
    }

    public var view: JSONObject? { currentView }

    /** Deliver one stream message (a command object, a bare view, or JSON text). */
    public func push(_ data: Any?) {
        do {
            let command = try streamCommandFromDynamic(data)
            options.onCommand?(command)
            try apply(command)
            if errorMessage != nil {
                errorMessage = nil
                refresh()
            }
        } catch {
            self.error(error)
        }
    }

    public func error(_ e: Any?) {
        let message = errorText(e)
        errorMessage = message
        options.onError?(message)
        refresh()
    }

    public func done() {
        options.onStreamDone?()
    }

    /**
     * Read commands from a streaming response: newline-delimited JSON, or
     * server-sent events (`data:` lines). Replaces any previous connection.
     * (A platform that cannot stream reports it through `onError`, so the TS
     * "cannot stream" branch has no separate counterpart.)
     */
    public func connect(_ request: FetchRequest) {
        cancel?()
        cancel = platform().fetchStream(request, StreamLineReader(self))
    }

    private func apply(_ c: ElpianStreamCommand) throws {
        let animate = c.animate ?? false
        let duration = c.animationDurationMs.map { max(0, min(30000, $0)) } ?? options.defaultAnimationDurationMs ?? 240
        let curve: String
        if let ac = c.animationCurve, !ac.isEmpty, CURVES.contains(jsTrim(ac)) { curve = jsTrim(ac) } else { curve = options.defaultAnimationCurve ?? "easeInOut" }
        func setActive() {
            activeDuration = animate ? duration : 0
            activeCurve = curve
        }
        switch c.action {
        case "setView":
            guard let v = c.view else { throw StreamCommandException("setView requires \"view\" object.") }
            setActive()
            update(v.copy())
        case "patchView":
            guard let p = c.patch else { throw StreamCommandException("patchView requires \"patch\" object.") }
            guard let cur = currentView else { throw StreamCommandException("patchView received before any setView command.") }
            setActive()
            update(deepMerge(cur, p))
        case "setStylesheet":
            guard let s = c.stylesheet else { throw StreamCommandException("setStylesheet requires \"stylesheet\" object.") }
            surface.engine.loadStylesheet(s)
            setActive()
            refresh()
        case "renderWithStylesheet":
            guard let s = c.stylesheet, let v = c.view else {
                throw StreamCommandException("renderWithStylesheet requires both \"stylesheet\" and \"view\".")
            }
            surface.engine.loadStylesheet(s)
            setActive()
            update(v.copy())
        case "clear":
            currentView = nil
            version += 1
            setActive()
            refresh()
        default:
            throw StreamCommandException("Unknown stream action: \(c.action).")
        }
    }

    private func update(_ view: JSONObject) {
        currentView = view
        version += 1
        refresh()
    }

    private func refresh() {
        if let err = errorMessage {
            surface.setOverlay(messageBox("Stream Error: \(err)", 0xfff44336))
            return
        }
        surface.setContent(currentView)
    }

    open func dispose() {
        beforeDispose?()
        beforeDispose = nil
        cancel?()
        cancel = nil
        surface.dispose()
    }
}

private let SSE_FIELD = JSRegex("^(event|id|retry):")
