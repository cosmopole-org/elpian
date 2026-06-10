/// Canvas-based 3D renderer that uses the core engine types.
///
/// Takes a parsed scene (list of SceneNode, Camera3D, Environment3D, lights)
/// and renders it to a Flutter Canvas using the painter's algorithm with
/// per-vertex PBR-inspired lighting.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Color;
import '../diagnostics/elpian_trace.dart';
import 'core.dart';
import 'gltf/gltf_model.dart';
import 'gltf/model_cache.dart';

// ════════════════════════════════════════════════════════════════════
//  PROJECTED PRIMITIVES (screen-space)
// ════════════════════════════════════════════════════════════════════

/// Anything that can be depth-sorted into the painter's-algorithm draw list.
abstract class _Drawable {
  double get depth;
}

class _ScreenTri implements _Drawable {
  final List<ui.Offset> pts;
  final Color color;
  @override
  final double depth;
  final bool isWireframe;
  final Color? wireColor;

  _ScreenTri(this.pts, this.color, this.depth,
      {this.isWireframe = false, this.wireColor});
}

/// A batched, pre-sorted set of triangles from a single glTF primitive,
/// drawn in one [ui.Canvas.drawVertices] call. Carries an optional image
/// shader for texturing; per-vertex colours supply lighting (multiplied with
/// the texture via [ui.BlendMode.modulate]).
class _ModelBatch implements _Drawable {
  final ui.Vertices vertices;
  final ui.ImageShader? shader;
  @override
  final double depth;

  _ModelBatch(this.vertices, this.shader, this.depth);
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

/// Baked world-space geometry for a `static` node: triangles already
/// transformed to world space and lit by the (unchanging) lights, plus a
/// bounding sphere for frustum culling. Computed once and reused every frame —
/// only re-projection (which depends on the moving camera) happens per frame.
class _StaticMesh {
  final List<Vec3> pos; // 3 world positions per triangle (flattened)
  final List<Vec3> col; // 3 lit colours per triangle (flattened, pre-fog)
  final Vec3 center;
  final double radius;
  _StaticMesh(this.pos, this.col, this.center, this.radius);

  // Projected-triangle cache: a static node's screen triangles only change when
  // the view-projection matrix or the viewport does. While the camera is still
  // (the common case — a fixed-camera city/world with at most some animated
  // units), reusing this list skips re-projecting thousands of vertices per
  // frame. Keyed by a snapshot of `vp.m` (16 doubles) and the surface size.
  List<_ScreenTri>? cachedTris;
  List<double>? cachedVp;
  double cachedW = -1;
  double cachedH = -1;
}

/// Six view-frustum planes (a·x+b·y+c·z+d), extracted from a view-projection
/// matrix (Gribb–Hartmann). A point is inside when every plane yields ≥ 0.
class _Frustum {
  final Float64List planes; // 6 × (a,b,c,d), normalized
  _Frustum(this.planes);

  factory _Frustum.fromVp(Mat4 vp) {
    final m = vp.m; // column-major
    // Rows of vp: rowR = (m[R], m[R+4], m[R+8], m[R+12]).
    final p = Float64List(24);
    void set(int idx, double a, double b, double c, double d) {
      final len = math.sqrt(a * a + b * b + c * c);
      final inv = len > 1e-9 ? 1.0 / len : 1.0;
      p[idx] = a * inv;
      p[idx + 1] = b * inv;
      p[idx + 2] = c * inv;
      p[idx + 3] = d * inv;
    }

    final r0a = m[0], r0b = m[4], r0c = m[8], r0d = m[12];
    final r1a = m[1], r1b = m[5], r1c = m[9], r1d = m[13];
    final r2a = m[2], r2b = m[6], r2c = m[10], r2d = m[14];
    final r3a = m[3], r3b = m[7], r3c = m[11], r3d = m[15];
    set(0, r3a + r0a, r3b + r0b, r3c + r0c, r3d + r0d); // left
    set(4, r3a - r0a, r3b - r0b, r3c - r0c, r3d - r0d); // right
    set(8, r3a + r1a, r3b + r1b, r3c + r1c, r3d + r1d); // bottom
    set(12, r3a - r1a, r3b - r1b, r3c - r1c, r3d - r1d); // top
    set(16, r3a + r2a, r3b + r2b, r3c + r2c, r3d + r2d); // near
    set(20, r3a - r2a, r3b - r2b, r3c - r2c, r3d - r2d); // far
    return _Frustum(p);
  }

  /// True if the sphere lies entirely outside the frustum (safe to skip).
  bool sphereOutside(Vec3 c, double r) {
    for (var k = 0; k < 24; k += 4) {
      final d = planes[k] * c.x + planes[k + 1] * c.y + planes[k + 2] * c.z + planes[k + 3];
      if (d < -r) return true;
    }
    return false;
  }
}

class Scene3DRenderer {
  double _elapsed = 0;

  /// View frustum for the current frame, used to cull static nodes.
  _Frustum? _frustum;

