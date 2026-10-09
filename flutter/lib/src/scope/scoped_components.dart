import 'scope_contract.dart';

/// Helpers for declaring independent Elpian component re-render boundaries.
///
/// Each direct child of a component root receives a stable target key and a
/// keyed `Scope` wrapper. A scoped render targets the inner key; ScopePatch then
/// bumps only that wrapper's render token, leaving sibling component widgets
/// cached and untouched.
Map<String, dynamic> isolateComponentChildren(
  Map<String, dynamic> root,
  String namespace,
) {
  final children = root['children'];
  if (children is! List) return root;

  root['children'] = [
    for (var index = 0; index < children.length; index++)
      _isolateChild(children[index], namespace, index),
  ];
  return root;
}

Map<String, dynamic> scopedComponent(
  String key,
  Map<String, dynamic> component,
) {
  final target = Map<String, dynamic>.from(component);
  target['key'] =
      target['key']?.toString().isNotEmpty == true ? target['key'] : key;
  return {
    'type': ScopeContract.type,
    'key': '$key${ScopeContract.wrapperKeySuffix}',
    'props': <String, dynamic>{},
    'children': [target],
  };
}

dynamic _isolateChild(dynamic child, String namespace, int index) {
  if (child is! Map) return child;
  final component = Map<String, dynamic>.from(child);
  if (component['type'] == ScopeContract.type) return component;
  final explicitKey = component['key']?.toString();
  final key = explicitKey != null && explicitKey.isNotEmpty
      ? explicitKey
      : '$namespace-component-$index';
  return scopedComponent(key, component);
}
