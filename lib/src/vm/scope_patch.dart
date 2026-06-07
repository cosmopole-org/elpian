/// Scoped re-render application for server-driven / VM-driven Elpian views.
///
/// A `render(view, scopeKey)` host call from a client component (QuickJS / Elpian
/// VM) does not have to replace the whole tree: when it carries a `scopeKey`,
/// only the subtree whose node `key` matches is substituted, and the render
/// token on every enclosing `Scope` node is bumped so just those `Scope`
/// widgets rebuild (see `ElpianScope`). This is what isolates re-render
/// propagation after a local state mutation — a tab switch, a drag, a HUD tick —
/// from the rest of the screen.
///
/// These helpers are deliberately widget-free and side-effect-free (beyond the
/// in-place tree mutation they are asked to perform) so the same logic backs
/// both [ElpianVmWidget] and the Next.js bridge, and so it can be unit-tested
/// without a Flutter binding.
class ScopePatch {
  ScopePatch._();

  /// Monotonic token stamped onto `Scope` nodes. Incrementing it on a render is
  /// what tells an already-mounted `ElpianScope` to rebuild its cached child.
  static int _tokenCounter = 0;

  /// A trimmed, non-empty scope key, or null for "no scope → full render".
  static String? normalizeKey(String? scopeKey) {
    if (scopeKey == null) return null;
    final normalized = scopeKey.trim();
    if (normalized.isEmpty || normalized == 'null') return null;
    return normalized;
  }

  /// Ensure the replacement subtree carries the target [key] so it matches on a
  /// subsequent scoped render. Returns [json] unchanged when it already has a
  /// non-empty key.
  static Map<String, dynamic> ensureKey(
    Map<String, dynamic> json,
    String key,
  ) {
    if ((json['key']?.toString().isNotEmpty ?? false)) return json;
    return <String, dynamic>{...json, 'key': key};
  }

  /// Bump the render token on every `Scope` node *inside* [json] (in place) so a
  /// freshly substituted subtree's own scopes refresh. Returns [json].
  static Map<String, dynamic> markRerender(Map<String, dynamic> json) {
    _markTokensInPlace(json);
    return json;
  }

  /// Replace the node whose `key` equals [targetKey] within [tree] (mutated in
  /// place) with [replacement], bumping the render token on every enclosing
  /// `Scope` ancestor so they rebuild. Returns true when the key was found.
  static bool replaceByKey(
    Map<String, dynamic> tree,
    String targetKey,
    Map<String, dynamic> replacement,
  ) {
    return _replace(tree, targetKey, replacement, <Map<String, dynamic>>[]);
  }

  /// Resolve a scoped render against [tree]:
  ///
  /// * no scope key (or no existing [tree]) → return [view] for a full render;
  /// * key found → patch [tree] in place and return it (same instance);
  /// * key missing → return [view] (caller falls back to a full render).
  static Map<String, dynamic> apply(
    Map<String, dynamic>? tree,
    Map<String, dynamic> view,
    String? scopeKey,
  ) {
    final key = normalizeKey(scopeKey);
    if (key == null || tree == null) return view;
    final replacement = markRerender(ensureKey(view, key));
    final replaced = replaceByKey(tree, key, replacement);
    return replaced ? tree : view;
  }

  static bool _replace(
    Map<String, dynamic> node,
    String targetKey,
    Map<String, dynamic> replacement,
    List<Map<String, dynamic>> scopeAncestors,
  ) {
    if (node['key']?.toString() == targetKey) {
      node
        ..clear()
        ..addAll(replacement);
      _markNodes(scopeAncestors);
      return true;
    }

    final isScope = node['type']?.toString() == 'Scope';
    if (isScope) scopeAncestors.add(node);

    final children = node['children'];
    if (children is! List) {
      if (isScope) scopeAncestors.removeLast();
      return false;
    }

    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      if (child is! Map) continue;
      final childMap = child is Map<String, dynamic>
          ? child
          : Map<String, dynamic>.from(child);
      final replaced = _replace(childMap, targetKey, replacement, scopeAncestors);
      if (!identical(child, childMap)) children[i] = childMap;
      if (replaced) {
        if (isScope) scopeAncestors.removeLast();
        return true;
      }
    }

    if (isScope) scopeAncestors.removeLast();
    return false;
  }

  static void _markNodes(List<Map<String, dynamic>> scopeNodes) {
    for (final scopeNode in scopeNodes) {
      final props =
          Map<String, dynamic>.from(scopeNode['props'] as Map? ?? const {});
      props['__scopeRenderToken'] = ++_tokenCounter;
      scopeNode['props'] = props;
    }
  }

  static void _markTokensInPlace(dynamic node) {
    if (node is! Map) return;
    if (node['type']?.toString() == 'Scope') {
      final props =
          Map<String, dynamic>.from(node['props'] as Map? ?? const {});
      props['__scopeRenderToken'] = ++_tokenCounter;
      node['props'] = props;
    }
    final children = node['children'];
    if (children is! List) return;
    for (final child in children) {
      _markTokensInPlace(child);
    }
  }
}
