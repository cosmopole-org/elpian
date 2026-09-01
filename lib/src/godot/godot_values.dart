/// Godot Variant value types and their wire marshaling.
///
/// Every Godot Variant shape a guest can hand to (or read back from) the engine
/// has a wrapper here and a tagged wire form. The tags are exactly the ones the
/// engine-side reflective interpreter already speaks — `{vec3: [x,y,z]}`,
/// `{color: [r,g,b,a]}`, `{xform3d: [...]}` and so on — so the same C++
/// `GodotController` marshaling is reused unchanged.
///
/// ## The int/float rule you must know
///
/// A Dart `num` is ambiguous at the boundary: Godot may need an `int` (an enum,
/// an index, a flag, a count) or a `float`. Bare numbers are marshaled by their
/// Dart type (`int` → int, `double` → float), which is usually right — but when
/// an API demands a specific one, be explicit with [GInt] / [GFloat]. Number
/// misbehaviour at the boundary is almost always this.
library;

import 'protocol.dart';

/// Base class for every Variant wrapper.
abstract class GodotValue {
  const GodotValue();

  /// This value's tagged wire form.
  Map<String, Object?> toWire();
}

// ---------------------------------------------------------------------------
// Vectors
// ---------------------------------------------------------------------------

class Vector2 extends GodotValue {
  const Vector2(this.x, this.y);
  const Vector2.zero() : x = 0, y = 0;
  final double x, y;
  @override
  Map<String, Object?> toWire() => {'vec2': [x, y]};
  @override
  String toString() => 'Vector2($x, $y)';
}

class Vector2i extends GodotValue {
  const Vector2i(this.x, this.y);
  final int x, y;
  @override
  Map<String, Object?> toWire() => {'vec2i': [x, y]};
  @override
  String toString() => 'Vector2i($x, $y)';
}

class Vector3 extends GodotValue {
  const Vector3(this.x, this.y, this.z);
  const Vector3.zero() : x = 0, y = 0, z = 0;
  const Vector3.all(double v) : x = v, y = v, z = v;
  final double x, y, z;

  Vector3 operator +(Vector3 o) => Vector3(x + o.x, y + o.y, z + o.z);
  Vector3 operator -(Vector3 o) => Vector3(x - o.x, y - o.y, z - o.z);
  Vector3 operator *(double s) => Vector3(x * s, y * s, z * s);

  @override
  Map<String, Object?> toWire() => {'vec3': [x, y, z]};
  @override
  String toString() => 'Vector3($x, $y, $z)';
}

class Vector3i extends GodotValue {
  const Vector3i(this.x, this.y, this.z);
  final int x, y, z;
  @override
  Map<String, Object?> toWire() => {'vec3i': [x, y, z]};
}

class Vector4 extends GodotValue {
  const Vector4(this.x, this.y, this.z, this.w);
  final double x, y, z, w;
  @override
  Map<String, Object?> toWire() => {'vec4': [x, y, z, w]};
}

class Vector4i extends GodotValue {
  const Vector4i(this.x, this.y, this.z, this.w);
  final int x, y, z, w;
  @override
  Map<String, Object?> toWire() => {'vec4i': [x, y, z, w]};
}

// ---------------------------------------------------------------------------
// Colour and geometry
// ---------------------------------------------------------------------------

class GodotColor extends GodotValue {
  const GodotColor(this.r, this.g, this.b, [this.a = 1.0]);

  /// From an `0xRRGGBB` literal, the spelling most scene code wants.
  factory GodotColor.hex(int rgb, [double a = 1.0]) => GodotColor(
        ((rgb >> 16) & 0xFF) / 255.0,
        ((rgb >> 8) & 0xFF) / 255.0,
        (rgb & 0xFF) / 255.0,
        a,
      );

  final double r, g, b, a;
  @override
  Map<String, Object?> toWire() => {'color': [r, g, b, a]};
  @override
  String toString() => 'GodotColor($r, $g, $b, $a)';
}

class Rect2 extends GodotValue {
  const Rect2(this.x, this.y, this.w, this.h);
  final double x, y, w, h;
  @override
  Map<String, Object?> toWire() => {'rect2': [x, y, w, h]};
}

class Rect2i extends GodotValue {
  const Rect2i(this.x, this.y, this.w, this.h);
  final int x, y, w, h;
  @override
  Map<String, Object?> toWire() => {'rect2i': [x, y, w, h]};
}

class Plane extends GodotValue {
  const Plane(this.nx, this.ny, this.nz, this.d);
  final double nx, ny, nz, d;
  @override
  Map<String, Object?> toWire() => {'plane': [nx, ny, nz, d]};
}

