/// Runtime representation of a loaded glTF 2.0 / GLB model.
///
/// This holds the parsed, render-ready data (mesh primitives with skinning
/// attributes, the node hierarchy, skins, materials, decoded textures and
/// keyframe animations) plus the math needed to evaluate an animated skeleton
/// pose on the CPU. It is engine-agnostic: the [Scene3DRenderer] consumes it,
/// but it has no Flutter/Canvas dependencies beyond `dart:ui.Image` for
/// decoded textures.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import '../core.dart';

/// A single drawable primitive (triangle list) of a glTF mesh.
class GltfPrimitive {
  /// Flat `x,y,z` positions, 3 floats per vertex.
  final Float32List positions;

  /// Flat `x,y,z` normals (3 per vertex) or null when the asset omits them
  /// (e.g. the Khronos `Fox`). Face normals are derived at skin time instead.
  final Float32List? normals;

  /// Flat `u,v` texture coordinates (2 per vertex) or null.
  final Float32List? uvs;

  /// Four joint indices per vertex (skinned meshes only).
  final Uint16List? joints;

  /// Four bone weights per vertex (skinned meshes only).
  final Float32List? weights;

  /// Triangle indices, or null when the geometry is non-indexed (sequential).
  final Int32List? indices;

  final int vertexCount;
  final int? material;
  bool get skinned => joints != null && weights != null;

  /// Number of triangles to draw.
  int get triangleCount =>
      (indices != null ? indices!.length : vertexCount) ~/ 3;

  const GltfPrimitive({
    required this.positions,
    required this.vertexCount,
    this.normals,
    this.uvs,
    this.joints,
    this.weights,
    this.indices,
    this.material,
  });
}

/// PBR-ish material parameters extracted from a glTF material.
class GltfMaterial {
  final Vec3 baseColor;
  final double metallic;
  final double roughness;
  final Vec3 emissive;
  final double alpha;
  final bool doubleSided;
  final bool blend;

  /// Index into [GltfModel.textures] for the base-colour map, or null.
  final int? baseColorTexture;

  const GltfMaterial({
    this.baseColor = const Vec3(1, 1, 1),
    this.metallic = 0.0,
    this.roughness = 0.7,
    this.emissive = Vec3.zero,
    this.alpha = 1.0,
    this.doubleSided = false,
    this.blend = false,
    this.baseColorTexture,
  });
}

/// A decoded base-colour texture plus its lazily-built shader.
class GltfTexture {
  final ui.Image image;
  final double width;
  final double height;
  ui.ImageShader? _shader;

  GltfTexture(this.image)
      : width = image.width.toDouble(),
        height = image.height.toDouble();

  /// Identity-mapped image shader (texture coordinates are supplied in pixel
  /// space by the renderer). Built once and cached.
  ui.ImageShader get shader => _shader ??= ui.ImageShader(
        image,
        ui.TileMode.repeated,
        ui.TileMode.repeated,
        _identity4x4,
      );

  static final Float64List _identity4x4 = () {
    final m = Float64List(16);
    m[0] = m[5] = m[10] = m[15] = 1.0;
    return m;
  }();
}

/// A node in the glTF scene graph.
class GltfNodeDef {
  final Vec3 translation;
  final Quaternion rotation;
  final Vec3 scale;

  /// Explicit local matrix (mutually exclusive with TRS in the asset).
  final Mat4? matrix;
  final List<int> children;
  final int? mesh;
  final int? skin;
  final String? name;

  /// Set during load: true if any animation channel targets this node.
  bool animated = false;

  GltfNodeDef({
    this.translation = Vec3.zero,
    this.rotation = Quaternion.identity,
    this.scale = Vec3.one,
    this.matrix,
    List<int>? children,
    this.mesh,
    this.skin,
    this.name,
  }) : children = children ?? const [];

  Mat4 localMatrix() {
    final mx = matrix;
    if (mx != null) return mx;
    return Mat4.translation(translation) * rotation.toMat4() * Mat4.scale(scale);
  }
}

/// A skin: the joint nodes plus their inverse-bind matrices.
class GltfSkin {
  final List<int> joints;
  final List<Mat4> inverseBind;
  const GltfSkin(this.joints, this.inverseBind);
}

/// One keyframe sampler (input times → output values).
class GltfSampler {
  final Float32List times;
  final Float32List values;
  final int components; // 3 for translation/scale, 4 for rotation
  final String interpolation; // LINEAR | STEP | CUBICSPLINE
  const GltfSampler(this.times, this.values, this.components, this.interpolation);
}

