import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'canvas_api.dart';

class CanvasContextStore {
  CanvasContextStore._();

  static final CanvasContextStore instance = CanvasContextStore._();

  final Map<String, CanvasContext> _contexts = {};
  int _nextId = 1;

  CanvasContext create({String? id, double width = 0, double height = 0}) {
    final resolvedId = (id == null || id.isEmpty) ? 'ctx_${_nextId++}' : id;
    final existing = _contexts[resolvedId];
    if (existing != null) {
      return existing;
    }
    final ctx = CanvasContext(
      id: resolvedId,
      width: width,
      height: height,
    );
    _contexts[resolvedId] = ctx;
    return ctx;
  }

  CanvasContext? get(String id) => _contexts[id];

  void dispose(String id) {
    final ctx = _contexts.remove(id);
    ctx?.dispose();
  }

  void clearAll() {
    for (final ctx in _contexts.values) {
      ctx.dispose();
    }
    _contexts.clear();
  }
}

class CanvasContext {
  final String id;
  double width;
  double height;
  final CanvasAPIExecutor executor = CanvasAPIExecutor();

  final ValueNotifier<int> version = ValueNotifier<int>(0);
  bool _dirty = true;
  ui.Picture? _picture;
  final List<CanvasCommand> _pendingCommands = [];
  bool _forceFullRebuild = false;

  CanvasContext({
    required this.id,
    required this.width,
    required this.height,
  });

  void setSize(double w, double h) {
    if (w == width && h == height) return;
    width = w;
    height = h;
    _forceFullRebuild = true;
    _picture?.dispose();
    _picture = null;
    _markDirty();
  }

  void addCommand(CanvasCommand command) {
    executor.addCommand(command);
    _pendingCommands.add(command);
    _markDirty();
  }

  void addCommands(List<CanvasCommand> commands) {
    for (final cmd in commands) {
      executor.addCommand(cmd);
      _pendingCommands.add(cmd);
    }
    _markDirty();
  }

  void clear() {
    executor.clear();
    _pendingCommands.clear();
    _forceFullRebuild = true;
    _picture?.dispose();
    _picture = null;
    _markDirty();
  }

  ui.Picture? getPicture() {
    if (!_dirty && _picture != null) return _picture;
    if (width <= 0 || height <= 0) return _picture;

    final size = ui.Size(width, height);
    ui.Picture? picture;

    if (_picture == null || _forceFullRebuild) {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      executor.execute(canvas, size);
      picture = recorder.endRecording();
      _forceFullRebuild = false;
      _pendingCommands.clear();
    } else if (_pendingCommands.isNotEmpty) {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawPicture(_picture!);
      executor.executeCommands(canvas, size, _pendingCommands);
      picture = recorder.endRecording();
      _pendingCommands.clear();
    } else {
      _dirty = false;
      return _picture;
    }

    _picture?.dispose();
    _picture = picture;
    _dirty = false;
    return _picture;
  }

  void dispose() {
    _picture?.dispose();
    _picture = null;
    _pendingCommands.clear();
    version.dispose();
  }

  void _markDirty() {
    _dirty = true;
    version.value = version.value + 1;
  }
}
