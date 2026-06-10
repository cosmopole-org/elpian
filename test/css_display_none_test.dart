// CSS `display: none` must remove the element from layout — including when it
// arrives via a matching `@media` stylesheet rule. This is what responsive
// server-driven UIs rely on to swap desktop/mobile variants of a region
// (e.g. a navbar cluster hidden under (max-width: 820px)).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';
import 'package:elpian_ui/src/css/css_parser.dart';
import 'package:elpian_ui/src/css/stylesheet.dart';

Map<String, dynamic> _tree() => {
      'type': 'div',
      'props': <String, dynamic>{},
      'children': [
        {
          'type': 'div',
          'props': {'className': 'desktop-only'},
          'children': [
            {
              'type': 'span',
              'props': {'text': 'DESKTOP'},
            },
          ],
        },
        {
          'type': 'span',
          'props': {'text': 'ALWAYS'},
        },
      ],
    };

void main() {
  setUp(() {
    GlobalStylesheetManager().clear();
    CSSParser.viewportOverride = null;
  });

  tearDown(() {
    GlobalStylesheetManager().clear();
    CSSParser.viewportOverride = null;
  });

  testWidgets('inline display:none removes the element', (tester) async {
    final engine = ElpianEngine();
    final widget = engine.renderFromJson({
      'type': 'div',
      'props': <String, dynamic>{},
      'children': [
        {
          'type': 'div',
          'props': {
            'style': {'display': 'none'},
          },
          'children': [
            {
              'type': 'span',
              'props': {'text': 'HIDDEN'},
            },
          ],
        },
        {
          'type': 'span',
          'props': {'text': 'VISIBLE'},
        },
      ],
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));
    expect(find.text('HIDDEN'), findsNothing);
    expect(find.text('VISIBLE'), findsOneWidget);
  });

  testWidgets('display:none from a matching @media rule hides; non-matching shows',
      (tester) async {
    final mgr = GlobalStylesheetManager();
    final mobile = CSSStylesheet();
    mobile.addRule('.desktop-only', {'display': 'none !important'});
    mgr.addMediaQuery('(max-width: 820px)', mobile);

    // Narrow viewport → rule matches → hidden.
    CSSParser.viewportOverride = const Size(400, 900);
    final engine = ElpianEngine();
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: engine.renderFromJson(_tree()))));
    expect(find.text('DESKTOP'), findsNothing);
    expect(find.text('ALWAYS'), findsOneWidget);

    // Wide viewport → rule does not match → visible.
    CSSParser.viewportOverride = const Size(1366, 900);
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: engine.renderFromJson(_tree()))));
    expect(find.text('DESKTOP'), findsOneWidget);
  });
}
