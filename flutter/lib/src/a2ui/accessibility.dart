/// The accessibility semantics of an A2UI surface: per component its role,
/// label, description and state, from the component's `accessibility`
/// attributes or inferred from its visible content (a button's child text, an
/// input's label, an image's description). The lowering applies these to
/// Flutter semantics (button labels, image semantic labels); the conformance
/// `accessibility_check` cases read this tree directly.
library;

import 'context.dart';
import 'markdown.dart';
import 'processor.dart';

class A2UIAccessibilityNode {
  A2UIAccessibilityNode(this.id, this.role);

  final String id;
  final String role;
  String? label;
  String? description;
  bool? checked;
  String? live;
  bool? hidden;

  /// For bound attributes: the data path each one reads (`label`,
  /// `description`, `hidden`, `live`).
  Map<String, String>? bindings;

  /// The attribute named [name] (as the conformance cases spell it).
  Object? operator [](String name) => switch (name) {
        'id' => id,
        'role' => role,
        'label' => label,
        'description' => description,
        'checked' => checked,
        'live' => live,
        'hidden' => hidden,
        _ => null,
      };
}

const Map<String, String> _roles = {
  'Text': 'text',
  'Image': 'img',
  'Icon': 'img',
  'Video': 'video',
  'AudioPlayer': 'audio',
  'Row': 'group',
  'Column': 'group',
  'List': 'list',
  'Card': 'group',
  'Tabs': 'tablist',
  'Modal': 'dialog',
  'Divider': 'separator',
  'Button': 'button',
  'TextField': 'textbox',
  'CheckBox': 'checkbox',
  'Slider': 'slider',
  'DateTimeInput': 'textbox',
};

String accessibilityRole(A2UIComponent c) {
  if (c['component'] == 'ChoicePicker') {
    return c['variant'] == 'multipleSelection' ? 'group' : 'radiogroup';
  }
  return _roles[c['component']] ?? 'generic';
}

/// Semantics for one component (in the surface's root data scope).
A2UIAccessibilityNode describeAccessibility(
    A2UISurfaceModel surface, A2UIComponent c,
    [String scope = '/']) {
  final ctx = surface.context(scope);
  String text(Object? v) =>
      ctx.safe(() => plainText(parseMarkdown(ctx.string(v))), '');
  final node = A2UIAccessibilityNode('${c['id']}', accessibilityRole(c));
  final bindings = <String, String>{};
  final a = c['accessibility'] is Map ? c['accessibility'] as Map : const {};
  for (final attr in ['label', 'description', 'live', 'hidden']) {
    if (!a.containsKey(attr)) continue;
    final v = a[attr];
    if (isBinding(v)) {
      bindings[attr] = ctx.resolvePath((v as Map)['path'] as String);
    }
    final value = ctx.safe<Object?>(() => ctx.evaluate(v), null);
    if (attr == 'hidden') {
      if (value != null) node.hidden = value == true;
    } else if (value != null && value != '') {
      final s = '$value';
      if (attr == 'label') node.label = s;
      if (attr == 'description') node.description = s;
      if (attr == 'live') node.live = s;
    }
  }
  if (node.label == null && !bindings.containsKey('label')) {
    var inferred = '';
    final type = c['component'];
    if (type == 'Button') {
      final child =
          c['child'] is String ? surface.components[c['child']] : null;
      if (child?['component'] == 'Text') {
        inferred = text(child!['text']);
      } else if (c['title'] is String) {
        inferred = c['title'] as String;
      }
    } else if (const [
      'TextField',
      'CheckBox',
      'ChoicePicker',
      'Slider',
      'DateTimeInput'
    ].contains(type)) {
      inferred = text(c['label']);
    } else if (type == 'Image') {
      inferred = text(c['description']);
    } else if (type == 'Text') {
      inferred = text(c['text']);
    }
    if (inferred.isNotEmpty) node.label = inferred;
  }
  if (c['component'] == 'CheckBox') {
    node.checked = ctx.safe(() => ctx.boolean(c['value']), false);
  }
  if (bindings.isNotEmpty) node.bindings = bindings;
  return node;
}

/// Semantics of every component of [surface], by component id.
Map<String, A2UIAccessibilityNode> accessibilityTree(
        A2UISurfaceModel surface) =>
    {
      for (final c in surface.components.values)
        '${c['id']}': describeAccessibility(surface, c),
    };
