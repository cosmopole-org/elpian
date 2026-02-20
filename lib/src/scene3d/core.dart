/// Core 3D engine: math, meshes, materials, lights, camera, animation,
/// particles, physics, GLTF, scene graph nodes.
library;

import 'dart:math' as math;
import 'dart:typed_data';

// ════════════════════════════════════════════════════════════════════
//  MATH
// ════════════════════════════════════════════════════════════════════

class Vec2 {
  final double x, y;
  const Vec2(this.x, this.y);
  static const zero = Vec2(0, 0);
  Vec2 operator +(Vec2 o) => Vec2(x + o.x, y + o.y);
  Vec2 operator -(Vec2 o) => Vec2(x - o.x, y - o.y);
  Vec2 operator *(double s) => Vec2(x * s, y * s);
  double dot(Vec2 o) => x * o.x + y * o.y;
  double get length => math.sqrt(x * x + y * y);
}

class Vec3 {
  final double x, y, z;
  const Vec3(this.x, this.y, this.z);
  static const zero = Vec3(0, 0, 0);
  static const one = Vec3(1, 1, 1);
  static const up = Vec3(0, 1, 0);
  static const down = Vec3(0, -1, 0);
  static const forward = Vec3(0, 0, -1);
  static const right = Vec3(1, 0, 0);

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);
  Vec3 operator /(double s) => Vec3(x / s, y / s, z / s);
  Vec3 operator -() => Vec3(-x, -y, -z);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  Vec3 cross(Vec3 o) => Vec3(
        y * o.z - z * o.y,
        z * o.x - x * o.z,
        x * o.y - y * o.x,
      );
  double get length => math.sqrt(x * x + y * y + z * z);
  double get lengthSquared => x * x + y * y + z * z;
  Vec3 get normalized {
    final l = length;
    return l > 1e-7 ? this / l : zero;
  }

  Vec3 lerp(Vec3 o, double t) => this + (o - this) * t;
  Vec3 reflect(Vec3 normal) => this - normal * (2.0 * dot(normal));

  /// Component-wise multiply
  Vec3 scale(Vec3 o) => Vec3(x * o.x, y * o.y, z * o.z);
  Vec3 abs() => Vec3(x.abs(), y.abs(), z.abs());
  double maxComponent() => math.max(x, math.max(y, z));
  double minComponent() => math.min(x, math.min(y, z));

  @override
  String toString() => 'Vec3($x, $y, $z)';
}

class Vec4 {
  final double x, y, z, w;
  const Vec4(this.x, this.y, this.z, this.w);
  Vec3 get xyz => Vec3(x, y, z);
  Vec3 perspectiveDivide() => w.abs() > 1e-7 ? Vec3(x / w, y / w, z / w) : Vec3.zero;
}

class Quaternion {
  final double x, y, z, w;
  const Quaternion(this.x, this.y, this.z, this.w);
  static const identity = Quaternion(0, 0, 0, 1);

  static Quaternion fromAxisAngle(Vec3 axis, double angle) {
    final ha = angle / 2;
    final s = math.sin(ha);
    final a = axis.normalized;
    return Quaternion(a.x * s, a.y * s, a.z * s, math.cos(ha));
  }

  static Quaternion fromEuler(double rx, double ry, double rz) {
    final cx = math.cos(rx / 2), sx = math.sin(rx / 2);
    final cy = math.cos(ry / 2), sy = math.sin(ry / 2);
    final cz = math.cos(rz / 2), sz = math.sin(rz / 2);
    return Quaternion(
      sx * cy * cz - cx * sy * sz,
      cx * sy * cz + sx * cy * sz,
      cx * cy * sz - sx * sy * cz,
      cx * cy * cz + sx * sy * sz,
    );
  }

  Quaternion operator *(Quaternion o) => Quaternion(
        w * o.x + x * o.w + y * o.z - z * o.y,
        w * o.y - x * o.z + y * o.w + z * o.x,
        w * o.z + x * o.y - y * o.x + z * o.w,
        w * o.w - x * o.x - y * o.y - z * o.z,
      );

  Vec3 rotate(Vec3 v) {
    final u = Vec3(x, y, z);
    final s = w;
    return u * (2.0 * u.dot(v)) + v * (s * s - u.dot(u)) + u.cross(v) * (2.0 * s);
  }

  Quaternion get normalized {
    final l = math.sqrt(x * x + y * y + z * z + w * w);
    return l > 1e-7 ? Quaternion(x / l, y / l, z / l, w / l) : identity;
  }

  static Quaternion slerp(Quaternion a, Quaternion b, double t) {
    var dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
    var bx = b.x, by = b.y, bz = b.z, bw = b.w;
    if (dot < 0) {
      dot = -dot;
      bx = -bx; by = -by; bz = -bz; bw = -bw;
    }
    if (dot > 0.9995) {
      return Quaternion(
        a.x + t * (bx - a.x), a.y + t * (by - a.y),
        a.z + t * (bz - a.z), a.w + t * (bw - a.w),
      ).normalized;
    }
    final theta = math.acos(dot.clamp(-1.0, 1.0));
    final sinT = math.sin(theta);
    final s0 = math.sin((1 - t) * theta) / sinT;
    final s1 = math.sin(t * theta) / sinT;
    return Quaternion(
      s0 * a.x + s1 * bx, s0 * a.y + s1 * by,
      s0 * a.z + s1 * bz, s0 * a.w + s1 * bw,
    );
  }

  Mat4 toMat4() {
    final xx = x * x, yy = y * y, zz = z * z;
    final xy = x * y, xz = x * z, yz = y * z;
    final wx = w * x, wy = w * y, wz = w * z;
    return Mat4.fromRows(
      Vec3(1 - 2 * (yy + zz), 2 * (xy - wz), 2 * (xz + wy)),
      Vec3(2 * (xy + wz), 1 - 2 * (xx + zz), 2 * (yz - wx)),
      Vec3(2 * (xz - wy), 2 * (yz + wx), 1 - 2 * (xx + yy)),
    );
  }
}

class Mat4 {
  final Float64List m; // column-major 4×4
  Mat4._(this.m);

  factory Mat4.identity() {
    final m = Float64List(16);
    m[0] = m[5] = m[10] = m[15] = 1.0;
    return Mat4._(m);
  }

  factory Mat4.translation(Vec3 v) {
    final m = Float64List(16);
    m[0] = m[5] = m[10] = m[15] = 1.0;
    m[12] = v.x; m[13] = v.y; m[14] = v.z;
    return Mat4._(m);
  }

  factory Mat4.scale(Vec3 v) {
    final m = Float64List(16);
    m[0] = v.x; m[5] = v.y; m[10] = v.z; m[15] = 1.0;
    return Mat4._(m);
  }

  factory Mat4.rotationX(double r) {
    final c = math.cos(r), s = math.sin(r);
    final m = Float64List(16);
    m[0] = m[15] = 1.0;
    m[5] = c; m[6] = s; m[9] = -s; m[10] = c;
    return Mat4._(m);
  }

  factory Mat4.rotationY(double r) {
    final c = math.cos(r), s = math.sin(r);
    final m = Float64List(16);
    m[5] = m[15] = 1.0;
    m[0] = c; m[2] = -s; m[8] = s; m[10] = c;
    return Mat4._(m);
  }

  factory Mat4.rotationZ(double r) {
    final c = math.cos(r), s = math.sin(r);
    final m = Float64List(16);
    m[10] = m[15] = 1.0;
    m[0] = c; m[1] = s; m[4] = -s; m[5] = c;
    return Mat4._(m);
  }

