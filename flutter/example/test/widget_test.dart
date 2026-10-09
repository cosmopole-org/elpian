import 'package:flutter_test/flutter_test.dart';

import 'package:elpian_ui_example/main.dart';

void main() {
  // The launcher's entries are asserted by their labels, which is what a user
  // reads. That makes this test break when a renderer is renamed or dropped —
  // which is what it is for: it named "Bevy (Rust)" and "Impeller (Dart)" long
  // after both were replaced by the embedded Godot Scene3D, and nothing said
  // so, because the example package's tests were not in any local loop.
  testWidgets('Elpian example app renders the Scene3D launcher',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ElpianGameApp());
    expect(find.text('ELPIAN STRIKE FORCE'), findsOneWidget);
    expect(find.text('Showcase — 2D GUI + Scene3D'), findsOneWidget);
    expect(find.text('Scene3D — embedded Godot'), findsOneWidget);
  });
}
