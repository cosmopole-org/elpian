/// A handle to any engine object.
///
/// Objects never cross the seam — handles do. Every `GodotObject` is a thin
/// façade over an integer handle plus the controller that owns the transport;
/// each method turns into one op.
///
/// Because dispatch is reflective (by name, through `ClassDB`), this one class
/// covers *every* Godot class. There is no per-class wrapper to keep in sync
/// with the engine, and classes added in future Godot versions work unchanged.
library;

import 'godot_controller.dart';
import 'godot_values.dart';
import 'protocol.dart';

class GodotObject implements GodotHandle {
  GodotObject(this.controller, this.handle);

  final GodotController controller;

  /// The engine-side handle. Allocated on this side, so it is valid to use in
  /// further ops immediately — before the engine has even seen the create.
  final int handle;

  @override
  GodotRef get ref => GodotRef(handle);

  // -------------------------------------------------------------------------
  // Methods and properties
  // -------------------------------------------------------------------------

  /// Call any method by name, awaiting its return value.
  ///
  /// Use [callVoid] when the result is not needed — it avoids a round trip.
  Future<Object?> call(String method, [List<Object?>? args]) =>
      controller.request({
        OpKey.ref: handle,
        OpKey.method: method,
        OpKey.args: marshalArgs(args),
      });

  /// Call any method by name without awaiting a result — the hot path.
  void callVoid(String method, [List<Object?>? args]) => controller.enqueue({
        OpKey.ref: handle,
        OpKey.method: method,
        OpKey.args: marshalArgs(args),
      });

  /// Read any property.
  Future<Object?> get(String property) => controller.request({
        OpKey.ref: handle,
        OpKey.get: property,
      });

  /// Write any property. Fire-and-forget.
  void set(String property, Object? value) => controller.enqueue({
        OpKey.ref: handle,
        OpKey.set: property,
        OpKey.value: marshal(value),
      });

  /// Write several properties in one op — cheaper than one op each when
  /// configuring a freshly created node.
  void setAll(Map<String, Object?> properties) {
    if (properties.isEmpty) return;
    controller.enqueue({
      OpKey.ref: handle,
      OpKey.props: {
        for (final e in properties.entries) e.key: marshal(e.value),
      },
    });
  }

  /// Read a nested sub-property, e.g. `position:x`.
  Future<Object?> getIndexed(String path) => controller.request({
        OpKey.ref: handle,
        OpKey.getIndexed: path,
      });

  /// Write a nested sub-property, e.g. `position:x`.
  void setIndexed(String path, Object? value) => controller.enqueue({
        OpKey.ref: handle,
        OpKey.setIndexed: path,
        OpKey.value: marshal(value),
      });

  // -------------------------------------------------------------------------
  // Signals
  // -------------------------------------------------------------------------

  /// Connect any signal to a Dart closure.
  ///
  /// Returns the callback id, which [disconnect] takes. The closure is invoked
  /// when the engine delivers the signal — a *later* turn, never synchronously
  /// inside the call that caused it.
  int connect(String signal, GodotSignalCallback callback, {int flags = 0}) {
    final id = controller.registerCallback(callback);
    controller.enqueue({
      OpKey.ref: handle,
      OpKey.connect: signal,
      OpKey.cb: id,
      if (flags != 0) OpKey.flags: flags,
    });
    return id;
  }

  void disconnect(String signal, int callbackId) {
    controller.enqueue({
      OpKey.ref: handle,
      OpKey.disconnect: signal,
      OpKey.cb: callbackId,
    });
    controller.unregisterCallback(callbackId);
  }

  /// This object's signal as a value (for APIs that take a Signal).
  GSignal signal(String name) => GSignal(handle, name);

  void emitSignal(String name, [List<Object?>? args]) =>
      callVoid('emit_signal', [name, ...?args]);

  // -------------------------------------------------------------------------
  // Tree helpers
  // -------------------------------------------------------------------------

  /// `add_child` — the spelling every scene build uses.
  void addChild(GodotObject child) => callVoid('add_child', [child]);

  void removeChild(GodotObject child) => callVoid('remove_child', [child]);

  /// Add several children in one batch.
  void addChildren(Iterable<GodotObject> children) {
    for (final c in children) {
      addChild(c);
    }
  }

  // -------------------------------------------------------------------------
  // Lifetime
  // -------------------------------------------------------------------------

  /// `queue_free()` — the safe removal, at the end of the frame.
  void queueFree() => callVoid('queue_free');

  /// `memdelete` — immediate. Prefer [queueFree] for nodes in the tree.
  void freeNow() => controller.enqueue({OpKey.free: handle});

  /// Drop this side's handle without destroying the object. A `RefCounted` may
  /// then free itself.
  void release() => controller.releaseHandle(handle);

  @override
  bool operator ==(Object other) =>
      other is GodotObject && other.handle == handle;

  @override
  int get hashCode => handle.hashCode;

  @override
  String toString() => 'GodotObject(#$handle)';
}

/// A connected signal's Dart side.
typedef GodotSignalCallback = void Function(List<Object?> args);
