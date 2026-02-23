import 'dart:convert';

import 'package:flutter/material.dart';
import '../core/elpian_engine.dart';
import '../core/event_system.dart';
import '../models/elpian_node.dart';
import 'elpian_vm.dart';
import 'quickjs_vm.dart';
import 'runtime_kind.dart';
import 'wasm_vm.dart';
import 'vm_runtime_client.dart';
import 'host_api_catalog.dart';
import 'host_handler.dart';

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

class _ElpianVmWidgetState extends State<ElpianVmWidget> {
  late ElpianEngine _engine;
  ElpianVm? _vm;
  QuickJsVm? _quickJsVm;
  WasmVm? _wasmVm;
  Map<String, dynamic>? _currentViewJson;
  String? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _engine = widget.engine ?? ElpianEngine();
    if (widget.stylesheet != null) {
      _engine.loadStylesheet(widget.stylesheet!);
    }
    _initVm();
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
            _error = detail == null ? 'Failed to create VM' : 'Failed to create VM: $detail';
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
        onRender: (viewJson) {
          if (mounted) {
            setState(() {
              _currentViewJson = viewJson;
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
      );

      // Register built-in host handlers (core + DOM + Canvas APIs).
      final VmRuntimeClient runtimeVm = _vm ?? _quickJsVm ?? _wasmVm!;
      final hostHandlers = <String, HostCallHandler>{
        for (final apiName in VmHostApiCatalog.allHostApiNames)
          apiName: (name, payload) => hostHandler.handleHostCall(name, payload),
        ...?widget.hostHandlers,
      };
      runtimeVm.registerHostHandlers(hostHandlers);

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

    final payload = jsonEncode(_eventToJson(event));
    try {
      await runtimeVm.callFunctionWithInput(handler, payload);
    } catch (e) {
      debugPrint('ElpianVmWidget: Error calling event handler "$handler": $e');
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
    _vm?.dispose();
    _quickJsVm?.dispose();
    _wasmVm?.dispose();
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
