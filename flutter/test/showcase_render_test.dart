import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';

/// The `showcase` CLI template, rendered from the JSON its guest actually emits.
///
/// Both bugs this guards against produced the *same* symptom — a white screen
/// after the loading spinner — and neither surfaced an error anywhere near its
/// cause, so only an end-to-end render of the real tree catches them:
///
///  * a `Flexible` handed to a parent that is not a `Flex` throws while
///    applying parent data, which aborts the build of the whole subtree;
///  * the guest program trapped before its first `render()`, leaving the host
///    with no view to draw at all (fixed in js2elpian's capture transform).
void main() {
  Map<String, dynamic> loadView() =>
      jsonDecode(File('test/assets/showcase_view.json').readAsStringSync())
          as Map<String, dynamic>;

  testWidgets('the showcase template view renders its 2D chrome',
      (tester) async {
    final engine = ElpianEngine();
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => engine.renderFromJson(loadView())),
    ));
    await tester.pump();

    // A blank screen is the failure being guarded against, so assert on content
    // rather than merely on the absence of an exception.
    expect(find.text('Elpian Showcase'), findsOneWidget);
    expect(find.text('Bodies'), findsWidgets);
    expect(find.text('Recolour'), findsOneWidget);
  });

  testWidgets('a flex child of a non-flex parent degrades instead of blanking',
      (tester) async {
    // CSS ignores `flex` outside a flex container; Flutter would throw. The
    // engine must drop the wrapper and still paint the child.
    final view = {
      'type': 'div',
      'props': {
        'style': {'padding': '14'}
      },
      'children': [
        {
          'type': 'div',
          'props': {
            'style': {'flex': 1}
          },
          'children': [
            {
              'type': 'span',
              'props': {'text': 'still here'},
              'children': <dynamic>[],
            }
          ],
        }
      ],
    };

    final engine = ElpianEngine();
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => engine.renderFromJson(view)),
    ));
    await tester.pump();

    expect(find.text('still here'), findsOneWidget);
  });
}
