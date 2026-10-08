// Generic, cross-platform auth/token handling for `NextjsServerWidget`.
//
// This is a reusable Elpian feature — not specific to any app — and works
// identically on **web, Android, iOS, macOS, Windows and Linux**. A server that
// returns its issued tokens in the render envelope's `meta.auth`
// (`{ accessToken, refreshToken }`) and gates protected routes with a
// `navigation.redirectTo: <loginRoute>` directive gets, for free:
//   • a bearer `Authorization` header on every request,
//   • automatic capture + persistence of tokens from `meta.auth`,
//   • a silent refresh + retry when a route redirects to the login screen.
//
// Persistence uses `shared_preferences`, so a session survives app restarts on
// every platform (localStorage on web, native key-value stores elsewhere).
import 'package:shared_preferences/shared_preferences.dart';

/// Storage for the access/refresh token pair.
///
/// Getters are synchronous (the widget needs the token when building request
/// headers); implementations that persist asynchronously hydrate an in-memory
/// cache via [ensureReady] and write through on [save].
abstract class NextjsTokenStore {
  String? get accessToken;
  String? get refreshToken;
  bool get hasSession => (accessToken ?? '').isNotEmpty;

  /// Hydrate from persistent storage before first use. Idempotent; safe to call
  /// repeatedly. The default is a no-op (nothing to hydrate).
  Future<void> ensureReady() async {}

  /// Save one or both tokens (null leaves the existing value untouched).
  void save({String? access, String? refresh});

  /// Drop the whole session.
  void clear();
}

/// In-memory token store (session is lost on restart). Works on every platform;
/// useful for tests or when persistence is not wanted.
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
  Future<void> ensureReady() async {}

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

/// Cross-platform persistent token store backed by `shared_preferences`.
///
/// Tokens are cached in memory (so getters stay synchronous) and written
/// through to persistent storage on every change. Call [ensureReady] once
/// before the first request to restore a session from a previous run.
class SharedPrefsTokenStore implements NextjsTokenStore {
  SharedPrefsTokenStore({this.namespace = 'elpian'});

  final String namespace;

  String get _accessKey => '${namespace}_access_token';
  String get _refreshKey => '${namespace}_refresh_token';

  SharedPreferences? _prefs;
  String? _access;
  String? _refresh;
  Future<void>? _ready;

  @override
  String? get accessToken => _access;
  @override
  String? get refreshToken => _refresh;
  @override
  bool get hasSession => (_access ?? '').isNotEmpty;

  @override
  Future<void> ensureReady() {
    return _ready ??= _hydrate();
  }

  Future<void> _hydrate() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _access = _prefs!.getString(_accessKey);
      _refresh = _prefs!.getString(_refreshKey);
    } catch (_) {
      // Persistence unavailable on this platform → degrade to in-memory.
      _prefs = null;
    }
  }

  @override
  void save({String? access, String? refresh}) {
    if (access != null) {
      _access = access;
      _prefs?.setString(_accessKey, access);
    }
    if (refresh != null) {
      _refresh = refresh;
      _prefs?.setString(_refreshKey, refresh);
    }
  }

  @override
  void clear() {
    _access = null;
    _refresh = null;
    _prefs?.remove(_accessKey);
    _prefs?.remove(_refreshKey);
  }
}

/// Opt-in auth configuration for `NextjsServerWidget`.
class NextjsAuthConfig {
  NextjsAuthConfig({
    NextjsTokenStore? store,
    this.loginRoute = '/auth',
    this.refreshRoute = '/auth/refresh',
    this.bearerScheme = 'Bearer',
  }) : store = store ?? SharedPrefsTokenStore();

  /// Where tokens are kept (defaults to cross-platform persistent storage).
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
