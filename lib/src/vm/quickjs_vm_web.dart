import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:js_util' as js_util;

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
    _dispatchHostCall(apiName, payload);

    if (apiName == 'stringify') {
      return '{"type":"string","data":{"value":${jsonEncode(payload)}}}';
    }
    return '{"type":"i16","data":{"value":0}}';
  }

  @override
  void registerHostHandler(String apiName, HostCallHandler handler) {
    _hostHandlers[apiName] = handler;
  }

  @override
  void setDefaultHostHandler(HostCallHandler handler) {
    _defaultHostHandler = handler;
  }

  Future<String> _callAsync({required String method, required List<JSAny?> args}) async {
    final quickJs = globalContext['elpianQuickJs'];
    if (quickJs == null) {
      throw StateError(
        'QuickJS web runtime not loaded. Ensure web/quickjs_web_runtime.js is included in index.html.',
      );
    }

    final result = (quickJs as JSObject).callMethodVarArgs(method.toJS, args);
    final value = await js_util.promiseToFuture<Object?>(result as Object);
    return value?.toString() ?? '';
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

  void _dispatchHostCall(String apiName, String payload) {
    final handler = _hostHandlers[apiName];
    if (handler != null) {
      unawaited(handler(apiName, payload));
      return;
    }

    if (_defaultHostHandler != null) {
      unawaited(_defaultHostHandler!(apiName, payload));
      return;
    }

    if (apiName == 'println') {
      debugPrint('QuickJsVm[$machineId]: $payload');
    }
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
