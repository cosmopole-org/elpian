import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';

import '../diagnostics/elpian_trace.dart';
import 'elpian_vm.dart';
import 'governance/host_side_governor.dart';
import 'vm_runtime_client.dart';

class QuickJsVm implements VmRuntimeClient {
  final String machineId;
  final Map<String, HostCallHandler> _hostHandlers = {};
  HostCallHandler? _defaultHostHandler;
  Map<String, dynamic> _globalHostData = const {};
  String? _bootCode;

  /// Per-machine host-call handlers, keyed by `machineId`. The browser exposes a
  /// SINGLE global `__elpianQuickJsHostCall`, so every live VM must share it and
  /// be dispatched to by id. (Previously each VM overwrote the global with a
  /// closure bound to its own id, so on a screen with more than one live VM —
  /// e.g. a page poller plus a client-component stage shell — only the
  /// last-created VM's `host.render`/`host.fetch`/`host.submit` calls were
  /// honoured and every other VM's calls were silently dropped.)
  static final Map<String, String Function(String apiName, String payload)>
      _hostCallRegistry = {};
  static bool _globalBridgeInstalled = false;

  QuickJsVm({required this.machineId});

  static const String _label = 'QuickJs';

  /// Governs this instance at the host-call seam.
  ///
  /// This engine exposes no interrupt hook through its Dart API, so an
  /// instruction budget cannot be enforced here — `governanceSupport` says so
  /// rather than implying protection that is not there.
  @override
  late final HostSideGovernor governor = HostSideGovernor(
    machineId: machineId,
    enforcesInstructionBudget: false,
    onTerminate: () {
      unawaited(dispose());
    },
  );

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
    // Register this VM's handler, then install the SINGLE shared global
    // dispatcher exactly once. The dispatcher routes each call to the VM named
    // by `machineId`, so every live VM keeps working no matter the create order.
    _hostCallRegistry[machineId] = _syncHostCall;
    if (_globalBridgeInstalled) return;
    _globalBridgeInstalled = true;
    globalContext.setProperty(
      '__elpianQuickJsHostCall'.toJS,
      ((String machineId, String apiName, String payload) {
        final handler = _hostCallRegistry[machineId];
        if (handler == null) {
          return '{"type":"i16","data":{"value":0}}';
        }
        return handler(apiName, payload);
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
    if (apiName == 'render' || apiName == 'fetch' || apiName == 'submit') {
      ElpianTrace.mark('vm[$machineId] host.$apiName');
    }
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
    // The capability gate. Every host call a mini app makes crosses here, so
    // this is where a QuickJS/WASM guest is bounded — the engine itself gives
    // Dart no other seam. A denied call gets the typed null the Elpian VM
    // produces for the same case, so a guest sees one behaviour across all
    // three runtimes.
    final refusal = governor.checkAndCharge(apiName, bytes: payload.length);
    if (refusal != null) {
      assert(() {
        debugPrint('$_label[$machineId]: $apiName refused — $refusal');
        return true;
      }());
      return '{"type":"null","data":{"value":null}}';
    }

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
    _hostCallRegistry.remove(machineId);
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
