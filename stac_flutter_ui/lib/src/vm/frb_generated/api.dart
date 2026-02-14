/// Dart FFI bindings to the Elpian Rust VM native library.
///
/// On native platforms (Android, iOS, macOS, Linux, Windows), this uses
/// dart:ffi to call into the compiled Rust cdylib/staticlib.
library;

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

export 'vm_types.dart' show VmExecResult;
import 'vm_types.dart';

// ── Native function typedefs ────────────────────────────────────────

typedef _InitC = ffi.Void Function();
typedef _InitDart = void Function();

typedef _FreeStringC = ffi.Void Function(ffi.Pointer<Utf8>);
typedef _FreeStringDart = void Function(ffi.Pointer<Utf8>);

typedef _CreateVmC = ffi.Int32 Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
typedef _CreateVmDart = int Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);

typedef _ValidateC = ffi.Int32 Function(ffi.Pointer<Utf8>);
typedef _ValidateDart = int Function(ffi.Pointer<Utf8>);

typedef _ExecuteC = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);
typedef _ExecuteDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);

typedef _ExecuteFuncC = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Int64);
typedef _ExecuteFuncDart = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, int);

typedef _ExecuteFuncInputC = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Int64);
typedef _ExecuteFuncInputDart = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, int);

typedef _ContinueC = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
typedef _ContinueDart = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);

typedef _DestroyC = ffi.Int32 Function(ffi.Pointer<Utf8>);
typedef _DestroyDart = int Function(ffi.Pointer<Utf8>);

// ── Dynamic library loader ─────────────────────────────────────────

ffi.DynamicLibrary _loadLibrary() {
  if (Platform.isAndroid) {
    return ffi.DynamicLibrary.open('libelpian_vm.so');
  } else if (Platform.isIOS || Platform.isMacOS) {
    return ffi.DynamicLibrary.process();
  } else if (Platform.isLinux) {
    return ffi.DynamicLibrary.open('libelpian_vm.so');
  } else if (Platform.isWindows) {
    return ffi.DynamicLibrary.open('elpian_vm.dll');
  }
  throw UnsupportedError('Unsupported platform for native FFI');
}

// ── API class ───────────────────────────────────────────────────────

/// Native FFI bindings to the Elpian Rust VM.
class ElpianVmApi {
  static ElpianVmApi? _instance;
  late final ffi.DynamicLibrary _lib;

  late final _InitDart _init;
  late final _FreeStringDart _freeString;
  late final _CreateVmDart _createVmFromAst;
  late final _CreateVmDart _createVmFromCode;
  late final _ValidateDart _validateAst;
  late final _ExecuteDart _execute;
  late final _ExecuteFuncDart _executeFunc;
  late final _ExecuteFuncInputDart _executeFuncWithInput;
  late final _ContinueDart _continueExecution;
  late final _DestroyDart _destroyVm;
  late final _DestroyDart _vmExists;

  ElpianVmApi._() {
    _lib = _loadLibrary();
    _init = _lib.lookupFunction<_InitC, _InitDart>('elpian_init');
    _freeString = _lib
        .lookupFunction<_FreeStringC, _FreeStringDart>('elpian_free_string');
    _createVmFromAst =
        _lib.lookupFunction<_CreateVmC, _CreateVmDart>('elpian_create_vm_from_ast');
    _createVmFromCode =
        _lib.lookupFunction<_CreateVmC, _CreateVmDart>('elpian_create_vm_from_code');
    _validateAst =
        _lib.lookupFunction<_ValidateC, _ValidateDart>('elpian_validate_ast');
    _execute =
        _lib.lookupFunction<_ExecuteC, _ExecuteDart>('elpian_execute');
    _executeFunc =
        _lib.lookupFunction<_ExecuteFuncC, _ExecuteFuncDart>('elpian_execute_func');
    _executeFuncWithInput = _lib.lookupFunction<_ExecuteFuncInputC,
        _ExecuteFuncInputDart>('elpian_execute_func_with_input');
    _continueExecution =
        _lib.lookupFunction<_ContinueC, _ContinueDart>('elpian_continue_execution');
    _destroyVm =
        _lib.lookupFunction<_DestroyC, _DestroyDart>('elpian_destroy_vm');
    _vmExists =
        _lib.lookupFunction<_DestroyC, _DestroyDart>('elpian_vm_exists');
  }

