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

// ── Error result helper ─────────────────────────────────────────────

VmExecResult _errorResult(String message) => VmExecResult(
      hasHostCall: false,
      hostCallData: '',
      resultValue: '"$message"',
    );

// ── API class ───────────────────────────────────────────────────────

/// Native FFI bindings to the Elpian Rust VM.
class ElpianVmApi {
  static ElpianVmApi? _instance;
  static String? _lastError;
  static bool _nativeAvailable = false;

  static String? get lastError => _lastError;

  static void _setLastError(String error) {
    _lastError = error;
  }

  static void clearLastError() {
    _lastError = null;
  }

  late final ffi.DynamicLibrary _lib;

  _InitDart? _init;
  _FreeStringDart? _freeString;
  _CreateVmDart? _createVmFromAst;
  _CreateVmDart? _createVmFromCode;
  _ValidateDart? _validateAst;
  _ExecuteDart? _execute;
  _ExecuteFuncDart? _executeFunc;
  _ExecuteFuncInputDart? _executeFuncWithInput;
  _ContinueDart? _continueExecution;
  _DestroyDart? _destroyVm;
  _DestroyDart? _vmExists;

  ElpianVmApi._() {
    _lib = _loadLibrary();
    _init = _lib.lookupFunction<_InitC, _InitDart>('elpian_init');
    _freeString = _lib
        .lookupFunction<_FreeStringC, _FreeStringDart>('elpian_free_string');
    try {
      _createVmFromAst = _lib.lookupFunction<_CreateVmC, _CreateVmDart>(
        'elpian_create_vm_from_ast',
      );
    } catch (e) {
      _createVmFromAst = null;
      _setLastError(
        "FFI symbol lookup failed for elpian_create_vm_from_ast: $e",
      );
    }
    try {
      _createVmFromCode =
          _lib.lookupFunction<_CreateVmC, _CreateVmDart>('elpian_create_vm_from_code');
    } catch (e) {
      _createVmFromCode = null;
      _setLastError(
        "FFI symbol lookup failed for elpian_create_vm_from_code: $e",
      );
    }
    try {
      _validateAst = _lib.lookupFunction<_ValidateC, _ValidateDart>(
        'elpian_validate_ast',
      );
    } catch (e) {
      _validateAst = null;
      _setLastError(
        "FFI symbol lookup failed for elpian_validate_ast: $e",
      );
    }
    try {
      _execute =
          _lib.lookupFunction<_ExecuteC, _ExecuteDart>('elpian_execute');
    } catch (e) {
      _execute = null;
      _setLastError("FFI symbol lookup failed for elpian_execute: $e");
    }
    try {
      _executeFunc =
          _lib.lookupFunction<_ExecuteFuncC, _ExecuteFuncDart>('elpian_execute_func');
    } catch (e) {
      _executeFunc = null;
      _setLastError("FFI symbol lookup failed for elpian_execute_func: $e");
    }
    try {
      _executeFuncWithInput = _lib.lookupFunction<_ExecuteFuncInputC,
          _ExecuteFuncInputDart>('elpian_execute_func_with_input');
    } catch (e) {
      _executeFuncWithInput = null;
      _setLastError(
        "FFI symbol lookup failed for elpian_execute_func_with_input: $e",
      );
    }
    try {
      _continueExecution =
          _lib.lookupFunction<_ContinueC, _ContinueDart>('elpian_continue_execution');
    } catch (e) {
      _continueExecution = null;
      _setLastError(
        "FFI symbol lookup failed for elpian_continue_execution: $e",
      );
    }
    try {
      _destroyVm =
          _lib.lookupFunction<_DestroyC, _DestroyDart>('elpian_destroy_vm');
    } catch (e) {
      _destroyVm = null;
      _setLastError("FFI symbol lookup failed for elpian_destroy_vm: $e");
    }
    try {
      _vmExists =
          _lib.lookupFunction<_DestroyC, _DestroyDart>('elpian_vm_exists');
    } catch (e) {
      _vmExists = null;
      _setLastError("FFI symbol lookup failed for elpian_vm_exists: $e");
    }
  }

  /// Try to get the singleton API instance. Returns null if the native
  /// library could not be loaded (sets [lastError] with the reason).
  static ElpianVmApi? _tryGetApi() {
    if (_instance != null) return _instance;
    try {
      _instance = ElpianVmApi._();
      _nativeAvailable = true;
      return _instance;
    } catch (e) {
      _nativeAvailable = false;
      _setLastError('Failed to load native VM library: $e');
      return null;
    }
  }

  VmExecResult _callAndParse(ffi.Pointer<Utf8> ptr) {
    final jsonStr = ptr.toDartString();
    _freeString?.call(ptr);
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;
    return VmExecResult.fromJson(json);
  }

  static Future<void> initVmSystem() async {
    final api = _tryGetApi();
    api?._init?.call();
  }