  factory Mat4.fromAxisAngle(Vec3 axis, double angle) {
    return Quaternion.fromAxisAngle(axis, angle).toMat4();
  }

  factory Mat4.fromRows(Vec3 r0, Vec3 r1, Vec3 r2) {
    final m = Float64List(16);
    m[0] = r0.x; m[4] = r0.y; m[8] = r0.z;
    m[1] = r1.x; m[5] = r1.y; m[9] = r1.z;
    m[2] = r2.x; m[6] = r2.y; m[10] = r2.z;
    m[15] = 1.0;
    return Mat4._(m);
  }

  factory Mat4.perspective(double fovRad, double aspect, double near, double far) {
    final f = 1.0 / math.tan(fovRad / 2.0);
    final nf = 1.0 / (near - far);
    final m = Float64List(16);
    m[0] = f / aspect;
    m[5] = f;
    m[10] = (far + near) * nf;
    m[11] = -1.0;
    m[14] = 2.0 * far * near * nf;
    return Mat4._(m);
  }

  factory Mat4.orthographic(double l, double r, double b, double t, double n, double f) {
    final m = Float64List(16);
    m[0] = 2 / (r - l); m[5] = 2 / (t - b); m[10] = -2 / (f - n);
    m[12] = -(r + l) / (r - l);
    m[13] = -(t + b) / (t - b);
    m[14] = -(f + n) / (f - n);
    m[15] = 1.0;
    return Mat4._(m);
  }

  factory Mat4.lookAt(Vec3 eye, Vec3 target, Vec3 up) {
    final f = (target - eye).normalized;
    final s = f.cross(up).normalized;
    final u = s.cross(f);
    final m = Float64List(16);
    m[0] = s.x; m[4] = s.y; m[8] = s.z;
    m[1] = u.x; m[5] = u.y; m[9] = u.z;
    m[2] = -f.x; m[6] = -f.y; m[10] = -f.z;
    m[12] = -s.dot(eye);
    m[13] = -u.dot(eye);
    m[14] = f.dot(eye);
    m[15] = 1.0;
    return Mat4._(m);
  }

  factory Mat4.fromEulerXYZ(double rx, double ry, double rz) {
    return Mat4.rotationZ(rz) * Mat4.rotationY(ry) * Mat4.rotationX(rx);
  }

  factory Mat4.compose(Vec3 pos, Vec3 rotDeg, Vec3 scl) {
    final t = Mat4.translation(pos);
    final r = Mat4.fromEulerXYZ(
      rotDeg.x * math.pi / 180, rotDeg.y * math.pi / 180, rotDeg.z * math.pi / 180,
    );
    final s = Mat4.scale(scl);
    return t * r * s;
  }

  Mat4 operator *(Mat4 o) {
    final r = Float64List(16);
    for (var col = 0; col < 4; col++) {
      for (var row = 0; row < 4; row++) {
        var sum = 0.0;
        for (var k = 0; k < 4; k++) {
          sum += m[k * 4 + row] * o.m[col * 4 + k];
        }
        r[col * 4 + row] = sum;
      }
    }
    return Mat4._(r);
  }

  Vec3 transformPoint(Vec3 v) {
    final w = m[3] * v.x + m[7] * v.y + m[11] * v.z + m[15];
    final iw = w.abs() > 1e-7 ? 1.0 / w : 1.0;
    return Vec3(
      (m[0] * v.x + m[4] * v.y + m[8] * v.z + m[12]) * iw,
      (m[1] * v.x + m[5] * v.y + m[9] * v.z + m[13]) * iw,
      (m[2] * v.x + m[6] * v.y + m[10] * v.z + m[14]) * iw,
    );
  }

  Vec3 transformDir(Vec3 v) => Vec3(
        m[0] * v.x + m[4] * v.y + m[8] * v.z,
        m[1] * v.x + m[5] * v.y + m[9] * v.z,
        m[2] * v.x + m[6] * v.y + m[10] * v.z,
      );

  Vec4 transformVec4(Vec3 v) => Vec4(
        m[0] * v.x + m[4] * v.y + m[8] * v.z + m[12],
        m[1] * v.x + m[5] * v.y + m[9] * v.z + m[13],
        m[2] * v.x + m[6] * v.y + m[10] * v.z + m[14],
        m[3] * v.x + m[7] * v.y + m[11] * v.z + m[15],
      );
}

class AABB {
  final Vec3 min, max;
  const AABB(this.min, this.max);
  Vec3 get center => (min + max) * 0.5;
  Vec3 get size => max - min;
  bool containsPoint(Vec3 p) =>
      p.x >= min.x && p.x <= max.x &&
      p.y >= min.y && p.y <= max.y &&
      p.z >= min.z && p.z <= max.z;
  bool intersects(AABB o) =>
      min.x <= o.max.x && max.x >= o.min.x &&
      min.y <= o.max.y && max.y >= o.min.y &&
      min.z <= o.max.z && max.z >= o.min.z;
}

class Ray {
  final Vec3 origin, direction;
  const Ray(this.origin, this.direction);
  Vec3 at(double t) => origin + direction * t;

  double? intersectSphere(Vec3 center, double radius) {
    final oc = origin - center;
    final a = direction.dot(direction);
    final b = 2.0 * oc.dot(direction);
    final c = oc.dot(oc) - radius * radius;
    final d = b * b - 4 * a * c;
    if (d < 0) return null;
    return (-b - math.sqrt(d)) / (2 * a);
  }

  double? intersectPlane(Vec3 normal, double d) {
    final denom = normal.dot(direction);
    if (denom.abs() < 1e-7) return null;
    return -(normal.dot(origin) + d) / denom;
  }
}

// ════════════════════════════════════════════════════════════════════
//  VERTEX & TRIANGLE
// ════════════════════════════════════════════════════════════════════

class Vertex {
  final Vec3 position;
  final Vec3 normal;
  final Vec2 uv;
  final Vec3? tangent;
  final List<int>? boneIndices;
  final List<double>? boneWeights;

  const Vertex({
    required this.position,
    required this.normal,
    this.uv = Vec2.zero,
    this.tangent,
    this.boneIndices,
    this.boneWeights,
  });
}

class Triangle {
  final Vertex v0, v1, v2;
  const Triangle(this.v0, this.v1, this.v2);

  Vec3 get faceNormal => (v1.position - v0.position).cross(v2.position - v0.position).normalized;
  Vec3 get center => (v0.position + v1.position + v2.position) / 3.0;
}

class Mesh {
  final List<Triangle> triangles;
  final AABB bounds;
  const Mesh(this.triangles, this.bounds);
}

// ════════════════════════════════════════════════════════════════════
//  MESH GENERATORS
// ════════════════════════════════════════════════════════════════════