class Quaternion extends GodotValue {
  const Quaternion(this.x, this.y, this.z, this.w);
  final double x, y, z, w;
  @override
  Map<String, Object?> toWire() => {'quat': [x, y, z, w]};
}

class AABB extends GodotValue {
  const AABB(this.px, this.py, this.pz, this.sx, this.sy, this.sz);
  final double px, py, pz, sx, sy, sz;
  @override
  Map<String, Object?> toWire() => {'aabb': [px, py, pz, sx, sy, sz]};
}

/// A 3x3 basis, as three row triples.
class Basis extends GodotValue {
  const Basis(this.rows);
  final List<List<double>> rows;
  @override
  Map<String, Object?> toWire() => {'basis': rows};
}

/// A 2D transform, as a flat 6-element matrix.
class Transform2D extends GodotValue {
  const Transform2D(this.m);
  final List<double> m;
  @override
  Map<String, Object?> toWire() => {'xform2d': m};
}

/// A 3D transform, as a flat 12-element matrix (basis rows then origin).
class Transform3D extends GodotValue {
  const Transform3D(this.m);
  final List<double> m;
  @override
  Map<String, Object?> toWire() => {'xform3d': m};
}

/// A 4x4 projection, as a flat 16-element matrix.
class Projection extends GodotValue {
  const Projection(this.m);
  final List<double> m;
  @override
  Map<String, Object?> toWire() => {'proj': m};
}

// ---------------------------------------------------------------------------
// Names, ids, and dispatch
// ---------------------------------------------------------------------------

class StringName extends GodotValue {
  const StringName(this.value);
  final String value;
  @override
  Map<String, Object?> toWire() => {'sname': value};
}

class NodePath extends GodotValue {
  const NodePath(this.value);
  final String value;
  @override
  Map<String, Object?> toWire() => {'npath': value};
}

/// A Godot RID (a server-side resource id).
class GRid extends GodotValue {
  const GRid(this.id);
  final int id;
  @override
  Map<String, Object?> toWire() => {'rid': id};
}

/// A signal, as a (source object, name) pair.
class GSignal extends GodotValue {
  const GSignal(this.sourceHandle, this.name);
  final int sourceHandle;
  final String name;
  @override
  Map<String, Object?> toWire() => {
        'sig': [GodotRef(sourceHandle).toWire(), name]
      };
}

/// A Callable bound to a registered Dart closure.
class GCallable extends GodotValue {
  const GCallable(this.callbackId);
  final int callbackId;
  @override
  Map<String, Object?> toWire() => {'callable': callbackId};
}

// ---------------------------------------------------------------------------
// Numeric disambiguation
// ---------------------------------------------------------------------------

/// Force a number to marshal as a Godot `int`.
///
/// Use for enums, indices, flags, counts and font sizes:
/// `node.set('theme_override_font_sizes/font_size', GInt(18))`.
class GInt extends GodotValue {
  const GInt(this.value);
  final int value;
  @override
  Map<String, Object?> toWire() => {'int': value};
  @override
  String toString() => 'GInt($value)';
}

/// Force a number to marshal as a Godot `float`.
///
/// Use where a float is required but the value is whole:
/// `mesh.set('radius', GFloat(1))`.
class GFloat extends GodotValue {
  const GFloat(this.value);
  final num value;
  @override
  Map<String, Object?> toWire() => {'float': value.toDouble()};
  @override
  String toString() => 'GFloat($value)';
}

// ---------------------------------------------------------------------------
// Containers
// ---------------------------------------------------------------------------

/// A Dictionary with arbitrary (non-string) keys, as ordered pairs.
///
/// A plain Dart `Map<String, …>` already marshals to a Godot Dictionary; use
/// this only when the keys are not strings.
class GDict extends GodotValue {
  const GDict(this.entries);
  final List<(Object?, Object?)> entries;
  @override
  Map<String, Object?> toWire() => {
        'dictv': [
          for (final (k, v) in entries) [marshal(k), marshal(v)]
        ]
      };
}

/// A packed array. [tag] is one of
/// `u8` (base64 string) · `i32` · `i64` · `f32` · `f64` · `strs` ·
/// `pv2` · `pv3` · `pv4` · `pcol` (flat number lists).
class Packed extends GodotValue {
  const Packed(this.tag, this.data);

  factory Packed.bytesBase64(String b64) => Packed('u8', b64);
  factory Packed.i32(List<int> v) => Packed('i32', v);
  factory Packed.i64(List<int> v) => Packed('i64', v);
  factory Packed.f32(List<double> v) => Packed('f32', v);
  factory Packed.f64(List<double> v) => Packed('f64', v);
  factory Packed.strings(List<String> v) => Packed('strs', v);
  factory Packed.vector2s(List<double> flatXY) => Packed('pv2', flatXY);
  factory Packed.vector3s(List<double> flatXYZ) => Packed('pv3', flatXYZ);
  factory Packed.vector4s(List<double> flatXYZW) => Packed('pv4', flatXYZW);
  factory Packed.colors(List<double> flatRGBA) => Packed('pcol', flatRGBA);

