// Tests for tappable 3D scene nodes: the parser retains the raw `props` map
// (clickable / panelHref) on parsed nodes, the renderer exposes a screen-space
// projection helper that reuses the last rendered frame's view-projection, and
// GameSceneWidget picks the nearest clickable node under a tap and reports its
// props through the ElpianSceneTaps global hook.

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = ui.Size(160, 160);

/// Camera at (0,0,10) looking straight down -Z at the origin.
Map<String, dynamic> _camera() => {
      'type': 'camera',
      'camera_type': 'Perspective',
      'fov': 60,
      'near': 0.1,
      'far': 220,
      'transform': {
        'position': {'x': 0, 'y': 0, 'z': 10},
        'rotation': {'x': 0, 'y': 0, 'z': 0},
      },
    };

Map<String, dynamic> _cube(num z,
        {Map<String, dynamic>? props, String? id}) =>
    {
      'type': 'mesh3d',
      if (id != null) 'id': id,
      'mesh': {'shape': 'Cube'},
      'material': {
        'base_color': {'r': 0.8, 'g': 0.4, 'b': 0.3},
        'roughness': 0.9,
      },
      'transform': {
        'position': {'x': 0, 'y': 0, 'z': z},
      },
      if (props != null) 'props': props,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SceneParser props retention', () {
    test('model3d, gltf and mesh3d nodes keep their raw props map and id', () {
      final scene = SceneParser.parse({
        'world': [
          {
            'type': 'model3d',
            'id': 'b12',
            'model': 'https://example.com/house.glb',
            'normalize': 4,
            'transform': {
              'position': {'x': 2, 'y': 0, 'z': -3},
            },
            'props': {
              'clickable': true,
              'panelHref': '/buildings/12',
              'buildingId': 12,
            },
          },
          _cube(0, id: 'slot3', props: {
            'clickable': true,
            'panelHref': '/buildings/construct?slot=3',
          }),
          {
            'type': 'group',
            'transform': <String, dynamic>{},
          },
        ],
      });

      expect(scene.nodes, hasLength(3));

      final model = scene.nodes[0];
      expect(model.id, 'b12');
      expect(model.props, isNotNull);
      expect(model.props!['clickable'], isTrue);
      expect(model.props!['panelHref'], '/buildings/12');
      expect(model.props!['buildingId'], 12);

      final mesh = scene.nodes[1];
      expect(mesh.id, 'slot3');
      expect(mesh.props!['clickable'], isTrue);
      expect(mesh.props!['panelHref'], '/buildings/construct?slot=3');

      expect(scene.nodes[2].props, isNull);
    });
  });

  group('Scene3DRenderer.projectSphereToScreen', () {
    /// Renders one frame so the renderer caches the frame's view-projection.
    Scene3DRenderer renderFrame(ParsedScene scene, [ui.Size size = _size]) {
      final renderer = Scene3DRenderer();
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      renderer.render(
        canvas,
        size,
        camera: scene.camera,
        environment: scene.environment,
        lights: scene.lights,
        nodes: scene.nodes,
      );
      recorder.endRecording().dispose();
      return renderer;
    }

    test('projects through the cached frame matrices; nearer is smaller depth',
        () {
      final scene = SceneParser.parse({
        'world': [_camera(), _cube(0)],
      });
      final renderer = renderFrame(scene);
      expect(renderer.lastViewProjection, isNotNull);
      expect(renderer.lastViewportSize, _size);

      // A sphere on the view axis projects to the viewport centre.
      final centre = renderer.projectSphereToScreen(Vec3.zero, 1.0, _size);
      expect(centre, isNotNull);
      expect(centre!.center.dx, closeTo(80, 0.5));
      expect(centre.center.dy, closeTo(80, 0.5));
      expect(centre.radius, greaterThan(0));

      // Depth ordering: the sphere closer to the camera (z=5, camera at z=10)
      // has the smaller depth.
      final near = renderer.projectSphereToScreen(const Vec3(0, 0, 5), 1, _size);
      final far = renderer.projectSphereToScreen(const Vec3(0, 0, -5), 1, _size);
      expect(near, isNotNull);
      expect(far, isNotNull);
      expect(near!.depth, lessThan(far!.depth));

      // Behind the camera → no projection.
      expect(
          renderer.projectSphereToScreen(const Vec3(0, 0, 20), 1, _size), isNull);
    });

    test('maps NDC into the caller-supplied target size (renderScale support)',
        () {
      final scene = SceneParser.parse({
        'world': [_camera(), _cube(0)],
      });
      // Frame rendered at 160x160 (a reduced-renderScale raster) but taps are
      // measured in a 320x320 widget: the projected disc must scale up with
      // the target size, not the raster size.
      final renderer = renderFrame(scene);
      final small = renderer.projectSphereToScreen(Vec3.zero, 1, _size)!;
      final big = renderer
          .projectSphereToScreen(Vec3.zero, 1, const ui.Size(320, 320))!;
      expect(big.center.dx, closeTo(small.center.dx * 2, 0.5));
      expect(big.center.dy, closeTo(small.center.dy * 2, 0.5));
      expect(big.radius, closeTo(small.radius * 2, 0.5));
    });

    test('falls back to the supplied camera before any frame is rendered', () {
      final scene = SceneParser.parse({
        'world': [_camera(), _cube(0)],
      });
      final renderer = Scene3DRenderer(); // no frame rendered
      expect(renderer.projectSphereToScreen(Vec3.zero, 1, _size), isNull);
      final p = renderer.projectSphereToScreen(Vec3.zero, 1, _size,
          camera: scene.camera);
      expect(p, isNotNull);
      expect(p!.center.dx, closeTo(80, 0.5));
      expect(p.center.dy, closeTo(80, 0.5));
    });
  });

  group('GameSceneWidget tap-picking', () {
    // Clickable cubes live in the STATIC world (baked + cached process-wide),
    // proving props survive the static baking/sharing path end to end. The
    // camera is the dynamic part, as in the real game payloads.
    String sceneJson() => jsonEncode({
          'staticKey': 'tap-picking-test-v1',
          'staticWorld': [
            // Non-clickable cube NEAREST to the camera — must be ignored.
            _cube(6),
            // Two clickable cubes behind it, on the same view axis.
            _cube(3, id: 'near', props: {
              'clickable': true,
              'panelHref': '/buildings/near',
              'buildingId': 1,
            }),
            _cube(-4, id: 'far', props: {
              'clickable': true,
              'panelHref': '/buildings/far',
              'buildingId': 2,
            }),
          ],
          'world': [_camera()],
        });

    Widget host({double renderScale = 1.0}) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 200,
                child: GameSceneWidget(
                  sceneJson: sceneJson(),
                  interactive: true,
                  autoStart: false,
                  renderScale: renderScale,
                ),
              ),
            ),
          ),
        );

    testWidgets(
        'tap picks the nearest clickable node, skips non-clickables, '
        'and a miss fires nothing', (tester) async {
      GameSceneWidget.debugClearStaticSceneCache();
      final taps = <Map<String, dynamic>>[];
      ElpianSceneTaps.handler = taps.add;
      addTearDown(() => ElpianSceneTaps.handler = null);

      await tester.pumpWidget(host());
      await tester.pump();

      final widgetFinder = find.byType(GameSceneWidget);
      final centre = tester.getCenter(widgetFinder);

      // All three cubes project onto the widget centre. The non-clickable one
      // is nearest to the camera but must be ignored; of the two clickable
      // ones, the nearer ('near') must win over 'far'.
      await tester.tapAt(centre);
      await tester.pump();
      expect(taps, hasLength(1));
      expect(taps.single['panelHref'], '/buildings/near');
      expect(taps.single['buildingId'], 1);

      // A tap far away from every projected disc fires no callback.
      taps.clear();
      await tester.tapAt(tester.getTopLeft(widgetFinder) + const Offset(4, 4));
      await tester.pump();
      expect(taps, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'picking works when the painter rasterizes at a reduced renderScale '
        '(tap coordinates are widget-space)', (tester) async {
      GameSceneWidget.debugClearStaticSceneCache();
      final taps = <Map<String, dynamic>>[];
      ElpianSceneTaps.handler = taps.add;
      addTearDown(() => ElpianSceneTaps.handler = null);

      await tester.pumpWidget(host(renderScale: 0.5));
      await tester.pump();

      await tester.tapAt(tester.getCenter(find.byType(GameSceneWidget)));
      await tester.pump();
      expect(taps, hasLength(1));
      expect(taps.single['panelHref'], '/buildings/near');
      expect(tester.takeException(), isNull);
    });
  });
}
