import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'frb_generated/api.dart'
    if (dart.library.js_interop) 'frb_generated/api_web.dart';
import 'vm_runtime_client.dart';

/// Callback for handling host function calls from the Rust VM.
///
/// The VM sandbox calls host functions via `askHost(apiName, payload)`.
/// This callback receives the API name and JSON payload, and should
/// return a JSON response in the typed value format:
/// `{"type": "string", "data": {"value": "hello"}}`
typedef HostCallHandler = Future<String> Function(
  String apiName,
  String payload,
);

/// Represents the Elpian Rust VM instance managed from Dart.
///
/// This class wraps the Flutter Rust Bridge API to provide a convenient
/// interface for creating, running, and interacting with the sandboxed
/// JS-like VM. It handles the host call loop automatically, routing
/// calls like `render` and `updateApp` to registered handlers.
class ElpianVm implements VmRuntimeClient {
  final String machineId;
  final Map<String, HostCallHandler> _hostHandlers = {};
  HostCallHandler? _defaultHostHandler;
  bool _isRunning = false;
  int _cbCounter = 0;

  ElpianVm({required this.machineId});

  /// Whether the VM is currently executing.
  bool get isRunning => _isRunning;

  /// Last low-level FRB/FFI error (if any).
  static String? get lastApiError => ElpianVmApi.lastError;

  /// Initialize the VM subsystem. Call once at app startup before
  /// creating any VM instances.
  static Future<void> initialize() async {
    await ElpianVmApi.initVmSystem();
  }

  /// Create a VM from AST JSON (the Elpian compiler format).
  ///
  /// Example AST:
  /// ```json
  /// {
  ///   "type": "program",
  ///   "body": [
  ///     {"type": "definition", "data": {"leftSide": {...}, "rightSide": {...}}}
  ///   ]
  /// }
  /// ```
  static Future<ElpianVm?> fromAst(String machineId, String astJson) async {
    final success = await ElpianVmApi.createVmFromAst(
      machineId: machineId,
      astJson: astJson,
    );
    if (!success) return null;
    return ElpianVm(machineId: machineId);
  }

  /// Create a VM from source code string.
  static Future<ElpianVm?> fromCode(String machineId, String code) async {
    final success = await ElpianVmApi.createVmFromCode(
      machineId: machineId,
      code: code,
    );
    if (!success) return null;
    return ElpianVm(machineId: machineId);
  }

  /// Register a handler for a specific host API function.
  ///
  /// The VM's allowed host APIs are: `println`, `stringify`, `render`, `updateApp`.
  /// Register handlers for the ones you want to intercept.
  void registerHostHandler(String apiName, HostCallHandler handler) {
    _hostHandlers[apiName] = handler;
  }

  /// Set a default handler for any unregistered host API calls.
  void setDefaultHostHandler(HostCallHandler handler) {
    _defaultHostHandler = handler;
  }

  /// Execute the VM's main program and process all host calls
  /// until completion.
  Future<String> run() async {
    _isRunning = true;
    try {
      var result = await ElpianVmApi.executeVm(machineId: machineId);
      return await _processExecutionLoop(result);
    } finally {
      _isRunning = false;
    }
  }

  /// Execute a named function in the VM.
  Future<String> callFunction(String funcName) async {
    _isRunning = true;
    _cbCounter++;
    try {
      var result = await ElpianVmApi.executeVmFunc(
        machineId: machineId,
        funcName: funcName,
        cbId: _cbCounter,
      );
      return await _processExecutionLoop(result);
    } finally {
      _isRunning = false;
    }
  }

  /// Execute a named function with typed JSON input.
  ///
  /// The input should be in the Elpian typed value format:
  /// ```json
  /// {"type": "string", "data": {"value": "hello"}}
  /// ```
  Future<String> callFunctionWithInput(String funcName, String inputJson) async {
    _isRunning = true;
    _cbCounter++;
    try {
      var result = await ElpianVmApi.executeVmFuncWithInput(
        machineId: machineId,
        funcName: funcName,
        inputJson: inputJson,
        cbId: _cbCounter,
      );
      return await _processExecutionLoop(result);
    } finally {
      _isRunning = false;
    }
  }

  /// Process the execution loop, handling host calls until the VM
  /// completes or encounters an error.
  Future<String> _processExecutionLoop(VmExecResult result) async {
    while (result.hasHostCall) {
      // Parse the host call request
      final hostCallData = jsonDecode(result.hostCallData) as Map<String, dynamic>;
      final apiName = hostCallData['apiName'] as String;
      final payload = hostCallData['payload'] as String;

      // Route to the appropriate handler
      String response;
      try {
        response = await _handleHostCall(apiName, payload);
      } catch (e) {
        debugPrint('ElpianVm: Host call error for $apiName: $e');
        response = '{"type": "string", "data": {"value": "error: $e"}}';
      }

      // Continue VM execution with the response
      result = await ElpianVmApi.continueExecution(
        machineId: machineId,
        inputJson: response,
      );
    }

    return result.resultValue;
  }

  /// Handle a host call by routing to registered handlers.
  Future<String> _handleHostCall(String apiName, String payload) async {
    // Check for a registered handler
    final handler = _hostHandlers[apiName];
    if (handler != null) {
      return await handler(apiName, payload);
    }

    // Check for a default handler
    if (_defaultHostHandler != null) {
      return await _defaultHostHandler!(apiName, payload);
    }

    // Built-in handlers for common APIs
    switch (apiName) {
      case 'println':
        debugPrint('ElpianVm[$machineId]: $payload');
        return '{"type": "i16", "data": {"value": 0}}';
      case 'stringify':
        return '{"type": "string", "data": {"value": ${jsonEncode(payload)}}}';
      default:
        debugPrint('ElpianVm: Unhandled host call: $apiName');
        return '{"type": "i16", "data": {"value": 0}}';
    }
  }

  /// Destroy this VM instance and release Rust-side resources.
  Future<void> dispose() async {
    await ElpianVmApi.destroyVm(machineId: machineId);
  }
}
