// Micro-benchmark for the static-geometry render path. Builds a city-sized set
// of static meshes and renders many frames with a moving camera, comparing the
// baked+culled static path against the per-frame dynamic path. The static path
// transforms+lights each triangle once and only re-projects (and frustum-culls)
// thereafter, so it should be materially faster. Timings are printed; the
// assertion is a loose sanity bound so it never flakes in CI.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = ui.Size(480, 270);

Map<String, dynamic> _bigScene() {
  final world = <Map<String, dynamic>>[
    {
      'type': 'environment',
      'ambient_light': {'r': 0.30, 'g': 0.32, 'b': 0.40},
      'ambient_intensity': 0.5,
      'fog_type': 'linear',
      'fog_color': {'r': 0.30, 'g': 0.32, 'b': 0.40},
      'fog_near': 20,
      'fog_distance': 60,
    },
    {
      'type': 'light',
      'light_type': 'Directional',
      'color': {'r': 1.0, 'g': 0.9, 'b': 0.8},
      'intensity': 1.2,
      'transform': {'rotation': {'x': -35, 'y': 30, 'z': 0}},
    },
    {
      'type': 'light',
      'light_type': 'Point',
      'color': {'r': 0.5, 'g': 0.7, 'b': 1.0},
      'intensity': 1.2,
      'range': 14,
      'transform': {'position': {'x': 0, 'y': 4, 'z': 0}},
    },
  ];
  // A 12×12 grid of towers (box) each capped with a sphere — a few thousand
  // triangles, comparable to the game's static block.
  for (var gx = -6; gx < 6; gx++) {
    for (var gz = -6; gz < 6; gz++) {
      final x = gx * 4.0, z = gz * 4.0;
      final h = 4.0 + ((gx + gz) % 5).abs();
      world.add({
        'type': 'mesh3d',
        'mesh': {'shape': 'Cube'},
        'material': {
          'base_color': {'r': 0.4, 'g': 0.42, 'b': 0.5},
          'roughness': 0.9,
          'texture': 'checkerboard',
          'texture_color2': {'r': 0.7, 'g': 0.7, 'b': 0.55},
          'texture_scale': 6,
        },
        'transform': {
          'position': {'x': x, 'y': h / 2, 'z': z},
          'scale': {'x': 2.4, 'y': h, 'z': 2.4},
        },
      });
      world.add({
        'type': 'mesh3d',
        'mesh': {'shape': 'Sphere', 'radius': 1.0, 'segments': 12},
        'material': {
          'base_color': {'r': 0.2, 'g': 0.5, 'b': 0.25},
          'roughness': 1.0,
        },
        'transform': {'position': {'x': x, 'y': h + 0.6, 'z': z}},
      });
    }
  }
  return {'world': world};
}

void _markStatic(SceneNode n) {
  n.isStatic = true;
  for (final c in n.children) {
    _markStatic(c);
  }
}

double _run({required bool static, required int frames}) {
  final parsed = SceneParser.parse(_bigScene());
  if (static) {
    for (final n in parsed.nodes) {
      _markStatic(n);
    }
  }
  final renderer = Scene3DRenderer();
  final sw = Stopwatch();
  for (var f = 0; f < frames; f++) {
    // Orbit the camera so projection (and culling) changes every frame.
    final a = f / frames * 2 * math.pi;
    parsed.camera.position = Vec3(26 * math.cos(a), 18, 26 * math.sin(a));
    parsed.camera.target = Vec3.zero;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    // First frame primes the static cache; time the rest.
    if (f == 1) sw.start();
    renderer.render(
      canvas,
      _size,
      camera: parsed.camera,
      environment: parsed.environment,
      lights: parsed.lights,
      nodes: parsed.nodes,
    );
    recorder.endRecording();
  }
  sw.stop();
  return sw.elapsedMicroseconds / 1000.0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('static-baked render path is faster than the dynamic path', () {
    const frames = 40;
    // Warm both paths (JIT) before timing.
    _run(static: false, frames: 4);
    _run(static: true, frames: 4);

    final dynamicMs = _run(static: false, frames: frames);
    final staticMs = _run(static: true, frames: frames);

    // ignore: avoid_print
    print('static-render benchmark over $frames frames: '
        'dynamic=${dynamicMs.toStringAsFixed(1)}ms '
        'static=${staticMs.toStringAsFixed(1)}ms '
        'speedup=${(dynamicMs / staticMs).toStringAsFixed(2)}x');

    // Loose sanity bound: the baked path must not be meaningfully slower.
    expect(staticMs, lessThan(dynamicMs * 1.1),
        reason: 'baked static path should be at least as fast as dynamic');
  });
}
