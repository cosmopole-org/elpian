/// Web (WASM) bindings to the Elpian Rust VM.
///
/// Uses dart:js_interop to call into the wasm-bindgen compiled WASM module.
/// The WASM module must be loaded before using this API.
///
/// Build the WASM module with:
/// ```bash
/// cd rust && wasm-pack build --target web
/// ```

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
external JSString _wasmContinueExecution(JSString machineId, JSString inputJson);

@JS('elpian_wasm_destroy_vm')
external JSBoolean _wasmDestroyVm(JSString machineId);

@JS('elpian_wasm_vm_exists')
external JSBoolean _wasmVmExists(JSString machineId);

// ── API class for web (same name as native for conditional export) ───

/// Web (WASM) implementation of the Elpian VM API.
/// Same class name as native [ElpianVmApi] so conditional exports work.
class ElpianVmApi {
  static Future<void> initVmSystem() async {
    _wasmInit();
  }

  static Future<bool> createVmFromAst({
    required String machineId,
    required String astJson,
  }) async {
    return _wasmCreateVmFromAst(machineId.toJS, astJson.toJS).toDart;
  }

  static Future<bool> createVmFromCode({
    required String machineId,
    required String code,
  }) async {
    return _wasmCreateVmFromCode(machineId.toJS, code.toJS).toDart;
  }

  static Future<bool> validateAst({required String astJson}) async {
    return _wasmValidateAst(astJson.toJS).toDart;
  }

  static Future<VmExecResult> executeVm({
    required String machineId,
  }) async {
    final result = _wasmExecute(machineId.toJS).toDart;
    return VmExecResult.fromJsonString(result);
  }

  static Future<VmExecResult> executeVmFunc({
    required String machineId,
    required String funcName,
    required int cbId,
  }) async {
    final result =
        _wasmExecuteFunc(machineId.toJS, funcName.toJS, cbId.toJS).toDart;
    return VmExecResult.fromJsonString(result);
  }

  static Future<VmExecResult> executeVmFuncWithInput({
    required String machineId,
    required String funcName,
    required String inputJson,
    required int cbId,
  }) async {
    final result = _wasmExecuteFuncWithInput(
            machineId.toJS, funcName.toJS, inputJson.toJS, cbId.toJS)
        .toDart;
    return VmExecResult.fromJsonString(result);
  }

  static Future<VmExecResult> continueExecution({
    required String machineId,
    required String inputJson,
  }) async {
    final result =
        _wasmContinueExecution(machineId.toJS, inputJson.toJS).toDart;
    return VmExecResult.fromJsonString(result);
  }

  static Future<bool> destroyVm({required String machineId}) async {
    return _wasmDestroyVm(machineId.toJS).toDart;
  }

  static Future<bool> vmExists({required String machineId}) async {
    return _wasmVmExists(machineId.toJS).toDart;
  }
}
