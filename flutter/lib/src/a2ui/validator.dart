/// Client-side validation of server-to-client messages.
///
/// - [validateMessage] checks one message against the envelope schema and the
///   catalog's component / function tables (types, enums, required and unknown
///   properties, binding path syntax, function-call nesting, `formatString`
///   templates, data nesting).
/// - [A2UIValidator] validates batches statefully and, in strict mode, also
///   checks the component graph each batch leaves behind: a `root` exists,
///   no duplicate ids in one message, no self references, dangling
///   references or cycles, every component is reachable from `root`, and the
///   tree is at most [maxNesting] deep.
///
/// Issues are [A2UIError]s of category `ValidationError` whose `path` is a
/// JSON Pointer into the message (the protocol's `VALIDATION_FAILED` shape).
library;

import 'dart:convert';
import 'dart:math' as math;

import 'catalog.dart';
import 'errors.dart';
import 'expressions.dart';
import 'pointer.dart';

const List<String> supportedVersions = ['v0.9', 'v0.9.1'];
const List<String> messageKinds = [
  'createSurface',
  'updateComponents',
  'updateDataModel',
  'deleteSurface',
];

/// Deepest component tree / data value accepted.
const int maxNesting = 50;

/// Deepest nesting of function calls inside one dynamic value.
const int maxCallDepth = 5;

class _Issues {
  _Issues(this.surfaceId);
  final String? surfaceId;
  final List<A2UIError> list = [];
  void add(String path, String issue, String message) {
    list.add(A2UIError('ValidationError', message,
        surfaceId: surfaceId, path: path.isEmpty ? '/' : path, issue: issue));
  }
}

/// The message kind ([messageKinds]) of [msg], or null.
String? messageKind(Object? msg) {
  if (msg is! Map) return null;
  for (final k in messageKinds) {
    if (msg.containsKey(k)) return k;
  }
  return null;
}

/// The surface a message addresses, when it names one.
String? messageSurfaceId(Object? msg) {
  final kind = messageKind(msg);
  if (kind == null) return null;
  final body = (msg as Map)[kind];
  return body is Map && body['surfaceId'] is String
      ? body['surfaceId'] as String
      : null;
}

String _json(Object? v) {
  try {
    return jsonEncode(v);
  } catch (_) {
    return '$v';
  }
}

/// Schema-level validation of one server-to-client message.
List<A2UIError> validateMessage(Object? msg, A2UICatalog catalog,
    {bool requireVersion = true}) {
  final issues = _Issues(messageSurfaceId(msg));
  if (msg is! Map) {
    issues.add('/', 'type_mismatch', 'A message must be a JSON object');
    return issues.list;
  }
  if (!msg.containsKey('version')) {
    if (requireVersion) {
      issues.add(
          '/version', 'missing_field', 'The "version" field is required');
    }
  } else if (msg['version'] is! String ||
      !supportedVersions.contains(msg['version'])) {
    issues.add('/version', 'invalid_value',
        'Unsupported version ${_json(msg['version'])} (expected v0.9 or v0.9.1)');
  }
  final kinds = messageKinds.where(msg.containsKey).toList();
  if (kinds.length != 1) {
    issues.add('/', kinds.isNotEmpty ? 'invalid_value' : 'missing_field',
        'A message must contain exactly one of ${messageKinds.join(', ')}');
    return issues.list;
  }
  final kind = kinds.first;
  for (final k in msg.keys) {
    if (k != 'version' && k != kind) {
      issues.add('/$k', 'unknown_field', 'Unknown message field "$k"');
    }
  }
  final body = msg[kind];
  final base = '/$kind';
  if (body is! Map) {
    issues.add(base, 'type_mismatch', '"$kind" must be an object');
    return issues.list;
  }
  const allowed = <String, List<String>>{
    'createSurface': ['surfaceId', 'catalogId', 'theme', 'sendDataModel'],
    'updateComponents': ['surfaceId', 'components'],
    'updateDataModel': ['surfaceId', 'path', 'value'],
    'deleteSurface': ['surfaceId'],
  };
  for (final k in body.keys) {
    if (!allowed[kind]!.contains(k)) {
      issues.add('$base/$k', 'unknown_field', 'Unknown field "$k" in $kind');
    }
  }
  _requireString(issues, body, 'surfaceId', base);
  switch (kind) {
    case 'createSurface':
      _requireString(issues, body, 'catalogId', base);
      if (body.containsKey('theme')) {
        _validateTheme(issues, body['theme'], '$base/theme');
      }
      if (body.containsKey('sendDataModel') && body['sendDataModel'] is! bool) {
        issues.add('$base/sendDataModel', 'type_mismatch',
            '"sendDataModel" must be a boolean');
      }
    case 'updateComponents':
      if (!body.containsKey('components')) {
        issues.add(
            '$base/components', 'missing_field', '"components" is required');
      } else if (body['components'] is! List) {
        issues.add(
            '$base/components', 'type_mismatch', '"components" must be a list');
      } else {
        final comps = body['components'] as List;
        if (comps.isEmpty) {
          issues.add('$base/components', 'invalid_value',
              '"components" must not be empty');
        }
        for (var i = 0; i < comps.length; i++) {
          _validateComponent(issues, comps[i], catalog, '$base/components/$i');
        }
      }
    case 'updateDataModel':
      if (body.containsKey('path')) {
        final p = body['path'];
        if (p is! String) {
          issues.add('$base/path', 'type_mismatch', '"path" must be a string');
        } else if (!isValidPointerSyntax(p)) {
          issues.add(
              '$base/path', 'invalid_value', 'Invalid path syntax: "$p"');
        }
      }
      if (body['value'] != null && _depthOf(body['value']) > maxNesting) {
        issues.add('$base/value', 'limit',
            'Global recursion limit exceeded: the value nests deeper than $maxNesting levels');
      }
  }
  return issues.list;
}

