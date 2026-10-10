import 'package:elpian_client/main.dart';
import 'package:elpian_ui/elpian_ui.dart';
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

  test('agents default to the manifest app on the serving origin', () {
    final d = agentEndpointDefaults({'app': 'shop', 'client': {}},
        Uri.parse('http://localhost:8080/index.html?x=1'));
    expect(d.appId, 'shop');
    expect(d.baseUrl, 'http://localhost:8080/');
    final nested = agentEndpointDefaults(
        {'app': 'shop'}, Uri.parse('https://host.dev/preview/shop/'));
    expect(nested.baseUrl, 'https://host.dev/preview/shop/');
    // The resolved endpoint the A2UI registry builds from these defaults.
    final registry = A2UIRegistry()
      ..defaults = A2UIDefaults(appId: d.appId, baseUrl: d.baseUrl);
    expect(registry.endpoint('assistant')!.url,
        'http://localhost:8080/apps/shop/agent/assistant');
    expect(agentEndpointDefaults({}, Uri.parse('http://localhost:8080/')).appId,
        isNull);
  });
}