  final String tag;
  final Object? data;

  @override
  Map<String, Object?> toWire() => {tag: data};
}

// ---------------------------------------------------------------------------
// Marshaling
// ---------------------------------------------------------------------------

/// Marshal a Dart value into its wire form.
///
/// Recurses through lists and maps, so a whole scene description can be handed
/// in as ordinary Dart literals with wrappers only where a specific Variant
/// shape is needed.
Object? marshal(Object? v) {
  if (v == null || v is bool || v is String) return v;
  if (v is int || v is double) return v;
  if (v is GodotValue) return v.toWire();
  if (v is GodotRef) return v.toWire();
  if (v is GodotHandle) return v.ref.toWire();
  if (v is GodotCallbackRef) return v.toWire();
  if (v is List) return [for (final e in v) marshal(e)];
  if (v is Map) {
    // A plain map becomes a Godot Dictionary with string keys.
    return {
      'dict': {
        for (final e in v.entries) '${e.key}': marshal(e.value),
      }
    };
  }
  return v;
}

/// Marshal an argument list (null-safe: absent → `[]`).
List<Object?> marshalArgs(List<Object?>? args) =>
    args == null ? const [] : [for (final a in args) marshal(a)];

/// Unmarshal a wire value back into a Dart value.
///
/// Tagged maps become their wrapper; everything else passes through. Handles
/// come back as [GodotRef] — the controller wraps those into `GodotObject`s so
/// callers get a usable handle rather than a bare id.
Object? unmarshal(Object? v) {
  if (v is List) return [for (final e in v) unmarshal(e)];
  if (v is! Map) return v;

  if (v.containsKey('__dart_error__')) return v; // errors pass through
  if (v.length != 1) return v;

  final key = v.keys.first;
  final data = v[key];
  List<double> nums() =>
      [for (final e in data as List) (e as num).toDouble()];
  List<int> ints() => [for (final e in data as List) (e as num).toInt()];

  switch (key) {
    case 'ref':
      return GodotRef(data as int);
    case 'vec2':
      final n = nums();
      return Vector2(n[0], n[1]);
    case 'vec2i':
      final n = ints();
      return Vector2i(n[0], n[1]);
    case 'vec3':
      final n = nums();
      return Vector3(n[0], n[1], n[2]);
    case 'vec3i':
      final n = ints();
      return Vector3i(n[0], n[1], n[2]);
    case 'vec4':
      final n = nums();
      return Vector4(n[0], n[1], n[2], n[3]);
    case 'vec4i':
      final n = ints();
      return Vector4i(n[0], n[1], n[2], n[3]);
    case 'color':
      final n = nums();
      return GodotColor(n[0], n[1], n[2], n[3]);
    case 'rect2':
      final n = nums();
      return Rect2(n[0], n[1], n[2], n[3]);
    case 'rect2i':
      final n = ints();
      return Rect2i(n[0], n[1], n[2], n[3]);
    case 'plane':
      final n = nums();
      return Plane(n[0], n[1], n[2], n[3]);
    case 'quat':
      final n = nums();
      return Quaternion(n[0], n[1], n[2], n[3]);
    case 'aabb':
      final n = nums();
      return AABB(n[0], n[1], n[2], n[3], n[4], n[5]);
    case 'basis':
      return Basis([
        for (final row in data as List)
          [for (final e in row as List) (e as num).toDouble()]
      ]);
    case 'xform2d':
      return Transform2D(nums());
    case 'xform3d':
      return Transform3D(nums());
    case 'proj':
      return Projection(nums());
    case 'sname':
      return StringName(data as String);
    case 'npath':
      return NodePath(data as String);
    case 'rid':
      return GRid(data as int);
    case 'int':
      return (data as num).toInt();
    case 'float':
      return (data as num).toDouble();
    case 'callable':
      return GCallable(data as int);
    case 'dict':
      return {
        for (final e in (data as Map).entries) e.key: unmarshal(e.value),
      };
    case 'dictv':
      return GDict([
        for (final pair in data as List)
          (unmarshal((pair as List)[0]), unmarshal(pair[1]))
      ]);
    case 'u8':
    case 'i32':
    case 'i64':
    case 'f32':
    case 'f64':
    case 'strs':
    case 'pv2':
    case 'pv3':
    case 'pv4':
    case 'pcol':
      return Packed(key, data);
    default:
      return v;
  }
}