  static Future<bool> createVmFromAst({
    required String machineId,
    required String astJson,
  }) async {
    final api = _tryGetApi();
    if (api == null) return false;
    final fn = api._createVmFromAst;
    if (fn == null) {
      _setLastError(
        "createVmFromAst unavailable: missing native symbol elpian_create_vm_from_ast",
      );
      return false;
    }
    final midPtr = machineId.toNativeUtf8();
    final astPtr = astJson.toNativeUtf8();
    try {
      clearLastError();
      final ok = fn(midPtr, astPtr) == 1;
      if (!ok) {
        _setLastError("Native createVmFromAst returned false");
      }
      return ok;
    } finally {
      malloc.free(midPtr);
      malloc.free(astPtr);
    }
  }

  static Future<bool> createVmFromCode({
    required String machineId,
    required String code,
  }) async {
    final api = _tryGetApi();
    if (api == null) return false;
    final fn = api._createVmFromCode;
    if (fn == null) {
      _setLastError(
        "createVmFromCode unavailable: missing native symbol elpian_create_vm_from_code",
      );
      return false;
    }
    final midPtr = machineId.toNativeUtf8();
    final codePtr = code.toNativeUtf8();
    try {
      clearLastError();
      final ok = fn(midPtr, codePtr) == 1;
      if (!ok) {
        _setLastError("Native createVmFromCode returned false");
      }
      return ok;
    } finally {
      malloc.free(midPtr);
      malloc.free(codePtr);
    }
  }

  static Future<bool> validateAst({required String astJson}) async {
    final api = _tryGetApi();
    if (api == null) return false;
    final fn = api._validateAst;
    if (fn == null) {
      _setLastError(
        "validateAst unavailable: missing native symbol elpian_validate_ast",
      );
      return false;
    }
    final astPtr = astJson.toNativeUtf8();
    try {
      clearLastError();
      final ok = fn(astPtr) == 1;
      if (!ok) {
        _setLastError("Native validateAst returned false");
      }
      return ok;
    } finally {
      malloc.free(astPtr);
    }
  }

  static Future<VmExecResult> executeVm({
    required String machineId,
  }) async {
    final api = _tryGetApi();
    if (api == null) return _errorResult('native_lib_not_loaded');
    final fn = api._execute;
    if (fn == null) {
      _setLastError("executeVm unavailable: missing native symbol elpian_execute");
      return _errorResult('symbol_not_found');
    }
    final midPtr = machineId.toNativeUtf8();
    try {
      return api._callAndParse(fn(midPtr));
    } finally {
      malloc.free(midPtr);
    }
  }

  static Future<VmExecResult> executeVmFunc({
    required String machineId,
    required String funcName,
    required int cbId,
  }) async {
    final api = _tryGetApi();
    if (api == null) return _errorResult('native_lib_not_loaded');
    final fn = api._executeFunc;
    if (fn == null) {
      _setLastError("executeVmFunc unavailable: missing native symbol elpian_execute_func");
      return _errorResult('symbol_not_found');
    }
    final midPtr = machineId.toNativeUtf8();
    final fnPtr = funcName.toNativeUtf8();
    try {
      return api._callAndParse(fn(midPtr, fnPtr, cbId));
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
    final api = _tryGetApi();
    if (api == null) return _errorResult('native_lib_not_loaded');
    final fn = api._executeFuncWithInput;
    if (fn == null) {
      _setLastError(
        "executeVmFuncWithInput unavailable: missing native symbol elpian_execute_func_with_input",
      );
      return _errorResult('symbol_not_found');
    }
    final midPtr = machineId.toNativeUtf8();
    final fnPtr = funcName.toNativeUtf8();
    final inputPtr = inputJson.toNativeUtf8();
    try {
      return api._callAndParse(fn(midPtr, fnPtr, inputPtr, cbId));
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
    final api = _tryGetApi();
    if (api == null) return _errorResult('native_lib_not_loaded');
    final fn = api._continueExecution;
    if (fn == null) {
      _setLastError(
        "continueExecution unavailable: missing native symbol elpian_continue_execution",
      );
      return _errorResult('symbol_not_found');
    }
    final midPtr = machineId.toNativeUtf8();
    final inputPtr = inputJson.toNativeUtf8();
    try {
      return api._callAndParse(fn(midPtr, inputPtr));
    } finally {
      malloc.free(midPtr);
      malloc.free(inputPtr);
    }
  }

  static Future<bool> destroyVm({required String machineId}) async {
    final api = _tryGetApi();
    if (api == null) return false;
    final fn = api._destroyVm;
    if (fn == null) return false;
    final midPtr = machineId.toNativeUtf8();
    try {
      return fn(midPtr) == 1;
    } finally {
      malloc.free(midPtr);
    }
  }

  static Future<bool> vmExists({required String machineId}) async {
    final api = _tryGetApi();
    if (api == null) return false;
    final fn = api._vmExists;
    if (fn == null) return false;
    final midPtr = machineId.toNativeUtf8();
    try {
      return fn(midPtr) == 1;
    } finally {
      malloc.free(midPtr);
    }
  }
}
