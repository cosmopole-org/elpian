/// Canvas-based 3D renderer that uses the core engine types.
///
/// Takes a parsed scene (list of SceneNode, Camera3D, Environment3D, lights)
/// and renders it to a Flutter Canvas using the painter's algorithm with
/// per-vertex PBR-inspired lighting.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Color;
import 'core.dart';

// ════════════════════════════════════════════════════════════════════
//  PROJECTED TRIANGLE (screen-space)
// ════════════════════════════════════════════════════════════════════

class _ScreenTri {
  final List<ui.Offset> pts;
  final Color color;
  final double depth;
  final bool isWireframe;
  final Color? wireColor;

  _ScreenTri(this.pts, this.color, this.depth,
      {this.isWireframe = false, this.wireColor});
}

class _ScreenParticle {
  final ui.Offset center;
  final double radius;
  final Color color;
  final double depth;
  final double rotation;

  _ScreenParticle(this.center, this.radius, this.color, this.depth,
      this.rotation);
}

// ════════════════════════════════════════════════════════════════════
//  SCENE 3D RENDERER
// ════════════════════════════════════════════════════════════════════

class Scene3DRenderer {
  double _elapsed = 0;

  double get elapsed => _elapsed;

  /// Advance the internal clock (called by widget ticker).
  void advanceTime(double dt) {
    _elapsed += dt;
  }

  /// Reset the elapsed time.
  void resetTime() {
    _elapsed = 0;
  }

  /// Main render entry point.
  void render(
    ui.Canvas canvas,
    ui.Size size, {
    required Camera3D camera,
    required Environment3D environment,
    required List<Light3D> lights,
    required List<SceneNode> nodes,
  }) {
    // Sky gradient background
    _drawSkyGradient(canvas, size, environment);

    final aspect = size.width / size.height;
    camera.update(0, _elapsed);
    final view = camera.viewMatrix();
    final proj = camera.projectionMatrix(aspect);
    final vp = proj * view;

    final screenTris = <_ScreenTri>[];
    final screenParticles = <_ScreenParticle>[];

    // Process all scene nodes
    _processNodes(
      nodes, Mat4.identity(), vp, view, size,
      camera, environment, lights,
      screenTris, screenParticles,
    );

    // Sort back-to-front (painter's algorithm)
    screenTris.sort((a, b) => b.depth.compareTo(a.depth));
    screenParticles.sort((a, b) => b.depth.compareTo(a.depth));

    // Draw triangles
    final triPaint = ui.Paint()..style = ui.PaintingStyle.fill;
    final wirePaint = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (final st in screenTris) {
      final path = ui.Path()
        ..moveTo(st.pts[0].dx, st.pts[0].dy)
        ..lineTo(st.pts[1].dx, st.pts[1].dy)
        ..lineTo(st.pts[2].dx, st.pts[2].dy)
        ..close();

      if (st.isWireframe) {
        wirePaint.color = st.wireColor ?? st.color;
        canvas.drawPath(path, wirePaint);
      } else {
        triPaint.color = st.color;
        canvas.drawPath(path, triPaint);
      }
    }

    // Draw particles (as circles, sorted by depth)
    final particlePaint = ui.Paint()..style = ui.PaintingStyle.fill;
    for (final sp in screenParticles) {
      particlePaint.color = sp.color;
      canvas.drawCircle(sp.center, sp.radius, particlePaint);
    }
  }

  void _drawSkyGradient(ui.Canvas canvas, ui.Size size, Environment3D env) {
    final rect = ui.Rect.fromLTWH(0, 0, size.width, size.height);
    final gradient = ui.Gradient.linear(
      ui.Offset(0, 0),
      ui.Offset(0, size.height),
      [
        _vec3ToColor(env.skyColorTop),
        _vec3ToColor(env.skyColorBottom),
      ],
    );
    canvas.drawRect(rect, ui.Paint()..shader = gradient);
  }

  void _processNodes(
    List<SceneNode> nodes,
    Mat4 parentTransform,
    Mat4 vp,
    Mat4 view,
    ui.Size size,
    Camera3D camera,
    Environment3D environment,
    List<Light3D> lights,
    List<_ScreenTri> screenTris,
    List<_ScreenParticle> screenParticles,
  ) {
    for (final node in nodes) {
      if (!node.visible) continue;

      var localXform = node.localTransform();

      // Apply animations
      if (node.animations != null) {
        for (final anim in node.animations!) {
          localXform = anim.evaluate(_elapsed, localXform);
        }
      }

      final worldXform = parentTransform * localXform;

      // Apply physics
      if (node.rigidBody != null && !node.rigidBody!.isStatic) {
        node.position = node.rigidBody!.applyPhysics(
          node.position, 1.0 / 60.0, environment.gravity,
        );
      }

      switch (node.type) {
        case 'mesh3d':
          _renderMesh(
            node, worldXform, vp, view, size,
            camera, environment, lights, screenTris,
          );
          break;
        case 'particles':
          _renderParticles(
            node, worldXform, vp, size, camera, screenParticles,
          );
          break;
      }

      // Process children
      if (node.children.isNotEmpty) {
        _processNodes(
          node.children, worldXform, vp, view, size,
          camera, environment, lights,
          screenTris, screenParticles,
        );
      }
    }
  }

