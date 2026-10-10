import Foundation

/**
 * The default widget set (widgets/registry.ts) — the same type names
 * `ElpianEngine._registerDefaultWidgets` registers in Flutter (Flutter DSL
 * widgets, Scene3D, animation widgets, HTML elements) plus the Next.js
 * navigation widgets that `NextjsBridge` adds, and the A2UI surface widget
 * (`A2UISurface` / `a2ui-surface`).
 */
public func registerDefaultWidgets(_ engine: ElpianEngine) {
    engine.registerWidgets(flutterWidgets)
    engine.registerWidgets(animationWidgets)
    engine.registerWidgets(htmlWidgets)
    engine.registerWidgets(nextjsWidgets)
    engine.registerWidgets(a2uiWidgets)
}

/** A builder of an ordered `(type, builder)` widget list, by type. */
public func widgetBuilder(_ list: [(String, WidgetBuilder)], _ type: String) -> WidgetBuilder? {
    list.first { $0.0 == type }?.1
}