  /// Whether the most recent [render] drew any time-varying content — an
  /// animated camera, a particle system, a keyframe-animated node, or an
  /// animated glTF clip. When this is false the scene is fully static and the
  /// host widget can stop repainting it (see `GameSceneWidget._onTick`) instead
  /// of re-rasterizing an identical frame every tick.
  bool _dynamic = false;
  bool get hadDynamicContent => _dynamic;

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
    final _frameSw = ElpianTrace.enabled ? (Stopwatch()..start()) : null;
    // Assume static until we encounter time-varying content this frame.
    _dynamic = false;
    // An animated camera (orbit/follow/flythrough) or an active shake keeps the
    // scene moving every frame even when nothing else does.
    if (camera.mode != CameraMode.fixed || camera.shakeAmount > 0) {
      _dynamic = true;
    }
    // Sky gradient background
    _drawSkyGradient(canvas, size, environment);

    final aspect = size.width / size.height;
    camera.update(0, _elapsed);
    final view = camera.viewMatrix();
    final proj = camera.projectionMatrix(aspect);
    final vp = proj * view;
    _frustum = _Frustum.fromVp(vp);

    final screenTris = <_ScreenTri>[];
    final screenBatches = <_ModelBatch>[];
    final screenParticles = <_ScreenParticle>[];

    // Process all scene nodes
    _processNodes(
      nodes, Mat4.identity(), vp, view, size,
      camera, environment, lights,
      screenTris, screenBatches, screenParticles,
    );

    // Merge primitive triangles and model batches, then sort back-to-front
    // (painter's algorithm) so glTF characters interleave correctly with the
    // procedural world geometry.
    final drawables = <_Drawable>[...screenTris, ...screenBatches];
    drawables.sort((a, b) => b.depth.compareTo(a.depth));
    screenParticles.sort((a, b) => b.depth.compareTo(a.depth));

    final triPaint = ui.Paint()..style = ui.PaintingStyle.fill;
    final wirePaint = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.0;
    // Reusable paint for model batches (shader swapped per textured batch).
    final batchPaint = ui.Paint()
      ..style = ui.PaintingStyle.fill
      ..color = const Color(0xFFFFFFFF);

    // B: reuse a single Path across triangles (reset instead of reallocating
    // a new ui.Path per triangle each frame).
    final path = ui.Path();

    // C: batch consecutive opaque, solid-fill triangles into ONE
    // `drawVertices` call instead of one `drawPath` per triangle. The world
    // scaffold is thousands of such triangles, so this collapses thousands of
    // per-frame draw ops into a handful — the dominant cost of the software
    // painter. Depth order (painter's algorithm) is preserved because the batch
    // is flushed whenever a draw that must interleave by depth is hit: a model
    // batch, a wireframe edge, or a translucent triangle.
    final batchPos = <ui.Offset>[];
    final batchCol = <Color>[];
    void flushTriBatch() {
      if (batchPos.isEmpty) return;
      final verts = ui.Vertices(
        ui.VertexMode.triangles,
        List<ui.Offset>.of(batchPos),
        colors: List<Color>.of(batchCol),
      );
      batchPaint
        ..shader = null
        ..color = const Color(0xFFFFFFFF);
      // modulate(vertexColor, white) == vertexColor → flat per-triangle colour.
      canvas.drawVertices(verts, ui.BlendMode.modulate, batchPaint);
      batchPos.clear();
      batchCol.clear();
    }

    void strokeTri(_ScreenTri st, ui.Paint paint) {
      path.reset();
      path
        ..moveTo(st.pts[0].dx, st.pts[0].dy)
        ..lineTo(st.pts[1].dx, st.pts[1].dy)
        ..lineTo(st.pts[2].dx, st.pts[2].dy)
        ..close();
      canvas.drawPath(path, paint);
    }

    for (final d in drawables) {
      if (d is _ModelBatch) {
        flushTriBatch();
        batchPaint.shader = d.shader;
        canvas.drawVertices(d.vertices, ui.BlendMode.modulate, batchPaint);
        continue;
      }
      final st = d as _ScreenTri;

      if (st.isWireframe) {
        flushTriBatch();
        wirePaint.color = st.wireColor ?? st.color;
        strokeTri(st, wirePaint);
        continue;
      }

      // Translucent fills can't join an opaque batch without breaking the
      // back-to-front blend, so draw them individually (after flushing).
      if (st.color.a < 1.0) {
        flushTriBatch();
        triPaint.color = st.color;
        strokeTri(st, triPaint);
        continue;
      }

      // Opaque solid fill → accumulate into the current vertex batch.
      batchPos
        ..add(st.pts[0])
        ..add(st.pts[1])
        ..add(st.pts[2]);
      batchCol
        ..add(st.color)
        ..add(st.color)
        ..add(st.color);
    }
    flushTriBatch();

    // Draw particles (as circles, sorted by depth)
    final particlePaint = ui.Paint()..style = ui.PaintingStyle.fill;
    for (final sp in screenParticles) {
      particlePaint.color = sp.color;
      canvas.drawCircle(sp.center, sp.radius, particlePaint);
    }

