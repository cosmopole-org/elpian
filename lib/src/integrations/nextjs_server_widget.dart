import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/event_system.dart';
import '../css/css_parser.dart';
import '../vm/elpian_vm.dart';
import '../vm/host_api_catalog.dart';
import '../vm/host_handler.dart';
import '../vm/quickjs_vm.dart';
import '../vm/scope_patch.dart';
import '../vm/timer_host_api.dart';
import '../vm/vm_runtime_client.dart';
import 'client_comp_routing.dart';
import 'nextjs_auth.dart';
import 'nextjs_bridge.dart';

export 'nextjs_auth.dart';

typedef NextjsPayloadLoader = Future<Map<String, dynamic>> Function(
  String route, {
  Map<String, dynamic>? props,
  Map<String, String>? headers,
});

enum NextjsServerRequestMode {
  routePath,
  apiEndpoint,
}

class NextjsScriptExecutionResult {
  const NextjsScriptExecutionResult({
    required this.route,
    required this.kind,
    required this.output,
  });

  final String route;
  final String kind;
  final String output;
}

class NextjsServerWidget extends StatefulWidget {
  const NextjsServerWidget({
    super.key,
    required this.route,
    this.serverBaseUrl,
    this.endpoint,
    this.requestMode = NextjsServerRequestMode.routePath,
    this.loader,
    this.props,
    this.headers,
    this.bridge,
    this.authConfig,
    this.timeout = const Duration(minutes: 2),
    this.loadingBuilder,
    this.errorBuilder,
    this.onScriptExecuted,
    this.onScriptError,
  }) : assert(
          loader != null || serverBaseUrl != null,
          'Either provide loader or serverBaseUrl for automatic Next.js loading.',
        );

  final String route;
  final String? serverBaseUrl;
  final String? endpoint;
  final NextjsServerRequestMode requestMode;
  final NextjsPayloadLoader? loader;
  final Map<String, dynamic>? props;
  final Map<String, String>? headers;
  final NextjsBridge? bridge;

  /// Opt-in auth: bearer injection, `meta.auth` capture, silent refresh, and
  /// POSTing `NextjsForm`s (login/register) through to action routes.
  final NextjsAuthConfig? authConfig;

  /// Per-request timeout for every Next.js round-trip (route GET, action POST,
  /// silent refresh, client-component fetch). Defaults to 2 minutes to match the
  /// Next.js route handlers' `maxDuration = 120` budget — slow mobile links and
  /// cold serverless renders routinely need well over the old 15s ceiling.
  final Duration timeout;
  final WidgetBuilder? loadingBuilder;
  final Widget Function(BuildContext context, Object error)? errorBuilder;
  final ValueChanged<NextjsScriptExecutionResult>? onScriptExecuted;
  final void Function(Object error, StackTrace stackTrace)? onScriptError;

  @override
  State<NextjsServerWidget> createState() => _NextjsServerWidgetState();
}

class _NextjsServerWidgetState extends State<NextjsServerWidget> {
  late Future<Map<String, dynamic>> _payloadFuture;
  late NextjsBridge _bridge;
  late String _currentRoute;
  final List<String> _history = <String>[];

  String? _lastScriptSignature;
  static bool _elpianVmInitialized = false;
  Map<String, dynamic>? _scriptRenderedComponent;
  final Map<String, Map<String, dynamic>> _clientComponentCache =
      <String, Map<String, dynamic>>{};

  /// The component tree from the most recent server payload. Scoped client
  /// renders patch *this* tree so a local mutation (a HUD tick, a tab switch)
  /// only rebuilds its `Scope` subtree instead of the whole screen.
  Map<String, dynamic>? _lastEnvelopeComponent;

  /// The last fully-rendered component tree, retained across a navigation so the
  /// previous screen stays painted while the next route loads — instead of a
  /// full-screen spinner that tears down (and on city/world screens, reloads)
  /// the 3D scene on every tap.
  Map<String, dynamic>? _previousComponent;

  /// Long-lived VM for the page-level client script. Unlike one-shot client
  /// component resolution, this stays alive for the duration of the route so
  /// its timers keep ticking and its event handlers keep firing — the engine of
  /// scoped, in-place updates.
  VmRuntimeClient? _pageVm;
  VmTimerHostApi? _pageTimerApi;

  /// Live, persistent VMs for inline `clientComp` nodes (a tab strip, a
  /// draggable window), keyed by a per-render mount id. Each one stays alive for
  /// the route so its event handlers and timers keep firing, and every render it
  /// pushes is patched in place at its OWN mount scope — so a tap on a tab or a
  /// drag repaints just that component's subtree, never the whole screen.
  ///
  /// This is what makes client interactivity *bounded*: previously these scripts
  /// ran once in a throwaway VM that was disposed immediately, so their handlers
  /// were dead and the only way to change anything was a full-route navigation.
  final Map<String, _LiveClientComp> _liveClientComps =
      <String, _LiveClientComp>{};
  int _clientCompSeq = 0;
  bool _eventRoutingWired = false;

  @override
  void initState() {
    super.initState();
    _currentRoute = widget.route;
    _bridge = widget.bridge ?? NextjsBridge();
    _bridge.onNavigate = _handleNavigate;
    _bridge.onSubmit = _handleFormSubmit;
    // Route engine UI events once, up front — to live `clientComp` VMs and/or
    // the page VM. Wiring it here (not only when a page script runs) means a
    // panel with no poller still delivers taps to its window/tab components.
    _wireEventRouting();
    _payloadFuture = _loadPayload();
  }

  @override
  void didUpdateWidget(covariant NextjsServerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.bridge != oldWidget.bridge && widget.bridge != null) {
      _bridge = widget.bridge!;
      _bridge.onNavigate = _handleNavigate;
      _bridge.onSubmit = _handleFormSubmit;
    }

