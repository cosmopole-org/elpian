/// The `Scope` contract — the one definition of the strings that make scoped
/// re-render work.
///
/// A scoped render is a three-party agreement:
///
///   * [scopedComponent] / the server bridge **declare** a boundary by emitting
///     a node of type [ScopeContract.type];
///   * [ScopePatch] **bumps** [ScopeContract.renderTokenProp] on the enclosing
///     boundaries of a patched subtree;
///   * `ElpianScope` **observes** that prop and rebuilds only when it changes.
///
/// Those three live in different folders by necessity (a node builder, a
/// tree transform, a widget). Before this file the agreement was carried by
/// bare string literals repeated across `vm/`, `integrations/`, `widgets/` and
/// `html_widgets/` — four subsystems that had to stay in step with no compiler
/// help. Renaming the prop meant grepping for a magic string and hoping.
///
/// Everything that participates now refers to these constants.
library;

abstract final class ScopeContract {
  /// The node `type` that marks a re-render boundary.
  static const String type = 'Scope';

  /// The prop [ScopePatch] stamps a monotonic token onto. A change is the only
  /// signal that tells a mounted `ElpianScope` to rebuild its cached child.
  static const String renderTokenProp = '__scopeRenderToken';

  /// The suffix [scopedComponent] appends when deriving a wrapper's key from
  /// the key of the component it wraps.
  static const String wrapperKeySuffix = '__scope';

  /// Whether a raw node map declares a scope boundary.
  static bool isScopeNode(Object? node) =>
      node is Map && node['type']?.toString() == type;
}