    if (_frameSw != null) {
      _frameSw.stop();
      _frameCount++;
      final ms = _frameSw.elapsedMilliseconds;
      // Log the first few frames (cold paints after a rebuild) and any slow one.
      if (_frameCount <= 5 || ms >= 30) {
        ElpianTrace.mark('scene.render frame#$_frameCount '
            '${ms}ms (nodes=${nodes.length}, tris=${screenTris.length})');
      }
    }
  }

  int _frameCount = 0;

  void _drawSkyGradient(ui.Canvas canvas, ui.Size size, Environment3D env) {
    final rect = ui.Rect.fromLTWH(0, 0, size.width, size.height);
    final gradient = ui.Gradient.linear(
      const ui.Offset(0, 0),
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
    List<_ModelBatch> screenBatches,
    List<_ScreenParticle> screenParticles,
  ) {
    for (final node in nodes) {
      if (!node.visible) continue;

      var localXform = node.localTransform();

      // Apply animations
      if (node.animations != null && node.animations!.isNotEmpty) {
        _dynamic = true;
        for (final anim in node.animations!) {
          localXform = anim.evaluate(_elapsed, localXform);
        }
      }

      final worldXform = parentTransform * localXform;

      // Apply physics
      if (node.rigidBody != null && !node.rigidBody!.isStatic) {
        _dynamic = true;
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
        case 'model3d':
        case 'gltf':
          _renderModel(
            node, worldXform, vp, size,
            camera, environment, lights, screenTris, screenBatches,
          );
          break;
        case 'particles':
          _dynamic = true;
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
          screenTris, screenBatches, screenParticles,
        );
      }
    }
  }

  /// Cheap element-wise equality for two 16-element view-projection matrices.
  static bool _vpEquals(List<double>? a, List<double> b) {
    if (a == null || a.length != b.length) return false;
    for (var i = 0; i < b.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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
    final mat = node.material ?? const Material3D();

    // Static fast path: bake world-space lit geometry once, then each frame
    // frustum-cull the whole node and only re-project its triangles.
    if (node.isStatic) {
      var baked = node.renderCache as _StaticMesh?;
      if (baked == null) {
        final mesh = node.mesh ?? _generateMesh(node.meshType, node.meshParams);
        if (mesh == null) return;
        baked = _bakeStatic(mesh, mat, worldXform, environment, lights);
        node.renderCache = baked;
      }
      if (_frustum != null && _frustum!.sphereOutside(baked.center, baked.radius)) {
        return;
      }
      // Reuse the cached projection while the camera and viewport are unchanged.
      if (baked.cachedTris != null &&
          baked.cachedW == size.width &&
          baked.cachedH == size.height &&
          _vpEquals(baked.cachedVp, vp.m)) {
        screenTris.addAll(baked.cachedTris!);
        return;
      }
      final projected = <_ScreenTri>[];
      for (var i = 0; i < baked.pos.length; i += 3) {
        _projectTri(
          baked.pos[i], baked.pos[i + 1], baked.pos[i + 2],
          baked.col[i], baked.col[i + 1], baked.col[i + 2],
          mat, vp, size, camera, environment, projected,
        );
      }
      baked.cachedTris = projected;
      baked.cachedVp = List<double>.from(vp.m);
      baked.cachedW = size.width;
      baked.cachedH = size.height;
      screenTris.addAll(projected);
      return;
    }

    // Generate or use cached mesh
    final mesh = node.mesh ?? _generateMesh(node.meshType, node.meshParams);
    if (mesh == null) return;
    _emitMeshTris(
      mesh, mat, worldXform, vp, size, camera, environment, lights, screenTris,
    );
  }

  /// Bakes a mesh's triangles into world space with per-vertex lighting applied
  /// (specular omitted — it is view-dependent and negligible for the
  /// high-roughness static world). Reused every frame; see [_StaticMesh].
  _StaticMesh _bakeStatic(
    Mesh mesh,
    Material3D mat,
    Mat4 worldXform,
    Environment3D environment,
    List<Light3D> lights,
  ) {
    final pos = <Vec3>[];
    final col = <Vec3>[];
    var sx = 0.0, sy = 0.0, sz = 0.0;
    for (final tri in mesh.triangles) {
      final wp0 = worldXform.transformPoint(tri.v0.position);
      final wp1 = worldXform.transformPoint(tri.v1.position);
      final wp2 = worldXform.transformPoint(tri.v2.position);
      final wn0 = worldXform.transformDir(tri.v0.normal).normalized;
      final wn1 = worldXform.transformDir(tri.v1.normal).normalized;
      final wn2 = worldXform.transformDir(tri.v2.normal).normalized;
      col.add(_computeLighting(
          wp0, wn0, tri.v0.uv, mat, environment, lights, wp0, includeSpecular: false));
      col.add(_computeLighting(
          wp1, wn1, tri.v1.uv, mat, environment, lights, wp1, includeSpecular: false));
      col.add(_computeLighting(
          wp2, wn2, tri.v2.uv, mat, environment, lights, wp2, includeSpecular: false));
      pos.add(wp0);
      pos.add(wp1);
      pos.add(wp2);
      sx += wp0.x + wp1.x + wp2.x;
      sy += wp0.y + wp1.y + wp2.y;
      sz += wp0.z + wp1.z + wp2.z;
    }
    if (pos.isEmpty) {
      return _StaticMesh(pos, col, Vec3.zero, 0);
    }
    final n = pos.length;
    final center = Vec3(sx / n, sy / n, sz / n);
    var r2 = 0.0;
    for (final wp in pos) {
      final dx = wp.x - center.x, dy = wp.y - center.y, dz = wp.z - center.z;
      final d = dx * dx + dy * dy + dz * dz;
      if (d > r2) r2 = d;
    }
    return _StaticMesh(pos, col, center, math.sqrt(r2));
  }

  /// Transforms, lights, clips and projects a [Mesh]'s triangles into
  /// [screenTris]. Shared by procedural [SceneNode]s and the loading
  /// placeholder drawn while a glTF model streams in.
  void _emitMeshTris(
    Mesh mesh,
    Material3D mat,
    Mat4 worldXform,
    Mat4 vp,
    ui.Size size,
    Camera3D camera,
    Environment3D environment,
    List<Light3D> lights,
    List<_ScreenTri> screenTris,
  ) {
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

      _projectTri(
        wp0, wp1, wp2, c0, c1, c2,
        mat, vp, size, camera, environment, screenTris,
      );
    }
  }

