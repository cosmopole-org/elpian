/// Pure-Dart 3D scene renderer that works on all Flutter platforms
/// without requiring native FFI or WASM compilation.
///
/// Parses the same JSON scene format as the Rust renderer and draws
/// projected 3D geometry using Flutter's Canvas API (GPU-accelerated
/// via Skia/Impeller).
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';

// ── Vector / Matrix Math ──────────────────────────────────────────

class Vec3 {
  final double x, y, z;
  const Vec3(this.x, this.y, this.z);
  static const zero = Vec3(0, 0, 0);
  static const up = Vec3(0, 1, 0);

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
  Vec3 get normalized {
    final l = length;
    return l > 0.0001 ? this / l : zero;
  }

  Vec3 lerp(Vec3 o, double t) => this + (o - this) * t;
}

class Mat4 {
  final List<double> m; // column-major 4x4
  const Mat4._(this.m);

  static Mat4 identity() => Mat4._(List.generate(16, (i) => (i % 5 == 0) ? 1.0 : 0.0));

  static Mat4 translation(Vec3 v) {
    final m = List.generate(16, (i) => (i % 5 == 0) ? 1.0 : 0.0);
    m[12] = v.x; m[13] = v.y; m[14] = v.z;
    return Mat4._(m);
  }

  static Mat4 scale(Vec3 v) {
    final m = List.filled(16, 0.0);
    m[0] = v.x; m[5] = v.y; m[10] = v.z; m[15] = 1.0;
    return Mat4._(m);
  }

  static Mat4 rotationX(double rad) {
    final c = math.cos(rad), s = math.sin(rad);
    final m = List.generate(16, (i) => (i % 5 == 0) ? 1.0 : 0.0);
    m[5] = c; m[6] = s; m[9] = -s; m[10] = c;
    return Mat4._(m);
  }

  static Mat4 rotationY(double rad) {
    final c = math.cos(rad), s = math.sin(rad);
    final m = List.generate(16, (i) => (i % 5 == 0) ? 1.0 : 0.0);
    m[0] = c; m[2] = -s; m[8] = s; m[10] = c;
    return Mat4._(m);
  }

  static Mat4 rotationZ(double rad) {
    final c = math.cos(rad), s = math.sin(rad);
    final m = List.generate(16, (i) => (i % 5 == 0) ? 1.0 : 0.0);
    m[0] = c; m[1] = s; m[4] = -s; m[5] = c;
    return Mat4._(m);
  }

  static Mat4 perspective(double fovRad, double aspect, double near, double far) {
    final f = 1.0 / math.tan(fovRad / 2.0);
    final nf = 1.0 / (near - far);
    final m = List.filled(16, 0.0);
    m[0] = f / aspect;
    m[5] = f;
    m[10] = (far + near) * nf;
    m[11] = -1.0;
    m[14] = 2.0 * far * near * nf;
    return Mat4._(m);
  }

  static Mat4 lookAt(Vec3 eye, Vec3 target, Vec3 up) {
    final f = (target - eye).normalized;
    final s = f.cross(up).normalized;
    final u = s.cross(f);
    final m = List.filled(16, 0.0);
    m[0] = s.x; m[4] = s.y; m[8] = s.z;
    m[1] = u.x; m[5] = u.y; m[9] = u.z;
    m[2] = -f.x; m[6] = -f.y; m[10] = -f.z;
    m[12] = -s.dot(eye);
    m[13] = -u.dot(eye);
    m[14] = f.dot(eye);
    m[15] = 1.0;
    return Mat4._(m);
  }

  static Mat4 fromEulerXYZ(double rx, double ry, double rz) {
    return rotationZ(rz) * rotationY(ry) * rotationX(rx);
  }

  static Mat4 fromTransform(Vec3 pos, Vec3 rot, Vec3 scl) {
    final t = translation(pos);
    final r = fromEulerXYZ(
      rot.x * math.pi / 180.0,
      rot.y * math.pi / 180.0,
      rot.z * math.pi / 180.0,
    );
    final s = scale(scl);
    return t * r * s;
  }

  Mat4 operator *(Mat4 o) {
    final r = List.filled(16, 0.0);
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
    final iw = w.abs() > 0.0001 ? 1.0 / w : 1.0;
    return Vec3(
      (m[0] * v.x + m[4] * v.y + m[8] * v.z + m[12]) * iw,
      (m[1] * v.x + m[5] * v.y + m[9] * v.z + m[13]) * iw,
      (m[2] * v.x + m[6] * v.y + m[10] * v.z + m[14]) * iw,
    );
  }

  Vec3 transformDirection(Vec3 v) {
    return Vec3(
      m[0] * v.x + m[4] * v.y + m[8] * v.z,
      m[1] * v.x + m[5] * v.y + m[9] * v.z,
      m[2] * v.x + m[6] * v.y + m[10] * v.z,
    );
  }

  /// Returns clip-space (x, y, z, w) for near-plane clipping
  List<double> transformClip(Vec3 v) {
    return [
      m[0] * v.x + m[4] * v.y + m[8] * v.z + m[12],
      m[1] * v.x + m[5] * v.y + m[9] * v.z + m[13],
      m[2] * v.x + m[6] * v.y + m[10] * v.z + m[14],
      m[3] * v.x + m[7] * v.y + m[11] * v.z + m[15],
    ];
  }
}

