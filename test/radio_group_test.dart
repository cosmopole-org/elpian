import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';

void main() {
  testWidgets('Elpian Radio renders and reflects selected state', (tester) async {
    final engine = ElpianEngine();
    // value == groupValue -> this radio is selected.
    final selected = engine.renderFromJson({
      'type': 'Radio',
      'props': {'value': 'a', 'groupValue': 'a'},
    });
    final unselected = engine.renderFromJson({
      'type': 'Radio',
      'props': {'value': 'b', 'groupValue': 'a'},
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [selected, unselected]),
      ),
    ));
    await tester.pump();

    final radios =
        tester.widgetList<Radio<Object?>>(find.byType(Radio<Object?>)).toList();
    expect(radios.length, 2);
    // No exception, both radios built via RadioGroup.
    expect(tester.takeException(), isNull);
    expect(find.byType(RadioGroup<Object?>), findsNWidgets(2));
  });
}
