/// Shared types for the VM FFI layer (used by both native and web).
library;

import 'dart:convert';

/// Result of a VM execution step returned from Rust.
class VmExecResult {
  /// Whether the VM is paused waiting for a host call response.
  final bool hasHostCall;

  /// JSON string of the host call request.
  final String hostCallData;

  /// Stringified result value (only meaningful when hasHostCall is false).
  final String resultValue;

  const VmExecResult({
    required this.hasHostCall,
    required this.hostCallData,
    required this.resultValue,
  });

  factory VmExecResult.fromJson(Map<String, dynamic> json) {
    return VmExecResult(
      hasHostCall: json['hasHostCall'] as bool? ?? false,
      hostCallData: json['hostCallData'] as String? ?? '',
      resultValue: json['resultValue'] as String? ?? '',
    );
  }

  factory VmExecResult.fromJsonString(String jsonStr) {
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;
    return VmExecResult.fromJson(json);
  }
}
