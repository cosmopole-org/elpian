// Tritonias standalone Elpian **web** host.
//
// Served by the Next.js server at the site root. It renders the Tritonias game
// entirely through Elpian's `NextjsServerWidget`, talking to the same-origin
// `/elpian/**` render layer (so no CORS). It implements the auth transport the
// refactor plan calls for (`refactor/06`): a token store (localStorage), a
// bearer-injecting loader, and silent access-token refresh.
//
// Build: flutter build web --base-href /app/ -t lib/main_tritonias_web.dart
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:elpian_ui/elpian_ui.dart';

/// Same-origin Elpian render base, e.g. `https://tritonias.example/elpian`.
final String kServerBase = '${Uri.base.origin}/elpian';

/// Persistent token store backed by browser localStorage.
class TokenStore {
  static const _access = 'tritonias_access_token';
  static const _refresh = 'tritonias_refresh_token';

  static String? get accessToken => html.window.localStorage[_access];
  static String? get refreshToken => html.window.localStorage[_refresh];
  static bool get hasSession => (accessToken ?? '').isNotEmpty;

  static void save({String? access, String? refresh}) {
    if (access != null) html.window.localStorage[_access] = access;
    if (refresh != null) html.window.localStorage[_refresh] = refresh;
  }

  static void clear() {
    html.window.localStorage.remove(_access);
    html.window.localStorage.remove(_refresh);
  }
}

/// Notifies the app shell when the session is lost (so it can show login).
final ValueNotifier<bool> kSessionValid = ValueNotifier<bool>(TokenStore.hasSession);

Uri _routeUri(String route) =>
    Uri.parse('$kServerBase${route.startsWith('/') ? route : '/$route'}');

Map<String, String> _authHeaders([Map<String, String>? extra]) => {
      'accept': 'application/vnd.elpian+json, application/json',
      if (TokenStore.accessToken != null)
        'authorization': 'Bearer ${TokenStore.accessToken}',
      ...?extra,
    };

/// Attempt a silent access-token refresh using the stored refresh token.
/// Returns true on success (new tokens stored).
Future<bool> _tryRefresh() async {
  final rt = TokenStore.refreshToken;
  if (rt == null || rt.isEmpty) return false;
  try {
    final res = await http.post(
      _routeUri('/auth/refresh'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'refreshToken': rt}),
    );
    final env = jsonDecode(res.body) as Map<String, dynamic>;
    final auth = (env['meta'] as Map?)?['auth'];
    if (auth is Map && auth['accessToken'] != null) {
      TokenStore.save(
        access: auth['accessToken'] as String,
        refresh: auth['refreshToken'] as String?,
      );
      return true;
    }
  } catch (_) {/* fall through */}
  return false;
}

/// Custom payload loader: same-origin GET with bearer; on an auth redirect it
/// silently refreshes and retries once, else drops the session → login screen.
Future<Map<String, dynamic>> tritoniasLoader(
  String route, {
  Map<String, dynamic>? props,
  Map<String, String>? headers,
}) async {
  Future<Map<String, dynamic>> fetch() async {
    final res = await http.get(_routeUri(route), headers: _authHeaders(headers));
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Envelope must be a JSON object.');
    }
    return decoded;
  }

  var env = await fetch();
  final nav = env['navigation'];
  final redirectingToAuth =
      nav is Map && nav['redirectTo'] == '/auth';
  if (redirectingToAuth) {
    if (await _tryRefresh()) {
      env = await fetch();
    } else {
      TokenStore.clear();
      kSessionValid.value = false;
    }
  }
  return env;
}