  void _renderMesh(
    SceneNode node,
    Mat4 worldXform,
    Mat4 vp,
    Mat4 view,
    ui.Size size,
    Camera3D camera,
    Environment3D environment,
    List<Light3D> lights,
    List<_ScreenTri> screenTris,
  ) {
    // Generate or use cached mesh
    final mesh = node.mesh ?? _generateMesh(node.meshType, node.meshParams);
    if (mesh == null) return;

    final mat = node.material ?? const Material3D();
    final halfW = size.width / 2;
    final halfH = size.height / 2;
    final nearPlane = camera.near;

    for (final tri in mesh.triangles) {
      // Transform vertices to world space
      final wp0 = worldXform.transformPoint(tri.v0.position);
      final wp1 = worldXform.transformPoint(tri.v1.position);
      final wp2 = worldXform.transformPoint(tri.v2.position);

      // Transform normals
      final wn0 = worldXform.transformDir(tri.v0.normal).normalized;
      final wn1 = worldXform.transformDir(tri.v1.normal).normalized;
      final wn2 = worldXform.transformDir(tri.v2.normal).normalized;

      // Compute lighting at each vertex
      final c0 = _computeLighting(wp0, wn0, tri.v0.uv, mat, environment, lights, camera.position);
      final c1 = _computeLighting(wp1, wn1, tri.v1.uv, mat, environment, lights, camera.position);
      final c2 = _computeLighting(wp2, wn2, tri.v2.uv, mat, environment, lights, camera.position);

      // Project to clip space
      final clip0 = vp.transformVec4(wp0);
      final clip1 = vp.transformVec4(wp1);
      final clip2 = vp.transformVec4(wp2);

      // Near-plane clipping: collect vertices with their w values
      final clipVerts = [clip0, clip1, clip2];
      final colors = [c0, c1, c2];
      final clipped = _clipNearPlane(clipVerts, colors, nearPlane);
      if (clipped == null || clipped.verts.isEmpty) continue;

      // Perspective divide and screen mapping for clipped triangles
      for (var i = 0; i < clipped.verts.length - 2; i++) {
        final cvs = [clipped.verts[0], clipped.verts[i + 1], clipped.verts[i + 2]];
        final cls = [clipped.colors[0], clipped.colors[i + 1], clipped.colors[i + 2]];

        final screenPts = <ui.Offset>[];
        var avgDepth = 0.0;
        var allVisible = true;

        for (final cv in cvs) {
          if (cv.w <= 0.0001) {
            allVisible = false;
            break;
          }
          final ndc = cv.perspectiveDivide();
          // Frustum cull (loose)
          if (ndc.x < -1.5 || ndc.x > 1.5 || ndc.y < -1.5 || ndc.y > 1.5) {
            allVisible = false;
            break;
          }
          screenPts.add(ui.Offset(
            (ndc.x * 0.5 + 0.5) * size.width,
            (0.5 - ndc.y * 0.5) * size.height,
          ));
          avgDepth += ndc.z;
        }

        if (!allVisible || screenPts.length < 3) continue;
        avgDepth /= 3.0;

        // Back-face culling (unless double-sided)
        final edge1 = screenPts[1] - screenPts[0];
        final edge2 = screenPts[2] - screenPts[0];
        final cross = edge1.dx * edge2.dy - edge1.dy * edge2.dx;
        if (cross > 0 && !mat.doubleSided) continue;

        // Average vertex colors
        final avgR = (cls[0].x + cls[1].x + cls[2].x) / 3.0;
        final avgG = (cls[0].y + cls[1].y + cls[2].y) / 3.0;
        final avgB = (cls[0].z + cls[1].z + cls[2].z) / 3.0;

        // Apply fog
        final triCenter = (wp0 + wp1 + wp2) / 3.0;
        final dist = (triCenter - camera.position).length;
        final fogF = environment.fogFactor(dist);

        final finalR = avgR * fogF + environment.fogColor.x * (1 - fogF);
        final finalG = avgG * fogF + environment.fogColor.y * (1 - fogF);
        final finalB = avgB * fogF + environment.fogColor.z * (1 - fogF);

        final alpha = mat.alphaMode == AlphaMode.blend ? mat.alpha : 1.0;
        if (mat.alphaMode == AlphaMode.cutoff && mat.alpha < mat.alphaCutoff) continue;

        final color = Color.fromARGB(
          (alpha * 255).round().clamp(0, 255),
          (finalR * 255).round().clamp(0, 255),
          (finalG * 255).round().clamp(0, 255),
          (finalB * 255).round().clamp(0, 255),
        );

        screenTris.add(_ScreenTri(
          screenPts, color, avgDepth,
          isWireframe: mat.wireframe,
          wireColor: mat.wireframe ? color : null,
        ));
      }
    }
  }

