// `model3d` bounds-based normalization: scene authors give a target world
// height (`normalize: 4` or `normalize: {height: 4, ground: true}`) instead of
// hand-tuning per-asset scale factors for GLBs with arbitrary intrinsic sizes.

import 'dart:typed_data';

import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter_test/flutter_test.dart';

GltfModel _model({required Vec3 min, required Vec3 max}) => GltfModel(
      nodes: [GltfNodeDef(mesh: 0)],
      rootNodes: const [0],
      meshes: [
        [
          GltfPrimitive(
            positions: Float32List.fromList([
              min.x, min.y, min.z, //
              max.x, max.y, max.z, //
              min.x, max.y, max.z, //
            ]),
            vertexCount: 3,
          ),
        ],
      ],
      materials: const [],
      skins: const [],
      animations: const [],
      textures: const [],
      animationByName: const {},
      restMin: min,
      restMax: max,
    );

void main() {
  test('scales the rest height to the target world height', () {
    // A 0.4-unit-tall asset normalized to 4 world units → uniform ×10.
    final m = _model(min: const Vec3(-0.1, 0.2, -0.3), max: const Vec3(0.1, 0.6, 0.3));
    final t = m.normalizeTransform(height: 4);
    final top = t.transformPoint(const Vec3(0, 0.6, 0));
    final bottom = t.transformPoint(const Vec3(0, 0.2, 0));
    expect(top.y - bottom.y, closeTo(4.0, 1e-9));
    // Uniform: X/Z scale by the same factor.
    final side = t.transformPoint(const Vec3(0.1, 0.2, 0));
    expect(side.x, closeTo(1.0, 1e-9));
  });

  test('ground snaps the rest-pose base to y=0', () {
    final m = _model(min: const Vec3(-1, 0.2, -1), max: const Vec3(1, 0.6, 1));
    final t = m.normalizeTransform(height: 4, ground: true);
    expect(t.transformPoint(const Vec3(0, 0.2, 0)).y, closeTo(0, 1e-9));
    expect(t.transformPoint(const Vec3(0, 0.6, 0)).y, closeTo(4, 1e-9));
  });

  test('center recenters the footprint on the local origin', () {
    final m = _model(min: const Vec3(2, 0, 4), max: const Vec3(4, 1, 8));
    final t = m.normalizeTransform(height: 1, ground: true, center: true);
    final mid = t.transformPoint(const Vec3(3, 0, 6));
    expect(mid.x, closeTo(0, 1e-9));
    expect(mid.z, closeTo(0, 1e-9));
    expect(mid.y, closeTo(0, 1e-9));
  });

  test('degenerate bounds or non-positive height → identity', () {
    void expectIdentity(Mat4 t) {
      final p = t.transformPoint(const Vec3(1, 1, 1));
      expect(p.x, closeTo(1, 1e-9));
      expect(p.y, closeTo(1, 1e-9));
      expect(p.z, closeTo(1, 1e-9));
    }

    final flat = _model(min: const Vec3(0, 1, 0), max: const Vec3(2, 1, 2));
    expectIdentity(flat.normalizeTransform(height: 4));
    final m = _model(min: const Vec3(0, 0, 0), max: const Vec3(1, 1, 1));
    expectIdentity(m.normalizeTransform(height: 0));
  });

  test('scene parser passes normalize through to the node extra', () {
    final scene = SceneParser.parse({
      'world': [
        {
          'type': 'model3d',
          'model': 'https://example.test/town_hall.glb',
          'normalize': {'height': 6, 'ground': true},
        },
      ],
    });
    final node = scene.nodes.first;
    expect(node.extra?['normalize'], {'height': 6, 'ground': true});
  });
}
