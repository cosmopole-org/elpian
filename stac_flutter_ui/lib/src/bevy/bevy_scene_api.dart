/// Native FFI bindings to the Elpian Bevy 3D scene renderer.
///
/// On native platforms (Android, iOS, macOS, Linux, Windows), this uses
/// dart:ffi to call into the compiled Rust cdylib/staticlib for high-performance
/// 3D scene rendering. Frame data is transferred as raw RGBA pixel buffers.
library;

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// ── Native function typedefs ────────────────────────────────────────

typedef _VoidC = ffi.Void Function();
typedef _VoidDart = void Function();

typedef _FreeStringC = ffi.Void Function(ffi.Pointer<Utf8>);
typedef _FreeStringDart = void Function(ffi.Pointer<Utf8>);

typedef _CreateSceneC = ffi.Int32 Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Uint32, ffi.Uint32);
typedef _CreateSceneDart = int Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, int, int);

typedef _UpdateSceneC = ffi.Int32 Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
typedef _UpdateSceneDart = int Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);

typedef _RenderFrameC = ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Float);
typedef _RenderFrameDart = int Function(ffi.Pointer<Utf8>, double);

typedef _ResizeSceneC = ffi.Int32 Function(
    ffi.Pointer<Utf8>, ffi.Uint32, ffi.Uint32);
typedef _ResizeSceneDart = int Function(ffi.Pointer<Utf8>, int, int);

typedef _GetFramePtrC = ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<Utf8>);
typedef _GetFramePtrDart = ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<Utf8>);

typedef _GetFrameJsonC = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);
typedef _GetFrameJsonDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);

typedef _GetFrameSizeC = ffi.Uint32 Function(ffi.Pointer<Utf8>);
typedef _GetFrameSizeDart = int Function(ffi.Pointer<Utf8>);

typedef _GetDimensionsC = ffi.Uint64 Function(ffi.Pointer<Utf8>);
typedef _GetDimensionsDart = int Function(ffi.Pointer<Utf8>);

typedef _SendInputC = ffi.Int32 Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
typedef _SendInputDart = int Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);

typedef _DestroyC = ffi.Int32 Function(ffi.Pointer<Utf8>);
typedef _DestroyDart = int Function(ffi.Pointer<Utf8>);

typedef _GetElapsedC = ffi.Float Function(ffi.Pointer<Utf8>);
typedef _GetElapsedDart = double Function(ffi.Pointer<Utf8>);

typedef _GetFrameCountC = ffi.Uint64 Function(ffi.Pointer<Utf8>);
typedef _GetFrameCountDart = int Function(ffi.Pointer<Utf8>);

// ── Dynamic library loader ──────────────────────────────────────────

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

// ── Frame data result ───────────────────────────────────────────────

/// Holds the rendered frame data from the Bevy scene renderer.
class BevyFrameData {
  final int width;
  final int height;
  final Uint8List pixels; // RGBA8 pixel data
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

// ── API class ───────────────────────────────────────────────────────

/// Native FFI bindings to the Elpian Bevy 3D scene renderer.
///
/// This class provides direct access to the Rust-based 3D rendering engine
/// through dart:ffi. It supports creating scenes from JSON, rendering frames,
/// retrieving pixel data, and forwarding input events.
class BevySceneApi {
  static BevySceneApi? _instance;
  late final ffi.DynamicLibrary _lib;

  late final _VoidDart _init;
  late final _FreeStringDart _freeString;
  late final _CreateSceneDart _createScene;
  late final _UpdateSceneDart _updateScene;
  late final _RenderFrameDart _renderFrame;
  late final _ResizeSceneDart _resizeScene;
  late final _GetFramePtrDart _getFramePtr;
  late final _GetFrameJsonDart _getFrameJson;
  late final _GetFrameSizeDart _getFrameSize;
  late final _GetDimensionsDart _getDimensions;
  late final _SendInputDart _sendInput;
  late final _DestroyDart _destroyScene;
  late final _DestroyDart _sceneExists;
  late final _GetElapsedDart _getElapsedTime;
  late final _GetFrameCountDart _getFrameCount;