void _requireString(_Issues issues, Map body, String key, String base) {
  if (!body.containsKey(key)) {
    issues.add('$base/$key', 'missing_field', '"$key" is required');
  } else if (body[key] is! String) {
    issues.add('$base/$key', 'type_mismatch', '"$key" must be a string');
  }
}

void _validateTheme(_Issues issues, Object? theme, String path) {
  if (theme is! Map) {
    issues.add(path, 'type_mismatch', '"theme" must be an object');
    return;
  }
  final pc = theme['primaryColor'];
  if (theme.containsKey('primaryColor') &&
      (pc is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(pc))) {
    issues.add('$path/primaryColor', 'invalid_value',
        '"primaryColor" must be a hex color like #00BFFF');
  }
  for (final k in ['iconUrl', 'agentDisplayName']) {
    if (theme.containsKey(k) && theme[k] is! String) {
      issues.add('$path/$k', 'type_mismatch', '"$k" must be a string');
    }
  }
}

int _depthOf(Object? value) {
  if (value is List) {
    var max = 0;
    for (final v in value) {
      max = math.max(max, _depthOf(v));
    }
    return max + 1;
  }
  if (value is Map) {
    var max = 0;
    for (final v in value.values) {
      max = math.max(max, _depthOf(v));
    }
    return max + 1;
  }
  return 0;
}

/// Validate one component definition against [catalog].
void _validateComponent(
    _Issues issues, Object? c, A2UICatalog catalog, String base) {
  if (c is! Map) {
    issues.add(base, 'type_mismatch', 'A component must be an object');
    return;
  }
  _requireString(issues, c, 'id', base);
  if (!c.containsKey('component')) {
    issues.add('$base/component', 'missing_field', '"component" is required');
    return;
  }
  if (c['component'] is! String) {
    issues.add(
        '$base/component', 'type_mismatch', '"component" must be a string');
    return;
  }
  final type = c['component'] as String;
  final spec = catalog.components[type];
  if (spec == null) {
    issues.add(
        '$base/component', 'invalid_value', 'Unknown component type "$type"');
    return;
  }
  c.forEach((k, v) {
    if (k == 'id' || k == 'component') return;
    final ps = spec.props[k] ?? commonProps[k];
    if (ps == null) {
      issues.add('$base/$k', 'unknown_field', 'Unknown property "$k" on $type');
      return;
    }
    _checkKind(issues, v, ps.kind, '$base/$k', catalog);
    if (ps.enumValues != null && v is String && !ps.enumValues!.contains(v)) {
      issues.add('$base/$k', 'invalid_value',
          '"$k" must be one of ${ps.enumValues!.join(', ')}');
    }
  });
  for (final r in spec.required) {
    if (!c.containsKey(r)) {
      issues.add('$base/$r', 'missing_field', '$type requires "$r"');
    }
  }
}

