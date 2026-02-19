import 'dart:convert';

import 'package:flutter/material.dart';
import '../core/elpian_engine.dart';
import '../core/event_system.dart';
import '../models/elpian_node.dart';
import 'elpian_vm.dart';
import 'host_handler.dart';

/// A Flutter widget that runs an Elpian Rust VM sandbox and renders
/// the view tree it produces via the ElpianEngine.
///
/// The VM accepts an AST program in JSON format. The AST can use
/// `host_call` nodes (or the equivalent `askHost` function call) to
/// communicate with Flutter — most importantly `render`, which sends
/// a JSON view tree for the engine to display.
///
/// ## Automatic Event Handling
///
/// When the rendered view tree contains nodes with an `"events"` map whose
/// values are **strings** (VM function names), the engine automatically
/// calls the corresponding VM function when that event fires. The VM
/// function receives a typed event object with `type`, `target`, and
/// event-specific fields (`x`/`y`, `key`, `value`, `scale`, etc.).
///
/// ## Usage
///
/// ```dart
/// ElpianVmWidget.fromAst(
///   machineId: 'my-app',
///   astJson: jsonEncode({
///     "type": "program",
///     "body": [
///       {
///         "type": "host_call",
///         "data": {
///           "name": "render",
///           "args": [{
///             "type": "object",
///             "data": { "value": {
///               "type": { "type": "string", "data": { "value": "Text" } },
///               "props": { "type": "object", "data": { "value": {
///                 "data": { "type": "string", "data": { "value": "Hello from VM!" } }
///               }}}
///             }}
///           }]
///         }
///       }
///     ]
///   }),
/// )
/// ```
class ElpianVmWidget extends StatefulWidget {
  /// Unique identifier for this VM instance.
  final String machineId;

  /// Source code to run in the VM (mutually exclusive with [astJson]).
  final String? code;

  /// AST JSON to run in the VM (mutually exclusive with [code]).
  final String? astJson;

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
  }) : astJson = null;

  @override
  State<ElpianVmWidget> createState() => _ElpianVmWidgetState();
}

class _ElpianVmWidgetState extends State<ElpianVmWidget> {
  late ElpianEngine _engine;
  ElpianVm? _vm;
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
      // Create the VM
      ElpianVm? vm;
      if (widget.code != null) {
        vm = await ElpianVm.fromCode(widget.machineId, widget.code!);
      } else if (widget.astJson != null) {
        vm = await ElpianVm.fromAst(widget.machineId, widget.astJson!);
      }

      if (vm == null) {
        setState(() {
          _error = 'Failed to create VM';
          _isLoading = false;
        });
        return;
      }

      _vm = vm;

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

      // Register built-in host handlers
      vm.registerHostHandler('render', (apiName, payload) {
        return hostHandler.handleRender(payload);
      });
      vm.registerHostHandler('updateApp', (apiName, payload) {
        return hostHandler.handleUpdateApp(payload);
      });
      vm.registerHostHandler('println', (apiName, payload) {
        return hostHandler.handlePrintln(payload);
      });
      vm.registerHostHandler('stringify', (apiName, payload) {
        return hostHandler.handleStringify(payload);
      });

      // Register additional host handlers
      widget.hostHandlers?.forEach((name, handler) {
        vm!.registerHostHandler(name, handler);
      });

      // Wire up automatic VM event callback bridge.
      // When the rendered UI contains event handlers that are strings
      // (VM function names), the EventDispatcher routes them here so
      // the VM function is executed automatically.
      _engine.eventDispatcher.vmEventCallback = (funcName, event) async {
        if (_vm == null || _vm!.isRunning) return;
        try {
          final eventJson = _eventToTypedJson(event);
          await _vm!.callFunctionWithInput(funcName, eventJson);
        } catch (e) {
          debugPrint(
            'ElpianVmWidget: Error calling VM function "$funcName": $e',
          );
        }
      };

      // Execute the VM
      await vm.run();

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

  Future<void> _callEntryFunction() async {
    if (_vm == null) return;
    try {
      if (widget.entryInput != null) {
        await _vm!.callFunctionWithInput(
          widget.entryFunction!,
          widget.entryInput!,
        );
      } else {
        await _vm!.callFunction(widget.entryFunction!);
      }
    } catch (e) {
      debugPrint('ElpianVmWidget: Error calling ${widget.entryFunction}: $e');
    }
  }

  /// Call a function in the running VM from Dart.
  /// Useful for sending events back to the VM.
  Future<String> callVmFunction(String funcName, {String? input}) async {
    if (_vm == null) return '';
    if (input != null) {
      return _vm!.callFunctionWithInput(funcName, input);
    }
    return _vm!.callFunction(funcName);
  }

  /// Convert an [ElpianEvent] to the VM's typed-value JSON format so
  /// it can be passed as input to a VM function.
  ///
  /// The resulting JSON is an object with at least `type` and `target`
  /// fields, plus subclass-specific fields (position, key, value, …).
  String _eventToTypedJson(ElpianEvent event) {
    Map<String, dynamic> str(String v) =>
        {'type': 'string', 'data': {'value': v}};
    Map<String, dynamic> f64(double v) =>
        {'type': 'f64', 'data': {'value': v}};
    Map<String, dynamic> i32(int v) =>
        {'type': 'i32', 'data': {'value': v}};

    final fields = <String, dynamic>{
      'type': str(event.type),
      'target': str(event.target?.toString() ?? ''),
    };

    if (event is ElpianPointerEvent) {
      fields['x'] = f64(event.position.dx);
      fields['y'] = f64(event.position.dy);
      fields['localX'] = f64(event.localPosition.dx);
      fields['localY'] = f64(event.localPosition.dy);
    } else if (event is ElpianKeyboardEvent) {
      fields['key'] = str(event.key);
      fields['keyCode'] = i32(event.keyCode);
    } else if (event is ElpianInputEvent) {
      fields['value'] = str(event.value?.toString() ?? '');
    } else if (event is ElpianGestureEvent) {
      fields['scale'] = f64(event.scale);
      fields['rotation'] = f64(event.rotation);
    }

    return jsonEncode({
      'type': 'object',
      'data': {'value': fields},
    });
  }

  @override
  void dispose() {
    // Remove the VM event bridge so the singleton dispatcher
    // doesn't hold a reference to a disposed widget.
    _engine.eventDispatcher.vmEventCallback = null;
    _vm?.dispose();
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
    );
  }
}
