#if canImport(UIKit)
import UIKit
import os.log
#if !ELPIAN_SINGLE_MODULE
import ElpianCore
#endif

/**
 * iOS as an Elpian platform (AndroidPlatform.kt, platform.ts on the web): the
 * main thread, CADisplayLink frames, main-queue timers, commits through a
 * [ViewRenderer] per surface, TextKit text measurement, viewports (size,
 * scale, safe area, locale, dark mode, Dynamic Type scale), the image cache,
 * URLSession networking (with streaming), UserDefaults storage and bundled
 * assets. The engines (Godot, the Elpian VM, the JS sandbox, WASM) are
 * injected by the host (see [Elpian.install]).
 */
open class IOSPlatform: Platform {
    public let name = "ios"
    public let godot: GodotPlatformBinding?
    public let elpianVm: ElpianVmBinding?
    public let jsSandbox: JsSandboxFactory?
    public let wasm: WasmEngine?
    /** Prefix for storage keys. */
    private let storagePrefix: String
    /** The deep link / app URL reported in viewports. */
    public var href: String?
    /** The Godot binding's surface provider for `scene3d` views. */
    public var godotSurfaceProvider: GodotSurfaceProvider?

    public let images = ImageLoader()
    private let defaults: UserDefaults
    private var timers: [Int: DispatchWorkItem] = [:]
    private var nextTimer = 1
    private var frameCallbacks: [Int: (Double) -> Void] = [:]
    private var nextFrame = 1
    private var displayLink: CADisplayLink?
    private let session: URLSession
    private static let logger = OSLog(subsystem: "dev.elpian", category: "Elpian")

    private final class SurfaceEntry {
        let root: ElpianSurfaceView
        let renderer: ViewRenderer
        let hooks: Hooks
        init(_ root: ElpianSurfaceView, _ renderer: ViewRenderer, _ hooks: Hooks) {
            self.root = root
            self.renderer = renderer
            self.hooks = hooks
        }
    }

    private final class Hooks: RendererHooks {
        weak var platform: IOSPlatform?
        let sink: (ViewEvent) -> Void
        init(_ platform: IOSPlatform, _ sink: @escaping (ViewEvent) -> Void) {
            self.platform = platform
            self.sink = sink
        }
        func emit(_ event: ViewEvent) { sink(event) }
        func imageLoaded(_ src: String, _ width: Int, _ height: Int) {
            guard let images = platform?.images else { return }
            if let natural = images.size(src), width > 0 {
                images.reportSize(src, natural.0, natural.1)
            } else {
                images.reportSize(src, width, height)
            }
        }
        func loadImage(_ src: String, _ callback: @escaping (UIImage?) -> Void) {
            guard let images = platform?.images else { return callback(nil) }
            images.load(src, callback)
        }
        func godotSurfaces() -> GodotSurfaceProvider? { platform?.godotSurfaceProvider }
    }

    private var surfaces: [String: SurfaceEntry] = [:]

    public init(godot: GodotPlatformBinding? = nil, elpianVm: ElpianVmBinding? = nil, jsSandbox: JsSandboxFactory? = nil, wasm: WasmEngine? = nil,
                storagePrefix: String = "", href: String? = nil, defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.godot = godot
        self.elpianVm = elpianVm
        self.jsSandbox = jsSandbox
        self.wasm = wasm
        self.storagePrefix = storagePrefix
        self.href = href
        self.defaults = defaults
        self.session = session
        ElpianFonts.registerBundledFonts()
    }

    // ---------------------------------------------------------------------
    // Surfaces
    // ---------------------------------------------------------------------

    /** Render surface [id] into [root]; [emit] receives the view events (→ the session). */
    @discardableResult
    public func attachSurface(_ id: String, _ root: ElpianSurfaceView, _ emit: @escaping (ViewEvent) -> Void) -> ViewRenderer {
        detachSurface(id)
        let hooks = Hooks(self, emit)
        let renderer = ViewRenderer(root: root, hooks: hooks)
        surfaces[id] = SurfaceEntry(root, renderer, hooks)
        return renderer
    }

