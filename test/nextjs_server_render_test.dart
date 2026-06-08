// Regression guard: NextjsServerWidget must render a server envelope whose
// component tree contains Scope nodes + a page jsCode (the city/panel shape),
// without throwing during init/build. Uses a canned loader so no network or
// QuickJS native runtime is needed — this isolates the engine-side render path.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';

Map<String, dynamic> _cityEnvelope() => {
      'component': {
        'type': 'div',
        'style': {'width': '100%', 'height': '100vh'},
        'children': [
          {
            'type': 'div',
            'children': [
              {
                'type': 'Scope',
                'key': 'city-navbar__scope',
                'props': <String, dynamic>{},
                'children': [
                  {
                    'type': 'div',
                    'key': 'city-navbar',
                    'children': [
                      {'type': 'span', 'props': {'text': 'Lycanis Harbor'}}
                    ],
                  }
                ],
              },
              {
                'type': 'Scope',
                'key': 'hud__scope',
                'props': <String, dynamic>{},
                'children': [
                  {'type': 'div', 'key': 'hud', 'props': {'text': 'resources'}}
                ],
              },
            ],
          }
        ],
      },
      'jsCode': 'function MainComponent(){ return "null"; }',
      'stylesheet': {
        'rules': [
          {'selector': '.btn', 'styles': {'color': '#fff'}}
        ]
      },
    };

void main() {
  testWidgets('renders a server envelope with scopes + page jsCode (no throw)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NextjsServerWidget(
          route: '/city',
          serverBaseUrl: 'http://example.invalid/elpian',
          loader: (route, {props, headers}) async => _cityEnvelope(),
        ),
      ),
    ));

    // Resolve the future + a couple of frames.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    // The navbar text from the rendered tree must be on screen.
    expect(find.text('Lycanis Harbor'), findsOneWidget);
  });
}
