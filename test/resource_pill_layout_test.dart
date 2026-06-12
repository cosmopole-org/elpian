// The resource dock pill is a flex child that also handles taps. The tap target
// must NOT carry flex (the engine wraps event nodes in a GestureDetector, which
// would bury the Flexible and throw "Incorrect use of ParentDataWidget" in the
// Row). This mirrors the tritonias structure: flex on an outer wrapper, events
// on the inner face — and asserts it lays out cleanly inside a flex row.
import 'dart:ui' show Size;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';
import 'package:elpian_ui/src/css/css_parser.dart';
import 'package:elpian_ui/src/css/stylesheet.dart';

void main() {
  setUp(() { GlobalStylesheetManager().clear(); CSSParser.viewportOverride = const Size(412, 915); });
  tearDown(() { GlobalStylesheetManager().clear(); CSSParser.viewportOverride = null; });

  testWidgets('flex pill with inner event face lays out without ParentData error', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Map<String, dynamic> pill(String label, String handler) => {
          'type': 'div',
          'style': {'display': 'flex', 'flexDirection': 'column', 'flex': 1},
          'children': [
            {
              'type': 'div',
              'style': {'display': 'flex', 'flexDirection': 'row', 'justifyContent': 'center'},
              'events': {'click': handler},
              'children': [
                {'type': 'span', 'props': {'text': label}},
              ],
            },
          ],
        };

    final dock = {
      'type': 'div',
      'style': {'display': 'flex', 'flexDirection': 'row', 'gap': 7},
      'children': [pill('GOLD', '__openRes_gold'), pill('WOOD', '__openRes_wood')],
    };

    final engine = ElpianEngine();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: engine.renderFromJson(dock))));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('GOLD'), findsOneWidget);
    expect(find.text('WOOD'), findsOneWidget);
  });
}
