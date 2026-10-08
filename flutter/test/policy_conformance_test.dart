import 'dart:convert';
import 'dart:io';

import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Dart half of the shared policy conformance corpus.
///
/// The Rust half is `rust/crates/elpian-host/tests/policy_conformance.rs` and
/// reads the same file. A case that passes on one side and fails on the other
/// means a mini app would hold different capabilities on a device than on the
/// host — and the difference would only ever surface as a bug in whichever
/// direction was more permissive. `ElpianCapability.surface` being absent while
/// the VM had it was exactly that, which is why this corpus exists.
void main() {
  final corpusFile = File('test/fixtures/policy_corpus.json');
  final corpus =
      jsonDecode(corpusFile.readAsStringSync()) as Map<String, dynamic>;
  final cases = (corpus['cases'] as List).cast<Map<String, dynamic>>();

  Set<ElpianCapability> capsOf(dynamic raw) {
    final out = <ElpianCapability>{};
    for (final name in (raw as List? ?? const [])) {
      final cap = ElpianCapability.fromWireName(name.toString());
      // Unknown names are dropped, matching the Rust side and
      // `MiniAppManifest.fromJson`.
      if (cap != null) out.add(cap);
    }
    return out;
  }

  ElpianLimits? limitsOf(dynamic raw) {
    if (raw is! Map) return null;
    int? axis(String name) => raw[name] as int?;
    return ElpianLimits(
      maxInstructions: axis('maxInstructions'),
      maxInstructionsPerTurn: axis('maxInstructionsPerTurn'),
      maxMemoryBytes: axis('maxMemoryBytes'),
      maxStorageBytes: axis('maxStorageBytes'),
      maxCallDepth: axis('maxCallDepth'),
    );
  }

  test('the corpus has not lost cases', () {
    expect(cases.length, greaterThanOrEqualTo(16));
  });

  for (final testCase in cases) {
    final name = testCase['name'] as String;
    test('policy corpus: $name', () {
      final manifestJson = testCase['manifest'] as Map<String, dynamic>;
      final grantJson = testCase['grant'] as Map<String, dynamic>;
      final expected = testCase['expect'] as Map<String, dynamic>;

      final manifest = MiniAppManifest(
        id: 'corpus',
        name: 'corpus',
        version: '1.0.0',
        entrypoint: 'main',
        runtime: ElpianRuntime.elpian,
        requestedCapabilities: capsOf(manifestJson['requestedCapabilities']),
        requestedLimits: limitsOf(manifestJson['requestedLimits']),
        allowsChildren: manifestJson['allowsChildren'] as bool? ?? false,
      );

      final grant = MiniAppGrant(
        capabilities: capsOf(grantJson['capabilities']),
        limits: limitsOf(grantJson['limits']) ?? ElpianLimits.unlimited,
        mayHostChildren: grantJson['mayHostChildren'] as bool? ?? false,
      );

      final policy = MiniAppPolicy.resolve(manifest, grant);

      expect(
        policy.capabilities.map((c) => c.wireName).toSet(),
        capsOf(expected['capabilities']).map((c) => c.wireName).toSet(),
        reason: 'capabilities',
      );
      expect(
        policy.deniedRequests.map((c) => c.wireName).toSet(),
        capsOf(expected['denied']).map((c) => c.wireName).toSet(),
        reason: 'denied set',
      );

      if (expected.containsKey('mayHostChildren')) {
        expect(policy.mayHostChildren, expected['mayHostChildren'],
            reason: 'mayHostChildren');
      }

      final expectedLimits = expected['limits'];
      if (expectedLimits is Map) {
        // Only the axes a case names are checked, so a case can speak about one
        // axis without restating the other four.
        final actual = <String, int?>{
          'maxInstructions': policy.limits.maxInstructions,
          'maxInstructionsPerTurn': policy.limits.maxInstructionsPerTurn,
          'maxMemoryBytes': policy.limits.maxMemoryBytes,
          'maxStorageBytes': policy.limits.maxStorageBytes,
          'maxCallDepth': policy.limits.maxCallDepth,
        };
        for (final axis in expectedLimits.keys) {
          expect(actual[axis], expectedLimits[axis], reason: axis as String);
        }
      }
    });
  }
}