  BevySceneApi._() {
    _lib = _loadLibrary();
    _init = _lib.lookupFunction<_VoidC, _VoidDart>('elpian_bevy_init');
    _freeString = _lib
        .lookupFunction<_FreeStringC, _FreeStringDart>('elpian_free_string');
    _createScene = _lib
        .lookupFunction<_CreateSceneC, _CreateSceneDart>(
            'elpian_bevy_create_scene');
    _updateScene = _lib
        .lookupFunction<_UpdateSceneC, _UpdateSceneDart>(
            'elpian_bevy_update_scene');
    _renderFrame = _lib
        .lookupFunction<_RenderFrameC, _RenderFrameDart>(
            'elpian_bevy_render_frame');
    _resizeScene = _lib
        .lookupFunction<_ResizeSceneC, _ResizeSceneDart>(
            'elpian_bevy_resize_scene');
    _getFramePtr = _lib
        .lookupFunction<_GetFramePtrC, _GetFramePtrDart>(
            'elpian_bevy_get_frame_ptr');
    _getFrameJson = _lib
        .lookupFunction<_GetFrameJsonC, _GetFrameJsonDart>(
            'elpian_bevy_get_frame_json');
    _getFrameSize = _lib
        .lookupFunction<_GetFrameSizeC, _GetFrameSizeDart>(
            'elpian_bevy_get_frame_size');
    _getDimensions = _lib
        .lookupFunction<_GetDimensionsC, _GetDimensionsDart>(
            'elpian_bevy_get_scene_dimensions');
    _sendInput = _lib
        .lookupFunction<_SendInputC, _SendInputDart>(
            'elpian_bevy_send_input');
    _destroyScene = _lib
        .lookupFunction<_DestroyC, _DestroyDart>(
            'elpian_bevy_destroy_scene');
    _sceneExists = _lib
        .lookupFunction<_DestroyC, _DestroyDart>(
            'elpian_bevy_scene_exists');
    _getElapsedTime = _lib
        .lookupFunction<_GetElapsedC, _GetElapsedDart>(
            'elpian_bevy_get_elapsed_time');
    _getFrameCount = _lib
        .lookupFunction<_GetFrameCountC, _GetFrameCountDart>(
            'elpian_bevy_get_frame_count');
  }

  factory BevySceneApi() {
    _instance ??= BevySceneApi._();
    return _instance!;
  }

  // ── Static API methods ──────────────────────────────────────────

  /// Initialize the Bevy scene subsystem. Call once at app startup.
  static void initSceneSystem() {
    BevySceneApi()._init();
  }

  /// Create a new 3D scene from JSON.
  static bool createScene({
    required String sceneId,
    required String json,
    required int width,
    required int height,
  }) {
    final api = BevySceneApi();
    final sidPtr = sceneId.toNativeUtf8();
    final jsonPtr = json.toNativeUtf8();
    try {
      return api._createScene(sidPtr, jsonPtr, width, height) == 1;
    } finally {
      malloc.free(sidPtr);
      malloc.free(jsonPtr);
    }
  }

  /// Update an existing scene with new JSON data.
  static bool updateScene({
    required String sceneId,
    required String json,
  }) {
    final api = BevySceneApi();
    final sidPtr = sceneId.toNativeUtf8();
    final jsonPtr = json.toNativeUtf8();
    try {
      return api._updateScene(sidPtr, jsonPtr) == 1;
    } finally {
      malloc.free(sidPtr);
      malloc.free(jsonPtr);
    }
  }

  /// Render one frame of the scene.
  static bool renderFrame({
    required String sceneId,
    required double deltaTime,
  }) {
    final api = BevySceneApi();
    final sidPtr = sceneId.toNativeUtf8();
    try {
      return api._renderFrame(sidPtr, deltaTime) == 1;
    } finally {
      malloc.free(sidPtr);
    }
  }

