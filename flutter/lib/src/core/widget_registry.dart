import 'package:flutter/widgets.dart';
import '../models/elpian_node.dart';

/// Builds a widget for one node of an Elpian tree.
///
/// Prefer this name over [WidgetBuilder]: Flutter exports a `WidgetBuilder` of
/// its own (`Widget Function(BuildContext)`), so a file importing both
/// `package:flutter/material.dart` and this library cannot name either without
/// a prefix.
typedef ElpianWidgetBuilder = Widget Function(
    ElpianNode node, List<Widget> children);

/// The original spelling, kept so existing embedders keep compiling.
/// Ambiguous against Flutter's own `WidgetBuilder` — use
/// [ElpianWidgetBuilder] in new code.
typedef WidgetBuilder = ElpianWidgetBuilder;

class WidgetRegistry {
  WidgetRegistry();

  /// The registry every un-scoped caller sees.
  static final WidgetRegistry shared = WidgetRegistry();

  final Map<String, WidgetBuilder> _registry = {};

  void register(String type, WidgetBuilder builder) {
    _registry[type] = builder;
  }

  void registerAll(Map<String, WidgetBuilder> builders) {
    _registry.addAll(builders);
  }

  WidgetBuilder? get(String type) {
    return _registry[type];
  }

  bool has(String type) {
    return _registry.containsKey(type);
  }

  void unregister(String type) {
    _registry.remove(type);
  }

  void clear() {
    _registry.clear();
  }

  Map<String, WidgetBuilder> get all => Map.unmodifiable(_registry);
}
