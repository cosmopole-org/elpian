import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';

/// A flex row whose children use `flex:1` (tight Expanded) must not crash when
/// it is nested as a NON-flex child of another flex container — the live case
/// being the resource dock's `flex:1` pill rows sitting inside the HUD column,
/// which a parent row hands an unbounded width. Before the guard this threw
/// "RenderFlex children have non-zero flex but incoming width constraints are
/// unbounded" and the subtree failed to lay out.
void main() {
  testWidgets('nested flex:1 row in an unbounded-width context lays out', (tester) async {
    final engine = ElpianEngine();
    // Outer row (no flex children) → its column child gets unbounded width →
    // the inner flex:1 row would crash without the unbounded-axis guard.
    final node = {
      'type': 'div',
      'style': {'display': 'flex', 'flexDirection': 'row'},
      'children': [
        {
          'type': 'div',
          'style': {'display': 'flex', 'flexDirection': 'column'},
          'children': [
            {
              'type': 'div',
              'style': {'display': 'flex', 'flexDirection': 'row'},
              'children': [
                {'type': 'div', 'style': {'flex': 1, 'height': 12, 'backgroundColor': '#a00'}},
                {'type': 'div', 'style': {'flex': 1, 'height': 12, 'backgroundColor': '#0a0'}},
              ],
            },
          ],
        },
      ],
    };

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          scrollDirection: Axis.horizontal, // hands the subtree unbounded width
          child: engine.renderFromJson(node),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // No exception, and the flex row shrink-wrapped to its content.
    expect(tester.takeException(), isNull);
    expect(find.byType(IntrinsicWidth), findsWidgets);
  });
}
