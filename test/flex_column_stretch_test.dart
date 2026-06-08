import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';

/// Finding #4: a column with no `align-items` should stretch its children to
/// the full cross-axis width (CSS default), so row-children can use
/// `space-between` / flex spacers to push content apart, and so block-flow
/// stacks fill their parent. Flutter's [Column] defaults to `start` (and a
/// plain block div is a `mainAxisSize.min` column), which shrink-wraps every
/// child to its content width — collapsing space-between rows and badges.
///
/// We reproduce stretch by giving width-less children an infinite width (under
/// a bounded width), while preserving children that declare an explicit width
/// and leaving `align-items: center/start` columns untouched.
void main() {
  late ElpianEngine engine;

  setUp(() {
    engine = ElpianEngine();
  });

  double widthOfKey(WidgetTester tester, String key) {
    return tester.renderObject<RenderBox>(find.byKey(ValueKey(key))).size.width;
  }

  testWidgets(
      'block-flow column stretches a width-less child to the bounded parent width',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: engine.renderFromJson({
            // Plain block div (no display:flex) => mainAxisSize.min column.
            'type': 'div',
            'children': [
              {
                'type': 'div',
                'key': 'target',
                // No width: should stretch to the full 400px.
                'children': [
                  {
                    'type': 'div',
                    'style': {'width': 100, 'height': 30},
                    'children': [],
                  },
                ],
              },
              {
                'type': 'div',
                'style': {'width': 100, 'height': 30},
                'children': [],
              },
            ],
          }),
        ),
      ),
    ));

    expect(widthOfKey(tester, 'target'), 400);
  });

  testWidgets('explicit child width is preserved under auto-stretch',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: engine.renderFromJson({
            'type': 'div',
            'children': [
              {
                'type': 'div',
                'key': 'fixed',
                'style': {'width': 150, 'height': 40},
                'children': [],
              },
              {
                'type': 'div',
                'style': {'width': 100, 'height': 30},
                'children': [],
              },
            ],
          }),
        ),
      ),
    ));

    expect(widthOfKey(tester, 'fixed'), 150);
  });

  testWidgets('alignItems:center column does NOT stretch width-less children',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: engine.renderFromJson({
            'type': 'div',
            'style': {
              'display': 'flex',
              'flexDirection': 'column',
              'alignItems': 'center',
            },
            'children': [
              {
                'type': 'div',
                'key': 'centered',
                // No width: under `center` it must shrink-wrap to 100, not 400.
                'children': [
                  {
                    'type': 'div',
                    'style': {'width': 100, 'height': 30},
                    'children': [],
                  },
                ],
              },
            ],
          }),
        ),
      ),
    ));

    expect(widthOfKey(tester, 'centered'), 100);
  });

  testWidgets('unbounded width falls back to start (no infinite-width crash)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            engine.renderFromJson({
              'type': 'div',
              'children': [
                {
                  'type': 'div',
                  'style': {'width': 100, 'height': 30},
                  'children': [],
                },
                {
                  'type': 'div',
                  'style': {'width': 80, 'height': 30},
                  'children': [],
                },
              ],
            }),
          ],
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
  });
}
