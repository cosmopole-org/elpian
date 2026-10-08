import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MockGodotBinding binding;
  late GodotController controller;

  setUp(() {
    binding = MockGodotBinding();
    controller = GodotController(binding: binding);
  });

  tearDown(() => controller.dispose());

  group('op emission', () {
    test('create allocates a handle and emits one op', () async {
      final node = controller.create('Node3D');
      await controller.flush();

      expect(binding.ops, hasLength(1));
      expect(binding.ops.single['new'], 'Node3D');
      expect(binding.ops.single['def'], node.handle);
    });

    test('a handle is usable before the engine has seen the create', () {
      // This is the property that makes the transport one-way: no await here.
      final node = controller.create('MeshInstance3D');
      node.set('visible', true);
      expect(node.handle, greaterThan(HandleAllocator.selfHandle));
    });

    test('set / setAll / call emit the documented op shapes', () async {
      final node = controller.create('Node3D');
      node.set('visible', true);
      node.setAll({'a': 1, 'b': const Vector3(1, 2, 3)});
      node.callVoid('add_child', [node]);
      node.setIndexed('position:x', 5.0);
      await controller.flush();

      final ops = binding.ops;
      expect(ops[1], {'ref': node.handle, 'set': 'visible', 'value': true});
      expect(ops[2]['props'], {
        'a': 1,
        'b': {
          'vec3': [1.0, 2.0, 3.0]
        }
      });
      expect(ops[3]['method'], 'add_child');
      expect(ops[3]['args'], [
        {'ref': node.handle}
      ]);
      expect(ops[4], {'ref': node.handle, 'seti': 'position:x', 'value': 5.0});
    });

    test('singleton, tree and load each carry an allocated handle', () async {
      final s = controller.singleton('Input');
      final t = controller.tree();
      final l = controller.load('res://a.tscn');
      await controller.flush();

      expect(binding.ops[0], {'singleton': 'Input', 'def': s.handle});
      expect(binding.ops[1], {'tree': true, 'def': t.handle});
      expect(binding.ops[2], {'load': 'res://a.tscn', 'def': l.handle});
      expect({s.handle, t.handle, l.handle}, hasLength(3));
    });

    test('mount adds under the reserved self handle', () async {
      final node = controller.create('Node3D');
      controller.mount(node);
      await controller.flush();

      final mountOp = binding.ops.last;
      expect(mountOp['ref'], HandleAllocator.selfHandle);
      expect(mountOp['method'], 'add_child');
    });
  });

  group('batching', () {
    test('an explicit batch defers every op until endBatch', () async {
      controller.beginBatch();
      for (var i = 0; i < 50; i++) {
        controller.create('Node3D');
      }
      expect(binding.ops, isEmpty, reason: 'nothing may cross before endBatch');
      expect(controller.pendingOps, 50);

      await controller.endBatch();
      expect(binding.ops, hasLength(50));
    });

    test('a read flushes queued writes first, preserving order', () async {
      final node = controller.create('Node3D');
      node.set('visible', false);
      await node.get('visible');

      // create, set, then the get — the engine must observe them in that order.
      expect(
          binding.ops.map((o) => o.keys.first).toList(), ['new', 'ref', 'ref']);
      expect(binding.ops[1]['set'], 'visible');
      expect(binding.ops[2]['get'], 'visible');
    });
  });

  group('signals', () {
    test('connect registers a callback and the engine can fire it', () async {
      final node = controller.create('Button');
      List<Object?>? received;
      final id = node.connect('pressed', (args) => received = args);
      await controller.flush();

      final op = binding.ops.last;
      expect(op['connect'], 'pressed');
      expect(op['cb'], id);

      binding.fireSignal(id, [
        {
          'vec3': [1.0, 2.0, 3.0]
        }
      ]);
      expect(received, hasLength(1));
      expect(received!.single, isA<Vector3>());
    });

    test('disconnect stops delivery', () async {
      final node = controller.create('Button');
      var calls = 0;
      final id = node.connect('pressed', (_) => calls++);
      node.disconnect('pressed', id);

      binding.fireSignal(id, const []);
      expect(calls, 0);
    });
  });

  group('G3 helpers', () {
    test('mesh builds MeshInstance3D + primitive + material', () async {
      controller.beginBatch();
      controller.g3.mesh('sphere', options: {
        'radius': 2.0,
        'color': const GodotColor(1, 0, 0, 1),
        'position': [0, 1, 0],
      });
      await controller.endBatch();

      final created = binding.ops
          .where((o) => o.containsKey('new'))
          .map((o) => o['new'])
          .toList();
      expect(created,
          containsAll(['MeshInstance3D', 'SphereMesh', 'StandardMaterial3D']));

      final radius = binding.ops.firstWhere((o) => o['set'] == 'radius');
      expect(radius['value'], {'float': 2.0});

      final position = binding.ops.firstWhere((o) => o['set'] == 'position');
      expect(position['value'], {
        'vec3': [0.0, 1.0, 0.0]
      });
    });

    test('unknown shapes fall back to a box, matching the bridge', () async {
      controller.beginBatch();
      controller.g3.primitive('hexahedron');
      await controller.endBatch();
      expect(binding.ops.first['new'], 'BoxMesh');
    });

    test('environment writes enum values numerically, needing no round trip',
        () async {
      controller.beginBatch();
      controller.g3.environment();
      await controller.endBatch();

      final bg = binding.ops.firstWhere((o) => o['set'] == 'background_mode');
      expect(bg['value'], {'int': 1}, reason: 'Environment.BG_COLOR');
      final ambient =
          binding.ops.firstWhere((o) => o['set'] == 'ambient_light_source');
      expect(ambient['value'], {'int': 3},
          reason: 'Environment.AMBIENT_SOURCE_COLOR');
    });

    test('vec3 coerces lists, scalars and Vector3', () {
      expect(Godot3D.vec3(const Vector3(1, 2, 3), 0, 0, 0).x, 1);
      expect(Godot3D.vec3([4, 5, 6], 0, 0, 0).y, 5);
      expect(Godot3D.vec3(2, 0, 0, 0).z, 2, reason: 'a scalar is uniform');
      expect(Godot3D.vec3(null, 7, 8, 9).x, 7,
          reason: 'null takes the default');
    });
  });

  group('surface lifecycle', () {
    test('attach binds the root handle to this surface', () async {
      await controller.attachSurface();
      expect(
          binding.surfaces[controller.surfaceId], HandleAllocator.selfHandle);
    });

    test('detach releases it', () async {
      await controller.attachSurface();
      await controller.detachSurface();
      expect(binding.surfaces, isEmpty);
    });

    test('ops after dispose are dropped rather than throwing', () async {
      controller.dispose();
      controller.create('Node3D');
      await controller.flush();
      expect(binding.ops, isEmpty);
    });
  });
}
