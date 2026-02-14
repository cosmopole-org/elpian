/// Auto-generated stub for flutter_rust_bridge bindings.
///
/// This file provides the Dart interface to the Rust VM API.
/// Run `flutter_rust_bridge_codegen generate` to regenerate from Rust source.
///
/// After running codegen, this file will be replaced with the actual
/// generated bindings that handle FFI/WASM communication automatically.
library;

/// Result of a VM execution step returned from Rust.
class VmExecResult {
  /// Whether the VM is paused waiting for a host call response.
  final bool hasHostCall;

  /// JSON string of the host call request: {"machineId", "apiName", "payload"}.
  final String hostCallData;

  /// Stringified result value (only meaningful when hasHostCall is false).
  final String resultValue;

  const VmExecResult({
    required this.hasHostCall,
    required this.hostCallData,
    required this.resultValue,
  });
}

/// Stub class for the FRB-generated Rust API bindings.
///
/// After running `flutter_rust_bridge_codegen generate`, this class will be
/// replaced by the actual generated code that communicates with Rust via FFI
/// on mobile/desktop or WASM on web.
///
/// To run codegen:
/// ```bash
/// cd stac_flutter_ui
/// flutter_rust_bridge_codegen generate
/// ```
class ElpianVmApi {
  /// Initialize the VM subsystem. Call once at app startup.
  static Future<void> initVmSystem() async {
    throw UnimplementedError(
      'Run flutter_rust_bridge_codegen generate to create bindings. '
      'See stac_flutter_ui/flutter_rust_bridge.yaml for configuration.',
    );
  }

  /// Create a VM from AST JSON string.
  static Future<bool> createVmFromAst({
    required String machineId,
    required String astJson,
  }) async {
    throw UnimplementedError('Run flutter_rust_bridge_codegen generate');
  }

  /// Create a VM from source code string.
  static Future<bool> createVmFromCode({
    required String machineId,
    required String code,
  }) async {
    throw UnimplementedError('Run flutter_rust_bridge_codegen generate');
  }

  /// Validate AST JSON without creating a VM.
  static Future<bool> validateAst({required String astJson}) async {
    throw UnimplementedError('Run flutter_rust_bridge_codegen generate');
  }

  /// Execute the main program of a VM.
  static Future<VmExecResult> executeVm({
    required String machineId,
  }) async {
    throw UnimplementedError('Run flutter_rust_bridge_codegen generate');
  }

  /// Execute a named function in the VM.
  static Future<VmExecResult> executeVmFunc({
    required String machineId,
    required String funcName,
    required int cbId,
  }) async {
    throw UnimplementedError('Run flutter_rust_bridge_codegen generate');
  }

  /// Execute a named function with JSON input in the VM.
  static Future<VmExecResult> executeVmFuncWithInput({
    required String machineId,
    required String funcName,
    required String inputJson,
    required int cbId,
  }) async {
    throw UnimplementedError('Run flutter_rust_bridge_codegen generate');
  }

  /// Continue VM execution after a host call response.
  static Future<VmExecResult> continueExecution({
    required String machineId,
    required String inputJson,
  }) async {
    throw UnimplementedError('Run flutter_rust_bridge_codegen generate');
  }

  /// Destroy a VM instance.
  static Future<bool> destroyVm({required String machineId}) async {
    throw UnimplementedError('Run flutter_rust_bridge_codegen generate');
  }

  /// Check if a VM exists.
  static Future<bool> vmExists({required String machineId}) async {
    throw UnimplementedError('Run flutter_rust_bridge_codegen generate');
  }
}
