import 'package:flutter_test/flutter_test.dart';

import 'package:elpian_ui_example/main.dart';

void main() {
  testWidgets('Elpian example app renders the TPS renderer launcher',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ElpianGameApp());
    expect(find.text('ELPIAN STRIKE FORCE'), findsOneWidget);
    expect(find.text('Play — Bevy (Rust)'), findsOneWidget);
    expect(find.text('Play — Impeller (Dart)'), findsOneWidget);
  });
}
