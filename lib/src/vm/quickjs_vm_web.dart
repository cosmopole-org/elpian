import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';

import 'elpian_vm.dart';

class QuickJsVm {
  final String machineId;
  final Map<String, HostCallHandler> _hostHandlers = {};
  HostCallHandler? _defaultHostHandler;

  QuickJsVm({required this.machineId});

  static Future<void> initialize() async {}

  static Future<QuickJsVm> fromCode(String machineId, String code) async {
    final vm = QuickJsVm(machineId: machineId);
    vm._bootstrapHostBridge();
    await vm.runCode(code);
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
    // Web bridge keeps host-call lifecycle identical for render/updateApp/println.
    String response = '{"type":"i16","data":{"value":0}}';
    _handleHostCall(apiName, payload).then((value) => response = value);
    return response;
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

  Future<String> run() async => '';

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
