import 'dart:convert';

import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QuickJS host/UI integration contracts', () {
    test('HostHandler render payload from JS can be rendered by ElpianEngine',
        () async {
      final engine = ElpianEngine();
      Map<String, dynamic>? lastView;
      String? lastScopeKey;

      final hostHandler = HostHandler(
        onRender: (viewJson, scopeKey) {
          lastView = viewJson;
          lastScopeKey = scopeKey;
        },
      );

      final payload = jsonEncode({
        'type': 'Column',
        'children': [
          {
            'type': 'Text',
            'props': {'text': 'Hello from QuickJS'},
          },
        ],
      });

      final response = hostHandler.handleRender(payload);

      expect(lastView, isNotNull);
      expect(lastView!['type'], equals('Column'));
      expect(lastScopeKey, isNull);
      expect(response, contains('"type":"i16"'));

      final renderedWidget = engine.renderFromJson(lastView!);
      expect(renderedWidget, isA<Widget>());
    });

    test('HostHandler supports array-wrapped host args format', () async {
      Map<String, dynamic>? lastView;
      String? lastScopeKey;
      final hostHandler = HostHandler(
        onRender: (viewJson, scopeKey) {
          lastView = viewJson;
          lastScopeKey = scopeKey;
        },
      );

      hostHandler.handleRender(jsonEncode([
        {
          'type': 'Text',
          'props': {'text': 'wrapped payload'},
        },
        'scope-child'
      ]));

      expect(lastView, isNotNull);
      expect(lastView!['type'], equals('Text'));
      expect(lastScopeKey, equals('scope-child'));
    });

    test('HostHandler updateApp + println callbacks receive JS-side payloads',
        () async {
      Map<String, dynamic>? update;
      String? println;

      final hostHandler = HostHandler(
        onUpdateApp: (data) => update = data,
        onPrintln: (msg) => println = msg,
      );

      hostHandler.handleUpdateApp(
        jsonEncode([
          {
            'source': 'quickjs',
            'event': 'loaded',
          }
        ]),
      );
      hostHandler.handlePrintln(jsonEncode(['quickjs says hi']));

      expect(update, isNotNull);
      expect(update!['source'], equals('quickjs'));
      expect(println, equals('quickjs says hi'));
    });

    test('HostHandler supports DOM + Canvas host API catalog', () {
      final hostHandler = HostHandler();

      final created = jsonDecode(hostHandler.handleHostCall(
        'dom.createElement',
        jsonEncode([
          {
            'tagName': 'div',
            'id': 'root',
            'classes': ['page']
          }
        ]),
      )) as Map<String, dynamic>;
      expect(created['type'], equals('object'));

      hostHandler.handleHostCall(
        'canvas.fillRect',
        jsonEncode([
          {'x': 0, 'y': 0, 'width': 100, 'height': 50}
        ]),
      );
      final commands =
          jsonDecode(hostHandler.handleHostCall('canvas.getCommands', '[]'))
              as Map<String, dynamic>;
      expect(commands['type'], equals('array'));
      expect((commands['data']['value'] as List).isNotEmpty, isTrue);
    });

    test('VM widgets expose runtime selection for QuickJS', () {
      const widget = ElpianVmWidget.fromCode(
        machineId: 'quickjs-widget-contract',
        runtime: ElpianRuntime.quickJs,
        code: 'askHost("println", "hello")',
      );

      final scope = ElpianVmScope(
        controller: ElpianVmController(),
        machineId: 'quickjs-scope-contract',
        runtime: ElpianRuntime.quickJs,
        code: 'askHost("println", "scope")',
      );

      expect(widget.runtime, equals(ElpianRuntime.quickJs));
      expect(scope.runtime, equals(ElpianRuntime.quickJs));
    });
  });
}
