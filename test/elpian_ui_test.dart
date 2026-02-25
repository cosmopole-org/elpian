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
      
      final json = <String, dynamic>{
        'type': 'CustomTest',
        'props': <String, dynamic>{},
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

  group('HTML Media Widget Tests', () {
    late ElpianEngine engine;

    setUp(() {
      engine = ElpianEngine();
    });

    testWidgets('video element renders player fallback when src is missing', (tester) async {
      final widget = MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 200,
            child: engine.renderFromJson({
              'type': 'video',
              'props': <String, dynamic>{},
            }),
          ),
        ),
      );

      await tester.pumpWidget(widget);

      expect(find.text('video src is required'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('audio element renders player fallback when src is missing', (tester) async {
      final widget = MaterialApp(
        home: Scaffold(
          body: engine.renderFromJson({
            'type': 'audio',
            'props': <String, dynamic>{},
          }),
        ),
      );

      await tester.pumpWidget(widget);

      expect(find.text('audio src is required'), findsOneWidget);
      expect(find.byIcon(Icons.audiotrack), findsOneWidget);
    });
  });


  group('HTML Extended Element Tests', () {
    late ElpianEngine engine;

    setUp(() {
      engine = ElpianEngine();
    });

    testWidgets('iframe shows source-required fallback when src is missing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 180,
              child: engine.renderFromJson({
                'type': 'iframe',
                'props': <String, dynamic>{},
              }),
            ),
          ),
        ),
      );

      expect(find.text('iframe source is required'), findsOneWidget);
    });

    testWidgets('canvas builds without throwing when no commands are provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: engine.renderFromJson({
              'type': 'canvas',
              'props': <String, dynamic>{
                'width': 300,
                'height': 150,
              },
            }),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
    });
  });


  group('Math Expression Widget Tests', () {
    late ElpianEngine engine;

    setUp(() {
      engine = ElpianEngine();
    });

    testWidgets('math expression shows required message when empty', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: engine.renderFromJson({
              'type': 'MathExpression',
              'props': <String, dynamic>{},
            }),
          ),
        ),
      );

      expect(find.text('Math expression is required'), findsOneWidget);
    });

    testWidgets('math expression sanitizes unsafe TeX commands', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: engine.renderFromJson({
              'type': 'MathExpression',
              'props': <String, dynamic>{
                'expression': r'\frac{1}{2} + \input{secret.tex}',
              },
            }),
          ),
        ),
      );

      expect(
        find.text('Unsafe commands were sanitized from the expression.'),
        findsOneWidget,
      );
    });
  });

}
