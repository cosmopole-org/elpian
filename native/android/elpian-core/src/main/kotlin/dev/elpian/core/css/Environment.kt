package dev.elpian.core.css

/**
 * The live environment CSS values resolve against: viewport (`%`, `vw`, `vh`,
 * `calc()`), safe-area insets (`env()`), root font size (`rem`). Process-wide,
 * as `CSSParser.viewportOverride` is in Flutter; [generation] invalidates
 * viewport-relative caches.
 */
object CssEnvironment {
    @Volatile var viewportWidth = 1280.0
        private set
    @Volatile var viewportHeight = 800.0
        private set
    @Volatile var safeArea = EdgeInsets.ZERO
        private set
    @Volatile var rootFontSize = 16.0
        private set
    @Volatile var devicePixelRatio = 1.0
        private set
    @Volatile var generation = 0
        private set

    @Synchronized
    fun update(
        viewportWidth: Double? = null,
        viewportHeight: Double? = null,
        safeArea: EdgeInsets? = null,
        rootFontSize: Double? = null,
        devicePixelRatio: Double? = null,
    ): Boolean {
        var changed = false
        if (viewportWidth != null && viewportWidth != this.viewportWidth) { this.viewportWidth = viewportWidth; changed = true }
        if (viewportHeight != null && viewportHeight != this.viewportHeight) { this.viewportHeight = viewportHeight; changed = true }
        if (safeArea != null && safeArea != this.safeArea) { this.safeArea = safeArea; changed = true }
        if (rootFontSize != null && rootFontSize != this.rootFontSize) { this.rootFontSize = rootFontSize; changed = true }
        if (devicePixelRatio != null && devicePixelRatio != this.devicePixelRatio) { this.devicePixelRatio = devicePixelRatio; changed = true }
        if (changed) generation++
        return changed
    }
}
