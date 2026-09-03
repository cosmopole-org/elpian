import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient, SocketException;

import 'package:flutter/foundation.dart';

import 'server_component.dart' show ServerRenderResult;

/// The client half of the Elpian fullstack seam: a mini app's client VM
/// reaching its own server functions.
///
/// # Which app is not a parameter
///
/// A connector is built for one app and carries its id in every URL it
/// constructs. Guest code passes a *function* name and arguments, never an app,
/// so a mini app cannot address another's backend — there is no cross-app check
/// to bypass because there is no argument to forge. The server enforces the
/// same thing independently: it takes the app from the path it routed.
///
/// # The client's network policy is advisory
///
/// [ElpianNetPolicy] lets a well-behaved device apply the app's posture locally
/// — refusing an outbound call a `closed` app should not make, without a round
/// trip. That is a courtesy and a latency saving, **not** the boundary: a device
/// is under the user's control and its policy can be edited or replaced. Every
/// rule here is enforced again on the server, and the server's answer is the one
/// that counts.
class ElpianServerClient {
  ElpianServerClient({
    required this.baseUrl,
    required this.appId,
    this.netPolicy = ElpianNetPolicy.closed,
    this.authorization,
    this.timeout = const Duration(seconds: 15),
    HttpClient? httpClient,
  }) : _client = httpClient ?? HttpClient();

  /// Origin of the host serving this app, e.g. `http://127.0.0.1:4180`.
  final String baseUrl;

  /// The app whose functions this connector reaches. Fixed at construction.
  final String appId;

  /// The app's posture, as advertised by its manifest.
  final ElpianNetPolicy netPolicy;

  /// A credential to present. The host turns it into `ctx.user`; the client
  /// never constructs an identity itself.
  final String? authorization;

  final Duration timeout;
  final HttpClient _client;

  /// Host APIs this connector services, ready for
  /// `ElpianVm.registerHostHandlers`.
  Map<String, Future<String> Function(String, String)> get hostHandlers => {
        'server.call': (api, payload) => _invoke(payload, render: false),
        'server.render': (api, payload) => _invoke(payload, render: true),
        'net.fetch': (api, payload) => _clientFetch(payload),
      };

  Future<String> _invoke(String payload, {required bool render}) async {
    final args = _positional(payload);
    final name = args.isNotEmpty ? args[0] : null;
    if (name is! String || name.isEmpty) {
      return _typedNull();
    }
    final body = args.length > 1 ? args[1] : const <String, dynamic>{};

    final path = render ? 'render' : 'fn';
    // The function name is percent-encoded so it cannot change the *shape* of
    // the path. A name containing `/` would otherwise add a segment, and a URL
    // the guest partly controls must not be able to re-point the request at a
    // different route. (The server refuses the resulting path either way, since
    // it matches routes by segment count — this stops the attempt at the source
    // rather than relying on the far end to notice.)
    final uri = Uri.parse(
        '$baseUrl/apps/${Uri.encodeComponent(appId)}/$path/${Uri.encodeComponent(name)}');

    try {
      final request = await _client.postUrl(uri).timeout(timeout);
      request.headers.set('content-type', 'application/json');
      if (authorization != null) {
        request.headers.set('authorization', authorization!);
      }
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(timeout);
      final text = await utf8.decoder.bind(response).join().timeout(timeout);

      if (response.statusCode != 200) {
        // The server's message is deliberately coarse; pass it through rather
        // than inventing detail the client does not have.
        final message = _errorMessage(text) ?? 'the call failed';
        return _typedError(message);
      }
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['ok'] == true) {
        return _typedValue(decoded['result']);
      }
      return _typedError(_errorMessage(text) ?? 'the call failed');
    } on TimeoutException {
      return _typedError('the server did not answer in time');
    } on SocketException {
      return _typedError('the server could not be reached');
    } catch (error) {
      // Any other transport failure. The guest gets a value it can test, not a
      // throw — its subset has no try/catch, so a throw would simply trap it.
      debugPrint('ElpianServerClient: $appId/$path failed: $error');
      return _typedError('the call failed');
    }
  }

  /// A client-side `net.fetch`, applied against the advisory policy.
  Future<String> _clientFetch(String payload) async {
    final args = _positional(payload);
    final url = args.isNotEmpty ? args[0] : null;
    if (url is! String) return _typedNull();

    if (!netPolicy.allows(url)) {
      // Refused locally, without a round trip. The same call would be refused
      // by the server too — this only saves the trip and the latency.
      return _typedError('the request was not permitted');
    }
    // A device that *is* allowed to reach out still goes through its host's
    // broker rather than opening its own socket, so one policy governs both
    // halves and one audit trail sees both.
    return _invokeProxy(url);
  }

  Future<String> _invokeProxy(String url) async {
    final uri = Uri.parse('$baseUrl/apps/$appId/proxy');
    try {
      final request = await _client.postUrl(uri).timeout(timeout);
      request.headers.set('content-type', 'application/json');
      if (authorization != null) {
        request.headers.set('authorization', authorization!);
      }
      request.add(utf8.encode(jsonEncode({'url': url})));
      final response = await request.close().timeout(timeout);
      final text = await utf8.decoder.bind(response).join().timeout(timeout);
      if (response.statusCode != 200) {
        return _typedError('the request was not permitted');
      }
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['ok'] == true) {
        return _typedValue(decoded['result']);
      }
      return _typedError('the request was not permitted');
    } catch (_) {
      return _typedError('the request was not permitted');
    }
  }

  /// Fetch a server component's payload, for [ServerComponent].
  ///
  /// Returns a result rather than throwing, matching the guest SDK's shape: the
  /// caller is UI code that has to put *something* on screen either way.
  Future<ServerRenderResult> renderComponent(
    String name,
    Map<String, dynamic> args,
  ) async {
    final raw = await _invoke(jsonEncode([name, args]), render: true);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['error'] != null) {
        final error = decoded['error'];
        final message =
            error is Map ? (error['message']?.toString() ?? 'the call failed')
                         : error.toString();
        return ServerRenderResult(error: message);
      }
      if (decoded is Map<String, dynamic>) {
        return ServerRenderResult(payload: decoded);
      }
      return const ServerRenderResult(error: 'the server returned no payload');
    } catch (_) {
      return const ServerRenderResult(error: 'the server returned no payload');
    }
  }

  /// Invoke an action, for UI code that is not going through a guest VM.
  Future<ServerCallResult> callAction(
    String name,
    Map<String, dynamic> args,
  ) async {
    final raw = await _invoke(jsonEncode([name, args]), render: false);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['error'] != null) {
        final error = decoded['error'];
        final message =
            error is Map ? (error['message']?.toString() ?? 'the call failed')
                         : error.toString();
        return ServerCallResult(error: message);
      }
      return ServerCallResult(result: decoded);
    } catch (_) {
      return const ServerCallResult(error: 'the call failed');
    }
  }

  void close() => _client.close(force: true);

  // ---- payload helpers ------------------------------------------------------

  /// The guest passes arguments as an array. Be lenient about a bare value,
  /// which is what a hand-written call looks like.
  List<dynamic> _positional(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is List) return decoded;
      return [decoded];
    } catch (_) {
      return const [];
    }
  }

  String? _errorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } catch (_) {}
    return null;
  }

  /// The VM accepts plain JSON as a host-call reply, so a result is passed
  /// through as it came back.
  String _typedValue(dynamic value) => jsonEncode(value);

  /// An error is a *value*, matching what the guest SDK expects: the subset has
  /// no try/catch, so anything the guest must handle has to be returnable.
  String _typedError(String message) => jsonEncode({
        'error': {'code': 'unavailable', 'message': message}
      });

  String _typedNull() => jsonEncode(null);
}

