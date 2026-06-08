import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/src/css/css_parser.dart';
import 'package:elpian_ui/src/css/stylesheet.dart';

void main() {
  // Mirrors the game's responsive `.game-window`: a floating, fixed-width
  // window by default; full-screen under (max-width: 820px). The bug was the
  // engine resolving `@media` against an unreliable platform viewport, so a
  // desktop window collapsed to the mobile full-screen layout. Media must
  // resolve against the host-provided widget viewport (CSSParser.viewportOverride).
  setUp(() {
    final mgr = GlobalStylesheetManager();
    mgr.clear();
    mgr.global.addRule('.game-window', {
      'position': 'absolute',
      'width': 460,
      'top': 96,
      'left': 24,
    });
    final mobile = CSSStylesheet();
    mobile.addRule('.game-window', {
      'position': 'fixed !important',
      'width': '100% !important',
    });
    mgr.addMediaQuery('(max-width: 820px)', mobile);
  });

  tearDown(() {
    GlobalStylesheetManager().clear();
    CSSParser.viewportOverride = null;
  });

  Map<String, dynamic> resolveGameWindow() =>
      GlobalStylesheetManager().getComputedStyleMap(
        tagName: 'div',
        classes: ['game-window'],
      );

  test('desktop viewport → floating window (absolute, fixed width)', () {
    CSSParser.viewportOverride = const Size(1280, 800);
    final s = resolveGameWindow();
    expect(s['position'], 'absolute');
    expect(s['width'], 460);
  });

  test('mobile viewport → full-screen window (fixed, 100%)', () {
    CSSParser.viewportOverride = const Size(400, 850);
    final s = resolveGameWindow();
    expect(s['position'], 'fixed');
    expect(s['width'].toString(), '100%');
  });

  test('the same rules flip purely on the override (no other input changes)',
      () {
    CSSParser.viewportOverride = const Size(1440, 900);
    expect(resolveGameWindow()['position'], 'absolute');
    CSSParser.viewportOverride = const Size(380, 820);
    expect(resolveGameWindow()['position'], 'fixed');
  });
}
