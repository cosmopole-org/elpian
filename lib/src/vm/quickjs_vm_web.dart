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
  Map<String, dynamic> _globalHostData = const {};
  String? _bootCode;

  QuickJsVm({required this.machineId});

  static Future<void> initialize() async {}

  static Future<QuickJsVm> fromCode(String machineId, String code) async {
    final vm = QuickJsVm(machineId: machineId);
    vm._bootstrapHostBridge();
    await vm._initMachine();
    vm._bootCode = code;
    return vm;
  }

  static Future<QuickJsVm> fromAst(String machineId, String astJson) async {
    throw UnsupportedError(
      'QuickJS runtime expects JavaScript source in `code`; AST JSON is only supported by the Elpian runtime.',
    );
  }

  void _bootstrapHostBridge() {
    globalContext.setProperty(
      '__elpianQuickJsHostCall'.toJS,
      ((String machineId, String apiName, String payload) {
        if (machineId != this.machineId) {
          return '{"type":"i16","data":{"value":0}}';
        }
        return _syncHostCall(apiName, payload);
      }).toJS,
    );
  }

  Future<void> _initMachine() async {
    await _callAsync(
      method: 'initMachine',
      args: [machineId.toJS],
    );
  }

  String _syncHostCall(String apiName, String payload) {
    return _dispatchHostCall(apiName, payload);
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

  @override
  Future<void> setGlobalHostData(Map<String, dynamic> data) async {
    _globalHostData = Map<String, dynamic>.from(data);
    final encoded = jsonEncode(jsonEncode(_globalHostData));
    await _callAsync(
      method: 'evalCode',
      args: [
        machineId.toJS,
        '''
          (function() {
            var __env = JSON.parse($encoded);
            globalThis.__ELPIAN_HOST_ENV__ = __env;
            globalThis.ELPIAN_HOST_ENV = __env;
            globalThis.getElpianHostEnv = function() { return globalThis.__ELPIAN_HOST_ENV__; };
          })();
        '''
            .toJS
      ],
    );
  }

  Future<String> _callAsync(
      {required String method, required List<JSAny?> args}) async {
    final quickJs = globalContext['elpianQuickJs'];
    if (quickJs == null) {
      throw StateError(
        'QuickJS web runtime not loaded. Ensure '
        'assets/packages/elpian_ui/assets/web_runtime/quickjs_web_runtime.js is included in your web index.html.',
      );
    }

    final result = (quickJs as JSObject).callMethodVarArgs(method.toJS, args);

    final jsValue = result.dartify();

    if (jsValue == null ||
        jsValue is String ||
        jsValue is num ||
        jsValue is bool) {
      return jsValue?.toString() ?? '';
    }

    final jsResultObject = result as Object;
    if (jsResultObject is JSPromise) {
      final value = await jsResultObject.toDart;
      return value?.toString() ?? '';
    }

    return jsResultObject.toString();
  }

  Future<String> runCode(String code) {
    return _callAsync(
      method: 'evalCode',
      args: [machineId.toJS, code.toJS],
    );
  }

  @override
  Future<String> run() async {
    final code = _bootCode;
    if (code == null || code.isEmpty) return '';
    return runCode(code);
  }

  @override
  Future<String> callFunction(String funcName) {
    return _callAsync(
      method: 'callFunction',
      args: [machineId.toJS, funcName.toJS],
    );
  }

  @override
  Future<String> callFunctionWithInput(String funcName, String inputJson) {
    return _callAsync(
      method: 'callFunctionWithInput',
      args: [machineId.toJS, funcName.toJS, inputJson.toJS],
    );
  }

  String _dispatchHostCall(String apiName, String payload) {
    final handler = _hostHandlers[apiName];
    if (handler != null) {
      final result = handler(apiName, payload);
      if (result is String) return result;
      return '{"type":"i16","data":{"value":0}}';
    }

    if (_defaultHostHandler != null) {
      final result = _defaultHostHandler!(apiName, payload);
      if (result is String) return result;
      return '{"type":"i16","data":{"value":0}}';
    }

    if (apiName == 'println') {
      debugPrint('QuickJsVm[$machineId]: $payload');
    }
    if (apiName == 'env.get') {
      return jsonEncode({
        'type': 'object',
        'data': {'value': _globalHostData},
      });
    }
    if (apiName == 'stringify') {
      return '{"type":"string","data":{"value":${jsonEncode(payload)}}}';
    }
    return '{"type":"i16","data":{"value":0}}';
  }

  @override
  Future<void> dispose() async {
    try {
      await _callAsync(
        method: 'disposeMachine',
        args: [machineId.toJS],
      );
    } catch (_) {
      // no-op for teardown safety.
    }
  }
}