// ── Scene Data Types ──────────────────────────────────────────────

class _Triangle {
  final Vec3 v0, v1, v2, normal;
  // Per-vertex UVs (parity with scene3d). Used to sample procedural textures at
  // the triangle centroid in this flat-shaded fallback.
  final Offset uv0, uv1, uv2;
  const _Triangle(this.v0, this.v1, this.v2, this.normal,
      {this.uv0 = Offset.zero, this.uv1 = Offset.zero, this.uv2 = Offset.zero});

  static _Triangle fromVertices(Vec3 v0, Vec3 v1, Vec3 v2) {
    final n = (v1 - v0).cross(v2 - v0).normalized;
    return _Triangle(v0, v1, v2, n);
  }
}

class _Camera {
  Vec3 position;
  Vec3 forward;
  Vec3 up;
  double fov;
  double near;
  double far;
  _Camera({
    this.position = const Vec3(0, 5, 10),
    this.forward = const Vec3(0, -0.34, -0.94),
    this.up = Vec3.up,
    this.fov = 60.0,
    this.near = 0.1,
    this.far = 1000.0,
  });
}

class _Light {
  final String type;
  final Vec3 position;
  final Vec3 direction;
  final Vec3 color;
  final double intensity;
  /// Point/spot reach; `null` = unbounded inverse-square only.
  final double? range;
  const _Light({
    required this.type,
    required this.position,
    required this.direction,
    required this.color,
    required this.intensity,
    this.range,
  });
}

/// Environment shading params (sky gradient, fog, ambient) collected per frame.
class _Environment {
  final Vec3 ambientColor;
  final double ambientIntensity;
  final bool fogEnabled;
  final bool fogLinear;
  final Vec3 fogColor;
  final double fogNear;
  final double fogDistance;
  /// (top, bottom) sky gradient used to clear the frame; null = flat clear.
  final (Vec3, Vec3)? skyGradient;
  const _Environment({
    this.ambientColor = const Vec3(1, 1, 1),
    this.ambientIntensity = 0.3,
    this.fogEnabled = false,
    this.fogLinear = false,
    this.fogColor = const Vec3(0.7, 0.7, 0.8),
    this.fogNear = 0.0,
    this.fogDistance = 100.0,
    this.skyGradient,
  });
}

class _RenderTriangle {
  final List<Offset> screenPoints;
  final double depth;
  final Color color;
  const _RenderTriangle(this.screenPoints, this.depth, this.color);
}

// ── Scene Renderer ────────────────────────────────────────────────

class DartSceneRenderer {
  double _elapsed = 0.0;

  /// Advance internal animation clock without rendering.
  void advanceTime(double deltaTime) {
    _elapsed += deltaTime;
  }

