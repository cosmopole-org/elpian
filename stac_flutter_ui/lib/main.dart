import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

void main() => runApp(const BevyScene3DApp());

// ═══════════════════════════════════════════════════════════════════
// App
// ═══════════════════════════════════════════════════════════════════

class BevyScene3DApp extends StatelessWidget {
  const BevyScene3DApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Elpian - 3D Scene',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const Scene3DPage(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 3D Math
// ═══════════════════════════════════════════════════════════════════

class Vec3 {
  final double x, y, z;
  const Vec3(this.x, this.y, this.z);
  static const zero = Vec3(0, 0, 0);
  static const up = Vec3(0, 1, 0);

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);
  Vec3 operator -() => Vec3(-x, -y, -z);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  Vec3 cross(Vec3 o) => Vec3(
        y * o.z - z * o.y,
        z * o.x - x * o.z,
        x * o.y - y * o.x,
      );

  double get length => math.sqrt(x * x + y * y + z * z);
  Vec3 get normalized {
    final l = length;
    return l > 1e-10 ? Vec3(x / l, y / l, z / l) : zero;
  }
}

class Mat4 {
  final List<double> m; // 16 elements, column-major

  const Mat4._(this.m);

  factory Mat4.identity() => const Mat4._([
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
      ]);

  factory Mat4.perspective(
      double fovDeg, double aspect, double near, double far) {
    final f = 1.0 / math.tan(fovDeg * math.pi / 360.0);
    final nf = 1.0 / (near - far);
    return Mat4._([
      f / aspect, 0, 0, 0,
      0, f, 0, 0,
      0, 0, (far + near) * nf, -1,
      0, 0, 2 * far * near * nf, 0,
    ]);
  }

  factory Mat4.lookAt(Vec3 eye, Vec3 target, Vec3 up) {
    final f = (target - eye).normalized;
    final s = f.cross(up).normalized;
    final u = s.cross(f);
    return Mat4._([
      s.x, u.x, -f.x, 0,
      s.y, u.y, -f.y, 0,
      s.z, u.z, -f.z, 0,
      -s.dot(eye), -u.dot(eye), f.dot(eye), 1,
    ]);
  }

  factory Mat4.translation(double tx, double ty, double tz) => Mat4._([
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        tx, ty, tz, 1,
      ]);

  factory Mat4.rotationX(double rad) {
    final c = math.cos(rad), s = math.sin(rad);
    return Mat4._([
      1, 0, 0, 0,
      0, c, s, 0,
      0, -s, c, 0,
      0, 0, 0, 1,
    ]);
  }

  factory Mat4.rotationY(double rad) {
    final c = math.cos(rad), s = math.sin(rad);
    return Mat4._([
      c, 0, -s, 0,
      0, 1, 0, 0,
      s, 0, c, 0,
      0, 0, 0, 1,
    ]);
  }

  factory Mat4.rotationZ(double rad) {
    final c = math.cos(rad), s = math.sin(rad);
    return Mat4._([
      c, s, 0, 0,
      -s, c, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1,
    ]);
  }

  factory Mat4.scale(double sx, double sy, double sz) => Mat4._([
        sx, 0, 0, 0,
        0, sy, 0, 0,
        0, 0, sz, 0,
        0, 0, 0, 1,
      ]);

  factory Mat4.rotationAxis(Vec3 axis, double rad) {
    final a = axis.normalized;
    final c = math.cos(rad), s = math.sin(rad), t = 1 - c;
    return Mat4._([
      t * a.x * a.x + c, t * a.x * a.y + s * a.z, t * a.x * a.z - s * a.y, 0,
      t * a.x * a.y - s * a.z, t * a.y * a.y + c, t * a.y * a.z + s * a.x, 0,
      t * a.x * a.z + s * a.y, t * a.y * a.z - s * a.x, t * a.z * a.z + c, 0,
      0, 0, 0, 1,
    ]);
  }

  Mat4 operator *(Mat4 o) {
    final r = List<double>.filled(16, 0.0);
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
    if (w.abs() < 1e-10) return Vec3.zero;
    return Vec3(
      (m[0] * v.x + m[4] * v.y + m[8] * v.z + m[12]) / w,
      (m[1] * v.x + m[5] * v.y + m[9] * v.z + m[13]) / w,
      (m[2] * v.x + m[6] * v.y + m[10] * v.z + m[14]) / w,
    );
  }

