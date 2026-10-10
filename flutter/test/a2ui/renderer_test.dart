// The basic catalog examples through processor + lowering + the Elpian engine,
// the catalog table against catalog.json, functions, two-way binding, Tabs /
// Modal state, the transport's chunk-split NDJSON decoding, conversations, the
// A2UISurface widget and the agent host APIs — the Flutter counterpart of
// native/web/test/a2ui/renderer.test.mjs.
import 'dart:convert';
import 'dart:io';

import 'package:elpian_ui/elpian_ui.dart';
import 'package:elpian_ui/src/widgets/svg_path.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> readJson(String path) =>
    jsonDecode(File('../a2ui/$path').readAsStringSync())
        as Map<String, dynamic>;

List<({String file, Map<String, dynamic> json})> examples() {
  final dir = Directory('../a2ui/spec/catalogs/basic/examples');
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final f in files)
      (
        file: f.uri.pathSegments.last,
        json: jsonDecode(f.readAsStringSync()) as Map<String, dynamic>
      )
  ];
}

LoweringHooks hooks(A2UIProcessor p, List<List<Object?>> log) => LoweringHooks(
      write: (sid, path, value) {
        log.add(['write', path, value]);
        p.setData(sid, path, value);
      },
      action: (sid, id, action, scope) =>
          log.add(['action', p.dispatchAction(sid, id, action, scope: scope)]),
      invalidate: () => log.add(['invalidate']),
      error: (e) => log.add(['error', e.message]),
    );

void walk(Map<String, dynamic> node, void Function(Map<String, dynamic>) fn) {
  fn(node);
  for (final c in (node['children'] as List? ?? const [])) {
    walk(c as Map<String, dynamic>, fn);
  }
}

Map<String, dynamic>? findNode(
    Map<String, dynamic> node, bool Function(Map<String, dynamic>) pred) {
  Map<String, dynamic>? hit;
  walk(node, (n) {
    if (hit == null && pred(n)) hit = n;
  });
  return hit;
}

ElpianInputEvent inputEvent(Object? value) => ElpianInputEvent(
    type: 'input', eventType: ElpianEventType.input, value: value);

ElpianEvent clickEvent() =>
    ElpianEvent(type: 'click', eventType: ElpianEventType.click);

/// A scripted [AgentFetchStream]: records requests, replays chunks.
class FakeAgent {
  final List<({String url, Map<String, dynamic> body})> requests = [];
  List<String> chunks = const [];
  String? error;