  Vec3 _computeLighting(
    Vec3 worldPos,
    Vec3 worldNormal,
    Vec2 uv,
    Material3D mat,
    Environment3D env,
    List<Light3D> lights,
    Vec3 cameraPos,
  ) {
    if (mat.unlit) {
      return mat.sampleTexture(uv) + mat.emissive * mat.emissiveStrength;
    }

    final baseColor = mat.sampleTexture(uv);
    final viewDir = (cameraPos - worldPos).normalized;

    // Ambient
    var result = baseColor.scale(env.ambientColor) * env.ambientIntensity;

    for (final light in lights) {
      Vec3 lightDir;
      double attenuation = 1.0;

      if (light.type == LightType.directional) {
        lightDir = (-light.direction).normalized;
      } else if (light.type == LightType.point) {
        final toLight = light.position - worldPos;
        final dist = toLight.length;
        lightDir = toLight / (dist > 0.001 ? dist : 1.0);
        attenuation = 1.0 / (1.0 + dist * dist / (light.range * light.range));
      } else if (light.type == LightType.spot) {
        final toLight = light.position - worldPos;
        final dist = toLight.length;
        lightDir = toLight / (dist > 0.001 ? dist : 1.0);
        final spotAngle = math.acos(lightDir.dot((-light.direction).normalized).clamp(-1, 1));
        final outerRad = light.outerConeAngle * math.pi / 180;
        final innerRad = light.innerConeAngle * math.pi / 180;
        if (spotAngle > outerRad) continue;
        final spotFade = ((outerRad - spotAngle) / (outerRad - innerRad)).clamp(0, 1);
        attenuation = spotFade / (1.0 + dist * dist / (light.range * light.range));
      } else {
        lightDir = Vec3.up;
      }

      final nDotL = worldNormal.dot(lightDir).clamp(0, 1);
      final lightColor = light.color * light.intensity * attenuation;

      // Diffuse (Lambertian)
      final diffuse = baseColor.scale(lightColor) * nDotL;

      // Specular (Blinn-Phong with roughness)
      final halfV = (lightDir + viewDir).normalized;
      final nDotH = worldNormal.dot(halfV).clamp(0, 1);
      final shininess = (1.0 - mat.roughness) * 128.0 + 2.0;
      final specStrength = mat.metallic * 0.8 + 0.2;
      final specular = lightColor * (math.pow(nDotH, shininess) * specStrength * nDotL);

      result = result + diffuse + specular;
    }

    // Emissive
    result = result + mat.emissive * mat.emissiveStrength;

    // Clamp
    return Vec3(
      result.x.clamp(0, 1),
      result.y.clamp(0, 1),
      result.z.clamp(0, 1),
    );
  }

  _ClippedResult? _clipNearPlane(List<Vec4> verts, List<Vec3> colors, double near) {
    // Simple near-plane clip: vertices with w > near pass
    final inside = <int>[];
    final outside = <int>[];
    for (var i = 0; i < verts.length; i++) {
      if (verts[i].w > near) {
        inside.add(i);
      } else {
        outside.add(i);
      }
    }

    if (inside.length == 3) return _ClippedResult(verts, colors);
    if (inside.isEmpty) return null;

    // Clip: generate new vertices at the near plane
    final outVerts = <Vec4>[];
    final outColors = <Vec3>[];

    for (var i = 0; i < 3; i++) {
      final j = (i + 1) % 3;
      final vi = verts[i], vj = verts[j];
      final ci = colors[i], cj = colors[j];
      final wi = vi.w, wj = vj.w;

      if (wi > near) {
        outVerts.add(vi);
        outColors.add(ci);
      }

      // Edge crosses near plane?
      if ((wi > near) != (wj > near)) {
        final t = (near - wi) / (wj - wi);
        outVerts.add(Vec4(
          vi.x + t * (vj.x - vi.x),
          vi.y + t * (vj.y - vi.y),
          vi.z + t * (vj.z - vi.z),
          vi.w + t * (vj.w - vi.w),
        ));
        outColors.add(ci.lerp(cj, t));
      }
    }

    if (outVerts.length < 3) return null;
    return _ClippedResult(outVerts, outColors);
  }