  void renderScene(
    Canvas canvas,
    Size size,
    Map<String, dynamic> scene,
    double deltaTime,
  ) {
    _elapsed += deltaTime;

    final world = scene['world'] as List<dynamic>? ?? [];

    // Collect environment (ambient, fog, sky gradient).
    final env = _collectEnvironment(world);

    // Clear background: vertical sky gradient when provided, else flat color.
    if (env.skyGradient != null) {
      final (top, bottom) = env.skyGradient!;
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_vecToColor(top), _vecToColor(bottom)],
        ).createShader(Offset.zero & size);
      canvas.drawRect(Offset.zero & size, paint);
    } else {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFF14141E),
      );
    }

    // Collect camera
    final camera = _findCamera(world);

    // Collect lights
    final lights = _collectLights(world);

    // Build matrices
    final aspect = size.width / size.height;
    final view = Mat4.lookAt(
      camera.position,
      camera.position + camera.forward,
      camera.up,
    );
    final proj = Mat4.perspective(
      camera.fov * math.pi / 180.0,
      aspect,
      camera.near,
      camera.far,
    );
    final viewProj = proj * view;

    // Collect all render triangles
    final renderTris = <_RenderTriangle>[];

    for (final node in world) {
      _collectRenderTriangles(
        node,
        Mat4.identity(),
        viewProj,
        camera,
        lights,
        env,
        size,
        renderTris,
      );
    }

    // Sort by depth (painter's algorithm: far to near)
    renderTris.sort((a, b) => b.depth.compareTo(a.depth));

    // Draw triangles. B: reuse one Path + one Paint across triangles instead of
    // allocating a fresh ui.Path and Paint per triangle each frame.
    final path = Path();
    final triPaint = Paint()..style = PaintingStyle.fill;
    for (final tri in renderTris) {
      path.reset();
      path
        ..moveTo(tri.screenPoints[0].dx, tri.screenPoints[0].dy)
        ..lineTo(tri.screenPoints[1].dx, tri.screenPoints[1].dy)
        ..lineTo(tri.screenPoints[2].dx, tri.screenPoints[2].dy)
        ..close();
      triPaint.color = tri.color;
      canvas.drawPath(path, triPaint);
    }
  }

  _Camera _findCamera(List<dynamic> nodes) {
    for (final node in nodes) {
      if (node['type'] == 'camera') {
        final t = _parseTransform(node['transform']);
        final rotMat = Mat4.fromEulerXYZ(
          t.rotation.x * math.pi / 180.0,
          t.rotation.y * math.pi / 180.0,
          t.rotation.z * math.pi / 180.0,
        );
        final forward = rotMat.transformDirection(const Vec3(0, 0, -1)).normalized;
        final up = rotMat.transformDirection(Vec3.up).normalized;
        return _Camera(
          position: t.position,
          forward: forward,
          up: up,
          fov: (node['fov'] as num?)?.toDouble() ?? 60.0,
          near: (node['near'] as num?)?.toDouble() ?? 0.1,
          far: (node['far'] as num?)?.toDouble() ?? 1000.0,
        );
      }
    }
    // Default camera
    const pos = Vec3(0, 5, 10);
    return _Camera(
      position: pos,
      forward: (Vec3.zero - pos).normalized,
      up: Vec3.up,
    );
  }

  List<_Light> _collectLights(List<dynamic> nodes) {
    final lights = <_Light>[];
    for (final node in nodes) {
      if (node['type'] == 'light') {
        final t = _parseTransform(node['transform']);
        final rotMat = Mat4.fromEulerXYZ(
          t.rotation.x * math.pi / 180.0,
          t.rotation.y * math.pi / 180.0,
          t.rotation.z * math.pi / 180.0,
        );
        final dir = rotMat.transformDirection(const Vec3(0, 0, -1)).normalized;
        lights.add(_Light(
          type: node['light_type'] as String? ?? 'Directional',
          position: t.position,
          direction: dir,
          color: node['color'] != null ? _parseColor3(node['color']) : const Vec3(1, 1, 1),
          intensity: (node['intensity'] as num?)?.toDouble() ?? 1.0,
          range: (node['range'] as num?)?.toDouble(),
        ));
      }
    }
    if (lights.isEmpty) {
      lights.add(const _Light(
        type: 'Directional',
        position: Vec3(5, 10, 5),
        direction: Vec3(-0.41, -0.82, -0.41),
        color: Vec3(1, 1, 1),
        intensity: 1.0,
      ));
    }
    return lights;
  }

  /// Collect environment shading params: ambient, fog (with `fog_type:"linear"`
  /// + `fog_near`), and the vertical sky gradient. Mirrors the Rust renderer.
  _Environment _collectEnvironment(List<dynamic> nodes) {
    for (final node in nodes) {
      if (node['type'] == 'environment') {
        final fogType = node['fog_type'] as String?;
        final fogLinear = fogType != null && fogType.toLowerCase() == 'linear';
        // A `fog_type` implies fog is on even when `fog_enabled` is omitted.
        final fogEnabled = (node['fog_enabled'] as bool? ?? false) || fogType != null;
        (Vec3, Vec3)? sky;
        if (node['sky_color_top'] != null && node['sky_color_bottom'] != null) {
          sky = (_parseColor3(node['sky_color_top']), _parseColor3(node['sky_color_bottom']));
        }
        return _Environment(
          ambientColor:
              node['ambient_light'] != null ? _parseColor3(node['ambient_light']) : const Vec3(1, 1, 1),
          ambientIntensity: (node['ambient_intensity'] as num?)?.toDouble() ?? 0.3,
          fogEnabled: fogEnabled,
          fogLinear: fogLinear,
          fogColor: node['fog_color'] != null ? _parseColor3(node['fog_color']) : const Vec3(0.7, 0.7, 0.8),
          fogNear: (node['fog_near'] as num?)?.toDouble() ?? 0.0,
          fogDistance: (node['fog_distance'] as num?)?.toDouble() ?? 100.0,
          skyGradient: sky,
        );
      }
    }
    return const _Environment();
  }

  Color _vecToColor(Vec3 c) => Color.fromARGB(
        255,
        (c.x.clamp(0.0, 1.0) * 255).round(),
        (c.y.clamp(0.0, 1.0) * 255).round(),
        (c.z.clamp(0.0, 1.0) * 255).round(),
      );

  void _collectRenderTriangles(
    Map<String, dynamic> node,
    Mat4 parentTransform,
    Mat4 viewProj,
    _Camera camera,
    List<_Light> lights,
    _Environment env,
    Size screenSize,
    List<_RenderTriangle> out,
  ) {
    final type = node['type'] as String? ?? '';

    if (type == 'mesh3d') {
      final t = _parseTransform(node['transform']);
      final anim = node['animation'];
      var local = Mat4.fromTransform(t.position, t.rotation, t.scale);

      if (anim != null) {
        local = _applyAnimation(local, anim);
      }

      final world = parentTransform * local;
      final material = _parseMaterial(node['material']);
      final triangles = _generateMeshTriangles(node['mesh']);
      final mvp = viewProj * world;

      for (final tri in triangles) {
        _projectAndAddTriangle(
          tri, world, mvp, camera, lights, material, env, screenSize, out,
        );
      }

      // Render children
      final children = node['children'] as List<dynamic>? ?? [];
      for (final child in children) {
        _collectRenderTriangles(
          child as Map<String, dynamic>, world, viewProj, camera,
          lights, env, screenSize, out,
        );
      }
    } else if (type == 'group') {
      final t = _parseTransform(node['transform']);
      final local = Mat4.fromTransform(t.position, t.rotation, t.scale);
      final world = parentTransform * local;
      final children = node['children'] as List<dynamic>? ?? [];
      for (final child in children) {
        _collectRenderTriangles(
          child as Map<String, dynamic>, world, viewProj, camera,
          lights, env, screenSize, out,
        );
      }
    }
    // camera, light, environment, skybox are non-renderable
  }

  void _projectAndAddTriangle(
    _Triangle tri,
    Mat4 world,
    Mat4 mvp,
    _Camera camera,
    List<_Light> lights,
    _MaterialDef material,
    _Environment env,
    Size screenSize,
    List<_RenderTriangle> out,
  ) {
    // Transform to world space for lighting
    final w0 = world.transformPoint(tri.v0);
    final w1 = world.transformPoint(tri.v1);
    final w2 = world.transformPoint(tri.v2);
    final worldNormal = world.transformDirection(tri.normal).normalized;

    // Clip space
    final c0 = mvp.transformClip(tri.v0);
    final c1 = mvp.transformClip(tri.v1);
    final c2 = mvp.transformClip(tri.v2);

    // Near-plane clipping
    const wClip = 0.001;
    final clips = [c0, c1, c2];
    final inside = [c0[3] > wClip, c1[3] > wClip, c2[3] > wClip];
    final insideCount = inside.where((v) => v).length;

    if (insideCount == 0) return;

    // Compute lighting
    final center = Vec3(
      (w0.x + w1.x + w2.x) / 3,
      (w0.y + w1.y + w2.y) / 3,
      (w0.z + w1.z + w2.z) / 3,
    );
    // Procedural texture sampled at the centroid UV (flat-shaded fallback).
    final centroidUv = Offset(
      (tri.uv0.dx + tri.uv1.dx + tri.uv2.dx) / 3.0,
      (tri.uv0.dy + tri.uv1.dy + tri.uv2.dy) / 3.0,
    );
    final color = _computeLighting(
      center, worldNormal, camera, lights, material, env, centroidUv,
    );

    // Clip and project
    List<List<double>> clipped;
    if (insideCount == 3) {
      clipped = clips;
    } else {
      clipped = _clipTriangleNearPlane(clips, inside, wClip);
      if (clipped.length < 3) return;
    }

    // Fan-triangulate clipped polygon
    for (var k = 1; k < clipped.length - 1; k++) {
      final a = clipped[0];
      final b = clipped[k];
      final c = clipped[k + 1];

      final sa = _ndcToScreen(a, screenSize);
      final sb = _ndcToScreen(b, screenSize);
      final sc = _ndcToScreen(c, screenSize);

      if (sa == null || sb == null || sc == null) continue;

      final depth = (a[2] / a[3] + b[2] / b[3] + c[2] / c[3]) / 3.0;

      out.add(_RenderTriangle([sa, sb, sc], depth, color));
    }
  }

  List<List<double>> _clipTriangleNearPlane(
    List<List<double>> clips, List<bool> inside, double wClip,
  ) {
    final result = <List<double>>[];
    for (var i = 0; i < 3; i++) {
      final j = (i + 1) % 3;
      if (inside[i]) result.add(clips[i]);
      if (inside[i] != inside[j]) {
        final ci = clips[i];
        final cj = clips[j];
        final t = (ci[3] - wClip) / (ci[3] - cj[3]);
        result.add([
          ci[0] + (cj[0] - ci[0]) * t,
          ci[1] + (cj[1] - ci[1]) * t,
          ci[2] + (cj[2] - ci[2]) * t,
          ci[3] + (cj[3] - ci[3]) * t,
        ]);
      }
    }
    return result;
  }

  Offset? _ndcToScreen(List<double> clip, Size size) {
    if (clip[3].abs() < 0.0001) return null;
    final x = clip[0] / clip[3];
    final y = clip[1] / clip[3];
    return Offset(
      (x * 0.5 + 0.5) * size.width,
      (1.0 - (y * 0.5 + 0.5)) * size.height,
    );
  }

  Color _computeLighting(
    Vec3 position, Vec3 normal, _Camera camera,
    List<_Light> lights, _MaterialDef material,
    _Environment env, Offset uv,
  ) {
    // Effective albedo: procedural texture sample (or flat base color).
    final albedo = material.sampleTexture(uv);
    // Emissive scaled by emissive_strength (lets neon/glow push past 1.0).
    final emissive = material.emissive * material.emissiveStrength;

    double r, g, b;

    if (material.unlit) {
      // Self-lit surfaces (paint, neon, tracers) bypass shading.
      r = albedo.x + emissive.x;
      g = albedo.y + emissive.y;
      b = albedo.z + emissive.z;
    } else {
      final n = normal.normalized;
      final viewDir = (camera.position - position).normalized;

      // Ambient
      r = env.ambientColor.x * env.ambientIntensity * albedo.x;
      g = env.ambientColor.y * env.ambientIntensity * albedo.y;
      b = env.ambientColor.z * env.ambientIntensity * albedo.z;

      for (final light in lights) {
        Vec3 lightDir;
        double attenuation;

        if (light.type == 'Directional') {
          lightDir = (-light.direction).normalized;
          attenuation = 1.0;
        } else {
          // Point / Spot
          final toLight = light.position - position;
          final dist = toLight.length;
          lightDir = toLight / dist.clamp(0.001, double.infinity);
          attenuation = 1.0 /
              (1.0 + 0.09 * dist + 0.032 * dist * dist) *
              _rangeFalloff(dist, light.range);
        }

        // Diffuse
        final nDotL = n.dot(lightDir).clamp(0.0, 1.0);
        r += albedo.x * light.color.x * light.intensity * nDotL * attenuation;
        g += albedo.y * light.color.y * light.intensity * nDotL * attenuation;
        b += albedo.z * light.color.z * light.intensity * nDotL * attenuation;

        // Specular (Blinn-Phong)
        final halfVec = (lightDir + viewDir).normalized;
        final nDotH = n.dot(halfVec).clamp(0.0, 1.0);
        final shininess = ((1.0 - material.roughness) * 128.0).clamp(1.0, 128.0);
        final specStrength = material.metallic > 0 ? material.metallic * 0.8 : 0.04;
        final spec = math.pow(nDotH, shininess) * specStrength * attenuation * light.intensity;
        r += light.color.x * spec;
        g += light.color.y * spec;
        b += light.color.z * spec;
      }

      // Emissive
      r += emissive.x;
      g += emissive.y;
      b += emissive.z;
    }

    // Fog: blend toward the fog color by distance from the camera.
    if (env.fogEnabled) {
      final dist = (camera.position - position).length;
      double fogFactor;
      if (env.fogLinear) {
        final far = math.max(env.fogDistance, env.fogNear + 0.001);
        fogFactor = ((dist - env.fogNear) / (far - env.fogNear)).clamp(0.0, 1.0);
      } else {
        final f = (dist / env.fogDistance).clamp(0.0, 1.0);
        fogFactor = f * f;
      }
      r = r + (env.fogColor.x - r) * fogFactor;
      g = g + (env.fogColor.y - g) * fogFactor;
      b = b + (env.fogColor.z - b) * fogFactor;
    }

    return Color.fromARGB(
      (material.alpha * 255).round().clamp(0, 255),
      (r * 255).round().clamp(0, 255),
      (g * 255).round().clamp(0, 255),
      (b * 255).round().clamp(0, 255),
    );
  }

  /// Smooth point/spot-light cutoff (parity with the Rust `range_falloff`):
  /// full strength near the source, fading to zero at `range`. `null` keeps the
  /// unbounded inverse-square falloff.
  double _rangeFalloff(double dist, double? range) {
    if (range == null || range <= 0.0) return 1.0;
    final x = (dist / range).clamp(0.0, 1.0);
    final w = 1.0 - x * x;
    return (w * w).clamp(0.0, 1.0);
  }

  Mat4 _applyAnimation(Mat4 base, Map<String, dynamic> anim) {
    final animType = anim['animation_type'] as Map<String, dynamic>?;
    if (animType == null) return base;

    final duration = (anim['duration'] as num?)?.toDouble() ?? 1.0;
    final looping = anim['looping'] as bool? ?? false;
    final easingStr = anim['easing'] as String? ?? 'Linear';

    double rawProgress;
    if (looping) {
      rawProgress = (_elapsed % duration) / duration;
    } else {
      rawProgress = (_elapsed / duration).clamp(0.0, 1.0);
    }
    final t = _applyEasing(rawProgress, easingStr);

    final type = animType['type'] as String? ?? '';
    switch (type) {
      case 'Rotate':
        final axis = _parseVec3(animType['axis']) ;
        final degrees = (animType['degrees'] as num?)?.toDouble() ?? 360.0;
        final axisN = axis.normalized;
        if (axisN.length < 0.001) return base;
        final angle = degrees * math.pi / 180.0 * t;
        final rot = _rotationFromAxisAngle(axisN, angle);
        return base * rot;
      case 'Bounce':
        final height = (animType['height'] as num?)?.toDouble() ?? 1.0;
        final y = math.sin(t * math.pi) * height;
        return base * Mat4.translation(Vec3(0, y, 0));
      case 'Pulse':
        final minScale = (animType['min_scale'] as num?)?.toDouble() ?? 0.8;
        final maxScale = (animType['max_scale'] as num?)?.toDouble() ?? 1.2;
        final s = minScale + (maxScale - minScale) * (0.5 + 0.5 * math.sin(t * 2 * math.pi));
        return base * Mat4.scale(Vec3(s, s, s));
      case 'Translate':
        final from = _parseVec3(animType['from']);
        final to = _parseVec3(animType['to']);
        final pos = from.lerp(to, t);
        return Mat4.translation(pos);
      case 'Scale':
        final from = _parseVec3(animType['from']);
        final to = _parseVec3(animType['to']);
        final scl = from.lerp(to, t);
        return base * Mat4.scale(scl);
      default:
        return base;
    }
  }

  Mat4 _rotationFromAxisAngle(Vec3 axis, double angle) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    final t = 1.0 - c;
    final x = axis.x, y = axis.y, z = axis.z;
    final m = List.filled(16, 0.0);
    m[0] = t * x * x + c;      m[1] = t * x * y + s * z;  m[2] = t * x * z - s * y;
    m[4] = t * x * y - s * z;  m[5] = t * y * y + c;      m[6] = t * y * z + s * x;
    m[8] = t * x * z + s * y;  m[9] = t * y * z - s * x;  m[10] = t * z * z + c;
    m[15] = 1.0;
    return Mat4._(m);
  }

  double _applyEasing(double p, String easing) {
    switch (easing) {
      case 'EaseIn': return p * p;
      case 'EaseOut': return p * (2 - p);
      case 'EaseInOut':
        return p < 0.5 ? 2 * p * p : -1 + (4 - 2 * p) * p;
      case 'Bounce':
        const n1 = 7.5625, d1 = 2.75;
        if (p < 1 / d1) return n1 * p * p;
        if (p < 2 / d1) { final q = p - 1.5 / d1; return n1 * q * q + 0.75; }
        if (p < 2.5 / d1) { final q = p - 2.25 / d1; return n1 * q * q + 0.9375; }
        final q = p - 2.625 / d1; return n1 * q * q + 0.984375;
      default: return p; // Linear
    }
  }

  // ── Mesh Generation ─────────────────────────────────────────────

  List<_Triangle> _generateMeshTriangles(dynamic mesh) {
    if (mesh is String) {
      if (mesh == 'Cube') return _generateCube(1.0);
      return _generateCube(1.0);
    }
    if (mesh is Map<String, dynamic>) {
      final shape = mesh['shape'] as String? ?? 'Cube';
      switch (shape) {
        case 'Cube': return _generateCube(1.0);
        case 'Sphere':
          final r = (mesh['radius'] as num?)?.toDouble() ?? 1.0;
          // `segments` is the scene3d spelling; accept it as an alias.
          final sub = ((mesh['subdivisions'] ?? mesh['segments']) as num?)?.toInt() ?? 16;
          return _generateSphere(r, sub.clamp(4, 32));
        case 'Plane':
          final s = (mesh['size'] as num?)?.toDouble() ?? 1.0;
          return _generatePlane(s);
        case 'Cylinder':
          final r = (mesh['radius'] as num?)?.toDouble() ?? 0.5;
          final h = (mesh['height'] as num?)?.toDouble() ?? 1.0;
          final seg = (mesh['segments'] as num?)?.toInt() ?? 16;
          return _generateCylinder(r, h, seg.clamp(3, 64));
        case 'Cone':
          final r = (mesh['radius'] as num?)?.toDouble() ?? 0.5;
          final h = (mesh['height'] as num?)?.toDouble() ?? 1.0;
          final seg = (mesh['segments'] as num?)?.toInt() ?? 16;
          return _generateCone(r, h, seg.clamp(3, 64));
        case 'Torus':
          final r = (mesh['radius'] as num?)?.toDouble() ?? 1.0;
          final tr = (mesh['tube_radius'] as num?)?.toDouble() ?? 0.25;
          return _generateTorus(r, tr, 24, 12);
        default: return _generateCube(1.0);
      }
    }
    return _generateCube(1.0);
  }

  List<_Triangle> _generateCube(double size) {
    final h = size / 2;
    final v = [
      // Front
      Vec3(-h,-h,h), Vec3(h,-h,h), Vec3(h,h,h), Vec3(-h,h,h),
      // Back
      Vec3(-h,-h,-h), Vec3(-h,h,-h), Vec3(h,h,-h), Vec3(h,-h,-h),
      // Top
      Vec3(-h,h,-h), Vec3(-h,h,h), Vec3(h,h,h), Vec3(h,h,-h),
      // Bottom
      Vec3(-h,-h,-h), Vec3(h,-h,-h), Vec3(h,-h,h), Vec3(-h,-h,h),
      // Right
      Vec3(h,-h,-h), Vec3(h,h,-h), Vec3(h,h,h), Vec3(h,-h,h),
      // Left
      Vec3(-h,-h,-h), Vec3(-h,-h,h), Vec3(-h,h,h), Vec3(-h,h,-h),
    ];
    final n = [
      const Vec3(0,0,1), const Vec3(0,0,-1), const Vec3(0,1,0),
      const Vec3(0,-1,0), const Vec3(1,0,0), const Vec3(-1,0,0),
    ];
    // Per-corner UVs, matching scene3d's cube layout.
    const uv = [Offset(0, 1), Offset(1, 1), Offset(1, 0), Offset(0, 0)];
    final tris = <_Triangle>[];
    for (var f = 0; f < 6; f++) {
      final b = f * 4;
      tris.add(_Triangle(v[b], v[b+1], v[b+2], n[f], uv0: uv[0], uv1: uv[1], uv2: uv[2]));
      tris.add(_Triangle(v[b], v[b+2], v[b+3], n[f], uv0: uv[0], uv1: uv[2], uv2: uv[3]));
    }
    return tris;
  }

  List<_Triangle> _generateSphere(double radius, int segments) {
    final tris = <_Triangle>[];
    for (var i = 0; i < segments; i++) {
      final theta1 = math.pi * i / segments;
      final theta2 = math.pi * (i + 1) / segments;
      for (var j = 0; j < segments; j++) {
        final phi1 = 2 * math.pi * j / segments;
        final phi2 = 2 * math.pi * (j + 1) / segments;
        final v0 = _spherePoint(radius, theta1, phi1);
        final v1 = _spherePoint(radius, theta2, phi1);
        final v2 = _spherePoint(radius, theta2, phi2);
        final v3 = _spherePoint(radius, theta1, phi2);
        final u0 = Offset(j / segments, i / segments);
        final u1 = Offset(j / segments, (i + 1) / segments);
        final u2 = Offset((j + 1) / segments, (i + 1) / segments);
        final u3 = Offset((j + 1) / segments, i / segments);
        if (i != 0) tris.add(_Triangle(v0, v1, v2, v0.normalized, uv0: u0, uv1: u1, uv2: u2));
        if (i != segments - 1) tris.add(_Triangle(v0, v2, v3, v0.normalized, uv0: u0, uv1: u2, uv2: u3));
      }
    }
    return tris;
  }

  Vec3 _spherePoint(double r, double theta, double phi) => Vec3(
    r * math.sin(theta) * math.cos(phi),
    r * math.cos(theta),
    r * math.sin(theta) * math.sin(phi),
  );

  List<_Triangle> _generatePlane(double size) {
    final h = size / 2;
    const u0 = Offset(0, 0), u1 = Offset(1, 0), u2 = Offset(1, 1), u3 = Offset(0, 1);
    return [
      _Triangle(Vec3(-h,0,-h), Vec3(h,0,-h), Vec3(h,0,h), Vec3.up, uv0: u0, uv1: u1, uv2: u2),
      _Triangle(Vec3(-h,0,-h), Vec3(h,0,h), Vec3(-h,0,h), Vec3.up, uv0: u0, uv1: u2, uv2: u3),
    ];
  }

  List<_Triangle> _generateCylinder(double radius, double height, int segments) {
    final tris = <_Triangle>[];
    final hh = height / 2;
    for (var i = 0; i < segments; i++) {
      final a1 = 2 * math.pi * i / segments;
      final a2 = 2 * math.pi * (i + 1) / segments;
      final x1 = radius * math.cos(a1), z1 = radius * math.sin(a1);
      final x2 = radius * math.cos(a2), z2 = radius * math.sin(a2);
      final n = Vec3((x1+x2)/2, 0, (z1+z2)/2).normalized;
      final uLo = i / segments, uHi = (i + 1) / segments;
      tris.add(_Triangle(Vec3(x1,-hh,z1), Vec3(x2,-hh,z2), Vec3(x2,hh,z2), n,
          uv0: Offset(uLo, 0), uv1: Offset(uHi, 0), uv2: Offset(uHi, 1)));
      tris.add(_Triangle(Vec3(x1,-hh,z1), Vec3(x2,hh,z2), Vec3(x1,hh,z1), n,
          uv0: Offset(uLo, 0), uv1: Offset(uHi, 1), uv2: Offset(uLo, 1)));
      tris.add(_Triangle(Vec3(0,hh,0), Vec3(x1,hh,z1), Vec3(x2,hh,z2), Vec3.up));
      tris.add(_Triangle(Vec3(0,-hh,0), Vec3(x2,-hh,z2), Vec3(x1,-hh,z1), const Vec3(0,-1,0)));
    }
    return tris;
  }

  List<_Triangle> _generateCone(double radius, double height, int segments) {
    final tris = <_Triangle>[];
    final apex = Vec3(0, height, 0);
    for (var i = 0; i < segments; i++) {
      final a1 = 2 * math.pi * i / segments;
      final a2 = 2 * math.pi * (i + 1) / segments;
      final x1 = radius * math.cos(a1), z1 = radius * math.sin(a1);
      final x2 = radius * math.cos(a2), z2 = radius * math.sin(a2);
      final sn = Vec3((x1+x2)/2, radius/height, (z1+z2)/2).normalized;
      tris.add(_Triangle(Vec3(x1,0,z1), Vec3(x2,0,z2), apex, sn));
      tris.add(_Triangle(Vec3.zero, Vec3(x2,0,z2), Vec3(x1,0,z1), const Vec3(0,-1,0)));
    }
    return tris;
  }

  List<_Triangle> _generateTorus(double radius, double tubeRadius, int radial, int tubular) {
    final tris = <_Triangle>[];
    for (var i = 0; i < radial; i++) {
      final t1 = 2 * math.pi * i / radial;
      final t2 = 2 * math.pi * (i + 1) / radial;
      for (var j = 0; j < tubular; j++) {
        final p1 = 2 * math.pi * j / tubular;
        final p2 = 2 * math.pi * (j + 1) / tubular;
        final v00 = _torusPoint(radius, tubeRadius, t1, p1);
        final v10 = _torusPoint(radius, tubeRadius, t2, p1);
        final v11 = _torusPoint(radius, tubeRadius, t2, p2);
        final v01 = _torusPoint(radius, tubeRadius, t1, p2);
        tris.add(_Triangle.fromVertices(v00, v10, v11));
        tris.add(_Triangle.fromVertices(v00, v11, v01));
      }
    }
    return tris;
  }

  Vec3 _torusPoint(double r, double tr, double theta, double phi) {
    final rr = r + tr * math.cos(phi);
    return Vec3(rr * math.cos(theta), tr * math.sin(phi), rr * math.sin(theta));
  }

  // ── Parsers ─────────────────────────────────────────────────────

  Vec3 _parseVec3(dynamic v) {
    if (v == null) return Vec3.zero;
    if (v is Map) {
      return Vec3(
        (v['x'] as num?)?.toDouble() ?? 0,
        (v['y'] as num?)?.toDouble() ?? 0,
        (v['z'] as num?)?.toDouble() ?? 0,
      );
    }
    return Vec3.zero;
  }

  Vec3 _parseColor3(dynamic c) {
    if (c == null) return const Vec3(1, 1, 1);
    if (c is Map) {
      return Vec3(
        (c['r'] as num?)?.toDouble() ?? 1,
        (c['g'] as num?)?.toDouble() ?? 1,
        (c['b'] as num?)?.toDouble() ?? 1,
      );
    }
    return const Vec3(1, 1, 1);
  }

  _TransformDef _parseTransform(dynamic t) {
    if (t == null) return _TransformDef.identity;
    if (t is Map) {
      return _TransformDef(
        position: _parseVec3(t['position']),
        rotation: _parseVec3(t['rotation']),
        scale: t['scale'] != null ? _parseVec3(t['scale']) : const Vec3(1, 1, 1),
      );
    }
    return _TransformDef.identity;
  }

  _MaterialDef _parseMaterial(dynamic m) {
    if (m == null) return _MaterialDef.defaultMat;
    if (m is Map) {
      // Explicit scalar `alpha` wins; otherwise fall back to `base_color.a`.
      final baseA = m['base_color'] != null ? (m['base_color']['a'] as num?)?.toDouble() ?? 1.0 : 1.0;
      return _MaterialDef(
        baseColor: m['base_color'] != null ? _parseColor3(m['base_color']) : const Vec3(0.8, 0.8, 0.8),
        metallic: (m['metallic'] as num?)?.toDouble() ?? 0.0,
        roughness: (m['roughness'] as num?)?.toDouble() ?? 0.5,
        emissive: m['emissive'] != null ? _parseColor3(m['emissive']) : Vec3.zero,
        emissiveStrength: (m['emissive_strength'] as num?)?.toDouble() ?? 1.0,
        alpha: (m['alpha'] as num?)?.toDouble() ?? baseA,
        unlit: m['unlit'] as bool? ?? false,
        texture: m['texture'] as String?,
        textureColor2: m['texture_color2'] != null
            ? _parseColor3(m['texture_color2'])
            : const Vec3(0.3, 0.3, 0.3),
        textureScale: (m['texture_scale'] as num?)?.toDouble() ?? 1.0,
      );
    }
    return _MaterialDef.defaultMat;
  }
}