/// One animation channel (a sampler driving a node's TRS path).
class GltfChannel {
  final int node;
  final String path; // translation | rotation | scale
  final int sampler;
  const GltfChannel(this.node, this.path, this.sampler);
}

/// A named animation clip.
class GltfAnimation {
  final String name;
  final List<GltfChannel> channels;
  final List<GltfSampler> samplers;
  final double duration;
  const GltfAnimation(this.name, this.channels, this.samplers, this.duration);
}

/// A fully-parsed, render-ready model.
class GltfModel {
  final List<GltfNodeDef> nodes;
  final List<int> rootNodes;

  /// `meshes[meshIndex]` = list of primitives.
  final List<List<GltfPrimitive>> meshes;
  final List<GltfMaterial> materials;
  final List<GltfSkin> skins;
  final List<GltfAnimation> animations;
  final List<GltfTexture> textures;
  final Map<String, int> animationByName;

  /// Half-extent of the model's rest pose, used to size a loading placeholder
  /// and to help callers pick a sensible scale.
  final Vec3 restCenter;
  final double restRadius;

  /// Rest-pose axis-aligned bounds (model space). Drives `normalize` on
  /// `model3d` nodes: scene authors give a target world height instead of
  /// hand-tuning a per-asset scale factor for GLBs with arbitrary intrinsic
  /// sizes.
  final Vec3 restMin;
  final Vec3 restMax;

  GltfModel({
    required this.nodes,
    required this.rootNodes,
    required this.meshes,
    required this.materials,
    required this.skins,
    required this.animations,
    required this.textures,
    required this.animationByName,
    this.restCenter = Vec3.zero,
    this.restRadius = 1.0,
    this.restMin = const Vec3(-0.5, -0.5, -0.5),
    this.restMax = const Vec3(0.5, 0.5, 0.5),
  });

  /// Model-space adjustment that normalizes the rest pose to a target size
  /// (uniform scale), optionally snapping the rest-pose base to `y = 0`
  /// ([ground]) and centering the footprint on the local origin ([center]).
  ///
  /// [height] targets the rest-pose Y extent; [footprint] targets the larger
  /// of the X/Z extents. When both are given the *smaller* factor wins — a
  /// "contain" fit, so the model fills a `footprint × footprint` cell without
  /// exceeding `height`. Returns identity when the bounds are degenerate or
  /// no positive constraint is given. Apply between the node transform and
  /// the model: `world = nodeTransform * normalizeTransform(...)`.
  Mat4 normalizeTransform({
    double? height,
    double? footprint,
    bool ground = false,
    bool center = false,
  }) {
    final extentY = restMax.y - restMin.y;
    final extentXZ = (restMax.x - restMin.x) > (restMax.z - restMin.z)
        ? restMax.x - restMin.x
        : restMax.z - restMin.z;
    double? f;
    if (height != null && height > 0 && extentY > 1e-9) {
      f = height / extentY;
    }
    if (footprint != null && footprint > 0 && extentXZ > 1e-9) {
      final ff = footprint / extentXZ;
      f = (f == null || ff < f) ? ff : f;
    }
    if (f == null) {
      if (height != null || footprint != null) return Mat4.identity();
      f = 1.0;
    }
    var m = Mat4.scale(Vec3(f, f, f));
    if (ground || center) {
      final tx = center ? -(restMin.x + restMax.x) / 2 : 0.0;
      final tz = center ? -(restMin.z + restMax.z) / 2 : 0.0;
      final ty = ground ? -restMin.y : 0.0;
      m = m * Mat4.translation(Vec3(tx, ty, tz));
    }
    return m;
  }

  int? resolveAnimation(String? name) {
    if (animations.isEmpty) return null;
    if (name == null || name.isEmpty) return 0;
    final byName = animationByName[name];
    if (byName != null) return byName;
    // Allow numeric indices as a fallback ("0", "1", ...).
    final asInt = int.tryParse(name);
    if (asInt != null && asInt >= 0 && asInt < animations.length) return asInt;
    return 0;
  }

