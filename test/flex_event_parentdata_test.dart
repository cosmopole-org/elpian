import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:elpian_ui/src/core/elpian_engine.dart';
import 'package:elpian_ui/src/models/elpian_node.dart';

/// Regression: a node that is BOTH a flex child (`flex`/`flex-grow`) AND has an
/// event handler must not crash. The event wrapper (a gesture detector, which
/// owns a RenderObject) used to be placed OUTSIDE the builder's `Flexible`, so
/// the `Flexible`'s `FlexParentData` was applied to the gesture detector instead
/// of the parent `Row`/`Column` — Flutter throws "Incorrect use of
/// ParentDataWidget" and the whole subtree (e.g. a tappable navbar button) fails
/// to render. The fix keeps the `Flexible` outermost and wraps its child.
void main() {
  testWidgets('flex child with a click handler mounts without a ParentData error',
      (tester) async {
    final node = ElpianNode.fromJson({
      'type': 'div',
      'style': {'display': 'flex', 'flexDirection': 'row'},
      'children': [
        {
          'type': 'div',
          // flex child AND tappable — the crashing combination.
          'style': {'flex': 1, 'padding': 8},
          'events': {'click': '__noop'},
          'children': [
            {'type': 'Text', 'props': {'text': 'tap me'}},
          ],
        },
        {
          'type': 'div',
          'style': {'flex': 1},
          'events': {'click': '__noop2'},
          'children': [
            {'type': 'Text', 'props': {'text': 'and me'}},
          ],
        },
      ],
    });

    final errors = <FlutterErrorDetails>[];
    final prev = FlutterError.onError;
    FlutterError.onError = errors.add;

    final engine = ElpianEngine();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(800, 600)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(width: 800, child: engine.renderFromJson(node.toJson())),
        ),
      ),
    );

    FlutterError.onError = prev;

    final parentDataErrors = errors
        .where((e) => '${e.exception}'.contains('ParentDataWidget'))
        .toList();
    expect(parentDataErrors, isEmpty,
        reason: 'flex + event node must not raise a ParentData error');
  });
}