  /// Clips (near plane), perspective-divides, back-face culls, fogs and emits a
  /// single world-space triangle with per-vertex colours. Shared by the dynamic
  /// mesh path ([_emitMeshTris]) and the baked static path ([_renderMesh]).
  void _projectTri(
    Vec3 wp0, Vec3 wp1, Vec3 wp2,
    Vec3 c0, Vec3 c1, Vec3 c2,
    Material3D mat,
    Mat4 vp,
    ui.Size size,
    Camera3D camera,
    Environment3D environment,
    List<_ScreenTri> screenTris,
  ) {
    final nearPlane = camera.near;

    // Project to clip space
    final clip0 = vp.transformVec4(wp0);
    final clip1 = vp.transformVec4(wp1);
    final clip2 = vp.transformVec4(wp2);

    // Frustum clipping (near plane + the four side planes). Side clipping is
    // what keeps huge floor/sea planes visible: a ground quad's corners can sit
    // far outside NDC while its surface fills the whole viewport, so whole-
    // triangle rejection must only happen for triangles entirely outside.
    final clipVerts = [clip0, clip1, clip2];
    final colors = [c0, c1, c2];
    final clipped = _clipFrustum(clipVerts, colors, nearPlane);
    if (clipped == null || clipped.verts.isEmpty) return;

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

  // ════════════════════════════════════════════════════════════════════
  //  GLTF MODEL RENDERING (skinned, animated, textured)
  // ════════════════════════════════════════════════════════════════════

  /// Renders a `model3d`/`gltf` node. Streams the model in via
  /// [GltfModelCache]; until it is ready a capsule placeholder is drawn so the
  /// character is never invisible. Once loaded, the requested animation clip is
  /// sampled at the node's time, the skeleton is posed, vertices are skinned on
  /// the CPU, lit and projected, then each primitive is emitted as one batched
  /// [ui.Canvas.drawVertices] call.
  void _renderModel(
    SceneNode node,
    Mat4 worldXform,
    Mat4 vp,
    ui.Size size,
    Camera3D camera,
    Environment3D environment,
    List<Light3D> lights,
    List<_ScreenTri> screenTris,
    List<_ModelBatch> screenBatches,
  ) {
    final url = node.gltfUrl;
    if (url == null) return;
    final model = GltfModelCache.instance.get(url);

    if (model == null) {
      // A model that is still loading must keep the scene repainting so it pops
      // in the moment its bytes arrive (otherwise idle-gating would freeze the
      // frame on the placeholder forever).
      if (GltfModelCache.instance.statusOf(url) != GltfLoadStatus.failed) {
        _dynamic = true;
      }
      // Loading (or failed): draw a subtle capsule placeholder. When the node
      // declares a `normalize` height, size the placeholder to it so the
      // pop-in does not jump scale.
      final extra = node.extra ?? const <String, dynamic>{};
      final normalize = extra['normalize'];
      final targetH = normalize is num
          ? normalize.toDouble()
          : normalize is Map
              ? (normalize['height'] as num?)?.toDouble()
              : null;
      final h = (targetH != null && targetH > 0) ? targetH : 1.0;
      final placeholder = _generateMesh('Capsule', {
        'radius': 0.45 * h,
        'height': h,
        'segments': 10,
      });
      if (placeholder != null) {
        _emitMeshTris(
          placeholder,
          const Material3D(baseColor: Vec3(0.3, 0.34, 0.42), roughness: 0.8),
          worldXform * Mat4.translation(Vec3(0, 0.5 * h, 0)),
          vp, size, camera, environment, lights, screenTris,
        );
      }
      return;
    }

    final extra = node.extra ?? const <String, dynamic>{};
    final animName = extra['animation'] as String?;
    final animIdx = model.resolveAnimation(animName);
    final pinnedTime = (extra['anim_time'] as num?)?.toDouble();
    final time = pinnedTime ?? _elapsed;
    // A playing clip (driven by the elapsed clock, not pinned to a fixed pose)
    // keeps the model moving every frame.
    if (animIdx != null && animIdx >= 0 && pinnedTime == null) _dynamic = true;

    final tint = _vec3From(extra['tint']) ?? Vec3.one;
    final emissiveOverride = _vec3From(extra['emissive']);
    final emissiveStrength = (extra['emissive_strength'] as num?)?.toDouble() ?? 1.0;

    // Bounds-based normalization: `normalize: 4` (target height) or
    // `normalize: {height, ground, center}`. Applied between the node
    // transform and the model so authors size assets in world units.
    final normalized = _normalizeFrame(extra['normalize'], model, worldXform);
    worldXform = normalized;

    final globals = model.computeGlobalTransforms(animIdx, time);

    for (var ni = 0; ni < model.nodes.length; ni++) {
      final meshIdx = model.nodes[ni].mesh;
      if (meshIdx == null || meshIdx >= model.meshes.length) continue;

      final skinIdx = model.nodes[ni].skin;
      List<Mat4>? jointMats;
      if (skinIdx != null && skinIdx < model.skins.length) {
        final skin = model.skins[skinIdx];
        jointMats = List<Mat4>.generate(
          skin.joints.length,
          (k) => globals[skin.joints[k]] * skin.inverseBind[k],
          growable: false,
        );
      }
      final modelMat = worldXform * globals[ni];

      for (final prim in model.meshes[meshIdx]) {
        _emitPrimitive(
          prim, model, jointMats, worldXform, modelMat,
          vp, size, camera, environment, lights,
          tint, emissiveOverride, emissiveStrength, screenBatches,
        );
      }
    }
  }

  /// Resolve a `model3d` node's `normalize` request against the model's
  /// rest-pose bounds. Accepts a bare number (target world height) or a map
  /// `{height, ground, center}`; anything else returns [worldXform] unchanged.
  static Mat4 _normalizeFrame(
      dynamic normalize, GltfModel model, Mat4 worldXform) {
    if (normalize == null) return worldXform;
    double? height;
    double? footprint;
    var ground = false;
    var center = false;
    if (normalize is num) {
      height = normalize.toDouble();
    } else if (normalize is Map) {
      height = (normalize['height'] as num?)?.toDouble();
      footprint = (normalize['footprint'] as num?)?.toDouble();
      ground = normalize['ground'] == true;
      center = normalize['center'] == true;
    } else {
      return worldXform;
    }
    return worldXform *
        model.normalizeTransform(
            height: height, footprint: footprint, ground: ground, center: center);
  }

  void _emitPrimitive(
    GltfPrimitive prim,
    GltfModel model,
    List<Mat4>? jointMats,
    Mat4 worldXform,
    Mat4 modelMat,
    Mat4 vp,
    ui.Size size,
    Camera3D camera,
    Environment3D environment,
    List<Light3D> lights,
    Vec3 tint,
    Vec3? emissiveOverride,
    double emissiveStrength,
    List<_ModelBatch> screenBatches,
  ) {
    final vcount = prim.vertexCount;
    if (vcount == 0) return;

    // Resolve material → engine Material3D for lighting (texture handled by
    // the per-batch shader; baseColor here is the glTF baseColorFactor × tint).
    final gmat = (prim.material != null && prim.material! < model.materials.length)
        ? model.materials[prim.material!]
        : const GltfMaterial();
    final litMat = Material3D(
      baseColor: gmat.baseColor.scale(tint),
      metallic: gmat.metallic,
      roughness: gmat.roughness,
      emissive: emissiveOverride ?? gmat.emissive,
      emissiveStrength: emissiveOverride != null ? emissiveStrength : 1.0,
      doubleSided: gmat.doubleSided,
    );

    GltfTexture? texture;
    if (gmat.baseColorTexture != null &&
        gmat.baseColorTexture! < model.textures.length &&
        prim.uvs != null) {
      texture = model.textures[gmat.baseColorTexture!];
    }
    final texW = texture?.width ?? 1.0;
    final texH = texture?.height ?? 1.0;

    final pos = prim.positions;
    final nrm = prim.normals;
    final uvs = prim.uvs;
    final skinned = prim.skinned && jointMats != null;
    final hasNormals = nrm != null;

    // Per-vertex scratch (one allocation pass over the primitive).
    final worldPos = List<Vec3>.filled(vcount, Vec3.zero);
    final screen = List<ui.Offset>.filled(vcount, ui.Offset.zero);
    final ndcZ = Float32List(vcount);
    final visible = List<bool>.filled(vcount, false);
    final litColor = hasNormals ? List<Vec3>.filled(vcount, Vec3.zero) : null;
    final nearPlane = camera.near;

    for (var v = 0; v < vcount; v++) {
      final px = pos[v * 3], py = pos[v * 3 + 1], pz = pos[v * 3 + 2];
      final Vec3 wp;
      if (skinned) {
        final sp = _skinPoint(jointMats!, prim.joints!, prim.weights!, v, px, py, pz);
        wp = worldXform.transformPoint(sp);
      } else {
        wp = modelMat.transformPoint(Vec3(px, py, pz));
      }
      worldPos[v] = wp;

      if (hasNormals) {
        final nx = nrm[v * 3], ny = nrm[v * 3 + 1], nz = nrm[v * 3 + 2];
        Vec3 wn;
        if (skinned) {
          final sn = _skinNormal(jointMats!, prim.joints!, prim.weights!, v, nx, ny, nz);
          wn = worldXform.transformDir(sn).normalized;
        } else {
          wn = modelMat.transformDir(Vec3(nx, ny, nz)).normalized;
        }
        final uv = uvs != null ? Vec2(uvs[v * 2], uvs[v * 2 + 1]) : Vec2.zero;
        litColor![v] = _fogged(
          _computeLighting(wp, wn, uv, litMat, environment, lights, camera.position),
          wp, camera, environment,
        );
      }

      final clip = vp.transformVec4(wp);
      if (clip.w <= nearPlane) {
        visible[v] = false;
        continue;
      }
      final ndc = clip.perspectiveDivide();
      if (ndc.x < -1.6 || ndc.x > 1.6 || ndc.y < -1.6 || ndc.y > 1.6) {
        visible[v] = false;
        continue;
      }
      screen[v] = ui.Offset(
        (ndc.x * 0.5 + 0.5) * size.width,
        (0.5 - ndc.y * 0.5) * size.height,
      );
      ndcZ[v] = ndc.z;
      visible[v] = true;
    }

    final triCount = prim.triangleCount;
    final indices = prim.indices;

    // Collect visible triangles so they can be depth-sorted within the batch
    // (no per-pixel z-buffer — painter's order inside one drawVertices call).
    final tris = <_PrimTri>[];
    for (var t = 0; t < triCount; t++) {
      final i0 = indices != null ? indices[t * 3] : t * 3;
      final i1 = indices != null ? indices[t * 3 + 1] : t * 3 + 1;
      final i2 = indices != null ? indices[t * 3 + 2] : t * 3 + 2;
      if (!visible[i0] || !visible[i1] || !visible[i2]) continue;

      final s0 = screen[i0], s1 = screen[i1], s2 = screen[i2];
      final cross = (s1.dx - s0.dx) * (s2.dy - s0.dy) -
          (s1.dy - s0.dy) * (s2.dx - s0.dx);
      if (cross > 0 && !gmat.doubleSided) continue;

      Color c0, c1, c2;
      if (hasNormals) {
        final lc = litColor!; // non-null whenever hasNormals
        c0 = _toColor(lc[i0]);
        c1 = _toColor(lc[i1]);
        c2 = _toColor(lc[i2]);
      } else {
        // Flat shading: derive a face normal from world positions.
        final wp0 = worldPos[i0], wp1 = worldPos[i1], wp2 = worldPos[i2];
        final fn = (wp1 - wp0).cross(wp2 - wp0).normalized;
        final lit = _fogged(
          _computeLighting(
              (wp0 + wp1 + wp2) / 3.0, fn, Vec2.zero, litMat, environment, lights, camera.position),
          (wp0 + wp1 + wp2) / 3.0, camera, environment,
        );
        c0 = c1 = c2 = _toColor(lit);
      }

      final depth = (ndcZ[i0] + ndcZ[i1] + ndcZ[i2]) / 3.0;
      tris.add(_PrimTri(s0, s1, s2, c0, c1, c2,
          texture != null
              ? ui.Offset(uvs![i0 * 2] * texW, uvs[i0 * 2 + 1] * texH)
              : ui.Offset.zero,
          texture != null
              ? ui.Offset(uvs![i1 * 2] * texW, uvs[i1 * 2 + 1] * texH)
              : ui.Offset.zero,
          texture != null
              ? ui.Offset(uvs![i2 * 2] * texW, uvs[i2 * 2 + 1] * texH)
              : ui.Offset.zero,
          depth));
    }

    if (tris.isEmpty) return;
    tris.sort((a, b) => b.depth.compareTo(a.depth));

    final n = tris.length * 3;
    final positions = List<ui.Offset>.filled(n, ui.Offset.zero, growable: false);
    final colors = List<Color>.filled(n, const Color(0xFFFFFFFF), growable: false);
    final texCoords = texture != null
        ? List<ui.Offset>.filled(n, ui.Offset.zero, growable: false)
        : null;
    var avgDepth = 0.0;
    for (var i = 0; i < tris.length; i++) {
      final t = tris[i];
      final b = i * 3;
      positions[b] = t.s0;
      positions[b + 1] = t.s1;
      positions[b + 2] = t.s2;
      colors[b] = t.c0;
      colors[b + 1] = t.c1;
      colors[b + 2] = t.c2;
      if (texCoords != null) {
        texCoords[b] = t.uv0;
        texCoords[b + 1] = t.uv1;
        texCoords[b + 2] = t.uv2;
      }
      avgDepth += t.depth;
    }
    avgDepth /= tris.length;

    final vertices = ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      colors: colors,
      textureCoordinates: texCoords,
    );
    screenBatches.add(_ModelBatch(vertices, texture?.shader, avgDepth));
  }

