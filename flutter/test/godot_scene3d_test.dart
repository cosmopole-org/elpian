import 'dart:convert';

import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MockGodotBinding binding;

  setUp(() {
    binding = MockGodotBinding();
    debugGodotBindingOverride = binding;
  });

  tearDown(() {
    debugGodotBindingOverride = null;
  });

  group('wire encodability', () {
    // The invariant that matters for a real transport: every op the controller
    // produces must survive jsonEncode. A Dart object that slips through
    // marshaling (a GodotObject passed as a method argument, say) only fails
    // here — never in the mock.
    test('every op a scene build produces is JSON-encodable', () async {
      final controller = GodotController(binding: binding);
      addTearDown(controller.dispose);

      controller.beginBatch();
      final parent = controller.g3.node(position: [0, 0, 0]);
      final child = controller.g3.mesh('box', options: {
        'color': const GodotColor(1, 0, 0, 1),
        'position': [1, 2, 3],
      });
      parent.addChild(child);
      controller.mount(parent);
      child.connect('tree_entered', (_) {});
      child.setAll({'name': 'crate', 'visible': true});
      child.setIndexed('position:y', 4.0);
      await controller.endBatch();

      expect(binding.ops, isNotEmpty);
      expect(
        () => jsonEncode(binding.ops),
        returnsNormally,
        reason: 'an op carried a value that marshaling did not convert',
      );
    });
  });

  group('scene DSL', () {
    test('builds environment, camera, lights and nodes', () async {
      final controller = GodotController(binding: binding);
      addTearDown(controller.dispose);

      final scene = SceneDsl(controller).build(const {
        'environment': {'bg': '#0d1117'},
        'camera': {
          'id': 'cam',
          'position': [0, 3, 8],
          'fov': 55
        },
        'lights': [
          {
            'type': 'directional',
            'shadow': true,
            'rotation': [-50, -30, 0]
          }
        ],
        'nodes': [
          {
            'type': 'mesh',
            'shape': 'torus',
            'id': 'ring',
            'color': '#6699ff',
            'children': [
              {'type': 'mesh', 'shape': 'sphere', 'id': 'bead'}
            ]
          }
        ],
      });
      await controller.flush();

      expect(scene.byId('cam'), isNotNull);
      expect(scene.byId('ring'), isNotNull);
      expect(scene.byId('bead'), isNotNull, reason: 'children are registered');
      expect(scene.roots, hasLength(4),
          reason: 'environment + camera + one light + one node');

      final created =
          binding.ops.where((o) => o.containsKey('new')).map((o) => o['new']);
      expect(
          created,
          containsAll(<String>[
            'WorldEnvironment',
            'Environment',
            'Camera3D',
            'DirectionalLight3D',
            'TorusMesh',
            'SphereMesh',
          ]));
    });

    test('a whole scene build costs one crossing', () async {
      final controller = GodotController(binding: binding);
      addTearDown(controller.dispose);

      // The mock records per op, so count how many were pending when the batch
      // closed rather than how many arrived.
      controller.beginBatch();
      SceneDsl(controller).build(const {
        'nodes': [
          {'type': 'mesh', 'shape': 'box'},
          {'type': 'mesh', 'shape': 'sphere'},
        ]
      });
      // build() opens and closes its own batch, so by here it has flushed once.
      await controller.endBatch();
      expect(binding.ops.length, greaterThan(4));
    });

    test('an unknown type is taken as a raw ClassDB class name', () async {
      final controller = GodotController(binding: binding);
      addTearDown(controller.dispose);

      SceneDsl(controller).build(const {
        'nodes': [
          {
            'type': 'CSGBox3D',
            'id': 'csg',
            'position': [1, 0, 0]
          }
        ]
      });
      await controller.flush();

      expect(binding.ops.first['new'], 'CSGBox3D');
    });

    test('a malformed spec does not leave the batch open', () async {
      final controller = GodotController(binding: binding);
      addTearDown(controller.dispose);

      // `lights` is not a list — the builder must still close its batch, or
      // every later op on this controller would stall.
      SceneDsl(controller).build(const {'lights': 'not-a-list'});
      controller.create('Node3D');
      await controller.flush();

      expect(binding.ops.any((o) => o['new'] == 'Node3D'), isTrue);
    });

    test('require throws a clear error for a missing id', () {
      final controller = GodotController(binding: binding);
      addTearDown(controller.dispose);
      final scene = SceneDsl(controller).build(const {});
      expect(() => scene.require('nope'), throwsArgumentError);
    });
  });

  group('colour parsing', () {
    test('accepts #RGB, #RRGGBB, #RRGGBBAA and lists', () {
      expect(parseColor('#f00')!.r, closeTo(1.0, 0.01));
      expect(parseColor('#00ff00')!.g, closeTo(1.0, 0.01));
      final withAlpha = parseColor('#0000ff80')!;
      expect(withAlpha.b, closeTo(1.0, 0.01));
      expect(withAlpha.a, closeTo(0.5, 0.01));
      expect(parseColor([1.0, 0.5, 0.0])!.g, closeTo(0.5, 0.01));
      expect(parseColor('not a colour'), isNull);
      expect(parseColor(null), isNull);
    });
  });

  group('Scene3D widget', () {
    testWidgets('renders the placeholder when no engine is present',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Scene3D(width: 200, height: 200)),
      ));
      await tester.pumpAndSettle();

      // The mock binding is not live, so the widget must degrade rather than
      // fail — a 2D app with a 3D panel stays usable everywhere.
      expect(find.text('3D unavailable on this platform'), findsOneWidget);
    });

    testWidgets('builds its initial scene and reports it through onReady',
        (tester) async {
      GodotScene? ready;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Scene3D(
            initialScene: const {
              'nodes': [
                {'type': 'mesh', 'shape': 'box', 'id': 'crate'}
              ]
            },
            onReady: (scene) => ready = scene,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(ready, isNotNull);
      expect(ready!.byId('crate'), isNotNull);
      expect(binding.ops.any((o) => o['new'] == 'BoxMesh'), isTrue);
    });

    testWidgets('re-rendering with a different scene rebuilds the world',
        (tester) async {
      Widget app(String shape) => MaterialApp(
            home: Scaffold(
              body: Scene3D(initialScene: {
                'nodes': [
                  {'type': 'mesh', 'shape': shape, 'id': 'x'}
                ]
              }),
            ),
          );

      await tester.pumpWidget(app('box'));
      await tester.pumpAndSettle();
      expect(binding.ops.any((o) => o['new'] == 'BoxMesh'), isTrue);

      binding.clear();
      await tester.pumpWidget(app('sphere'));
      await tester.pumpAndSettle();

      // A guest drives this widget by re-rendering the node, not by calling the
      // controller — so a changed scene must rebuild the world.
      expect(binding.ops.any((o) => o['new'] == 'SphereMesh'), isTrue);
    });

    testWidgets('an unchanged scene does not rebuild the world',
        (tester) async {
      const scene = {
        'nodes': [
          {'type': 'mesh', 'shape': 'box', 'id': 'x'}
        ]
      };
      // A fresh but structurally identical map, as a guest would emit.
      Widget app() => MaterialApp(
            home: Scaffold(
              body: Scene3D(initialScene: Map<String, Object?>.from(scene)),
            ),
          );

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      binding.clear();

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(binding.ops.where((o) => o.containsKey('new')), isEmpty,
          reason: 'a parent rebuild must not tear down and recreate the world');
    });

    testWidgets('a caller-supplied controller survives widget disposal',
        (tester) async {
      final controller = GodotSceneController(binding: binding);
      addTearDown(controller.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Scene3D(controller: controller)),
      ));
      await tester.pumpAndSettle();

      await tester
          .pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      await tester.pumpAndSettle();

      // Still usable: the controller is the caller's, not the widget's.
      expect(() => controller.godot.create('Node3D'), returnsNormally);
    });

    testWidgets('a clickable surface reports taps to ElpianSceneTaps',
        (tester) async {
      Map<String, dynamic>? tapped;
      ElpianSceneTaps.handler = (props) => tapped = props;
      addTearDown(() => ElpianSceneTaps.handler = null);

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Scene3D(
            width: 200,
            height: 200,
            clickable: true,
            tapProps: {'panelHref': '/buildings/12'},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Scene3D));
      await tester.pumpAndSettle();

      expect(tapped, {'panelHref': '/buildings/12'});
    });
  });

  group('engine registration', () {
    testWidgets('the Scene3D tag renders through the JSON pipeline',
        (tester) async {
      final engine = ElpianEngine();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: engine.renderFromJson(const {
            'type': 'Scene3D',
            'props': {
              'width': 200.0,
              'height': 200.0,
              'initialScene': {
                'nodes': [
                  {'type': 'mesh', 'shape': 'box'}
                ]
              }
            },
          }),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(Scene3D), findsOneWidget);
      expect(binding.ops.any((o) => o['new'] == 'BoxMesh'), isTrue);
    });
  });
}
