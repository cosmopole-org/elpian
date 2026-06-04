import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';

void main() {
  group('B — SceneNode.localTransform caching', () {
    test('returns the same cached matrix when TRS is unchanged', () {
      final node = SceneNode(type: 'mesh', position: const Vec3(1, 2, 3));
      final a = node.localTransform();
      final b = node.localTransform();
      expect(identical(a, b), isTrue, reason: 'cache hit should reuse Mat4');
    });

    test('recomputes (and stays correct) after position is reassigned', () {
      final node = SceneNode(type: 'mesh', position: const Vec3(1, 0, 0));
      final first = node.localTransform();
      node.position = const Vec3(5, 0, 0);
      final second = node.localTransform();

      expect(identical(first, second), isFalse);
      // Translation lives in column 3 (m[12..14]) for this matrix layout.
      expect(second.m[12], 5.0);
      // A fresh compose must equal the cached recompute.
      final fresh = Mat4.compose(
        const Vec3(5, 0, 0),
        Vec3.zero,
        Vec3.one,
      );
      for (var i = 0; i < 16; i++) {
        expect(second.m[i], closeTo(fresh.m[i], 1e-12));
      }
    });
  });

  group('B — ParticleEmitter pooling + swap-and-pop', () {
    test('live particle count stays bounded and all live particles are alive',
        () {
      final emitter = ParticleEmitter(
        emitRate: 500,
        lifetime: 0.1,
        maxParticles: 32,
      );
      // Advance many steps so particles continually spawn and die.
      for (var i = 0; i < 200; i++) {
        emitter.update(0.016, Vec3.zero);
      }
      expect(emitter.particles.length, lessThanOrEqualTo(32));
      for (final p in emitter.particles) {
        expect(p.life, greaterThan(0));
        expect(p.maxLife, greaterThan(0));
      }
    });

    test('recycled particles are fully reset (no stale life/rotation)', () {
      final emitter = ParticleEmitter(
        emitRate: 1000,
        lifetime: 0.05,
        maxParticles: 16,
      );
      // First burst, then a big step that kills everything (and recycles into
      // the pool) while immediately respawning from that pool.
      emitter.update(0.05, Vec3.zero);
      emitter.update(1.0, Vec3.zero);
      expect(emitter.particles, isNotEmpty,
          reason: 'pool reuse should still produce valid live particles');
      for (final p in emitter.particles) {
        // life must have been reset on reuse, not left stale/negative.
        expect(p.life, greaterThan(0));
        expect(p.life, lessThanOrEqualTo(emitter.lifetime * 1.2 + 1e-9));
      }
    });
  });
}