    public func detachSurface(_ id: String) {
        guard let s = surfaces.removeValue(forKey: id) else { return }
        s.renderer.clear()
    }

    public func renderer(_ id: String) -> ViewRenderer? { surfaces[id]?.renderer }

    /** The view hosting Godot surface [surfaceId] on any attached surface (for [IOSGodotBinding]). */
    public func godotSurfaceContainer(_ surfaceId: Int) -> UIView? {
        for s in surfaces.values { if let v = s.renderer.scene3dContainer(surfaceId) { return v } }
        return nil
    }

    /** Listen for image natural sizes (→ the session's `imageLoaded`). */
    public func onImageLoaded(_ listener: @escaping (_ src: String, _ width: Int, _ height: Int) -> Void) -> () -> Void {
        images.onImageLoaded(listener)
    }

    /** Fonts or text scale changed: drop cached metrics. */
    public func invalidateText() { TextEngine.clearCache() }

    // ---------------------------------------------------------------------
    // Time and scheduling
    // ---------------------------------------------------------------------

    public func now() -> Double { CACurrentMediaTime() * 1000 }

    public func setTimeout(_ callback: @escaping () -> Void, _ ms: Double) -> Int {
        let handle = nextTimer
        nextTimer += 1
        let w = DispatchWorkItem { [weak self] in
            self?.timers.removeValue(forKey: handle)
            callback()
        }
        timers[handle] = w
        let delay = ms.isFinite && ms > 0 ? ms / 1000 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
        return handle
    }

    public func clearTimeout(_ handle: Int) {
        timers.removeValue(forKey: handle)?.cancel()
    }

