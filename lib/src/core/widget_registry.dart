import 'package:flutter/widgets.dart';
import '../models/elpian_node.dart';

typedef WidgetBuilder = Widget Function(ElpianNode node, List<Widget> children);

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
