import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';

import 'visual_harness.dart';

/// Renders the REAL Tritonias screens (dumped to build/screens/*.json by
/// tritonias/scripts/dump-screens.mts) through the actual Elpian engine at a
/// spread of viewport sizes — portrait/landscape phone, small phone, tablet,
/// desktop — and writes a PNG per (screen × size). This is a responsiveness
/// audit harness: the images surface where layout fails to track the screen's
/// width AND height. 3D scenes were stubbed to same-size placeholders upstream.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final screensDir = Directory('build/screens');

  // (label, logical width, logical height)
  const sizes = <List<dynamic>>[
    ['phone_portrait', 390.0, 844.0],
    ['phone_landscape', 844.0, 390.0],
    ['phone_small', 320.0, 568.0],
    ['tablet_portrait', 768.0, 1024.0],
    ['desktop', 1366.0, 768.0],
  ];

  final screens = screensDir.existsSync()
      ? (screensDir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];

  for (final file in screens) {
    final name = file.uri.pathSegments.last.replaceAll('.json', '');
    final envelope = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

    for (final size in sizes) {
      final label = size[0] as String;
      final w = size[1] as double;
      final h = size[2] as double;

      testWidgets('$name @ $label (${w.toInt()}x${h.toInt()})', (tester) async {
        tester.view.physicalSize = Size(w, h);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final bridge = NextjsBridge()..onNavigate = (_, {bool replace = false}) {};
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: const Color(0xFF05101E),
              // The engine sizes vh/% against the platform view, so give it the
              // whole screen rect — exactly what a full-bleed game host does.
              body: SizedBox(
                width: w,
                height: h,
                child: RepaintBoundary(
                  key: key,
                  child: bridge.renderDocument(envelope),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 32));

        await tester.runAsync(() async {
          await captureBoundaryToPng(key, 'screen_${name}_$label');
        });
      });
    }
  }
}
