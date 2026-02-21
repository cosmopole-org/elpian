import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Parses host call payloads from the Rust VM and converts them
/// to ElpianNode-compatible JSON for the Flutter renderer.
///
/// The VM's `render` host function receives a JSON representation
/// of the view tree. This handler converts it into the format
/// expected by ElpianEngine.renderFromJson().
class HostHandler {
  /// Callback invoked when the VM calls `render(viewJson)`.
  /// The parameter is a ElpianNode-compatible JSON map.
  final void Function(Map<String, dynamic> viewJson)? onRender;

  /// Callback invoked when the VM calls `updateApp(updateData)`.
  /// The parameter is a JSON map with the update payload.
  final void Function(Map<String, dynamic> updateData)? onUpdateApp;

  /// Callback invoked when the VM calls `println(message)`.
  final void Function(String message)? onPrintln;

  HostHandler({
    this.onRender,
    this.onUpdateApp,
    this.onPrintln,
  });

  /// Handle a `render` host call from the VM.
  ///
  /// The payload from the VM is a stringified JSON object representing
  /// the view tree. This method parses it and converts it to the
  /// ElpianNode JSON format that ElpianEngine can render.
  ///
  /// Expected VM payload format (from askHost("render", viewData)):
  /// The VM serializes the render argument as a Val.stringify() result.
  /// This will be a JSON object/array/string depending on what the
  /// VM code passes to the render function.
  Future<String> handleRender(String payload) async {
    try {
      final dynamic parsed = _unwrapHostArgs(_parseVmPayload(payload));

      if (parsed is Map<String, dynamic>) {
        onRender?.call(parsed);
      } else if (parsed is String) {
        // If it's a string, try to parse it as JSON
        try {
          final jsonParsed = jsonDecode(parsed);
          if (jsonParsed is Map<String, dynamic>) {
            onRender?.call(jsonParsed);
          }
        } catch (_) {
          // Not valid JSON, treat as raw text render
          onRender?.call({
            'type': 'Text',
            'props': {'text': parsed},
          });
        }
      }

      return _makeResponse('i16', 0);
    } catch (e) {
      debugPrint('HostHandler: render error: $e');
      return _makeResponse('i16', 0);
    }
  }

  /// Handle an `updateApp` host call from the VM.
  Future<String> handleUpdateApp(String payload) async {
    try {
      final dynamic parsed = _unwrapHostArgs(_parseVmPayload(payload));

      if (parsed is Map<String, dynamic>) {
        onUpdateApp?.call(parsed);
      }

      return _makeResponse('i16', 0);
    } catch (e) {
      debugPrint('HostHandler: updateApp error: $e');
      return _makeResponse('i16', 0);
    }
  }

  /// Handle a `println` host call from the VM.
  Future<String> handlePrintln(String payload) async {
    final dynamic parsed = _unwrapHostArgs(_parseVmPayload(payload));
    final message = parsed is String ? parsed : payload;
    onPrintln?.call(message);
    return _makeResponse('i16', 0);
  }

  /// Handle a `stringify` host call from the VM.
  Future<String> handleStringify(String payload) async {
    return _makeResponse('string', payload);
  }

  /// Parse a VM payload string.
  /// The VM sends values through Val.stringify() which produces
  /// JSON-like strings. This method handles the various formats.
  dynamic _parseVmPayload(String payload) {
    if (payload.isEmpty) return null;

    // Try to parse as JSON first
    try {
      return jsonDecode(payload);
    } catch (_) {
      // If it's wrapped in quotes, it's a string value
      if (payload.startsWith('"') && payload.endsWith('"')) {
        return payload.substring(1, payload.length - 1);
      }
      return payload;
    }
  }

  /// Host calls encode arguments as an array payload.
  /// For common single-argument APIs (render/updateApp/println), unwrap
  /// the first argument so downstream handling receives the value itself.
  dynamic _unwrapHostArgs(dynamic parsed) {
    if (parsed is List<dynamic>) {
      if (parsed.isEmpty) return null;
      return parsed.first;
    }
    return parsed;
  }

  /// Create a typed response JSON for the VM.
  String _makeResponse(String type, dynamic value) {
    return jsonEncode({
      'type': type,
      'data': {'value': value},
    });
  }
}