  factory ElpianVmApi() {
    _instance ??= ElpianVmApi._();
    return _instance!;
  }

  VmExecResult _callAndParse(ffi.Pointer<Utf8> ptr) {
    final jsonStr = ptr.toDartString();
    _freeString(ptr);
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;
    return VmExecResult.fromJson(json);
  }

  static Future<void> initVmSystem() async {
    ElpianVmApi()._init();
  }

  static Future<bool> createVmFromAst({
    required String machineId,
    required String astJson,
  }) async {
    final api = ElpianVmApi();
    final midPtr = machineId.toNativeUtf8();
    final astPtr = astJson.toNativeUtf8();
    try {
      return api._createVmFromAst(midPtr, astPtr) == 1;
    } finally {
      malloc.free(midPtr);
      malloc.free(astPtr);
    }
  }

  static Future<bool> createVmFromCode({
    required String machineId,
    required String code,
  }) async {
    final api = ElpianVmApi();
    final midPtr = machineId.toNativeUtf8();
    final codePtr = code.toNativeUtf8();
    try {
      return api._createVmFromCode(midPtr, codePtr) == 1;
    } finally {
      malloc.free(midPtr);
      malloc.free(codePtr);
    }
  }

  static Future<bool> validateAst({required String astJson}) async {
    final api = ElpianVmApi();
    final astPtr = astJson.toNativeUtf8();
    try {
      return api._validateAst(astPtr) == 1;
    } finally {
      malloc.free(astPtr);
    }
  }

  static Future<VmExecResult> executeVm({
    required String machineId,
  }) async {
    final api = ElpianVmApi();
    final midPtr = machineId.toNativeUtf8();
    try {
      return api._callAndParse(api._execute(midPtr));
    } finally {
      malloc.free(midPtr);
    }
  }

  static Future<VmExecResult> executeVmFunc({
    required String machineId,
    required String funcName,
    required int cbId,
  }) async {
    final api = ElpianVmApi();
    final midPtr = machineId.toNativeUtf8();
    final fnPtr = funcName.toNativeUtf8();
    try {
      return api._callAndParse(api._executeFunc(midPtr, fnPtr, cbId));
    } finally {
      malloc.free(midPtr);
      malloc.free(fnPtr);
    }
  }

  static Future<VmExecResult> executeVmFuncWithInput({
    required String machineId,
    required String funcName,
    required String inputJson,
    required int cbId,
  }) async {
    final api = ElpianVmApi();
    final midPtr = machineId.toNativeUtf8();
    final fnPtr = funcName.toNativeUtf8();
    final inputPtr = inputJson.toNativeUtf8();
    try {
      return api._callAndParse(
          api._executeFuncWithInput(midPtr, fnPtr, inputPtr, cbId));
    } finally {
      malloc.free(midPtr);
      malloc.free(fnPtr);
      malloc.free(inputPtr);
    }
  }

  static Future<VmExecResult> continueExecution({
    required String machineId,
    required String inputJson,
  }) async {
    final api = ElpianVmApi();
    final midPtr = machineId.toNativeUtf8();
    final inputPtr = inputJson.toNativeUtf8();
    try {
      return api._callAndParse(api._continueExecution(midPtr, inputPtr));
    } finally {
      malloc.free(midPtr);
      malloc.free(inputPtr);
    }
  }

  static Future<bool> destroyVm({required String machineId}) async {
    final api = ElpianVmApi();
    final midPtr = machineId.toNativeUtf8();
    try {
      return api._destroyVm(midPtr) == 1;
    } finally {
      malloc.free(midPtr);
    }
  }

  static Future<bool> vmExists({required String machineId}) async {
    final api = ElpianVmApi();
    final midPtr = machineId.toNativeUtf8();
    try {
      return api._vmExists(midPtr) == 1;
    } finally {
      malloc.free(midPtr);
    }
  }
}
