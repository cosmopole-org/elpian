import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/elpian_engine.dart';
import '../core/event_system.dart';
import 'elpian_vm.dart';
import 'quickjs_vm.dart';
import 'runtime_kind.dart';
import 'wasm_vm.dart';
import 'vm_runtime_client.dart';
import 'host_api_catalog.dart';
import 'host_handler.dart';
import 'timer_host_api.dart';

/// A Flutter widget that runs an Elpian Rust VM sandbox and renders
/// the view tree it produces via the ElpianEngine.
///
/// The VM code can call `askHost("render", viewJson)` to send a JSON
/// representation of the UI, which this widget renders using the
/// server-driven UI engine with all registered HTML/CSS/Flutter widgets.
///
/// ## Usage
///
/// ```dart
/// ElpianVmWidget(
///   machineId: 'my-app',
///   code: '''
///     def view = {
///       "type": "div",
///       "props": {
///         "style": { "padding": "16", "backgroundColor": "#f0f0f0" }
///       },
///       "children": [
///         { "type": "h1", "props": { "text": "Hello from VM!" } },
///         { "type": "p", "props": { "text": "This UI is controlled by sandboxed code." } }
///       ]
///     }
///     askHost("render", view)
///   ''',
/// )
/// ```
///
/// ## AST Mode
///
/// You can also provide a pre-compiled AST instead of source code:
///
/// ```dart
/// ElpianVmWidget.fromAst(
///   machineId: 'my-app',
///   astJson: '{"type":"program","body":[...]}',
/// )
/// ```
class ElpianVmWidget extends StatefulWidget {
  /// Unique identifier for this VM instance.
  final String machineId;

  /// Source code to run in the VM (mutually exclusive with [astJson]).
  final String? code;

  /// AST JSON to run in the VM (mutually exclusive with [code]).
  final String? astJson;

  /// Runtime backend used to execute [code]/[astJson].
  ///
  /// - [ElpianRuntime.elpian]: Rust VM sandbox (default), expects AST for [astJson].
  /// - [ElpianRuntime.quickJs]: QuickJS runtime, expects JavaScript in [code].
  /// - [ElpianRuntime.wasm]: WebAssembly runtime, expects WASM config JSON in [code].
  final ElpianRuntime runtime;

  /// Optional ElpianEngine instance to use for rendering.
  /// If not provided, a new default engine is created.
  final ElpianEngine? engine;

  /// Optional stylesheet JSON to load into the engine.
  final Map<String, dynamic>? stylesheet;

  /// Widget to display while the VM is initializing.
  final Widget? loadingWidget;

  /// Widget to display when the VM encounters an error.
  final Widget Function(String error)? errorBuilder;

  /// Callback for when the VM calls `println`.
  final void Function(String message)? onPrintln;

  /// Callback for when the VM calls `updateApp`.
  final void Function(Map<String, dynamic> data)? onUpdateApp;

  /// Additional host call handlers.
  final Map<String, HostCallHandler>? hostHandlers;

  /// Name of the function to call after initial execution.
  /// If null, the main program body is executed.
  final String? entryFunction;

  /// JSON input to pass to the entry function.
  final String? entryInput;

  const ElpianVmWidget({
    super.key,
    required this.machineId,
    this.code,
    this.astJson,
    this.engine,
    this.stylesheet,
    this.loadingWidget,
    this.errorBuilder,
    this.onPrintln,
    this.onUpdateApp,
    this.hostHandlers,
    this.entryFunction,
    this.entryInput,
    this.runtime = ElpianRuntime.elpian,
  }) : assert(code != null || astJson != null,
            'Either code or astJson must be provided');

  /// Create a widget from AST JSON.
  const ElpianVmWidget.fromAst({
    super.key,
    required this.machineId,
    required String this.astJson,
    this.engine,
    this.stylesheet,
    this.loadingWidget,
    this.errorBuilder,
    this.onPrintln,
    this.onUpdateApp,
    this.hostHandlers,
    this.entryFunction,
    this.entryInput,
    this.runtime = ElpianRuntime.elpian,
  }) : code = null;