bool _isBindingShape(Object? v) =>
    v is Map && v.containsKey('path') && v.length == 1;

void _checkBinding(_Issues issues, Map v, String path) {
  final p = v['path'];
  if (p is! String) {
    issues.add(
        '$path/path', 'type_mismatch', 'A binding "path" must be a string');
  } else if (!isValidPointerSyntax(p)) {
    issues.add('$path/path', 'invalid_value', 'Invalid path syntax: "$p"');
  }
}

void _checkKind(
    _Issues issues, Object? v, String kind, String path, A2UICatalog catalog) {
  void dynamic(bool Function(Object? x) literal, String what) {
    if (literal(v)) return;
    if (_isBindingShape(v)) return _checkBinding(issues, v as Map, path);
    if (v is Map && v.containsKey('call')) {
      return _checkCall(issues, v, path, catalog);
    }
    issues.add(path, 'type_mismatch',
        'Expected $what, a {"path"} binding or a function call');
  }

  switch (kind) {
    case 'any':
      if (_isBindingShape(v)) {
        _checkBinding(issues, v as Map, path);
      } else if (v is Map && v.containsKey('call')) {
        _checkCall(issues, v, path, catalog);
      }
      return;
    case 'DynamicString':
      return dynamic((x) => x is String, 'a string');
    case 'DynamicNumber':
      return dynamic((x) => x is num, 'a number');
    case 'DynamicBoolean':
      return dynamic((x) => x is bool, 'a boolean');
    case 'DynamicStringList':
      return dynamic(
          (x) => x is List && x.every((s) => s is String), 'a list of strings');
    case 'DynamicValue':
      return dynamic(
          (x) => x is String || x is num || x is bool || x is List, 'a value');
    case 'DynamicBooleanList':
      if (v is! List) {
        return issues.add(path, 'type_mismatch', 'Expected a list');
      }
      if (v.length < 2) {
        issues.add(path, 'invalid_value', 'Expected at least two values');
      }
      for (var i = 0; i < v.length; i++) {
        _checkKind(issues, v[i], 'DynamicBoolean', '$path/$i', catalog);
      }
      return;
    case 'ComponentId':
      if (v is! String) {
        issues.add(path, 'type_mismatch', 'Expected a component id (string)');
      }
      return;
    case 'ChildList':
      if (v is List) {
        for (var i = 0; i < v.length; i++) {
          if (v[i] is! String) {
            issues.add('$path/$i', 'type_mismatch',
                'Expected a component id (string)');
          }
        }
      } else if (v is Map) {
        for (final k in v.keys) {
          if (k != 'componentId' && k != 'path') {
            issues.add(
                '$path/$k', 'unknown_field', 'Unknown template field "$k"');
          }
        }
        if (!v.containsKey('componentId')) {
          issues.add('$path/componentId', 'missing_field',
              'A child template requires "componentId"');
        } else if (v['componentId'] is! String) {
          issues.add('$path/componentId', 'type_mismatch',
              '"componentId" must be a string');
        }
        if (!v.containsKey('path')) {
          issues.add('$path/path', 'missing_field',
              'A child template requires "path"');
        } else {
          _checkBinding(issues, v, path);
        }
      } else {
        issues.add(path, 'invalid_value',
            'Expected a list of component ids or a {componentId, path} template');
      }
      return;
    case 'Action':
      if (v is Map && v.length == 1 && v['event'] is Map) {
        final e = v['event'] as Map;
        if (e['name'] is! String) {
          issues.add(
              '$path/event/name',
              e.containsKey('name') ? 'type_mismatch' : 'missing_field',
              'An event requires a "name" string');
        }
        for (final k in e.keys) {
          if (k != 'name' && k != 'context') {
            issues.add(
                '$path/event/$k', 'unknown_field', 'Unknown event field "$k"');
          }
        }
        if (e.containsKey('context')) {
          final ctx = e['context'];
          if (ctx is! Map) {
            issues.add('$path/event/context', 'type_mismatch',
                'An event "context" must be an object');
          } else {
            ctx.forEach((k, x) => _checkKind(
                issues, x, 'any', '$path/event/context/$k', catalog));
          }
        }
      } else if (v is Map && v.length == 1 && v['functionCall'] is Map) {
        _checkCall(
            issues, v['functionCall'] as Map, '$path/functionCall', catalog);
      } else {
        issues.add(path, 'invalid_value',
            'An action must be {"event": {"name", "context"}} or {"functionCall": {...}}');
      }
      return;
    case 'Checks':
      if (v is! List) {
        return issues.add(path, 'type_mismatch', '"checks" must be a list');
      }
      for (var i = 0; i < v.length; i++) {
        final check = v[i];
        final p = '$path/$i';
        if (check is! Map) {
          issues.add(p, 'type_mismatch', 'A check must be an object');
          continue;
        }
        if (check['message'] is! String) {
          issues.add(
              '$p/message',
              check.containsKey('message') ? 'type_mismatch' : 'missing_field',
              'A check requires a "message" string');
        }
        if (check.containsKey('condition')) {
          _checkKind(issues, check['condition'], 'DynamicBoolean',
              '$p/condition', catalog);
        } else if (check['call'] is String) {
          _checkCall(issues,
              {'call': check['call'], 'args': check['args'] ?? {}}, p, catalog);
        } else {
          issues.add('$p/condition', 'missing_field',
              'A check requires a "condition"');
        }
      }
      return;
    case 'Accessibility':
      if (v is! Map) {
        return issues.add(
            path, 'type_mismatch', '"accessibility" must be an object');
      }
      for (final k in ['label', 'description']) {
        if (v.containsKey(k)) {
          _checkKind(issues, v[k], 'DynamicString', '$path/$k', catalog);
        }
      }
      return;
    case 'IconName':
      if (v is String) {
        if (!iconNames.contains(v)) {
          issues.add(path, 'invalid_value', 'Unknown icon name "$v"');
        }
      } else if (v is Map && v.containsKey('svgPath')) {
        if (v['svgPath'] is! String || v.length != 1) {
          issues.add(path, 'invalid_value', 'An icon must be {"svgPath": "…"}');
        }
      } else if (_isBindingShape(v)) {
        _checkBinding(issues, v as Map, path);
      } else {
        issues.add(path, 'type_mismatch',
            'Expected an icon name, {"svgPath"} or a binding');
      }
      return;
    case 'TabList':
      if (v is! List || v.isEmpty) {
        return issues.add(
            path, 'invalid_value', '"tabs" must be a non-empty list');
      }
      for (var i = 0; i < v.length; i++) {
        final t = v[i];
        final p = '$path/$i';
        if (t is! Map) {
          issues.add(p, 'type_mismatch', 'A tab must be an object');
          continue;
        }
        if (!t.containsKey('title')) {
          issues.add('$p/title', 'missing_field', 'A tab requires "title"');
        } else {
          _checkKind(issues, t['title'], 'DynamicString', '$p/title', catalog);
        }
        if (t['child'] is! String) {
          issues.add(
              '$p/child',
              t.containsKey('child') ? 'type_mismatch' : 'missing_field',
              'A tab requires a "child" id');
        }
        for (final k in t.keys) {
          if (k != 'title' && k != 'child') {
            issues.add('$p/$k', 'unknown_field', 'Unknown tab field "$k"');
          }
        }
      }
      return;
    case 'OptionList':
      if (v is! List) {
        return issues.add(path, 'type_mismatch', '"options" must be a list');
      }
      for (var i = 0; i < v.length; i++) {
        final o = v[i];
        final p = '$path/$i';
        if (o is! Map) {
          issues.add(p, 'type_mismatch', 'An option must be an object');
          continue;
        }
        if (!o.containsKey('label')) {
          issues.add('$p/label', 'missing_field', 'An option requires "label"');
        } else {
          _checkKind(issues, o['label'], 'DynamicString', '$p/label', catalog);
        }
        if (o['value'] is! String) {
          issues.add(
              '$p/value',
              o.containsKey('value') ? 'type_mismatch' : 'missing_field',
              'An option requires a "value" string');
        }
      }
      return;
    case 'string':
      if (v is! String) issues.add(path, 'type_mismatch', 'Expected a string');
      return;
    case 'number':
      if (v is! num) issues.add(path, 'type_mismatch', 'Expected a number');
      return;
    case 'boolean':
      if (v is! bool) issues.add(path, 'type_mismatch', 'Expected a boolean');
      return;
  }
}

