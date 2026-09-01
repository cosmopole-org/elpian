/// The embedded-Godot transport seam.
///
/// A binding moves ops from Dart to a real Godot 4 engine and surfaces its
/// replies and signal callbacks. Three implementations exist, chosen at runtime
/// by [resolveGodotBinding]:
///
///   * **native** ([MethodChannelGodotBinding]) — Android/iOS. Ops cross a
///     platform channel into the embedded Godot library, which drains them each
///     frame through the reflective `ElpianScene3D` interpreter. The viewport is
///     a platform view.
///   * **web** ([WebGodotBinding], see `godot_binding_web.dart`) — a Godot HTML5
///     export in a canvas, fed over a JS drain hook.
///   * **mock** ([MockGodotBinding]) — records ops and mints handles. Used in
///     tests and on any platform where the Godot artifact is absent, so the 2D
///     app stays fully live and `Scene3D` degrades to a placeholder rather than
///     crashing the tree.
///
/// Ops are **fire-and-forget**: handles are allocated on this side, so a create
/// needs no round trip and the engine can apply the op a frame later. Only ops
/// that genuinely read state (`get`, `method` with a return, `classinfo`) await
/// a reply.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'protocol.dart';

/// A callback delivered from the engine: a connected signal fired.
typedef GodotSignalDispatch = void Function(int callbackId, List<Object?> args);

/// The contract every transport implements.
abstract class GodotBinding {
  /// Whether a real engine is behind this binding. False for [MockGodotBinding],
  /// which is the cue for `Scene3D` to draw its placeholder.
  bool get isLive;

  /// Send a batch of ops in one crossing and return their replies, in order.
  ///
  /// Implementations may reply with nulls for ops that carry no result — the
  /// controller only reads positions it knows produce a value.
  Future<List<Wire>> send(List<Op> ops);

  /// Send a batch without awaiting replies. The hot path: property writes,
  /// node creation, transform updates.
  void post(List<Op> ops);

  /// Bind a `Scene3D` surface to a viewport rooted at [mountHandle].
  Future<void> mountSurface(int surfaceId, int mountHandle);

  /// Release a surface's viewport when its widget is disposed.
  Future<void> releaseSurface(int surfaceId);

  /// Signal callbacks arriving from the engine.
  set onSignal(GodotSignalDispatch? handler);

  /// Transport diagnostics (`{pushed, polls, drained}`), when available.
  Future<Map<String, Object?>?> stats() async => null;

  void dispose() {}
}

// ---------------------------------------------------------------------------
// Native
// ---------------------------------------------------------------------------

/// The channel names the native module registers. Kept here so the Dart and
/// native sides have one shared definition to disagree about.
abstract final class GodotChannels {
  static const ops = 'elpian/godot/ops';
  static const events = 'elpian/godot/events';
  static const viewType = 'elpian/godot/surface';
}

/// Ops cross a platform channel to the embedded Godot library.
class MethodChannelGodotBinding implements GodotBinding {
  MethodChannelGodotBinding({
    MethodChannel? channel,
    EventChannel? events,
  })  : _channel = channel ?? const MethodChannel(GodotChannels.ops),
        _events = events ?? const EventChannel(GodotChannels.events) {
    _subscription = _events.receiveBroadcastStream().listen(
      _dispatchEvent,
      onError: (Object e) =>
          debugPrint('ElpianGodot: event channel error: $e'),
    );
  }

  final MethodChannel _channel;
  final EventChannel _events;
  StreamSubscription<dynamic>? _subscription;

  @override
  GodotSignalDispatch? onSignal;

  @override
  bool get isLive => true;

  @override
  Future<List<Wire>> send(List<Op> ops) async {
    if (ops.isEmpty) return const [];
    final reply = await _channel.invokeMethod<String>('batch', encodeOps(ops));
    return reply == null ? const [] : decodeReplies(reply);
  }

  @override
  void post(List<Op> ops) {
    if (ops.isEmpty) return;
    // Deliberately not awaited: the engine applies these a frame later and the
    // caller already knows every handle involved.
    _channel.invokeMethod<void>('post', encodeOps(ops)).catchError(
      (Object e) => debugPrint('ElpianGodot: post failed: $e'),
    );
  }