  Vec3 transformDir(Vec3 v) => Vec3(
        m[0] * v.x + m[4] * v.y + m[8] * v.z,
        m[1] * v.x + m[5] * v.y + m[9] * v.z,
        m[2] * v.x + m[6] * v.y + m[10] * v.z,
      );
}

// ═══════════════════════════════════════════════════════════════════
// Render Data
// ═══════════════════════════════════════════════════════════════════

class RenderTriangle {
  final Vec3 v0, v1, v2;
  final Vec3 worldNormal;
  final Vec3 worldCenter;
  final Color baseColor;
  final double metallic;
  final double roughness;
  double depth = 0;
  Color litColor = Colors.black;

  RenderTriangle({
    required this.v0,
    required this.v1,
    required this.v2,
    required this.worldNormal,
    required this.worldCenter,
    required this.baseColor,
    this.metallic = 0,
    this.roughness = 0.5,
  });
}

// ═══════════════════════════════════════════════════════════════════
// Mesh Generation (object space, centered at origin)
// ═══════════════════════════════════════════════════════════════════

typedef Tri = (Vec3, Vec3, Vec3);

List<Tri> _generateCube() {
  const s = 0.5;
  const v = [
    Vec3(-s, -s, -s), Vec3(s, -s, -s), Vec3(s, s, -s), Vec3(-s, s, -s),
    Vec3(-s, -s, s), Vec3(s, -s, s), Vec3(s, s, s), Vec3(-s, s, s),
  ];
  return [
    (v[4], v[5], v[6]), (v[4], v[6], v[7]), // front
    (v[1], v[0], v[3]), (v[1], v[3], v[2]), // back
    (v[7], v[6], v[2]), (v[7], v[2], v[3]), // top
    (v[0], v[1], v[5]), (v[0], v[5], v[4]), // bottom
    (v[5], v[1], v[2]), (v[5], v[2], v[6]), // right
    (v[0], v[4], v[7]), (v[0], v[7], v[3]), // left
  ];
}

List<Tri> _generateSphere(double radius, int segments) {
  final tris = <Tri>[];
  final latSteps = segments;
  final lonSteps = segments * 2;

  Vec3 sphereVert(int lat, int lon) {
    final theta = math.pi * lat / latSteps;
    final phi = 2 * math.pi * lon / lonSteps;
    return Vec3(
      radius * math.sin(theta) * math.cos(phi),
      radius * math.cos(theta),
      radius * math.sin(theta) * math.sin(phi),
    );
  }

  for (var i = 0; i < latSteps; i++) {
    for (var j = 0; j < lonSteps; j++) {
      final a = sphereVert(i, j);
      final b = sphereVert(i + 1, j);
      final c = sphereVert(i + 1, j + 1);
      final d = sphereVert(i, j + 1);
      if (i > 0) tris.add((a, b, c));
      if (i < latSteps - 1) tris.add((a, c, d));
    }
  }
  return tris;
}

List<Tri> _generateCylinder(double radius, double height, {int segments = 12}) {
  final tris = <Tri>[];
  final halfH = height / 2;

  for (var i = 0; i < segments; i++) {
    final a1 = 2 * math.pi * i / segments;
    final a2 = 2 * math.pi * ((i + 1) % segments) / segments;
    final x1 = radius * math.cos(a1), z1 = radius * math.sin(a1);
    final x2 = radius * math.cos(a2), z2 = radius * math.sin(a2);

    // Side quads
    final t0 = Vec3(x1, halfH, z1);
    final t1 = Vec3(x2, halfH, z2);
    final b0 = Vec3(x1, -halfH, z1);
    final b1 = Vec3(x2, -halfH, z2);
    tris.add((t0, b0, b1));
    tris.add((t0, b1, t1));

    // Top cap
    tris.add((Vec3(0, halfH, 0), t0, t1));
    // Bottom cap
    tris.add((Vec3(0, -halfH, 0), b1, b0));
  }
  return tris;
}

List<Tri> _generatePlane(double size) {
  final s = size / 2;
  final a = Vec3(-s, 0, -s);
  final b = Vec3(s, 0, -s);
  final c = Vec3(s, 0, s);
  final d = Vec3(-s, 0, s);
  return [(a, c, b), (a, d, c)];
}