int _callDepth(Object? v) {
  if (v is List) {
    var max = 0;
    for (final x in v) {
      max = math.max(max, _callDepth(x));
    }
    return max;
  }
  if (v is! Map) return 0;
  var inner = 0;
  final args = v['args'];
  if (args is Map) {
    for (final x in args.values) {
      inner = math.max(inner, _callDepth(x));
    }
  }
  if (v['call'] is String) return inner + 1;
  var max = 0;
  for (final x in v.values) {
    max = math.max(max, _callDepth(x));
  }
  return max;
}

void _checkCall(_Issues issues, Map v, String path, A2UICatalog catalog) {
  if (_callDepth(v) > maxCallDepth) {
    issues.add(path, 'limit',
        'functionCall depth exceeds the maximum of $maxCallDepth');
    return;
  }
  final name = v['call'];
  if (name is! String) {
    return issues.add(
        '$path/call', 'type_mismatch', '"call" must be a function name');
  }
  for (final k in v.keys) {
    if (k != 'call' && k != 'args' && k != 'returnType') {
      issues.add(
          '$path/$k', 'unknown_field', 'Unknown function-call field "$k"');
    }
  }
  final spec = catalog.functions[name];
  if (spec == null) {
    return issues.add(
        '$path/call', 'invalid_value', 'Unknown function "$name"');
  }
  if (v.containsKey('returnType') &&
      !['string', 'number', 'boolean', 'array', 'object', 'any', 'void']
          .contains(v['returnType'])) {
    issues.add('$path/returnType', 'invalid_value',
        'Invalid returnType ${_json(v['returnType'])}');
  }
  final args = v.containsKey('args') ? v['args'] : <String, dynamic>{};
  if (args is! Map) {
    return issues.add(
        '$path/args', 'type_mismatch', '"args" must be an object');
  }
  args.forEach((k, x) {
    final kind = spec.args[k];
    if (kind == null) {
      issues.add(
          '$path/args/$k', 'unknown_field', '$name() has no argument "$k"');
      return;
    }
    _checkKind(issues, x, kind, '$path/args/$k', catalog);
  });
  for (final r in spec.required) {
    if (!args.containsKey(r)) {
      issues.add('$path/args/$r', 'missing_field', '$name() requires "$r"');
    }
  }
  if (spec.anyOf != null &&
      !spec.anyOf!.any((group) => group.every(args.containsKey))) {
    issues.add('$path/args', 'missing_field',
        '$name() requires one of ${spec.anyOf!.map((g) => g.join('+')).join(' or ')}');
  }
  if (name == 'formatString' && args['value'] is String) {
    try {
      parseTemplate(args['value'] as String);
    } on A2UIError catch (e) {
      issues.add('$path/args/value', 'invalid_value', e.message);
    }
  }
}

