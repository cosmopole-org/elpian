import Foundation

/**
 * The default widget set (widgets/registry.ts) — the same type names
 * `ElpianEngine._registerDefaultWidgets` registers in Flutter (Flutter DSL
 * widgets, Scene3D, animation widgets, HTML elements) plus the Next.js
 * navigation widgets that `NextjsBridge` adds.
 */
public func registerDefaultWidgets(_ engine: ElpianEngine) {
    engine.registerWidgets(flutterWidgets)
    engine.registerWidgets(animationWidgets)
    engine.registerWidgets(htmlWidgets)
    engine.registerWidgets(nextjsWidgets)
}

/** A builder of an ordered `(type, builder)` widget list, by type. */
public func widgetBuilder(_ list: [(String, WidgetBuilder)], _ type: String) -> WidgetBuilder? {
    list.first { $0.0 == type }?.1
}