  /// Compute every node's global (model-space) transform for the given
  /// animation clip sampled at [time] seconds. The clip loops on [duration].
  /// Returns a list indexed by node.
  List<Mat4> computeGlobalTransforms(int? animIndex, double time) {
    final n = nodes.length;
    // Start from each node's static local TRS.
    final locals = List<Mat4>.generate(n, (i) => nodes[i].localMatrix(),
        growable: false);

    if (animIndex != null && animIndex >= 0 && animIndex < animations.length) {
      final anim = animations[animIndex];
      final t = anim.duration > 0 ? time % anim.duration : 0.0;

      // Collect per-node animated components, falling back to the node's base.
      final overrideT = <int, Vec3>{};
      final overrideR = <int, Quaternion>{};
      final overrideS = <int, Vec3>{};

      for (final ch in anim.channels) {
        final s = anim.samplers[ch.sampler];
        switch (ch.path) {
          case 'translation':
            overrideT[ch.node] = _sampleVec3(s, t);
            break;
          case 'scale':
            overrideS[ch.node] = _sampleVec3(s, t);
            break;
          case 'rotation':
            overrideR[ch.node] = _sampleQuat(s, t);
            break;
        }
      }

      for (var i = 0; i < n; i++) {
        if (!nodes[i].animated) continue;
        final node = nodes[i];
        final tr = overrideT[i] ?? node.translation;
        final ro = overrideR[i] ?? node.rotation;
        final sc = overrideS[i] ?? node.scale;
        locals[i] = Mat4.translation(tr) * ro.toMat4() * Mat4.scale(sc);
      }
    }

    final globals = List<Mat4>.filled(n, Mat4.identity(), growable: false);
    final visited = List<bool>.filled(n, false);
    void rec(int i, Mat4 parent) {
      if (i < 0 || i >= n || visited[i]) return;
      visited[i] = true;
      final g = parent * locals[i];
      globals[i] = g;
      for (final c in nodes[i].children) {
        rec(c, g);
      }
    }

    final identity = Mat4.identity();
    for (final r in rootNodes) {
      rec(r, identity);
    }
    // Any node not reachable from a root (defensive) keeps its local matrix.
    for (var i = 0; i < n; i++) {
      if (!visited[i]) globals[i] = locals[i];
    }
    return globals;
  }

  static Vec3 _sampleVec3(GltfSampler s, double t) {
    final seg = _segment(s.times, t);
    final i0 = seg.$1, i1 = seg.$2, f = seg.$3;
    final v = s.values;
    final c = s.components;
    if (s.interpolation == 'CUBICSPLINE') {
      // value is the middle of [inTangent, value, outTangent]
      final b0 = (i0 * 3 + 1) * c;
      final b1 = (i1 * 3 + 1) * c;
      return Vec3(
        _lerp(v[b0], v[b1], f),
        _lerp(v[b0 + 1], v[b1 + 1], f),
        _lerp(v[b0 + 2], v[b1 + 2], f),
      );
    }
    final b0 = i0 * c, b1 = i1 * c;
    if (s.interpolation == 'STEP') {
      return Vec3(v[b0], v[b0 + 1], v[b0 + 2]);
    }
    return Vec3(
      _lerp(v[b0], v[b1], f),
      _lerp(v[b0 + 1], v[b1 + 1], f),
      _lerp(v[b0 + 2], v[b1 + 2], f),
    );
  }

  static Quaternion _sampleQuat(GltfSampler s, double t) {
    final seg = _segment(s.times, t);
    final i0 = seg.$1, i1 = seg.$2, f = seg.$3;
    final v = s.values;
    final cubic = s.interpolation == 'CUBICSPLINE';
    final base0 = cubic ? (i0 * 3 + 1) * 4 : i0 * 4;
    final base1 = cubic ? (i1 * 3 + 1) * 4 : i1 * 4;
    final q0 = Quaternion(v[base0], v[base0 + 1], v[base0 + 2], v[base0 + 3]);
    if (s.interpolation == 'STEP') return q0.normalized;
    final q1 = Quaternion(v[base1], v[base1 + 1], v[base1 + 2], v[base1 + 3]);
    return Quaternion.slerp(q0.normalized, q1.normalized, f);
  }

  /// Returns (lowerIndex, upperIndex, fraction) for time [t] in [times].
  static (int, int, double) _segment(Float32List times, double t) {
    final n = times.length;
    if (n == 0) return (0, 0, 0.0);
    if (t <= times[0]) return (0, 0, 0.0);
    if (t >= times[n - 1]) return (n - 1, n - 1, 0.0);
    // Linear scan (keyframe counts are small); binary search not needed.
    var i = 1;
    while (i < n && times[i] < t) {
      i++;
    }
    final i0 = i - 1, i1 = i;
    final span = times[i1] - times[i0];
    final f = span > 1e-9 ? (t - times[i0]) / span : 0.0;
    return (i0, i1, f);
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
