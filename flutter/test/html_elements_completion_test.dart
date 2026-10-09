// HTML elements that used to be placeholders: tables (colspan / rowspan /
// border-collapse), details/summary, dialog, datalist, image maps, sub/sup,
// media <source>/<track>, <object> params, <picture> and iframe fallbacks.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';
import 'package:elpian_ui/src/core/event_dispatcher.dart' as ed;
import 'package:elpian_ui/src/html_widgets/html_embedded_link_card.dart';
import 'package:elpian_ui/src/html_widgets/html_table_layout.dart';

Map<String, dynamic> td(String text, {Map<String, dynamic>? props}) => {
      'type': 'td',
      'props': {'text': text, ...?props},
    };

Map<String, dynamic> tr(List<Map<String, dynamic>> cells) =>
    {'type': 'tr', 'children': cells};

void main() {
  final dispatcher = ed.EventDispatcher.shared;
  final events = <ElpianEvent>[];

  setUp(() {
    GlobalStylesheetManager.shared.clear();
    events.clear();
    dispatcher.globalEventHandler = events.add;
  });
  tearDown(() {
    dispatcher.globalEventHandler = null;
    GlobalStylesheetManager.shared.clear();
  });

  Future<void> pump(WidgetTester tester, Map<String, dynamic> json) async {
    final engine = ElpianEngine();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: engine.renderFromJson(json),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('table', () {
    testWidgets('lays cells out on a grid with colspan', (tester) async {
      await pump(tester, {
        'type': 'table',
        'style': {'borderCollapse': 'collapse'},
        'children': [
          tr([
            td('Wide header', props: {'colspan': 2})
          ]),
          tr([td('A'), td('B')]),
        ],
      });

      Rect cell(String text) => tester.getRect(find
          .ancestor(of: find.text(text), matching: find.byType(Padding))
          .first);
      final wide = cell('Wide header');
      final a = cell('A');
      final b = cell('B');
      // Collapsed: no spacing. The spanning cell covers both columns.
      expect(a.top, closeTo(wide.bottom, 0.01));
      expect(b.left, closeTo(a.right, 0.01));
      expect(wide.left, closeTo(a.left, 0.01));
      expect(wide.right, closeTo(b.right, 0.01));
    });

    testWidgets('rowspan occupies the slot below and pushes cells right',
        (tester) async {
      await pump(tester, {
        'type': 'table',
        'props': {'cellspacing': 4},
        'children': [
          tr([
            td('Tall', props: {'rowspan': 2}),
            td('R1'),
          ]),
          tr([td('R2')]),
        ],
      });

      Rect cell(String text) => tester.getRect(find
          .ancestor(of: find.text(text), matching: find.byType(Padding))
          .first);
      final tall = cell('Tall');
      final r1 = cell('R1');
      final r2 = cell('R2');
      // R2 is in the second column (the first is taken by the rowspan).
      expect(r2.left, closeTo(r1.left, 0.01));
      expect(r1.left, closeTo(tall.right + 4, 0.01));
      // The tall cell spans both rows and the spacing between them.
      expect(tall.top, closeTo(r1.top, 0.01));
      expect(tall.bottom, closeTo(r2.bottom, 0.01));
      expect(r2.top, closeTo(r1.bottom + 4, 0.01));
    });

    testWidgets('thead / tbody / tfoot and caption render in HTML order',
        (tester) async {
      await pump(tester, {
        'type': 'table',
        'children': [
          {
            'type': 'caption',
            'props': {'text': 'Inventory'}
          },
          {
            'type': 'tfoot',
            'children': [
              tr([td('Total')])
            ]
          },
          {
            'type': 'tbody',
            'children': [
              tr([td('Wood')])
            ]
          },
          {
            'type': 'thead',
            'children': [
              tr([
                {
                  'type': 'th',
                  'props': {'text': 'Item'}
                }
              ])
            ]
          },
        ],
      });

      expect(find.textContaining('Unknown widget'), findsNothing);
      final caption = tester.getTopLeft(find.text('Inventory')).dy;
      final head = tester.getTopLeft(find.text('Item')).dy;
      final body = tester.getTopLeft(find.text('Wood')).dy;
      final foot = tester.getTopLeft(find.text('Total')).dy;
      expect(caption < head && head < body && body < foot, isTrue);
      // th is bold.
      final th = tester.widget<Text>(find.text('Item'));
      expect(th.style?.fontWeight, FontWeight.bold);
    });

    testWidgets('a table with fixed width fills it', (tester) async {
      await pump(tester, {
        'type': 'table',
        'style': {'width': 400, 'borderCollapse': 'collapse'},
        'props': {'border': '1'},
        'children': [
          tr([td('x'), td('y')]),
        ],
      });
      final table = find.byType(HtmlTableLayout);
      expect(tester.getSize(table).width, closeTo(400, 0.01));
    });
  });

  group('details / summary', () {
    testWidgets('starts closed, toggles on summary tap and reports toggle',
        (tester) async {
      await pump(tester, {
        'type': 'details',
        'key': 'd',
        'events': {'toggle': 'onToggle'},
        'children': [
          {
            'type': 'summary',
            'props': {'text': 'More'}
          },
          {
            'type': 'p',
            'props': {'text': 'Hidden body'}
          },
        ],
      });
      expect(find.text('More'), findsOneWidget);
      expect(find.text('Hidden body'), findsNothing);

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('Hidden body'), findsOneWidget);
      final toggle = events.where((e) => e.type == 'toggle').toList();
      expect(toggle, hasLength(1));
      expect(toggle.single.data['open'], isTrue);

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('Hidden body'), findsNothing);
      expect(
          events.where((e) => e.type == 'toggle').last.data['open'], isFalse);
    });

    testWidgets('the open attribute starts it open', (tester) async {
      await pump(tester, {
        'type': 'details',
        'props': {'open': true},
        'children': [
          {
            'type': 'summary',
            'props': {'text': 'S'}
          },
          {
            'type': 'span',
            'props': {'text': 'Shown'}
          },
        ],
      });
      expect(find.text('Shown'), findsOneWidget);
    });
  });

  group('dialog', () {
    testWidgets('is not rendered unless open', (tester) async {
      await pump(tester, {
        'type': 'dialog',
        'children': [
          {
            'type': 'p',
            'props': {'text': 'Dialog body'}
          }
        ],
      });
      expect(find.text('Dialog body'), findsNothing);
    });

    testWidgets('open non-modal dialog renders inline', (tester) async {
      await pump(tester, {
        'type': 'dialog',
        'props': {'open': true},
        'children': [
          {
            'type': 'p',
            'props': {'text': 'Inline dialog'}
          }
        ],
      });
      expect(find.text('Inline dialog'), findsOneWidget);
      expect(find.byType(ModalBarrier), findsOneWidget); // the app's own
    });

    testWidgets('modal dialog floats over a barrier and closes on Escape',
        (tester) async {
      await pump(tester, {
        'type': 'dialog',
        'key': 'dlg',
        'events': {'close': 'onClose', 'cancel': 'onCancel'},
        'props': {'open': true, 'modal': true},
        'children': [
          {
            'type': 'p',
            'props': {'text': 'Are you sure?'}
          }
        ],
      });
      expect(find.text('Are you sure?'), findsOneWidget);
      expect(find.byType(ModalBarrier), findsNWidgets(2));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Are you sure?'), findsNothing);
      expect(
          events.map((e) => e.type), containsAllInOrder(['cancel', 'close']));
    });
  });

  testWidgets('input list= offers its datalist as suggestions', (tester) async {
    await pump(tester, {
      'type': 'div',
      'children': [
        {
          'type': 'input',
          'key': 'city',
          'events': {'change': 'onCity'},
          'props': {'list': 'cities', 'placeholder': 'City'},
        },
        {
          'type': 'datalist',
          'props': {'id': 'cities'},
          'children': [
            {
              'type': 'option',
              'props': {'value': 'Paris'}
            },
            {
              'type': 'option',
              'props': {'value': 'Prague'}
            },
            {
              'type': 'option',
              'props': {'value': 'Oslo'}
            },
          ],
        },
      ],
    });

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'pr');
    await tester.pumpAndSettle();
    expect(find.text('Prague'), findsOneWidget);
    expect(find.text('Paris'), findsNothing);
    expect(find.text('Oslo'), findsNothing);

    await tester.tap(find.text('Prague'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'Prague');
    final change =
        events.whereType<ElpianInputEvent>().where((e) => e.type == 'change');
    expect(change.single.value, 'Prague');
  });

  testWidgets('img usemap hit-tests areas and dispatches their events',
      (tester) async {
    final clicked = <String>[];
    final engine = ElpianEngine();
    final tree = ElpianNode(type: 'div', children: [
      const ElpianNode(
        type: 'img',
        key: 'pic',
        props: {
          'src': 'missing.png',
          'alt': 'map',
          'usemap': '#m',
          'style': {'width': 200, 'height': 100},
        },
      ),
      ElpianNode(type: 'map', props: const {
        'name': 'm'
      }, children: [
        ElpianNode(
          type: 'area',
          key: 'left',
          props: const {'shape': 'rect', 'coords': '0,0,100,100'},
          events: {'click': () => clicked.add('left')},
        ),
        ElpianNode(
          type: 'area',
          key: 'circle',
          props: const {'shape': 'circle', 'coords': '150,50,20'},
          events: {'click': () => clicked.add('circle')},
        ),
      ]),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(alignment: Alignment.topLeft, child: engine.render(tree)),
      ),
    ));
    await tester.pumpAndSettle();

    final map = find.byType(HtmlImageMap);
    expect(map, findsOneWidget);
    final origin = tester.getTopLeft(map);
    await tester.tapAt(origin + const Offset(30, 30));
    await tester.tapAt(origin + const Offset(150, 50));
    await tester.tapAt(origin + const Offset(190, 95)); // no area
    expect(clicked, ['left', 'circle']);
  });

  test('image map areas: rect, circle and polygon hit testing', () {
    final poly = ImageMapArea('poly', [0, 0, 10, 0, 0, 10]);
    expect(poly.contains(2, 2), isTrue);
    expect(poly.contains(9, 9), isFalse);
    final circle = ImageMapArea('circle', [5, 5, 2]);
    expect(circle.contains(6, 6), isTrue);
    expect(circle.contains(8, 8), isFalse);
    final rect = ImageMapArea('rect', [10, 10, 0, 0]);
    expect(rect.contains(5, 5), isTrue);
  });

  testWidgets('sub and sup are smaller and shifted off the baseline',
      (tester) async {
    await pump(tester, {
      'type': 'div',
      'children': [
        {
          'type': 'sub',
          'props': {'text': 'low'}
        },
        {
          'type': 'sup',
          'props': {'text': 'high'}
        },
      ],
    });
    double shiftOf(String text) => tester
        .widget<Transform>(find
            .ancestor(of: find.text(text), matching: find.byType(Transform))
            .first)
        .transform
        .getTranslation()
        .y;
    expect(shiftOf('low'), greaterThan(0));
    expect(shiftOf('high'), lessThan(0));
    final size = tester.widget<Text>(find.text('high')).style!.fontSize!;
    expect(size, lessThan(14));
    expect(find.byType(HtmlScript), findsNWidgets(2));
  });

  group('media sources, tracks and params', () {
    test('video/audio play the first usable <source>', () {
      const node = ElpianNode(type: 'video', children: [
        ElpianNode(type: 'source', props: {
          'src': 'clip.ogv',
          'type': 'video/ogg',
        }),
        ElpianNode(type: 'source', props: {
          'src': 'clip.mp4',
          'type': 'video/mp4',
        }),
      ]);
      expect(HtmlSource.mediaSource(node), 'clip.mp4');
      expect(
          HtmlSource.mediaSource(
              const ElpianNode(type: 'audio', props: {'src': 'direct.mp3'})),
          'direct.mp3');
    });

    test('the default captions <track> is chosen and WebVTT parses', () {
      const node = ElpianNode(type: 'video', children: [
        ElpianNode(type: 'track', props: {
          'src': 'chapters.vtt',
          'kind': 'chapters',
        }),
        ElpianNode(type: 'track', props: {
          'src': 'en.vtt',
          'kind': 'subtitles',
        }),
        ElpianNode(type: 'track', props: {
          'src': 'fr.vtt',
          'kind': 'captions',
          'default': true,
        }),
      ]);
      expect(HtmlTrack.captionTrack(node)!.props['src'], 'fr.vtt');

      final vtt =
          HtmlTrack.parse('WEBVTT\n\n00:00:01.000 --> 00:00:02.500\nBonjour\n');
      expect(vtt.captions.single.text, 'Bonjour');
      expect(vtt.captions.single.start, const Duration(seconds: 1));
      final srt = HtmlTrack.parse('1\n00:00:01,000 --> 00:00:02,000\nHello\n');
      expect(srt.captions.single.text, 'Hello');
    });

    test('<object> passes its <param>s as query parameters', () {
      const node = ElpianNode(type: 'object', props: {
        'data': 'https://example.com/player?x=1',
      }, children: [
        ElpianNode(type: 'param', props: {'name': 'autoplay', 'value': '1'}),
        ElpianNode(type: 'param', props: {'name': 'lang', 'value': 'en us'}),
      ]);
      expect(HtmlObject.withParams(node, 'https://example.com/player?x=1'),
          'https://example.com/player?x=1&autoplay=1&lang=en+us');
    });

    testWidgets('<object> without data shows its fallback content',
        (tester) async {
      await pump(tester, {
        'type': 'object',
        'children': [
          {
            'type': 'param',
            'props': {'name': 'a', 'value': 'b'}
          },
          {
            'type': 'p',
            'props': {'text': 'Fallback'}
          },
        ],
      });
      expect(find.text('Fallback'), findsOneWidget);
    });

    test('<picture> picks the first source whose media matches', () {
      const sources = [
        ElpianNode(type: 'source', props: {
          'media': '(min-width: 800px)',
          'srcset': 'wide.png 1x, wide@2x.png 2x',
        }),
        ElpianNode(type: 'source', props: {'srcset': 'narrow.png'}),
      ];
      expect(HtmlPicture.selectSource(sources, 1024, 768), 'wide.png');
      expect(HtmlPicture.selectSource(sources, 400, 800), 'narrow.png');
    });
  });

  testWidgets('iframe without an inline web view is a link card',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await pump(tester, {
        'type': 'iframe',
        'props': {'src': 'https://example.com/embed'},
      });
      expect(find.byType(EmbeddedLinkCard), findsOneWidget);
      expect(find.textContaining('https://example.com/embed'), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