  void Function() call(
    AgentEndpoint endpoint,
    String body, {
    required void Function(String chunk) onChunk,
    required void Function() onDone,
    required void Function(String message) onError,
  }) {
    requests.add(
        (url: endpoint.url, body: jsonDecode(body) as Map<String, dynamic>));
    final chunks = this.chunks;
    final error = this.error;
    var cancelled = false;
    () async {
      for (final c in chunks) {
        await Future<void>.delayed(Duration.zero);
        if (cancelled) return;
        onChunk(c);
      }
      await Future<void>.delayed(Duration.zero);
      if (cancelled) return;
      if (error != null) {
        onError(error);
      } else {
        onDone();
      }
    }();
    return () => cancelled = true;
  }
}

Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  test('the basic catalog table matches catalog.json', () {
    final json = readJson('spec/catalogs/basic/catalog.json');
    expect(basicCatalog.id, json['catalogId']);
    final components = json['components'] as Map<String, dynamic>;
    expect(basicComponents.keys.toSet(), components.keys.toSet());
    components.forEach((name, schema) {
      final allOf = (schema['allOf'] as List).cast<Map>();
      final own = allOf.firstWhere(
          (a) => (a['properties'] as Map?)?.containsKey('component') == true);
      final props = (own['properties'] as Map)
          .keys
          .where((p) => p != 'component')
          .toSet();
      final checkable =
          allOf.any((a) => '${a[r'$ref'] ?? ''}'.endsWith('Checkable'));
      final ours =
          basicComponents[name]!.props.keys.where((p) => p != 'checks');
      expect(ours.toSet(), props, reason: name);
      expect(basicComponents[name]!.props.containsKey('checks'), checkable,
          reason: '$name checks');
      expect(basicComponents[name]!.required.toSet(),
          (own['required'] as List).where((r) => r != 'component').toSet(),
          reason: '$name required');
      for (final p in props) {
        final e = (own['properties'] as Map)[p]['enum'];
        if (e != null) {
          expect(basicComponents[name]!.props[p]!.enumValues!.toSet(),
              (e as List).toSet(),
              reason: '$name.$p');
        }
      }
    });
    expect(commonProps.keys.toSet(),
        {'accessibility', 'component', 'id', 'weight'});
    final functions = json['functions'] as Map<String, dynamic>;
    expect(basicFunctionSpecs.keys.toSet(), functions.keys.toSet());
    functions.forEach((name, schema) {
      expect(basicFunctionSpecs[name]!.args.keys.toSet(),
          (schema['properties']['args']['properties'] as Map).keys.toSet(),
          reason: name);
      expect(basicFunctionSpecs[name]!.returnType,
          schema['properties']['returnType']['const'],
          reason: name);
    });
    final iconEnum = components['Icon']['allOf'][2]['properties']['name']
        ['oneOf'][0]['enum'];
    expect(iconNames.toSet(), (iconEnum as List).toSet());
  });

  test('every catalog icon maps to a Material icon', () {
    for (final name in iconNames) {
      expect(ElpianIcon.hasIcon(materialIconName(name)), isTrue,
          reason: '$name → ${materialIconName(name)}');
    }
  });

  final all = examples();

  test('there are 43 basic catalog examples', () => expect(all, hasLength(43)));

  for (final example in all) {
    testWidgets('example ${example.file}: processes, lowers, renders',
        (tester) async {
      final messages = example.json['messages'] as List;
      final processor = A2UIProcessor(validation: ValidationMode.strict);
      expect(
          processor.processAll(messages).map((e) => '${e.path}: ${e.message}'),
          isEmpty);
      final v = A2UIValidator(basicCatalog, strict: true);
      final topology = v.validateBatch(messages).map((e) => e.message).toList();
      // Incremental examples replace placeholders, leaving them unreachable.
      final orphans = topology
          .map((m) =>
              RegExp(r"^Component '(.+)' is not reachable").firstMatch(m)?[1])
          .whereType<String>()
          .toSet();
      expect(topology.where((m) => !m.contains('is not reachable')), isEmpty);
      expect(processor.surfaces, isNotEmpty);
      for (final surface in processor.surfaces) {
        expect(surface.isReady, isTrue);
        final log = <List<Object?>>[];
        final result = lowerSurface(
            surface,
            LoweringOptions(
                hooks: hooks(processor, log),
                state: A2UIUiState(),
                expandAll: true));
        expect(result.placeholders, isEmpty);
        expect(log.where((l) => l[0] == 'error'), isEmpty);
        final lowered = result.lowered.map((m) => m.split('@').first).toSet();
        for (final id in surface.components.keys) {
          if (lowered.contains(id) || orphans.contains(id)) continue;
          final asTemplate = surface.components.values.any((c) =>
              c['children'] is Map && c['children']['componentId'] == id);
          expect(asTemplate, isTrue, reason: '$id was not lowered');
        }
        final engine = ElpianEngine(services: ElpianServices(appId: 'test'));
        final types = <String>{};
        walk(result.node, (n) => types.add(n['type'] as String));
        for (final t in types) {
          expect(engine.services.registry.has(t), isTrue,
              reason: 'lowered to unregistered widget $t');
        }
        await tester
            .pumpWidget(host(engine.render(ElpianNode.fromJson(result.node))));
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Unknown widget'), findsNothing);
        expect(tester.getSize(find.byType(SingleChildScrollView)).height,
            greaterThan(0));
        await tester.pumpWidget(const SizedBox());
      }
    });
  }

  test('two-way binding, checks and actions on a form', () {
    final p = A2UIProcessor();
    p.processAll([
      {
        'version': 'v0.9.1',
        'createSurface': {
          'surfaceId': 'f',
          'catalogId': basicCatalogId,
          'theme': {'primaryColor': '#00BFFF'}
        }
      },
      {
        'version': 'v0.9.1',
        'updateComponents': {
          'surfaceId': 'f',
          'components': [
            {
              'id': 'root',
              'component': 'Column',
              'children': ['name', 'echo', 'go']
            },
            {
              'id': 'name',
              'component': 'TextField',
              'label': 'Name',
              'value': {'path': '/form/name'},
              'checks': [
                {
                  'condition': {
                    'call': 'required',
                    'args': {
                      'value': {'path': '/form/name'}
                    }
                  },
                  'message': 'Required'
                }
              ]
            },
            {
              'id': 'echo',
              'component': 'Text',
              'text': {
                'call': 'formatString',
                'args': {'value': r'Hi ${/form/name}'},
                'returnType': 'string'
              }
            },
            {'id': 'go_label', 'component': 'Text', 'text': 'Go'},
            {
              'id': 'go',
              'component': 'Button',
              'child': 'go_label',
              'variant': 'primary',
              'action': {
                'event': {
                  'name': 'submit',
                  'context': {
                    'name': {'path': '/form/name'}
                  }
                }
              },
              'checks': [
                {
                  'condition': {
                    'call': 'required',
                    'args': {
                      'value': {'path': '/form/name'}
                    }
                  },
                  'message': 'Required'
                }
              ]
            },
          ]
        }
      },
    ]);
    final log = <List<Object?>>[];
    final state = A2UIUiState();
    Map<String, dynamic> lower() => lowerSurface(p.surface('f')!,
            LoweringOptions(hooks: hooks(p, log), state: state))
        .node;
    var tree = lower();
    final button = findNode(tree, (n) => n['type'] == 'Button')!;
    expect(button['props']['disabled'], isTrue);
    expect(button['props']['style']['backgroundColor'], '#00BFFF');
    final input = findNode(tree, (n) => n['type'] == 'TextField')!;
    (input['events']['input'] as Function)(inputEvent('Ada'));
    expect(p.dataModel('f'), {
      'form': {'name': 'Ada'}
    });
    tree = lower();
    expect(findNode(tree, (n) => n['type'] == 'TextField')!['props']['value'],
        'Ada');
    expect(
        findNode(
            tree,
            (n) =>
                n['type'] == 'Text' &&
                '${n['props']['text']}'.startsWith('Hi'))!['props']['text'],
        'Hi Ada');
    final enabled = findNode(tree, (n) => n['type'] == 'Button')!;
    expect(enabled['props']['disabled'], isFalse);
    (enabled['events']['click'] as Function)(clickEvent());
    final action =
        log.firstWhere((l) => l[0] == 'action')[1] as A2UIClientAction;
    expect(action.name, 'submit');
    expect(action.surfaceId, 'f');
    expect(action.sourceComponentId, 'go');
    expect(action.context, {'name': 'Ada'});
    p.process({
      'version': 'v0.9.1',
      'updateDataModel': {
        'surfaceId': 'f',
        'path': '/form/name',
        'value': 'Grace'
      }
    });
    expect(
        findNode(lower(), (n) => n['type'] == 'TextField')!['props']['value'],
        'Grace');
  });

  testWidgets('a lowered TextField writes through the rendered widget',
      (tester) async {
    final p = A2UIProcessor();
    p.processAll([
      {
        'version': 'v0.9.1',
        'createSurface': {'surfaceId': 'f', 'catalogId': basicCatalogId}
      },
      {
        'version': 'v0.9.1',
        'updateComponents': {
          'surfaceId': 'f',
          'components': [
            {
              'id': 'root',
              'component': 'TextField',
              'label': 'Name',
              'value': {'path': '/name'}
            },
          ]
        }
      },
    ]);
    final engine = ElpianEngine(services: ElpianServices(appId: 'tf'));
    final node = lowerSurface(p.surface('f')!,
            LoweringOptions(hooks: hooks(p, []), state: A2UIUiState()))
        .node;
    await tester.pumpWidget(host(engine.render(ElpianNode.fromJson(node))));
    await tester.enterText(find.byType(TextField), 'Ada');
    expect(p.dataModel('f'), {'name': 'Ada'});
  });

  test('Tabs and Modal keep UI state', () {
    final p = A2UIProcessor();
    p.processAll(
        readJson('spec/catalogs/basic/examples/36_modal.json')['messages']
            as List);
    final s = p.surfaces.first;
    final state = A2UIUiState();
    final log = <List<Object?>>[];
    LoweringResult lower() =>
        lowerSurface(s, LoweringOptions(hooks: hooks(p, log), state: state));
    final tree = lower();
    expect(tree.node['type'], 'Column');
    final trigger = findNode(tree.node, (n) => n['type'] == 'Button')!;
    (trigger['events']['click'] as Function)(clickEvent());
    final open = lower();
    expect(open.node['type'], 'ConstrainedBox');
    final barrier =
        findNode(open.node, (n) => '${n['key'] ?? ''}'.endsWith('/barrier'))!;
    (barrier['events']['click'] as Function)(clickEvent());
    expect(lower().node['type'], 'Column');
  });

  test('functions: formatting and validation', () {
    final p = A2UIProcessor();
    p.process({
      'version': 'v0.9.1',
      'createSurface': {'surfaceId': 's', 'catalogId': basicCatalogId}
    });
    final ctx = p.surface('s')!.context();
    Object? call(String name, Map<String, dynamic> args) =>
        ctx.call(name, args);
    expect(call('formatNumber', {'value': 1234.5, 'decimals': 2}), '1,234.50');
    expect(
        call('formatNumber',
            {'value': 1234.5, 'decimals': 0, 'grouping': false}),
        '1235');
    expect(
        call('formatCurrency', {'value': 49.99, 'currency': 'EUR'}), '€49.99');
    expect(call('formatCurrency', {'value': -1234.5, 'currency': 'USD'}),
        r'-$1,234.50');
    expect(
        formatDatePattern(
            DateTime.utc(2026, 2, 2, 15, 17), "EEEE, MMM d 'at' h:mm a"),
        'Monday, Feb 2 at 3:17 PM');
    expect(formatDatePattern(DateTime(2026, 1, 16), 'yyyy-MM-dd EEE MMMM yy'),
        '2026-01-16 Fri January 26');
    expect(call('pluralize', {'value': 1, 'one': 'item', 'other': 'items'}),
        'item');
    expect(call('pluralize', {'value': 3, 'one': 'item', 'other': 'items'}),
        'items');
    expect(call('pluralize', {'value': 0, 'zero': 'none', 'other': 'items'}),
        'none');
    expect(call('required', {'value': []}), false);
    expect(call('email', {'value': 'a@b.co'}), true);
    expect(call('length', {'value': 'abc', 'min': 4}), false);
    expect(call('numeric', {'value': '5', 'min': 1, 'max': 10}), true);
    expect(call('regex', {'value': '12345', 'pattern': r'^[0-9]{5}$'}), true);
    expect(
        call('and', {
          'values': [
            true,
            {
              'call': 'not',
              'args': {'value': false}
            }
          ]
        }),
        true);
    expect(
        call('or', {
          'values': [false, false]
        }),
        false);
    expect(
        () => call('openUrl', {'url': 'javascript:alert(1)'}),
        throwsA(isA<A2UIError>()
            .having((e) => e.message, 'message', contains('not allowed'))));
    expect(
        () => call('nope', {}),
        throwsA(isA<A2UIError>().having(
            (e) => e.message, 'message', contains('Unknown function'))));
  });

  test('svgPath icons parse', () {
    final path = parseSvgPath(
        'M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z');
    final b = path.getBounds();
    expect(b.left, closeTo(2, 0.01));
    expect(b.right, closeTo(22, 0.01));
    final arc = parseSvgPath('M2 12a10 10 0 1020 0 10 10 0 10-20 0z');
    expect(arc.getBounds().width, closeTo(20, 0.1));
  });

  test('NDJSON decoding survives arbitrary chunk splits', () {
    final lines = [
      {'type': 'conversation', 'conversationId': 'c1'},
      {
        'version': 'v0.9.1',
        'createSurface': {'surfaceId': 's', 'catalogId': basicCatalogId}
      },
      {'type': 'text', 'text': 'héllo — ünïcode ✓'},
      {'type': 'done', 'stopReason': 'end_turn'},
    ];
    final text = '${lines.map(jsonEncode).join('\n')}\n';
    for (final size in [1, 2, 3, 7, 13, text.length]) {
      final d = NdjsonDecoder();
      final out = <Object?>[];
      for (var i = 0; i < text.length; i += size) {
        out.addAll(d.push(text.substring(i, (i + size).clamp(0, text.length))));
      }
      out.addAll(d.end());
      expect(out, lines, reason: 'chunk size $size');
    }
    final d = NdjsonDecoder();
    expect(d.push('{"a":1}\r\n{"b"'), [
      {'a': 1}
    ]);
    expect(d.push(':2}'), isEmpty);
    expect(d.end(), [
      {'b': 2}
    ]);
  });

  test('a conversation streams a turn from a fake agent', () async {
    final agent = FakeAgent()
      ..chunks = [
        '{"type":"conversation","conversationId":"conv-1"}\n{"version":"v0.9.1","createSurface":{"surfaceId":"s","catalogId":"$basicCatalogId","sendDataModel":true}}\n',
        '{"version":"v0.9.1","updateComponents":{"surfaceId":"s","components":[{"id":"root","component":"Text","text":{"path":"/greeting"}}]}}\n{"version":"v0.9',
        '.1","updateDataModel":{"surfaceId":"s","path":"/greeting","value":"Hello"}}\n{"type":"text","text":"Here you go"}\n{"type":"done","stopReason":"end_turn"}\n',
      ];
    final conv = A2UIConversation(
        endpoint: const AgentEndpoint(
            baseUrl: 'http://agent.test/', appId: 'shop', agent: 'assistant'),
        fetch: agent.call);
    final events = <String>[];
    conv.on((e) => events.add(e.type));
    final turn = conv.send('hi');
    expect(await turn.conversationId, 'conv-1');
    final done = await turn.done;
    expect(done.conversationId, 'conv-1');
    expect(done.stopReason, 'end_turn');
    expect(agent.requests.first.url,
        'http://agent.test/apps/shop/agent/assistant');
    expect(agent.requests.first.body, {
      'message': 'hi',
      'capabilities': {
        'supportedCatalogIds': [basicCatalogId]
      }
    });
    expect((conv.dataModel('s') as Map)['greeting'], 'Hello');
    expect(conv.transcript.map((t) => t.toJson()), [
      {'role': 'user', 'text': 'hi'},
      {'role': 'agent', 'text': 'Here you go'},
    ]);
    expect(events, containsAll(['done', 'text', 'conversation']));
    agent.chunks = ['{"type":"done","stopReason":"end_turn"}'];
    await conv.sendAction({
      'name': 'x',
      'surfaceId': 's',
      'sourceComponentId': 'root',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'context': {}
    }).done;
    final second = agent.requests[1].body;
    expect(second['conversationId'], 'conv-1');
    expect(second['action']['name'], 'x');
    expect(second['dataModel'], {
      'version': 'v0.9.1',
      'surfaces': {
        's': {'greeting': 'Hello'}
      }
    });
    agent
      ..chunks = []
      ..error = 'HTTP status 500';
    expect((await conv.send('again').done).stopReason, 'error');
  });

  test('agent endpoints resolve from the registry defaults', () {
    final registry = A2UIRegistry();
    expect(registry.endpoint('assistant'), isNull, reason: 'no defaults');
    registry.defaults =
        const A2UIDefaults(baseUrl: 'http://localhost:8080/', appId: 'shop');
    expect(registry.endpoint('assistant')!.url,
        'http://localhost:8080/apps/shop/agent/assistant');
    expect(registry.endpoint('')?.url, isNull, reason: 'no agent');
    expect(
        registry
            .endpoint('a b', appId: 'other/app', baseUrl: 'https://x.dev')!
            .url,
        'https://x.dev/apps/other%2Fapp/agent/a%20b');
    // A widget without `app` / `baseUrl` reaches the current app's agent.
    final conv = a2uiConversationFor(registry, {'agent': 'assistant'}, 'w');
    expect(
        conv.endpoint!.url, 'http://localhost:8080/apps/shop/agent/assistant');
    // Static messages never reach an agent.
    final stat = a2uiConversationFor(
        registry, {'agent': 'assistant', 'messages': []}, 'w2');
    expect(stat.endpoint, isNull);
  });

  testWidgets('ElpianVmWidget points the app registry at its agents',
      (tester) async {
    final engine = ElpianEngine(services: ElpianServices(appId: 'vm'));
    await tester.pumpWidget(MaterialApp(
      home: ElpianVmWidget.fromAst(
        machineId: 'a2ui-defaults',
        astJson: '{}',
        engine: engine,
        agentAppId: 'shop',
        agentBaseUrl: 'http://localhost:8080/',
      ),
    ));
    final registry = a2uiRegistry(engine.services);
    expect(registry.defaults.appId, 'shop');
    expect(registry.endpoint('assistant')!.url,
        'http://localhost:8080/apps/shop/agent/assistant');
  });

  testWidgets(
      'A2UISurface widget: static messages, events and the agent host APIs',
      (tester) async {
    final messages = readJson(
        'spec/catalogs/basic/examples/00_interactive-button.json')['messages'];
    final got = <Map<String, dynamic>>[];
    final services = ElpianServices(appId: 'widget');
    final engine = ElpianEngine(services: services);
    await tester.pumpWidget(host(engine.renderFromJson({
      'type': 'A2UISurface',
      'key': 'w',
      'props': {'messages': messages},
      'events': {
        'a2uiAction': (ElpianEvent e) =>
            got.add(Map<String, dynamic>.from(e.data['value'] as Map)),
      },
    })));
    await tester.pump();
    expect(tester.takeException(), isNull);
    final registry = a2uiRegistry(services);
    final conv = registry['static:w']!;
    expect(conv.processor.surfaces, hasLength(1));
    final s = conv.processor.surfaces.first;
    final button =
        s.components.values.firstWhere((c) => c['component'] == 'Button');
    // Tapping the rendered button dispatches the action to the node's events.
    await tester.tap(find.byType(ElevatedButton).first);
    await tester.pump();
    expect(got, hasLength(1));
    expect(got.first['sourceComponentId'], button['id']);

    // Host APIs share the registry; the guest SDK's `askHost(name, [{...}])`
    // shape and a bare object both work.
    final handler = HostHandler(services: services);
    final model = jsonDecode(await handler.dispatch(
        'a2ui.dataModel',
        jsonEncode([
          {'conversation': 'static:w', 'surfaceId': s.id}
        ]))) as Map;
    expect(['object', 'null'], contains(model['type']));

    final agent = FakeAgent()
      ..chunks = [
        '{"type":"conversation","conversationId":"c9"}\n{"type":"done","stopReason":"end_turn"}\n'
      ];
    registry
      ..fetch = agent.call
      ..defaults =
          const A2UIDefaults(baseUrl: 'http://agent.test', appId: 'shop');
    final sent =
        await tester.runAsync(() async => jsonDecode(await handler.dispatch(
            'agent.send',
            jsonEncode([
              {'agent': 'assistant', 'message': 'hello'}
            ]))) as Map);
    expect(sent!['data']['value'],
        {'conversationId': 'c9', 'conversation': 'agent:assistant'});
    expect(
        agent.requests.last.url, 'http://agent.test/apps/shop/agent/assistant');

    final refused = HostHandler(services: services, onAuthorize: (_) => false);
    expect(
        jsonDecode(await refused.dispatch(
            'agent.send', '{"agent":"assistant"}'))['type'],
        'null');
    await tester.pumpWidget(const SizedBox());
  });
}
