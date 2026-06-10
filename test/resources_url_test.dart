// Server-relative resource URLs (img src "/icons/x.png") must resolve against
// the render server's origin, not the Flutter asset bundle.

import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';

void main() {
  tearDown(() => ElpianResources.baseUrl = null);

  test('absolute and data URLs pass through', () {
    ElpianResources.baseUrl = 'https://game.example.com';
    expect(ElpianResources.resolve('https://cdn.x/y.png'), 'https://cdn.x/y.png');
    expect(ElpianResources.resolve('data:image/png;base64,AA=='),
        'data:image/png;base64,AA==');
  });

  test('root-relative and relative resolve against baseUrl', () {
    ElpianResources.baseUrl = 'https://game.example.com';
    expect(ElpianResources.resolve('/favicon.png'),
        'https://game.example.com/favicon.png');
    expect(ElpianResources.resolve('img/logo.png'),
        'https://game.example.com/img/logo.png');
  });

  test('asset: scheme stays an asset reference', () {
    ElpianResources.baseUrl = 'https://game.example.com';
    final r = ElpianResources.resolve('asset:images/x.png');
    expect(r, 'asset:images/x.png');
    expect(ElpianResources.isNetwork(r), isFalse);
  });
}
