// Tritonias Elpian host — a minimal Flutter shell that points the
// `NextjsServerWidget` black-box client at the Tritonias Next.js render layer
// (`/elpian/**`) and renders whatever envelopes it returns. Used for the
// end-to-end render check.
//
// It supplies a CUSTOM loader (the transport hook the integration plan calls
// for, `refactor/06`) that:
//   • preserves the `/elpian` path prefix — the widget's default loader does
//     `Uri.resolve('/route')`, which would drop the prefix and hit legacy HTML;
//   • injects the `Authorization: Bearer <token>` header on every request.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:elpian_ui/elpian_ui.dart';

String _cfg(String envKey, String defineValue, String fallback) {
  final env = Platform.environment[envKey];
  if (env != null && env.isNotEmpty) return env;
  if (defineValue.isNotEmpty) return defineValue;
  return fallback;
}

final String kServerBaseUrl = _cfg('TRITONIAS_SERVER',
    const String.fromEnvironment('SERVER'), 'http://127.0.0.1:3000/elpian');
final String kToken =
    _cfg('TRITONIAS_TOKEN', const String.fromEnvironment('TOKEN'), '');
final String kRoute =
    _cfg('TRITONIAS_ROUTE', const String.fromEnvironment('ROUTE'), '/city');

/// Custom payload loader: `serverBaseUrl + route` (prefix-preserving) + bearer.
Future<Map<String, dynamic>> tritoniasLoader(
  String route, {
  Map<String, dynamic>? props,
  Map<String, String>? headers,
}) async {
  final base = kServerBaseUrl.endsWith('/')
      ? kServerBaseUrl.substring(0, kServerBaseUrl.length - 1)
      : kServerBaseUrl;
  final path = route.startsWith('/') ? route : '/$route';
  final uri = Uri.parse('$base$path');

  final client = HttpClient();
  try {
    final req = await client.getUrl(uri);
    req.headers.set('accept', 'application/vnd.elpian+json, application/json');
    req.headers.set('x-elpian-route', route);
    if (kToken.isNotEmpty) {
      req.headers.set('authorization', 'Bearer $kToken');
    }
    headers?.forEach(req.headers.set);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('GET $uri → HTTP ${res.statusCode}: $body');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Envelope must decode to a JSON object.');
    }
    return decoded;
  } finally {
    client.close(force: true);
  }
}

void main() {
  runApp(const TritoniasHostApp());
}

class TritoniasHostApp extends StatelessWidget {
  const TritoniasHostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tritonias (Elpian host)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0A1626),
      ),
      home: Scaffold(
        body: NextjsServerWidget(
          route: kRoute,
          serverBaseUrl: kServerBaseUrl,
          loader: tritoniasLoader,
          loadingBuilder: (context) => const Center(
            child: Text('Loading Tritonias…',
                style: TextStyle(color: Color(0xFFE6F0FF))),
          ),
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Render error:\n$error',
                  style: const TextStyle(color: Color(0xFFE53935))),
            ),
          ),
        ),
      ),
    );
  }
}
