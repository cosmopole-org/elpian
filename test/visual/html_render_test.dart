import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';

import 'visual_harness.dart';

void main() {
  testWidgets('html/css: stylesheet class + inline merge (D1/D2 end-to-end)',
      timeout: const Timeout(Duration(seconds: 60)), (tester) async {
    // Register a stylesheet rule. The element below also carries inline styles;
    // the engine must merge BOTH (inline wins on conflict) and keep
    // stylesheet-only fields (D2 lossless merge).
    final mgr = GlobalStylesheetManager()..clear();
    mgr.global.addRule('.card', {
      'backgroundColor': '#2c3e50',
      'padding': '20',
      'borderRadius': 16,
      'color': '#ecf0f1', // stylesheet-only text color (must survive merge)
      'width': 120, // overridden inline below
    });

    final engine = ElpianEngine();
    final widget = engine.renderFromJson({
      'type': 'div',
      'props': {
        'style': {
          'display': 'flex',
          'flexDirection': 'column',
          'gap': 12,
          'padding': '24',
          'backgroundColor': '#1a242f',
        },
      },
      'children': [
        {
          'type': 'div',
          'key': 'card1',
          'props': {
            'className': 'card',
            // inline overrides width (200), adds margin; color comes from sheet
            'style': {'width': 220, 'margin': '0 0 4 0'},
          },
          'children': [
            {
              'type': 'span',
              'props': {
                'style': {'fontSize': 18, 'fontWeight': 'bold'}
              },
              'children': [
                {'type': 'text', 'props': {'text': 'Merged Card'}}
              ],
            },
          ],
        },
        {
          'type': 'div',
          'props': {
            'style': {
              'width': 220,
              'height': 40,
              'backgroundColor': '#e74c3c',
              'borderRadius': 8,
            },
          },
          'children': const [],
        },
      ],
    });

    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: widget,
              ),
            ),
          ),
        ),
      ),
    );
    // Use a single pump (not pumpAndSettle): the tree is static, and
    // pumpAndSettle can hang in a full-suite run if an earlier test left a
    // repeating ticker active in the shared binding.
    await tester.pump(const Duration(milliseconds: 32));

    // toImage() must run in a real async zone (the fake-async test zone never
    // drives the raster completer), otherwise it can hang when this file runs
    // alongside others.
    File? file;
    await tester.runAsync(() async {
      file = await captureBoundaryToPng(key, 'html_css_card');
    });
    expect(file!.existsSync(), isTrue);
    expect(file!.lengthSync(), greaterThan(0));
  });
}