  void _renderParticles(
    SceneNode node,
    Mat4 worldXform,
    Mat4 vp,
    ui.Size size,
    Camera3D camera,
    List<_ScreenParticle> screenParticles,
  ) {
    final emitter = node.emitter;
    if (emitter == null) return;

    final emitterPos = worldXform.transformPoint(Vec3.zero);
    emitter.update(1.0 / 60.0, emitterPos);

    for (final p in emitter.particles) {
      final clip = vp.transformVec4(p.position);
      if (clip.w <= 0.001) continue;
      final ndc = clip.perspectiveDivide();
      if (ndc.x < -1.5 || ndc.x > 1.5 || ndc.y < -1.5 || ndc.y > 1.5) continue;

      final sx = (ndc.x * 0.5 + 0.5) * size.width;
      final sy = (0.5 - ndc.y * 0.5) * size.height;

      final pSize = emitter.getParticleSize(p);
      final screenRadius = (pSize * size.height / (clip.w * 2)).clamp(0.5, 50.0);
      final pColor = emitter.getParticleColor(p);
      final pAlpha = emitter.getParticleAlpha(p);

      final color = Color.fromARGB(
        (pAlpha * 255).round().clamp(0, 255),
        (pColor.x * 255).round().clamp(0, 255),
        (pColor.y * 255).round().clamp(0, 255),
        (pColor.z * 255).round().clamp(0, 255),
      );

      screenParticles.add(_ScreenParticle(
        ui.Offset(sx, sy), screenRadius, color, ndc.z, p.rotation,
      ));
    }
  }

  Mesh? _generateMesh(String? meshType, Map<String, dynamic>? params) {
    if (meshType == null) return null;
    final p = params ?? {};

    switch (meshType) {
      case 'Cube':
        return MeshGen.cube(size: _d(p['size'], 1.0));
      case 'Sphere':
        return MeshGen.sphere(
          radius: _d(p['radius'], 0.5),
          segments: _i(p['subdivisions'], _i(p['segments'], 16)),
        );
      case 'Plane':
        return MeshGen.plane(size: _d(p['size'], 10.0));
      case 'Cylinder':
        return MeshGen.cylinder(
          radius: _d(p['radius'], 0.5),
          height: _d(p['height'], 1.0),
          segments: _i(p['segments'], 16),
        );
      case 'Cone':
        return MeshGen.cone(
          radius: _d(p['radius'], 0.5),
          height: _d(p['height'], 1.0),
          segments: _i(p['segments'], 16),
        );
      case 'Torus':
        return MeshGen.torus(
          majorRadius: _d(p['major_radius'], 1.0),
          tubeRadius: _d(p['tube_radius'], 0.3),
          radialSegments: _i(p['radial_segments'], 16),
          tubularSegments: _i(p['tubular_segments'], 24),
        );
      case 'Capsule':
        return MeshGen.capsule(
          radius: _d(p['radius'], 0.5),
          height: _d(p['height'], 1.0),
          segments: _i(p['segments'], 16),
        );
      case 'Pyramid':
        return MeshGen.pyramid(
          base: _d(p['base'], 1.0),
          height: _d(p['height'], 1.0),
        );
      case 'Wedge':
        return MeshGen.wedge(
          width: _d(p['width'], 1.0),
          height: _d(p['height'], 1.0),
          depth: _d(p['depth'], 1.0),
        );
      case 'IcoSphere':
        return MeshGen.icosphere(
          radius: _d(p['radius'], 0.5),
          subdivisions: _i(p['subdivisions'], 2),
        );
      case 'Billboard':
        return MeshGen.billboard(
          width: _d(p['width'], 1.0),
          height: _d(p['height'], 1.0),
        );
      default:
        return MeshGen.cube(size: 1.0);
    }
  }

  static double _d(dynamic v, double def) =>
      (v as num?)?.toDouble() ?? def;
  static int _i(dynamic v, int def) => (v as num?)?.toInt() ?? def;
}

class _ClippedResult {
  final List<Vec4> verts;
  final List<Vec3> colors;
  _ClippedResult(this.verts, this.colors);
}

Color _vec3ToColor(Vec3 c) => Color.fromARGB(
      255,
      (c.x * 255).round().clamp(0, 255),
      (c.y * 255).round().clamp(0, 255),
      (c.z * 255).round().clamp(0, 255),
    );
