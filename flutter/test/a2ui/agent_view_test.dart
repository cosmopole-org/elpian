import 'dart:async';
import 'dart:convert';

import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _catalog =
    'https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json';

void main() {
  testWidgets(
      'ElpianAgentView sends the prompt, renders the agent surface and reports events',
      (tester) async {
    final key = GlobalKey<ElpianAgentViewState>();
    final requests = <String>[];
    final events = <String>[];

    void Function() fakeAgent(
      AgentEndpoint endpoint,
      String body, {
      required void Function(String chunk) onChunk,
      required void Function() onDone,
      required void Function(String message) onError,
    }) {
      requests.add('${endpoint.url} $body');
      final message = (jsonDecode(body) as Map)['message'];
      final lines = [
        {'type': 'conversation', 'conversationId': 'c1'},
        {
          'version': 'v0.9.1',
          'createSurface': {'surfaceId': 's', 'catalogId': _catalog}
        },
        {
          'version': 'v0.9.1',
          'updateComponents': {
            'surfaceId': 's',
            'components': [
              {'id': 'root', 'component': 'Text', 'text': 'You said: $message'}
            ]
          }
        },
        {'type': 'text', 'text': 'Done.'},
        {'type': 'done', 'stopReason': 'end_turn'},
      ];
      // Delivered in small chunks, split mid-line.
      final ndjson = '${lines.map(jsonEncode).join('\n')}\n';
      scheduleMicrotask(() {
        for (var i = 0; i < ndjson.length; i += 7) {
          onChunk(ndjson.substring(
              i, i + 7 > ndjson.length ? ndjson.length : i + 7));
        }
        onDone();
      });
      return () {};
    }

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ElpianAgentView(
          key: key,
          baseUrl: 'http://host.test',
          appId: 'shop',
          agent: 'assistant',
          prompt: 'Hello',
          fetch: fakeAgent,
          onEvent: (type, payload) =>
              events.add('$type ${jsonEncode(payload)}'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(requests, hasLength(1));
    expect(requests.single,
        startsWith('http://host.test/apps/shop/agent/assistant '));
    expect(find.text('You said: Hello'), findsOneWidget);
    expect(find.text('Done.'), findsOneWidget);
    expect(key.currentState!.conversationId, 'c1');
    expect(events.where((e) => e.startsWith('a2uiDone')), isNotEmpty);
    expect(events.firstWhere((e) => e.startsWith('a2uiText')),
        contains('"text":"Done."'));

    // A follow-up from outside continues the same conversation.
    key.currentState!.send('More');
    await tester.pumpAndSettle();
    expect(requests, hasLength(2));
    expect(
        jsonDecode(
            requests.last.split(' ').skip(1).join(' '))['conversationId'],
        'c1');
    expect(find.text('You said: More'), findsOneWidget);
  });
}
