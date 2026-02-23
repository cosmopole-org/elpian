/// Parses JSON scene definitions into the core 3D engine types.
///
/// Supports the same JSON format used by the Bevy renderer, plus extended
/// features (particles, physics, multiple animations, procedural textures).
library;

import 'dart:math' as math;
import 'core.dart';

/// Parsed scene ready for rendering.
class ParsedScene {
  final Camera3D camera;
  final Environment3D environment;
  final List<Light3D> lights;
  final List<SceneNode> nodes;

  const ParsedScene({
    required this.camera,
    required this.environment,
    required this.lights,
    required this.nodes,
  });
}

/// Parses a JSON map into a [ParsedScene].
class SceneParser {
  /// Parse the top-level scene JSON.
  static ParsedScene parse(Map<String, dynamic> json) {
    final world = json['world'] as List<dynamic>? ?? [];

    var camera = Camera3D();
    var environment = const Environment3D();
    final lights = <Light3D>[];
    final nodes = <SceneNode>[];

    for (final item in world) {
      if (item is! Map<String, dynamic>) continue;
      final type = item['type'] as String? ?? '';

      switch (type) {
        case 'environment':
          environment = _parseEnvironment(item);
          break;
        case 'camera':
          camera = _parseCamera(item);
          break;
        case 'light':
          lights.add(_parseLight(item));
          break;
        case 'mesh3d':
        case 'group':
        case 'particles':
        case 'text3d':
          nodes.add(_parseNode(item));
          break;
      }
    }

    // Ensure at least one directional light exists
    if (lights.isEmpty) {
      lights.add(const Light3D(
        type: LightType.directional,
        direction: Vec3(0.5, -1.0, 0.3),
        intensity: 1.0,
      ));
    }

    return ParsedScene(
      camera: camera,
      environment: environment,
      lights: lights,
      nodes: nodes,
    );
  }

  // ── Environment ──────────────────────────────────────────────────

  static Environment3D _parseEnvironment(Map<String, dynamic> json) {
    final ambient = _parseColor3(json['ambient_light']);
    return Environment3D(
      ambientColor: ambient ?? const Vec3(0.4, 0.4, 0.5),
      ambientIntensity: _d(json['ambient_intensity'], 0.3),
      skyColorTop: _parseColor3(json['sky_color_top']) ?? const Vec3(0.3, 0.5, 0.9),
      skyColorBottom: _parseColor3(json['sky_color_bottom']) ?? const Vec3(0.7, 0.8, 1.0),
      fogType: _parseFogType(json['fog_type'] as String?),
      fogColor: _parseColor3(json['fog_color']) ?? const Vec3(0.7, 0.7, 0.8),
      fogNear: _d(json['fog_near'], 10.0),
      fogFar: _d(json['fog_distance'] ?? json['fog_far'], 100.0),
      fogDensity: _d(json['fog_density'], 0.02),
      gravity: _parseVec3(json['gravity']) ?? const Vec3(0, -9.81, 0),
    );
  }

  static const _fogTypeMap = <String, FogType>{
    'linear': FogType.linear,
    'exponential': FogType.exponential,
  };

  static FogType _parseFogType(String? s) => _fogTypeMap[s] ?? FogType.none;

  // ── Camera ───────────────────────────────────────────────────────

  static Camera3D _parseCamera(Map<String, dynamic> json) {
    final transform = json['transform'] as Map<String, dynamic>? ?? {};
    final pos = _parseVec3(transform['position']) ?? const Vec3(0, 5, 10);
    final rot = _parseVec3(transform['rotation']) ?? Vec3.zero;

    // Compute target from rotation angles
    final rx = rot.x * math.pi / 180;
    final ry = rot.y * math.pi / 180;
    final forward = Vec3(
      math.sin(ry) * math.cos(rx),
      math.sin(rx),
      -math.cos(ry) * math.cos(rx),
    );
    final target = pos + forward * 10;

    return Camera3D(
      type: json['camera_type'] == 'Orthographic'
          ? CameraType.orthographic
          : CameraType.perspective,
      position: pos,
      target: target,
      fov: _d(json['fov'], 60.0),
      near: _d(json['near'], 0.1),
      far: _d(json['far'], 1000.0),
      orthoSize: _d(json['ortho_size'], 10.0),
      mode: _parseCameraMode(json['mode'] as String?),
      orbitSpeed: _d(json['orbit_speed'], 10.0),
      orbitRadius: _d(json['orbit_radius'], 10.0),
    );
  }

