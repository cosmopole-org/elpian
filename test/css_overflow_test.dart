import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';

void main() {
  group('CSS overflow parsing', () {
    test('auto and scroll both map to Overflow.scroll', () {
      expect(CSSParser.parse({'overflow': 'auto'}).overflow, Overflow.scroll);
      expect(CSSParser.parse({'overflow': 'scroll'}).overflow, Overflow.scroll);
    });

    test('hidden maps to Overflow.hidden, visible to visible', () {
      expect(CSSParser.parse({'overflow': 'hidden'}).overflow, Overflow.hidden);
      expect(CSSParser.parse({'overflow': 'visible'}).overflow, Overflow.visible);
    });

    test('overflowX / overflowY parse independently', () {
      final style = CSSParser.parse({'overflowX': 'hidden', 'overflowY': 'auto'});
      expect(style.overflowX, Overflow.hidden);
      expect(style.overflowY, Overflow.scroll);
    });
  });

  group('CSS overflow application', () {
    testWidgets('overflowY:auto with a bounded height becomes scrollable',
        (tester) async {
      final style = CSSParser.parse({'overflowY': 'auto', 'maxHeight': 100});
      final widget = CSSProperties.applyStyle(
        const SizedBox(height: 1000),
        style,
      );
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('overflow:hidden clips without scrolling', (tester) async {
      final style = CSSParser.parse({'overflow': 'hidden'});
      final widget = CSSProperties.applyStyle(const SizedBox(), style);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));
      expect(find.byType(ClipRect), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsNothing);
    });

    testWidgets('overflowY:auto without a bound degrades to a clip (no crash)',
        (tester) async {
      final style = CSSParser.parse({'overflowY': 'auto'});
      final widget = CSSProperties.applyStyle(const SizedBox(), style);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.byType(ClipRect), findsOneWidget);
    });
  });
}