/// POST a sign-in and persist the issued tokens. Returns an error string or null.
Future<String?> signIn(String email, String password) async {
  try {
    final res = await http.post(
      _routeUri('/auth/signin'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    final env = jsonDecode(res.body) as Map<String, dynamic>;
    final auth = (env['meta'] as Map?)?['auth'];
    if (res.statusCode == 200 && auth is Map && auth['accessToken'] != null) {
      TokenStore.save(
        access: auth['accessToken'] as String,
        refresh: auth['refreshToken'] as String?,
      );
      kSessionValid.value = true;
      return null;
    }
    // Error envelope renders a toast component with the message text.
    return _extractToastText(env) ?? 'Sign-in failed (HTTP ${res.statusCode}).';
  } catch (e) {
    return 'Network error: $e';
  }
}

/// POST a sign-up. Returns a status/error message (verification required, etc.).
Future<String> signUp(String email, String username, String password) async {
  try {
    final res = await http.post(
      _routeUri('/auth/signup'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'email': email, 'username': username, 'password': password}),
    );
    final env = jsonDecode(res.body) as Map<String, dynamic>;
    return _extractToastText(env) ??
        (res.statusCode == 200 ? 'Account created — verify your email, then sign in.' : 'Sign-up failed.');
  } catch (e) {
    return 'Network error: $e';
  }
}

/// Pull the human text out of a toast-component envelope (best-effort).
String? _extractToastText(Map<String, dynamic> env) {
  String? walk(dynamic node) {
    if (node is Map) {
      final props = node['props'];
      if (props is Map && props['text'] is String) {
        final t = props['text'] as String;
        if (t.length > 3 && !t.contains('✕')) return t;
      }
      for (final c in (node['children'] as List? ?? const [])) {
        final r = walk(c);
        if (r != null) return r;
      }
    }
    return null;
  }

  return walk(env['component']);
}

void main() {
  runApp(const TritoniasApp());
}

class TritoniasApp extends StatelessWidget {
  const TritoniasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tritonias',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0A1626),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD4A017),
          brightness: Brightness.dark,
        ),
      ),
      home: ValueListenableBuilder<bool>(
        valueListenable: kSessionValid,
        builder: (context, valid, _) =>
            valid ? const GameView() : const LoginScreen(),
      ),
    );
  }
}

/// The full game, rendered by Elpian from the `/elpian/city` route. Navigation
/// (navbar links, panels) is driven by `NextjsLink` taps inside the engine.
class GameView extends StatelessWidget {
  const GameView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: NextjsServerWidget(
              route: '/city',
              serverBaseUrl: kServerBase,
              loader: tritoniasLoader,
              loadingBuilder: (context) => const Center(
                child: CircularProgressIndicator(color: Color(0xFFD4A017)),
              ),
              errorBuilder: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Could not load the game:\n$error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFE53935))),
                ),
              ),
            ),
          ),
          Positioned(
            top: 10,
            right: 12,
            child: TextButton.icon(
              onPressed: () {
                TokenStore.clear();
                kSessionValid.value = false;
              },
              icon: const Icon(Icons.logout, size: 16, color: Color(0xFF8DA2BC)),
              label: const Text('Sign out',
                  style: TextStyle(color: Color(0xFF8DA2BC))),
            ),
          ),
        ],
      ),
    );
  }
}

/// Native sign-in / sign-up gate (the Elpian auth form's QuickJS `submit` host
/// hook is not wired, so auth is handled here, then the Elpian game is shown).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _signup = false;
  bool _busy = false;
  String? _message;

  static const _gold = Color(0xFFD4A017);
  static const _panel = Color(0xFF0E1F33);
  static const _border = Color(0xFF1C3450);
  static const _text = Color(0xFFE6F0FF);
  static const _muted = Color(0xFF8DA2BC);

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    if (_signup) {
      final msg = await signUp(_email.text.trim(), _username.text.trim(), _password.text);
      setState(() {
        _busy = false;
        _message = msg;
      });
    } else {
      final err = await signIn(_email.text.trim(), _password.text);
      setState(() {
        _busy = false;
        _message = err;
      });
      // On success the ValueListenable swaps to the game automatically.
    }
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _muted),
        filled: true,
        fillColor: const Color(0xFF0A1626),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _gold),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            width: 380,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: _panel,
              border: Border.all(color: _border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_signup ? 'Join Tritonias' : 'Welcome back',
                    style: const TextStyle(
                        color: _gold,
                        fontSize: 24,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                    _signup
                        ? 'Found your first city and rise to power.'
                        : 'Sign in to command your islands.',
                    style: const TextStyle(color: _muted, fontSize: 14)),
                const SizedBox(height: 20),
                TextField(controller: _email, style: const TextStyle(color: _text), decoration: _dec('Email')),
                if (_signup) ...[
                  const SizedBox(height: 12),
                  TextField(controller: _username, style: const TextStyle(color: _text), decoration: _dec('Username')),
                ],
                const SizedBox(height: 12),
                TextField(controller: _password, obscureText: true, style: const TextStyle(color: _text), decoration: _dec('Password')),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: const Color(0xFF1A1206),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _busy ? null : _submit,
                    child: Text(_busy ? '…' : (_signup ? 'Create Account' : 'Sign In'),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(_message!, style: const TextStyle(color: Color(0xFFF9A825), fontSize: 13)),
                ],
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => setState(() {
                    _signup = !_signup;
                    _message = null;
                  }),
                  child: Text(
                      _signup ? 'Already have an account? Sign in' : 'Create an account',
                      style: const TextStyle(color: Color(0xFF039BE5))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
