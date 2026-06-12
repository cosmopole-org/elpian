import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Typed `NextjsForm` field rendering: hidden values stay invisible but are
/// submitted, selects render as dropdowns (submitting the option VALUE, not
/// its label), checkboxes toggle true/false, and ranges render as sliders.
void main() {
  Widget host(NextjsBridge bridge, Map<String, dynamic> node) {
    return MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: bridge.renderComponent(node))),
    );
  }

  Map<String, dynamic> formNode(List<Map<String, dynamic>> fields) => {
        'type': 'NextjsForm',
        'props': {
          'action': '/trade/create-request',
          'submitLabel': 'Publish',
          'fields': fields,
        },
      };

  testWidgets('hidden fields render nothing but submit their value',
      (tester) async {
    Map<String, dynamic>? submitted;
    final bridge = NextjsBridge(onSubmit: (action, values) async {
      submitted = values;
      return null;
    });

    await tester.pumpWidget(host(
      bridge,
      formNode([
        {'name': 'requestId', 'type': 'hidden', 'value': 'req-42'},
      ]),
    ));

    // No editable control for the hidden field — only the submit button.
    expect(find.byType(TextField), findsNothing);
    expect(find.text('req-42'), findsNothing);

    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();
    expect(submitted, isNotNull);
    expect(submitted!['requestId'], 'req-42');
  });

  testWidgets('select renders a dropdown and submits the option value',
      (tester) async {
    Map<String, dynamic>? submitted;
    final bridge = NextjsBridge(onSubmit: (action, values) async {
      submitted = values;
      return null;
    });

    await tester.pumpWidget(host(
      bridge,
      formNode([
        {
          'name': 'offerResourceType',
          'type': 'select',
          'label': 'Offer Resource',
          'options': [
            {'value': 'wood', 'label': '🪵 Lumber'},
            {'value': 'marble', 'label': '🪨 Marble'},
          ],
        },
      ]),
    ));

    expect(find.byType(DropdownButton<String>), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    // Pick the second option from the menu.
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🪨 Marble').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();
    expect(submitted!['offerResourceType'], 'marble');
  });

  testWidgets('select falls back to comma-separated placeholder options',
      (tester) async {
    Map<String, dynamic>? submitted;
    final bridge = NextjsBridge(onSubmit: (action, values) async {
      submitted = values;
      return null;
    });

    await tester.pumpWidget(host(
      bridge,
      formNode([
        {
          'name': 'resourceType',
          'type': 'select',
          'placeholder': 'wood,marble,wine',
        },
      ]),
    ));

    expect(find.byType(DropdownButton<String>), findsOneWidget);
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();
    // Defaults to the first option.
    expect(submitted!['resourceType'], 'wood');
  });

  testWidgets('checkbox toggles and submits true/false', (tester) async {
    Map<String, dynamic>? submitted;
    final bridge = NextjsBridge(onSubmit: (action, values) async {
      submitted = values;
      return null;
    });

    await tester.pumpWidget(host(
      bridge,
      formNode([
        {'name': 'safeMode', 'type': 'checkbox', 'label': 'Safe mode', 'value': 'false'},
      ]),
    ));

    expect(find.byType(Checkbox), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();
    expect(submitted!['safeMode'], 'true');
  });

  testWidgets('range renders a slider and submits its numeric value',
      (tester) async {
    Map<String, dynamic>? submitted;
    final bridge = NextjsBridge(onSubmit: (action, values) async {
      submitted = values;
      return null;
    });

    await tester.pumpWidget(host(
      bridge,
      formNode([
        {
          'name': 'radius',
          'type': 'range',
          'label': 'Visibility Radius',
          'value': '180',
          'min': 10,
          'max': 500,
          'step': 10,
        },
      ]),
    ));

    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('180'), findsOneWidget); // current-value readout

    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();
    expect(submitted!['radius'], '180');
  });

  testWidgets('number fields filter non-numeric input', (tester) async {
    final bridge = NextjsBridge(onSubmit: (action, values) async => null);

    await tester.pumpWidget(host(
      bridge,
      formNode([
        {'name': 'amount', 'type': 'number', 'label': 'Amount'},
      ]),
    ));

    await tester.enterText(find.byType(TextField), 'abc123xyz');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '123',
    );
  });
}
