package dev.elpian.core.widgets

import dev.elpian.core.engine.ElpianEngine

/**
 * The default widget set (widgets/registry.ts) — the same type names
 * `ElpianEngine._registerDefaultWidgets` registers in Flutter (Flutter DSL
 * widgets, Scene3D, animation widgets, HTML elements) plus the Next.js
 * navigation widgets that `NextjsBridge` adds.
 */
fun registerDefaultWidgets(engine: ElpianEngine) {
    engine.registerWidgets(flutterWidgets)
    engine.registerWidgets(animationWidgets)
    engine.registerWidgets(htmlWidgets)
    engine.registerWidgets(nextjsWidgets)
}
