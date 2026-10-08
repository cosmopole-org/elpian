import Foundation

/**
 * The live environment CSS values resolve against (css/environment.ts): the
 * viewport (for `%`, `vw`, `vh`, `vmin`, `vmax`, `calc()`), the safe-area
 * insets (for `env()`) and the root font size (for `rem`).
 *
 * Mirrors `CSSParser.viewportOverride` / `_safeAreaInsets` in Flutter. Each
 * session sets it before resolving styles; it is process-wide because the
 * parser is shared, exactly as in the Flutter engine.
 */
public struct CssEnvironmentValues: Equatable {
    public var viewportWidth: Double
    public var viewportHeight: Double
    public var safeArea: EdgeInsets
    public var rootFontSize: Double
    public var devicePixelRatio: Double
}

public enum CssEnvironment {
    private static let lock = NSLock()
    private static var env = CssEnvironmentValues(viewportWidth: 1280, viewportHeight: 800, safeArea: .zero, rootFontSize: 16, devicePixelRatio: 1)
    private static var gen = 0

    /** A snapshot of the environment (`cssEnvironment()`). */
    public static var current: CssEnvironmentValues {
        lock.lock()
        defer { lock.unlock() }
        return env
    }

    public static var viewportWidth: Double { current.viewportWidth }
    public static var viewportHeight: Double { current.viewportHeight }
    public static var safeArea: EdgeInsets { current.safeArea }
    public static var rootFontSize: Double { current.rootFontSize }
    public static var devicePixelRatio: Double { current.devicePixelRatio }

    /** Bumped whenever the environment changes, invalidating viewport-relative caches. */
    public static var generation: Int {
        lock.lock()
        defer { lock.unlock() }
        return gen
    }

    /** `updateCssEnvironment`: apply the given fields; true when anything changed. */
    @discardableResult
    public static func update(
        viewportWidth: Double? = nil,
        viewportHeight: Double? = nil,
        safeArea: EdgeInsets? = nil,
        rootFontSize: Double? = nil,
        devicePixelRatio: Double? = nil
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var changed = false
        if let v = viewportWidth, v != env.viewportWidth { env.viewportWidth = v; changed = true }
        if let v = viewportHeight, v != env.viewportHeight { env.viewportHeight = v; changed = true }
        if let v = safeArea, v != env.safeArea { env.safeArea = v; changed = true }
        if let v = rootFontSize, v != env.rootFontSize { env.rootFontSize = v; changed = true }
        if let v = devicePixelRatio, v != env.devicePixelRatio { env.devicePixelRatio = v; changed = true }
        if changed { gen += 1 }
        return changed
    }
}

public func cssEnvironment() -> CssEnvironmentValues { CssEnvironment.current }
public func cssEnvironmentGeneration() -> Int { CssEnvironment.generation }

@discardableResult
public func updateCssEnvironment(
    viewportWidth: Double? = nil,
    viewportHeight: Double? = nil,
    safeArea: EdgeInsets? = nil,
    rootFontSize: Double? = nil,
    devicePixelRatio: Double? = nil
) -> Bool {
    CssEnvironment.update(viewportWidth: viewportWidth, viewportHeight: viewportHeight, safeArea: safeArea,
                          rootFontSize: rootFontSize, devicePixelRatio: devicePixelRatio)
}