List<Tri> _generateTorus(double majorR, double minorR,
    {int majorSegs = 12, int minorSegs = 8}) {
  final tris = <Tri>[];

  Vec3 torusVert(int i, int j) {
    final u = 2 * math.pi * i / majorSegs;
    final v = 2 * math.pi * j / minorSegs;
    return Vec3(
      (majorR + minorR * math.cos(v)) * math.cos(u),
      minorR * math.sin(v),
      (majorR + minorR * math.cos(v)) * math.sin(u),
    );
  }

  for (var i = 0; i < majorSegs; i++) {
    for (var j = 0; j < minorSegs; j++) {
      final a = torusVert(i, j);
      final b = torusVert(i + 1, j);
      final c = torusVert(i + 1, j + 1);
      final d = torusVert(i, j + 1);
      tris.add((a, b, c));
      tris.add((a, c, d));
    }
  }
  return tris;
}

// ═══════════════════════════════════════════════════════════════════
// Scene Data Structures
// ═══════════════════════════════════════════════════════════════════

class SceneCamera {
  Vec3 position;
  Vec3 rotation; // Euler angles in degrees (pitch, yaw, roll)
  double fov;
  double near;
  double far;

  SceneCamera({
    this.position = const Vec3(0, 2, 5),
    this.rotation = Vec3.zero,
    this.fov = 60,
    this.near = 0.1,
    this.far = 1000,
  });

  Vec3 get forward {
    final pitch = rotation.x * math.pi / 180;
    final yaw = rotation.y * math.pi / 180;
    return Vec3(
      -math.cos(pitch) * math.sin(yaw),
      math.sin(pitch),
      -math.cos(pitch) * math.cos(yaw),
    );
  }

  Mat4 viewMatrix() {
    final target = position + forward * 10;
    return Mat4.lookAt(position, target, Vec3.up);
  }
}

class SceneLight {
  String lightType;
  Color color;
  double intensity;
  Vec3 position;
  Vec3 rotation;

  SceneLight({
    this.lightType = 'Directional',
    this.color = Colors.white,
    this.intensity = 1.0,
    this.position = Vec3.zero,
    this.rotation = Vec3.zero,
  });

  Vec3 get direction {
    final pitch = rotation.x * math.pi / 180;
    final yaw = rotation.y * math.pi / 180;
    return Vec3(
      -math.cos(pitch) * math.sin(yaw),
      math.sin(pitch),
      -math.cos(pitch) * math.cos(yaw),
    ).normalized;
  }
}

class SceneEnvironment {
  Color ambientColor;
  double ambientIntensity;

  SceneEnvironment({
    this.ambientColor = const Color(0xFF666680),
    this.ambientIntensity = 0.3,
  });
}

class SceneAnimation {
  String type; // Rotate, Bounce, Pulse
  Vec3 axis;
  double degrees;
  double height;
  double minScale;
  double maxScale;
  double duration;
  bool looping;
  String easing;

  SceneAnimation({
    this.type = 'Rotate',
    this.axis = const Vec3(0, 1, 0),
    this.degrees = 360,
    this.height = 1,
    this.minScale = 0.8,
    this.maxScale = 1.2,
    this.duration = 1,
    this.looping = true,
    this.easing = 'Linear',
  });
}

class SceneMesh {
  List<Tri> triangles;
  Color baseColor;
  double metallic;
  double roughness;
  Vec3 position;
  Vec3 rotation;
  Vec3 scale;
  SceneAnimation? animation;

  SceneMesh({
    required this.triangles,
    this.baseColor = Colors.grey,
    this.metallic = 0,
    this.roughness = 0.5,
    this.position = Vec3.zero,
    this.rotation = Vec3.zero,
    this.scale = const Vec3(1, 1, 1),
    this.animation,
  });
}

// ═══════════════════════════════════════════════════════════════════
// Scene Parser
// ═══════════════════════════════════════════════════════════════════

class ParsedScene {
  SceneCamera camera = SceneCamera();
  final List<SceneLight> lights = [];
  SceneEnvironment environment = SceneEnvironment();
  final List<SceneMesh> meshes = [];

  static ParsedScene fromJson(Map<String, dynamic> json) {
    final scene = ParsedScene();
    final world = json['world'] as List<dynamic>? ?? [];
    scene._parseNodes(world, Vec3.zero, Vec3.zero);
    return scene;
  }

