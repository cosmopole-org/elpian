import 'dart:convert';

import 'package:flutter/material.dart';
import '../core/elpian_engine.dart';
import '../models/elpian_node.dart';
import 'elpian_vm.dart';
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

  @override
  void dispose() {
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
