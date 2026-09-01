/// The Godot op protocol — the single, uniform vocabulary every 3D operation
/// crosses on.
///
/// Elpian does not wrap Godot's API by hand. The engine side runs a *reflective*
/// interpreter (`ElpianScene3D::exec_op_json`, the `elpian_godot` GDExtension)
/// that addresses the engine **by name** through `ClassDB`. So coverage is
/// complete by construction — every node class, method, property, signal,
/// singleton and constant, including ones added in future Godot versions —
/// and this Dart side only has to *transport* ops and marshal values.
///
/// The vocabulary is identical to the one Victor's React Native host and the
/// C++ `GodotController` already speak, so the engine-side interpreter is reused
/// verbatim. Only the transport differs (Flutter platform channels here, JSI
/// there).
library;

import 'dart:convert';

/// A value as it appears on the wire: JSON-shaped, with handles and callbacks
/// carried as tagged maps (`{"ref": id}` / `{"cb": id}`).
typedef Wire = Object?;

/// One op. Only a small subset of keys is present on any given op — the key
/// that is present *is* the op kind.
///
/// Kept as a plain map rather than a sealed class hierarchy: the set of kinds is
/// defined by the engine-side interpreter, not by us, and a map keeps this side
/// forward-compatible with kinds added there.
typedef Op = Map<String, Object?>;

/// Op keys, named so call sites read as the protocol rather than as strings.
abstract final class OpKey {
  // Object lifecycle.
  static const create = 'new';
  static const def = 'def';
  static const self = 'self';
  static const tree = 'tree';
  static const singleton = 'singleton';
  static const load = 'load';
  static const free = 'free';

  // Addressing an existing object.
  static const ref = 'ref';

  // Property access.
  static const get = 'get';
  static const set = 'set';
  static const getIndexed = 'geti';
  static const setIndexed = 'seti';
  static const value = 'value';
  static const props = 'props';

  // Method dispatch.
  static const method = 'method';
  static const args = 'args';
  static const static_ = 'static';

  // Signals.
  static const connect = 'connect';
  static const disconnect = 'disconnect';
  static const cb = 'cb';
  static const flags = 'flags';

  // Engine introspection / evaluation.
  static const constant = 'const';
  static const expr = 'expr';
  static const names = 'names';
  static const values = 'values';
  static const classes = 'classes';
  static const classInfo = 'classinfo';
  static const audit = 'audit';

  // Surface binding.
  static const mount = 'mount';
  static const surface = 'surface';
}

/// A handle to an engine object as it travels inside op arguments.
///
/// Objects never cross the seam — 64-bit handles do. A handle is allocated on
/// *this* side (see [HandleAllocator]) so a create op needs no round trip: the
/// caller already knows the handle it will refer to, and the engine applies the
/// op a frame later.
class GodotRef {
  const GodotRef(this.id);

  final int id;

  Map<String, Object?> toWire() => {'ref': id};

  static bool isRef(Object? v) =>
      v is Map && v.length == 1 && v['ref'] is int;

  static GodotRef fromWire(Map v) => GodotRef(v['ref'] as int);

  @override
  bool operator ==(Object other) => other is GodotRef && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'GodotRef($id)';
}

/// A callback registration as it travels inside op arguments.
class GodotCallbackRef {
  const GodotCallbackRef(this.id);

  final int id;

  Map<String, Object?> toWire() => {'cb': id};

  static bool isCallback(Object? v) =>
      v is Map && v.length == 1 && v['cb'] is int;

  @override
  String toString() => 'GodotCallbackRef($id)';
}

/// Anything that marshals to an engine handle.
///
/// Implemented by `GodotObject`. Declared here so [marshal] can recognise a
/// handle without `godot_values.dart` importing `godot_object.dart` — which
/// would close an import cycle through the controller.
abstract interface class GodotHandle {
  GodotRef get ref;
}

/// Allocates the handles this side hands to the engine.
///
/// Guest-allocated handles are what make the transport one-way: an op that
/// creates an object carries the handle it will be known by, so nothing has to
/// block on a reply. Starts above zero because `0` is the protocol's "no
/// handle", and `1` is reserved for the scene root (`{self: true}`).
class HandleAllocator {
  HandleAllocator({int start = selfHandle + 1}) : _next = start;

  /// The handle the engine binds to the `ElpianScene3D` root itself.
  static const int selfHandle = 1;

  int _next;

  int allocate() => _next++;

  /// How many handles have been handed out — diagnostics only.
  int get issued => _next - selfHandle - 1;
}

/// The error convention shared with the Godot bridge: a reply carrying
/// `__dart_error__` is a failure, not a value.
Map<String, Object?> wireError(String message) => {'__dart_error__': message};

/// Whether a reply is an engine-side error.
bool isWireError(Object? v) =>
    v is Map && v.containsKey('__dart_error__');

/// The message of an engine-side error reply, or null.
String? wireErrorMessage(Object? v) =>
    isWireError(v) ? (v as Map)['__dart_error__']?.toString() : null;

/// Raised when the engine reports an op failure.
class GodotOpException implements Exception {
  GodotOpException(this.message, {this.op});

  final String message;
  final Op? op;

  @override
  String toString() => op == null
      ? 'GodotOpException: $message'
      : 'GodotOpException: $message (op: ${jsonEncode(op)})';
}

/// Encode a batch of ops for the transport.
///
/// Ops are sent as a JSON array in one crossing. Batching is the difference
/// between one channel hop per frame and one per property write, so the
/// controller batches by default and this is the hot path.
String encodeOps(List<Op> ops) => jsonEncode(ops);

/// Decode the engine's replies to a batch.
List<Wire> decodeReplies(String json) {
  if (json.isEmpty) return const [];
  final decoded = jsonDecode(json);
  return decoded is List ? decoded : [decoded];
}