  /// Create a widget from source code.
  const ElpianVmWidget.fromCode({
    super.key,
    required this.machineId,
    required String this.code,
    this.engine,
    this.stylesheet,
    this.loadingWidget,
    this.errorBuilder,
    this.onPrintln,
    this.onUpdateApp,
    this.hostHandlers,
    this.entryFunction,
    this.entryInput,
    this.runtime = ElpianRuntime.elpian,
  }) : astJson = null;

  @override
  State<ElpianVmWidget> createState() => _ElpianVmWidgetState();
}

class _ElpianVmWidgetState extends State<ElpianVmWidget>
    with WidgetsBindingObserver {
  late ElpianEngine _engine;
  ElpianVm? _vm;
  QuickJsVm? _quickJsVm;
  WasmVm? _wasmVm;
  VmTimerHostApi? _timerHostApi;
  Map<String, dynamic>? _currentViewJson;
  String? _error;
  bool _isLoading = true;
  int _scopeRenderTokenCounter = 0;
  Map<String, dynamic> _hostEnvironmentData = const <String, dynamic>{};
  String? _hostEnvironmentDigest;
  bool _hostEnvironmentSyncScheduled = false;
  bool _dependenciesReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _engine = widget.engine ?? ElpianEngine();
    if (widget.stylesheet != null) {
      _engine.loadStylesheet(widget.stylesheet!);
    }
    _initVm();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dependenciesReady = true;
    _scheduleHostEnvironmentSync();
  }

  @override
  void didChangeMetrics() {
    _scheduleHostEnvironmentSync(force: true);
  }

  VmRuntimeClient? get _activeRuntimeVm => _vm ?? _quickJsVm ?? _wasmVm;

  void _scheduleHostEnvironmentSync({bool force = false}) {
    if (_hostEnvironmentSyncScheduled) return;
    _hostEnvironmentSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _hostEnvironmentSyncScheduled = false;
      if (!mounted) return;
      await _syncHostEnvironmentToRuntime(force: force);
    });
  }

  Future<void> _syncHostEnvironmentToRuntime({bool force = false}) async {
    final runtimeVm = _activeRuntimeVm;
    if (runtimeVm == null) {
      _updateHostEnvironmentCache();
      return;
    }
    final changed = _updateHostEnvironmentCache();
    if (!changed && !force) return;
    try {
      await runtimeVm.setGlobalHostData(_hostEnvironmentData);
    } catch (e) {
      debugPrint('ElpianVmWidget: failed to sync host env: $e');
    }
  }

  bool _updateHostEnvironmentCache() {
    final next = _buildHostEnvironmentData();
    final digest = jsonEncode(next);
    if (digest == _hostEnvironmentDigest) return false;
    _hostEnvironmentDigest = digest;
    _hostEnvironmentData = next;
    return true;
  }

  Map<String, dynamic> _buildHostEnvironmentData() {
    final mediaQuery = _dependenciesReady ? MediaQuery.maybeOf(context) : null;
    final fallbackView = _fallbackView();
    final view = _dependenciesReady
        ? (View.maybeOf(context) ?? fallbackView)
        : fallbackView;

    final double devicePixelRatio = mediaQuery?.devicePixelRatio ??
        view?.devicePixelRatio ??
        fallbackView?.devicePixelRatio ??
        1.0;

    final ui.Size physicalSize =
        view?.physicalSize ?? fallbackView?.physicalSize ?? ui.Size.zero;

    final ui.Size logicalSize = mediaQuery?.size ??
        (devicePixelRatio > 0
            ? ui.Size(
                physicalSize.width / devicePixelRatio,
                physicalSize.height / devicePixelRatio,
              )
            : ui.Size.zero);

    final orientation =
        logicalSize.width >= logicalSize.height ? 'landscape' : 'portrait';
    final uri = Uri.base;

    return <String, dynamic>{
      'machineId': widget.machineId,
      'runtime': widget.runtime.name,
      'viewport': {
        'width': logicalSize.width,
        'height': logicalSize.height,
        'devicePixelRatio': devicePixelRatio,
        'orientation': orientation,
      },
      'screen': {
        'physicalWidth': physicalSize.width,
        'physicalHeight': physicalSize.height,
      },
      'safeArea': mediaQuery == null
          ? _edgeInsetsToMapFromViewPadding(
              view?.padding,
              devicePixelRatio,
            )
          : {
              'top': mediaQuery.padding.top,
              'right': mediaQuery.padding.right,
              'bottom': mediaQuery.padding.bottom,
              'left': mediaQuery.padding.left,
            },
      'page': {
        'href': uri.toString(),
        'scheme': uri.scheme,
        'host': uri.host,
        'port': uri.hasPort ? uri.port : null,
        'path': uri.path,
        'query': uri.query,
        'queryParameters': uri.queryParameters,
        'fragment': uri.fragment,
      },
      'platform': {
        'isWeb': kIsWeb,
        'defaultTargetPlatform': defaultTargetPlatform.name,
        'locale':
            WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag(),
      },
    };
  }

  ui.FlutterView? _fallbackView() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isNotEmpty) return views.first;
    return null;
  }

  Map<String, dynamic> _edgeInsetsToMapFromViewPadding(
    ui.ViewPadding? padding,
    double devicePixelRatio,
  ) {
    if (padding == null || devicePixelRatio <= 0) {
      return const {
        'top': 0.0,
        'right': 0.0,
        'bottom': 0.0,
        'left': 0.0,
      };
    }
    return {
      'top': padding.top / devicePixelRatio,
      'right': padding.right / devicePixelRatio,
      'bottom': padding.bottom / devicePixelRatio,
      'left': padding.left / devicePixelRatio,
    };
  }

  Future<void> _initVm() async {
    try {
      // Initialize only the selected runtime subsystem.
      if (widget.runtime == ElpianRuntime.elpian) {
        await ElpianVm.initialize();
        ElpianVm? vm;
        if (widget.code != null) {
          vm = await ElpianVm.fromCode(widget.machineId, widget.code!);
        } else if (widget.astJson != null) {
          vm = await ElpianVm.fromAst(widget.machineId, widget.astJson!);
        }

        if (vm == null) {
          setState(() {
            final detail = ElpianVm.lastApiError;
            _error = detail == null
                ? 'Failed to create VM'
                : 'Failed to create VM: $detail';
            _isLoading = false;
          });
          return;
        }

        _vm = vm;
      } else if (widget.runtime == ElpianRuntime.quickJs) {
        await QuickJsVm.initialize();
        if (widget.code == null) {
          setState(() {
            _error = 'QuickJS runtime requires `code` (JavaScript source).';
            _isLoading = false;
          });
          return;
        }
        _quickJsVm = await QuickJsVm.fromCode(widget.machineId, widget.code!);
      } else {
        await WasmVm.initialize();
        if (widget.code == null) {
          setState(() {
            _error = 'WASM runtime requires `code` (WASM config JSON).';
            _isLoading = false;
          });
          return;
        }
        _wasmVm = await WasmVm.fromCode(widget.machineId, widget.code!);
      }

      // Wire all UI events to VM function names declared in node.events.
      // This keeps event routing fully engine-driven (no extra app-layer glue).
      _engine.setGlobalEventHandler((event) {
        _routeEventToVm(event);
      });

      // Set up host handlers
      final hostHandler = HostHandler(
        onRender: (viewJson, scopeKey) {
          if (mounted) {
            setState(() {
              _applyRenderUpdate(viewJson, scopeKey: scopeKey);
            });
          }
        },
        onUpdateApp: (data) {
          widget.onUpdateApp?.call(data);
          // Re-run the entry function if there is one to get updated view
          if (widget.entryFunction != null) {
            _callEntryFunction();
          }
        },
        onPrintln: widget.onPrintln,
        onGetEnvironment: () => _hostEnvironmentData,
      );

      // Register built-in host handlers (core + DOM + Canvas APIs).
      final VmRuntimeClient runtimeVm = _vm ?? _quickJsVm ?? _wasmVm!;
      _timerHostApi?.dispose();
      _timerHostApi = VmTimerHostApi(
        invoke: (funcName, inputJson) async {
          if (inputJson == null) {
            await runtimeVm.callFunction(funcName);
          } else {
            await runtimeVm.callFunctionWithInput(funcName, inputJson);
          }
        },
        onError: (message) {
          debugPrint('ElpianVmWidget: $message');
        },
      );

      final timerHandlers = <String, HostCallHandler>{
        for (final apiName in VmHostApiCatalog.timerApiNames)
          apiName: (name, payload) => _timerHostApi!.handle(name, payload),
      };
      final hostHandlers = <String, HostCallHandler>{
        for (final apiName in VmHostApiCatalog.allHostApiNames)
          apiName: (name, payload) => hostHandler.handleHostCall(name, payload),
        ...timerHandlers,
        ...?widget.hostHandlers,
      };
      runtimeVm.registerHostHandlers(hostHandlers);
      await _syncHostEnvironmentToRuntime(force: true);

      // Execute the VM
      await runtimeVm.run();

      // Call entry function if specified
      if (widget.entryFunction != null) {
        await _callEntryFunction();
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _routeEventToVm(ElpianEvent event) async {
    final VmRuntimeClient? runtimeVm = _vm ?? _quickJsVm ?? _wasmVm;
    if (runtimeVm == null) return;
    final nodeId = event.currentTarget?.toString();
    if (nodeId == null || nodeId.isEmpty) return;

    final node = _engine.eventDispatcher.getNode(nodeId);
    final handler = node?.events?[event.type];

    if (handler is! String || handler.isEmpty) return;

    // The Elpian runtime expects typed JSON input for function arguments.
    // Keep this path typed so both native and wasm runtimes decode event args.
    final payload = jsonEncode(
      _toTypedVmValue(
        _eventToJson(event),
      ),
    );
    try {
      await runtimeVm.callFunctionWithInput(handler, payload);
    } catch (e) {
      // Backward compatibility for handlers declared without params in
      // older AST programs/runtimes.
      try {
        await runtimeVm.callFunction(handler);
      } catch (fallbackError) {
        debugPrint(
          'ElpianVmWidget: Error calling event handler "$handler": $e; '
          'fallback failed: $fallbackError',
        );
      }
    }
  }

  Map<String, dynamic> _eventToJson(ElpianEvent event) {
    final base = <String, dynamic>{
      'type': event.type,
      'eventType': event.eventType.name,
      'target': event.target?.toString(),
      'currentTarget': event.currentTarget?.toString(),
      'timestamp': event.timestamp.toIso8601String(),
      'phase': event.phase.name,
      'data': event.data,
    };

    if (event is ElpianPointerEvent) {
      base.addAll({
        'position': {'x': event.position.dx, 'y': event.position.dy},
        'localPosition': {
          'x': event.localPosition.dx,
          'y': event.localPosition.dy,
        },
        'delta': {'x': event.delta.dx, 'y': event.delta.dy},
        'buttons': event.buttons,
        'pressure': event.pressure,
        'distance': event.distance,
        'pointerId': event.pointerId,
      });
    } else if (event is ElpianKeyboardEvent) {
      base.addAll({
        'key': event.key,
        'keyCode': event.keyCode,
        'altKey': event.altKey,
        'ctrlKey': event.ctrlKey,
        'shiftKey': event.shiftKey,
        'metaKey': event.metaKey,
      });
    } else if (event is ElpianInputEvent) {
      base.addAll({
        'value': event.value,
        'inputType': event.inputType,
      });
    } else if (event is ElpianGestureEvent) {
      base.addAll({
        'velocity': {'x': event.velocity.dx, 'y': event.velocity.dy},
        'scale': event.scale,
        'rotation': event.rotation,
        'focalPoint': {'x': event.focalPoint.dx, 'y': event.focalPoint.dy},
      });
    }

    return base;
  }

  Map<String, dynamic> _toTypedVmValue(dynamic value) {
    if (value == null) {
      return const {
        'type': 'null',
        'data': {'value': null},
      };
    }
    if (value is bool) {
      return {
        'type': 'bool',
        'data': {'value': value},
      };
    }
    if (value is int) {
      return {
        'type': 'i64',
        'data': {'value': value},
      };
    }
    if (value is double) {
      return {
        'type': 'f64',
        'data': {'value': value},
      };
    }
    if (value is num) {
      return {
        'type': 'f64',
        'data': {'value': value.toDouble()},
      };
    }
    if (value is String) {
      return {
        'type': 'string',
        'data': {'value': value},
      };
    }
    if (value is List) {
      return {
        'type': 'array',
        'data': {
          'value': value.map(_toTypedVmValue).toList(),
        },
      };
    }
    if (value is Map) {
      final map = <String, dynamic>{};
      for (final entry in value.entries) {
        map[entry.key.toString()] = _toTypedVmValue(entry.value);
      }
      return {
        'type': 'object',
        'data': {'value': map},
      };
    }

    // Fallback: preserve value as a string when type is unknown.
    return {
      'type': 'string',
      'data': {'value': value.toString()},
    };
  }

  Future<void> _callEntryFunction() async {
    final VmRuntimeClient? runtimeVm = _vm ?? _quickJsVm ?? _wasmVm;
    if (runtimeVm == null) return;
    try {
      if (widget.entryInput != null) {
        await runtimeVm.callFunctionWithInput(
          widget.entryFunction!,
          widget.entryInput!,
        );
      } else {
        await runtimeVm.callFunction(widget.entryFunction!);
      }
    } catch (e) {
      debugPrint('ElpianVmWidget: Error calling ${widget.entryFunction}: $e');
    }
  }

  void _applyRenderUpdate(
    Map<String, dynamic> incomingViewJson, {
    String? scopeKey,
  }) {
    final normalizedScopeKey = _normalizeScopeKey(scopeKey);

    if (normalizedScopeKey == null || _currentViewJson == null) {
      _currentViewJson = incomingViewJson;
      return;
    }

    final replacement = _markScopeRerender(
      _ensureNodeKey(incomingViewJson, normalizedScopeKey),
    );
    final replaced = _replaceNodeByKey(
      _currentViewJson!,
      normalizedScopeKey,
      replacement,
      scopeAncestorStack: <Map<String, dynamic>>[],
    );

    if (replaced) {
      return;
    }

    debugPrint(
      'ElpianVmWidget: scope "$normalizedScopeKey" not found. Applying full render.',
    );
    _currentViewJson = incomingViewJson;
  }

  bool _replaceNodeByKey(Map<String, dynamic> node, String targetKey,
      Map<String, dynamic> replacement,
      {required List<Map<String, dynamic>> scopeAncestorStack}) {
    final key = node['key']?.toString();
    if (key == targetKey) {
      node
        ..clear()
        ..addAll(replacement);
      _markScopeNodesForRefresh(scopeAncestorStack);
      return true;
    }

    final isScopeNode = node['type']?.toString() == 'Scope';
    if (isScopeNode) {
      scopeAncestorStack.add(node);
    }

    final children = node['children'];
    if (children is! List) {
      if (isScopeNode) {
        scopeAncestorStack.removeLast();
      }
      return false;
    }

    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      if (child is! Map) continue;

      final childMap = child is Map<String, dynamic>
          ? child
          : Map<String, dynamic>.from(child);
      final replaced = _replaceNodeByKey(
        childMap,
        targetKey,
        replacement,
        scopeAncestorStack: scopeAncestorStack,
      );
      if (!identical(child, childMap)) {
        children[i] = childMap;
      }
      if (replaced) {
        if (isScopeNode) {
          scopeAncestorStack.removeLast();
        }
        return true;
      }
    }

    if (isScopeNode) {
      scopeAncestorStack.removeLast();
    }

    return false;
  }

  String? _normalizeScopeKey(String? scopeKey) {
    if (scopeKey == null) return null;
    final normalized = scopeKey.trim();
    if (normalized.isEmpty || normalized == 'null') return null;
    return normalized;
  }

  Map<String, dynamic> _ensureNodeKey(
    Map<String, dynamic> json,
    String scopeKey,
  ) {
    if ((json['key']?.toString().isNotEmpty ?? false)) {
      return json;
    }
    return <String, dynamic>{
      ...json,
      'key': scopeKey,
    };
  }

  Map<String, dynamic> _markScopeRerender(Map<String, dynamic> json) {
    _markScopeTokensInPlace(json);
    return json;
  }

  void _markScopeNodesForRefresh(List<Map<String, dynamic>> scopeNodes) {
    for (final scopeNode in scopeNodes) {
      final props =
          Map<String, dynamic>.from(scopeNode['props'] as Map? ?? const {});
      props['__scopeRenderToken'] = ++_scopeRenderTokenCounter;
      scopeNode['props'] = props;
    }
  }

  void _markScopeTokensInPlace(dynamic node) {
    if (node is! Map) return;

    final type = node['type']?.toString();
    if (type == 'Scope') {
      final props =
          Map<String, dynamic>.from(node['props'] as Map? ?? const {});
      props['__scopeRenderToken'] = ++_scopeRenderTokenCounter;
      node['props'] = props;
    }

    final children = node['children'];
    if (children is! List) return;
    for (final child in children) {
      _markScopeTokensInPlace(child);
    }
  }

  /// Call a function in the running VM from Dart.
  /// Useful for sending events back to the VM.
  Future<String> callVmFunction(String funcName, {String? input}) async {
    final VmRuntimeClient? runtimeVm = _vm ?? _quickJsVm ?? _wasmVm;
    if (runtimeVm == null) return '';
    if (input != null) {
      return runtimeVm.callFunctionWithInput(funcName, input);
    }
    return runtimeVm.callFunction(funcName);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _vm?.dispose();
    _quickJsVm?.dispose();
    _wasmVm?.dispose();
    _timerHostApi?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(_error!);
      }
      return Container(
        padding: const EdgeInsets.all(16),
        color: Colors.red.withOpacity(0.1),
        child: Text(
          'VM Error: $_error',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }

    if (_isLoading) {
      return widget.loadingWidget ??
          const Center(child: CircularProgressIndicator());
    }

    if (_currentViewJson == null) {
      return const SizedBox.shrink();
    }

    _scheduleHostEnvironmentSync();

    try {
      return _engine.renderFromJson(_currentViewJson!);
    } catch (e) {
      return Container(
        padding: const EdgeInsets.all(16),
        color: Colors.orange.withOpacity(0.1),
        child: Text(
          'Render Error: $e',
          style: const TextStyle(color: Colors.orange),
        ),
      );
    }
  }
}

/// A controller that provides programmatic access to a running ElpianVm
/// within a widget tree. Use with [ElpianVmScope].
class ElpianVmController {
  _ElpianVmScopeState? _state;

  /// Call a function in the VM.
  Future<String> callFunction(String funcName, {String? input}) async {
    if (_state == null) return '';
    return _state!._widget.callVmFunction(funcName, input: input);
  }

  void _attach(_ElpianVmScopeState state) {
    _state = state;
  }

  void _detach() {
    _state = null;
  }
}

/// Wraps [ElpianVmWidget] and provides a [ElpianVmController] for
/// programmatic access to the VM from ancestor widgets.
class ElpianVmScope extends StatefulWidget {
  final ElpianVmController controller;
  final String machineId;
  final String? code;
  final String? astJson;
  final ElpianEngine? engine;
  final Map<String, dynamic>? stylesheet;
  final Widget? loadingWidget;
  final Widget Function(String error)? errorBuilder;
  final void Function(String message)? onPrintln;
  final void Function(Map<String, dynamic> data)? onUpdateApp;
  final Map<String, HostCallHandler>? hostHandlers;
  final String? entryFunction;
  final String? entryInput;
  final ElpianRuntime runtime;

  const ElpianVmScope({
    super.key,
    required this.controller,
    required this.machineId,
    this.code,
    this.astJson,
    this.engine,
    this.stylesheet,
    this.loadingWidget,
    this.errorBuilder,
    this.onPrintln,
    this.onUpdateApp,
    this.hostHandlers,
    this.entryFunction,
    this.entryInput,
    this.runtime = ElpianRuntime.elpian,
  });

  @override
  State<ElpianVmScope> createState() => _ElpianVmScopeState();
}

class _ElpianVmScopeState extends State<ElpianVmScope> {
  final GlobalKey<_ElpianVmWidgetState> _widgetKey = GlobalKey();

  _ElpianVmWidgetState get _widget => _widgetKey.currentState!;

  @override
  void initState() {
    super.initState();
    widget.controller._attach(this);
  }

  @override
  void dispose() {
    widget.controller._detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ElpianVmWidget(
      key: _widgetKey,
      machineId: widget.machineId,
      code: widget.code,
      astJson: widget.astJson,
      engine: widget.engine,
      stylesheet: widget.stylesheet,
      loadingWidget: widget.loadingWidget,
      errorBuilder: widget.errorBuilder,
      onPrintln: widget.onPrintln,
      onUpdateApp: widget.onUpdateApp,
      hostHandlers: widget.hostHandlers,
      entryFunction: widget.entryFunction,
      entryInput: widget.entryInput,
      runtime: widget.runtime,
    );
  }
}