    if (widget.route != oldWidget.route) {
      _navigateTo(widget.route, replace: true);
      return;
    }

    if (widget.loader != oldWidget.loader ||
        widget.serverBaseUrl != oldWidget.serverBaseUrl ||
        widget.endpoint != oldWidget.endpoint ||
        widget.requestMode != oldWidget.requestMode ||
        widget.props != oldWidget.props ||
        widget.headers != oldWidget.headers) {
      _payloadFuture = _loadPayload();
    }
  }

  Future<Map<String, dynamic>> _loadPayload() async {
    // Tear down the previous screen's live client-component VMs and restart mount
    // numbering, so this load resolves a fresh, self-consistent set of mounts.
    await _disposeClientCompVms();
    _clientCompSeq = 0;

    // Restore a persisted session (cross-platform) before the first request, so
    // a returning user stays logged in. Idempotent.
    await widget.authConfig?.store.ensureReady();

    final loader = widget.loader ?? _defaultHttpLoader;
    var payload = await loader(
      _currentRoute,
      props: widget.props,
      headers: widget.headers,
    );

    // Generic auth handling: capture issued tokens, and silently refresh +
    // retry when a protected route bounces us to the login screen.
    _captureAuth(payload);
    final config = widget.authConfig;
    if (config != null && widget.loader == null) {
      final nav = payload['navigation'];
      final redirectsToLogin =
          nav is Map && nav['redirectTo']?.toString() == config.loginRoute;
      if (redirectsToLogin && (config.store.refreshToken ?? '').isNotEmpty) {
        if (await _tryRefresh()) {
          payload = await _defaultHttpLoader(
            _currentRoute,
            props: widget.props,
            headers: widget.headers,
          );
          _captureAuth(payload);
        }
      }
    }

    final envelope = NextjsRenderEnvelope.fromJson(payload);
    final resolvedComponent = await _resolveClientComponentNodes(
      envelope.component,
      packedClientComponents: envelope.clientComponents,
    );

    return {
      ...payload,
      'component': resolvedComponent,
    };
  }

  /// Build an absolute request URI by *preserving the base path* (e.g. an
  /// `/elpian` prefix). The default `Uri.resolve('/route')` would discard the
  /// base path; concatenation keeps it, which is what server route prefixes
  /// need. The root route `'/'` maps to the base itself.
  Uri _buildUri(String route) {
    final base = (widget.serverBaseUrl ?? '').replaceAll(RegExp(r'/+$'), '');
    String path;
    if (route.isEmpty || route == '/') {
      path = '';
    } else if (route.startsWith('http://') || route.startsWith('https://')) {
      return Uri.parse(route);
    } else {
      path = route.startsWith('/') ? route : '/$route';
    }
    return Uri.parse('$base$path');
  }

  /// Authorization header from the configured token store (empty when none).
  Map<String, String> _authHeaders() {
    final config = widget.authConfig;
    final token = config?.store.accessToken;
    if (token == null || token.isEmpty) return const {};
    return {'authorization': '${config!.bearerScheme} $token'};
  }

  /// Capture `meta.auth` / `meta.clearAuth` from a render or action response.
  void _captureAuth(Map<String, dynamic> envelope) {
    final config = widget.authConfig;
    if (config == null) return;
    final meta = envelope['meta'];
    if (meta is! Map) return;
    if (meta['clearAuth'] == true) {
      config.store.clear();
      return;
    }
    if (meta.containsKey('auth')) {
      final auth = meta['auth'];
      if (auth is Map) {
        config.store.save(
          access: auth['accessToken']?.toString(),
          refresh: auth['refreshToken']?.toString(),
        );
      } else if (auth == null) {
        config.store.clear();
      }
    }
  }

  /// Exchange the refresh token for a fresh access token. Returns true on
  /// success; clears the session on failure.
  Future<bool> _tryRefresh() async {
    final config = widget.authConfig;
    if (config == null) return false;
    final rt = config.store.refreshToken;
    if (rt == null || rt.isEmpty) return false;
    try {
      final env = await _postJson(config.refreshRoute, {'refreshToken': rt});
      final meta = env['meta'];
      final auth = meta is Map ? meta['auth'] : null;
      if (auth is Map && auth['accessToken'] != null) {
        config.store.save(
          access: auth['accessToken']?.toString(),
          refresh: auth['refreshToken']?.toString(),
        );
        return true;
      }
    } catch (_) {
      // fall through to clear
    }
    config.store.clear();
    return false;
  }

  /// POST a JSON body to an action route (auth attached) and decode the
  /// returned envelope.
  Future<Map<String, dynamic>> _postJson(String route, Object? body) async {
    final res = await http
        .post(
          _buildUri(route),
          headers: {
            'content-type': 'application/json',
            'accept': 'application/vnd.elpian+json, application/json',
            'x-elpian-route': route,
            ..._authHeaders(),
            ...?widget.headers,
          },
          body: jsonEncode(body),
        )
        .timeout(widget.timeout);
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Action response must decode to a JSON object.');
    }
    return decoded;
  }

  /// Handle a `NextjsForm` submission: POST the values, capture auth, apply any
  /// navigation. Returns an inline error message, or null on success.
  Future<String?> _handleFormSubmit(
    String action,
    Map<String, dynamic> values,
  ) async {
    try {
      final env = await _postJson(action, values);
      _captureAuth(env);
      final nav = env['navigation'];
      if (nav is Map && nav.isNotEmpty) {
        _applyServerNavigation(Map<String, dynamic>.from(nav));
        return null;
      }
      // No navigation → the server returned a fragment/toast. Surface its text
      // inline if we can find one, else swap the rendered component.
      final inline = _firstText(env['component']);
      if (inline != null) return inline;
      final component = env['component'];
      if (component is Map<String, dynamic>) {
        _setScriptRenderedComponent(component);
      }
      return null;
    } catch (e) {
      return 'Request failed: $e';
    }
  }

  /// Pull the first meaningful text out of a component tree (for inline errors).
  String? _firstText(dynamic node) {
    if (node is Map) {
      final props = node['props'];
      if (props is Map && props['text'] is String) {
        final t = props['text'] as String;
        if (t.trim().length > 2 && !t.contains('✕')) return t;
      }
      final children = node['children'];
      if (children is List) {
        for (final c in children) {
          final r = _firstText(c);
          if (r != null) return r;
        }
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> _defaultHttpLoader(
    String route, {
    Map<String, dynamic>? props,
    Map<String, String>? headers,
  }) async {
    final baseUrl = widget.serverBaseUrl;
    if (baseUrl == null || baseUrl.isEmpty) {
      throw StateError('serverBaseUrl is required when no custom loader is provided.');
    }

    if (widget.requestMode == NextjsServerRequestMode.routePath) {
      final uri = _buildUri(route);
      final response = await http.get(
        uri,
        headers: {
          'accept': 'application/vnd.elpian+json, application/json',
          'x-elpian-route': route,
          if (props != null && props.isNotEmpty) 'x-elpian-props': jsonEncode(props),
          ..._authHeaders(),
          ...?headers,
        },
      ).timeout(widget.timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'Next.js route $uri returned HTTP ${response.statusCode}: ${response.body}',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Next.js route response must decode to a JSON object.');
      }
      return decoded;
    }

    final endpointUri = _buildUri(widget.endpoint ?? '/api/elpian-render');
    final response = await http.post(
      endpointUri,
      headers: {
        'content-type': 'application/json',
        ..._authHeaders(),
        ...?headers,
      },
      body: jsonEncode(NextjsBridge.buildRouteRequest(route: route, props: props)),
    ).timeout(widget.timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Next.js endpoint $endpointUri returned HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Next.js payload must decode to a JSON object.');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> _resolveClientComponentNodes(
    Map<String, dynamic> node,
    {Map<String, dynamic>? packedClientComponents}
  ) async {
    final type = node['type']?.toString();
    if (type == 'clientComp' || type == 'client-component') {
      final resolved = await _resolveClientComponentNode(
        node,
        packedClientComponents: packedClientComponents,
      );
      if (resolved != null) return resolved;
      return {
        'type': 'Text',
        'props': {'text': 'Failed to execute client component jsCode'},
      };
    }

    final children = node['children'];
    if (children is List) {
      final resolvedChildren = <dynamic>[];
      for (final child in children) {
        if (child is Map<String, dynamic>) {
          resolvedChildren.add(
            await _resolveClientComponentNodes(
              child,
              packedClientComponents: packedClientComponents,
            ),
          );
        } else if (child is Map) {
          resolvedChildren.add(
            await _resolveClientComponentNodes(
              Map<String, dynamic>.from(child),
              packedClientComponents: packedClientComponents,
            ),
          );
        } else {
          resolvedChildren.add(child);
        }
      }
      return {
        ...node,
        'children': resolvedChildren,
      };
    }

    return node;
  }

  Future<Map<String, dynamic>?> _resolveClientComponentNode(
    Map<String, dynamic> node,
    {Map<String, dynamic>? packedClientComponents}
  ) async {
    final props = (node['props'] is Map<String, dynamic>)
        ? Map<String, dynamic>.from(node['props'] as Map<String, dynamic>)
        : <String, dynamic>{};

    String? jsCode = node['jsCode']?.toString() ?? props['jsCode']?.toString();
    String? entry = node['jsEntryFunction']?.toString() ??
        props['jsEntryFunction']?.toString() ??
        'MainComponent';

    if (jsCode == null || jsCode.isEmpty) {
      final packedScript = _findPackedClientComponentScript(
        node,
        props,
        packedClientComponents,
      );
      jsCode = packedScript?.jsCode;
      entry = packedScript?.jsEntryFunction ?? entry;
    }

    if ((jsCode == null || jsCode.isEmpty) && widget.serverBaseUrl != null) {
      final fetchedScript = await _fetchClientComponentScript(node, props);
      jsCode = fetchedScript?.jsCode;
      entry = fetchedScript?.jsEntryFunction ?? entry;
    }

    if (jsCode == null || jsCode.isEmpty) {
      return null;
    }

    // Mount the component on a PERSISTENT VM (not a throwaway one): its handlers
    // and timers stay alive and its renders patch its own scope in place. On any
    // failure this returns null and the caller renders the fallback placeholder,
    // so a broken component never takes down sibling server content.
    return _mountClientComponent(
      jsCode: jsCode,
      entryFunction: entry,
      props: props,
      style: node['style'],
    );
  }

  /// Mount an inline `clientComp` on a long-lived QuickJS VM and return its
  /// initial render, wrapped in a `Scope` keyed by the mount id. The VM is kept
  /// in [_liveClientComps] so events route back to it and its subsequent renders
  /// (taps, timers) patch only its mount scope. Returns null on failure.
  Future<Map<String, dynamic>?> _mountClientComponent({
    required String jsCode,
    required String entryFunction,
    required Map<String, dynamic> props,
    Object? style,
  }) async {
    final mountId = 'cc${_clientCompSeq++}';
    final machineId =
        'nextjs-$mountId-${DateTime.now().microsecondsSinceEpoch}';

    QuickJsVm vm;
    try {
      vm = await QuickJsVm.fromCode(machineId, jsCode);
    } catch (e) {
      debugPrint('NextjsServerWidget: clientComp "$mountId" create failed: $e');
      return null;
    }
    final record = _LiveClientComp(
      mountId: mountId,
      vm: vm,
      style: style is Map<String, dynamic> ? style : null,
    );
    // Register before running so an asynchronously-delivered render (the web
    // QuickJS runtime calls back async) lands in the registry.
    _liveClientComps[mountId] = record;

    // The web QuickJS runtime delivers renders asynchronously, so we await the
    // FIRST render (with a timeout) before inlining, then fold later renders
    // (drag/tab) on the next build. Every render is bound to this mount's OWN
    // scope, so it repaints just this component — never the rest of the screen.
    final firstRender = Completer<void>();
    final hostHandler = HostHandler(
      onRender: (viewJson, _) {
        record.latest = ClientCompRouting.namespaceHandlers(viewJson, mountId);
        if (!firstRender.isCompleted) {
          firstRender.complete();
        } else {
          record.dirty = true;
          if (mounted) setState(() {});
        }
      },
      onPrintln: (m) => debugPrint('NextjsServerWidget[$mountId]: $m'),
    );

    record.timer = VmTimerHostApi(
      invoke: (fn, input) async {
        if (input == null) {
          await vm.callFunction(fn);
        } else {
          await vm.callFunctionWithInput(fn, input);
        }
      },
      onError: (m) => debugPrint('NextjsServerWidget[$mountId timer]: $m'),
    );

    final handlers = <String, HostCallHandler>{
      for (final apiName in VmHostApiCatalog.allHostApiNames)
        apiName: (name, payload) => hostHandler.handleHostCall(name, payload),
      for (final apiName in VmHostApiCatalog.timerApiNames)
        apiName: (name, payload) => record.timer!.handle(name, payload),
      'navigate': (name, payload) => _hostNavigate(payload),
    };
    vm.registerHostHandlers(handlers);

    try {
      await vm.run();
      await vm.callFunctionWithInput(entryFunction, jsonEncode(props));
      // Give the (async) first render a chance to land so the inlined content is
      // the real component, not an empty placeholder.
      await firstRender.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('NextjsServerWidget: clientComp "$mountId" first render timed out');
        },
      );
    } catch (e) {
      debugPrint('NextjsServerWidget: clientComp "$mountId" exec failed: $e');
      _liveClientComps.remove(mountId);
      await record.dispose();
      return null;
    }

    // Inline this mount's Scope with its first render (or an empty placeholder
    // if it never arrived — a later render folds in on the next build).
    record.dirty = false;
    return _wrapClientCompInScope(_clientCompContent(record), mountId);
  }

  /// The content node inlined under a mount's `Scope`: the component's latest
  /// render (or an empty div before the first render arrives), keyed `<mountId>`
  /// so a scoped patch targets it, with the server node's style merged in.
  Map<String, dynamic> _clientCompContent(_LiveClientComp record) {
    final base = record.latest ?? <String, dynamic>{'type': 'div'};
    final node = <String, dynamic>{...base, 'key': record.mountId};
    final style = record.style;
    if (style != null) {
      final existing = node['style'];
      node['style'] =
          existing is Map<String, dynamic> ? {...style, ...existing} : style;
    }
    return node;
  }

  /// Wrap a client component's content in a `Scope` keyed `<mountId>__scope`.
  Map<String, dynamic> _wrapClientCompInScope(
    Map<String, dynamic> content,
    String mountId,
  ) {
    return <String, dynamic>{
      'type': 'Scope',
      'key': '${mountId}__scope',
      'props': <String, dynamic>{},
      'children': <dynamic>[content],
    };
  }

  /// Fold any pending client-component renders into the live tree, each bounded
  /// to its own mount scope. `replaceByKey` swaps just that mount's content and
  /// bumps its enclosing `Scope` token, so only that component's subtree
  /// rebuilds — the scene, navbar and other components keep their cached widgets.
  /// Called from build(); it never re-bumps a scope whose content is unchanged.
  void _foldClientCompRenders() {
    if (_liveClientComps.isEmpty) return;
    final tree = _scriptRenderedComponent ?? _lastEnvelopeComponent;
    if (tree == null) return;
    var any = false;
    for (final record in _liveClientComps.values) {
      if (!record.dirty || record.latest == null) continue;
      if (ScopePatch.replaceByKey(tree, record.mountId, _clientCompContent(record))) {
        record.dirty = false;
        any = true;
      }
    }
    if (any) _scriptRenderedComponent = tree;
  }

  /// Tear down all live client-component VMs (on route change or disposal).
  Future<void> _disposeClientCompVms() async {
    if (_liveClientComps.isEmpty) return;
    final comps = _liveClientComps.values.toList();
    _liveClientComps.clear();
    for (final c in comps) {
      await c.dispose();
    }
  }

  _PackedClientScript? _findPackedClientComponentScript(
    Map<String, dynamic> node,
    Map<String, dynamic> props,
    Map<String, dynamic>? packedClientComponents,
  ) {
    if (packedClientComponents == null || packedClientComponents.isEmpty) {
      return null;
    }

    final keys = _clientComponentLookupKeys(node, props);
    for (final key in keys) {
      final raw = packedClientComponents[key];
      if (raw == null) continue;
      final packed = _normalizePackedScript(raw);
      if (packed != null) return packed;
    }

    if (packedClientComponents.length == 1) {
      return _normalizePackedScript(packedClientComponents.values.first);
    }

    return null;
  }

  Future<_PackedClientScript?> _fetchClientComponentScript(
    Map<String, dynamic> node,
    Map<String, dynamic> props,
  ) async {
    final lookupKeys = _clientComponentLookupKeys(node, props);
    if (lookupKeys.isEmpty) return null;

    for (final key in lookupKeys) {
      final cached = _clientComponentCache[key];
      if (cached != null) {
        final packed = _normalizePackedScript(cached);
        if (packed != null) return packed;
      }
    }

    final baseUrl = widget.serverBaseUrl;
    if (baseUrl == null || baseUrl.isEmpty) return null;

    try {
      final endpointUri = _buildUri(widget.endpoint ?? '/api/elpian-client-component');
      final response = await http.post(
        endpointUri,
        headers: {
          'content-type': 'application/json',
          'accept': 'application/json',
          ..._authHeaders(),
          ...?widget.headers,
        },
        body: jsonEncode({
          'route': _currentRoute,
          'lookupKeys': lookupKeys,
          'componentNode': node,
        }),
      ).timeout(widget.timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final componentsRaw = decoded['clientComponents'];
      if (componentsRaw is Map<String, dynamic>) {
        for (final entry in componentsRaw.entries) {
          if (entry.value is Map<String, dynamic>) {
            _clientComponentCache[entry.key] =
                Map<String, dynamic>.from(entry.value as Map<String, dynamic>);
          } else if (entry.value is String) {
            _clientComponentCache[entry.key] = {'jsCode': entry.value};
          }
        }
      }

      final directPacked = _normalizePackedScript(decoded);
      if (directPacked != null) {
        for (final key in lookupKeys) {
          _clientComponentCache[key] = {
            'jsCode': directPacked.jsCode,
            'jsEntryFunction': directPacked.jsEntryFunction,
          };
        }
        return directPacked;
      }

      for (final key in lookupKeys) {
        final cached = _clientComponentCache[key];
        if (cached == null) continue;
        final packed = _normalizePackedScript(cached);
        if (packed != null) return packed;
      }
    } catch (_) {
      // Ignore fetch failures, client component can still be resolved inline.
    }

    return null;
  }

  List<String> _clientComponentLookupKeys(
    Map<String, dynamic> node,
    Map<String, dynamic> props,
  ) {
    final keys = <String>{
      ..._stringCandidates([
        node['clientComponentKey'],
        node['componentKey'],
        node['componentId'],
        node['id'],
        node['name'],
        node['path'],
        node['componentPath'],
        node['module'],
      ]),
      ..._stringCandidates([
        props['clientComponentKey'],
        props['componentKey'],
        props['componentId'],
        props['id'],
        props['name'],
        props['path'],
        props['componentPath'],
        props['module'],
      ]),
    };

    if (keys.isEmpty) {
      final fallback = 'anon-${node.hashCode.abs()}-${props.hashCode.abs()}';
      keys.add(fallback);
    }

    return keys.toList(growable: false);
  }

  Iterable<String> _stringCandidates(List<dynamic> values) sync* {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) {
        yield text;
      }
    }
  }

  _PackedClientScript? _normalizePackedScript(dynamic raw) {
    if (raw is String && raw.trim().isNotEmpty) {
      return _PackedClientScript(jsCode: raw.trim(), jsEntryFunction: 'MainComponent');
    }

    if (raw is Map<String, dynamic>) {
      final jsCode = raw['jsCode']?.toString();
      if (jsCode == null || jsCode.trim().isEmpty) return null;
      final entry = raw['jsEntryFunction']?.toString();
      return _PackedClientScript(
        jsCode: jsCode,
        jsEntryFunction: (entry == null || entry.isEmpty) ? 'MainComponent' : entry,
      );
    }

    if (raw is Map) {
      return _normalizePackedScript(Map<String, dynamic>.from(raw));
    }

    return null;
  }

  void _handleNavigate(String route, {bool replace = false}) {
    _navigateTo(route, replace: replace);
  }

  void _navigateTo(String route, {bool replace = false}) {
    if (_currentRoute == route && !replace) return;

    unawaited(_disposePageVm());
    setState(() {
      if (!replace) {
        _history.add(_currentRoute);
      }
      _currentRoute = route;
      _payloadFuture = _loadPayload();
      // Keep the just-rendered screen as the loading fallback so the next route
      // paints over a live screen (scene included) instead of a blank spinner.
      _previousComponent =
          _scriptRenderedComponent ?? _lastEnvelopeComponent ?? _previousComponent;
      _scriptRenderedComponent = null;
      _lastEnvelopeComponent = null;
      _lastScriptSignature = null;
    });
  }

  void _navigateBack() {
    if (_history.isEmpty) return;
    unawaited(_disposePageVm());
    setState(() {
      _currentRoute = _history.removeLast();
      _payloadFuture = _loadPayload();
      // Keep the just-rendered screen as the loading fallback so the next route
      // paints over a live screen (scene included) instead of a blank spinner.
      _previousComponent =
          _scriptRenderedComponent ?? _lastEnvelopeComponent ?? _previousComponent;
      _scriptRenderedComponent = null;
      _lastEnvelopeComponent = null;
      _lastScriptSignature = null;
    });
  }

  void _refresh() {
    unawaited(_disposePageVm());
    setState(() {
      _payloadFuture = _loadPayload();
      // Keep the just-rendered screen as the loading fallback so the next route
      // paints over a live screen (scene included) instead of a blank spinner.
      _previousComponent =
          _scriptRenderedComponent ?? _lastEnvelopeComponent ?? _previousComponent;
      _scriptRenderedComponent = null;
      _lastEnvelopeComponent = null;
      _lastScriptSignature = null;
    });
  }

  @override
  void dispose() {
    unawaited(_disposePageVm());
    unawaited(_disposeClientCompVms());
    super.dispose();
  }

  Future<void> _ensureElpianVmInitialized() async {
    if (_elpianVmInitialized) return;
    await ElpianVm.initialize();
    _elpianVmInitialized = true;
  }

  Map<String, dynamic>? _decodeRenderPayload(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        if (decoded['component'] is Map<String, dynamic>) {
          return decoded['component'] as Map<String, dynamic>;
        }
        return decoded;
      }
    } catch (_) {
      // ignore, payload may be plain string
    }
    return null;
  }

  void _setScriptRenderedComponent(Map<String, dynamic>? component) {
    if (component == null || !mounted) return;
    setState(() {
      _scriptRenderedComponent = component;
    });
  }

  /// Apply a `render(view, scopeKey)` call from a live client script.
  ///
  /// With a `scopeKey`, only the matching `Scope` subtree of the live tree is
  /// substituted (and its enclosing scopes' tokens bumped) so a local mutation —
  /// a HUD tick, a tab switch — rebuilds just that region instead of the whole
  /// screen. Without one, it replaces the rendered component (legacy behaviour).
  void _applyClientRender(Map<String, dynamic> view, String? scopeKey) {
    if (!mounted) return;
    final key = ScopePatch.normalizeKey(scopeKey);
    if (key == null) {
      setState(() => _scriptRenderedComponent = view);
      return;
    }
    // Patch the live tree — the script's own prior render if any, else the
    // current server-rendered component — in place, BOUNDED to the target
    // scope. A render aimed at a scope that isn't on screen must not blow away
    // the whole view (the global-propagation bug): keep the current tree.
    final tree = _scriptRenderedComponent ?? _lastEnvelopeComponent;
    final next = ScopePatch.applyBounded(tree, view, key);
    if (next == null) {
      debugPrint(
        'NextjsServerWidget: scoped render targeted missing scope "$key"; '
        'keeping current screen (no global re-render).',
      );
      return;
    }
    setState(() => _scriptRenderedComponent = next);
  }

  /// Tear down the persistent page-level VM and its timers (on route change or
  /// widget disposal) so pollers and intervals don't outlive their screen.
  Future<void> _disposePageVm() async {
    _pageTimerApi?.dispose();
    _pageTimerApi = null;
    final vm = _pageVm;
    _pageVm = null;
    if (vm != null) {
      try {
        await vm.dispose();
      } catch (_) {
        // best-effort teardown
      }
    }
  }

  static const String _hostOk = '{"type":"i16","data":{"value":1}}';

  /// `askHost('fetch', { route, onData })` — fetch a fragment route and hand the
  /// decoded envelope back to the VM function named by `onData`. Async by
  /// design: the call returns immediately and the result arrives via callback,
  /// so a poller never blocks the VM waiting on the network.
  Future<String> _hostFetch(String payload) async {
    try {
      final args = _firstArgMap(payload);
      final route = args['route']?.toString();
      final onData = args['onData']?.toString();
      if (route == null || route.isEmpty) return _hostOk;
      final envelope = await _defaultHttpLoader(route, headers: widget.headers);
      final vm = _pageVm;
      if (onData != null && onData.isNotEmpty && vm != null) {
        await vm.callFunctionWithInput(onData, jsonEncode(envelope));
      }
    } catch (e) {
      debugPrint('NextjsServerWidget[page fetch]: $e');
    }
    return _hostOk;
  }

  /// `askHost('submit', { route, body, onResult })` — POST an action and hand
  /// the response envelope back to `onResult`. Navigation directives are applied
  /// automatically (matching `NextjsForm`).
  Future<String> _hostSubmit(String payload) async {
    try {
      final args = _firstArgMap(payload);
      final route = args['route']?.toString();
      final onResult = args['onResult']?.toString();
      if (route == null || route.isEmpty) return _hostOk;
      final env = await _postJson(route, args['body']);
      _captureAuth(env);
      final nav = env['navigation'];
      if (nav is Map && nav.isNotEmpty) {
        _applyServerNavigation(Map<String, dynamic>.from(nav));
      }
      final vm = _pageVm;
      if (onResult != null && onResult.isNotEmpty && vm != null) {
        await vm.callFunctionWithInput(onResult, jsonEncode(env));
      }
    } catch (e) {
      debugPrint('NextjsServerWidget[page submit]: $e');
    }
    return _hostOk;
  }

  /// `askHost('navigate', navigation)` — apply a server-style navigation
  /// directive (`redirectTo` / `refresh` / `back`) from a client script.
  String _hostNavigate(String payload) {
    try {
      final nav = _firstArgMap(payload);
      if (nav.isNotEmpty) _applyServerNavigation(nav);
    } catch (e) {
      debugPrint('NextjsServerWidget[page navigate]: $e');
    }
    return _hostOk;
  }

  /// Route engine UI events (clicks, pointer moves, …) on the rendered tree to
  /// the owning VM's named handlers. A node opts in by declaring
  /// `events: { 'click': 'handlerFnName' }`. Handlers belonging to an inline
  /// client component are namespaced `<mountId>::<fn>` so a tap is delivered to
  /// that component's own VM; everything else goes to the page VM. This is what
  /// lets a tap re-render only its scope instead of re-fetching the route.
  void _wireEventRouting() {
    if (_eventRoutingWired) return;
    _eventRoutingWired = true;
    _bridge.engine.setGlobalEventHandler((event) {
      unawaited(_routeEvent(event));
    });
  }

  Future<void> _routeEvent(ElpianEvent event) async {
    final nodeId = event.currentTarget?.toString();
    if (nodeId == null || nodeId.isEmpty) return;
    final node = _bridge.engine.eventDispatcher.getNode(nodeId);
    final handler = node?.events?[event.type];
    if (handler is! String || handler.isEmpty) return;

    // A namespaced handler (`<mountId>::<fn>`) belongs to a live client
    // component; route it to that component's VM. Otherwise it's the page VM's.
    final route = ClientCompRouting.parse(handler);
    final VmRuntimeClient? vm =
        route != null ? _liveClientComps[route.mountId]?.vm : _pageVm;
    final String fn = route?.fn ?? handler;
    if (vm == null) return;

    // QuickJS handlers receive a plain-JSON event (unlike the Rust VM's typed
    // payloads), so a loose object is enough; fall back to a no-arg call for
    // handlers declared without parameters.
    final input = jsonEncode(_eventToHostJson(event));
    try {
      await vm.callFunctionWithInput(fn, input);
    } catch (_) {
      try {
        await vm.callFunction(fn);
      } catch (e) {
        debugPrint('NextjsServerWidget: event handler "$handler" failed: $e');
      }
    }
  }

  /// A loose JSON event for QuickJS handlers. Includes pointer coordinates so
  /// drag components (which read `e.x`/`e.y`) work.
  Map<String, dynamic> _eventToHostJson(ElpianEvent event) {
    final base = <String, dynamic>{'type': event.type};
    if (event is ElpianPointerEvent) {
      base['x'] = event.position.dx;
      base['y'] = event.position.dy;
    }
    return base;
  }

  /// Decode the first host-call argument into a JSON map (host calls wrap their
  /// args in an array; the bridge may also pass a bare object or JSON string).
  Map<String, dynamic> _firstArgMap(String payload) {
    dynamic parsed;
    try {
      parsed = jsonDecode(payload);
    } catch (_) {
      return const {};
    }
    if (parsed is List && parsed.isNotEmpty) parsed = parsed.first;
    if (parsed is String) {
      try {
        parsed = jsonDecode(parsed);
      } catch (_) {
        return const {};
      }
    }
    if (parsed is Map<String, dynamic>) return parsed;
    if (parsed is Map) return Map<String, dynamic>.from(parsed);
    return const {};
  }

  /// Run the page-level client script on a *persistent* QuickJS VM.
  ///
  /// Unlike one-shot `clientComp` resolution, this VM lives for the duration of
  /// the route (until [_navigateTo]/[_refresh]/dispose tears it down) so its
  /// `setInterval` timers keep ticking and its `render(view, scopeKey)` calls
  /// keep arriving. Combined with `Scope` nodes, that yields cheap, isolated
  /// in-place updates (e.g. a polled HUD) without re-rendering the whole screen.
  ///
  /// Host surface: the standard core/timer/DOM APIs (via [HostHandler]) plus
  /// `fetch`/`submit`/`navigate` bridges back into this widget.
  Future<void> _runPageScript(
    String jsCode, {
    required String entryFunction,
  }) async {
    await _disposePageVm();

    final machineId = 'nextjs-page-${DateTime.now().microsecondsSinceEpoch}';
    final vm = await QuickJsVm.fromCode(machineId, jsCode);
    _pageVm = vm;

    final hostHandler = HostHandler(
      onRender: (viewJson, scopeKey) => _applyClientRender(viewJson, scopeKey),
      onPrintln: (m) => debugPrint('NextjsServerWidget[page]: $m'),
    );

    _pageTimerApi = VmTimerHostApi(
      invoke: (funcName, inputJson) async {
        if (_pageVm == null) return;
        if (inputJson == null) {
          await vm.callFunction(funcName);
        } else {
          await vm.callFunctionWithInput(funcName, inputJson);
        }
      },
      onError: (m) => debugPrint('NextjsServerWidget[page timer]: $m'),
    );

    final handlers = <String, HostCallHandler>{
      for (final apiName in VmHostApiCatalog.allHostApiNames)
        apiName: (name, payload) => hostHandler.handleHostCall(name, payload),
      for (final apiName in VmHostApiCatalog.timerApiNames)
        apiName: (name, payload) => _pageTimerApi!.handle(name, payload),
      'fetch': (name, payload) => _hostFetch(payload),
      'submit': (name, payload) => _hostSubmit(payload),
      'navigate': (name, payload) => _hostNavigate(payload),
    };
    vm.registerHostHandlers(handlers);
    // Event routing is wired once in initState (covers page VM + client comps).

    await vm.run();
    if (entryFunction.isNotEmpty) {
      final initial = await vm.callFunction(entryFunction);
      // The entry's return value seeds the initial render only when the script
      // returns a real component tree (a full-screen renderer). A side-effect
      // script — e.g. a poller that patches a scope via `askHost('render')` —
      // returns `null`, leaving the server-rendered screen untouched.
      final seeded = _decodeRenderPayload(initial);
      if (seeded != null &&
          seeded['type'] != null &&
          _scriptRenderedComponent == null) {
        _setScriptRenderedComponent(seeded);
      }
    }

    widget.onScriptExecuted?.call(
      NextjsScriptExecutionResult(
        route: _currentRoute,
        kind: 'js',
        output: '',
      ),
    );
  }

  void _triggerScriptExecution(NextjsRenderEnvelope envelope) {
    final jsCode = envelope.jsCode;
    final vmAst = envelope.vmAstJson;
    if ((jsCode == null || jsCode.isEmpty) && (vmAst == null || vmAst.isEmpty)) {
      return;
    }

    final signature =
        '$_currentRoute|${envelope.jsEntryFunction ?? 'MainComponent'}|${jsCode ?? ''}|${vmAst ?? ''}';
    if (_lastScriptSignature == signature) return;
    _lastScriptSignature = signature;

    unawaited(_executeEnvelopeScripts(envelope));
  }

  Future<void> _executeEnvelopeScripts(NextjsRenderEnvelope envelope) async {
    try {
      if (envelope.jsCode != null && envelope.jsCode!.isNotEmpty) {
        await _runPageScript(
          envelope.jsCode!,
          entryFunction: envelope.jsEntryFunction ?? 'MainComponent',
        );
      }

      if (envelope.vmAstJson != null && envelope.vmAstJson!.isNotEmpty) {
        await _ensureElpianVmInitialized();
        final vmMachineId = 'nextjs-ast-${DateTime.now().microsecondsSinceEpoch}';
        final vm = await ElpianVm.fromAst(vmMachineId, envelope.vmAstJson!);
        if (vm == null) {
          throw StateError('Failed to create Elpian VM from AST payload.');
        }

        vm.registerHostHandler('render', (apiName, payload) {
          final component = _decodeRenderPayload(payload);
          _setScriptRenderedComponent(component);
          return '{"type":"i16","data":{"value":1}}';
        });

        try {
          final output = await vm.run();
          final returnedComponent = _decodeRenderPayload(output);
          _setScriptRenderedComponent(returnedComponent);

          widget.onScriptExecuted?.call(
            NextjsScriptExecutionResult(
              route: _currentRoute,
              kind: 'vmAst',
              output: output,
            ),
          );
        } finally {
          await vm.dispose();
        }
      }
    } catch (error, stackTrace) {
      widget.onScriptError?.call(error, stackTrace);
      debugPrint('NextjsServerWidget script execution error: $error');
    }
  }

  void _applyServerNavigation(Map<String, dynamic>? navigation) {
    if (navigation == null || navigation.isEmpty) return;

    if (navigation['back'] == true) {
      scheduleMicrotask(_navigateBack);
      return;
    }

    if (navigation['refresh'] == true) {
      scheduleMicrotask(_refresh);
      return;
    }

    final redirectTo = navigation['redirectTo']?.toString();
    if (redirectTo != null && redirectTo.isNotEmpty) {
      final replace = navigation['replace'] == true;
      if (redirectTo != _currentRoute || replace) {
        scheduleMicrotask(() => _navigateTo(redirectTo, replace: replace));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Resolve `@media` rules against the REAL widget viewport (not the
    // platform view, which is unreliable on web) so responsive layout — a
    // floating window on desktop, full-screen on mobile — is correct.
    final mq = MediaQuery.maybeOf(context);
    if (mq != null) CSSParser.viewportOverride = mq.size;

    return FutureBuilder<Map<String, dynamic>>(
      future: _payloadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          // While the next route loads, keep the previous screen painted (with a
          // thin progress bar on top) so navigation doesn't blank out — and, on
          // city/world screens, doesn't tear down and reload the 3D scene. The
          // engine's static-scene cache then lets the next screen reuse the
          // already-baked scaffold, so the swap is near-instant.
          final fallback = _previousComponent;
          if (fallback != null) {
            Widget previous;
            try {
              previous = _bridge.engine.wrapAsDocument(
                _bridge.engine.renderFromJson(fallback),
                fallback,
              );
            } catch (_) {
              previous = widget.loadingBuilder?.call(context) ??
                  const Center(child: CircularProgressIndicator());
            }
            return Stack(
              children: [
                previous,
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              ],
            );
          }
          return widget.loadingBuilder?.call(context) ??
              const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          final error = snapshot.error!;
          return widget.errorBuilder?.call(context, error) ??
              Center(
                child: Text(
                  'Next.js payload error on "$_currentRoute": $error',
                  textAlign: TextAlign.center,
                ),
              );
        }

        final payload = snapshot.data;
        if (payload == null) {
          return const Center(child: Text('Next.js payload was empty.'));
        }

        final envelope = NextjsRenderEnvelope.fromJson(payload);
        // Remember the server tree so a scoped client render has a base to
        // patch even before the script's first full render.
        _lastEnvelopeComponent = envelope.component;
        _triggerScriptExecution(envelope);
        _applyServerNavigation(envelope.navigation);

        // Fold any client-component renders that arrived (async) since the last
        // build into the live tree, each bounded to its own mount scope.
        _foldClientCompRenders();

        final componentToRender = _scriptRenderedComponent ?? envelope.component;
        final rendered = _bridge.engine.renderWithStylesheet(
          componentToRender,
          stylesheet: envelope.stylesheet,
        );
        // Browser `<body>` semantics: tall screens scroll, full-bleed stages
        // stay pinned. Without this, content past the viewport was unreachable.
        return _bridge.engine.wrapAsDocument(rendered, componentToRender);
      },
    );
  }
}

/// A mounted inline client component: a persistent VM, its timer host API, and
/// the latest render it produced. Lives for the route so its handlers/timers
/// keep firing and its renders fold into its own mount scope in place.
class _LiveClientComp {
  _LiveClientComp({required this.mountId, required this.vm, this.style});

  final String mountId;
  final VmRuntimeClient vm;

  /// The server node's style, merged onto every render of this mount.
  final Map<String, dynamic>? style;

  VmTimerHostApi? timer;

  /// The component's most recent render (namespaced handlers), folded into the
  /// tree under this mount's `Scope` on the next build. Null before the first
  /// render arrives (web delivers the first render asynchronously).
  Map<String, dynamic>? latest;

  /// Set when [latest] changes; cleared once folded so an unchanged mount scope
  /// is never re-bumped (and thus never needlessly rebuilds).
  bool dirty = false;

  Future<void> dispose() async {
    timer?.dispose();
    timer = null;
    try {
      await vm.dispose();
    } catch (_) {
      // best-effort teardown
    }
  }
}

class _PackedClientScript {
  const _PackedClientScript({
    required this.jsCode,
    required this.jsEntryFunction,
  });

  final String jsCode;
  final String jsEntryFunction;
}
