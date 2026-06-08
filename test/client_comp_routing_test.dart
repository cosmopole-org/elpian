import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/src/integrations/client_comp_routing.dart';

void main() {
  group('ClientCompRouting.parse', () {
    test('bare handler (page VM) → null', () {
      expect(ClientCompRouting.parse('__h0'), isNull);
      expect(ClientCompRouting.parse('handleClick'), isNull);
    });

    test('namespaced handler → (mountId, fn)', () {
      final r = ClientCompRouting.parse('cc3::__h1');
      expect(r, isNotNull);
      expect(r!.mountId, 'cc3');
      expect(r.fn, '__h1');
    });

    test('round-trips with namespaced()', () {
      final h = ClientCompRouting.namespaced('cc7', '__h2');
      final r = ClientCompRouting.parse(h)!;
      expect(r.mountId, 'cc7');
      expect(r.fn, '__h2');
    });

    test('a leading separator is not treated as a mount route', () {
      expect(ClientCompRouting.parse('::oops'), isNull);
    });
  });

  group('ClientCompRouting.namespaceHandlers', () {
    test('prefixes handlers throughout the tree and is idempotent', () {
      final tree = <String, dynamic>{
        'type': 'div',
        'events': {'click': '__h0'},
        'children': [
          {
            'type': 'button',
            'events': {'click': '__h1', 'pointerdown': '__h2'},
          },
          {
            'type': 'span', // no events — untouched
            'props': {'text': 'hi'},
          },
        ],
      };

      ClientCompRouting.namespaceHandlers(tree, 'cc0');
      expect((tree['events'] as Map)['click'], 'cc0::__h0');
      final btn = (tree['children'] as List)[0] as Map;
      expect((btn['events'] as Map)['click'], 'cc0::__h1');
      expect((btn['events'] as Map)['pointerdown'], 'cc0::__h2');

      // Idempotent: a second pass must not double-prefix.
      ClientCompRouting.namespaceHandlers(tree, 'cc0');
      expect((tree['events'] as Map)['click'], 'cc0::__h0');
      expect((btn['events'] as Map)['click'], 'cc0::__h1');
    });

    test('events belonging to one mount never collide with another', () {
      Map<String, dynamic> node() => {
            'type': 'button',
            'events': {'click': '__h0'},
          };
      final a = ClientCompRouting.namespaceHandlers(node(), 'cc0');
      final b = ClientCompRouting.namespaceHandlers(node(), 'cc1');
      expect((a['events'] as Map)['click'], 'cc0::__h0');
      expect((b['events'] as Map)['click'], 'cc1::__h0');
      // Routing each back resolves to the correct distinct VM.
      expect(ClientCompRouting.parse((a['events'] as Map)['click'])!.mountId, 'cc0');
      expect(ClientCompRouting.parse((b['events'] as Map)['click'])!.mountId, 'cc1');
    });
  });
}
