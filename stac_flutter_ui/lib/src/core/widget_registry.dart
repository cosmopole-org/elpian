import 'package:flutter/widgets.dart';
import '../models/stac_node.dart';

typedef WidgetBuilder = Widget Function(StacNode node, List<Widget> children);

class WidgetRegistry {
  static final WidgetRegistry _instance = WidgetRegistry._internal();
  factory WidgetRegistry() => _instance;
  WidgetRegistry._internal();

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
