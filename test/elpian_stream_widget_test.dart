import 'dart:async';

import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ElpianStreamWidget', () {
    test('parses animation options from command payload', () {
      final command = ElpianStreamCommand.fromDynamic({
        'action': 'setView',
        'view': {
          'type': 'Text',
          'props': {'text': 'animated'},
        },
        'animate': true,
        'animationDurationMs': 500,
        'animationCurve': 'easeInOut',
      });

      expect(command.animate, isTrue);
      expect(command.animationDurationMs, equals(500));
      expect(command.animationCurve, equals('easeInOut'));
    });

    testWidgets('renders shorthand view payload from stream', (tester) async {
      final controller = StreamController<dynamic>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
          home: ElpianStreamWidget(
            stream: controller.stream,
            loadingWidget: const Text('loading'),
          ),
        ),
      );

      expect(find.text('loading'), findsOneWidget);

      controller.add({
        'type': 'Text',
        'props': {'text': 'hello stream'},
      });
      await tester.pump();

      expect(find.text('hello stream'), findsOneWidget);
    });

    testWidgets('applies patchView command to current tree', (tester) async {
      final controller = StreamController<dynamic>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
          home: ElpianStreamWidget(stream: controller.stream),
        ),
      );

      controller.add({
        'action': 'setView',
        'view': {
          'type': 'Text',
          'props': {'text': 'old'},
        },
      });
      await tester.pump();
      expect(find.text('old'), findsOneWidget);

      controller.add({
        'action': 'patchView',
        'patch': {
          'props': {'text': 'new'},
        },
      });
      await tester.pump();

      expect(find.text('new'), findsOneWidget);
      expect(find.text('old'), findsNothing);
    });

    testWidgets('uses animated transition when update command sets animate=true',
        (tester) async {
      final controller = StreamController<dynamic>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
          home: ElpianStreamWidget(stream: controller.stream),
        ),
      );

      controller.add({
        'action': 'setView',
        'view': {
          'type': 'Text',
          'props': {'text': 'v1'},
        },
      });
      await tester.pump();

      controller.add({
        'action': 'setView',
        'animate': true,
        'animationDurationMs': 700,
        'animationCurve': 'easeInOut',
        'view': {
          'type': 'Text',
          'props': {'text': 'v2'},
        },
      });
      await tester.pump();

      final switcher = tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
      expect(switcher.duration, const Duration(milliseconds: 700));
      expect(find.text('v2'), findsOneWidget);
    });
  });
}
