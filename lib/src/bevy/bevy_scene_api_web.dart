/// Web FFI bindings to the Elpian Bevy 3D scene renderer.
///
/// On web platforms, this uses dart:js_interop to call into the WASM-compiled
/// Rust library via wasm-bindgen. Pixel data is transferred as Uint8List.
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

// ── Frame data result ───────────────────────────────────────────────

/// Holds the rendered frame data from the Bevy scene renderer.
class BevyFrameData {
  final int width;
  final int height;
  final Uint8List pixels;
  final int frameCount;

  const BevyFrameData({
    required this.width,
    required this.height,
    required this.pixels,
    required this.frameCount,
  });

  int get byteLength => pixels.length;
  bool get isEmpty => pixels.isEmpty;
}

// ── JS interop bindings ─────────────────────────────────────────────

@JS('elpian_bevy_wasm_init')
external void _wasmInit();

@JS('elpian_bevy_wasm_create_scene')
external JSBoolean _wasmCreateScene(
    JSString sceneId, JSString json, JSNumber width, JSNumber height);

@JS('elpian_bevy_wasm_update_scene')
external JSBoolean _wasmUpdateScene(JSString sceneId, JSString json);

@JS('elpian_bevy_wasm_render_frame')
external JSBoolean _wasmRenderFrame(JSString sceneId, JSNumber deltaTime);

@JS('elpian_bevy_wasm_resize_scene')
external JSBoolean _wasmResizeScene(
    JSString sceneId, JSNumber width, JSNumber height);

@JS('elpian_bevy_wasm_get_frame')
external JSString _wasmGetFrame(JSString sceneId);

@JS('elpian_bevy_wasm_get_frame_bytes')
external JSUint8Array _wasmGetFrameBytes(JSString sceneId);

@JS('elpian_bevy_wasm_send_input')
external JSBoolean _wasmSendInput(JSString sceneId, JSString inputJson);

@JS('elpian_bevy_wasm_destroy_scene')
external JSBoolean _wasmDestroyScene(JSString sceneId);

@JS('elpian_bevy_wasm_scene_exists')
external JSBoolean _wasmSceneExists(JSString sceneId);

@JS('elpian_bevy_wasm_get_elapsed_time')
external JSNumber _wasmGetElapsedTime(JSString sceneId);


// ── API class ───────────────────────────────────────────────────────

/// Web FFI bindings to the Elpian Bevy 3D scene renderer.
class BevySceneApi {
  static bool _wasmAvailable = false;

  static void initSceneSystem() {
    try {
      _wasmInit();
      _wasmAvailable = true;
    } catch (_) {
      _wasmAvailable = false;
    }
  }

  static bool createScene({
    required String sceneId,
    required String json,
    required int width,
    required int height,
  }) {
    if (!_wasmAvailable) return false;
    try {
      return _wasmCreateScene(
              sceneId.toJS, json.toJS, width.toJS, height.toJS)
          .toDart;
    } catch (_) {
      return false;
    }
  }

  static bool updateScene({
    required String sceneId,
    required String json,
  }) {
    if (!_wasmAvailable) return false;
    try {
      return _wasmUpdateScene(sceneId.toJS, json.toJS).toDart;
    } catch (_) {
      return false;
    }
  }

  static bool renderFrame({
    required String sceneId,
    required double deltaTime,
  }) {
    if (!_wasmAvailable) return false;
    try {
      return _wasmRenderFrame(sceneId.toJS, deltaTime.toJS).toDart;
    } catch (_) {
      return false;
    }
  }

  static bool resizeScene({
    required String sceneId,
    required int width,
    required int height,
  }) {
    if (!_wasmAvailable) return false;
    try {
      return _wasmResizeScene(sceneId.toJS, width.toJS, height.toJS).toDart;
    } catch (_) {
      return false;
    }
  }

  /// Get the rendered frame as raw RGBA pixel data.
  static BevyFrameData? getFrameDirect({required String sceneId}) {
    if (!_wasmAvailable) return null;
    try {
      final frameJson = _wasmGetFrame(sceneId.toJS).toDart;
      final json = jsonDecode(frameJson) as Map<String, dynamic>;
      if (!json.containsKey('width')) return null;

      final width = json['width'] as int;
      final height = json['height'] as int;
      final frameCount = json['frameCount'] as int;

      // Get raw pixel bytes from WASM
      final jsBytes = _wasmGetFrameBytes(sceneId.toJS);
      final pixels = jsBytes.toDart;

      return BevyFrameData(
        width: width,
        height: height,
        pixels: pixels,
        frameCount: frameCount,
      );
    } catch (_) {
      return null;
    }
  }

  /// Alias for getFrameDirect on web.
  static BevyFrameData? getFrameJson({required String sceneId}) {
    return getFrameDirect(sceneId: sceneId);
  }

  static bool sendInput({
    required String sceneId,
    required String inputJson,
  }) {
    if (!_wasmAvailable) return false;
    try {
      return _wasmSendInput(sceneId.toJS, inputJson.toJS).toDart;
    } catch (_) {
      return false;
    }
  }

  static bool destroyScene({required String sceneId}) {
    if (!_wasmAvailable) return false;
    try {
      return _wasmDestroyScene(sceneId.toJS).toDart;
    } catch (_) {
      return false;
    }
  }

  static bool sceneExists({required String sceneId}) {
    if (!_wasmAvailable) return false;
    try {
      return _wasmSceneExists(sceneId.toJS).toDart;
    } catch (_) {
      return false;
    }
  }

  static double getElapsedTime({required String sceneId}) {
    if (!_wasmAvailable) return 0.0;
    try {
      return _wasmGetElapsedTime(sceneId.toJS).toDartDouble;
    } catch (_) {
      return 0.0;
    }
  }
}
