// Generic auth/token handling for `NextjsServerWidget`.
//
// This is a reusable Elpian feature — not specific to any app. A server that
// returns its issued tokens in the render envelope's `meta.auth`
// (`{ accessToken, refreshToken }`) and gates protected routes with a
// `navigation.redirectTo: <loginRoute>` directive will get, for free:
//   • a bearer `Authorization` header on every request,
//   • automatic capture/persistence of tokens from `meta.auth`,
//   • a silent refresh + retry when a route redirects to the login screen.
//
// The widget also POSTs login/registration forms (`NextjsForm`) and applies the
// resulting `navigation`, so the whole auth flow is handled by the widget.
import 'nextjs_token_persist_stub.dart'
    if (dart.library.html) 'nextjs_token_persist_web.dart' as persist;

/// Storage for the access/refresh token pair.
abstract class NextjsTokenStore {
  String? get accessToken;
  String? get refreshToken;
  bool get hasSession => (accessToken ?? '').isNotEmpty;

  /// Save one or both tokens (null leaves the existing value untouched).
  void save({String? access, String? refresh});

  /// Drop the whole session.
  void clear();
}

/// In-memory token store (session is lost on reload). Works on every platform.
class InMemoryTokenStore implements NextjsTokenStore {
  String? _access;
  String? _refresh;

  @override
  String? get accessToken => _access;
  @override
  String? get refreshToken => _refresh;
  @override
  bool get hasSession => (_access ?? '').isNotEmpty;

  @override
  void save({String? access, String? refresh}) {
    if (access != null) _access = access;
    if (refresh != null) _refresh = refresh;
  }

  @override
  void clear() {
    _access = null;
    _refresh = null;
  }
}

/// Persistent token store. On web it is backed by `localStorage` (so the
/// session survives reloads); on other platforms it falls back to in-memory.
class PersistentTokenStore implements NextjsTokenStore {
  PersistentTokenStore({this.namespace = 'elpian'});

  final String namespace;

  String get _accessKey => '${namespace}_access_token';
  String get _refreshKey => '${namespace}_refresh_token';

  @override
  String? get accessToken => persist.readPersisted(_accessKey);
  @override
  String? get refreshToken => persist.readPersisted(_refreshKey);
  @override
  bool get hasSession => (accessToken ?? '').isNotEmpty;

  @override
  void save({String? access, String? refresh}) {
    if (access != null) persist.writePersisted(_accessKey, access);
    if (refresh != null) persist.writePersisted(_refreshKey, refresh);
  }

  @override
  void clear() {
    persist.writePersisted(_accessKey, null);
    persist.writePersisted(_refreshKey, null);
  }
}

/// Opt-in auth configuration for `NextjsServerWidget`.
class NextjsAuthConfig {
  NextjsAuthConfig({
    NextjsTokenStore? store,
    this.loginRoute = '/auth',
    this.refreshRoute = '/auth/refresh',
    this.bearerScheme = 'Bearer',
  }) : store = store ?? PersistentTokenStore();

  /// Where tokens are kept (defaults to persistent / localStorage on web).
  final NextjsTokenStore store;

  /// The route a protected page redirects to when unauthenticated. When the
  /// server returns `navigation.redirectTo == loginRoute`, the widget attempts a
  /// silent refresh before surfacing the login screen.
  final String loginRoute;

  /// Route that exchanges a refresh token for a fresh access token. Receives a
  /// `{ refreshToken }` POST body and returns the new pair in `meta.auth`.
  final String refreshRoute;

  /// Authorization header scheme (almost always `Bearer`).
  final String bearerScheme;
}