  static const _cameraModeMap = <String, CameraMode>{
    'orbit': CameraMode.orbit,
    'first_person': CameraMode.firstPerson,
    'follow': CameraMode.follow,
    'flythrough': CameraMode.flythrough,
  };

  static CameraMode _parseCameraMode(String? s) => _cameraModeMap[s] ?? CameraMode.fixed;

  // ── Light ────────────────────────────────────────────────────────

  static Light3D _parseLight(Map<String, dynamic> json) {
    final transform = json['transform'] as Map<String, dynamic>? ?? {};
    final pos = _parseVec3(transform['position']) ?? Vec3.zero;
    final rot = _parseVec3(transform['rotation']) ?? const Vec3(-45, 30, 0);

    // Compute direction from rotation
    final rx = rot.x * math.pi / 180;
    final ry = rot.y * math.pi / 180;
    final dir = Vec3(
      math.sin(ry) * math.cos(rx),
      math.sin(rx),
      -math.cos(ry) * math.cos(rx),
    );

    return Light3D(
      type: _parseLightType(json['light_type'] as String?),
      color: _parseColor3(json['color']) ?? Vec3.one,
      intensity: _d(json['intensity'], 1.0),
      position: pos,
      direction: dir,
      range: _d(json['range'], 50.0),
      innerConeAngle: _d(json['inner_cone_angle'], 30.0),
      outerConeAngle: _d(json['outer_cone_angle'], 45.0),
      castShadow: json['cast_shadow'] as bool? ?? false,
    );
  }

  static const _lightTypeMap = <String, LightType>{
    'Point': LightType.point,
    'Spot': LightType.spot,
    'Area': LightType.area,
  };

  static LightType _parseLightType(String? s) => _lightTypeMap[s] ?? LightType.directional;

  // ── Scene Node ───────────────────────────────────────────────────

  static SceneNode _parseNode(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'group';
    final transform = json['transform'] as Map<String, dynamic>? ?? {};
    final pos = _parseVec3(transform['position']) ?? Vec3.zero;
    final rot = _parseVec3(transform['rotation']) ?? Vec3.zero;
    final scl = _parseVec3(transform['scale']) ?? Vec3.one;

    // Parse mesh type and params
    String? meshType;
    Map<String, dynamic>? meshParams;
    if (type == 'mesh3d') {
      final meshDef = json['mesh'];
      if (meshDef is String) {
        meshType = meshDef;
        meshParams = {};
      } else if (meshDef is Map<String, dynamic>) {
        meshType = meshDef['shape'] as String? ?? 'Cube';
        meshParams = meshDef;
      } else {
        meshType = 'Cube';
        meshParams = {};
      }
    }

    // Parse material
    Material3D? material;
    if (json['material'] != null) {
      material = _parseMaterial(json['material'] as Map<String, dynamic>);
    }

    // Parse animations (single or list)
    List<AnimationDef>? animations;
    final animDef = json['animation'];
    if (animDef is Map<String, dynamic>) {
      animations = [_parseAnimation(animDef)];
    } else if (animDef is List) {
      animations = animDef
          .whereType<Map<String, dynamic>>()
          .map(_parseAnimation)
          .toList();
    }

    // Parse particles
    ParticleEmitter? emitter;
    if (type == 'particles' && json['emitter'] != null) {
      emitter = _parseEmitter(json['emitter'] as Map<String, dynamic>);
    }

    // Parse physics
    RigidBody? rigidBody;
    if (json['physics'] != null) {
      rigidBody = _parseRigidBody(json['physics'] as Map<String, dynamic>);
    }

    // Parse children
    List<SceneNode>? children;
    if (json['children'] is List) {
      children = (json['children'] as List)
          .whereType<Map<String, dynamic>>()
          .map(_parseNode)
          .toList();
    }

    return SceneNode(
      type: type,
      id: json['id'] as String?,
      name: json['name'] as String?,
      position: pos,
      rotation: rot,
      scale: scl,
      visible: json['visible'] as bool? ?? true,
      children: children,
      material: material,
      meshType: meshType,
      meshParams: meshParams,
      animations: animations,
      emitter: emitter,
      rigidBody: rigidBody,
      text: json['text'] as String?,
      textSize: (json['text_size'] as num?)?.toDouble(),
      extra: json['extra'] as Map<String, dynamic>?,
    );
  }

