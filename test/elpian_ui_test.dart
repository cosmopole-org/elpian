import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';

void main() {
  group('Elpian Engine Tests', () {
    late ElpianEngine engine;

    setUp(() {
      engine = ElpianEngine();
    });

    test('Engine initializes with default widgets', () {
      expect(engine, isNotNull);
    });

    test('Can register custom widget', () {
      engine.registerWidget('CustomTest', (node, children) {
        return const SizedBox();
      });
      
      final json = {
        'type': 'CustomTest',
        'props': {},
      };
      
      final widget = engine.renderFromJson(json);
      expect(widget, isNotNull);
    });
  });

  group('CSS Parser Tests', () {
    test('Parses color correctly', () {
      final style = CSSParser.parse({
        'color': '#FF0000',
      });
      
      expect(style.color, isNotNull);
    });

    test('Parses padding correctly', () {
      final style = CSSParser.parse({
        'padding': '16',
      });
      
      expect(style.padding, isNotNull);
    });

    test('Parses font properties correctly', () {
      final style = CSSParser.parse({
        'fontSize': 24,
        'fontWeight': 'bold',
      });
      
      expect(style.fontSize, equals(24.0));
      expect(style.fontWeight, isNotNull);
    });
  });

  group('ElpianNode Tests', () {
    test('Can create node from JSON', () {
      final json = {
        'type': 'Text',
        'props': {'text': 'Hello'},
      };
      
      final node = ElpianNode.fromJson(json);
      
      expect(node.type, equals('Text'));
      expect(node.props['text'], equals('Hello'));
    });

    test('Can serialize node to JSON', () {
      final node = ElpianNode(
        type: 'Container',
        props: {'width': 100},
      );
      
      final json = node.toJson();
      
      expect(json['type'], equals('Container'));
      expect(json['props']['width'], equals(100));
    });
  });

  group('Widget Registry Tests', () {
    test('Can register and retrieve widgets', () {
      final registry = WidgetRegistry();
      
      registry.register('Test', (node, children) {
        return const SizedBox();
      });
      
      expect(registry.has('Test'), isTrue);
      expect(registry.get('Test'), isNotNull);
    });

    test('Can unregister widgets', () {
      final registry = WidgetRegistry();
      
      registry.register('Test', (node, children) {
        return const SizedBox();
      });
      
      registry.unregister('Test');
      
      expect(registry.has('Test'), isFalse);
    });
  });
}