    public func requestFrame(_ callback: @escaping (Double) -> Void) -> Int {
        let handle = nextFrame
        nextFrame += 1
        let schedule = { [weak self] in
            guard let self = self else { return }
            self.frameCallbacks[handle] = callback
            if self.displayLink == nil {
                let link = CADisplayLink(target: DisplayLinkProxy { [weak self] in self?.frame() }, selector: #selector(DisplayLinkProxy.tick))
                link.add(to: .main, forMode: .common)
                self.displayLink = link
            }
            self.displayLink?.isPaused = false
        }
        if Thread.isMainThread { schedule() } else { DispatchQueue.main.async(execute: schedule) }
        return handle
    }

    public func cancelFrame(_ handle: Int) {
        frameCallbacks.removeValue(forKey: handle)
    }

    private func frame() {
        let t = (displayLink?.timestamp ?? CACurrentMediaTime()) * 1000
        let due = frameCallbacks.sorted { $0.key < $1.key }
        frameCallbacks.removeAll()
        for (_, cb) in due { cb(t) }
        if frameCallbacks.isEmpty { displayLink?.isPaused = true }
    }

    // ---------------------------------------------------------------------
    // Rendering
    // ---------------------------------------------------------------------

    public func commit(_ surface: String, _ ops: [ViewOp]) {
        guard let s = surfaces[surface] else { return }
        s.renderer.apply(ops, scale: s.root.window?.screen.scale ?? UIScreen.main.scale)
    }

    public func measureText(_ spec: TextSpec, _ maxWidth: Double) -> TextMetrics { TextEngine.measure(spec, maxWidth) }

    public func measureControl(_ spec: ControlMeasureSpec, _ maxWidth: Double) -> Size? {
        if spec.kind == .native {
            guard let name = spec.props["component"] as? String else { return nil }
            let props = asMap(spec.props["componentProps"]) ?? JSONObject()
            return NativeComponents.measurer(name)?(props, maxWidth)
        }
        // The core's sizes are the Material defaults the custom-drawn controls use.
        return nil
    }

    public func imageSize(_ src: String) -> Size? {
        images.size(src).map { Size(width: Double($0.0), height: Double($0.1)) }
    }

    public func preloadImage(_ src: String) { images.preload(src) }

    public func viewport(_ surface: String) -> Viewport {
        let root = surfaces[surface]?.root
        let screen = root?.window?.screen ?? UIScreen.main
        let traits = root?.traitCollection ?? UITraitCollection.current
        let w = root.map { $0.bounds.width > 0 ? $0.bounds.width : screen.bounds.width } ?? screen.bounds.width
        let h = root.map { $0.bounds.height > 0 ? $0.bounds.height : screen.bounds.height } ?? screen.bounds.height
        let insets = root?.safeAreaInsets ?? .zero
        let locale = Locale.preferredLanguages.first ?? Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        let scaleFactor = UIFontMetrics(forTextStyle: .body).scaledValue(for: 17, compatibleWith: traits) / 17
        return Viewport(
            width: Double(w),
            height: Double(h),
            devicePixelRatio: Double(screen.scale),
            safeArea: EdgeInsets(top: Double(insets.top), right: Double(insets.right), bottom: Double(insets.bottom), left: Double(insets.left)),
            locale: locale,
            platform: "ios",
            isWeb: false,
            darkMode: traits.userInterfaceStyle == .dark,
            textScale: Double(scaleFactor),
            href: href
        )
    }

    // ---------------------------------------------------------------------
    // Services
    // ---------------------------------------------------------------------

    public func log(_ level: LogLevel, _ message: String) {
        let type: OSLogType
        switch level {
        case .debug: type = .debug
        case .warn: type = .default
        case .error: type = .error
        case .info: type = .info
        }
        os_log("[elpian] %{public}@", log: IOSPlatform.logger, type: type, message)
    }

    public func openUrl(_ url: String) {
        guard let u = URL(string: url) else {
            log(.warn, "openUrl(\(url)): not a URL")
            return
        }
        DispatchQueue.main.async {
            UIApplication.shared.open(u, options: [:]) { ok in
                if !ok { self.log(.warn, "openUrl(\(url)) failed") }
            }
        }
    }

    private func request(_ r: FetchRequest) throws -> URLRequest {
        guard let u = URL(string: r.url) else { throw PlatformError("network error reaching \(r.url): invalid URL") }
        var req = URLRequest(url: u)
        let method = (r.method ?? "GET").uppercased()
        req.httpMethod = method
        if let t = r.timeoutMs { req.timeoutInterval = t / 1000 }
        for (k, v) in r.headers ?? [:] { req.setValue(v, forHTTPHeaderField: k) }
        if let body = r.body, method != "GET" && method != "HEAD" { req.httpBody = body.data(using: .utf8) }
        return req
    }

    private static func headers(_ response: URLResponse?) -> [String: String] {
        var out: [String: String] = [:]
        guard let http = response as? HTTPURLResponse else { return out }
        for (k, v) in http.allHeaderFields {
            out[String(describing: k).lowercased()] = String(describing: v)
        }
        return out
    }

    public func fetch(_ r: FetchRequest) async throws -> FetchResponse {
        let req = try request(r)
        do {
            let (data, response) = try await session.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            return FetchResponse(status: status, headers: IOSPlatform.headers(response), body: String(decoding: data, as: UTF8.self))
        } catch let e as URLError where e.code == .timedOut {
            throw PlatformError("request to \(r.url) timed out")
        } catch {
            throw PlatformError("network error reaching \(r.url): \(error.localizedDescription)")
        }
    }

    public func fetchStream(_ r: FetchRequest, _ handlers: StreamHandlers) -> () -> Void {
        let req: URLRequest
        do {
            req = try request(r)
        } catch {
            handlers.onError("\(error)")
            return {}
        }
        let stream = StreamTask(handlers)
        let s = URLSession(configuration: session.configuration, delegate: stream, delegateQueue: nil)
        let task = s.dataTask(with: req)
        stream.task = task
        task.resume()
        s.finishTasksAndInvalidate()
        return { stream.cancel() }
    }

    public func storageGet(_ key: String) -> String? { defaults.string(forKey: storagePrefix + key) }

    public func storageSet(_ key: String, _ value: String?) {
        if let v = value { defaults.set(v, forKey: storagePrefix + key) } else { defaults.removeObject(forKey: storagePrefix + key) }
    }

    /** A bundled file by relative path: the main bundle first, then the Elpian resource bundles. */
    public static func bundleURL(_ path: String) -> URL? {
        let p = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var bundles = [Bundle.main]
        bundles.append(contentsOf: ElpianFonts.resourceBundles())
        for b in bundles {
            if let base = b.resourceURL {
                let u = base.appendingPathComponent(p)
                if FileManager.default.fileExists(atPath: u.path) { return u }
            }
            let ns = p as NSString
            if let u = b.url(forResource: ns.lastPathComponent, withExtension: nil, subdirectory: ns.deletingLastPathComponent.isEmpty ? nil : ns.deletingLastPathComponent) {
                return u
            }
        }
        return nil
    }

    public func loadAsset(_ path: String, _ encoding: AssetEncoding) async throws -> String {
        var p = path
        if p.hasPrefix("asset:") { p = String(p.dropFirst("asset:".count)) }
        p = p.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let u = IOSPlatform.bundleURL(p) else { throw PlatformError("asset \(path): not found in the app bundle") }
        let data: Data
        do {
            data = try Data(contentsOf: u)
        } catch {
            throw PlatformError("asset \(path): \(error.localizedDescription)")
        }
        switch encoding {
        case .utf8: return String(decoding: data, as: UTF8.self)
        case .base64: return data.base64EncodedString()
        }
    }
}

/** A platform service failure (the message is what the core reports). */
public struct PlatformError: Error, CustomStringConvertible, LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
    public var errorDescription: String? { message }
}