class _TransformDef {
  final Vec3 position, rotation, scale;
  const _TransformDef({required this.position, required this.rotation, required this.scale});
  static const identity = _TransformDef(position: Vec3.zero, rotation: Vec3.zero, scale: Vec3(1, 1, 1));
}

class _MaterialDef {
  final Vec3 baseColor;
  final double metallic, roughness, alpha, emissiveStrength;
  final Vec3 emissive;
  final bool unlit;
  /// Procedural texture kind: `noise | checkerboard | stripes | gradient` (null = none).
  final String? texture;
  final Vec3 textureColor2;
  final double textureScale;
  const _MaterialDef({
    required this.baseColor, required this.metallic, required this.roughness,
    required this.emissive, required this.alpha,
    this.emissiveStrength = 1.0,
    this.unlit = false,
    this.texture,
    this.textureColor2 = const Vec3(0.3, 0.3, 0.3),
    this.textureScale = 1.0,
  });
  static const defaultMat = _MaterialDef(
    baseColor: Vec3(0.8, 0.8, 0.8), metallic: 0.0, roughness: 0.5,
    emissive: Vec3.zero, alpha: 1.0,
  );

  /// Sample the procedural texture at `uv`, returning the effective albedo.
  /// Mirrors `Material3D.sampleTexture` in scene3d/core.dart and the Rust
  /// `sample_texture_kind`.
  Vec3 sampleTexture(Offset uv) {
    switch (texture) {
      case 'checkerboard':
        final u = (uv.dx * textureScale).floor();
        final v = (uv.dy * textureScale).floor();
        return (u + v) % 2 == 0 ? baseColor : textureColor2;
      case 'stripes':
        final s = (uv.dx * textureScale * 10).floor() % 2 == 0;
        return s ? baseColor : textureColor2;
      case 'gradient':
        return baseColor.lerp(textureColor2, uv.dy);
      case 'noise':
        final n = _simpleNoise(uv.dx * textureScale, uv.dy * textureScale);
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