/// A mini app's client-side network posture.
///
/// Mirrors the server's three modes. It exists so a device can apply the app's
/// own rules without a round trip — and it is advisory, always. The server does
/// not trust a client to have applied it.
class ElpianNetPolicy {
  const ElpianNetPolicy._(this.mode, this.allowlist);

  /// No egress. The app's only reachable peer is its own server functions.
  static const closed = ElpianNetPolicy._('closed', <String>[]);

  /// Unrestricted egress. First-party code and nothing else.
  static const open = ElpianNetPolicy._('open', <String>[]);

  /// Egress only to the listed hosts, through the host's broker.
  factory ElpianNetPolicy.brokered(List<String> allowlist) =>
      ElpianNetPolicy._('brokered', List.unmodifiable(allowlist));

  final String mode;
  final List<String> allowlist;

  /// Read a posture out of an app manifest.
  ///
  /// Anything unrecognised — including absent — is [closed]. The default has to
  /// be the safe one: a manifest whose network stanza was mistyped must not
  /// silently grant egress.
  factory ElpianNetPolicy.fromManifest(dynamic value) {
    if (value == 'open') return open;
    if (value is Map) {
      final allow = (value['allow'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const <String>[];
      return ElpianNetPolicy.brokered(allow);
    }
    return closed;
  }

  bool allows(String url) {
    if (mode == 'closed') return false;
    if (mode == 'open') return true;
    final host = Uri.tryParse(url)?.host;
    if (host == null || host.isEmpty) return false;
    return allowlist.any((entry) => _matches(entry.toLowerCase(), host.toLowerCase()));
  }

  /// Whole-label matching, the same rule the server applies: `*.example.com`
  /// must not match `evil-example.com`, and `example.com` must not match
  /// `notexample.com`.
  static bool _matches(String entry, String host) {
    if (entry.startsWith('*.')) {
      final suffix = entry.substring(2);
      return host != suffix &&
          host.length > suffix.length &&
          host.endsWith(suffix) &&
          host[host.length - suffix.length - 1] == '.';
    }
    return host == entry;
  }
}


/// The result of invoking a server action from Dart.
class ServerCallResult {
  const ServerCallResult({this.result, this.error});

  final dynamic result;

  /// The server's message, or null on success. An error is a *value* here for
  /// the same reason it is in the guest SDK: callers have to render something
  /// either way, and a throw forces every call site into a try/catch that most
  /// of them would get wrong.
  final String? error;

  bool get ok => error == null;
}