  /// Linear-blend skin a position. Reads joint matrices directly (no [Vec3]
  /// allocation per bone) for speed in the per-vertex hot loop.
  static Vec3 _skinPoint(List<Mat4> jm, Uint16List joints, Float32List weights,
      int v, double px, double py, double pz) {
    var x = 0.0, y = 0.0, z = 0.0;
    final b = v * 4;
    for (var w = 0; w < 4; w++) {
      final wt = weights[b + w];
      if (wt == 0) continue;
      final m = jm[joints[b + w]].m;
      x += wt * (m[0] * px + m[4] * py + m[8] * pz + m[12]);
      y += wt * (m[1] * px + m[5] * py + m[9] * pz + m[13]);
      z += wt * (m[2] * px + m[6] * py + m[10] * pz + m[14]);
    }
    return Vec3(x, y, z);
  }

  static Vec3 _skinNormal(List<Mat4> jm, Uint16List joints, Float32List weights,
      int v, double nx, double ny, double nz) {
    var x = 0.0, y = 0.0, z = 0.0;
    final b = v * 4;
    for (var w = 0; w < 4; w++) {
      final wt = weights[b + w];
      if (wt == 0) continue;
      final m = jm[joints[b + w]].m;
      x += wt * (m[0] * nx + m[4] * ny + m[8] * nz);
      y += wt * (m[1] * nx + m[5] * ny + m[9] * nz);
      z += wt * (m[2] * nx + m[6] * ny + m[10] * nz);
    }
    return Vec3(x, y, z);
  }