class MeshGen {
  static Mesh cube({double size = 1.0}) {
    final h = size / 2;
    final faces = <List<Vec3>>[
      [Vec3(-h,-h,h), Vec3(h,-h,h), Vec3(h,h,h), Vec3(-h,h,h)],     // front
      [Vec3(h,-h,-h), Vec3(-h,-h,-h), Vec3(-h,h,-h), Vec3(h,h,-h)],  // back
      [Vec3(-h,h,-h), Vec3(-h,h,h), Vec3(h,h,h), Vec3(h,h,-h)],      // top
      [Vec3(-h,-h,h), Vec3(-h,-h,-h), Vec3(h,-h,-h), Vec3(h,-h,h)],  // bottom
      [Vec3(h,-h,h), Vec3(h,-h,-h), Vec3(h,h,-h), Vec3(h,h,h)],      // right
      [Vec3(-h,-h,-h), Vec3(-h,-h,h), Vec3(-h,h,h), Vec3(-h,h,-h)],  // left
    ];
    final normals = [const Vec3(0,0,1), const Vec3(0,0,-1), const Vec3(0,1,0), const Vec3(0,-1,0), const Vec3(1,0,0), const Vec3(-1,0,0)];
    final uvs = [const Vec2(0,1), const Vec2(1,1), const Vec2(1,0), const Vec2(0,0)];
    final tris = <Triangle>[];
    for (var f = 0; f < 6; f++) {
      final v = faces[f]; final n = normals[f];
      tris.add(Triangle(
        Vertex(position: v[0], normal: n, uv: uvs[0]),
        Vertex(position: v[1], normal: n, uv: uvs[1]),
        Vertex(position: v[2], normal: n, uv: uvs[2]),
      ));
      tris.add(Triangle(
        Vertex(position: v[0], normal: n, uv: uvs[0]),
        Vertex(position: v[2], normal: n, uv: uvs[2]),
        Vertex(position: v[3], normal: n, uv: uvs[3]),
      ));
    }
    return Mesh(tris, AABB(Vec3(-h,-h,-h), Vec3(h,h,h)));
  }

  static Mesh sphere({double radius = 1.0, int segments = 16}) {
    final tris = <Triangle>[];
    for (var i = 0; i < segments; i++) {
      final t1 = math.pi * i / segments;
      final t2 = math.pi * (i + 1) / segments;
      for (var j = 0; j < segments; j++) {
        final p1 = 2 * math.pi * j / segments;
        final p2 = 2 * math.pi * (j + 1) / segments;
        final v0 = _sphPt(radius, t1, p1), v1 = _sphPt(radius, t2, p1);
        final v2 = _sphPt(radius, t2, p2), v3 = _sphPt(radius, t1, p2);
        final n0 = v0.normalized, n1 = v1.normalized, n2 = v2.normalized, n3 = v3.normalized;
        final u0 = Vec2(j / segments, i / segments);
        final u1 = Vec2(j / segments, (i + 1) / segments);
        final u2 = Vec2((j + 1) / segments, (i + 1) / segments);
        final u3 = Vec2((j + 1) / segments, i / segments);
        if (i != 0) {
          tris.add(Triangle(
            Vertex(position: v0, normal: n0, uv: u0),
            Vertex(position: v1, normal: n1, uv: u1),
            Vertex(position: v2, normal: n2, uv: u2),
          ));
        }
        if (i != segments - 1) {
          tris.add(Triangle(
            Vertex(position: v0, normal: n0, uv: u0),
            Vertex(position: v2, normal: n2, uv: u2),
            Vertex(position: v3, normal: n3, uv: u3),
          ));
        }
      }
    }
    return Mesh(tris, AABB(Vec3(-radius,-radius,-radius), Vec3(radius,radius,radius)));
  }

  static Vec3 _sphPt(double r, double t, double p) =>
      Vec3(r * math.sin(t) * math.cos(p), r * math.cos(t), r * math.sin(t) * math.sin(p));

  static Mesh plane({double size = 1.0, int subdivisions = 1}) {
    final tris = <Triangle>[];
    final h = size / 2;
    final step = size / subdivisions;
    for (var i = 0; i < subdivisions; i++) {
      for (var j = 0; j < subdivisions; j++) {
        final x0 = -h + j * step, z0 = -h + i * step;
        final x1 = x0 + step, z1 = z0 + step;
        final u0 = Vec2(j / subdivisions, i / subdivisions);
        final u1 = Vec2((j + 1) / subdivisions, i / subdivisions);
        final u2 = Vec2((j + 1) / subdivisions, (i + 1) / subdivisions);
        final u3 = Vec2(j / subdivisions, (i + 1) / subdivisions);
        tris.add(Triangle(
          Vertex(position: Vec3(x0, 0, z0), normal: Vec3.up, uv: u0),
          Vertex(position: Vec3(x1, 0, z0), normal: Vec3.up, uv: u1),
          Vertex(position: Vec3(x1, 0, z1), normal: Vec3.up, uv: u2),
        ));
        tris.add(Triangle(
          Vertex(position: Vec3(x0, 0, z0), normal: Vec3.up, uv: u0),
          Vertex(position: Vec3(x1, 0, z1), normal: Vec3.up, uv: u2),
          Vertex(position: Vec3(x0, 0, z1), normal: Vec3.up, uv: u3),
        ));
      }
    }
    return Mesh(tris, AABB(Vec3(-h, 0, -h), Vec3(h, 0, h)));
  }

  static Mesh cylinder({double radius = 0.5, double height = 1.0, int segments = 16}) {
    final tris = <Triangle>[];
    final hh = height / 2;
    for (var i = 0; i < segments; i++) {
      final a1 = 2 * math.pi * i / segments, a2 = 2 * math.pi * (i + 1) / segments;
      final c1 = math.cos(a1), s1 = math.sin(a1);
      final c2 = math.cos(a2), s2 = math.sin(a2);
      final x1 = radius * c1, z1 = radius * s1, x2 = radius * c2, z2 = radius * s2;
      final n = Vec3((c1 + c2) / 2, 0, (s1 + s2) / 2).normalized;
      // Side
      tris.add(Triangle(
        Vertex(position: Vec3(x1, -hh, z1), normal: n, uv: Vec2(i / segments, 0)),
        Vertex(position: Vec3(x2, -hh, z2), normal: n, uv: Vec2((i + 1) / segments, 0)),
        Vertex(position: Vec3(x2, hh, z2), normal: n, uv: Vec2((i + 1) / segments, 1)),
      ));
      tris.add(Triangle(
        Vertex(position: Vec3(x1, -hh, z1), normal: n, uv: Vec2(i / segments, 0)),
        Vertex(position: Vec3(x2, hh, z2), normal: n, uv: Vec2((i + 1) / segments, 1)),
        Vertex(position: Vec3(x1, hh, z1), normal: n, uv: Vec2(i / segments, 1)),
      ));
      // Top cap
      tris.add(Triangle(
        Vertex(position: Vec3(0, hh, 0), normal: Vec3.up),
        Vertex(position: Vec3(x1, hh, z1), normal: Vec3.up),
        Vertex(position: Vec3(x2, hh, z2), normal: Vec3.up),
      ));
      // Bottom cap
      tris.add(Triangle(
        Vertex(position: Vec3(0, -hh, 0), normal: Vec3.down),
        Vertex(position: Vec3(x2, -hh, z2), normal: Vec3.down),
        Vertex(position: Vec3(x1, -hh, z1), normal: Vec3.down),
      ));
    }
    return Mesh(tris, AABB(Vec3(-radius, -hh, -radius), Vec3(radius, hh, radius)));
  }