  @override
  Future<void> mountSurface(int surfaceId, int mountHandle) =>
      _channel.invokeMethod<void>('mountSurface', {
        'surfaceId': surfaceId,
        'mountNode': mountHandle,
      });

  @override
  Future<void> releaseSurface(int surfaceId) =>
      _channel.invokeMethod<void>('releaseSurface', {'surfaceId': surfaceId});

  @override
  Future<Map<String, Object?>?> stats() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('stats');
    return raw?.map((k, v) => MapEntry('$k', v));
  }

  void _dispatchEvent(dynamic event) {
    if (event is! Map) return;
    final id = event['cb'];
    if (id is! int) return;
    final args = event['args'];
    onSignal?.call(id, args is List ? args : const []);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}

// ---------------------------------------------------------------------------
// Mock
// ---------------------------------------------------------------------------

/// A no-engine binding: records every op and mints handles the caller did not
/// supply, so the whole 3D pipeline is exercisable in tests and on platforms
/// without the Godot artifact.
///
/// This is what makes `Scene3D` safe to put in any tree: with no engine present
/// the widget renders a placeholder and the surrounding 2D app is unaffected.
class MockGodotBinding implements GodotBinding {
  final List<Op> ops = [];
  final Map<int, int> surfaces = {};
  int _nextHostHandle = 1000000;

  @override
  GodotSignalDispatch? onSignal;

  @override
  bool get isLive => false;

  @override
  Future<List<Wire>> send(List<Op> batch) async => batch.map(_record).toList();

  @override
  void post(List<Op> batch) {
    for (final op in batch) {
      _record(op);
    }
  }

  Wire _record(Op op) {
    ops.add(op);
    // Echo the caller-allocated handle for object-producing ops so control flow
    // keeps working; mint one only when the caller did not supply it.
    final producesHandle = op.containsKey(OpKey.create) ||
        op[OpKey.self] == true ||
        op[OpKey.tree] == true ||
        op.containsKey(OpKey.singleton) ||
        op.containsKey(OpKey.load);
    if (producesHandle) {
      final def = op[OpKey.def];
      return (def is int && def != 0) ? def : _nextHostHandle++;
    }
    return null;
  }

  @override
  Future<void> mountSurface(int surfaceId, int mountHandle) async {
    surfaces[surfaceId] = mountHandle;
  }

  @override
  Future<void> releaseSurface(int surfaceId) async {
    surfaces.remove(surfaceId);
  }

  /// Deliver a signal as if the engine had fired it — for tests.
  void fireSignal(int callbackId, List<Object?> args) =>
      onSignal?.call(callbackId, args);

  void clear() => ops.clear();

  @override
  Future<Map<String, Object?>?> stats() async =>
      {'pushed': ops.length, 'polls': 0, 'drained': ops.length};

  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
// Resolution
// ---------------------------------------------------------------------------

/// Override the binding process-wide — for tests, or to install a custom
/// transport. Set back to null to restore automatic resolution.
GodotBinding? debugGodotBindingOverride;

GodotBinding? _resolved;

/// The binding for this platform, created once.
///
/// Falls back to [MockGodotBinding] whenever a live engine cannot be reached,
/// so a missing Godot artifact degrades a `Scene3D` to a placeholder instead of
/// taking down the widget tree.
GodotBinding resolveGodotBinding() {
  final override = debugGodotBindingOverride;
  if (override != null) return override;
  return _resolved ??= _createBinding();
}

/// Drop the cached binding (tests, hot restart).
void resetGodotBinding() {
  _resolved?.dispose();
  _resolved = null;
}

GodotBinding _createBinding() {
  if (kIsWeb) {
    // The web binding lives behind a conditional import so `dart:js_interop`
    // never reaches a native build; it registers itself when loaded.
    return webGodotBindingFactory?.call() ?? MockGodotBinding();
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return MethodChannelGodotBinding();
    case TargetPlatform.macOS:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
    case TargetPlatform.fuchsia:
      // Desktop embedding is not wired yet — degrade rather than throw.
      return MockGodotBinding();
  }
}

/// Installed by the web binding when it is compiled in.
GodotBinding Function()? webGodotBindingFactory;
