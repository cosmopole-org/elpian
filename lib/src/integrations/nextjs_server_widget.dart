import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../vm/elpian_vm.dart';
import '../vm/quickjs_vm.dart';
import 'nextjs_bridge.dart';

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
    this.timeout = const Duration(seconds: 15),
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

  @override
  void initState() {
    super.initState();
    _currentRoute = widget.route;
    _bridge = widget.bridge ?? NextjsBridge();
    _bridge.onNavigate = _handleNavigate;
    _payloadFuture = _loadPayload();
  }

  @override
  void didUpdateWidget(covariant NextjsServerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.bridge != oldWidget.bridge && widget.bridge != null) {
      _bridge = widget.bridge!;
      _bridge.onNavigate = _handleNavigate;
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
    final loader = widget.loader ?? _defaultHttpLoader;
    final payload = await loader(
      _currentRoute,
      props: widget.props,
      headers: widget.headers,
    );

    final envelope = NextjsRenderEnvelope.fromJson(payload);
    final resolvedComponent = await _resolveClientComponentNodes(envelope.component);

    return {
      ...payload,
      'component': resolvedComponent,
    };
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

    final client = HttpClient();
    try {
      if (widget.requestMode == NextjsServerRequestMode.routePath) {
        final routePath = _normalizeRoutePath(route);
        final uri = Uri.parse(baseUrl).resolve(routePath);
        final request = await client.getUrl(uri).timeout(widget.timeout);
        request.headers.set('accept', 'application/vnd.elpian+json, application/json');
        request.headers.set('x-elpian-route', route);
        if (props != null && props.isNotEmpty) {
          request.headers.set('x-elpian-props', jsonEncode(props));
        }
        headers?.forEach(request.headers.set);

        final response = await request.close().timeout(widget.timeout);
        final responseBody = await response.transform(utf8.decoder).join();

        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw StateError(
            'Next.js route ${uri.toString()} returned HTTP ${response.statusCode}: $responseBody',
          );
        }

        final decoded = jsonDecode(responseBody);
        if (decoded is! Map<String, dynamic>) {
          throw FormatException('Next.js route response must decode to a JSON object.');
        }
        return decoded;
      }

      final endpointPath = widget.endpoint ?? '/api/elpian-render';
      final endpointUri = Uri.parse(baseUrl).resolve(endpointPath);
      final request = await client.postUrl(endpointUri).timeout(widget.timeout);
      request.headers.contentType = ContentType.json;
      headers?.forEach(request.headers.set);
      request.write(
        jsonEncode(
          NextjsBridge.buildRouteRequest(route: route, props: props),
        ),
      );

      final response = await request.close().timeout(widget.timeout);
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'Next.js endpoint ${endpointUri.toString()} returned HTTP ${response.statusCode}: $responseBody',
        );
      }

      final decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic>) {
        throw FormatException('Next.js payload must decode to a JSON object.');
      }
      return decoded;
    } finally {
      client.close();
    }
  }

  String _normalizeRoutePath(String route) {
    if (route.isEmpty) return '/';
    if (route.startsWith('http://') || route.startsWith('https://')) {
      return Uri.parse(route).path;
    }
    return route.startsWith('/') ? route : '/$route';
  }

  Future<Map<String, dynamic>> _resolveClientComponentNodes(
    Map<String, dynamic> node,
  ) async {
    final type = node['type']?.toString();
    if (type == 'clientComp' || type == 'client-component') {
      final resolved = await _resolveClientComponentNode(node);
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
          resolvedChildren.add(await _resolveClientComponentNodes(child));
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
  ) async {
    final props = (node['props'] is Map<String, dynamic>)
        ? Map<String, dynamic>.from(node['props'] as Map<String, dynamic>)
        : <String, dynamic>{};

    final jsCode = node['jsCode']?.toString() ?? props['jsCode']?.toString();
    if (jsCode == null || jsCode.isEmpty) {
      return null;
    }

    final entry = node['jsEntryFunction']?.toString() ??
        props['jsEntryFunction']?.toString() ??
        'MainComponent';

    final component = await _runJsComponentCode(
      jsCode,
      entryFunction: entry,
      inputProps: props,
    );

    if (component == null) return null;

    final style = node['style'];
    if (style is Map<String, dynamic>) {
      final existingStyle = component['style'];
      if (existingStyle is Map<String, dynamic>) {
        component['style'] = {
          ...style,
          ...existingStyle,
        };
      } else {
        component['style'] = style;
      }
    }

    return component;
  }

  void _handleNavigate(String route, {bool replace = false}) {
    _navigateTo(route, replace: replace);
  }

  void _navigateTo(String route, {bool replace = false}) {
    if (_currentRoute == route && !replace) return;

    setState(() {
      if (!replace) {
        _history.add(_currentRoute);
      }
      _currentRoute = route;
      _payloadFuture = _loadPayload();
      _scriptRenderedComponent = null;
      _lastScriptSignature = null;
    });
  }

  void _navigateBack() {
    if (_history.isEmpty) return;
    setState(() {
      _currentRoute = _history.removeLast();
      _payloadFuture = _loadPayload();
      _scriptRenderedComponent = null;
      _lastScriptSignature = null;
    });
  }

  void _refresh() {
    setState(() {
      _payloadFuture = _loadPayload();
      _scriptRenderedComponent = null;
      _lastScriptSignature = null;
    });
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

  Future<Map<String, dynamic>?> _runJsComponentCode(
    String jsCode, {
    required String entryFunction,
    Map<String, dynamic>? inputProps,
  }) async {
    final jsMachineId = 'nextjs-comp-${DateTime.now().microsecondsSinceEpoch}';
    final quickVm = await QuickJsVm.fromCode(jsMachineId, jsCode);
    Map<String, dynamic>? rendered;

    quickVm.registerHostHandler('render', (apiName, payload) {
      rendered = _decodeRenderPayload(payload) ?? rendered;
      return '{"type":"i16","data":{"value":1}}';
    });

    try {
      await quickVm.run();
      final output = inputProps == null
          ? await quickVm.callFunction(entryFunction)
          : await quickVm.callFunctionWithInput(entryFunction, jsonEncode(inputProps));
      rendered ??= _decodeRenderPayload(output);
      return rendered;
    } finally {
      await quickVm.dispose();
    }
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
        final rendered = await _runJsComponentCode(
          envelope.jsCode!,
          entryFunction: envelope.jsEntryFunction ?? 'MainComponent',
        );
        _setScriptRenderedComponent(rendered);

        widget.onScriptExecuted?.call(
          NextjsScriptExecutionResult(
            route: _currentRoute,
            kind: 'js',
            output: jsonEncode(rendered ?? const <String, dynamic>{}),
          ),
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
    return FutureBuilder<Map<String, dynamic>>(
      future: _payloadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
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
        _triggerScriptExecution(envelope);
        _applyServerNavigation(envelope.navigation);

        final componentToRender = _scriptRenderedComponent ?? envelope.component;
        return _bridge.engine.renderWithStylesheet(
          componentToRender,
          stylesheet: envelope.stylesheet,
        );
      },
    );
  }
}
