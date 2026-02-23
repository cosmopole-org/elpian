import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:wasm_run_flutter/wasm_run_flutter.dart';

import 'elpian_vm.dart';
import 'vm_runtime_client.dart';

class WasmVm implements VmRuntimeClient {
  final String machineId;
  final Map<String, HostCallHandler> _hostHandlers = {};
  HostCallHandler? _defaultHostHandler;

  WasmModule? _module;
  WasmInstance? _instance;
  WasmMemory? _memory;
  _WasmVmConfig? _config;

  String? _bootCode;

  static bool _runtimeInitialized = false;

  WasmVm({required this.machineId});

  static Future<void> initialize() async {
    if (_runtimeInitialized) return;
    WasmRunFlutterNative.registerWith();
    _runtimeInitialized = true;
  }

  static Future<WasmVm> fromCode(String machineId, String code) async {
    final vm = WasmVm(machineId: machineId);
    vm._bootCode = code;
    return vm;
  }

  static Future<WasmVm> fromAst(String machineId, String astJson) async {
    throw UnsupportedError('WASM runtime expects JSON runtime config in `code`.');
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
  Future<String> run() async {
    final code = _bootCode;
    if (code == null || code.isEmpty) return '';

    await _ensureLoaded(code);
    final run = _requireFunction(_config!.exports.run);
    run.call(const []);
    return _readResultString();
  }

  @override
  Future<String> callFunction(String funcName) async {
    _assertLoaded();

    final fnText = _writeString(funcName);
    try {
      _requireFunction(_config!.exports.callFunction).call([fnText.ptr, fnText.length]);
      return _readResultString();
    } finally {
      _dealloc(fnText);
    }
  }

  @override
  Future<String> callFunctionWithInput(String funcName, String inputJson) async {
    _assertLoaded();

    final fnText = _writeString(funcName);
    final inputText = _writeString(inputJson);
    try {
      _requireFunction(_config!.exports.callFunctionWithInput)
          .call([fnText.ptr, fnText.length, inputText.ptr, inputText.length]);
      return _readResultString();
    } finally {
      _dealloc(fnText);
      _dealloc(inputText);
    }
  }

  Future<void> _ensureLoaded(String configJson) async {
    if (_instance != null) return;

    final config = _WasmVmConfig.fromJson(configJson);
    final wasmBytes = await _loadWasmBytes(config);

    final module = await compileWasmModule(wasmBytes);
    final builder = module.builder();

    for (final import in module.getImports()) {
      if (import.kind != WasmExternalKind.function) continue;

      final funcTy = import.type?.maybeWhen(
        func: (field0) => field0,
        orElse: () => null,
      );

      final params = List<ValueTy?>.from(funcTy?.parameters ?? const <ValueTy>[]);
      final results = funcTy?.results;

      builder.addImport(
        import.module,
        import.name,
        WasmFunction(
          (Object? _, [Object? __, Object? ___, Object? ____, Object? _____, Object? ______]) {},
          name: '${import.module}.${import.name}',
          params: params,
          results: results,
          call: ([List<Object?>? args]) =>
              _handleImportedFunction(import.name, args ?? const []),
        ),
      );
    }

    final instance = await builder.build();

    final memory = instance.getMemory(config.exports.memory) ??
        instance.exports.values.whereType<WasmMemory>().firstOrNull;

    if (memory == null) {
      throw StateError('WASM memory export not found: ${config.exports.memory}');
    }

    _config = config;
    _module = module;
    _instance = instance;
    _memory = memory;
  }

  List<Object?> _handleImportedFunction(String importName, List<Object?> args) {
    if (importName != 'elpian_host_call') {
      return const [0];
    }

    if (args.length < 6) {
      return const [0];
    }

    final apiPtr = _intArg(args[0]);
    final apiLen = _intArg(args[1]);
    final payloadPtr = _intArg(args[2]);
    final payloadLen = _intArg(args[3]);
    final outPtr = _intArg(args[4]);
    final outCap = _intArg(args[5]);

    final apiName = _readString(apiPtr, apiLen);
    final payload = _readString(payloadPtr, payloadLen);

    final response = _dispatchHostCall(apiName, payload);
    final written = _writeStringInto(response, outPtr, outCap);
    return [written];
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
      debugPrint('WasmVm[$machineId]: $payload');
    }
    if (apiName == 'stringify') {
      return jsonEncode({
        'type': 'string',
        'data': {'value': payload},
      });
    }
    return '{"type":"i16","data":{"value":0}}';
  }

  WasmFunction _requireFunction(String name) {
    final instance = _instance;
    if (instance == null) {
      throw StateError('WASM instance is not loaded.');
    }
    final fn = instance.getFunction(name);
    if (fn == null) {
      throw StateError('WASM function export not found: $name');
    }
    return fn;
  }

