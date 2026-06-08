import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';

/// Finding #6: `display:grid` had no engine support, so grid containers
/// collapsed into a vertical stack. We now parse `grid-template-columns` and
/// lay the children out in a responsive [Wrap] with computed item widths.
void main() {
  late ElpianEngine engine;

  setUp(() {
    engine = ElpianEngine();
  });

  group('grid-template-columns parsing', () {
    test('auto-fill minmax populates gridTemplateColumns + grid gap', () {
      final style = CSSParser.parse({
        'display': 'grid',
        'gridTemplateColumns': 'repeat(auto-fill, minmax(120px, 1fr))',
        'gap': 8,
      });
      expect(style.display, 'grid');
      expect(style.gridTemplateColumns, 'repeat(auto-fill, minmax(120px, 1fr))');
      expect(style.gap, 8);
    });

    test('kebab-case grid-gap / row-gap / column-gap parse', () {
      final style = CSSParser.parse({
        'grid-gap': 12,
        'row-gap': 4,
        'column-gap': 6,
      });
      expect(style.gridGap, 12);
      expect(style.rowGap, 4);
      expect(style.columnGap, 6);
    });
  });

  Widget gridOf(Map<String, dynamic> style, int count, {double width = 400}) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: ElpianEngine().renderFromJson({
            'type': 'div',
            'style': {'display': 'grid', ...style},
            'children': [
              for (var i = 0; i < count; i++)
                {
                  'type': 'div',
                  'key': 'cell$i',
                  'style': {'height': 30},
                  'children': [],
                },
            ],
          }),
        ),
      ),
    );
  }

  double widthOfKey(WidgetTester tester, String key) {
    return tester.renderObject<RenderBox>(find.byKey(ValueKey(key))).size.width;
  }

  testWidgets('grid renders a Wrap (not a forced single column)',
      (tester) async {
    await tester.pumpWidget(gridOf(
      {'gridTemplateColumns': 'repeat(auto-fill, minmax(120px, 1fr))', 'gap': 8},
      6,
    ));
    expect(find.byType(Wrap), findsOneWidget);
  });

  testWidgets('auto-fill packs the right number of equal columns',
      (tester) async {
    // 400px wide, 8px gap, min 120 => floor((400+8)/(120+8)) = 3 columns.
    // Item width = (400 - 8*2) / 3 = 128.
    await tester.pumpWidget(gridOf(
      {'gridTemplateColumns': 'repeat(auto-fill, minmax(120px, 1fr))', 'gap': 8},
      6,
    ));
    expect(widthOfKey(tester, 'cell0'), closeTo(128, 0.5));
  });

  testWidgets('repeat(N, 1fr) yields a fixed column count', (tester) async {
    // 2 columns, 10px gap, 400px => item = (400 - 10) / 2 = 195.
    await tester.pumpWidget(gridOf(
      {'gridTemplateColumns': 'repeat(2, 1fr)', 'gap': 10},
      4,
    ));
    expect(widthOfKey(tester, 'cell0'), closeTo(195, 0.5));
  });
}