/** A streaming response body, decoded as UTF-8 across chunk boundaries and delivered on the main thread. */
private final class StreamTask: NSObject, URLSessionDataDelegate {
    private let handlers: StreamHandlers
    var task: URLSessionDataTask?
    private var cancelled = false
    private var pendingBytes = Data()
    private let lock = NSLock()

    init(_ handlers: StreamHandlers) {
        self.handlers = handlers
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
        task?.cancel()
    }

    private func main(_ block: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isCancelled else { return }
            block()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let status = http.statusCode
            main { self.handlers.onError("HTTP status \(status)") }
            lock.lock()
            cancelled = true
            lock.unlock()
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        pendingBytes.append(data)
        // Keep an incomplete trailing UTF-8 sequence for the next chunk.
        var cut = pendingBytes.count
        var i = pendingBytes.count - 1
        var back = 0
        while i >= 0 && back < 4 {
            let b = pendingBytes[pendingBytes.startIndex + i]
            if b & 0xC0 == 0x80 {
                i -= 1
                back += 1
                continue
            }
            let need = b & 0x80 == 0 ? 1 : (b & 0xE0 == 0xC0 ? 2 : (b & 0xF0 == 0xE0 ? 3 : 4))
            if pendingBytes.count - i < need { cut = i }
            break
        }
        let ready = pendingBytes.prefix(cut)
        pendingBytes = Data(pendingBytes.suffix(from: pendingBytes.startIndex + cut))
        if ready.isEmpty { return }
        let chunk = String(decoding: ready, as: UTF8.self)
        main { self.handlers.onChunk(chunk) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if isCancelled { return }
        if let e = error {
            main { self.handlers.onError(e.localizedDescription) }
            return
        }
        if !pendingBytes.isEmpty {
            let rest = String(decoding: pendingBytes, as: UTF8.self)
            pendingBytes = Data()
            main { self.handlers.onChunk(rest) }
        }
        main { self.handlers.onDone() }
    }
}
#endif