class _SurfaceShape {
  _SurfaceShape([Map<String, Map>? components]) : components = components ?? {};
  final Map<String, Map> components;
}

/// Stateful batch validation (the conformance `validate` action): each batch
/// is checked against the state the previous accepted batches left; a batch
/// with issues changes nothing.
class A2UIValidator {
  A2UIValidator(this.catalog,
      {this.strict = false, this.requireVersion = true});

  final A2UICatalog catalog;
  final bool strict;
  final bool requireVersion;
  Map<String, _SurfaceShape> _surfaces = {};

  List<A2UIError> validateBatch(List messages) {
    final issues = <A2UIError>[];
    for (var i = 0; i < messages.length; i++) {
      for (final e in validateMessage(messages[i], catalog,
          requireVersion: requireVersion)) {
        issues.add(A2UIError('ValidationError', e.message,
            surfaceId: e.surfaceId,
            issue: e.issue,
            path: '/$i${e.path == '/' ? '' : e.path}'));
      }
    }
    if (issues.isNotEmpty) return issues;
    final next = <String, _SurfaceShape>{
      for (final e in _surfaces.entries)
        e.key: _SurfaceShape(Map.of(e.value.components)),
    };
    final touched = <String>{};
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i] as Map;
      final kind = messageKind(m)!;
      final body = m[kind] as Map;
      final sid = '${body['surfaceId']}';
      void fail(String message, [String? path]) =>
          issues.add(A2UIError('ValidationError', message,
              surfaceId: sid, path: path ?? '/$i/$kind', issue: 'topology'));
      if (kind == 'createSurface') {
        if (next.containsKey(sid)) {
          fail('Surface "$sid" already exists');
        } else {
          next[sid] = _SurfaceShape();
        }
      } else if (kind == 'deleteSurface') {
        next.remove(sid);
      } else if (kind == 'updateComponents') {
        final s = next[sid];
        if (s == null) {
          fail('Surface "$sid" has not been created');
          continue;
        }
        final seen = <String>{};
        final comps = body['components'] as List;
        for (var j = 0; j < comps.length; j++) {
          final c = comps[j] as Map;
          final id = c['id'] as String;
          if (strict && seen.contains(id)) {
            fail('Duplicate component ID "$id" in one updateComponents message',
                '/$i/updateComponents/components/$j/id');
          }
          seen.add(id);
          s.components[id] = c;
        }
        touched.add(sid);
      } else if (kind == 'updateDataModel') {
        if (!next.containsKey(sid)) fail('Surface "$sid" has not been created');
      }
    }
    if (strict) {
      for (final sid in touched) {
        final s = next[sid];
        if (s != null) issues.addAll(_topology(sid, s));
      }
    }
    if (issues.isEmpty) _surfaces = next;
    return issues;
  }

  /// Graph checks for one surface's component map.
  List<A2UIError> _topology(String surfaceId, _SurfaceShape surface) {
    final out = <A2UIError>[];
    void fail(String message) => out.add(A2UIError('ValidationError', message,
        surfaceId: surfaceId, path: '/', issue: 'topology'));
    final comps = surface.components;
    if (comps.isEmpty) return out;
    if (!comps.containsKey('root')) {
      fail(
          'Missing root component: surface "$surfaceId" has no component with id "root"');
      return out;
    }
    List<ChildReference> refs(Map c) =>
        childReferences(Map<String, dynamic>.from(c), catalog);
    comps.forEach((id, c) {
      for (final ref in refs(c)) {
        if (ref.id == id) {
          fail(
              'Self-reference detected: component "$id" references itself (${ref.prop})');
        } else if (!comps.containsKey(ref.id)) {
          fail(
              "Dangling reference: component \"$id\" references non-existent component '${ref.id}' (${ref.prop})");
        }
      }
    });
    if (out.isNotEmpty) return out;
    final reached = <String>{};
    final stack = <String>[];
    List<String>? cycle;
    var tooDeep = false;
    void visit(String id) {
      if (cycle != null || tooDeep) return;
      final at = stack.indexOf(id);
      if (at >= 0) {
        cycle = [...stack.sublist(at), id];
        return;
      }
      if (stack.length + 1 > maxNesting) {
        tooDeep = true;
        return;
      }
      reached.add(id);
      stack.add(id);
      for (final ref in refs(comps[id]!)) {
        if (comps.containsKey(ref.id)) visit(ref.id);
      }
      stack.removeLast();
    }

    visit('root');
    if (cycle != null) {
      fail(
          'Circular reference detected. Circular component reference: ${cycle!.join(' -> ')}');
    } else if (tooDeep) {
      fail(
          'Global recursion limit exceeded: the component tree is deeper than $maxNesting levels');
    } else {
      for (final id in comps.keys) {
        if (!reached.contains(id)) {
          fail("Component '$id' is not reachable from 'root'");
        }
      }
    }
    return out;
  }
}
