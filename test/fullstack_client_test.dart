import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The client half of the fullstack seam, driven against a stand-in host.
///
/// The Rust side has its own end-to-end tests against the real `elpiand`; these
/// pin the *Dart* behaviour — that a failure is a value rather than a throw,
/// that a stale response cannot overwrite a newer one, that a failed
/// revalidation keeps working content on screen, and that the advisory network
/// policy matches the rule the server applies.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The test binding installs an HttpOverrides that answers every request with
  // 400 and never opens a socket. These tests drive a real loopback server on
  // purpose — the point is to exercise the connector's actual transport, not a
  // mock of it — so the override is removed for this suite.
  setUpAll(() => HttpOverrides.global = null);

  late HttpServer server;
  late String baseUrl;
  // Set by each test to control what the stand-in host answers.
  late Future<Map<String, dynamic>> Function(String path, int callNumber) reply;
  var callCount = 0;

  setUp(() async {
    callCount = 0;
    reply = (path, n) async => {'ok': true, 'result': null};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      final n = ++callCount;
      await utf8.decoder.bind(request).join();
      final body = await reply(request.uri.path, n);
      final status = body.remove('_status') as int? ?? 200;
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(body));
      await request.response.close();
    });
  });

  tearDown(() async => server.close(force: true));

  ElpianServerClient clientFor({String app = 'notes'}) =>
      ElpianServerClient(baseUrl: baseUrl, appId: app);

  // ---- the connector ------------------------------------------------------

  test('an action returns its result', () async {
    reply = (path, n) async => {
          'ok': true,
          'result': {'id': 7}
        };
    final result = await clientFor().callAction('createNote', {'title': 'x'});
    expect(result.ok, isTrue);
    expect(result.result, {'id': 7});
  });

  test('a failure is a value, never a throw', () async {
    // The guest subset has no try/catch, and UI code has to render something
    // either way — so every failure comes back as a result.
    reply = (path, n) async => {'_status': 500, 'error': 'the function failed'};
    final result = await clientFor().callAction('boom', const {});
    expect(result.ok, isFalse);
    expect(result.error, 'the function failed');
  });

  test('an unreachable host is a value too', () async {
    final unreachable =
        ElpianServerClient(baseUrl: 'http://127.0.0.1:1', appId: 'notes');
    final result = await unreachable.callAction('anything', const {});
    expect(result.ok, isFalse);
    expect(result.error, isNotNull);
    unreachable.close();
  });

  test('the app id comes from the connector, never from guest arguments',
      () async {
    // A guest passes a function name and arguments. There is no argument that
    // could name another app, which is the whole of the isolation story on this
    // side — and the server enforces it again from the path it routed.
    String? seenPath;
    reply = (path, n) async {
      seenPath = path;
      return {'ok': true, 'result': null};
    };
    await clientFor(app: 'mine').callAction('victim/secret', const {});
    expect(seenPath, '/apps/mine/fn/victim%2Fsecret');
    expect(seenPath, isNot(contains('/apps/victim/')));
  });

  // ---- the advisory policy ------------------------------------------------

  group('ElpianNetPolicy', () {
    test('closed allows nothing', () {
      expect(ElpianNetPolicy.closed.allows('https://example.com/'), isFalse);
      expect(ElpianNetPolicy.closed.allows('http://127.0.0.1/'), isFalse);
    });

    test('an allowlist matches whole labels only', () {
      final policy =
          ElpianNetPolicy.brokered(['example.com', '*.api.example.com']);
      expect(policy.allows('https://example.com/x'), isTrue);
      expect(policy.allows('https://v1.api.example.com/x'), isTrue);

      // The same rules the Rust broker applies. A mismatch between the two
      // would mean a device silently allowing what the server refuses, which
      // reads to an author as an intermittent failure.
      expect(policy.allows('https://notexample.com/'), isFalse);
      expect(policy.allows('https://example.com.evil.net/'), isFalse);
      expect(policy.allows('https://evil-api.example.com/'), isFalse);
      expect(policy.allows('https://api.example.com/'), isFalse,
          reason: 'the bare suffix is not a subdomain of itself');
    });

    test('an unrecognised manifest stanza is closed, not open', () {
      // The default has to be the safe one: a mistyped network stanza must not
      // silently grant egress.
      expect(ElpianNetPolicy.fromManifest(null).mode, 'closed');
      expect(ElpianNetPolicy.fromManifest('nonsense').mode, 'closed');
      expect(ElpianNetPolicy.fromManifest('closed').mode, 'closed');
      expect(ElpianNetPolicy.fromManifest('open').mode, 'open');
      expect(
        ElpianNetPolicy.fromManifest({
          'allow': ['api.example.com']
        }).mode,
        'brokered',
      );
    });
  });

  // ---- the widget ---------------------------------------------------------
  //
  // These exercise the widget's own logic — the pending state, the error path,
  // the generation guard, and what happens to on-screen content when a
  // revalidation fails. The transport is covered by the connector tests above;
  // driving real sockets from inside `testWidgets`' fake-async zone would test
  // the zone more than the widget.

  testWidgets('a server component renders the payload it was given',
      (tester) async {
    final client = _StubClient()
      ..next = (n) async => const ServerRenderResult(payload: {
            'component': {
              'type': 'Text',
              'props': {'text': 'from the server'}
            }
          });

    await tester.pumpWidget(MaterialApp(
      home: ServerComponent(client: client, name: 'NoteList'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('from the server'), findsOneWidget);
  });

  testWidgets('the pending widget shows only until the first payload arrives',
      (tester) async {
    final gate = Completer<void>();
    final client = _StubClient()
      ..next = (n) async {
        await gate.future;
        return const ServerRenderResult(payload: {
          'component': {
            'type': 'Text',
            'props': {'text': 'arrived'}
          }
        });
      };

    await tester.pumpWidget(MaterialApp(
      home: ServerComponent(
        client: client,
        name: 'NoteList',
        pending: const Text('loading'),
      ),
    ));
    await tester.pump();
    expect(find.text('loading'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('arrived'), findsOneWidget);
    expect(find.text('loading'), findsNothing);
  });

  testWidgets('a failed first render shows the error builder', (tester) async {
    final client = _StubClient()
      ..next =
          (n) async => const ServerRenderResult(error: 'the function failed');

    await tester.pumpWidget(MaterialApp(
      home: ServerComponent(
        client: client,
        name: 'NoteList',
        errorBuilder: (context, message) => Text('failed: $message'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('failed: the function failed'), findsOneWidget);
  });

  testWidgets('a failed revalidation keeps the content already on screen',
      (tester) async {
    // Losing working content because a refresh failed is worse than showing
    // content that is a second old.
    final client = _StubClient()
      ..next = (n) async => n == 1
          ? const ServerRenderResult(payload: {
              'component': {
                'type': 'Text',
                'props': {'text': 'still good'}
              }
            })
          : const ServerRenderResult(error: 'the function failed');

    await tester.pumpWidget(MaterialApp(
      home: ServerComponent(
        client: client,
        name: 'NoteList',
        revalidate: const Duration(milliseconds: 50),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('still good'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    expect(client.calls, greaterThan(1), reason: 'a revalidation fired');
    expect(find.text('still good'), findsOneWidget,
        reason: 'a failed refresh must not blank working content');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a slow earlier response cannot overwrite a newer one',
      (tester) async {
    // Two fetches can be in flight when arguments change, and they can finish
    // out of order. Without a generation guard the slower — older — answer wins
    // and the component shows stale content nothing will correct.
    final slow = Completer<void>();
    final client = _StubClient()
      ..next = (n) async {
        if (n == 1) {
          await slow.future;
          return const ServerRenderResult(payload: {
            'component': {
              'type': 'Text',
              'props': {'text': 'stale'}
            }
          });
        }
        return const ServerRenderResult(payload: {
          'component': {
            'type': 'Text',
            'props': {'text': 'fresh'}
          }
        });
      };

    await tester.pumpWidget(MaterialApp(
      home: ServerComponent(
          client: client, name: 'Panel', args: const {'page': 1}),
    ));
    await tester.pump();

    // Change the arguments, starting a second fetch that finishes first.
    await tester.pumpWidget(MaterialApp(
      home: ServerComponent(
          client: client, name: 'Panel', args: const {'page': 2}),
    ));
    await tester.pumpAndSettle();
    expect(find.text('fresh'), findsOneWidget);

    // Now let the first, older fetch land.
    slow.complete();
    await tester.pumpAndSettle();
    expect(find.text('fresh'), findsOneWidget,
        reason: 'the older response must not win by arriving later');
    expect(find.text('stale'), findsNothing);
  });
}

/// A connector whose answers the test chooses.
///
/// Subclassing the real client rather than introducing an interface keeps the
/// production type as the one thing callers see, and keeps this stub honest
/// about what it is standing in for.
class _StubClient extends ElpianServerClient {
  _StubClient() : super(baseUrl: 'http://127.0.0.1:1', appId: 'stub');

  late Future<ServerRenderResult> Function(int callNumber) next;
  int calls = 0;

  @override
  Future<ServerRenderResult> renderComponent(
    String name,
    Map<String, dynamic> args,
  ) {
    calls += 1;
    return next(calls);
  }
}