  /// Resize the scene's render target.
  static bool resizeScene({
    required String sceneId,
    required int width,
    required int height,
  }) {
    final api = BevySceneApi();
    final sidPtr = sceneId.toNativeUtf8();
    try {
      return api._resizeScene(sidPtr, width, height) == 1;
    } finally {
      malloc.free(sidPtr);
    }
  }

  /// Get the rendered frame as raw RGBA pixel data via direct memory access.
  ///
  /// This is the highest-performance path for native platforms.
  /// Returns null if the scene doesn't exist.
  static BevyFrameData? getFrameDirect({required String sceneId}) {
    final api = BevySceneApi();
    final sidPtr = sceneId.toNativeUtf8();
    try {
      final size = api._getFrameSize(sidPtr);
      if (size == 0) return null;

      final ptr = api._getFramePtr(sidPtr);
      if (ptr == ffi.nullptr) return null;

      final dims = api._getDimensions(sidPtr);
      final width = (dims >> 32) & 0xFFFFFFFF;
      final height = dims & 0xFFFFFFFF;

      // Copy pixels from native memory into a Dart Uint8List
      final pixels = Uint8List(size);
      for (var i = 0; i < size; i++) {
        pixels[i] = ptr[i];
      }

      return BevyFrameData(
        width: width,
        height: height,
        pixels: pixels,
        frameCount: api._getFrameCount(sidPtr),
      );
    } finally {
      malloc.free(sidPtr);
    }
  }

  /// Get the rendered frame via JSON (includes base64-encoded pixel data).
  /// Slower than getFrameDirect but works across all platforms.
  static BevyFrameData? getFrameJson({required String sceneId}) {
    final api = BevySceneApi();
    final sidPtr = sceneId.toNativeUtf8();
    try {
      final resultPtr = api._getFrameJson(sidPtr);
      final jsonStr = resultPtr.toDartString();
      api._freeString(resultPtr);

      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (!json.containsKey('width')) return null;

      final width = json['width'] as int;
      final height = json['height'] as int;
      final dataStr = json['data'] as String;
      final frameCount = json['frameCount'] as int;

      final pixels = base64Decode(dataStr);

      return BevyFrameData(
        width: width,
        height: height,
        pixels: Uint8List.fromList(pixels),
        frameCount: frameCount,
      );
    } finally {
      malloc.free(sidPtr);
    }
  }

  /// Send an input event to the scene.
  static bool sendInput({
    required String sceneId,
    required String inputJson,
  }) {
    final api = BevySceneApi();
    final sidPtr = sceneId.toNativeUtf8();
    final inputPtr = inputJson.toNativeUtf8();
    try {
      return api._sendInput(sidPtr, inputPtr) == 1;
    } finally {
      malloc.free(sidPtr);
      malloc.free(inputPtr);
    }
  }

  /// Destroy a scene and free its resources.
  static bool destroyScene({required String sceneId}) {
    final api = BevySceneApi();
    final sidPtr = sceneId.toNativeUtf8();
    try {
      return api._destroyScene(sidPtr) == 1;
    } finally {
      malloc.free(sidPtr);
    }
  }

  /// Check if a scene exists.
  static bool sceneExists({required String sceneId}) {
    final api = BevySceneApi();
    final sidPtr = sceneId.toNativeUtf8();
    try {
      return api._sceneExists(sidPtr) == 1;
    } finally {
      malloc.free(sidPtr);
    }
  }

  /// Get the elapsed time for a scene.
  static double getElapsedTime({required String sceneId}) {
    final api = BevySceneApi();
    final sidPtr = sceneId.toNativeUtf8();
    try {
      return api._getElapsedTime(sidPtr);
    } finally {
      malloc.free(sidPtr);
    }
  }
}
