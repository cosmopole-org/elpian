import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';

void main() {
  group('CSS background shorthand → gradient/color', () {
    test('background: linear-gradient(...) parses to a LinearGradient', () {
      final style = CSSParser.parse({
        'background': 'linear-gradient(135deg, #F4C95B, #E0902F)',
      });
      expect(style.gradient, isA<LinearGradient>());
      final g = style.gradient as LinearGradient;
      expect(g.colors.length, 2);
      // 135deg → to bottom-right.
      expect(g.begin, Alignment.topLeft);
      expect(g.end, Alignment.bottomRight);
      // A pure gradient background leaves backgroundColor unset.
      expect(style.backgroundColor, isNull);
    });

    test('rgba() stops are not split on their internal commas', () {
      final style = CSSParser.parse({
        'background':
            'linear-gradient(180deg, rgba(32,25,19,0.92), rgba(10,14,24,0.94))',
      });
      final g = style.gradient as LinearGradient;
      expect(g.colors.length, 2);
      // 180deg → top→bottom.
      expect(g.begin, Alignment.topCenter);
      expect(g.end, Alignment.bottomCenter);
    });

    test('colour stop percentages are honoured', () {
      final style = CSSParser.parse({
        'background': 'linear-gradient(90deg, #000 0%, #fff 100%)',
      });
      final g = style.gradient as LinearGradient;
      expect(g.stops, [0.0, 1.0]);
      expect(g.begin, Alignment.centerLeft);
      expect(g.end, Alignment.centerRight);
    });

    test('background: <solid color> resolves to backgroundColor (no gradient)', () {
      final style = CSSParser.parse({'background': '#0B1F3A'});
      expect(style.gradient, isNull);
      expect(style.backgroundColor, isNotNull);
    });

    test('explicit gradient/backgroundColor keys still win', () {
      final style = CSSParser.parse({
        'backgroundColor': '#112233',
        'background': 'linear-gradient(0deg, #000, #fff)',
      });
      // backgroundColor key takes precedence for the solid colour…
      expect(style.backgroundColor, isNotNull);
      // …and the gradient still comes from the shorthand.
      expect(style.gradient, isA<LinearGradient>());
    });
  });
}
