import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';

void main() {
  setUp(CSSParser.clearCache);

  group('D1 — CSSParser.parse memoization', () {
    test('identical maps return the same cached CSSStyle instance', () {
      final a = CSSParser.parse(<String, dynamic>{'width': 100, 'color': 'red'});
      // Distinct map object with equal content must hit the cache.
      final b = CSSParser.parse(<String, dynamic>{'width': 100, 'color': 'red'});
      expect(identical(a, b), isTrue);
      expect(CSSParser.cacheSize, 1);
    });

    test('different maps produce different cached entries', () {
      CSSParser.parse(<String, dynamic>{'width': 100});
      CSSParser.parse(<String, dynamic>{'width': 200});
      expect(CSSParser.cacheSize, 2);
    });

    test('parse result is still correct (color/width parsed)', () {
      final style = CSSParser.parse(<String, dynamic>{
        'width': 100,
        'color': '#ff0000',
        'fontWeight': 'bold',
      });
      expect(style.width, 100);
      expect(style.color, const Color(0xFFFF0000));
      expect(style.fontWeight, FontWeight.bold);
    });

    test('mutating the caller map after parse does not corrupt the cache', () {
      final map = <String, dynamic>{'width': 50};
      final first = CSSParser.parse(map);
      map['width'] = 999; // mutate after caching
      // Re-parsing the original content must still hit the same entry.
      final again = CSSParser.parse(<String, dynamic>{'width': 50});
      expect(identical(first, again), isTrue);
      expect(first.width, 50);
    });
  });

  group('D2 — lossless stylesheet+inline merge', () {
    test('getComputedStyleMap returns the raw cascade map', () {
      final sheet = CSSStylesheet();
      sheet.addRule('.box', <String, dynamic>{'width': 100, 'color': 'red'});
      final map = sheet.getComputedStyleMap(tagName: 'div', classes: ['box']);
      expect(map['width'], 100);
      expect(map['color'], 'red');
    });

    test('merging maps then parsing keeps fields present only in the sheet',
        () {
      final sheet = CSSStylesheet();
      // letterSpacing exists only in the stylesheet, width only inline.
      sheet.addRule('.box', <String, dynamic>{
        'letterSpacing': 4,
        'color': 'blue',
      });
      final sheetMap =
          sheet.getComputedStyleMap(tagName: 'div', classes: ['box']);
      final inlineMap = <String, dynamic>{'color': '#ff0000', 'width': 200};

      final merged = CSSParser.parse(<String, dynamic>{
        ...sheetMap,
        ...inlineMap,
      });

      // Inline wins on conflict...
      expect(merged.color, const Color(0xFFFF0000));
      // ...inline-only field present...
      expect(merged.width, 200);
      // ...and the sheet-only field SURVIVES (the old _styleToMap path dropped
      // letterSpacing entirely).
      expect(merged.letterSpacing, 4);
    });
  });
}
