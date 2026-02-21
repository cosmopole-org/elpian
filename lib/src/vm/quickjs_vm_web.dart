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
      ((String apiName, String payload) => _syncHostCall(apiName, payload))
          .toJS,
    );
  }

  String _syncHostCall(String apiName, String payload) {
    // Trigger host handlers; JS interop callback itself must return synchronously.
    _handleHostCall(apiName, payload);

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

  Future<String> _handleHostCall(String apiName, String payload) async {
    final handler = _hostHandlers[apiName];
    if (handler != null) {
      return handler(apiName, payload);
    }

    if (_defaultHostHandler != null) {
      return _defaultHostHandler!(apiName, payload);
    }

    switch (apiName) {
      case 'println':
        debugPrint('QuickJsVm[$machineId]: $payload');
        return '{"type":"i16","data":{"value":0}}';
      case 'stringify':
        return '{"type":"string","data":{"value":${jsonEncode(payload)}}}';
      default:
        debugPrint('QuickJsVm[$machineId]: Unhandled host call: $apiName');
        return '{"type":"i16","data":{"value":0}}';
    }
  }

  Future<void> dispose() async {}
}
