// A ground/sea plane far larger than the view frustum must still rasterize:
// its corners project way outside NDC while its surface fills the viewport.
// Whole-triangle rejection on any out-of-bounds vertex (the old "loose
// frustum cull") made every large floor invisible — the camera-facing half of
// the scene rendered pure sky. Triangles are now Sutherland–Hodgman-clipped
// against the near plane and the four frustum sides.

import 'dart:ui' as ui;

import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = ui.Size(160, 160);

Map<String, dynamic> _scene({required double planeSize}) => {
      'world': [
        {
          'type': 'environment',
          'sky_color_top': {'r': 0.0, 'g': 0.0, 'b': 1.0},
          'sky_color_bottom': {'r': 0.0, 'g': 0.0, 'b': 1.0},
          'ambient_light': {'r': 1.0, 'g': 1.0, 'b': 1.0},
          'ambient_intensity': 1.0,
        },
        {
          'type': 'camera',
          'camera_type': 'Perspective',
          'fov': 60,
          'near': 0.1,
          'far': 500,
          'transform': {
            'position': {'x': 0, 'y': 6, 'z': 14},
            'rotation': {'x': -25, 'y': 0, 'z': 0},
          },
        },
        {
          'type': 'light',
          'light_type': 'Directional',
          'color': {'r': 1, 'g': 1, 'b': 1},
          'intensity': 1.0,
          'transform': {
            'rotation': {'x': -50, 'y': 20, 'z': 0},
          },
        },
        {
          'type': 'mesh3d',
          'mesh': {'shape': 'Plane', 'size': planeSize},
          'material': {
            'base_color': {'r': 1.0, 'g': 0.0, 'b': 0.0},
            'roughness': 1.0,
          },
          'transform': {
            'position': {'x': 0, 'y': 0, 'z': 0}
          },
        },
      ],
    };

Future<List<int>> _render(Map<String, dynamic> json) async {
  final scene = SceneParser.parse(json);
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

/// Sample RGB at (x, y).
(int, int, int) _px(List<int> rgba, int x, int y) {
  final o = (y * _size.width.toInt() + x) * 4;
  return (rgba[o], rgba[o + 1], rgba[o + 2]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a plane much larger than the frustum still covers the lower viewport',
      () async {
    for (final planeSize in [20.0, 240.0, 2000.0]) {
      final rgba = await _render(_scene(planeSize: planeSize));
      // The bottom-center of the frame looks down at the plane: red, not the
      // blue sky.
      final (r, g, b) = _px(rgba, 80, 140);
      expect(r, greaterThan(100),
          reason: 'plane(size=$planeSize) not rasterized at bottom-center');
      expect(b, lessThan(100),
          reason: 'plane(size=$planeSize): sky visible where the plane must be');
      // The top of the frame is sky.
      final (skyR, _, skyB) = _px(rgba, 80, 8);
      expect(skyB, greaterThan(100), reason: 'sky missing (size=$planeSize)');
      expect(skyR, lessThan(100), reason: 'sky overdrawn (size=$planeSize)');
    }
  });
}