  static Mesh cone({double radius = 0.5, double height = 1.0, int segments = 16}) {
    final tris = <Triangle>[];
    final apex = Vec3(0, height, 0);
    for (var i = 0; i < segments; i++) {
      final a1 = 2 * math.pi * i / segments, a2 = 2 * math.pi * (i + 1) / segments;
      final x1 = radius * math.cos(a1), z1 = radius * math.sin(a1);
      final x2 = radius * math.cos(a2), z2 = radius * math.sin(a2);
      final sn = Vec3((x1 + x2) / 2, radius / height, (z1 + z2) / 2).normalized;
      tris.add(Triangle(
        Vertex(position: Vec3(x1, 0, z1), normal: sn),
        Vertex(position: Vec3(x2, 0, z2), normal: sn),
        Vertex(position: apex, normal: sn),
      ));
      tris.add(Triangle(
        const Vertex(position: Vec3(0, 0, 0), normal: Vec3.down),
        Vertex(position: Vec3(x2, 0, z2), normal: Vec3.down),
        Vertex(position: Vec3(x1, 0, z1), normal: Vec3.down),
      ));
    }
    return Mesh(tris, AABB(Vec3(-radius, 0, -radius), Vec3(radius, height, radius)));
  }

  static Mesh torus({double radius = 1.0, double tubeRadius = 0.25, int radial = 24, int tubular = 12}) {
    final tris = <Triangle>[];
    for (var i = 0; i < radial; i++) {
      final t1 = 2 * math.pi * i / radial, t2 = 2 * math.pi * (i + 1) / radial;
      for (var j = 0; j < tubular; j++) {
        final p1 = 2 * math.pi * j / tubular, p2 = 2 * math.pi * (j + 1) / tubular;
        final v00 = _torPt(radius, tubeRadius, t1, p1);
        final v10 = _torPt(radius, tubeRadius, t2, p1);
        final v11 = _torPt(radius, tubeRadius, t2, p2);
        final v01 = _torPt(radius, tubeRadius, t1, p2);
        final c00 = Vec3(radius * math.cos(t1), 0, radius * math.sin(t1));
        final c10 = Vec3(radius * math.cos(t2), 0, radius * math.sin(t2));
        final n00 = (v00 - c00).normalized, n10 = (v10 - c10).normalized;
        final n11 = (v11 - c10).normalized, n01 = (v01 - c00).normalized;
        tris.add(Triangle(
          Vertex(position: v00, normal: n00, uv: Vec2(i / radial, j / tubular)),
          Vertex(position: v10, normal: n10, uv: Vec2((i + 1) / radial, j / tubular)),
          Vertex(position: v11, normal: n11, uv: Vec2((i + 1) / radial, (j + 1) / tubular)),
        ));
        tris.add(Triangle(
          Vertex(position: v00, normal: n00, uv: Vec2(i / radial, j / tubular)),
          Vertex(position: v11, normal: n11, uv: Vec2((i + 1) / radial, (j + 1) / tubular)),
          Vertex(position: v01, normal: n01, uv: Vec2(i / radial, (j + 1) / tubular)),
        ));
      }
    }
    final e = radius + tubeRadius;
    return Mesh(tris, AABB(Vec3(-e, -tubeRadius, -e), Vec3(e, tubeRadius, e)));
  }

  static Vec3 _torPt(double r, double tr, double t, double p) {
    final rr = r + tr * math.cos(p);
    return Vec3(rr * math.cos(t), tr * math.sin(p), rr * math.sin(t));
  }

  static Mesh capsule({double radius = 0.5, double height = 2.0, int segments = 16}) {
    final tris = <Triangle>[];
    final halfH = (height - 2 * radius).clamp(0, double.infinity) / 2;
    final halfSeg = segments ~/ 2;
    // Top hemisphere
    for (var i = 0; i < halfSeg; i++) {
      final t1 = math.pi * i / segments, t2 = math.pi * (i + 1) / segments;
      for (var j = 0; j < segments; j++) {
        final p1 = 2 * math.pi * j / segments, p2 = 2 * math.pi * (j + 1) / segments;
        final off = Vec3(0, halfH, 0);
        final v0 = _sphPt(radius, t1, p1) + off, v1 = _sphPt(radius, t2, p1) + off;
        final v2 = _sphPt(radius, t2, p2) + off, v3 = _sphPt(radius, t1, p2) + off;
        if (i != 0) {
          tris.add(Triangle(
            Vertex(position: v0, normal: (v0 - off).normalized),
            Vertex(position: v1, normal: (v1 - off).normalized),
            Vertex(position: v2, normal: (v2 - off).normalized),
          ));
        }
        tris.add(Triangle(
          Vertex(position: v0, normal: (v0 - off).normalized),
          Vertex(position: v2, normal: (v2 - off).normalized),
          Vertex(position: v3, normal: (v3 - off).normalized),
        ));
      }
    }
    // Bottom hemisphere
    for (var i = halfSeg; i < segments; i++) {
      final t1 = math.pi * i / segments, t2 = math.pi * (i + 1) / segments;
      for (var j = 0; j < segments; j++) {
        final p1 = 2 * math.pi * j / segments, p2 = 2 * math.pi * (j + 1) / segments;
        final off = Vec3(0, -halfH, 0);
        final v0 = _sphPt(radius, t1, p1) + off, v1 = _sphPt(radius, t2, p1) + off;
        final v2 = _sphPt(radius, t2, p2) + off, v3 = _sphPt(radius, t1, p2) + off;
        tris.add(Triangle(
          Vertex(position: v0, normal: (v0 - off).normalized),
          Vertex(position: v1, normal: (v1 - off).normalized),
          Vertex(position: v2, normal: (v2 - off).normalized),
        ));
        if (i != segments - 1) {
          tris.add(Triangle(
            Vertex(position: v0, normal: (v0 - off).normalized),
            Vertex(position: v2, normal: (v2 - off).normalized),
            Vertex(position: v3, normal: (v3 - off).normalized),
          ));
        }
      }
    }
    // Cylinder body between hemispheres
    for (var i = 0; i < segments; i++) {
      final a1 = 2 * math.pi * i / segments, a2 = 2 * math.pi * (i + 1) / segments;
      final c1 = math.cos(a1), s1a = math.sin(a1);
      final c2 = math.cos(a2), s2a = math.sin(a2);
      final n = Vec3((c1 + c2) / 2, 0, (s1a + s2a) / 2).normalized;
      final b = Vec3(radius * c1, -halfH, radius * s1a);
      final b2 = Vec3(radius * c2, -halfH, radius * s2a);
      final t = Vec3(radius * c1, halfH, radius * s1a);
      final t2 = Vec3(radius * c2, halfH, radius * s2a);
      tris.add(Triangle(Vertex(position: b, normal: n), Vertex(position: b2, normal: n), Vertex(position: t2, normal: n)));
      tris.add(Triangle(Vertex(position: b, normal: n), Vertex(position: t2, normal: n), Vertex(position: t, normal: n)));
    }
    final th = halfH + radius;
    return Mesh(tris, AABB(Vec3(-radius, -th, -radius), Vec3(radius, th, radius)));
  }

  static Mesh pyramid({double base = 1.0, double height = 1.0}) {
    final h = base / 2;
    final apex = Vec3(0, height, 0);
    final v0 = Vec3(-h, 0, -h), v1 = Vec3(h, 0, -h), v2 = Vec3(h, 0, h), v3 = Vec3(-h, 0, h);
    final tris = <Triangle>[];
    void face(Vec3 a, Vec3 b, Vec3 c) {
      final n = (b - a).cross(c - a).normalized;
      tris.add(Triangle(Vertex(position: a, normal: n), Vertex(position: b, normal: n), Vertex(position: c, normal: n)));
    }
    face(v0, v1, apex); face(v1, v2, apex); face(v2, v3, apex); face(v3, v0, apex);
    // Bottom
    tris.add(Triangle(Vertex(position: v0, normal: Vec3.down), Vertex(position: v3, normal: Vec3.down), Vertex(position: v2, normal: Vec3.down)));
    tris.add(Triangle(Vertex(position: v0, normal: Vec3.down), Vertex(position: v2, normal: Vec3.down), Vertex(position: v1, normal: Vec3.down)));
    return Mesh(tris, AABB(Vec3(-h, 0, -h), Vec3(h, height, h)));
  }

