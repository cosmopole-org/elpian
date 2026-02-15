import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'bevy_scene_api.dart'
    if (dart.library.js_interop) 'bevy_scene_api_web.dart';

/// High-level controller for managing a Bevy 3D scene.
///
/// This class wraps the FFI API to provide a convenient interface for
/// creating, updating, rendering, and interacting with 3D scenes defined
/// in JSON. It handles scene lifecycle, rendering loop management, and
/// input event forwarding.
///
/// Usage:
/// ```dart
/// final controller = BevySceneController(sceneId: 'my-scene');
/// await controller.loadScene(jsonString, width: 800, height: 600);
/// controller.renderFrame(deltaTime: 1/60);
/// final frame = controller.getFrame();
/// ```
class BevySceneController {
  final String sceneId;
  int _width = 0;
  int _height = 0;
  bool _isLoaded = false;
  int _frameCount = 0;

  /// Callback invoked whenever a new frame is rendered.
  VoidCallback? onFrameReady;

  BevySceneController({required this.sceneId});

  /// Whether a scene is currently loaded.
  bool get isLoaded => _isLoaded;

  /// Current render width.
  int get width => _width;

  /// Current render height.
  int get height => _height;

  /// Number of frames rendered.
  int get frameCount => _frameCount;

  /// Initialize the Bevy scene subsystem.
  /// Call once at app startup before creating any scenes.
  static void initialize() {
    BevySceneApi.initSceneSystem();
  }

  /// Load a 3D scene from a JSON string.
  ///
  /// The JSON should follow the SceneDef format:
  /// ```json
  /// {
  ///   "world": [
  ///     {"type": "mesh3d", "mesh": "Cube", "material": {...}, "transform": {...}},
  ///     {"type": "light", "light_type": "Directional", ...},
  ///     {"type": "camera", "camera_type": "Perspective", ...}
  ///   ]
  /// }
  /// ```
  bool loadScene(String json, {required int width, required int height}) {
    _width = width;
    _height = height;

    final success = BevySceneApi.createScene(
      sceneId: sceneId,
      json: json,
      width: width,
      height: height,
    );

    _isLoaded = success;
    return success;
  }

  /// Load a scene from a JSON Map.
  bool loadSceneFromMap(Map<String, dynamic> sceneMap,
      {required int width, required int height}) {
    return loadScene(jsonEncode(sceneMap), width: width, height: height);
  }

  /// Update the scene with new JSON data.
  ///
  /// This replaces the scene definition while preserving animation state
  /// for smooth transitions.
  bool updateScene(String json) {
    if (!_isLoaded) return false;
    return BevySceneApi.updateScene(sceneId: sceneId, json: json);
  }

  /// Update the scene from a JSON Map.
  bool updateSceneFromMap(Map<String, dynamic> sceneMap) {
    return updateScene(jsonEncode(sceneMap));
  }

  /// Render one frame of the scene.
  ///
  /// [deltaTime] is the time elapsed since the last frame in seconds.
  /// Typical usage: pass 1/60 for 60fps, or use the actual elapsed time
  /// from a Ticker/AnimationController.
  bool renderFrame({double deltaTime = 1 / 60}) {
    if (!_isLoaded) return false;

    final success = BevySceneApi.renderFrame(
      sceneId: sceneId,
      deltaTime: deltaTime,
    );

    if (success) {
      _frameCount++;
      onFrameReady?.call();
    }

    return success;
  }

  /// Get the latest rendered frame data.
  ///
  /// Returns null if no frame has been rendered yet or the scene doesn't exist.
  /// The returned BevyFrameData contains RGBA8 pixel data that can be
  /// converted to a dart:ui Image for display.
  BevyFrameData? getFrame() {
    if (!_isLoaded) return null;
    return BevySceneApi.getFrameDirect(sceneId: sceneId);
  }

  /// Resize the render target.
  bool resize({required int width, required int height}) {
    if (!_isLoaded) return false;
    _width = width;
    _height = height;
    return BevySceneApi.resizeScene(
      sceneId: sceneId,
      width: width,
      height: height,
    );
  }

  /// Send a touch/pointer event to the scene.
  bool sendTouchDown(double x, double y) {
    return _sendInput('TouchDown', x, y);
  }

  /// Send a touch move event.
  bool sendTouchMove(double x, double y,
      {double deltaX = 0, double deltaY = 0}) {
    return _sendInput('TouchMove', x, y, deltaX: deltaX, deltaY: deltaY);
  }

  /// Send a touch up event.
  bool sendTouchUp(double x, double y) {
    return _sendInput('TouchUp', x, y);
  }

  /// Send a mouse wheel event.
  bool sendMouseWheel(double x, double y,
      {double deltaX = 0, double deltaY = 0}) {
    return _sendInput('MouseWheel', x, y, deltaX: deltaX, deltaY: deltaY);
  }

  bool _sendInput(String eventType, double x, double y,
      {double deltaX = 0, double deltaY = 0}) {
    if (!_isLoaded) return false;

    final inputJson = jsonEncode({
      'event_type': eventType,
      'x': x,
      'y': y,
      'delta_x': deltaX,
      'delta_y': deltaY,
    });

    return BevySceneApi.sendInput(sceneId: sceneId, inputJson: inputJson);
  }

  /// Get the elapsed time for the scene in seconds.
  double get elapsedTime {
    if (!_isLoaded) return 0;
    return BevySceneApi.getElapsedTime(sceneId: sceneId);
  }

  /// Dispose the controller and free Rust-side resources.
  void dispose() {
    if (_isLoaded) {
      BevySceneApi.destroyScene(sceneId: sceneId);
      _isLoaded = false;
    }
  }
}
