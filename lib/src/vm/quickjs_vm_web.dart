import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';

import 'elpian_vm.dart';
import 'vm_runtime_client.dart';

class QuickJsVm implements VmRuntimeClient {
  final String machineId;
  final Map<String, HostCallHandler> _hostHandlers = {};
  HostCallHandler? _defaultHostHandler;
  String? _bootCode;

  QuickJsVm({required this.machineId});

  static Future<void> initialize() async {}

  static Future<QuickJsVm> fromCode(String machineId, String code) async {
    final vm = QuickJsVm(machineId: machineId);
    vm._bootstrapHostBridge();
    vm._bootCode = code;
    return vm;
  }

  static Future<QuickJsVm> fromAst(String machineId, String astJson) async {
    throw UnsupportedError(
      'QuickJS runtime expects JavaScript source in `code`; AST JSON is only supported by the Elpian runtime.',
    );
  }

  void _bootstrapHostBridge() {
    final global = globalContext;
    global.setProperty(
      'askHost'.toJS,
      ((String apiName, String payload) => _syncHostCall(apiName, payload)).toJS,
    );

    // Normalize payloads to string on the JS side so Dart bridge types stay stable.
    global.callMethod(
      'eval'.toJS,
      [
        '''
          (function() {
            const _askHostRaw = globalThis.askHost;
            globalThis.askHost = function(apiName, payload) {
              const normalized = typeof payload === 'string'
                ? payload
                : JSON.stringify(payload);
              return _askHostRaw(apiName, normalized);
            };
          })();
        '''.toJS,
      ].toJS,
    );
  }

  String _syncHostCall(String apiName, String payload) {
    _dispatchHostCall(apiName, payload);

    if (apiName == 'stringify') {
      return '{"type":"string","data":{"value":${jsonEncode(payload)}}}';
    }
    return '{"type":"i16","data":{"value":0}}';
  }

  void registerHostHandler(String apiName, HostCallHandler handler) {
    _hostHandlers[apiName] = handler;
  }

  void setDefaultHostHandler(HostCallHandler handler) {
    _defaultHostHandler = handler;
  }

  Future<String> runCode(String code) async {
    final result = globalContext.callMethod('eval'.toJS, [code.toJS].toJS);
    return result.dartify()?.toString() ?? '';
  }

  Future<String> run() async {
    final code = _bootCode;
    if (code == null || code.isEmpty) return '';
    return runCode(code);
  }

  Future<String> callFunction(String funcName) async {
    final result = globalContext.callMethod('eval'.toJS, ['$funcName();'.toJS].toJS);
    return result.dartify()?.toString() ?? '';
  }

  Future<String> callFunctionWithInput(String funcName, String inputJson) async {
    final escaped = jsonEncode(inputJson);
    final result = globalContext.callMethod(
      'eval'.toJS,
      ['$funcName(JSON.parse($escaped));'.toJS].toJS,
    );
    return result.dartify()?.toString() ?? '';
  }

  void _dispatchHostCall(String apiName, String payload) {
    final handler = _hostHandlers[apiName];
    if (handler != null) {
      handler(apiName, payload);
      return;
    }

    if (_defaultHostHandler != null) {
      _defaultHostHandler!(apiName, payload);
      return;
    }

    if (apiName == 'println') {
      debugPrint('QuickJsVm[$machineId]: $payload');
    }
  }

  Future<void> dispose() async {}
}