  static Mesh wedge({double width = 1.0, double height = 1.0, double depth = 1.0}) {
    final hw = width / 2, hd = depth / 2;
    final v = [Vec3(-hw,0,-hd), Vec3(hw,0,-hd), Vec3(hw,0,hd), Vec3(-hw,0,hd),
               Vec3(-hw,height,-hd), Vec3(hw,height,-hd)];
    final tris = <Triangle>[];
    void quad(Vec3 a, Vec3 b, Vec3 c, Vec3 d) {
      final n = (b - a).cross(c - a).normalized;
      tris.add(Triangle(Vertex(position: a, normal: n), Vertex(position: b, normal: n), Vertex(position: c, normal: n)));
      tris.add(Triangle(Vertex(position: a, normal: n), Vertex(position: c, normal: n), Vertex(position: d, normal: n)));
    }
    void tri(Vec3 a, Vec3 b, Vec3 c) {
      final n = (b - a).cross(c - a).normalized;
      tris.add(Triangle(Vertex(position: a, normal: n), Vertex(position: b, normal: n), Vertex(position: c, normal: n)));
    }
    quad(v[0], v[1], v[2], v[3]); // bottom
    quad(v[0], v[4], v[5], v[1]); // back
    tri(v[0], v[3], v[4]); // left
    tri(v[1], v[5], v[2]); // right
    quad(v[3], v[2], v[5], v[4]); // slope
    return Mesh(tris, AABB(Vec3(-hw, 0, -hd), Vec3(hw, height, hd)));
  }

  static Mesh icosphere({double radius = 1.0, int subdivisions = 2}) {
    final t = (1.0 + math.sqrt(5.0)) / 2.0;
    var verts = <Vec3>[
      Vec3(-1, t, 0), Vec3(1, t, 0), Vec3(-1, -t, 0), Vec3(1, -t, 0),
      Vec3(0, -1, t), Vec3(0, 1, t), Vec3(0, -1, -t), Vec3(0, 1, -t),
      Vec3(t, 0, -1), Vec3(t, 0, 1), Vec3(-t, 0, -1), Vec3(-t, 0, 1),
    ].map((v) => v.normalized * radius).toList();
    var faces = <List<int>>[
      [0,11,5],[0,5,1],[0,1,7],[0,7,10],[0,10,11],
      [1,5,9],[5,11,4],[11,10,2],[10,7,6],[7,1,8],
      [3,9,4],[3,4,2],[3,2,6],[3,6,8],[3,8,9],
      [4,9,5],[2,4,11],[6,2,10],[8,6,7],[9,8,1],
    ];
    final midCache = <String, int>{};
    int getMid(int a, int b) {
      final key = a < b ? '$a-$b' : '$b-$a';
      return midCache.putIfAbsent(key, () {
        verts.add((verts[a] + verts[b]).normalized * radius);
        return verts.length - 1;
      });
    }
    for (var s = 0; s < subdivisions; s++) {
      final newFaces = <List<int>>[];
      for (final f in faces) {
        final a = getMid(f[0], f[1]), b = getMid(f[1], f[2]), c = getMid(f[2], f[0]);
        newFaces.addAll([[f[0],a,c],[f[1],b,a],[f[2],c,b],[a,b,c]]);
      }
      faces = newFaces;
    }
    final tris = faces.map((f) {
      final p0 = verts[f[0]], p1 = verts[f[1]], p2 = verts[f[2]];
      return Triangle(
        Vertex(position: p0, normal: p0.normalized),
        Vertex(position: p1, normal: p1.normalized),
        Vertex(position: p2, normal: p2.normalized),
      );
    }).toList();
    return Mesh(tris, AABB(Vec3(-radius,-radius,-radius), Vec3(radius,radius,radius)));
  }

  static Mesh heightmap({required int width, required int height, required List<double> heights,
      double scaleX = 1.0, double scaleY = 1.0, double scaleZ = 1.0}) {
    final tris = <Triangle>[];
    for (var z = 0; z < height - 1; z++) {
      for (var x = 0; x < width - 1; x++) {
        final h00 = heights[z * width + x] * scaleY;
        final h10 = heights[z * width + x + 1] * scaleY;
        final h01 = heights[(z + 1) * width + x] * scaleY;
        final h11 = heights[(z + 1) * width + x + 1] * scaleY;
        final v00 = Vec3(x * scaleX, h00, z * scaleZ);
        final v10 = Vec3((x + 1) * scaleX, h10, z * scaleZ);
        final v01 = Vec3(x * scaleX, h01, (z + 1) * scaleZ);
        final v11 = Vec3((x + 1) * scaleX, h11, (z + 1) * scaleZ);
        final n1 = (v10 - v00).cross(v01 - v00).normalized;
        final n2 = (v01 - v11).cross(v10 - v11).normalized;
        tris.add(Triangle(Vertex(position: v00, normal: n1), Vertex(position: v10, normal: n1), Vertex(position: v01, normal: n1)));
        tris.add(Triangle(Vertex(position: v10, normal: n2), Vertex(position: v11, normal: n2), Vertex(position: v01, normal: n2)));
      }
    }
    return Mesh(tris, AABB(Vec3.zero, Vec3((width - 1) * scaleX, scaleY, (height - 1) * scaleZ)));
  }

  /// Simple text billboard (generates quads per character)
  static Mesh billboard({double width = 1.0, double height = 1.0}) {
    final hw = width / 2, hh = height / 2;
    return Mesh([
      Triangle(
        Vertex(position: Vec3(-hw, -hh, 0), normal: const Vec3(0, 0, 1), uv: const Vec2(0, 1)),
        Vertex(position: Vec3(hw, -hh, 0), normal: const Vec3(0, 0, 1), uv: const Vec2(1, 1)),
        Vertex(position: Vec3(hw, hh, 0), normal: const Vec3(0, 0, 1), uv: const Vec2(1, 0)),
      ),
      Triangle(
        Vertex(position: Vec3(-hw, -hh, 0), normal: const Vec3(0, 0, 1), uv: const Vec2(0, 1)),
        Vertex(position: Vec3(hw, hh, 0), normal: const Vec3(0, 0, 1), uv: const Vec2(1, 0)),
        Vertex(position: Vec3(-hw, hh, 0), normal: const Vec3(0, 0, 1), uv: const Vec2(0, 0)),
      ),
    ], AABB(Vec3(-hw, -hh, 0), Vec3(hw, hh, 0)));
  }
}

// ════════════════════════════════════════════════════════════════════
//  MATERIAL
// ════════════════════════════════════════════════════════════════════

enum AlphaMode { opaque, blend, cutoff }
enum TextureType { none, checkerboard, gradient, noise, stripes }

class Material3D {
  final Vec3 baseColor;
  final double metallic;
  final double roughness;
  final Vec3 emissive;
  final double emissiveStrength;
  final double alpha;
  final AlphaMode alphaMode;
  final double alphaCutoff;
  final bool doubleSided;
  final bool wireframe;
  final bool unlit;
  final TextureType texture;
  final Vec3 textureColor2;
  final double textureScale;

