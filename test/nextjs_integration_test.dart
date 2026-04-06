import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NextjsRenderEnvelope', () {
    test('parses valid envelope payload with script fields', () {
      final envelope = NextjsRenderEnvelope.fromJson({
        'component': {
          'type': 'Text',
          'props': {'text': 'Hello from Next.js'}
        },
        'meta': {'route': '/home'},
        'navigation': {'redirectTo': '/auth', 'replace': true},
        'clientComponents': {
          'profile-card': {
            'jsCode': 'function MainComponent(){ return "ok"; }',
            'jsEntryFunction': 'MainComponent',
          },
        },
        'jsCode': 'function MainComponent(){ return "ok"; }',
        'jsEntryFunction': 'MainComponent',
        'vmAstJson': '{"type":"program","body":[]}',
      });

      expect(envelope.component['type'], equals('Text'));
      expect(envelope.meta?['route'], equals('/home'));
      expect(envelope.navigation?['redirectTo'], equals('/auth'));
      expect(envelope.clientComponents?['profile-card'], isA<Map<String, dynamic>>());
      expect(envelope.jsCode, contains('MainComponent'));
      expect(envelope.jsEntryFunction, equals('MainComponent'));
      expect(envelope.vmAstJson, isNotNull);
    });

    test('throws for invalid payload without component', () {
      expect(
        () => NextjsRenderEnvelope.fromJson({'stylesheet': {}}),
        throwsFormatException,
      );
    });

    test('throws for invalid jsCode type', () {
      expect(
        () => NextjsRenderEnvelope.fromJson({
          'component': {'type': 'Text'},
          'jsCode': {'not': 'string'},
        }),
        throwsFormatException,
      );
    });

    test('throws for invalid jsEntryFunction type', () {
      expect(
        () => NextjsRenderEnvelope.fromJson({
          'component': {'type': 'Text'},
          'jsEntryFunction': 101,
        }),
        throwsFormatException,
      );
    });

    test('throws for invalid clientComponents type', () {
      expect(
        () => NextjsRenderEnvelope.fromJson({
          'component': {'type': 'Text'},
          'clientComponents': 'not-an-object',
        }),
        throwsFormatException,
      );
    });
  });

  group('NextjsBridge', () {
    test('buildRouteRequest keeps route/props/context', () {
      final request = NextjsBridge.buildRouteRequest(
        route: '/dashboard',
        props: const {'userId': 42},
        context: const {'locale': 'en-US'},
      );

      expect(request['route'], equals('/dashboard'));
      expect(request['props']['userId'], equals(42));
      expect(request['context']['locale'], equals('en-US'));
    });
  });

  group('NextjsServerWidget', () {
    test('defaults to routePath request mode for normal Next.js routing', () {
      const widget = NextjsServerWidget(
        route: '/',
        serverBaseUrl: 'https://mini.example.com',
      );

      expect(widget.requestMode, equals(NextjsServerRequestMode.routePath));
      expect(widget.endpoint, isNull);
    });

    test('supports explicit single-endpoint API mode', () {
      const widget = NextjsServerWidget(
        route: '/',
        serverBaseUrl: 'https://mini.example.com',
        requestMode: NextjsServerRequestMode.apiEndpoint,
        endpoint: '/api/elpian-render',
      );

      expect(widget.requestMode, equals(NextjsServerRequestMode.apiEndpoint));
      expect(widget.endpoint, equals('/api/elpian-render'));
    });

    testWidgets('renders server payload with Elpian engine', (tester) async {
      final widget = MaterialApp(
        home: Scaffold(
          body: NextjsServerWidget(
            route: '/welcome',
            loader: (route, {props, headers}) async {
              return {
                'component': {
                  'type': 'Text',
                  'props': {'text': 'Loaded route: $route'},
                },
              };
            },
          ),
        ),
      );

      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      expect(find.text('Loaded route: /welcome'), findsOneWidget);
    });

    testWidgets('resolves packed client component scripts in server hierarchy', (tester) async {
      final widget = MaterialApp(
        home: Scaffold(
          body: NextjsServerWidget(
            route: '/client-demo',
            loader: (route, {props, headers}) async {
              return {
                'component': {
                  'type': 'Column',
                  'children': [
                    {
                      'type': 'Text',
                      'props': {'text': 'Server before'},
                    },
                    {
                      'type': 'clientComp',
                      'componentId': 'counter-main',
                      'props': {'start': 7},
                    },
                    {
                      'type': 'Text',
                      'props': {'text': 'Server after'},
                    },
                  ],
                },
                'clientComponents': {
                  'counter-main': {
                    'jsCode': '''
                      function MainComponent(props){
                        return JSON.stringify({
                          type: "Text",
                          props: {text: "Client count: " + props.start}
                        });
                      }
                    '''
                  }
                },
              };
            },
          ),
        ),
      );

      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      expect(find.text('Server before'), findsOneWidget);
      expect(find.text('Client count: 7'), findsOneWidget);
      expect(find.text('Server after'), findsOneWidget);
    });

    testWidgets('navigates using NextjsLink widget', (tester) async {
      final widget = MaterialApp(
        home: Scaffold(
          body: NextjsServerWidget(
            route: '/',
            loader: (route, {props, headers}) async {
              if (route == '/') {
                return {
                  'component': {
                    'type': 'Column',
                    'children': [
                      {
                        'type': 'Text',
                        'props': {'text': 'Home'}
                      },
                      {
                        'type': 'NextjsLink',
                        'props': {'text': 'Go profile', 'href': '/profile'}
                      }
                    ]
                  },
                };
              }

              return {
                'component': {
                  'type': 'Text',
                  'props': {'text': 'Profile page'},
                },
              };
            },
          ),
        ),
      );

      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      await tester.tap(find.text('Go profile'));
      await tester.pumpAndSettle();

      expect(find.text('Profile page'), findsOneWidget);
    });

    testWidgets('applies server redirect navigation command', (tester) async {
      final widget = MaterialApp(
        home: Scaffold(
          body: NextjsServerWidget(
            route: '/private',
            loader: (route, {props, headers}) async {
              if (route == '/private') {
                return {
                  'component': {
                    'type': 'Text',
                    'props': {'text': 'Redirecting...'},
                  },
                  'navigation': {
                    'redirectTo': '/auth/login',
                    'replace': true,
                  },
                };
              }

              return {
                'component': {
                  'type': 'Text',
                  'props': {'text': 'Auth login'},
                },
              };
            },
          ),
        ),
      );

      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      expect(find.text('Auth login'), findsOneWidget);
    });
  });
}
