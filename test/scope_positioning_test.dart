// A positioned element wrapped in a `Scope` (the update boundary every
// client-component mount and server scope() produces) must still be absolutely
// positioned by its parent: Scopes are re-render boundaries, not layout nodes.

import 'dart:ui' show Size;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';
import 'package:elpian_ui/src/css/css_parser.dart';
import 'package:elpian_ui/src/css/stylesheet.dart';

void main() {
  setUp(() {
    GlobalStylesheetManager().clear();
    CSSParser.viewportOverride = const Size(1366, 900);
  });
  tearDown(() {
    GlobalStylesheetManager().clear();
    CSSParser.viewportOverride = null;
  });

  testWidgets('absolute window inside a Scope floats at its class geometry',
      (tester) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final engine = ElpianEngine();
    engine.loadStylesheet({
      'rules': [
        {
          'selector': '.game-window',
          'styles': {'position': 'absolute', 'top': 96, 'left': 24, 'width': 460},
        },
      ],
    });

    final stage = {
      'type': 'div',
      'props': {
        'style': {'position': 'relative', 'width': '100%', 'height': '100vh'},
      },
      'children': [
        {
          'type': 'div',
          'props': {
            'style': {'position': 'absolute', 'top': 0, 'left': 0, 'right': 0, 'bottom': 0},
          },
          'children': [
            {
              'type': 'Scope',
              'key': 'panel__scope',
              'props': <String, dynamic>{},
              'children': [
                {
                  'type': 'div',
                  'props': {'className': 'game-window'},
                  'children': [
                    {'type': 'span', 'props': {'text': 'WINDOW BODY'}},
                  ],
                },
              ],
            },
          ],
        },
      ],
    };

    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: engine.renderFromJson(stage))));
    await tester.pump();

    final box = tester.renderObject<RenderBox>(find.text('WINDOW BODY'));
    final pos = box.localToGlobal(Offset.zero);
    // Inside the 460-wide window at (24, 96) — not full-width in flow at (0, 0).
    expect(pos.dx, greaterThanOrEqualTo(24));
    expect(pos.dy, greaterThanOrEqualTo(96));
    expect(box.size.width, lessThanOrEqualTo(460));
  });
}