  const Material3D({
    this.baseColor = const Vec3(0.8, 0.8, 0.8),
    this.metallic = 0.0,
    this.roughness = 0.5,
    this.emissive = Vec3.zero,
    this.emissiveStrength = 1.0,
    this.alpha = 1.0,
    this.alphaMode = AlphaMode.opaque,
    this.alphaCutoff = 0.5,
    this.doubleSided = false,
    this.wireframe = false,
    this.unlit = false,
    this.texture = TextureType.none,
    this.textureColor2 = const Vec3(0.3, 0.3, 0.3),
    this.textureScale = 1.0,
  });

  Vec3 sampleTexture(Vec2 uv) {
    switch (texture) {
      case TextureType.checkerboard:
        final u = (uv.x * textureScale).floor(), v = (uv.y * textureScale).floor();
        return (u + v) % 2 == 0 ? baseColor : textureColor2;
      case TextureType.stripes:
        final s = (uv.x * textureScale * 10).floor() % 2 == 0;
        return s ? baseColor : textureColor2;
      case TextureType.gradient:
        return baseColor.lerp(textureColor2, uv.y);
      case TextureType.noise:
        final n = _simpleNoise(uv.x * textureScale, uv.y * textureScale);
        return baseColor * (0.5 + 0.5 * n);
      default:
        return baseColor;
    }
  }

  static double _simpleNoise(double x, double y) {
    final n = math.sin(x * 12.9898 + y * 78.233) * 43758.5453;
    return n - n.floor();
  }
}

// ════════════════════════════════════════════════════════════════════
//  LIGHTS
// ════════════════════════════════════════════════════════════════════

enum LightType { directional, point, spot, area }

class Light3D {
  final LightType type;
  final Vec3 color;
  final double intensity;
  final Vec3 position;
  final Vec3 direction;
  final double range;
  final double innerConeAngle;
  final double outerConeAngle;
  final bool castShadow;

  const Light3D({
    this.type = LightType.directional,
    this.color = Vec3.one,
    this.intensity = 1.0,
    this.position = Vec3.zero,
    this.direction = const Vec3(0, -1, 0),
    this.range = 50.0,
    this.innerConeAngle = 30.0,
    this.outerConeAngle = 45.0,
    this.castShadow = false,
  });
}

// ════════════════════════════════════════════════════════════════════
//  CAMERA
// ════════════════════════════════════════════════════════════════════

enum CameraType { perspective, orthographic }
enum CameraMode { fixed, orbit, firstPerson, follow, flythrough }

class Camera3D {
  CameraType type;
  Vec3 position;
  Vec3 target;
  Vec3 up;
  double fov;
  double near;
  double far;
  double orthoSize;
  CameraMode mode;
  double orbitSpeed;
  double orbitRadius;
  Vec3? followTarget;
  Vec3 followOffset;
  double shakeAmount;
  double shakeDecay;

  Camera3D({
    this.type = CameraType.perspective,
    this.position = const Vec3(0, 5, 10),
    this.target = Vec3.zero,
    this.up = Vec3.up,
    this.fov = 60.0,
    this.near = 0.1,
    this.far = 1000.0,
    this.orthoSize = 10.0,
    this.mode = CameraMode.fixed,
    this.orbitSpeed = 10.0,
    this.orbitRadius = 10.0,
    this.followTarget,
    this.followOffset = const Vec3(0, 5, 10),
    this.shakeAmount = 0.0,
    this.shakeDecay = 5.0,
  });

  Mat4 viewMatrix() {
    var eye = position;
    if (shakeAmount > 0) {
      final r = math.Random();
      eye = eye + Vec3(
        (r.nextDouble() - 0.5) * shakeAmount,
        (r.nextDouble() - 0.5) * shakeAmount,
        (r.nextDouble() - 0.5) * shakeAmount,
      );
    }
    return Mat4.lookAt(eye, target, up);
  }

  Mat4 projectionMatrix(double aspect) {
    if (type == CameraType.orthographic) {
      final h = orthoSize / 2, w = h * aspect;
      return Mat4.orthographic(-w, w, -h, h, near, far);
    }
    return Mat4.perspective(fov * math.pi / 180.0, aspect, near, far);
  }

  void update(double dt, double elapsed) {
    if (shakeAmount > 0) shakeAmount *= math.exp(-shakeDecay * dt);
    if (mode == CameraMode.orbit) {
      final angle = elapsed * orbitSpeed * math.pi / 180;
      position = Vec3(
        target.x + orbitRadius * math.cos(angle),
        position.y,
        target.z + orbitRadius * math.sin(angle),
      );
    } else if (mode == CameraMode.follow && followTarget != null) {
      final desired = followTarget! + followOffset;
      position = position.lerp(desired, (dt * 3).clamp(0, 1));
      target = followTarget!;
    }
  }
}

// ════════════════════════════════════════════════════════════════════
//  ANIMATION
// ════════════════════════════════════════════════════════════════════

enum EasingType { linear, easeIn, easeOut, easeInOut, bounce, elastic, back, sine }

double applyEasing(double t, EasingType easing) {
  switch (easing) {
    case EasingType.linear: return t;
    case EasingType.easeIn: return t * t * t;
    case EasingType.easeOut: return 1 - (1 - t) * (1 - t) * (1 - t);
    case EasingType.easeInOut: return t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) * (-2 * t + 2) * (-2 * t + 2) / 2;
    case EasingType.bounce:
      var p = 1 - t;
      if (p < 1 / 2.75) return 1 - 7.5625 * p * p;
      if (p < 2 / 2.75) { p -= 1.5 / 2.75; return 1 - (7.5625 * p * p + 0.75); }
      if (p < 2.5 / 2.75) { p -= 2.25 / 2.75; return 1 - (7.5625 * p * p + 0.9375); }
      p -= 2.625 / 2.75; return 1 - (7.5625 * p * p + 0.984375);
    case EasingType.elastic:
      if (t == 0 || t == 1) return t;
      return -math.pow(2, 10 * t - 10) * math.sin((t * 10 - 10.75) * (2 * math.pi / 3));
    case EasingType.back:
      const c = 1.70158;
      return (c + 1) * t * t * t - c * t * t;
    case EasingType.sine:
      return 0.5 - 0.5 * math.cos(t * math.pi);
  }
}

class AnimationDef {
  final String type; // Rotate, Translate, Scale, Bounce, Pulse, Orbit, Swing, Shake, Path, Keyframe
  final double duration;
  final bool looping;
  final EasingType easing;
  final double delay;
  final Map<String, dynamic> params;

  const AnimationDef({
    required this.type,
    this.duration = 1.0,
    this.looping = true,
    this.easing = EasingType.linear,
    this.delay = 0.0,
    this.params = const {},
  });

