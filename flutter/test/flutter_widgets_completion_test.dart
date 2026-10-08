// Flutter-DSL widgets that used to be placeholders: InkWell / GestureDetector
// (gestures dispatched as events, once), Dismissible, Draggable + DragTarget,
// Scaffold / AppBar slots, and the Shimmer skeleton.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';
import 'package:elpian_ui/src/core/event_dispatcher.dart' as ed;

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
  });

  List<String> types() => events.map((e) => e.type).toList();

  Future<void> pump(WidgetTester tester, Map<String, dynamic> json,
      {bool bare = false, bool settle = true}) async {
    final engine = ElpianEngine();
    final rendered = engine.renderFromJson(json);
    await tester.pumpWidget(MaterialApp(
      home: bare ? rendered : Scaffold(body: Center(child: rendered)),
    ));
    if (settle) await tester.pumpAndSettle();
  }

  Map<String, dynamic> label(String text) => {
        'type': 'Text',
        'props': {'data': text, 'text': text},
      };

  testWidgets('InkWell dispatches tap/click once, plus declared gestures',
      (tester) async {
    await pump(tester, {
      'type': 'InkWell',
      'key': 'ink',
      'events': {'click': 'onClick', 'longpress': 'onLong'},
      'children': [
        {
          'type': 'SizedBox',
          'style': {'width': 100, 'height': 40},
          'children': [label('Ink')]
        }
      ],
    });
    expect(find.byType(InkWell), findsOneWidget);

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();
    expect(types().where((t) => t == 'click'), hasLength(1));
    expect(events.firstWhere((e) => e.type == 'click').currentTarget, 'ink');

    await tester.longPress(find.byType(InkWell));
    await tester.pumpAndSettle();
    expect(types(), contains('longpress'));
  });

  testWidgets('GestureDetector dispatches taps, double taps and drags',
      (tester) async {
    await pump(tester, {
      'type': 'GestureDetector',
      'key': 'gd',
      'events': {
        'tap': 'onTap',
        'doubletap': 'onDouble',
        'dragstart': 'onStart',
        'drag': 'onDrag',
        'dragend': 'onEnd',
        'swiperight': 'onSwipe',
      },
      'children': [
        {
          'type': 'SizedBox',
          'style': {'width': 200, 'height': 100},
        }
      ],
    });
    final target = find.byType(GestureDetector).first;

    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 400));
    expect(types().where((t) => t == 'tap'), hasLength(1));

    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(types(), contains('doubletap'));

    events.clear();
    await tester.fling(target, const Offset(150, 0), 1500);
    await tester.pumpAndSettle();
    expect(types(), containsAllInOrder(['dragstart', 'drag', 'dragend']));
    expect(types(), contains('swiperight'));
    final drag = events
        .whereType<ElpianPointerEvent>()
        .firstWhere((e) => e.type == 'drag');
    expect(drag.delta.dx, greaterThan(0));
  });

  testWidgets('Dismissible removes the child and reports the direction',
      (tester) async {
    await pump(tester, {
      'type': 'Dismissible',
      'key': 'row1',
      'events': {'dismissed': 'onDismissed'},
      'props': {'direction': 'endToStart'},
      'children': [
        {
          'type': 'SizedBox',
          'style': {'width': 300, 'height': 50},
          'children': [label('Swipe me')],
        },
        {
          'type': 'Container',
          'props': {'slot': 'background'},
          'style': {'backgroundColor': '#ff0000'},
        },
      ],
    });
    expect(find.text('Swipe me'), findsOneWidget);
    await tester.fling(find.text('Swipe me'), const Offset(-400, 0), 2000);
    await tester.pumpAndSettle();
    expect(find.text('Swipe me'), findsNothing);
    final dismissed = events.firstWhere((e) => e.type == 'dismissed');
    expect(dismissed.data['direction'], 'endToStart');
  });

  testWidgets('Draggable drops its data on an accepting DragTarget',
      (tester) async {
    await pump(
      tester,
      {
        'type': 'Column',
        'children': [
          {
            'type': 'Draggable',
            'key': 'piece',
            'events': {'dragstart': 's', 'dragend': 'e'},
            'props': {'data': 'knight'},
            'children': [
              {
                'type': 'SizedBox',
                'style': {'width': 60, 'height': 60},
                'children': [label('Piece')],
              }
            ],
          },
          {
            'type': 'SizedBox',
            'style': {'height': 100},
          },
          {
            'type': 'DragTarget',
            'key': 'square',
            'events': {'accept': 'onAccept', 'drop': 'onDrop'},
            'props': {
              'accepts': ['knight', 'bishop']
            },
            'children': [
              {
                'type': 'SizedBox',
                'style': {'width': 120, 'height': 120},
                'children': [label('Square')],
              }
            ],
          },
        ],
      },
    );

    final from = tester.getCenter(find.text('Piece'));
    final to = tester.getCenter(find.text('Square'));
    final gesture = await tester.startGesture(from);
    await tester.pump();
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
        types(),
        containsAllInOrder(
            ['dragstart', 'dragenter', 'drop', 'accept', 'dragend']));
    final accept = events.firstWhere((e) => e.type == 'accept');
    expect(accept.data['data'], 'knight');
    expect(accept.currentTarget, 'square');
    final end = events.firstWhere((e) => e.type == 'dragend');
    expect(end.data['accepted'], isTrue);
    expect(end.currentTarget, 'piece');
  });

  testWidgets('DragTarget rejects data it does not accept', (tester) async {
    await pump(tester, {
      'type': 'Column',
      'children': [
        {
          'type': 'Draggable',
          'props': {'data': 'pawn'},
          'children': [label('Pawn')],
        },
        {
          'type': 'SizedBox',
          'style': {'height': 80},
        },
        {
          'type': 'DragTarget',
          'key': 't',
          'events': {'accept': 'a'},
          'props': {'accepts': 'queen'},
          'children': [
            {
              'type': 'SizedBox',
              'style': {'width': 100, 'height': 100},
              'children': [label('Target')],
            }
          ],
        },
      ],
    });
    await tester.drag(
        find.text('Pawn'),
        tester.getCenter(find.text('Target')) -
            tester.getCenter(find.text('Pawn')));
    await tester.pumpAndSettle();
    expect(types(), isNot(contains('accept')));
    expect(types(), contains('dragreject'));
  });

  testWidgets('Scaffold fills appBar, drawer, FAB and bottom bar slots',
      (tester) async {
    await pump(
      tester,
      {
        'type': 'Scaffold',
        'children': [
          {
            'type': 'AppBar',
            'props': {'title': 'Inbox', 'centerTitle': true},
            'children': [
              {
                'type': 'Icon',
                'props': {'slot': 'leading', 'icon': 'menu'},
              },
              {
                'type': 'Icon',
                'props': {'icon': 'search'},
              },
            ],
          },
          {
            'type': 'Column',
            'children': [label('Body text')],
          },
          {
            'type': 'Column',
            'props': {'slot': 'drawer'},
            'children': [label('Drawer item')],
          },
          {
            'type': 'FloatingActionButton',
            'key': 'fab',
            'events': {'click': 'onFab'},
            'props': {'tooltip': 'Compose'},
          },
          {
            'type': 'Container',
            'props': {'slot': 'bottomNavigationBar'},
            'style': {'height': 56},
            'children': [label('Bottom bar')],
          },
        ],
      },
      bare: true,
    );

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('Body text'), findsOneWidget);
    expect(find.text('Bottom bar'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.drawer, isNotNull);
    expect(scaffold.appBar, isNotNull);
    expect(scaffold.bottomNavigationBar, isNotNull);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(types().where((t) => t == 'click'), hasLength(1));

    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
    expect(find.text('Drawer item'), findsOneWidget);
  });

  testWidgets('Shimmer skeleton paints its base colour', (tester) async {
    await pump(
        tester,
        {
          'type': 'Shimmer',
          'style': {'width': 120, 'height': 16, 'shimmerBaseColor': '#112233'},
        },
        settle: false);
    final box = tester.widget<Container>(find.descendant(
        of: find.byType(ShaderMask), matching: find.byType(Container)));
    final decoration = box.decoration! as BoxDecoration;
    expect(decoration.color, const Color(0xFF112233));
    // Let the repeating animation tick without leaking.
    await tester.pump(const Duration(milliseconds: 500));
  });
}
