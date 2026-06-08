import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';
import 'package:elpian_ui/src/css/css_parser.dart';
import 'package:elpian_ui/src/css/stylesheet.dart' as css;

/// Unit coverage for the viewport/responsive primitives added to the engine:
/// `calc()`, `env(safe-area-inset-*)`, `@media (orientation)`, `aspect-ratio`,
/// and the `flex-grow` longhand. These are the "relate the UI to the screen"
/// building blocks the engine previously dropped.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The test binding's implicit view is 800x600 @ dpr 3 by default → logical
  // viewport is governed by CSSParser._viewportSize(); we read it to compute
  // expectations rather than hard-coding, so the asserts track the real value.
  final vp = CSSParser.viewportSize();

  group('calc()', () {
    test('subtracts a fixed px from a viewport height', () {
      final v = CSSParser.parseDimension('calc(100vh - 92px)', isWidth: false);
      expect(v, closeTo(vp.height - 92, 0.01));
    });

    test('adds two terms, mixing vw and px', () {
      final v = CSSParser.parseDimension('calc(50vw + 20px)', isWidth: true);
      expect(v, closeTo(vp.width * 0.5 + 20, 0.01));
    });

    test('unsupported multiply yields null (property dropped, not wrong)', () {
      expect(CSSParser.parseDimension('calc(100vh * 2)', isWidth: false), isNull);
    });
  });

  group('env(safe-area-inset-*)', () {
    test('a known inset resolves to the device value (0 with no padding)', () {
      // CSS `env()` uses the *actual* inset; the fallback applies only when the
      // variable is unknown. The headless test view has no safe-area padding.
      expect(
        CSSParser.parseDimension('env(safe-area-inset-bottom, 16px)', isWidth: false),
        0,
      );
    });

    test('an unknown env var uses its fallback', () {
      expect(
        CSSParser.parseDimension('env(safe-area-inset-xyz, 16px)', isWidth: false),
        16,
      );
    });

    test('resolves inside calc() (inset is 0 here, so equals 100vh)', () {
      final v = CSSParser.parseDimension(
        'calc(100vh - env(safe-area-inset-top, 44px))',
        isWidth: false,
      );
      expect(v, closeTo(vp.height, 0.01));
    });
  });

  group('aspect-ratio', () {
    test('parses "16/9" and a bare ratio', () {
      expect(CSSParser.parseAspectRatio('16/9'), closeTo(16 / 9, 0.001));
      expect(CSSParser.parseAspectRatio('1.5'), 1.5);
      expect(CSSParser.parseAspectRatio('auto'), isNull);
    });

    testWidgets('derives height from a fixed width', (tester) async {
      final engine = ElpianEngine();
      final node = {
        'type': 'div',
        'style': {'width': 300, 'aspectRatio': '3/1', 'backgroundColor': '#222'},
        'children': [
          {'type': 'span', 'props': {'text': 'x'}},
        ],
      };
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: engine.renderFromJson(node),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final box = tester.getRect(find.byType(AspectRatio));
      expect(box.width / box.height, closeTo(3.0, 0.05));
    });
  });

  group('@media orientation', () {
    final landscape = css.MediaQuery(query: '(orientation: landscape)', stylesheet: css.CSSStylesheet());
    final portrait = css.MediaQuery(query: '(orientation: portrait)', stylesheet: css.CSSStylesheet());

    test('landscape matches wide viewports only', () {
      expect(landscape.matches(800, 400), isTrue);
      expect(landscape.matches(400, 800), isFalse);
    });
    test('portrait matches tall viewports only', () {
      expect(portrait.matches(400, 800), isTrue);
      expect(portrait.matches(800, 400), isFalse);
    });
    test('combines with a width clause (and-semantics)', () {
      final mq = css.MediaQuery(
        query: '(max-width: 820) and (orientation: portrait)',
        stylesheet: css.CSSStylesheet(),
      );
      expect(mq.matches(400, 800), isTrue); // narrow + portrait
      expect(mq.matches(900, 1200), isFalse); // portrait but too wide
      expect(mq.matches(400, 300), isFalse); // narrow but landscape
    });
  });

  group('flex-grow longhand', () {
    testWidgets('flex-grow:1 fills like flex:1', (tester) async {
      final engine = ElpianEngine();
      final node = {
        'type': 'div',
        'style': {'display': 'flex', 'flexDirection': 'row', 'width': 400},
        'children': [
          {'type': 'div', 'style': {'flexGrow': 1, 'height': 10, 'backgroundColor': '#a00'}},
          {'type': 'div', 'style': {'width': 100, 'height': 10, 'backgroundColor': '#0a0'}},
        ],
      };
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: engine.renderFromJson(node),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // The flex-grow child should claim the remaining 300px of the 400 row.
      final grow = tester.getRect(find.byType(Container).first);
      expect(grow.width, greaterThan(250));
    });
  });
}
