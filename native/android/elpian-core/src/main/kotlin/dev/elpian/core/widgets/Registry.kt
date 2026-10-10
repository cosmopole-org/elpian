package dev.elpian.core.widgets

import dev.elpian.core.engine.ElpianEngine

/**
 * The default widget set (widgets/registry.ts) — the same type names
 * `ElpianEngine._registerDefaultWidgets` registers in Flutter (Flutter DSL
 * widgets, Scene3D, animation widgets, HTML elements) plus the Next.js
 * navigation widgets that `NextjsBridge` adds, and the A2UI surface widget
 * (`A2UISurface` / `a2ui-surface`).
 */
fun registerDefaultWidgets(engine: ElpianEngine) {
    engine.registerWidgets(flutterWidgets)
    engine.registerWidgets(animationWidgets)
    engine.registerWidgets(htmlWidgets)
    engine.registerWidgets(nextjsWidgets)
    engine.registerWidgets(dev.elpian.core.a2ui.a2uiWidgets)
}
