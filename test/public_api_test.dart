// Each focused entrypoint must stand on its own.
//
// `elpian_ui.dart` was a flat barrel of ~200 exports with no layering: every
// internal widget class sat at the same level as the engine, and a super-app
// shell reaching for a capability enum had to pull in the whole widget set to
// get it. Governance was not exported at all.
//
// These imports are the test. Each entrypoint is imported *alone*, under a
// prefix, and used — so a missing export or an accidental dependency on the
// full barrel fails the build rather than being noticed later by a consumer.
import 'package:elpian_ui/elpian_governance.dart' as governance;
import 'package:elpian_ui/elpian_godot.dart' as godot;
import 'package:elpian_ui/elpian_runtime.dart' as runtime;
import 'package:elpian_ui/elpian_ui.dart' as everything;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('elpian_governance.dart', () {
    test('carries the whole control plane without the widget set', () {
      // Policy: what an app declares, what it is granted, what it gets.
      const manifest = governance.MiniAppManifest(
        id: 'probe',
        name: 'Probe',
        requestedCapabilities: {governance.ElpianCapability.render},
      );
      final policy = governance.MiniAppPolicy.resolve(
        manifest,
        governance.MiniAppGrant.untrusted,
      );
      expect(policy.capabilities, {governance.ElpianCapability.render});

      // Budgets and meters.
      expect(governance.ElpianLimits.sandboxed.maxInstructions, isNotNull);
      expect(governance.ElpianUsage.zero.instructions, 0);

      // The isolation unit policy is enforced against.
      expect(governance.ElpianServices(appId: 'probe').appId, 'probe');

      // Which capability gates a given host API.
      expect(
          governance.VmHostApiCatalog.capabilityFor('dom.appendChild'), 'dom');

      // Honest reporting of what a backend enforces.
      expect(
          governance.GovernanceSupport.none.canSandboxUntrustedCode, isFalse);
      expect(governance.GovernanceSupport.full.canSandboxUntrustedCode, isTrue);
    });
  });

  group('elpian_runtime.dart', () {
    test('carries the runtimes and their governance', () {
      expect(runtime.ElpianRuntime.values, hasLength(3));
      expect(runtime.ElpianVm.isRuntimeAvailable, isA<bool>());
      // Governance travels with the runtime: anything that can start a mini
      // app should always be able to bound it.
      expect(runtime.ElpianLimits.unlimited.maxInstructions, isNull);
    });
  });

  group('elpian_godot.dart', () {
    test('carries the 3D surface and its protocol', () {
      expect(godot.OpKey.create, 'new');
      expect(godot.MockGodotBinding().isLive, isFalse);
    });
  });

  group('elpian_ui.dart', () {
    test('is a superset — nothing is reachable only through a subset', () {
      // Sampled from each focused entrypoint. If the main barrel ever stops
      // re-exporting one of them, this stops compiling.
      expect(everything.ElpianCapability.render, isNotNull);
      expect(everything.ElpianLimits.sandboxed, isNotNull);
      expect(everything.MiniAppGrant.untrusted, isNotNull);
      expect(everything.ElpianRuntime.elpian, isNotNull);
      expect(everything.OpKey.create, 'new');
      // ...and the widget set the focused entrypoints deliberately omit.
      expect(everything.ElpianEngine(), isNotNull);
    });
  });
}
