// The client facility sections build tile grids, progress meters, nested stat
// cards and event buttons. This renders a representative facility tree (the
// shapes __facilitySections emits) and asserts it lays out cleanly in the real
// engine — no overflow/ParentData exceptions.
import 'dart:ui' show Size;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';
import 'package:elpian_ui/src/css/css_parser.dart';
import 'package:elpian_ui/src/css/stylesheet.dart';

void main() {
  setUp(() { GlobalStylesheetManager().clear(); CSSParser.viewportOverride = const Size(412, 915); });
  tearDown(() { GlobalStylesheetManager().clear(); CSSParser.viewportOverride = null; });

  testWidgets('facility section (grid + progress + card + button) renders cleanly', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Map<String, dynamic> sp(String t) => {'type': 'span', 'props': {'text': t}};
    final tile = {
      'type': 'div',
      'style': {'display': 'flex', 'flexDirection': 'column', 'gap': 2, 'padding': 10, 'minWidth': 104},
      'children': [sp('🪵'), sp('Lumber'), sp('+5/min')],
    };
    final grid = {
      'type': 'div',
      'style': {'display': 'flex', 'flexDirection': 'row', 'gap': 8, 'flexWrap': 'wrap'},
      'children': [tile, tile],
    };
    final progress = {
      'type': 'div',
      'style': {'display': 'flex', 'flexDirection': 'column', 'gap': 4},
      'children': [
        {'type': 'div', 'style': {'height': 6, 'borderRadius': 999, 'overflow': 'hidden'}, 'children': [
          {'type': 'div', 'style': {'height': 6, 'width': '60%', 'backgroundColor': 'rgba(127,216,198,1)'}}
        ]},
        sp('City development'),
      ],
    };
    final card = {
      'type': 'div',
      'style': {'display': 'flex', 'flexDirection': 'column', 'gap': 4, 'padding': 12, 'borderWidth': 1, 'borderColor': 'rgba(216,185,120,0.18)'},
      'children': [
        {'type': 'div', 'style': {'display': 'flex', 'flexDirection': 'row', 'justifyContent': 'space-between'}, 'children': [sp('Tax income'), sp('+8/min')]},
      ],
    };
    final trainBtn = {'type': 'button', 'props': {'text': 'Train Swordsman'}, 'events': {'click': '__btr'},
      'style': {'textAlign': 'center', 'fontWeight': 800, 'paddingTop': 9, 'paddingBottom': 9, 'borderRadius': 8}};
    final section = {
      'type': 'div',
      'style': {'display': 'flex', 'flexDirection': 'column', 'gap': 8},
      'children': [sp('Production Output'), grid, progress, card, trainBtn],
    };
    final panel = {
      'type': 'div',
      'props': {'className': 'panel-card'},
      'style': {'display': 'flex', 'flexDirection': 'column', 'gap': 10, 'padding': 16},
      'children': [section],
    };

    final engine = ElpianEngine();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: engine.renderFromJson(panel)))));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Production Output'), findsOneWidget);
    expect(find.text('Train Swordsman'), findsOneWidget);
  });
}
