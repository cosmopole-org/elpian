import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';

/// A `NextjsLink` styled as a flex row (the game's glyph + label buttons) must
/// honour its own `gap` and alignment styles for its children — the bare
/// default Row dropped them, squashing button contents together.
void main() {
  testWidgets('link content honours the flex gap between glyph and label',
      (tester) async {
    final bridge = NextjsBridge();
    final node = {
      'type': 'NextjsLink',
      'props': {'href': '/world', 'ariaLabel': 'World'},
      'style': {
        'display': 'flex',
        'flexDirection': 'row',
        'alignItems': 'center',
        'gap': 6,
        'paddingLeft': 12,
        'paddingRight': 12,
        'height': 42,
      },
      'children': [
        {
          'type': 'span',
          'props': {'text': 'W'},
          'style': {'fontSize': 13},
        },
        {
          'type': 'span',
          'props': {'text': 'World'},
          'style': {'fontSize': 12},
        },
      ],
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

    final glyphRight = tester.getTopRight(find.text('W')).dx;
    final labelLeft = tester.getTopLeft(find.text('World')).dx;
    expect(labelLeft - glyphRight, closeTo(6, 0.6));

    // Both children sit vertically centred on the same axis.
    final glyphCenter = tester.getCenter(find.text('W')).dy;
    final labelCenter = tester.getCenter(find.text('World')).dy;
    expect((glyphCenter - labelCenter).abs(), lessThan(1));
  });

  testWidgets('a column-direction link stacks its children with the gap',
      (tester) async {
    final bridge = NextjsBridge();
    final node = {
      'type': 'NextjsLink',
      'props': {'href': '/city', 'ariaLabel': 'City'},
      'style': {
        'display': 'flex',
        'flexDirection': 'column',
        'gap': 4,
        'padding': 8,
      },
      'children': [
        {
          'type': 'span',
          'props': {'text': 'Top'},
        },
        {
          'type': 'span',
          'props': {'text': 'Bottom'},
        },
      ],
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

    final topBottom = tester.getBottomLeft(find.text('Top')).dy;
    final bottomTop = tester.getTopLeft(find.text('Bottom')).dy;
    expect(bottomTop - topBottom, closeTo(4, 0.6));
  });
}
