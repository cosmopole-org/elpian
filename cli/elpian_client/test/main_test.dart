import 'package:elpian_client/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dynamic client content inherits a normal Material text style',
      (tester) async {
    await tester.pumpWidget(const ElpianClientApp());

    final context = tester.element(find.byType(DynamicElpianClient));
    final style = DefaultTextStyle.of(context).style;

    expect(style.decoration, isNot(TextDecoration.underline));
    expect(style.decorationStyle, isNot(TextDecorationStyle.double));
    expect(style.debugLabel, isNot(contains('fallback style')));
  });
}
