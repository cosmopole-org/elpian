import Foundation

/**
 * What the core needs from the platform it runs on (platform/platform.ts) —
 * UIKit on iOS, fakes in the tests. Everything is synchronous except
 * networking and asset loading, so the core lays out and paints inside a
 * single turn. Every callback is delivered on the main thread.
 */
public struct Viewport: Equatable {
    public var width: Double
    public var height: Double
    public var devicePixelRatio: Double
    public var safeArea: EdgeInsets
    /** e.g. `en-US`. */
    public var locale: String
    /** `android`, `ios`, `web`, … (Flutter's `defaultTargetPlatform`). */
    public var platform: String
    public var isWeb: Bool
    public var darkMode: Bool
    /** System text scale factor (accessibility). */
    public var textScale: Double
    /** The deep link / app URL. */
    public var href: String?

    public init(width: Double, height: Double, devicePixelRatio: Double = 1, safeArea: EdgeInsets = .zero, locale: String = "en-US",
                platform: String = "ios", isWeb: Bool = false, darkMode: Bool = false, textScale: Double = 1, href: String? = nil) {
        self.width = width
        self.height = height
        self.devicePixelRatio = devicePixelRatio
        self.safeArea = safeArea
        self.locale = locale
        self.platform = platform
        self.isWeb = isWeb
        self.darkMode = darkMode
        self.textScale = textScale
        self.href = href
    }
}

public struct FetchRequest {
    public var url: String
    public var method: String?
    public var headers: [String: String]?
    public var body: String?
    public var timeoutMs: Double?

    public init(url: String, method: String? = nil, headers: [String: String]? = nil, body: String? = nil, timeoutMs: Double? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.timeoutMs = timeoutMs
    }
}

public struct FetchResponse {
    public var status: Int
    public var headers: [String: String]
    public var body: String

    public init(status: Int, headers: [String: String], body: String) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

public protocol StreamHandlers: AnyObject {
    func onChunk(_ text: String)
    func onDone()
    func onError(_ message: String)
}

/** A Godot transport to the native engine (see godot/binding.ts). */
public protocol GodotPlatformBinding: AnyObject {
    var isLive: Bool { get }
    func post(_ opsJson: String)
    func send(_ opsJson: String) async throws -> String
    func mountSurface(_ surfaceId: Int, _ mountHandle: Int)
    func releaseSurface(_ surfaceId: Int)
    func setSignalHandler(_ handler: ((_ callbackId: Int, _ argsJson: String) -> Void)?)
    func stats() async -> JSONObject?
}

public extension GodotPlatformBinding {
    func stats() async -> JSONObject? { nil }
}

public enum LogLevel: String {
    case debug, info, warn, error
}

public enum AssetEncoding: String {
    case utf8, base64
}

public struct PlatformUnsupported: Error, CustomStringConvertible {
    public let feature: String
    public init(_ feature: String) { self.feature = feature }
    public var description: String { "Elpian core: the platform does not support \(feature)" }
}

public protocol Platform: AnyObject {
    var name: String { get }

    // ---- time and scheduling ----
    func now() -> Double
    func setTimeout(_ callback: @escaping () -> Void, _ ms: Double) -> Int
    func clearTimeout(_ handle: Int)
    /** Ask for [callback] on the next display frame (vsync), with the frame time in ms. */
    func requestFrame(_ callback: @escaping (Double) -> Void) -> Int
    func cancelFrame(_ handle: Int)

    // ---- rendering ----
    /** Apply a batch of view operations to [surface] (a session's root container). */
    func commit(_ surface: String, _ ops: [ViewOp])
    func measureText(_ spec: TextSpec, _ maxWidth: Double) -> TextMetrics
    /** Intrinsic size of a native control; return nil to use the core's Material defaults. */
    func measureControl(_ spec: ControlMeasureSpec, _ maxWidth: Double) -> Size?
    /** Natural pixel size of an image once known (nil while loading). */
    func imageSize(_ src: String) -> Size?
    /** Called by the core when it learns an image size is needed; the platform calls back `imageLoaded`. */
    func preloadImage(_ src: String)
    func viewport(_ surface: String) -> Viewport

    // ---- services ----
    func log(_ level: LogLevel, _ message: String)
    func openUrl(_ url: String)
    func fetch(_ request: FetchRequest) async throws -> FetchResponse
    /** Stream a response body; returns a canceller. */
    func fetchStream(_ request: FetchRequest, _ handlers: StreamHandlers) -> () -> Void
    func storageGet(_ key: String) -> String?
    func storageSet(_ key: String, _ value: String?)
    /** Load a bundled asset (`asset:` URIs / app asset paths) as text or base64. */
    func loadAsset(_ path: String, _ encoding: AssetEncoding) async throws -> String
    var godot: GodotPlatformBinding? { get }

    // ---- sandboxes (see VM/Bindings.swift) ----
    var elpianVm: ElpianVmBinding? { get }
    var jsSandbox: JsSandboxFactory? { get }
    var wasm: WasmEngine? { get }
}

/** The optional members of the TypeScript `Platform` interface. */
public extension Platform {
    func measureControl(_ spec: ControlMeasureSpec, _ maxWidth: Double) -> Size? { nil }
    func imageSize(_ src: String) -> Size? { nil }
    func preloadImage(_ src: String) {}
    func openUrl(_ url: String) {}
    func fetch(_ request: FetchRequest) async throws -> FetchResponse { throw PlatformUnsupported("fetch") }
    func fetchStream(_ request: FetchRequest, _ handlers: StreamHandlers) -> () -> Void {
        handlers.onError(PlatformUnsupported("fetchStream").description)
        return {}
    }
    func storageGet(_ key: String) -> String? { nil }
    func storageSet(_ key: String, _ value: String?) {}
    func loadAsset(_ path: String, _ encoding: AssetEncoding) async throws -> String { throw PlatformUnsupported("loadAsset") }
    var godot: GodotPlatformBinding? { nil }
    var elpianVm: ElpianVmBinding? { nil }
    var jsSandbox: JsSandboxFactory? { nil }
    var wasm: WasmEngine? { nil }
}

private let platformLock = NSLock()
private var currentPlatform: Platform?

public func setPlatform(_ platform: Platform) {
    platformLock.lock()
    currentPlatform = platform
    platformLock.unlock()
}

/** The installed platform. Traps when none is installed, as the TypeScript engine (native/web) throws. */
public func platform() -> Platform {
    platformLock.lock()
    defer { platformLock.unlock() }
    guard let p = currentPlatform else { fatalError("Elpian core: no platform installed (call setPlatform first)") }
    return p
}

public func hasPlatform() -> Bool {
    platformLock.lock()
    defer { platformLock.unlock() }
    return currentPlatform != nil
}