  Mat4 evaluate(double elapsed, Mat4 base) {
    final adjustedTime = elapsed - delay;
    if (adjustedTime < 0) return base;
    double rawT;
    if (looping) {
      rawT = (adjustedTime % duration) / duration;
    } else {
      rawT = (adjustedTime / duration).clamp(0, 1);
    }
    final t = applyEasing(rawT, easing);

    switch (type) {
      case 'Rotate':
        final axis = _v3(params['axis'], Vec3.up);
        final degrees = _d(params['degrees'], 360);
        return base * Mat4.fromAxisAngle(axis, degrees * math.pi / 180 * t);
      case 'Translate':
        final from = _v3(params['from'], Vec3.zero);
        final to = _v3(params['to'], Vec3.up);
        return Mat4.translation(from.lerp(to, t)) * base;
      case 'Scale':
        final from = _v3(params['from'], Vec3.one);
        final to = _v3(params['to'], Vec3.one * 2);
        return base * Mat4.scale(from.lerp(to, t));
      case 'Bounce':
        final height = _d(params['height'], 1.5);
        return base * Mat4.translation(Vec3(0, math.sin(t * math.pi) * height, 0));
      case 'Pulse':
        final minS = _d(params['min_scale'], 0.8);
        final maxS = _d(params['max_scale'], 1.2);
        final s = minS + (maxS - minS) * (0.5 + 0.5 * math.sin(t * 2 * math.pi));
        return base * Mat4.scale(Vec3(s, s, s));
      case 'Orbit':
        final radius = _d(params['radius'], 3);
        final height = _d(params['height'], 0);
        final angle = t * 2 * math.pi;
        return base * Mat4.translation(Vec3(radius * math.cos(angle), height, radius * math.sin(angle)));
      case 'Swing':
        final angle = _d(params['angle'], 45);
        final axis = _v3(params['axis'], const Vec3(0, 0, 1));
        final a = math.sin(t * 2 * math.pi) * angle * math.pi / 180;
        return base * Mat4.fromAxisAngle(axis, a);
      case 'Shake':
        final intensity = _d(params['intensity'], 0.1);
        final r = math.Random((elapsed * 1000).toInt());
        return base * Mat4.translation(Vec3(
          (r.nextDouble() - 0.5) * intensity,
          (r.nextDouble() - 0.5) * intensity,
          (r.nextDouble() - 0.5) * intensity,
        ));
      case 'Float':
        final amplitude = _d(params['amplitude'], 0.5);
        final y = math.sin(elapsed * 2 * math.pi / duration) * amplitude;
        return base * Mat4.translation(Vec3(0, y, 0));
      case 'Spin':
        final speed = _v3(params['speed'], const Vec3(0, 90, 0));
        return base * Mat4.fromEulerXYZ(
          speed.x * math.pi / 180 * elapsed,
          speed.y * math.pi / 180 * elapsed,
          speed.z * math.pi / 180 * elapsed,
        );
      default:
        return base;
    }
  }

  static double _d(dynamic v, double def) => (v as num?)?.toDouble() ?? def;
  static Vec3 _v3(dynamic v, Vec3 def) {
    if (v is Map) return Vec3((v['x'] as num?)?.toDouble() ?? 0, (v['y'] as num?)?.toDouble() ?? 0, (v['z'] as num?)?.toDouble() ?? 0);
    return def;
  }
}

/// Keyframe animation channel
class KeyframeChannel {
  final String property; // 'position', 'rotation', 'scale'
  final List<double> times;
  final List<Vec3> values;

  const KeyframeChannel({required this.property, required this.times, required this.values});

  Vec3 evaluate(double t) {
    if (times.isEmpty) return Vec3.zero;
    if (t <= times.first) return values.first;
    if (t >= times.last) return values.last;
    for (var i = 0; i < times.length - 1; i++) {
      if (t >= times[i] && t < times[i + 1]) {
        final f = (t - times[i]) / (times[i + 1] - times[i]);
        return values[i].lerp(values[i + 1], f);
      }
    }
    return values.last;
  }
}

// ════════════════════════════════════════════════════════════════════
//  PARTICLE SYSTEM
// ════════════════════════════════════════════════════════════════════

enum EmitterShape { point, sphere, cone, box, ring }

class Particle {
  Vec3 position;
  Vec3 velocity;
  Vec3 color;
  double size;
  double life;
  double maxLife;
  double rotation;
  double rotationSpeed;
  Particle({
    required this.position, required this.velocity, required this.color,
    required this.size, required this.life, required this.maxLife,
    this.rotation = 0, this.rotationSpeed = 0,
  });
}

class ParticleEmitter {
  final EmitterShape shape;
  final double emitRate;
  final double lifetime;
  final Vec3 startColor;
  final Vec3 endColor;
  final double startSize;
  final double endSize;
  final double startAlpha;
  final double endAlpha;
  final Vec3 gravity;
  final Vec3 wind;
  final double spread;
  final double speed;
  final double speedVariance;
  final int maxParticles;
  final bool worldSpace;
  final String blendMode; // 'additive', 'normal'
  final double burstCount;
  final bool prewarm;

  final List<Particle> _particles = [];
  double _emitAccum = 0;
  final math.Random _rng = math.Random();

  ParticleEmitter({
    this.shape = EmitterShape.point,
    this.emitRate = 20,
    this.lifetime = 2,
    this.startColor = Vec3.one,
    this.endColor = Vec3.one,
    this.startSize = 0.1,
    this.endSize = 0.0,
    this.startAlpha = 1.0,
    this.endAlpha = 0.0,
    this.gravity = const Vec3(0, -2, 0),
    this.wind = Vec3.zero,
    this.spread = 45.0,
    this.speed = 2.0,
    this.speedVariance = 0.5,
    this.maxParticles = 200,
    this.worldSpace = true,
    this.blendMode = 'additive',
    this.burstCount = 0,
    this.prewarm = false,
  });

  List<Particle> get particles => _particles;

  void update(double dt, Vec3 emitterPos) {
    // Update existing particles
    for (var i = _particles.length - 1; i >= 0; i--) {
      final p = _particles[i];
      p.life -= dt;
      if (p.life <= 0) { _particles.removeAt(i); continue; }
      p.velocity = p.velocity + (gravity + wind) * dt;
      p.position = p.position + p.velocity * dt;
      p.rotation += p.rotationSpeed * dt;
    }
    // Emit new particles
    _emitAccum += emitRate * dt;
    while (_emitAccum >= 1.0 && _particles.length < maxParticles) {
      _emitAccum -= 1.0;
      _particles.add(_spawnParticle(emitterPos));
    }
  }

  Particle _spawnParticle(Vec3 pos) {
    final dir = _randomDirection();
    final spd = speed + ((_rng.nextDouble() - 0.5) * 2 * speedVariance);
    return Particle(
      position: pos + _shapeOffset(),
      velocity: dir * spd,
      color: startColor,
      size: startSize,
      life: lifetime * (0.8 + _rng.nextDouble() * 0.4),
      maxLife: lifetime,
      rotationSpeed: (_rng.nextDouble() - 0.5) * 3,
    );
  }

  Vec3 _randomDirection() {
    final spreadRad = spread * math.pi / 180;
    final theta = _rng.nextDouble() * spreadRad;
    final phi = _rng.nextDouble() * 2 * math.pi;
    return Vec3(math.sin(theta) * math.cos(phi), math.cos(theta), math.sin(theta) * math.sin(phi));
  }

  Vec3 _shapeOffset() {
    switch (shape) {
      case EmitterShape.sphere:
        return _randomDirection() * _rng.nextDouble() * 0.5;
      case EmitterShape.box:
        return Vec3((_rng.nextDouble() - 0.5), (_rng.nextDouble() - 0.5), (_rng.nextDouble() - 0.5));
      case EmitterShape.ring:
        final a = _rng.nextDouble() * 2 * math.pi;
        return Vec3(math.cos(a), 0, math.sin(a));
      default:
        return Vec3.zero;
    }
  }

  double getParticleAlpha(Particle p) {
    final t = 1 - (p.life / p.maxLife);
    return startAlpha + (endAlpha - startAlpha) * t;
  }

  double getParticleSize(Particle p) {
    final t = 1 - (p.life / p.maxLife);
    return startSize + (endSize - startSize) * t;
  }

  Vec3 getParticleColor(Particle p) {
    final t = 1 - (p.life / p.maxLife);
    return startColor.lerp(endColor, t);
  }
}

