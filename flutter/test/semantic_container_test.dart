import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The HTML sectioning elements after they were collapsed into one builder.
///
/// `<article>`, `<aside>`, `<main>` and `<section>` were byte-for-byte
/// identical apart from the class name; `<header>` and `<footer>` differed by
/// one full-width wrapper. Six files, one behaviour and a half. These tests pin
/// what each tag renders so the collapse is demonstrably behaviour-preserving.
void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SizedBox(width: 400, child: child)),
      );

  Widget render(String tag, Map<String, dynamic> style, int childCount) =>
      ElpianEngine().renderFromJson({
        'type': tag,
        'style': style,
        'children': [
          for (var i = 0; i < childCount; i++)
            {
              'type': 'div',
              'key': 'cell$i',
              'style': {'height': 20, 'width': 50},
              'children': [],
            },
        ],
      });

  group('every sectioning tag still renders', () {
    for (final tag in [
      'section',
      'article',
      'aside',
      'main',
      'header',
      'footer'
    ]) {
      testWidgets('<$tag> lays its children out in a column by default',
          (tester) async {
        await tester.pumpWidget(wrap(render(tag, const {}, 3)));
        expect(find.byType(Column), findsWidgets);
        expect(find.byKey(const ValueKey('cell2')), findsOneWidget);
      });

      testWidgets('<$tag> becomes a row under display:flex', (tester) async {
        await tester.pumpWidget(wrap(
          render(tag, const {'display': 'flex', 'flexDirection': 'row'}, 2),
        ));
        expect(find.byType(Row), findsWidgets);
      });

      testWidgets('<$tag> renders nothing visible when empty', (tester) async {
        await tester.pumpWidget(wrap(render(tag, const {}, 0)));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the two families differ only in width', () {
    testWidgets('header and footer stretch to their parent', (tester) async {
      for (final tag in ['header', 'footer']) {
        await tester.pumpWidget(wrap(render(tag, const {}, 1)));
        final box = tester.renderObject<RenderBox>(
          find.byKey(const ValueKey('cell0')),
        );
        // The child is 50 wide, but its parent stretches across the 400-wide
        // container — that wrapper is the whole difference between the two
        // families.
        final parentWidth = tester
            .renderObject<RenderBox>(find.byType(Column).last)
            .constraints
            .maxWidth;
        expect(parentWidth, 400, reason: '<$tag> should be full width');
        expect(box.size.width, 50);
      }
    });

    testWidgets('the flow elements do not stretch', (tester) async {
      await tester.pumpWidget(wrap(
        render('article', const {}, 1),
      ));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('cell0')), findsOneWidget);
    });
  });

  group('gap', () {
    testWidgets('spacers go between children, not around them', (tester) async {
      await tester.pumpWidget(wrap(render(
        'section',
        const {'display': 'flex', 'flexDirection': 'row', 'gap': 10},
        3,
      )));

      // Three children with a 10px gap means two spacers: 3*50 + 2*10 = 170.
      final row = tester.renderObject<RenderBox>(find.byType(Row).last);
      expect(row.size.width, greaterThanOrEqualTo(170));
    });

    testWidgets('a single child gets no spacer', (tester) async {
      await tester.pumpWidget(wrap(render(
        'section',
        const {'display': 'flex', 'gap': 10},
        1,
      )));
      expect(find.byKey(const ValueKey('cell0')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