  void _parseNodes(List<dynamic> nodes, Vec3 parentPos, Vec3 parentRot) {
    for (final node in nodes) {
      if (node is! Map<String, dynamic>) continue;
      final type = node['type'] as String? ?? '';
      final transform = node['transform'] as Map<String, dynamic>?;
      final pos = _parseVec3(transform?['position']) + parentPos;
      final rot = _parseVec3(transform?['rotation']) + parentRot;

      switch (type) {
        case 'environment':
          final al = node['ambient_light'] as Map<String, dynamic>?;
          environment = SceneEnvironment(
            ambientColor: al != null
                ? Color.fromARGB(
                    255,
                    ((al['r'] as num? ?? 0.5) * 255).round(),
                    ((al['g'] as num? ?? 0.5) * 255).round(),
                    ((al['b'] as num? ?? 0.5) * 255).round(),
                  )
                : const Color(0xFF808080),
            ambientIntensity: (node['ambient_intensity'] as num?)?.toDouble() ?? 0.3,
          );
          break;

        case 'camera':
          camera = SceneCamera(
            position: pos,
            rotation: rot,
            fov: (node['fov'] as num?)?.toDouble() ?? 60,
            near: (node['near'] as num?)?.toDouble() ?? 0.1,
            far: (node['far'] as num?)?.toDouble() ?? 1000,
          );
          break;

        case 'light':
          lights.add(SceneLight(
            lightType: node['light_type'] as String? ?? 'Directional',
            color: _parseColor(node['color']),
            intensity: (node['intensity'] as num?)?.toDouble() ?? 1.0,
            position: pos,
            rotation: rot,
          ));
          break;

        case 'mesh3d':
          final tris = _parseMeshShape(node['mesh']);
          final mat = node['material'] as Map<String, dynamic>? ?? {};
          meshes.add(SceneMesh(
            triangles: tris,
            baseColor: _parseColor(mat['base_color']),
            metallic: (mat['metallic'] as num?)?.toDouble() ?? 0,
            roughness: (mat['roughness'] as num?)?.toDouble() ?? 0.5,
            position: pos,
            rotation: rot,
            animation: _parseAnimation(node['animation']),
          ));
          break;

        case 'group':
          final children = node['children'] as List<dynamic>? ?? [];
          _parseNodes(children, pos, rot);
          break;
      }
    }
  }

  static Vec3 _parseVec3(Map<String, dynamic>? m) {
    if (m == null) return Vec3.zero;
    return Vec3(
      (m['x'] as num?)?.toDouble() ?? 0,
      (m['y'] as num?)?.toDouble() ?? 0,
      (m['z'] as num?)?.toDouble() ?? 0,
    );
  }

  static Color _parseColor(Map<String, dynamic>? m) {
    if (m == null) return Colors.grey;
    return Color.fromARGB(
      ((m['a'] as num?)?.toDouble() ?? 1.0) * 255 ~/ 1,
      ((m['r'] as num?)?.toDouble() ?? 0.5) * 255 ~/ 1,
      ((m['g'] as num?)?.toDouble() ?? 0.5) * 255 ~/ 1,
      ((m['b'] as num?)?.toDouble() ?? 0.5) * 255 ~/ 1,
    );
  }

  static List<Tri> _parseMeshShape(dynamic mesh) {
    if (mesh is String) {
      switch (mesh) {
        case 'Cube':
          return _generateCube();
        case 'Sphere':
          return _generateSphere(0.5, 8);
        case 'Cylinder':
          return _generateCylinder(0.5, 1.0);
        case 'Plane':
          return _generatePlane(10);
        default:
          return _generateCube();
      }
    }
    if (mesh is Map<String, dynamic>) {
      final shape = mesh['shape'] as String? ?? 'Cube';
      switch (shape) {
        case 'Sphere':
          final r = (mesh['radius'] as num?)?.toDouble() ?? 0.5;
          final segs = (mesh['subdivisions'] as num?)?.toInt() ?? 8;
          return _generateSphere(r, segs.clamp(4, 12));
        case 'Cylinder':
          final r = (mesh['radius'] as num?)?.toDouble() ?? 0.5;
          final h = (mesh['height'] as num?)?.toDouble() ?? 1.0;
          return _generateCylinder(r, h);
        case 'Plane':
          final size = (mesh['size'] as num?)?.toDouble() ?? 10;
          return _generatePlane(size);
        case 'Torus':
          final r = (mesh['radius'] as num?)?.toDouble() ?? 1.0;
          final tr = (mesh['tube_radius'] as num?)?.toDouble() ?? 0.3;
          return _generateTorus(r, tr);
        case 'Cube':
          return _generateCube();
        default:
          return _generateCube();
      }
    }
    return _generateCube();
  }

