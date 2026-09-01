import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('value marshaling', () {
    test('vectors, colours and transforms use the bridge wire tags', () {
      expect(marshal(const Vector3(1, 2, 3)), {
        'vec3': [1.0, 2.0, 3.0]
      });
      expect(marshal(const Vector2i(4, 5)), {
        'vec2i': [4, 5]
      });
      expect(marshal(const GodotColor(1, 0, 0, 1)), {
        'color': [1.0, 0.0, 0.0, 1.0]
      });
      expect(marshal(const Transform3D([1, 2, 3])), {
        'xform3d': [1, 2, 3]
      });
      expect(marshal(const StringName('hp')), {'sname': 'hp'});
      expect(marshal(const NodePath('a/b')), {'npath': 'a/b'});
      expect(marshal(const GRid(7)), {'rid': 7});
    });

    test('GInt and GFloat force the numeric Variant', () {
      expect(marshal(const GInt(18)), {'int': 18});
      expect(marshal(const GFloat(1)), {'float': 1.0});
    });

    test('bare numbers marshal by their Dart type', () {
      expect(marshal(3), 3);
      expect(marshal(3.5), 3.5);
    });

    test('lists and maps recurse; a map becomes a Dictionary', () {
      expect(marshal([const Vector2(1, 2), 3]), [
        {
          'vec2': [1.0, 2.0]
        },
        3
      ]);
      expect(marshal({'p': const Vector3(0, 1, 0)}), {
        'dict': {
          'p': {
            'vec3': [0.0, 1.0, 0.0]
          }
        }
      });
    });

    test('unmarshal is the inverse for every tagged shape', () {
      for (final value in <GodotValue>[
        const Vector2(1, 2),
        const Vector3(1, 2, 3),
        const Vector4(1, 2, 3, 4),
        const Vector2i(1, 2),
        const Vector3i(1, 2, 3),
        const GodotColor(0.1, 0.2, 0.3, 0.4),
        const Rect2(1, 2, 3, 4),
        const Plane(0, 1, 0, 2),
        const Quaternion(0, 0, 0, 1),
        const AABB(0, 0, 0, 1, 1, 1),
        const StringName('x'),
        const NodePath('a/b'),
        const GRid(9),
      ]) {
        final round = unmarshal(value.toWire());
        expect(round, isA<GodotValue>(),
            reason: '${value.runtimeType} did not round-trip');
        expect((round as GodotValue).toWire(), value.toWire(),
            reason: '${value.runtimeType} round-tripped to a different wire');
      }
    });

    test('handles round-trip as GodotRef', () {
      expect(unmarshal({'ref': 42}), const GodotRef(42));
      expect(marshal(const GodotRef(42)), {'ref': 42});
    });

    test('GodotColor.hex decodes 0xRRGGBB', () {
      final c = GodotColor.hex(0xFF8000);
      expect(c.r, closeTo(1.0, 0.01));
      expect(c.g, closeTo(0.502, 0.01));
      expect(c.b, closeTo(0.0, 0.01));
      expect(c.a, 1.0);
    });

    test('errors pass through unmarshal untouched', () {
      final err = wireError('boom');
      expect(isWireError(err), isTrue);
      expect(wireErrorMessage(err), 'boom');
      expect(unmarshal(err), err);
    });
  });

  group('handle allocation', () {
    test('never issues the reserved self handle', () {
      final alloc = HandleAllocator();
      final handles = List.generate(5, (_) => alloc.allocate());
      expect(handles, isNot(contains(HandleAllocator.selfHandle)));
      expect(handles, handles.toSet().toList(), reason: 'handles must be unique');
    });
  });
}