  // ── Material ─────────────────────────────────────────────────────

  static Material3D _parseMaterial(Map<String, dynamic> json) {
    final bc = _parseColor3(json['base_color']);
    final bcMap = json['base_color'] as Map<String, dynamic>?;
    final alpha = (bcMap != null && bcMap.containsKey('a'))
        ? (bcMap['a'] as num).toDouble()
        : _d(json['alpha'], 1.0);

    return Material3D(
      baseColor: bc ?? const Vec3(0.8, 0.8, 0.8),
      metallic: _d(json['metallic'], 0.0),
      roughness: _d(json['roughness'], 0.5),
      emissive: _parseColor3(json['emissive']) ?? Vec3.zero,
      emissiveStrength: _d(json['emissive_strength'], 1.0),
      alpha: alpha,
      alphaMode: _parseAlphaMode(json['alpha_mode'] as String?),
      alphaCutoff: _d(json['alpha_cutoff'], 0.5),
      doubleSided: json['double_sided'] as bool? ?? false,
      wireframe: json['wireframe'] as bool? ?? false,
      unlit: json['unlit'] as bool? ?? false,
      texture: _parseTextureType(json['texture'] as String?),
      textureColor2: _parseColor3(json['texture_color2']) ?? const Vec3(0.3, 0.3, 0.3),
      textureScale: _d(json['texture_scale'], 1.0),
    );
  }

  static const _alphaModeMap = <String, AlphaMode>{
    'blend': AlphaMode.blend,
    'cutoff': AlphaMode.cutoff,
  };

  static AlphaMode _parseAlphaMode(String? s) => _alphaModeMap[s] ?? AlphaMode.opaque;

  static const _textureTypeMap = <String, TextureType>{
    'checkerboard': TextureType.checkerboard,
    'gradient': TextureType.gradient,
    'noise': TextureType.noise,
    'stripes': TextureType.stripes,
  };

  static TextureType _parseTextureType(String? s) => _textureTypeMap[s] ?? TextureType.none;

  // ── Animation ────────────────────────────────────────────────────

  static AnimationDef _parseAnimation(Map<String, dynamic> json) {
    final animType = json['animation_type'];
    String type;
    Map<String, dynamic> params;

    if (animType is Map<String, dynamic>) {
      type = animType['type'] as String? ?? 'Rotate';
      params = Map<String, dynamic>.from(animType)..remove('type');
    } else if (animType is String) {
      type = animType;
      params = {};
    } else {
      type = json['type'] as String? ?? 'Rotate';
      params = {};
    }

    return AnimationDef(
      type: type,
      duration: _d(json['duration'], 1.0),
      looping: json['looping'] as bool? ?? true,
      easing: _parseEasing(json['easing'] as String?),
      delay: _d(json['delay'], 0.0),
      params: params,
    );
  }

  static const _easingTypeMap = <String, EasingType>{
    'EaseIn': EasingType.easeIn,
    'EaseOut': EasingType.easeOut,
    'EaseInOut': EasingType.easeInOut,
    'Bounce': EasingType.bounce,
    'Elastic': EasingType.elastic,
    'Back': EasingType.back,
    'Sine': EasingType.sine,
  };

