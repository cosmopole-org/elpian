import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('NextjsTokenStore (cross-platform)', () {
    test('InMemoryTokenStore stores, reports session, and clears', () async {
      final store = InMemoryTokenStore();
      expect(store.hasSession, isFalse);
      await store.ensureReady(); // no-op, must not throw

      store.save(access: 'a1', refresh: 'r1');
      expect(store.accessToken, 'a1');
      expect(store.refreshToken, 'r1');
      expect(store.hasSession, isTrue);

      // null leaves existing values untouched
      store.save(access: 'a2');
      expect(store.accessToken, 'a2');
      expect(store.refreshToken, 'r1');

      store.clear();
      expect(store.accessToken, isNull);
      expect(store.hasSession, isFalse);
    });

    test('SharedPrefsTokenStore persists + hydrates on every platform', () async {
      // shared_preferences works on web/mobile/desktop; the test backend mocks it.
      SharedPreferences.setMockInitialValues({});
      final store = SharedPrefsTokenStore(namespace: 'test');
      await store.ensureReady();
      store.save(access: 'acc', refresh: 'ref');
      expect(store.accessToken, 'acc');

      // A fresh store of the same namespace restores the persisted session.
      final reopened = SharedPrefsTokenStore(namespace: 'test');
      await reopened.ensureReady();
      expect(reopened.accessToken, 'acc');
      expect(reopened.refreshToken, 'ref');
      expect(reopened.hasSession, isTrue);

      reopened.clear();
      final afterClear = SharedPrefsTokenStore(namespace: 'test');
      await afterClear.ensureReady();
      expect(afterClear.hasSession, isFalse);
    });

    test('ensureReady is idempotent (single hydration)', () async {
      SharedPreferences.setMockInitialValues({'test2_access_token': 'x'});
      final store = SharedPrefsTokenStore(namespace: 'test2');
      final f1 = store.ensureReady();
      final f2 = store.ensureReady();
      expect(identical(f1, f2), isTrue);
      await f1;
      expect(store.accessToken, 'x');
    });
  });

  group('NextjsAuthConfig', () {
    test('defaults to a persistent cross-platform store', () {
      final config = NextjsAuthConfig();
      expect(config.store, isA<SharedPrefsTokenStore>());
      expect(config.loginRoute, '/auth');
      expect(config.refreshRoute, '/auth/refresh');
      expect(config.bearerScheme, 'Bearer');
    });

    test('accepts a custom store and routes', () {
      final store = InMemoryTokenStore();
      final config = NextjsAuthConfig(
        store: store,
        loginRoute: '/login',
        refreshRoute: '/session/refresh',
      );
      expect(identical(config.store, store), isTrue);
      expect(config.loginRoute, '/login');
      expect(config.refreshRoute, '/session/refresh');
    });
  });
}
