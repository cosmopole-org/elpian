// Layout regression for the Tritonias stage shell (navbar + overlay window
// manager). Reproduces the EXACT node shape `defineStageShell` emits so we can
// assert, against the real engine, that:
//   1. the navbar paints as a CONTENT-sized strip at the very top (not stretched
//      to fill the viewport, not clipped away), and
//   2. an open panel window is NOT clipped to the navbar band — its body paints
//      well below the navbar on a mobile viewport (full-bleed `.shell-window`).
//
// The shell mounts as: stage(100vh) > full-bleed wrapper(inset:0) > Scope >
// shell-root(absolute top/left/right, height:100vh) > [ pinned navbar, window ].
// All styles are TOP-LEVEL `style` maps, matching the client runtime's output.

import 'dart:ui' show Size;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';
import 'package:elpian_ui/src/css/css_parser.dart';
import 'package:elpian_ui/src/css/stylesheet.dart';

void main() {
  const mobile = Size(412, 915);

  setUp(() {
    GlobalStylesheetManager().clear();
    CSSParser.viewportOverride = mobile;
  });
  tearDown(() {
    GlobalStylesheetManager().clear();
    CSSParser.viewportOverride = null;
  });

  // The mobile `.shell-window` rule that turns an open window full-bleed +
  // opaque (the exact rule from tritonias' stylesheet that, combined with the
  // old top-anchored shell root, painted a black strip over the navbar).
  Map<String, dynamic> shellWindowMediaSheet() => {
        'rules': [
          {
            'media': '(max-width: 640px)',
            'selector': '.shell-window',
            'styles': {
              'left': '0 !important',
              'top': '0 !important',
              'right': '0 !important',
              'bottom': '0 !important',
              'width': '100% !important',
              'maxWidth': 'none !important',
              'height': '100% !important',
              'maxHeight': 'none !important',
              'paddingTop': '92 !important',
              'paddingBottom': '16 !important',
              'backgroundColor': 'rgba(5,14,28,1) !important',
            },
          },
        ],
      };

  Map<String, dynamic> navbar() => {
        'type': 'div',
        // The shell pins the navbar as its own top strip (top/left/right only →
        // unbounded height → shrink-wraps to content).
        'style': {
          'padding': 12,
          'position': 'absolute',
          'top': 0,
          'left': 0,
          'right': 0,
          'zIndex': 10,
        },
        'children': [
          {
            'type': 'div',
            'style': {
              'display': 'flex',
              'flexDirection': 'column',
              'backgroundColor': 'rgba(11,29,52,0.96)',
            },
            'children': [
              {
                'type': 'span',
                'props': {'text': 'NAVBAR'},
                'style': {'fontSize': 18},
              },
            ],
          },
        ],
      };

  Map<String, dynamic> windowNode() => {
        'type': 'div',
        'props': {'className': 'shell-window'},
        'style': {
          'position': 'fixed',
          'left': 96,
          'top': 84,
          'width': 560,
          'maxWidth': '94vw',
          'maxHeight': '84vh',
          'overflowY': 'auto',
          'zIndex': 61,
        },
        'children': [
          {'type': 'span', 'props': {'text': 'PANEL BODY'}},
        ],
      };

  Map<String, dynamic> stage({required bool withWindow}) => {
        'type': 'div',
        'style': {'position': 'relative', 'width': '100%', 'height': '100vh'},
        'children': [
          {
            'type': 'div',
            'style': {
              'position': 'absolute',
              'top': 0,
              'left': 0,
              'right': 0,
              'bottom': 0,
              'zIndex': 40,
            },
            'children': [
              {
                'type': 'Scope',
                'key': 'stage-shell__scope',
                'props': <String, dynamic>{},
                'children': [
                  {
                    'type': 'div',
                    'key': 'stage-shell',
                    'style': {
                      'position': 'absolute',
                      'top': 0,
                      'left': 0,
                      'right': 0,
                      'height': '100vh',
                      'zIndex': 40,
                    },
                    'children': [
                      navbar(),
                      if (withWindow) windowNode(),
                    ],
                  },
                ],
              },
            ],
          },
        ],
      };

  Future<void> pumpStage(WidgetTester tester, {required bool withWindow}) async {
    tester.view.physicalSize = mobile;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final engine = ElpianEngine();
    engine.loadStylesheet(shellWindowMediaSheet());
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: engine.renderFromJson(stage(withWindow: withWindow))),
    ));
    await tester.pump();
  }

  testWidgets('navbar paints as a content-sized strip at the top', (tester) async {
    await pumpStage(tester, withWindow: false);

    expect(find.text('NAVBAR'), findsOneWidget);
    final nav = tester.renderObject<RenderBox>(find.text('NAVBAR'));
    final pos = nav.localToGlobal(Offset.zero);
    // Pinned to the top (within the 12px padding), not pushed off-screen.
    expect(pos.dy, lessThan(40));
    // The navbar text sits near the top — the navy bar did NOT stretch to fill
    // the 915px viewport (the regression that hid the navbar behind a giant
    // full-screen panel / blank).
    expect(nav.size.height, lessThan(120));
  });

  testWidgets('open panel window is not clipped to the navbar band', (tester) async {
    await pumpStage(tester, withWindow: true);

    // The navbar still shows...
    expect(find.text('NAVBAR'), findsOneWidget);
    // ...and the panel body renders, pushed below the navbar by the full-bleed
    // mobile padding (92) — proof it is NOT clipped to a thin top strip.
    expect(find.text('PANEL BODY'), findsOneWidget);
    final body = tester.renderObject<RenderBox>(find.text('PANEL BODY'));
    final pos = body.localToGlobal(Offset.zero);
    expect(pos.dy, greaterThan(80));
    expect(pos.dy, lessThan(mobile.height));
  });
}
