#if canImport(UIKit)
import UIKit
#if !ELPIAN_SINGLE_MODULE
import ElpianCore
#endif

/** Which engines and services the iOS host installs (ElpianOptions in Elpian.kt). */
public struct ElpianOptions {
    /** Prefix for UserDefaults keys (per-app storage isolation). */
    public var storagePrefix: String
    /** The deep link / app URL reported to mini apps. */
    public var href: String?
    /** The Elpian VM (`libelpian_vm`, see scripts/build-rust.sh). */
    public var elpianVm: Bool
    /** JavaScript guests (JavaScriptCore). */
    public var javaScript: Bool
    /** WebAssembly guests (WasmKit). */
    public var wasm: Bool
    /** Godot `Scene3D` (live when a Godot runtime is linked, see godot/ios/README.md). */
    public var godot: Bool

    public init(storagePrefix: String = "", href: String? = nil, elpianVm: Bool = true, javaScript: Bool = true, wasm: Bool = true, godot: Bool = true) {
        self.storagePrefix = storagePrefix
        self.href = href
        self.elpianVm = elpianVm
        self.javaScript = javaScript
        self.wasm = wasm
        self.godot = godot
    }
}

/**
 * The iOS host of Elpian mini apps: the Swift core (`ElpianCore`) laid out and
 * rendered to UIKit views, with the Elpian VM, JavaScriptCore, WASM and Godot
 * engines. No JavaScript glue — JS only runs inside sandboxed guests.
 *
 *     Elpian.install()
 *     let view = ElpianHostView(frame: .zero)
 *     view.open(kind: "miniapp", options: ["runtime": "quickjs", "code": code, "entryFunction": "main"])
 *     _ = view.on("println") { print($0 ?? "") }
 */
public enum Elpian {
    /** The core's version (ElpianCore.VERSION in the Kotlin and TypeScript cores). */
    public static let coreVersion = "1.0.0"

    private static var platform_: IOSPlatform?
    private static var registry_: SessionRegistry?
    private static var hosts: [String: WeakHost] = [:]
    private static var nextSurface = 1
    private static var observers: [NSObjectProtocol] = []

    private struct WeakHost {
        weak var view: ElpianHostView?
    }

    public static var isInstalled: Bool { platform_ != nil }

    /** The installed platform (installing with defaults on first use). */
    public static var platform: IOSPlatform { install() }

    static var registry: SessionRegistry {
        if registry_ == nil { install() }
        return registry_!
    }

    /** Install the iOS platform once (idempotent; must run on the main thread). */
    @discardableResult
    public static func install(_ options: ElpianOptions = .init()) -> IOSPlatform {
        if let p = platform_ { return p }
        var godot: IOSGodotBinding?
        if options.godot { godot = IOSGodotBinding() }
        var wasm: WasmEngine?
        #if canImport(WasmKit)
        if options.wasm { wasm = WasmKitEngine() }
        #endif
        var js: JsSandboxFactory?
        #if canImport(JavaScriptCore)
        if options.javaScript { js = JSCoreSandboxFactory() }
        #endif
        let platform = IOSPlatform(
            godot: godot,
            elpianVm: options.elpianVm ? IOSElpianVm() : nil,
            jsSandbox: js,
            wasm: wasm,
            storagePrefix: options.storagePrefix,
            href: options.href
        )
        platform.godotSurfaceProvider = godot
        setPlatform(platform)
        let registry = SessionRegistry(emit: { surface, event, payload in
            hosts[surface]?.view?.deliver(event, payload)
        })
        _ = platform.onImageLoaded { src, w, h in registry.imageLoaded(src, Double(w), Double(h)) }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIContentSizeCategory.didChangeNotification, object: nil, queue: .main) { _ in
            platform.invalidateText()
            registry.invalidateText()
            for id in hosts.keys { registry.viewportChanged(id) }
        })
        observers.append(center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            platform.images.trim()
        })
        platform_ = platform
        registry_ = registry
        return platform
    }

    static func newSurfaceId() -> String {
        defer { nextSurface += 1 }
        return "elpian-\(nextSurface)"
    }

    static func register(_ id: String, _ host: ElpianHostView) {
        hosts[id] = WeakHost(view: host)
    }

    static func unregister(_ id: String) {
        hosts.removeValue(forKey: id)
    }

    /** Register a host-native component for `native` views / server-component islands. */
    public static func registerNativeComponent(_ name: String, factory: @escaping NativeComponentFactory, measurer: NativeComponentMeasurer? = nil) {
        NativeComponents.register(name, factory: factory, measurer: measurer)
    }

    /** Register a `custom` canvas command painter. */
    public static func registerCanvasPainter(_ name: String, _ painter: @escaping CustomCanvasPainter) {
        CanvasPainter.registerCanvasPainter(name, painter)
    }
}
#endif