// ════════════════════════════════════════════════════════════════════
//  PHYSICS (Basic)
// ════════════════════════════════════════════════════════════════════

enum ColliderType { sphere, box, plane }

class RigidBody {
  Vec3 velocity;
  Vec3 angularVelocity;
  double mass;
  double restitution;
  double friction;
  bool isStatic;
  bool useGravity;
  ColliderType collider;
  double colliderRadius;
  Vec3 colliderSize;

  RigidBody({
    this.velocity = Vec3.zero,
    this.angularVelocity = Vec3.zero,
    this.mass = 1.0,
    this.restitution = 0.5,
    this.friction = 0.3,
    this.isStatic = false,
    this.useGravity = true,
    this.collider = ColliderType.sphere,
    this.colliderRadius = 0.5,
    this.colliderSize = Vec3.one,
  });

  Vec3 applyPhysics(Vec3 pos, double dt, Vec3 worldGravity) {
    if (isStatic) return pos;
    if (useGravity) velocity = velocity + worldGravity * dt;
    velocity = velocity * (1.0 - friction * dt);
    var newPos = pos + velocity * dt;
    // Simple ground collision
    if (collider == ColliderType.sphere && newPos.y - colliderRadius < 0) {
      newPos = Vec3(newPos.x, colliderRadius, newPos.z);
      velocity = Vec3(velocity.x, -velocity.y * restitution, velocity.z);
    } else if (newPos.y < 0) {
      newPos = Vec3(newPos.x, 0, newPos.z);
      velocity = Vec3(velocity.x, -velocity.y * restitution, velocity.z);
    }
    return newPos;
  }
}

// ════════════════════════════════════════════════════════════════════
//  ENVIRONMENT & FOG
// ════════════════════════════════════════════════════════════════════

enum FogType { none, linear, exponential }

class Environment3D {
  final Vec3 ambientColor;
  final double ambientIntensity;
  final Vec3 skyColorTop;
  final Vec3 skyColorBottom;
  final FogType fogType;
  final Vec3 fogColor;
  final double fogNear;
  final double fogFar;
  final double fogDensity;
  final Vec3 gravity;

  const Environment3D({
    this.ambientColor = const Vec3(0.4, 0.4, 0.5),
    this.ambientIntensity = 0.3,
    this.skyColorTop = const Vec3(0.3, 0.5, 0.9),
    this.skyColorBottom = const Vec3(0.7, 0.8, 1.0),
    this.fogType = FogType.none,
    this.fogColor = const Vec3(0.7, 0.7, 0.8),
    this.fogNear = 10.0,
    this.fogFar = 100.0,
    this.fogDensity = 0.02,
    this.gravity = const Vec3(0, -9.81, 0),
  });

  double fogFactor(double distance) {
    switch (fogType) {
      case FogType.linear:
        return ((fogFar - distance) / (fogFar - fogNear)).clamp(0, 1);
      case FogType.exponential:
        return math.exp(-fogDensity * distance);
      default:
        return 1.0;
    }
  }
}

// ════════════════════════════════════════════════════════════════════
//  SCENE NODES
// ════════════════════════════════════════════════════════════════════

class SceneNode {
  final String type;
  final String? id;
  final String? name;
  Vec3 position;
  Vec3 rotation;
  Vec3 scale;
  bool visible;
  final List<SceneNode> children;

  // Type-specific data
  Material3D? material;
  Mesh? mesh;
  String? meshType;
  Map<String, dynamic>? meshParams;
  Light3D? light;
  Camera3D? camera;
  List<AnimationDef>? animations;
  ParticleEmitter? emitter;
  RigidBody? rigidBody;
  String? text;
  double? textSize;
  String? gltfUrl;
  Map<String, dynamic>? extra;

  SceneNode({
    required this.type,
    this.id,
    this.name,
    this.position = Vec3.zero,
    this.rotation = Vec3.zero,
    this.scale = Vec3.one,
    this.visible = true,
    List<SceneNode>? children,
    this.material,
    this.mesh,
    this.meshType,
    this.meshParams,
    this.light,
    this.camera,
    this.animations,
    this.emitter,
    this.rigidBody,
    this.text,
    this.textSize,
    this.gltfUrl,
    this.extra,
  }) : children = children ?? [];

  Mat4 localTransform() => Mat4.compose(position, rotation, scale);
}

// ════════════════════════════════════════════════════════════════════
//  GLTF LOADER (simplified)
// ════════════════════════════════════════════════════════════════════

class GltfLoader {
  /// Parse a simplified glTF-like JSON structure into scene nodes.
  /// Supports nodes, meshes (primitives), materials.
  static List<SceneNode> loadFromJson(Map<String, dynamic> gltf) {
    final nodes = <SceneNode>[];
    final meshes = gltf['meshes'] as List<dynamic>? ?? [];
    final materials = gltf['materials'] as List<dynamic>? ?? [];
    final gltfNodes = gltf['nodes'] as List<dynamic>? ?? [];

    for (final node in gltfNodes) {
      final meshIdx = node['mesh'] as int?;
      final pos = _parseVec3(node['translation']);
      final rot = _parseVec3(node['rotation']);
      final scl = _parseVec3(node['scale'], Vec3.one);

      if (meshIdx != null && meshIdx < meshes.length) {
        final meshDef = meshes[meshIdx] as Map<String, dynamic>;
        final primitives = meshDef['primitives'] as List<dynamic>? ?? [];
        for (final prim in primitives) {
          final matIdx = prim['material'] as int?;
          Material3D? mat;
          if (matIdx != null && matIdx < materials.length) {
            mat = _parseMaterial(materials[matIdx] as Map<String, dynamic>);
          }
          final shape = prim['type'] as String? ?? 'Cube';
          nodes.add(SceneNode(
            type: 'mesh3d',
            name: node['name'] as String?,
            position: pos,
            rotation: rot,
            scale: scl,
            meshType: shape,
            meshParams: prim as Map<String, dynamic>,
            material: mat,
          ));
        }
      } else {
        nodes.add(SceneNode(
          type: 'group',
          name: node['name'] as String?,
          position: pos,
          rotation: rot,
          scale: scl,
        ));
      }
    }
    return nodes;
  }

  static Vec3 _parseVec3(dynamic v, [Vec3 def = Vec3.zero]) {
    if (v is List && v.length >= 3) {
      return Vec3((v[0] as num).toDouble(), (v[1] as num).toDouble(), (v[2] as num).toDouble());
    }
    if (v is Map) {
      return Vec3((v['x'] as num?)?.toDouble() ?? def.x, (v['y'] as num?)?.toDouble() ?? def.y, (v['z'] as num?)?.toDouble() ?? def.z);
    }
    return def;
  }

  static Material3D _parseMaterial(Map<String, dynamic> m) {
    final pbr = m['pbrMetallicRoughness'] as Map<String, dynamic>? ?? m;
    final bc = pbr['baseColorFactor'] as List<dynamic>?;
    return Material3D(
      baseColor: bc != null && bc.length >= 3
          ? Vec3((bc[0] as num).toDouble(), (bc[1] as num).toDouble(), (bc[2] as num).toDouble())
          : const Vec3(0.8, 0.8, 0.8),
      metallic: (pbr['metallicFactor'] as num?)?.toDouble() ?? 0.0,
      roughness: (pbr['roughnessFactor'] as num?)?.toDouble() ?? 0.5,
      alpha: bc != null && bc.length >= 4 ? (bc[3] as num).toDouble() : 1.0,
    );
  }
}
