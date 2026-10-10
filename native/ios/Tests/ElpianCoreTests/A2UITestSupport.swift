import XCTest
@testable import ElpianCore

/**
 * Shared harness for the A2UI tests (the port of native/web/test/a2ui/harness.mjs):
 * a headless platform (fixed-width text metrics, recorded view ops, manual
 * timers and frames, scripted fetchStream) and paths to the vendored A2UI files.
 */
enum A2UIFiles {
    /** The repository root (…/native/ios/Tests/ElpianCoreTests/<file> → …). */
    static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let a2ui = repo.appendingPathComponent("a2ui")

    static func json(_ url: URL) -> Any? {
        let text = try! String(contentsOf: url, encoding: .utf8)
        return try! JSON.parse(text)
    }

    static func conformance(_ name: String) -> [JSONObject] {
        (asArray(json(a2ui.appendingPathComponent("conformance/json/\(name).json"))) ?? []).compactMap { asMap($0) }
    }

    static var examplesDir: URL { a2ui.appendingPathComponent("spec/catalogs/basic/examples") }

    /** Every basic catalog example, sorted by file name. */
    static func examples() -> [(file: String, json: JSONObject)] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: examplesDir.path)) ?? []
        return files.filter { $0.hasSuffix(".json") }.sorted().map { ($0, asMap(json(examplesDir.appendingPathComponent($0)))!) }
    }

    static func example(_ file: String) -> JSONObject { asMap(json(examplesDir.appendingPathComponent(file)))! }

    static var catalog: JSONObject { asMap(json(a2ui.appendingPathComponent("spec/catalogs/basic/catalog.json")))! }
}

/** A scripted agent response: chunks delivered one per timer tick, then done (or [error]). */
struct A2UIStreamScript {
    var chunks: [String]
    var error: String?
}

final class A2UITestPlatform: Platform {
    let name = "test"
    var commits: [(String, [ViewOp])] = []
    var logs: [String] = []
    var opened: [String] = []
    var requests: [FetchRequest] = []
    var streamScript: ((FetchRequest) -> A2UIStreamScript)?
    private var frames: [(Int, (Double) -> Void)] = []
    private var nextFrame = 1
    private var clock = 0.0
    private var timers: [(handle: Int, at: Double, fn: () -> Void)] = []
    private var nextTimer = 1

    func now() -> Double { clock }
    func setTimeout(_ callback: @escaping () -> Void, _ ms: Double) -> Int {
        let h = nextTimer
        nextTimer += 1
        timers.append((h, clock + ms, callback))
        return h
    }
    func clearTimeout(_ handle: Int) { timers.removeAll { $0.handle == handle } }
    func requestFrame(_ callback: @escaping (Double) -> Void) -> Int {
        let h = nextFrame
        nextFrame += 1
        frames.append((h, callback))
        return h
    }
    func cancelFrame(_ handle: Int) { frames.removeAll { $0.0 == handle } }
    func commit(_ surface: String, _ ops: [ViewOp]) { commits.append((surface, ops)) }
    /** Each character is half the font size wide; lines are 1.2 em. */
    func measureText(_ spec: TextSpec, _ maxWidth: Double) -> TextMetrics {
        let fs = spec.spans.first?.style.fontSize ?? 14
        let chars = spec.spans.reduce(0) { $0 + jsLength($1.text) }
        let natural = Double(chars) * fs * 0.5
        let lines: Double = maxWidth == INF || natural <= maxWidth || maxWidth <= 0 ? 1 : (natural / maxWidth).rounded(.up)
        return TextMetrics(width: min(natural, maxWidth), height: lines * fs * 1.2, baseline: fs * 0.8,
                           lineCount: lines.isFinite ? Int(lines) : Int.max, didExceedMaxLines: false)
    }
    func viewport(_ surface: String) -> Viewport {
        Viewport(width: 400, height: 800, devicePixelRatio: 1, safeArea: .zero, locale: "en-US", platform: "ios", isWeb: false, darkMode: false, textScale: 1)
    }
    func log(_ level: LogLevel, _ message: String) { logs.append("\(level.rawValue): \(message)") }
    func openUrl(_ url: String) { opened.append(url) }

    func fetchStream(_ request: FetchRequest, _ handlers: StreamHandlers) -> () -> Void {
        requests.append(request)
        let script = streamScript?(request) ?? A2UIStreamScript(chunks: [])
        var cancelled = false
        var steps: [() -> Void] = script.chunks.map { c in { handlers.onChunk(c) } }
        steps.append { if let e = script.error { handlers.onError(e) } else { handlers.onDone() } }
        func run(_ i: Int) {
            guard i < steps.count else { return }
            _ = setTimeout({
                if cancelled { return }
                steps[i]()
                run(i + 1)
            }, 1)
        }
        run(0)
        return { cancelled = true }
    }

    /** Run main-actor tasks, timers (advancing the clock) and frames until idle. */
    @MainActor
    func drain() async {
        for _ in 0..<500 {
            for _ in 0..<10 { await Task.yield() }
            if let soonest = timers.map({ $0.at }).min(), soonest > clock { clock = soonest }
            let due = timers.filter { $0.at <= clock }
            timers.removeAll { t in due.contains { $0.handle == t.handle } }
            for t in due { t.fn() }
            let f = frames
            frames.removeAll()
            if !f.isEmpty { clock += 16 }
            for (_, cb) in f { cb(clock) }
            if due.isEmpty && f.isEmpty {
                for _ in 0..<20 { await Task.yield() }
                if timers.isEmpty && frames.isEmpty { return }
            }
        }
    }
}

/** Walk a lowered node JSON tree depth first. */
func a2uiWalk(_ node: JSONObject, _ fn: (JSONObject) -> Void) {
    fn(node)
    for c in asArray(node["children"]) ?? [] {
        if let m = asMap(c) { a2uiWalk(m, fn) }
    }
}

func a2uiFind(_ node: JSONObject, _ pred: (JSONObject) -> Bool) -> JSONObject? {
    var hit: JSONObject?
    a2uiWalk(node) { n in if hit == nil && pred(n) { hit = n } }
    return hit
}

func a2uiProps(_ node: JSONObject?) -> JSONObject { asMap(node?["props"]) ?? JSONObject() }

/** Fire a lowered node's event closure as the engine would. */
func a2uiFire(_ node: JSONObject?, _ name: String, value: Any? = nil, hasValue: Bool = false) {
    guard let fn = asMap(node?["events"])?[name] as? ElpianEventListener else {
        XCTFail("no \(name) handler")
        return
    }
    let e = ElpianEvent(type: name, eventType: name, target: nil)
    if hasValue || value != nil { e.value = value }
    fn(e)
}

func a2uiJson(_ text: String) -> JSONObject { asMap(try! JSON.parse(text))! }