  _WasmTextRef _writeString(String text) {
    final utf8 = utf8Encode(text);
    final alloc = _requireFunction(_config!.exports.alloc);
    final result = alloc.call([utf8.length]);
    final ptr = result.isEmpty ? 0 : _intArg(result.first);
    if (ptr <= 0) {
      throw StateError('WASM alloc returned invalid pointer for length ${utf8.length}.');
    }

    final memory = _memory!.view;
    final end = ptr + utf8.length;
    if (end > memory.length) {
      throw StateError('WASM memory write out of range (ptr=$ptr len=${utf8.length}).');
    }
    memory.setRange(ptr, end, utf8);
    return _WasmTextRef(ptr: ptr, length: utf8.length);
  }

  int _writeStringInto(String text, int ptr, int capacity) {
    if (capacity <= 0) return 0;
    final utf8 = utf8Encode(text);
    final length = utf8.length < capacity ? utf8.length : capacity;

    final memory = _memory!.view;
    final end = ptr + length;
    if (ptr < 0 || end > memory.length) {
      return 0;
    }
    memory.setRange(ptr, end, utf8.take(length));
    return length;
  }

  String _readString(int ptr, int len) {
    if (len <= 0) return '';
    final memory = _memory!.view;
    final end = ptr + len;
    if (ptr < 0 || end > memory.length) return '';
    final bytes = memory.sublist(ptr, end);
    return utf8.decode(bytes, allowMalformed: true);
  }

  String _readResultString() {
    final resultPtr = _requireFunction(_config!.exports.getResultPtr).call(const []);
    final resultLen = _requireFunction(_config!.exports.getResultLen).call(const []);

    final ptr = resultPtr.isEmpty ? 0 : _intArg(resultPtr.first);
    final len = resultLen.isEmpty ? 0 : _intArg(resultLen.first);

    if (ptr <= 0 || len <= 0) return '';
    return _readString(ptr, len);
  }

  void _dealloc(_WasmTextRef text) {
    final deallocName = _config?.exports.dealloc;
    if (deallocName == null || deallocName.isEmpty) return;

    final instance = _instance;
    if (instance == null) return;

    final dealloc = instance.getFunction(deallocName);
    if (dealloc == null) return;

    dealloc.call([text.ptr, text.length]);
  }

  int _intArg(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is BigInt) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  List<int> utf8Encode(String input) => utf8.encode(input);

  void _assertLoaded() {
    if (_instance == null || _memory == null || _config == null) {
      throw StateError('WASM runtime is not initialized. Call run() first.');
    }
  }

  @override
  Future<void> dispose() async {
    _instance?.dispose();
    _instance = null;
    _module = null;
    _memory = null;
    _config = null;
  }

  static Future<Uint8List> _loadWasmBytes(_WasmVmConfig config) async {
    if (config.wasmBase64 != null && config.wasmBase64!.isNotEmpty) {
      return base64Decode(config.wasmBase64!);
    }

    final assetPath = config.wasmAssetPath;
    if (assetPath == null || assetPath.isEmpty) {
      throw StateError('WASM config must provide either `wasmBase64` or `wasmAssetPath`.');
    }

    final bytes = await rootBundle.load(assetPath);
    return bytes.buffer.asUint8List();
  }
}

class _WasmVmConfig {
  final String? wasmBase64;
  final String? wasmAssetPath;
  final _WasmVmExports exports;

  const _WasmVmConfig({
    required this.wasmBase64,
    required this.wasmAssetPath,
    required this.exports,
  });

  factory _WasmVmConfig.fromJson(String source) {
    final raw = jsonDecode(source);
    if (raw is! Map) {
      throw StateError('WASM runtime config must be a JSON object.');
    }
    final map = Map<String, dynamic>.from(raw);
    return _WasmVmConfig(
      wasmBase64: map['wasmBase64']?.toString(),
      wasmAssetPath: map['wasmAssetPath']?.toString(),
      exports: _WasmVmExports.fromMap(
        Map<String, dynamic>.from(map['exports'] as Map? ?? const {}),
      ),
    );
  }
}

class _WasmVmExports {
  final String memory;
  final String alloc;
  final String dealloc;
  final String run;
  final String callFunction;
  final String callFunctionWithInput;
  final String getResultPtr;
  final String getResultLen;

  const _WasmVmExports({
    required this.memory,
    required this.alloc,
    required this.dealloc,
    required this.run,
    required this.callFunction,
    required this.callFunctionWithInput,
    required this.getResultPtr,
    required this.getResultLen,
  });

  factory _WasmVmExports.fromMap(Map<String, dynamic> map) {
    return _WasmVmExports(
      memory: map['memory']?.toString() ?? 'memory',
      alloc: map['alloc']?.toString() ?? 'alloc',
      dealloc: map['dealloc']?.toString() ?? 'dealloc',
      run: map['run']?.toString() ?? 'run',
      callFunction: map['callFunction']?.toString() ?? 'call_function',
      callFunctionWithInput: map['callFunctionWithInput']?.toString() ?? 'call_function_with_input',
      getResultPtr: map['getResultPtr']?.toString() ?? 'get_result_ptr',
      getResultLen: map['getResultLen']?.toString() ?? 'get_result_len',
    );
  }
}

class _WasmTextRef {
  final int ptr;
  final int length;

  const _WasmTextRef({required this.ptr, required this.length});
}

extension _IterableFirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