  static EasingType _parseEasing(String? s) => _easingTypeMap[s] ?? EasingType.linear;

  // ── Particle Emitter ─────────────────────────────────────────────

  static ParticleEmitter _parseEmitter(Map<String, dynamic> json) {
    return ParticleEmitter(
      shape: _parseEmitterShape(json['shape'] as String?),
      emitRate: _d(json['emit_rate'], 20),
      lifetime: _d(json['lifetime'], 2),
      startColor: _parseColor3(json['start_color']) ?? Vec3.one,
      endColor: _parseColor3(json['end_color']) ?? Vec3.one,
      startSize: _d(json['start_size'], 0.1),
      endSize: _d(json['end_size'], 0.0),
      startAlpha: _d(json['start_alpha'], 1.0),
      endAlpha: _d(json['end_alpha'], 0.0),
      gravity: _parseVec3(json['gravity']) ?? const Vec3(0, -2, 0),
      wind: _parseVec3(json['wind']) ?? Vec3.zero,
      spread: _d(json['spread'], 45.0),
      speed: _d(json['speed'], 2.0),
      speedVariance: _d(json['speed_variance'], 0.5),
      maxParticles: (json['max_particles'] as num?)?.toInt() ?? 200,
      worldSpace: json['world_space'] as bool? ?? true,
      blendMode: json['blend_mode'] as String? ?? 'additive',
      burstCount: _d(json['burst_count'], 0),
      prewarm: json['prewarm'] as bool? ?? false,
    );
  }

  static const _emitterShapeMap = <String, EmitterShape>{
    'sphere': EmitterShape.sphere,
    'cone': EmitterShape.cone,
    'box': EmitterShape.box,
    'ring': EmitterShape.ring,
  };

  static EmitterShape _parseEmitterShape(String? s) => _emitterShapeMap[s] ?? EmitterShape.point;

  // ── Physics ──────────────────────────────────────────────────────

  static RigidBody _parseRigidBody(Map<String, dynamic> json) {
    return RigidBody(
      velocity: _parseVec3(json['velocity']) ?? Vec3.zero,
      mass: _d(json['mass'], 1.0),
      restitution: _d(json['restitution'], 0.5),
      friction: _d(json['friction'], 0.3),
      isStatic: json['is_static'] as bool? ?? false,
      useGravity: json['use_gravity'] as bool? ?? true,
      collider: _parseColliderType(json['collider'] as String?),
      colliderRadius: _d(json['collider_radius'], 0.5),
      colliderSize: _parseVec3(json['collider_size']) ?? Vec3.one,
    );
  }

  static const _colliderTypeMap = <String, ColliderType>{
    'box': ColliderType.box,
    'plane': ColliderType.plane,
  };

  static ColliderType _parseColliderType(String? s) => _colliderTypeMap[s] ?? ColliderType.sphere;

  // ── Helpers ──────────────────────────────────────────────────────

  static double _d(dynamic v, double def) =>
      (v as num?)?.toDouble() ?? def;

  static Vec3? _parseVec3(dynamic v) {
    if (v is Map) {
      return Vec3(
        (v['x'] as num?)?.toDouble() ?? 0,
        (v['y'] as num?)?.toDouble() ?? 0,
        (v['z'] as num?)?.toDouble() ?? 0,
      );
    }
    if (v is List && v.length >= 3) {
      return Vec3(
        (v[0] as num).toDouble(),
        (v[1] as num).toDouble(),
        (v[2] as num).toDouble(),
      );
    }
    return null;
  }

  static Vec3? _parseColor3(dynamic v) {
    if (v is Map) {
      return Vec3(
        (v['r'] as num?)?.toDouble() ?? 0,
        (v['g'] as num?)?.toDouble() ?? 0,
        (v['b'] as num?)?.toDouble() ?? 0,
      );
    }
    if (v is List && v.length >= 3) {
      return Vec3(
        (v[0] as num).toDouble(),
        (v[1] as num).toDouble(),
        (v[2] as num).toDouble(),
      );
    }
    return null;
  }
}