  static SceneAnimation? _parseAnimation(Map<String, dynamic>? anim) {
    if (anim == null) return null;
    final animType = anim['animation_type'];
    if (animType == null) return null;

    String type = 'Rotate';
    Vec3 axis = const Vec3(0, 1, 0);
    double degrees = 360;
    double height = 1;
    double minScale = 0.8;
    double maxScale = 1.2;

    if (animType is Map<String, dynamic>) {
      type = animType['type'] as String? ?? 'Rotate';
      if (animType.containsKey('axis')) {
        axis = _parseVec3(animType['axis'] as Map<String, dynamic>?);
      }
      degrees = (animType['degrees'] as num?)?.toDouble() ?? 360;
      height = (animType['height'] as num?)?.toDouble() ?? 1;
      minScale = (animType['min_scale'] as num?)?.toDouble() ?? 0.8;
      maxScale = (animType['max_scale'] as num?)?.toDouble() ?? 1.2;
    }

    return SceneAnimation(
      type: type,
      axis: axis,
      degrees: degrees,
      height: height,
      minScale: minScale,
      maxScale: maxScale,
      duration: (anim['duration'] as num?)?.toDouble() ?? 1,
      looping: anim['looping'] as bool? ?? true,
      easing: anim['easing'] as String? ?? 'Linear',
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Scene Renderer
// ═══════════════════════════════════════════════════════════════════

class SceneRenderer {
  final ParsedScene scene;

  SceneRenderer(this.scene);

  List<RenderTriangle> render(double elapsed, double aspect,
      {double orbitYaw = 0, double orbitPitch = 0, double orbitZoom = 1}) {
    final cam = scene.camera;

    // Apply orbit controls to camera
    final baseFwd = cam.forward;
    final basePos = cam.position;
    final target = basePos + baseFwd * 10;

    // Orbit around the target point
    final camToTarget = target - basePos;
    final dist = camToTarget.length * orbitZoom;
    final baseYaw = math.atan2(-baseFwd.x, -baseFwd.z);
    final basePitch = math.asin(baseFwd.y.clamp(-1, 1));
    final yaw = baseYaw + orbitYaw;
    final pitch = (basePitch + orbitPitch).clamp(-math.pi / 2.5, math.pi / 2.5);

    final orbitPos = Vec3(
      target.x + dist * math.cos(pitch) * math.sin(yaw),
      target.y - dist * math.sin(pitch),
      target.z + dist * math.cos(pitch) * math.cos(yaw),
    );

    final view = Mat4.lookAt(orbitPos, target, Vec3.up);
    final proj = Mat4.perspective(cam.fov, aspect, cam.near, cam.far);
    final vp = proj * view;

    final renderTris = <RenderTriangle>[];

    for (final mesh in scene.meshes) {
      final model = _buildModelMatrix(mesh, elapsed);

      for (final tri in mesh.triangles) {
        // Transform to world space
        final w0 = model.transformPoint(tri.$1);
        final w1 = model.transformPoint(tri.$2);
        final w2 = model.transformPoint(tri.$3);

        // Face normal in world space
        final edge1 = w1 - w0;
        final edge2 = w2 - w0;
        final normal = edge1.cross(edge2).normalized;
        final center = Vec3(
          (w0.x + w1.x + w2.x) / 3,
          (w0.y + w1.y + w2.y) / 3,
          (w0.z + w1.z + w2.z) / 3,
        );

        // Backface culling (view direction)
        final viewDir = (center - orbitPos).normalized;
        if (normal.dot(viewDir) > 0.05) continue;

        // Project to clip space
        final p0 = vp.transformPoint(w0);
        final p1 = vp.transformPoint(w1);
        final p2 = vp.transformPoint(w2);

        // Simple near-plane clipping
        final camZ0 = _viewZ(view, w0);
        final camZ1 = _viewZ(view, w1);
        final camZ2 = _viewZ(view, w2);
        if (camZ0 > -cam.near && camZ1 > -cam.near && camZ2 > -cam.near) {
          continue;
        }

        // Compute lighting
        final litColor =
            _computeLighting(normal, center, mesh.baseColor, orbitPos);

        final rt = RenderTriangle(
          v0: p0,
          v1: p1,
          v2: p2,
          worldNormal: normal,
          worldCenter: center,
          baseColor: mesh.baseColor,
          metallic: mesh.metallic,
          roughness: mesh.roughness,
        );
        rt.depth = (camZ0 + camZ1 + camZ2) / 3;
        rt.litColor = litColor;

        renderTris.add(rt);
      }
    }

    // Sort by depth (painter's algorithm, farthest first)
    renderTris.sort((a, b) => a.depth.compareTo(b.depth));

    return renderTris;
  }

  double _viewZ(Mat4 view, Vec3 worldPos) {
    return view.m[2] * worldPos.x +
        view.m[6] * worldPos.y +
        view.m[10] * worldPos.z +
        view.m[14];
  }

  Mat4 _buildModelMatrix(SceneMesh mesh, double elapsed) {
    var model = Mat4.translation(mesh.position.x, mesh.position.y, mesh.position.z);

    // Static rotation
    if (mesh.rotation.x != 0) {
      model = model * Mat4.rotationX(mesh.rotation.x * math.pi / 180);
    }
    if (mesh.rotation.y != 0) {
      model = model * Mat4.rotationY(mesh.rotation.y * math.pi / 180);
    }
    if (mesh.rotation.z != 0) {
      model = model * Mat4.rotationZ(mesh.rotation.z * math.pi / 180);
    }

    // Animation
    final anim = mesh.animation;
    if (anim != null) {
      var t = (elapsed % anim.duration) / anim.duration;
      if (anim.easing == 'EaseInOut') {
        t = t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) * (-2 * t + 2) / 2;
      }

      switch (anim.type) {
        case 'Rotate':
          final angle = anim.degrees * t * math.pi / 180;
          model = model * Mat4.rotationAxis(anim.axis, angle);
          break;
        case 'Bounce':
          final offset = anim.height * math.sin(t * math.pi);
          model = Mat4.translation(
                  mesh.position.x, mesh.position.y + offset, mesh.position.z) *
              _extractRotation(model);
          break;
        case 'Pulse':
          final s = anim.minScale + (anim.maxScale - anim.minScale) *
                  (0.5 + 0.5 * math.sin(t * 2 * math.pi));
          model = model * Mat4.scale(s, s, s);
          break;
      }
    }

    return model;
  }

  Mat4 _extractRotation(Mat4 m) {
    // Return just rotation/scale part (no translation)
    return Mat4._([
      m.m[0], m.m[1], m.m[2], m.m[3],
      m.m[4], m.m[5], m.m[6], m.m[7],
      m.m[8], m.m[9], m.m[10], m.m[11],
      0, 0, 0, 1,
    ]);
  }

  Color _computeLighting(Vec3 normal, Vec3 position, Color baseColor, Vec3 camPos) {
    final env = scene.environment;
    // Ambient
    double r = env.ambientColor.red / 255.0 * env.ambientIntensity;
    double g = env.ambientColor.green / 255.0 * env.ambientIntensity;
    double b = env.ambientColor.blue / 255.0 * env.ambientIntensity;

    for (final light in scene.lights) {
      double ndotl;
      double lr = light.color.red / 255.0;
      double lg = light.color.green / 255.0;
      double lb = light.color.blue / 255.0;

      if (light.lightType == 'Directional') {
        final dir = light.direction;
        ndotl = math.max(0, normal.dot(-dir));
      } else {
        // Point light
        final toLight = light.position - position;
        final dist = toLight.length;
        final dir = toLight * (1.0 / math.max(dist, 0.01));
        ndotl = math.max(0, normal.dot(dir));
        // Attenuation
        ndotl *= 1.0 / (1.0 + 0.05 * dist * dist);
      }

      r += lr * light.intensity * ndotl;
      g += lg * light.intensity * ndotl;
      b += lb * light.intensity * ndotl;
    }

    // Add a subtle rim light for visual depth
    final viewDir = (camPos - position).normalized;
    final rim = math.pow(1.0 - math.max(0, normal.dot(viewDir)), 3) * 0.15;
    r += rim;
    g += rim;
    b += rim;

    return Color.fromARGB(
      255,
      (baseColor.red * r).round().clamp(0, 255),
      (baseColor.green * g).round().clamp(0, 255),
      (baseColor.blue * b).round().clamp(0, 255),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Custom Painter
// ═══════════════════════════════════════════════════════════════════

class Scene3DPainter extends CustomPainter {
  final List<RenderTriangle> triangles;

  Scene3DPainter({required this.triangles});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final scale = math.min(size.width, size.height) / 2;

    final paint = Paint()..style = PaintingStyle.fill;

    for (final tri in triangles) {
      // NDC to screen
      final x0 = cx + tri.v0.x * scale;
      final y0 = cy - tri.v0.y * scale;
      final x1 = cx + tri.v1.x * scale;
      final y1 = cy - tri.v1.y * scale;
      final x2 = cx + tri.v2.x * scale;
      final y2 = cy - tri.v2.y * scale;

      // Frustum culling (screen bounds)
      final minX = math.min(x0, math.min(x1, x2));
      final maxX = math.max(x0, math.max(x1, x2));
      final minY = math.min(y0, math.min(y1, y2));
      final maxY = math.max(y0, math.max(y1, y2));
      if (maxX < 0 || minX > size.width || maxY < 0 || minY > size.height) {
        continue;
      }

      paint.color = tri.litColor;
      final path = Path()
        ..moveTo(x0, y0)
        ..lineTo(x1, y1)
        ..lineTo(x2, y2)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(Scene3DPainter oldDelegate) => true;
}

// ═══════════════════════════════════════════════════════════════════
// Main Page Widget
// ═══════════════════════════════════════════════════════════════════

class Scene3DPage extends StatefulWidget {
  const Scene3DPage({super.key});

  @override
  State<Scene3DPage> createState() => _Scene3DPageState();
}

class _Scene3DPageState extends State<Scene3DPage>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  double _elapsed = 0;
  ParsedScene? _scene;
  SceneRenderer? _renderer;
  List<RenderTriangle> _triangles = [];

  // Orbit camera controls
  double _orbitYaw = 0;
  double _orbitPitch = 0;
  double _orbitZoom = 1.0;
  double _lastDragX = 0;
  double _lastDragY = 0;

  // Auto-rotate
  bool _autoRotate = true;

  @override
  void initState() {
    super.initState();
    _loadScene();
    _ticker = createTicker(_onTick)..start();
  }

  Future<void> _loadScene() async {
    try {
      final jsonStr =
          await rootBundle.loadString('lib/example/bevy_scene.json');
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      setState(() {
        _scene = ParsedScene.fromJson(json);
        _renderer = SceneRenderer(_scene!);
      });
    } catch (e) {
      // Fallback: use the inline scene from bevy_scene_example.dart
      setState(() {
        _scene = ParsedScene.fromJson(_fallbackScene());
        _renderer = SceneRenderer(_scene!);
      });
    }
  }

  Map<String, dynamic> _fallbackScene() {
    return {
      'world': [
        {
          'type': 'environment',
          'ambient_light': {'r': 0.4, 'g': 0.4, 'b': 0.5, 'a': 1.0},
          'ambient_intensity': 0.3,
        },
        {
          'type': 'camera',
          'camera_type': 'Perspective',
          'fov': 60.0,
          'transform': {
            'position': {'x': 3.0, 'y': 4.0, 'z': 8.0},
            'rotation': {'x': -20.0, 'y': 15.0, 'z': 0.0},
          },
        },
        {
          'type': 'light',
          'light_type': 'Directional',
          'color': {'r': 1.0, 'g': 0.95, 'b': 0.9, 'a': 1.0},
          'intensity': 1.2,
          'transform': {
            'rotation': {'x': -45.0, 'y': 30.0, 'z': 0.0},
          },
        },
        {
          'type': 'mesh3d',
          'mesh': 'Cube',
          'material': {
            'base_color': {'r': 0.8, 'g': 0.2, 'b': 0.2, 'a': 1.0},
            'metallic': 0.3,
            'roughness': 0.5,
          },
          'transform': {
            'position': {'x': 0.0, 'y': 1.0, 'z': 0.0},
          },
          'animation': {
            'animation_type': {
              'type': 'Rotate',
              'axis': {'x': 0.0, 'y': 1.0, 'z': 0.0},
              'degrees': 360.0,
            },
            'duration': 4.0,
            'looping': true,
            'easing': 'Linear',
          },
        },
        {
          'type': 'mesh3d',
          'mesh': {'shape': 'Sphere', 'radius': 0.8, 'subdivisions': 8},
          'material': {
            'base_color': {'r': 0.2, 'g': 0.6, 'b': 0.9, 'a': 1.0},
            'metallic': 0.8,
            'roughness': 0.2,
          },
          'transform': {
            'position': {'x': 3.0, 'y': 1.0, 'z': 0.0},
          },
          'animation': {
            'animation_type': {'type': 'Bounce', 'height': 1.5},
            'duration': 2.0,
            'looping': true,
            'easing': 'EaseInOut',
          },
        },
        {
          'type': 'mesh3d',
          'mesh': {'shape': 'Plane', 'size': 20.0},
          'material': {
            'base_color': {'r': 0.3, 'g': 0.3, 'b': 0.35, 'a': 1.0},
          },
          'transform': {
            'position': {'x': 0.0, 'y': 0.0, 'z': 0.0},
          },
        },
      ],
    };
  }

  void _onTick(Duration elapsed) {
    _elapsed = elapsed.inMicroseconds / 1000000.0;

    if (_autoRotate) {
      _orbitYaw = _elapsed * 0.15; // Slow auto-rotation
    }

    if (_renderer != null) {
      final size = MediaQuery.of(context).size;
      final aspect = size.width / math.max(size.height, 1);
      _triangles = _renderer!.render(
        _elapsed,
        aspect,
        orbitYaw: _orbitYaw,
        orbitPitch: _orbitPitch,
        orbitZoom: _orbitZoom,
      );
    }

    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1218),
      body: _scene == null
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF818CF8),
              ),
            )
          : Stack(
              children: [
                // 3D Scene
                GestureDetector(
                  onPanStart: (details) {
                    _autoRotate = false;
                    _lastDragX = details.localPosition.dx;
                    _lastDragY = details.localPosition.dy;
                  },
                  onPanUpdate: (details) {
                    final dx = details.localPosition.dx - _lastDragX;
                    final dy = details.localPosition.dy - _lastDragY;
                    _lastDragX = details.localPosition.dx;
                    _lastDragY = details.localPosition.dy;
                    _orbitYaw += dx * 0.005;
                    _orbitPitch += dy * 0.005;
                    _orbitPitch = _orbitPitch.clamp(-1.2, 1.2);
                  },
                  child: SizedBox.expand(
                    child: CustomPaint(
                      painter: Scene3DPainter(triangles: _triangles),
                    ),
                  ),
                ),

                // Top overlay
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xDD0F1218),
                          Color(0x000F1218),
                        ],
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                    child: Row(
                      children: [
                        const Icon(Icons.rocket_launch,
                            color: Color(0xFF818CF8), size: 28),
                        const SizedBox(width: 12),
                        const Text(
                          'Elpian',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Text(
                          'Bevy 3D Scene Renderer',
                          style: TextStyle(
                            color: Color(0x80FFFFFF),
                            fontSize: 14,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _autoRotate = !_autoRotate;
                              if (_autoRotate) {
                                _orbitYaw = _elapsed * 0.15;
                                _orbitPitch = 0;
                              }
                            });
                          },
                          icon: Icon(
                            _autoRotate
                                ? Icons.pause_circle_outline
                                : Icons.play_circle_outline,
                            color: const Color(0xFF818CF8),
                            size: 20,
                          ),
                          label: Text(
                            _autoRotate ? 'Pause' : 'Auto-Rotate',
                            style: const TextStyle(
                              color: Color(0xFF818CF8),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom overlay
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Color(0xDD0F1218),
                          Color(0x000F1218),
                        ],
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(24, 40, 24, 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _infoChip(Icons.view_in_ar, '${_scene!.meshes.length} Meshes'),
                        const SizedBox(width: 16),
                        _infoChip(Icons.lightbulb_outline,
                            '${_scene!.lights.length} Lights'),
                        const SizedBox(width: 16),
                        _infoChip(Icons.animation, 'Live Animations'),
                        const SizedBox(width: 16),
                        _infoChip(Icons.touch_app, 'Drag to Orbit'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white38, size: 16),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
