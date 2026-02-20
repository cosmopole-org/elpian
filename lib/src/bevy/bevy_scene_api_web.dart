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
external bool _wasmCreateScene(
    String sceneId, String json, int width, int height);

@JS('elpian_bevy_wasm_update_scene')
external bool _wasmUpdateScene(String sceneId, String json);

@JS('elpian_bevy_wasm_render_frame')
external bool _wasmRenderFrame(String sceneId, double deltaTime);

@JS('elpian_bevy_wasm_resize_scene')
external bool _wasmResizeScene(String sceneId, int width, int height);

@JS('elpian_bevy_wasm_get_frame')
external String _wasmGetFrame(String sceneId);

@JS('elpian_bevy_wasm_get_frame_bytes')
external JSUint8Array _wasmGetFrameBytes(String sceneId);

@JS('elpian_bevy_wasm_send_input')
external bool _wasmSendInput(String sceneId, String inputJson);

@JS('elpian_bevy_wasm_destroy_scene')
external bool _wasmDestroyScene(String sceneId);

@JS('elpian_bevy_wasm_scene_exists')
external bool _wasmSceneExists(String sceneId);

@JS('elpian_bevy_wasm_get_elapsed_time')
external double _wasmGetElapsedTime(String sceneId);

@JS('elpian_bevy_wasm_get_frame_count')
external int _wasmGetFrameCount(String sceneId);

// ── API class ───────────────────────────────────────────────────────

/// Web FFI bindings to the Elpian Bevy 3D scene renderer.
class BevySceneApi {
  static void initSceneSystem() {
    _wasmInit();
  }

  static bool createScene({
    required String sceneId,
    required String json,
    required int width,
    required int height,
  }) {
    return _wasmCreateScene(sceneId, json, width, height);
  }

  static bool updateScene({
    required String sceneId,
    required String json,
  }) {
    return _wasmUpdateScene(sceneId, json);
  }

  static bool renderFrame({
    required String sceneId,
    required double deltaTime,
  }) {
    return _wasmRenderFrame(sceneId, deltaTime);
  }

  static bool resizeScene({
    required String sceneId,
    required int width,
    required int height,
  }) {
    return _wasmResizeScene(sceneId, width, height);
  }

  /// Get the rendered frame as raw RGBA pixel data.
  static BevyFrameData? getFrameDirect({required String sceneId}) {
    final frameJson = _wasmGetFrame(sceneId);
    final json = jsonDecode(frameJson) as Map<String, dynamic>;
    if (!json.containsKey('width')) return null;

    final width = json['width'] as int;
    final height = json['height'] as int;
    final frameCount = json['frameCount'] as int;

    // Get raw pixel bytes from WASM
    final jsBytes = _wasmGetFrameBytes(sceneId);
    final pixels = jsBytes.toDart;

    return BevyFrameData(
      width: width,
      height: height,
      pixels: pixels,
      frameCount: frameCount,
    );
  }

  /// Alias for getFrameDirect on web.
  static BevyFrameData? getFrameJson({required String sceneId}) {
    return getFrameDirect(sceneId: sceneId);
  }

  static bool sendInput({
    required String sceneId,
    required String inputJson,
  }) {
    return _wasmSendInput(sceneId, inputJson);
  }

  static bool destroyScene({required String sceneId}) {
    return _wasmDestroyScene(sceneId);
  }

  static bool sceneExists({required String sceneId}) {
    return _wasmSceneExists(sceneId);
  }

  static double getElapsedTime({required String sceneId}) {
    return _wasmGetElapsedTime(sceneId);
  }
}
