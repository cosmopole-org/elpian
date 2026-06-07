import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/src/vm/scope_patch.dart';

void main() {
  group('ScopePatch.normalizeKey', () {
    test('trims and rejects empty / "null"', () {
      expect(ScopePatch.normalizeKey(null), isNull);
      expect(ScopePatch.normalizeKey('   '), isNull);
      expect(ScopePatch.normalizeKey('null'), isNull);
      expect(ScopePatch.normalizeKey('  hud  '), 'hud');
    });
  });

  Map<String, dynamic> tree() => {
        'type': 'div',
        'children': [
          {
            'type': 'Scope',
            'key': 'navbar',
            'props': <String, dynamic>{},
            'children': [
              {'type': 'span', 'props': {'text': 'nav'}}
            ],
          },
          {
            'type': 'Scope',
            'key': 'hud',
            'props': <String, dynamic>{},
            'children': [
              {'type': 'span', 'key': 'hud', 'props': {'text': 'old'}}
            ],
          },
        ],
      };

  group('ScopePatch.apply', () {
    test('no scope key → returns the new view (full render)', () {
      final view = {'type': 'div'};
      expect(ScopePatch.apply(tree(), view, null), same(view));
    });

    test('unknown key → returns the new view (caller does full render)', () {
      final view = {'type': 'div', 'key': 'nope'};
      expect(ScopePatch.apply(tree(), view, 'nope'), same(view));
    });

    test('known key → patches subtree in place and bumps enclosing scope token',
        () {
      final t = tree();
      final view = {
        'type': 'span',
        'props': {'text': 'new'},
      };
      final result = ScopePatch.apply(t, view, 'hud');

      // Mutated the original tree in place (same instance returned).
      expect(result, same(t));

      final hudScope = (t['children'] as List)[1] as Map<String, dynamic>;
      // The enclosing Scope's render token was bumped so it rebuilds...
      expect(hudScope['props']['__scopeRenderToken'], isA<int>());
      // ...while the untouched navbar scope keeps no token.
      final navScope = (t['children'] as List)[0] as Map<String, dynamic>;
      expect(navScope['props'].containsKey('__scopeRenderToken'), isFalse);

      // The matched node now carries the new content + its key (for next time).
      final patched = (hudScope['children'] as List)[0] as Map<String, dynamic>;
      expect(patched['props']['text'], 'new');
      expect(patched['key'], 'hud');
    });

    test('every apply produces a strictly increasing token', () {
      final t1 = tree();
      ScopePatch.apply(t1, {'type': 'span'}, 'hud');
      final token1 =
          ((t1['children'] as List)[1] as Map)['props']['__scopeRenderToken'] as int;

      final t2 = tree();
      ScopePatch.apply(t2, {'type': 'span'}, 'hud');
      final token2 =
          ((t2['children'] as List)[1] as Map)['props']['__scopeRenderToken'] as int;

      expect(token2, greaterThan(token1));
    });
  });
}
