import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';

import 'elpian_vm.dart';
import 'vm_runtime_client.dart';

/// A QuickJS-backed runtime that mirrors [ElpianVm]'s host API lifecycle.
class QuickJsVm implements VmRuntimeClient {
  final String machineId;
  final Map<String, HostCallHandler> _hostHandlers = {};
  HostCallHandler? _defaultHostHandler;

  late final JavascriptRuntime _runtime;
  bool _initialized = false;
  String? _bootCode;

  QuickJsVm({required this.machineId});

  static Future<void> initialize() async {
    // flutter_js runtime is initialized per VM instance.
  }

  static Future<QuickJsVm> fromCode(String machineId, String code) async {
    final vm = QuickJsVm(machineId: machineId);
    await vm._init();
    vm._bootstrapHostBridge();
    vm._bootCode = code;
    return vm;
  }

  /// QuickJS mode executes raw JavaScript; AST input is not supported.
  static Future<QuickJsVm> fromAst(String machineId, String astJson) async {
    throw UnsupportedError(
      'QuickJS runtime expects JavaScript source in `code`; AST JSON is only supported by the Elpian runtime.',
    );
  }

  Future<void> _init() async {
    if (_initialized) return;
    _runtime = getJavascriptRuntime();
    _initialized = true;
  }

  void _bootstrapHostBridge() {
    _runtime.onMessage('elpianHost', (dynamic args) {
      try {
        final request = _normalizeHostRequest(args);
        final apiName = request['apiName']!;
        final payload = request['payload']!;

        return _dispatchHostCall(apiName, payload);
      } catch (e) {
        debugPrint('QuickJsVm[$machineId]: host bridge error: $e');
        return '{"type":"i16","data":{"value":0}}';
      }
    });

    _runtime.evaluate('''
      globalThis.askHost = function(apiName) {
        var args = Array.prototype.slice.call(arguments, 1);
        var payload = '';
        if (args.length === 1) {
          payload = args[0];
        } else if (args.length > 1) {
          payload = args;
        }
        return sendMessage('elpianHost', JSON.stringify({
          apiName: apiName,
          payload: payload
        }));
      };
    ''');
  }

  Map<String, String> _normalizeHostRequest(dynamic raw) {
    dynamic request = raw;

    if (request is List && request.isNotEmpty) {
      request = request.first;
    }

    if (request is String) {
      final decoded = jsonDecode(request);
      if (decoded is Map<String, dynamic>) {
        request = decoded;
      }
    }

    if (request is Map) {
      final apiName = request['apiName']?.toString() ?? '';
      final payloadRaw = request['payload'];
      final payload =
          payloadRaw is String ? payloadRaw : jsonEncode(payloadRaw);
      return {'apiName': apiName, 'payload': payload};
    }

    throw StateError('Unsupported host message format: ${request.runtimeType}');
  }

  @override
  void registerHostHandler(String apiName, HostCallHandler handler) {
    _hostHandlers[apiName] = handler;
  }

  @override
  void registerHostHandlers(Map<String, HostCallHandler> handlers) {
    _hostHandlers.addAll(handlers);
  }

  @override
  void setDefaultHostHandler(HostCallHandler handler) {
    _defaultHostHandler = handler;
  }

  Future<String> runCode(String code) async {
    final result = _runtime.evaluate(code);
    return result.stringResult;
  }

  Future<String> run() async {
    final code = _bootCode;
    if (code == null || code.isEmpty) return '';
    return runCode(code);
  }

  Future<String> callFunction(String funcName) async {
    final result = _runtime.evaluate('$funcName();');
    return result.stringResult;
  }

  Future<String> callFunctionWithInput(
      String funcName, String inputJson) async {
    final escaped = jsonEncode(inputJson);
    final result = _runtime.evaluate('$funcName(JSON.parse($escaped));');
    return result.stringResult;
  }

  String _dispatchHostCall(String apiName, String payload) {
    final handler = _hostHandlers[apiName];
    if (handler != null) {
      final result = handler(apiName, payload);
      if (result is String) return result;
      return '{\"type\":\"i16\",\"data\":{\"value\":0}}';
    }

    if (_defaultHostHandler != null) {
      final result = _defaultHostHandler!(apiName, payload);
      if (result is String) return result;
      return '{\"type\":\"i16\",\"data\":{\"value\":0}}';
    }

    if (apiName == 'println') {
      debugPrint('QuickJsVm[$machineId]: $payload');
    }
    if (apiName == 'stringify') {
      return '{\"type\":\"string\",\"data\":{\"value\":${jsonEncode(payload)}}}';
    }
    return '{\"type\":\"i16\",\"data\":{\"value\":0}}';
  }

  Future<void> dispose() async {
    _runtime.dispose();
  }
}
