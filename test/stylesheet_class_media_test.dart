import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';

/// Regression coverage for the server-driven class cascade:
///   * class rules must contribute EVERY property (not just the old 6), so
///     `width`/`position`/`border`/`boxShadow`/gradient from a class apply;
///   * `{ media, selector, styles }` rules must be gated behind their query
///     instead of applying unconditionally (which corrupted desktop layouts);
///   * a trailing `!important` flag must be stripped so the value parses.
void main() {
  setUp(() => GlobalStylesheetManager().clear());
  tearDown(() => GlobalStylesheetManager().clear());

  test('class rules contribute all properties, not just six', () {
    GlobalStylesheetManager().global.addRule('.game-window', {
      'width': 460,
      'position': 'absolute',
      'borderRadius': 16,
      'borderWidth': 1,
    });

    final map = GlobalStylesheetManager().getComputedStyleMap(
      tagName: 'div',
      classes: ['game-window'],
    );

    expect(map['width'], 460);
    expect(map['position'], 'absolute');
    expect(map['borderRadius'], 16);
    expect(map['borderWidth'], 1);
  });

  test('media rules are gated by the query, not applied unconditionally', () {
    // Parse once: non-media rules come back in `.rules`, the media rule is
    // routed into the singleton's media queries (the parser's job).
    final parsed = JsonStylesheetParser.parseJsonStylesheet({
      'rules': [
        {
          'selector': '.game-window',
          'styles': {'width': 460},
        },
        {
          'media': '(max-width: 820px)',
          'selector': '.game-window',
          'styles': {'width': '100% !important', 'position': 'fixed !important'},
        },
      ],
    });
    // Load the non-media rules into global exactly as ElpianEngine does.
    for (final r in parsed.rules) {
      GlobalStylesheetManager().global.addRule(r.selector, r.styles);
    }

    // Desktop (1366 wide): the mobile @media override must NOT apply.
    final desktop = GlobalStylesheetManager().getComputedStyleMap(
      tagName: 'div',
      classes: ['game-window'],
      screenWidth: 1366,
      screenHeight: 900,
    );
    expect(desktop['width'], 460);
    expect(desktop.containsKey('position'), isFalse);

    // Mobile (412 wide): the override applies, and `!important` is stripped so
    // the values parse to a full-screen fixed panel.
    final mobile = GlobalStylesheetManager().getComputedStyleMap(
      tagName: 'div',
      classes: ['game-window'],
      screenWidth: 412,
      screenHeight: 915,
    );
    expect(mobile['width'], '100%');
    expect(mobile['position'], 'fixed');
  });

  test('stripImportant removes a trailing !important flag', () {
    expect(CSSParser.stripImportant('100% !important'), '100%');
    expect(CSSParser.stripImportant('fixed !important'), 'fixed');
    expect(CSSParser.stripImportant('0 !important'), '0');
    expect(CSSParser.stripImportant(460), 460);
  });

  test('inline styles still win over class rules', () {
    GlobalStylesheetManager().global.addRule('.game-window', {'width': 460});
    final map = GlobalStylesheetManager().getComputedStyleMap(
      tagName: 'div',
      classes: ['game-window'],
      inlineStyles: {'width': 600},
    );
    expect(map['width'], 600);
  });
}