  Vec3 _fogged(Vec3 color, Vec3 worldPos, Camera3D camera, Environment3D env) {
    final dist = (worldPos - camera.position).length;
    final f = env.fogFactor(dist);
    if (f >= 1.0) return color;
    return Vec3(
      color.x * f + env.fogColor.x * (1 - f),
      color.y * f + env.fogColor.y * (1 - f),
      color.z * f + env.fogColor.z * (1 - f),
    );
  }

  static Color _toColor(Vec3 c) => Color.fromARGB(
        255,
        (c.x * 255).round().clamp(0, 255),
        (c.y * 255).round().clamp(0, 255),
        (c.z * 255).round().clamp(0, 255),
      );

  static Vec3? _vec3From(dynamic v) {
    if (v is Map) {
      double c(Object? a, Object? b) =>
          (a as num?)?.toDouble() ?? (b as num?)?.toDouble() ?? 0.0;
      return Vec3(
        c(v['r'], v['x']),
        c(v['g'], v['y']),
        c(v['b'], v['z']),
      );
    }
    return null;
  }

  Vec3 _computeLighting(
    Vec3 worldPos,
    Vec3 worldNormal,
    Vec2 uv,
    Material3D mat,
    Environment3D env,
    List<Light3D> lights,
    Vec3 cameraPos, {
    bool includeSpecular = true,
  }) {
    if (mat.unlit) {
      return mat.sampleTexture(uv) + mat.emissive * mat.emissiveStrength;
    }

    final baseColor = mat.sampleTexture(uv);
    final viewDir = includeSpecular ? (cameraPos - worldPos).normalized : Vec3.zero;

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
        final spotAngle = math.acos(lightDir.dot((-light.direction).normalized).clamp(-1.0, 1.0));
        final outerRad = light.outerConeAngle * math.pi / 180;
        final innerRad = light.innerConeAngle * math.pi / 180;
        if (spotAngle > outerRad) continue;
        final spotFade = ((outerRad - spotAngle) / (outerRad - innerRad)).clamp(0.0, 1.0);
        attenuation = spotFade / (1.0 + dist * dist / (light.range * light.range));
      } else {
        lightDir = Vec3.up;
      }

