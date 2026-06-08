import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';

/// Icon buttons across the UI are the canonical "centre a glyph in a square"
/// idiom: a fixed-size `display:flex` box (`justify/alignItems:center`) holding
/// a single text glyph. The navbar action buttons are `NextjsLink`s, the window
/// close button is a `span`. Before the fix only `div` honoured the flex
/// centring (it builds its own Row/Column), so link/span icon buttons painted
/// their glyph in the top-left corner. These tests pin the glyph to the box
/// centre so that regression can't silently return.
void main() {
  /// Pump [node] alone in the top-left so widget rects are in a stable frame.
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(alignment: Alignment.topLeft, child: child),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Assert [glyph] is centred *and* content-sized within [box]. The
  /// content-size check is the part that actually catches the bug: a Text given
  /// tight box-sized constraints (the un-fixed path) is stretched to fill the
  /// box and paints its glyph in the top-left corner — yet its widget rect still
  /// shares the box's centre, so a centre-only assertion passes vacuously.
  /// Centring via [Align] instead lets the Text shrink to its glyph, so the rect
  /// is both smaller than the box and genuinely centred.
  void expectCentredGlyph(Rect glyph, Rect box) {
    expect((glyph.center.dx - box.center.dx).abs(), lessThan(1.0),
        reason: 'glyph not horizontally centred');
    expect((glyph.center.dy - box.center.dy).abs(), lessThan(1.0),
        reason: 'glyph not vertically centred');
    expect(glyph.width, lessThan(box.width - 2),
        reason: 'glyph stretched to box width (painted top-left), not centred');
    expect(glyph.height, lessThan(box.height - 2),
        reason: 'glyph stretched to box height (painted top-left), not centred');
  }

  testWidgets('navbar NextjsLink icon button centres its glyph', (tester) async {
    final bridge = NextjsBridge();
    final node = {
      'type': 'NextjsLink',
      'props': {'href': '/operations', 'ariaLabel': 'Open operations queue'},
      'style': {
        'width': 42,
        'height': 42,
        'borderRadius': 12,
        'display': 'flex',
        'justifyContent': 'center',
        'alignItems': 'center',
        'backgroundColor': '#1E3A62',
        'position': 'relative',
      },
      'children': [
        {
          'type': 'span',
          'props': {'text': '⌛'},
          'style': {'fontSize': 18, 'color': '#F2D98C'},
        },
      ],
    };

    await pump(tester, bridge.engine.renderFromJson(node));

    final box = tester.getRect(find.byType(GestureDetector).first);
    final glyph = tester.getRect(find.text('⌛'));
    expectCentredGlyph(glyph, box);
  });

  testWidgets('badged NextjsLink keeps the glyph centred, badge overlaid',
      (tester) async {
    final bridge = NextjsBridge();
    final node = {
      'type': 'NextjsLink',
      'props': {'href': '/battle', 'ariaLabel': 'Open battles'},
      'style': {
        'width': 42,
        'height': 42,
        'display': 'flex',
        'justifyContent': 'center',
        'alignItems': 'center',
        'backgroundColor': '#1E3A62',
        'position': 'relative',
      },
      'children': [
        {
          'type': 'span',
          'props': {'text': '⚔'},
          'style': {'fontSize': 18, 'color': '#F2D98C'},
        },
        {
          'type': 'span',
          'props': {'text': '3'},
          'style': {
            'position': 'absolute',
            'top': -6,
            'right': -6,
            'fontSize': 9,
          },
        },
      ],
    };

    await pump(tester, bridge.engine.renderFromJson(node));

    final box = tester.getRect(find.byType(GestureDetector).first);
    final glyph = tester.getRect(find.text('⚔'));
    // The absolute badge must NOT shove the main glyph off-centre.
    expectCentredGlyph(glyph, box);
    // The badge is overlaid near the top-right corner, above the glyph.
    final badge = tester.getRect(find.text('3'));
    expect(badge.center.dx, greaterThan(glyph.center.dx));
    expect(badge.center.dy, lessThan(glyph.center.dy));
  });

  testWidgets('window close span centres its ✕ glyph', (tester) async {
    final engine = ElpianEngine();
    final node = {
      'type': 'span',
      'props': {'text': '✕', 'ariaLabel': 'Close'},
      'style': {
        'width': 30,
        'height': 30,
        'borderRadius': 8,
        'backgroundColor': '#081222',
        'fontSize': 14,
        'display': 'flex',
        'alignItems': 'center',
        'justifyContent': 'center',
      },
    };

    await pump(tester, engine.renderFromJson(node));

    // The 30x30 box is the styled SizedBox; the glyph must sit at its centre.
    final glyph = tester.getRect(find.text('✕'));
    final box = tester.getRect(find.byType(SizedBox).last);
    expectCentredGlyph(glyph, box);
  });

  testWidgets('a fixed-size flex div was already centred (no regression)',
      (tester) async {
    final engine = ElpianEngine();
    final node = {
      'type': 'div',
      'style': {
        'width': 40,
        'height': 40,
        'display': 'flex',
        'justifyContent': 'center',
        'alignItems': 'center',
        'backgroundColor': '#22426C',
      },
      'children': [
        {
          'type': 'span',
          'props': {'text': '⚓'},
          'style': {'fontSize': 19},
        },
      ],
    };

    await pump(tester, engine.renderFromJson(node));

    final glyph = tester.getRect(find.text('⚓'));
    final box = tester.getRect(find.byType(SizedBox).last);
    expectCentredGlyph(glyph, box);
  });
}
