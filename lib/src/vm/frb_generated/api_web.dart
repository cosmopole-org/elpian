/// Web (WASM) bindings to the Elpian Rust VM.
///
/// Uses dart:js_interop to call into the wasm-bindgen compiled WASM module.
/// The WASM module must be loaded before using this API.
///
/// Build the WASM module with:
/// ```bash
/// cd rust && wasm-pack build --target web
/// ```
library;

import 'dart:js_interop';

export 'vm_types.dart' show VmExecResult;
import 'vm_types.dart';

// ── JS interop bindings ──────────────────────────────────────────────

@JS('elpian_wasm_init')
external void _wasmInit();

@JS('elpian_wasm_create_vm_from_ast')
external JSBoolean _wasmCreateVmFromAst(JSString machineId, JSString astJson);

@JS('elpian_wasm_create_vm_from_code')
external JSBoolean _wasmCreateVmFromCode(JSString machineId, JSString code);

@JS('elpian_wasm_validate_ast')
external JSBoolean _wasmValidateAst(JSString astJson);

@JS('elpian_wasm_execute')
external JSString _wasmExecute(JSString machineId);

@JS('elpian_wasm_execute_func')
external JSString _wasmExecuteFunc(
    JSString machineId, JSString funcName, JSNumber cbId);

@JS('elpian_wasm_execute_func_with_input')
external JSString _wasmExecuteFuncWithInput(
    JSString machineId, JSString funcName, JSString inputJson, JSNumber cbId);

@JS('elpian_wasm_continue_execution')
external JSString _wasmContinueExecution(
    JSString machineId, JSString inputJson);

@JS('elpian_wasm_destroy_vm')
external JSBoolean _wasmDestroyVm(JSString machineId);

@JS('elpian_wasm_vm_exists')
external JSBoolean _wasmVmExists(JSString machineId);

// ── Error result helper ─────────────────────────────────────────────

VmExecResult _errorResult(String message) => VmExecResult(
      hasHostCall: false,
      hostCallData: '',
      resultValue: '"$message"',
    );

// ── API class for web (same name as native for conditional export) ───

/// Web (WASM) implementation of the Elpian VM API.
/// Same class name as native [ElpianVmApi] so conditional exports work.
class ElpianVmApi {
  static String? _lastError;
  static bool _wasmAvailable = false;

  static String? get lastError => _lastError;

  static void clearLastError() {
    _lastError = null;
  }

  static const _wasmMissing = 'Elpian WASM module is not loaded. Ensure '
      'assets/packages/elpian_ui/assets/web_runtime/elpian_wasm_loader.js is included in '
      'web/index.html, then build wasm with: cd rust && wasm-pack build --target web';

  static Future<void> initVmSystem() async {
    try {
      _wasmInit();
      _wasmAvailable = true;
    } catch (e) {
      _wasmAvailable = false;
      _lastError = '$_wasmMissing ($e)';
    }
  }

  static Future<bool> createVmFromAst({
    required String machineId,
    required String astJson,
  }) async {
    clearLastError();
    if (!_wasmAvailable) {
      _lastError = _wasmMissing;
      return false;
    }
    try {
      final ok = _wasmCreateVmFromAst(machineId.toJS, astJson.toJS).toDart;
      if (!ok) {
        _lastError = "WASM createVmFromAst returned false";
      }
      return ok;
    } catch (e) {
      _lastError = 'WASM createVmFromAst failed: $e';
      return false;
    }
  }

  static Future<bool> createVmFromCode({
    required String machineId,
    required String code,
  }) async {
    clearLastError();
    if (!_wasmAvailable) {
      _lastError = _wasmMissing;
      return false;
    }
    try {
      final ok = _wasmCreateVmFromCode(machineId.toJS, code.toJS).toDart;
      if (!ok) {
        _lastError = "WASM createVmFromCode returned false";
      }
      return ok;
    } catch (e) {
      _lastError = 'WASM createVmFromCode failed: $e';
      return false;
    }
  }

  static Future<bool> validateAst({required String astJson}) async {
    clearLastError();
    if (!_wasmAvailable) {
      _lastError = _wasmMissing;
      return false;
    }
    try {
      final ok = _wasmValidateAst(astJson.toJS).toDart;
      if (!ok) {
        _lastError = "WASM validateAst returned false";
      }
      return ok;
    } catch (e) {
      _lastError = 'WASM validateAst failed: $e';
      return false;
    }
  }

  static Future<VmExecResult> executeVm({
    required String machineId,
  }) async {
    if (!_wasmAvailable) {
      _lastError = _wasmMissing;
      return _errorResult('wasm_not_available');
    }
    try {
      final result = _wasmExecute(machineId.toJS).toDart;
      return VmExecResult.fromJsonString(result);
    } catch (e) {
      _lastError = 'WASM executeVm failed: $e';
      return _errorResult('wasm_error');
    }
  }

  static Future<VmExecResult> executeVmFunc({
    required String machineId,
    required String funcName,
    required int cbId,
  }) async {
    if (!_wasmAvailable) {
      _lastError = _wasmMissing;
      return _errorResult('wasm_not_available');
    }
    try {
      final result =
          _wasmExecuteFunc(machineId.toJS, funcName.toJS, cbId.toJS).toDart;
      return VmExecResult.fromJsonString(result);
    } catch (e) {
      _lastError = 'WASM executeVmFunc failed: $e';
      return _errorResult('wasm_error');
    }
  }

  static Future<VmExecResult> executeVmFuncWithInput({
    required String machineId,
    required String funcName,
    required String inputJson,
    required int cbId,
  }) async {
    if (!_wasmAvailable) {
      _lastError = _wasmMissing;
      return _errorResult('wasm_not_available');
    }
    try {
      final result = _wasmExecuteFuncWithInput(
              machineId.toJS, funcName.toJS, inputJson.toJS, cbId.toJS)
          .toDart;
      return VmExecResult.fromJsonString(result);
    } catch (e) {
      _lastError = 'WASM executeVmFuncWithInput failed: $e';
      return _errorResult('wasm_error');
    }
  }

  static Future<VmExecResult> continueExecution({
    required String machineId,
    required String inputJson,
  }) async {
    if (!_wasmAvailable) {
      _lastError = _wasmMissing;
      return _errorResult('wasm_not_available');
    }
    try {
      final result =
          _wasmContinueExecution(machineId.toJS, inputJson.toJS).toDart;
      return VmExecResult.fromJsonString(result);
    } catch (e) {
      _lastError = 'WASM continueExecution failed: $e';
      return _errorResult('wasm_error');
    }
  }

  static Future<bool> destroyVm({required String machineId}) async {
    if (!_wasmAvailable) return false;
    try {
      return _wasmDestroyVm(machineId.toJS).toDart;
    } catch (e) {
      _lastError = 'WASM destroyVm failed: $e';
      return false;
    }
  }

  static Future<bool> vmExists({required String machineId}) async {
    if (!_wasmAvailable) return false;
    try {
      return _wasmVmExists(machineId.toJS).toDart;
    } catch (e) {
      _lastError = 'WASM vmExists failed: $e';
      return false;
    }
  }
}
