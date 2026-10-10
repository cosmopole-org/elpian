// The vendored A2UI conformance suites (a2ui/conformance/json) run against the
// Flutter renderer — the same cases, translations and skips as the web
// reference implementation's `native/web/test/a2ui/conformance.test.mjs`.
//
// Cases written for protocol v1.0 (inline `createSurface.dataModel/components`,
// `@call` / `@path`, `title`, `checked`, `selectedIndex`, `Container`) are
// translated to their v0.9.1 equivalents first ([fromV1]). Skipped:
// node_resolution (its fixtures are not vendored and it asserts web_core's
// reactive-node model) and cases with inline custom catalogs.
import 'dart:convert';
import 'dart:io';

import 'package:elpian_ui/src/a2ui/a2ui.dart';
import 'package:flutter_test/flutter_test.dart';

List<Map<String, dynamic>> conformance(String name) {
  final file = File('../a2ui/conformance/json/$name.json');
  return (jsonDecode(file.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
}

void expectA2UIError(void Function() fn, Map expected, String where) {
  Object? error;
  try {
    fn();
  } catch (e) {
    error = e;
  }
  expect(error, isA<A2UIError>(),
      reason: '$where: expected ${expected['category']}');
  final e = error as A2UIError;
  if (expected['category'] != null) {
    expect(e.category, expected['category'], reason: where);
  }
  if (expected['message'] != null) {
    expect(e.message, contains(expected['message']), reason: where);
  }
}

Object? renameKeys(Object? v) {
  if (v is List) return v.map(renameKeys).toList();
  if (v is Map) {
    return {
      for (final e in v.entries)
        (e.key == '@call'
            ? 'call'
            : e.key == '@path'
                ? 'path'
                : e.key as String): renameKeys(e.value),
    };
  }
  return v;
}

List<Map<String, dynamic>> fromV1(Iterable messages) {
  final out = <Map<String, dynamic>>[];
  for (final raw in messages) {
    final m = Map<String, dynamic>.from(renameKeys(raw) as Map);
    if (m['createSurface'] is Map) {
      final cs = Map<String, dynamic>.from(m['createSurface'] as Map);
      final hasData = cs.containsKey('dataModel');
      final dataModel = cs.remove('dataModel');
      final components = cs.remove('components');
      if (cs['catalogId'] == 'basic') cs['catalogId'] = basicCatalogId;
      out.add({'version': 'v0.9.1', 'createSurface': cs});
      if (hasData) {
        out.add({
          'version': 'v0.9.1',
          'updateDataModel': {
            'surfaceId': cs['surfaceId'],
            'path': '/',
            'value': dataModel
          }
        });
      }
      if (components != null) {
        out.add({
          'version': 'v0.9.1',
          'updateComponents': {
            'surfaceId': cs['surfaceId'],
            'components': components
          }
        });
      }
    } else {
      m.remove('version');
      out.add({'version': 'v0.9.1', ...m});
    }
  }
  return out;
}

List payloads(Map c) =>
    [for (final s in c['steps'] as List) ...((s as Map)['payload'] as List)];

String dotted(String? path) =>
    'messages${(path ?? '/').split('/').where((s) => s.isNotEmpty).map((s) => '.$s').join()}';

void checkExpected(List<A2UIError> issues, Object expected, String where) {
  expect(issues, isNotEmpty, reason: '$where: expected an error');
  final messages = issues.map((e) => e.message).join(' | ');
  if (expected is String) {
    expect(issues.any((e) => e.message.contains(expected)), isTrue,
        reason: '$where: $messages should mention "$expected"');
    return;
  }
  final exp = expected as Map;
  if (exp['category'] != null) {
    expect(issues.every((e) => e.category == exp['category']), isTrue,
        reason: where);
  }
  if (exp['message'] != null) {
    expect(
        issues.any((e) => e.message.contains(exp['message'] as String)), isTrue,
        reason: '$where: $messages');
  }
  for (final d in (exp['details'] as List? ?? const [])) {
    expect(
        issues.any((e) => dotted(e.path) == d['path'] && e.issue == d['code']),
        isTrue,
        reason:
            '$where: no issue at ${d['path']} (${d['code']}); got ${issues.map((e) => '${dotted(e.path)} ${e.issue}').join(', ')}');
  }
}

List<Map<String, dynamic>> a11yComponents(Map surface) {
  final comps = <Map<String, dynamic>>[];
  void conv(String id, Map c) {
    final out = <String, dynamic>{
      'id': id,
      ...Map<String, dynamic>.from(renameKeys(c) as Map)
    };
    out.remove('components');
    if (out['component'] == 'Container') {
      out['component'] = 'Column';
      out['children'] = out['child'] != null ? [out['child']] : [];
      out.remove('child');
    }
    if (out['component'] == 'Button' && out['title'] is String) {
      comps.add(
          {'id': '${id}__label', 'component': 'Text', 'text': out['title']});
      out['child'] = '${id}__label';
      out['action'] = {
        'event': {'name': 'press'}
      };
      out.remove('title');
    }
    if (out['component'] == 'CheckBox' && out.containsKey('checked')) {
      out['value'] = out.remove('checked');
    }
    if (out['component'] == 'ChoicePicker' &&
        out.containsKey('selectedIndex')) {
      out['value'] = [
        (out['options'] as List)[out['selectedIndex'] as int]['value']
      ];
      out.remove('selectedIndex');
    }
    comps.add(out);
  }

  conv(surface['id'] as String, surface);
  (surface['components'] as Map? ?? const {})
      .forEach((id, c) => conv(id as String, c as Map));
  return comps;
}

void main() {
  test('conformance: data_model', () {
    for (final c in conformance('data_model')) {
      final model = DataModel(c['initial'] ?? <String, dynamic>{});
      final notified = <String>[];
      for (final path in (c['watch'] as List? ?? const [])) {
        model.watch(path as String, (_, __) => notified.add(path));
      }
      for (final step in (c['steps'] as List).cast<Map>()) {
        notified.clear();
        final where = '${c['name']} ${jsonEncode(step)}';
        final path = step['path'] as String? ?? '/';
        if (step['expect_error'] != null) {
          expectA2UIError(() {
            if (step['op'] == 'get') {
              model.get(path);
            } else if (step['op'] == 'delete') {
              model.delete(path);
            } else {
              model.set(path, step['value']);
            }
          }, step['expect_error'] as Map, where);
          continue;
        }
        switch (step['op']) {
          case 'get':
            final v = model.get(path);
            if (step.containsKey('expect')) {
              expect(v, step['expect'], reason: where);
            }
            if (step['expect_absent'] == true) expect(v, isNull, reason: where);
            if (step['expect_type'] == 'list') {
              expect(v, isA<List>(), reason: where);
            }
            if (step['expect_type'] == 'object') {
              expect(v, isA<Map>(), reason: where);
            }
          case 'set':
            model.set(path, step['value']);
          case 'delete':
            model.delete(path);
          case 'dispose':
            model.dispose();
          default:
            fail('unknown op ${step['op']}');
        }
        if (step['expect_notified'] != null) {
          expect([...notified]..sort(),
              [...(step['expect_notified'] as List).cast<String>()]..sort(),
              reason: where);
        }
        (step['expect_values'] as Map? ?? const {}).forEach((p, v) {
          expect(model.get(p as String), v, reason: where);
        });
      }
    }
  });

  test('conformance: data_context', () {
    for (final c in conformance('data_context')) {
      expect(c['action'], 'resolve_path');
      final args = c['args'] as Map;
      expect(
          resolvePath(args['path'] as String, args['contextPath'] as String?),
          c['expect'],
          reason: c['name'] as String);
    }
  });

  test('conformance: expressions', () {
    for (final c in conformance('expressions')) {
      final name = c['name'] as String;
      if (c['action'] == 'parse_expression_template') {
        if (c['expect_error'] != null) {
          expectA2UIError(() => parseTemplate(c['input'] as String),
              c['expect_error'] as Map, name);
        } else {
          expect(parseTemplate(c['input'] as String), c['expect'],
              reason: name);
        }
      } else if (c['action'] == 'validate') {
        final messages = fromV1(payloads(c));
        final expected = (c['steps'] as List).cast<Map>().firstWhere(
            (s) => s['expectError'] != null,
            orElse: () => const {})['expectError'] as Map?;
        if (expected != null) {
          final issues = [
            for (final m in messages) ...validateMessage(m, basicCatalog)
          ];
          expect(
              issues.any((e) =>
                  e.category == expected['category'] &&
                  e.message.contains(expected['message'] as String)),
              isTrue,
              reason: '$name: ${issues.map((e) => e.message)}');
        } else {
          final p = A2UIProcessor(validation: ValidationMode.strict);
          expect(p.processAll(messages).map((e) => e.message), isEmpty,
              reason: name);
          final s = p.surfaces.first;
          final text = s.context().string(s.components['root']!['text']);
          expect(text,
              c['expect']['surfaces']['main']['components']['root']['text'],
              reason: name);
        }
      } else {
        fail('unexpected action ${c['action']}');
      }
    }
  });

  test('conformance: data_deletion', () {
    for (final c in conformance('data_deletion')) {
      final p = A2UIProcessor(validation: ValidationMode.strict);
      expect(p.processAll(fromV1(payloads(c))).map((e) => e.message), isEmpty,
          reason: c['name'] as String);
      (c['expect']['surfaces'] as Map).forEach((sid, exp) {
        expect(p.dataModel(sid as String), exp['dataModel'],
            reason: c['name'] as String);
      });
    }
  });

  test('conformance: actions', () {
    for (final c in conformance('actions')) {
      final p = A2UIProcessor();
      final sid = c['surfaceId'] as String? ?? 'main';
      p.process({
        'version': 'v0.9.1',
        'createSurface': {'surfaceId': sid, 'catalogId': basicCatalogId}
      });
      if (c['dataModel'] != null) {
        p.process({
          'version': 'v0.9.1',
          'updateDataModel': {
            'surfaceId': sid,
            'path': '/',
            'value': c['dataModel']
          }
        });
      }
      final emitted = <A2UIClientAction>[];
      p.on((e) {
        if (e.type == 'action') emitted.add(e.action!);
      });
      final action = p.dispatchAction(sid, 'btn', c['actionPayload'],
          scope: c['scope'] as String? ?? '/');
      final name = c['name'] as String;
      expect(action, isNotNull, reason: name);
      expect(emitted, hasLength(1));
      expect(action!.surfaceId, sid);
      expect(action.sourceComponentId, 'btn');
      expect(DateTime.tryParse(action.timestamp), isNotNull);
      final exp = c['expectDispatched'] as Map;
      expect(action.name, exp['name'], reason: name);
      expect(action.context, exp['context'] ?? {}, reason: name);
      if (exp['userMessage'] != null) {
        expect(action.userMessage, exp['userMessage']);
      }
    }
  });

  test('conformance: accessibility', () {
    for (final c in conformance('accessibility')) {
      final p = A2UIProcessor(validation: ValidationMode.off);
      p.process({
        'version': 'v0.9.1',
        'createSurface': {'surfaceId': 's', 'catalogId': basicCatalogId}
      });
      p.process({
        'version': 'v0.9.1',
        'updateComponents': {
          'surfaceId': 's',
          'components': a11yComponents(c['surface'] as Map)
        }
      });
      final s = p.surface('s')!;
      (c['assertions']['accessibilityTree'] as Map).forEach((id, exp) {
        final node = describeAccessibility(s, s.components[id]!);
        (exp as Map).forEach((k, v) {
          final where = '${c['name']} $id.$k';
          if (v is Map && v.containsKey('path')) {
            expect(node.bindings?[k], v['path'], reason: where);
          } else {
            expect(node[k as String], v, reason: where);
          }
        });
      });
    }
  });

  test('conformance: validator_v0_9', () {
    for (final c in conformance('validator_v0_9')) {
      if (c['catalog'] != null) continue; // inline custom catalog
      final v = A2UIValidator(basicCatalog,
          strict: c['strictMode'] == true, requireVersion: true);
      final steps = (c['steps'] as List).cast<Map>();
      for (var i = 0; i < steps.length; i++) {
        final issues = v.validateBatch(steps[i]['messages'] as List);
        final where = '${c['name']} step $i';
        if (steps[i]['expectError'] != null) {
          checkExpected(issues, steps[i]['expectError'] as Object, where);
        } else {
          expect(issues.map((e) => e.message), isEmpty, reason: where);
        }
      }
      expect(c['expectError'], isNull);
    }
  });

  test('conformance: composition_constraints', () {
    for (final c in conformance('composition_constraints')) {
      if (c['catalog'] is Map &&
          (c['catalog'] as Map)['catalogSchema'] != null) {
        continue; // v1.0 allowedParents/allowedChildren on a custom catalog
      }
      final name = c['name'] as String;
      final p = A2UIProcessor(validation: ValidationMode.strict);
      expect(p.processAll(fromV1(payloads(c))).map((e) => e.message), isEmpty,
          reason: name);
      final v = A2UIValidator(basicCatalog, strict: true);
      expect(
          v.validateBatch(fromV1(payloads(c))).map((e) => e.message), isEmpty,
          reason: name);
      (c['expect']['surfaces'] as Map).forEach((sid, exp) {
        (exp['components'] as Map).forEach((id, comp) {
          final actual = Map.of(p.surface(sid as String)!.components[id]!)
            ..remove('id');
          expect(actual, Map.of(comp as Map)..remove('id'), reason: name);
        });
      });
    }
  });
}