      final nDotL = worldNormal.dot(lightDir).clamp(0.0, 1.0);
      final lightColor = light.color * light.intensity * attenuation;

      // Diffuse (Lambertian)
      final diffuse = baseColor.scale(lightColor) * nDotL;
      result = result + diffuse;

      // Specular (Blinn-Phong with roughness) — view-dependent, so skipped for
      // baked static geometry.
      if (includeSpecular) {
        final halfV = (lightDir + viewDir).normalized;
        final nDotH = worldNormal.dot(halfV).clamp(0.0, 1.0);
        final shininess = (1.0 - mat.roughness) * 128.0 + 2.0;
        final specStrength = mat.metallic * 0.8 + 0.2;
        final specular = lightColor * (math.pow(nDotH, shininess) * specStrength * nDotL);
        result = result + specular;
      }
    }

    // Emissive
    result = result + mat.emissive * mat.emissiveStrength;

    // Clamp
    return Vec3(
      result.x.clamp(0.0, 1.0),
      result.y.clamp(0.0, 1.0),
      result.z.clamp(0.0, 1.0),
    );
  }

  /// Sutherland–Hodgman clip of a clip-space triangle against the near plane
  /// and the four side planes (|x| ≤ m·w, |y| ≤ m·w with a small margin so
  /// screen-edge interpolation artifacts stay just offscreen). Returns a fan
  /// polygon, or null when fully outside.
  _ClippedResult? _clipFrustum(List<Vec4> verts, List<Vec3> colors, double near) {
    const m = 1.05; // guard-band margin in NDC units
    // Signed "inside" distance per plane; > 0 keeps the vertex.
    final planes = <double Function(Vec4)>[
      (v) => v.w - near, // near
      (v) => m * v.w - v.x, // right  (x ≤ m·w)
      (v) => m * v.w + v.x, // left   (x ≥ -m·w)
      (v) => m * v.w - v.y, // top    (y ≤ m·w)
      (v) => m * v.w + v.y, // bottom (y ≥ -m·w)
    ];

    var pv = verts;
    var pc = colors;
    for (final plane in planes) {
      if (pv.isEmpty) return null;
      final ov = <Vec4>[];
      final oc = <Vec3>[];
      for (var i = 0; i < pv.length; i++) {
        final j = (i + 1) % pv.length;
        final di = plane(pv[i]);
        final dj = plane(pv[j]);
        if (di > 0) {
          ov.add(pv[i]);
          oc.add(pc[i]);
        }
        if ((di > 0) != (dj > 0)) {
          final t = di / (di - dj);
          final vi = pv[i], vj = pv[j];
          ov.add(Vec4(
            vi.x + t * (vj.x - vi.x),
            vi.y + t * (vj.y - vi.y),
            vi.z + t * (vj.z - vi.z),
            vi.w + t * (vj.w - vi.w),
          ));
          oc.add(pc[i].lerp(pc[j], t));
        }
      }
      pv = ov;
      pc = oc;
    }
    if (pv.length < 3) return null;
    return _ClippedResult(pv, pc);
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

  /// Cache of generated geometry keyed by mesh descriptor.
  ///
  /// Mesh geometry is immutable (transforms and lighting are applied later
  /// per-frame), so identical descriptors can safely share one [Mesh]. This
  /// turns mesh generation from a per-paint cost into a one-time cost per
  /// unique shape — essential for animated/game scenes that re-parse their
  /// node tree every frame.
  static final Map<String, Mesh> _meshCache = <String, Mesh>{};

  /// Builds a stable cache key from a mesh type and its geometry params.
  static String _meshKey(String meshType, Map<String, dynamic> p) {
    if (p.isEmpty) return meshType;
    final keys = p.keys.toList()..sort();
    final sb = StringBuffer(meshType);
    for (final k in keys) {
      sb..write('|')..write(k)..write('=')..write(p[k]);
    }
    return sb.toString();
  }

  Mesh? _generateMesh(String? meshType, Map<String, dynamic>? params) {
    if (meshType == null) return null;
    final p = params ?? const <String, dynamic>{};

    final cacheKey = _meshKey(meshType, p);
    final cached = _meshCache[cacheKey];
    if (cached != null) return cached;

    final mesh = _buildMesh(meshType, p);
    if (mesh != null) _meshCache[cacheKey] = mesh;
    return mesh;
  }

  Mesh? _buildMesh(String meshType, Map<String, dynamic> p) {
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
      case 'Ring':
        return MeshGen.ring(
          innerRadius: _d(p['inner_radius'], 0.5),
          outerRadius: _d(p['outer_radius'], 1.0),
          height: _d(p['height'], 0.2),
          segments: _i(p['segments'], 32),
        );
      case 'Cone':
        return MeshGen.cone(
          radius: _d(p['radius'], 0.5),
          height: _d(p['height'], 1.0),
          segments: _i(p['segments'], 16),
        );
      case 'Torus':
        return MeshGen.torus(
          radius: _d(p['major_radius'], 1.0),
          tubeRadius: _d(p['tube_radius'], 0.3),
          radial: _i(p['radial_segments'], 16),
          tubular: _i(p['tubular_segments'], 24),
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

/// A projected, lit glTF triangle awaiting batch assembly. Holds screen-space
/// positions, per-vertex colours (lighting), texture coordinates (in texel
/// space) and an average NDC depth for within-batch painter sorting.
class _PrimTri {
  final ui.Offset s0, s1, s2;
  final Color c0, c1, c2;
  final ui.Offset uv0, uv1, uv2;
  final double depth;
  _PrimTri(this.s0, this.s1, this.s2, this.c0, this.c1, this.c2, this.uv0,
      this.uv1, this.uv2, this.depth);
}

Color _vec3ToColor(Vec3 c) => Color.fromARGB(
      255,
      (c.x * 255).round().clamp(0, 255),
      (c.y * 255).round().clamp(0, 255),
      (c.z * 255).round().clamp(0, 255),
    );
