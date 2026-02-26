import 'package:flutter_test/flutter_test.dart';

import 'package:elpian_ui_example/main.dart';

void main() {
  testWidgets('Elpian example app renders unified demo launcher',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ElpianExamplesApp());
    expect(find.text('Elpian UI Examples'), findsOneWidget);
    expect(find.text('QuickJS Calculator'), findsOneWidget);
    expect(find.text('AST VM'), findsOneWidget);
  });
}
