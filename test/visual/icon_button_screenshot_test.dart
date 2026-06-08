import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';

import 'visual_harness.dart';

/// Renders the real Tritonias icon-button surfaces — the navbar action row
/// (square `NextjsLink` buttons, one badged) and a window header close button
/// (`span`) — at a mobile and a desktop width, capturing PNG screenshots so the
/// glyph centring can be eyeballed. Mirrors the JSON the TS builders emit in
/// `tritonias/src/elpian/ui/{navbar,window}.ts`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A square navbar icon button: fixed 42x42 flex box centring a gold glyph,
  // with an optional notification badge pinned to the top-right corner.
  Map<String, dynamic> iconButton(String glyph, {int? badge}) => {
        'type': 'NextjsLink',
        'props': {'href': '/x', 'ariaLabel': 'action'},
        'style': {
          'width': 42,
          'height': 42,
          'borderRadius': 12,
          'borderColor': 'rgba(216,185,120,0.34)',
          'borderWidth': 1,
          'display': 'flex',
          'justifyContent': 'center',
          'alignItems': 'center',
          'background':
              'linear-gradient(160deg, rgba(30,58,98,0.92), rgba(10,24,44,0.95))',
          'position': 'relative',
        },
        'children': [
          {
            'type': 'span',
            'props': {'text': glyph},
            'style': {'fontSize': 18, 'color': '#F2D98C'},
          },
          if (badge != null)
            {
              'type': 'span',
              'props': {'text': '$badge'},
              'style': {
                'position': 'absolute',
                'top': -6,
                'right': -6,
                'fontSize': 9,
                'fontWeight': 900,
                'backgroundColor': '#C0492F',
                'color': '#FFE9DF',
                'borderRadius': 999,
                'paddingLeft': 5,
                'paddingRight': 5,
                'paddingTop': 1,
                'paddingBottom': 1,
              },
            },
        ],
      };

  // The window header close button: a 30x30 flex span centring a muted ✕.
  Map<String, dynamic> closeButton() => {
        'type': 'span',
        'props': {'text': '✕', 'ariaLabel': 'Close'},
        'style': {
          'width': 30,
          'height': 30,
          'borderRadius': 8,
          'borderColor': 'rgba(126,167,220,0.22)',
          'borderWidth': 1,
          'backgroundColor': 'rgba(8,18,34,0.6)',
          'color': '#9DB1C6',
          'fontSize': 14,
          'display': 'flex',
          'alignItems': 'center',
          'justifyContent': 'center',
        },
      };

  Map<String, dynamic> demoScreen() => {
        'type': 'div',
        'style': {
          'display': 'flex',
          'flexDirection': 'column',
          'gap': 16,
          'padding': 12,
          'backgroundColor': '#0A182C',
        },
        'children': [
          // Navbar action row.
          {
            'type': 'div',
            'style': {
              'display': 'flex',
              'flexDirection': 'row',
              'justifyContent': 'flex-end',
              'alignItems': 'center',
              'gap': 7,
              'backgroundColor': 'rgba(16,30,52,0.7)',
              'borderRadius': 15,
              'padding': 9,
            },
            'children': [
              iconButton('⌛'),
              iconButton('⚔', badge: 3),
              iconButton('☰', badge: 12),
              iconButton('👤'),
            ],
          },
          // A window header strip ending in the close button.
          {
            'type': 'div',
            'style': {
              'display': 'flex',
              'flexDirection': 'row',
              'alignItems': 'center',
              'gap': 11,
              'backgroundColor': 'rgba(14,28,48,0.9)',
              'borderRadius': 12,
              'paddingTop': 13,
              'paddingBottom': 13,
              'paddingLeft': 16,
              'paddingRight': 14,
            },
            'children': [
              {
                'type': 'div',
                'style': {'flex': 1},
                'children': [
                  {
                    'type': 'span',
                    'props': {'text': 'Buildings'},
                    'style': {
                      'color': '#EAF2FF',
                      'fontSize': 16,
                      'fontWeight': 700,
                    },
                  },
                ],
              },
              closeButton(),
            ],
          },
        ],
      };

  Future<File> shot(WidgetTester tester, String name, double width) async {
    final bridge = NextjsBridge()..onNavigate = (_, {bool replace = false} ) {};
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF06101F),
          body: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: width,
                child: bridge.engine.renderFromJson(demoScreen()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 32));
    File? file;
    await tester.runAsync(() async {
      file = await captureBoundaryToPng(key, name);
    });
    expect(file!.existsSync(), isTrue);
    expect(file!.lengthSync(), greaterThan(0));
    return file!;
  }

  testWidgets('icon buttons — mobile (390px) screenshot', (tester) async {
    tester.view.physicalSize = const Size(390, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await shot(tester, 'icon_buttons_mobile_390', 390);
  });

  testWidgets('icon buttons — desktop (1280px) screenshot', (tester) async {
    tester.view.physicalSize = const Size(1280, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await shot(tester, 'icon_buttons_desktop_1280', 1280);
  });
}
