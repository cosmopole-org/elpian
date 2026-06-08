import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';

/// A segmented control (two `flex:1` NextjsLink tabs in a row) must split the
/// row into two equal-width halves — the Sign In/Sign Up + leaderboard toggles.
void main() {
  testWidgets('two flex:1 NextjsLink tabs split the row equally', (tester) async {
    final bridge = NextjsBridge();
    // Mirror the real structure: a fixed-width card column (no alignItems → the
    // block-flow stretch path) whose child is the width-less tabs row.
    final row = {
      'type': 'div',
      'style': {'display': 'flex', 'flexDirection': 'row'},
      'children': [
        {
          'type': 'NextjsLink',
          'props': {'text': 'Sign In', 'href': '/a'},
          'style': {'flex': 1, 'backgroundColor': '#FFCC00', 'padding': 8},
        },
        {
          'type': 'NextjsLink',
          'props': {'text': 'Sign Up', 'href': '/b'},
          'style': {'flex': 1, 'backgroundColor': '#3366FF', 'padding': 8},
        },
      ],
    };
    final node = {
      'type': 'div',
      'style': {'display': 'flex', 'flexDirection': 'column', 'width': 400},
      'children': [row],
    };

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: bridge.engine.renderFromJson(node),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final tabs = find.byType(GestureDetector);
    expect(tabs, findsNWidgets(2));
    final w0 = tester.getSize(tabs.at(0)).width;
    final w1 = tester.getSize(tabs.at(1)).width;
    // Each tab should be ~half of the 400px row, not shrink-wrapped to its text.
    expect(w0, greaterThan(150));
    expect(w1, greaterThan(150));
    expect((w0 - w1).abs(), lessThan(2));
  });
}
