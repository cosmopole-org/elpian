import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// The governance control plane, driven from Flutter across the real FFI
/// boundary.
///
/// This is the gap the refactor closed: every one of these mechanisms existed
/// in the Rust VM from the start, and none of it crossed to Dart. A Flutter
/// host could start a mini app and then had no say over what it did, how much
/// it spent, or whether it kept running.
///
/// The tests skip when the native library has not been built; CI builds it
/// first, so the bodies always run there.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final skip = ElpianVm.isRuntimeAvailable
      ? null
      : 'Native VM library not built. Run: cd rust && cargo build --release';

  /// A mini app that renders once — enough to be a real, running instance.
  const program = '''
{"type":"program","body":[
  {"type":"host_call","data":{"name":"render","args":[
    {"type":"string","data":{"value":"{\\"type\\":\\"text\\",\\"text\\":\\"hi\\"}"}}
  ]}}
]}''';

  Future<ElpianVm> spawn(String id) async {
    final vm = await ElpianVm.fromAst(id, program);
    expect(vm, isNotNull, reason: ElpianVm.lastApiError);
    return vm!;
  }

  group('budgets', () {
    test('a host can bound a mini app and read back the policy', () async {
      final vm = await spawn('gov-dart-limits');

      await vm.governor.setLimits(ElpianLimits.sandboxed);
      final read = await vm.governor.getLimits();

      expect(read.maxInstructions, ElpianLimits.sandboxed.maxInstructions);
      expect(read.maxMemoryBytes, ElpianLimits.sandboxed.maxMemoryBytes);
      expect(read.maxCallDepth, ElpianLimits.sandboxed.maxCallDepth);

      await vm.dispose();
    }, skip: skip);

    test('a host can meter what a mini app has spent', () async {
      final vm = await spawn('gov-dart-usage');
      vm.registerHostHandler(
          'render', (_, __) => '{"type":"string","data":{"value":"ok"}}');
      await vm.run();

      final used = await vm.governor.usage();
      expect(used.instructions, greaterThan(0),
          reason: 'running the program should register work');

      final pressure = used.pressureAgainst(ElpianLimits.sandboxed);
      expect(pressure['instructions'], isNotNull);
      expect(pressure['instructions'], lessThan(1.0));

      await vm.dispose();
    }, skip: skip);

    test('an unlimited policy reports no ceilings', () async {
      final vm = await spawn('gov-dart-unlimited');
      await vm.governor.setLimits(ElpianLimits.unlimited);

      final read = await vm.governor.getLimits();
      expect(read.maxInstructions, isNull);
      expect(read.maxMemoryBytes, isNull);

      await vm.dispose();
    }, skip: skip);
  });

  group('capabilities', () {
    test('a host can revoke one capability without touching the rest',
        () async {
      final vm = await spawn('gov-dart-caps');

      expect(await vm.governor.allowsApi('net.fetch'), isTrue);
      await vm.governor.setCapability(ElpianCapability.network, false);

      expect(await vm.governor.allowsApi('net.fetch'), isFalse);
      expect(await vm.governor.allowsApi('dom.appendChild'), isTrue,
          reason: 'revoking the network must not touch the document tree');

      await vm.dispose();
    }, skip: skip);

    test('sandbox denies everything then grants only what is asked', () async {
      final vm = await spawn('gov-dart-sandbox');

      await vm.governor.sandbox({
        ElpianCapability.render,
        ElpianCapability.dom,
      });

      expect(await vm.governor.allowsApi('render'), isTrue);
      expect(await vm.governor.allowsApi('dom.setStyle'), isTrue);
      expect(await vm.governor.allowsApi('net.fetch'), isFalse);
      expect(await vm.governor.allowsApi('fs.read'), isFalse);
      expect(await vm.governor.allowsApi('canvas.fillRect'), isFalse,
          reason: 'canvas was not granted, and is its own gate now');

      final caps = await vm.governor.effectiveCapabilities();
      expect(caps.granted, contains(ElpianCapability.render));
      expect(caps.denied, contains(ElpianCapability.network));

      await vm.dispose();
    }, skip: skip);
  });

  group('lifecycle', () {
    test('a host can read state and terminate a mini app', () async {
      final vm = await spawn('gov-dart-lifecycle');

      final before = await vm.governor.state();
      expect(before.state, ElpianRunState.running);
      expect(before.isDead, isFalse);
      expect(before.isTrapped, isFalse);

      await vm.governor.terminate();

      final after = await vm.governor.state();
      expect(after.isDead, isTrue);

      await vm.dispose();
    }, skip: skip);
  });

  group('the spawn tree', () {
    test('a parent cannot grant a child what it does not hold', () async {
      final parent = await spawn('gov-dart-tree-parent');
      final child = await spawn('gov-dart-tree-child');

      await ElpianVm.treeGovernor
          .adopt(parentId: parent.machineId, childId: child.machineId);

      // The parent closes the network for its whole branch.
      await parent.governor.setCapability(ElpianCapability.network, false);
      expect(await child.governor.allowsApi('net.fetch'), isFalse);

      // Handing it back to the child directly must stay inert.
      await child.governor.setCapability(ElpianCapability.network, true);

      final local = await child.governor.localCapabilities();
      final effective = await child.governor.effectiveCapabilities();
      expect(local.allows(ElpianCapability.network), isTrue,
          reason: 'the grant is recorded');
      expect(effective.allows(ElpianCapability.network), isFalse,
          reason: 'but a parent that lacks it can never confer it');
      expect(await child.governor.allowsApi('net.fetch'), isFalse);

      await parent.dispose();
      await child.dispose();
    }, skip: skip);

    test("a child's work counts against its parent", () async {
      final parent = await spawn('gov-dart-cost-parent');
      final child = await spawn('gov-dart-cost-child');
      for (final vm in [parent, child]) {
        vm.registerHostHandler(
            'render', (_, __) => '{"type":"string","data":{"value":"ok"}}');
      }

      await ElpianVm.treeGovernor
          .adopt(parentId: parent.machineId, childId: child.machineId);

      await parent.run();
      await child.run();

      final own = await parent.governor.usage();
      final branch = await parent.governor.subtreeUsage();
      final childOwn = await child.governor.usage();

      expect(childOwn.instructions, greaterThan(0));
      expect(branch.instructions, own.instructions + childOwn.instructions,
          reason: 'work pushed into a child stays on the parent’s bill');

      await parent.dispose();
      await child.dispose();
    }, skip: skip);

    test('a snapshot answers the whole dashboard in one call', () async {
      final parent = await spawn('gov-dart-snap-parent');
      final child = await spawn('gov-dart-snap-child');
      await ElpianVm.treeGovernor
          .adopt(parentId: parent.machineId, childId: child.machineId);
      await parent.governor.setLimits(ElpianLimits.sandboxed);

      final snap = await ElpianVm.treeGovernor.snapshot(parent.machineId);

      expect(snap.machineId, parent.machineId);
      expect(snap.state.state, ElpianRunState.running);
      expect(
          snap.limits.maxInstructions, ElpianLimits.sandboxed.maxInstructions);
      expect(snap.tree.children, contains(child.machineId));
      expect(
          snap.tree.subtree, containsAll([parent.machineId, child.machineId]));
      expect(snap.tree.isRoot, isTrue);

      await parent.dispose();
      await child.dispose();
    }, skip: skip);

    test('terminating a parent takes its whole branch', () async {
      final parent = await spawn('gov-dart-kill-parent');
      final child = await spawn('gov-dart-kill-child');
      await ElpianVm.treeGovernor
          .adopt(parentId: parent.machineId, childId: child.machineId);

      final affected =
          await ElpianVm.treeGovernor.terminateTree(parent.machineId);

      expect(affected, containsAll([parent.machineId, child.machineId]));
      expect((await child.governor.state()).isDead, isTrue,
          reason: 'a child does not outlive the parent that owned it');

      await parent.dispose();
      await child.dispose();
    }, skip: skip);
  });

  group('honesty about what each runtime enforces', () {
    test('the Elpian VM reports full enforcement', () {
      const governor = ElpianVmGovernor('gov-dart-support');
      expect(governor.governanceSupport.capabilities, isTrue);
      expect(governor.governanceSupport.instructionBudget, isTrue);
      expect(governor.governanceSupport.hierarchy, isTrue);
      expect(governor.governanceSupport.canSandboxUntrustedCode, isTrue);
    }, skip: skip);

    test('a host-side governor admits what it cannot enforce', () async {
      // QuickJS exposes no interrupt hook, so nothing in Dart can stop a
      // runaway loop on it. Saying so is the point: a host that checks before
      // loading third-party code must not be told it is protected.
      final quickJs = HostSideGovernor(
        machineId: 'quickjs-probe',
        enforcesInstructionBudget: false,
      );
      expect(quickJs.governanceSupport.capabilities, isTrue);
      expect(quickJs.governanceSupport.instructionBudget, isFalse);
      expect(quickJs.governanceSupport.canSandboxUntrustedCode, isFalse);

      // The seam it *can* enforce still works.
      await quickJs.sandbox({ElpianCapability.render});
      expect(quickJs.checkAndCharge('render'), isNull);
      expect(quickJs.checkAndCharge('net.fetch'), isNotNull,
          reason: 'a denied capability is refused at the seam');
    });

    test('a host-side governor stops a mini app that outruns its budget',
        () async {
      var terminated = false;
      final governor = HostSideGovernor(
        machineId: 'budget-probe',
        enforcesInstructionBudget: true,
        onTerminate: () => terminated = true,
      );
      await governor.setLimits(const ElpianLimits(maxInstructions: 2));

      expect(governor.checkAndCharge('render'), isNull);
      expect(governor.checkAndCharge('render'), isNull);
      expect(governor.checkAndCharge('render'), isNotNull);
      expect(terminated, isTrue);
      expect((await governor.state()).isTrapped, isTrue);
    });

    test('an absent runtime governs nothing and says so', () {
      const governor = UnenforcedGovernor('runtime missing');
      expect(governor.governanceSupport.canSandboxUntrustedCode, isFalse);
      expect(
        () => governor.setLimits(ElpianLimits.sandboxed),
        throwsA(isA<ElpianGovernanceException>()),
      );
    });
  });
}
