// The engine now surfaces form-control values to the page VM: an <input> and a
// <select> dispatch input/change events carrying the typed/chosen value (which
// NextjsServerWidget._eventToHostJson forwards to the node's events handler).
// These tests verify the widgets build from props and dispatch the value.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';
import 'package:elpian_ui/src/core/event_dispatcher.dart' as ed;
import 'package:elpian_ui/src/core/event_system.dart';

void main() {
  final dispatcher = ed.EventDispatcher();

  setUp(() {
    GlobalStylesheetManager().clear();
  });
  tearDown(() {
    dispatcher.globalEventHandler = null;
    GlobalStylesheetManager().clear();
  });

  testWidgets('select dispatches a change event with the chosen value', (tester) async {
    ElpianEvent? captured;
    dispatcher.globalEventHandler = (e) => captured ??= e;

    final engine = ElpianEngine();
    final node = {
      'type': 'select',
      'key': 'offer',
      'events': {'change': '__field_offer'},
      'props': {
        'value': 'wood',
        'options': [
          {'value': 'wood', 'label': 'Lumber'},
          {'value': 'marble', 'label': 'Marble'},
        ],
      },
    };
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: engine.renderFromJson(node))));
    await tester.pumpAndSettle();

    // Open the dropdown and pick "Marble".
    await tester.tap(find.text('Lumber'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marble').last);
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured, isA<ElpianInputEvent>());
    expect(captured!.type, 'change');
    expect((captured as ElpianInputEvent).value, 'marble');
    // It targets this node, so _routeEvent can resolve events.change → handler.
    expect(captured!.currentTarget, 'offer');
  });

  testWidgets('input dispatches an input event with the typed value', (tester) async {
    ElpianInputEvent? captured;
    dispatcher.globalEventHandler = (e) {
      if (e is ElpianInputEvent && e.type == 'input') captured = e;
    };

    final engine = ElpianEngine();
    final node = {
      'type': 'input',
      'key': 'amount',
      'events': {'input': '__field_amount'},
      'props': {'type': 'number', 'value': '200'},
    };
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: engine.renderFromJson(node))));
    await tester.pump();

    // Seeded from props.value, then edited.
    expect(find.text('200'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '350');
    await tester.pump();

    expect(captured, isNotNull);
    expect(captured!.value, '350');
    expect(captured!.currentTarget, 'amount');
  });
}
