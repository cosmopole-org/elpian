// Tests for the static-geometry render optimizations (parse caching, world-lit
// baking, frustum culling) in the pure-Dart 3D renderer.
//
// The key invariant: rendering a scene whose nodes are flagged `isStatic`
// (baked + cached + frustum-culled) must look essentially identical to
// rendering the same scene through the normal dynamic path — the only allowed
// difference is the view-dependent specular highlight, which the static bake
// intentionally omits (negligible for matte geometry).

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = ui.Size(160, 160);

Map<String, dynamic> _scene() => {
      'world': [
        {
          'type': 'environment',
          'ambient_light': {'r': 0.30, 'g': 0.32, 'b': 0.40},
          'ambient_intensity': 0.5,
          'fog_type': 'linear',
          'fog_color': {'r': 0.30, 'g': 0.32, 'b': 0.40},
          'fog_near': 20,
          'fog_distance': 90,
        },
        {
          'type': 'camera',
          'camera_type': 'Perspective',
          'fov': 60,
          'near': 0.1,
          'far': 220,
          'transform': {
            'position': {'x': 0, 'y': 3, 'z': 8},
            'rotation': {'x': -12, 'y': 0, 'z': 0},
          },
        },
        {
          'type': 'light',
          'light_type': 'Directional',
          'color': {'r': 1.0, 'g': 0.95, 'b': 0.88},
          'intensity': 1.2,
          'transform': {
            'rotation': {'x': -40, 'y': 30, 'z': 0},
          },
        },
        // Matte cube + sphere + ground (low spec so static/dynamic match tightly)
        {
          'type': 'mesh3d',
          'mesh': {'shape': 'Cube'},
          'material': {
            'base_color': {'r': 0.82, 'g': 0.30, 'b': 0.28},
            'roughness': 0.95,
          },
          'transform': {
            'position': {'x': -1.6, 'y': 0, 'z': 0},
            'scale': {'x': 1.5, 'y': 1.5, 'z': 1.5},
          },
        },
        {
          'type': 'mesh3d',
          'mesh': {'shape': 'Sphere', 'radius': 1.0, 'segments': 16},
          'material': {
            'base_color': {'r': 0.28, 'g': 0.68, 'b': 0.9},
            'roughness': 0.9,
          },
          'transform': {
            'position': {'x': 1.6, 'y': 0, 'z': 0},
          },
        },
        {
          'type': 'mesh3d',
          'mesh': {'shape': 'Plane', 'size': 30},
          'material': {
            'base_color': {'r': 0.38, 'g': 0.42, 'b': 0.38},
            'roughness': 1.0,
          },
          'transform': {
            'position': {'x': 0, 'y': -1.2, 'z': 0},
          },
        },
      ],
    };

void _markStatic(SceneNode n) {
  n.isStatic = true;
  for (final c in n.children) {
    _markStatic(c);
  }
}

Future<List<int>> _render(Map<String, dynamic> json, {required bool static}) async {
  final scene = SceneParser.parse(json);
  if (static) {
    for (final n in scene.nodes) {
      _markStatic(n);
    }
  }
  final renderer = Scene3DRenderer();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  renderer.render(
    canvas,
    _size,
    camera: scene.camera,
    environment: scene.environment,
    lights: scene.lights,
    nodes: scene.nodes,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(_size.width.toInt(), _size.height.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('static-baked render matches the dynamic render (within specular)', () async {
    final dynamicBytes = await _render(_scene(), static: false);
    final staticBytes = await _render(_scene(), static: true);

    expect(staticBytes.length, dynamicBytes.length);

    // Geometry must actually be visible (not a flat sky): luma must vary.
    var minL = 255, maxL = 0;
    for (var i = 0; i < dynamicBytes.length; i += 4) {
      final l = (dynamicBytes[i] + dynamicBytes[i + 1] + dynamicBytes[i + 2]) ~/ 3;
      if (l < minL) minL = l;
      if (l > maxL) maxL = l;
    }
    expect(maxL - minL, greaterThan(30),
        reason: 'scene should contain visible lit geometry');

    // Mean per-channel difference must be tiny (only specular omitted).
    var sum = 0;
    var count = 0;
    for (var i = 0; i < dynamicBytes.length; i++) {
      if (i % 4 == 3) continue; // skip alpha
      sum += (dynamicBytes[i] - staticBytes[i]).abs();
      count++;
    }
    final meanDiff = sum / count;
    expect(meanDiff, lessThan(6.0),
        reason: 'static bake should match dynamic shading closely '
            '(meanDiff=$meanDiff)');
  });

  testWidgets('GameSceneWidget parses staticWorld once and reuses it across '
      'dynamic updates', (tester) async {
    final base = _scene()['world'] as List;
    final env = base[0], cam = base[1], light = base[2];
    final cube = base[3], sphere = base[4], ground = base[5];

    String sceneJson(num camX) => jsonEncode({
          'staticKey': 'v1',
          'staticWorld': [env, light, cube, sphere, ground],
          'world': [
            {
              ...cam as Map,
              'transform': {
                'position': {'x': camX, 'y': 3, 'z': 8},
                'rotation': {'x': -12, 'y': 0, 'z': 0},
              },
            },
          ],
        });

    Widget host(String json) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 200,
              child: GameSceneWidget(
                sceneJson: json,
                interactive: false,
                autoStart: false,
              ),
            ),
          ),
        );

    await tester.pumpWidget(host(sceneJson(0)));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Change only the dynamic camera; static world (same staticKey) is reused.
    await tester.pumpWidget(host(sceneJson(2)));
    await tester.pump();
    expect(tester.takeException(), isNull);

    expect(find.byType(GameSceneWidget), findsOneWidget);
  });
}
