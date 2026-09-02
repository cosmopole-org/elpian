import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Nested mini apps, end to end over the real runtime.
///
/// A mini app may host mini apps of its own inside its GUI box. Four rules
/// govern that, and they must hold through the whole stack — manifest, policy,
/// host, and the VM's spawn tree:
///
///   1. a child inherits its parent's access by default;
///   2. a parent may narrow a child, but can never widen it past itself;
///   3. a child's execution counts against its parent's budget;
///   4. a parent may cap its children, and a branch that breaks the parent's
///      budget dies whole.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final skip = ElpianVm.isRuntimeAvailable
      ? null
      : 'Native VM library not built. Run: cd rust && cargo build --release';

  /// A program that does a little work, so meters register something.
  const source = 'var x = 1; var y = x + 1;';

  const shellManifest = MiniAppManifest(
    id: 'shell',
    name: 'Shell',
    allowsChildren: true,
    requestedCapabilities: {
      ElpianCapability.render,
      ElpianCapability.dom,
      ElpianCapability.network,
      ElpianCapability.vmManage,
    },
  );

  const shellGrant = MiniAppGrant(
    capabilities: {
      ElpianCapability.render,
      ElpianCapability.dom,
      ElpianCapability.network,
      ElpianCapability.vmManage,
      ElpianCapability.logging,
    },
    limits: ElpianLimits.sandboxed,
    mayHostChildren: true,
  );

  Future<MiniAppHost> launchShell(String id) => MiniAppHost.launch(
        manifest: MiniAppManifest(
          id: id,
          name: shellManifest.name,
          allowsChildren: true,
          requestedCapabilities: shellManifest.requestedCapabilities,
        ),
        grant: shellGrant,
        source: source,
      );

  test('a child inherits its parent’s access by default', () async {
    final parent = await launchShell('nest-inherit');
    final child = await parent.spawnChild(
      // No requestedCapabilities: the child asks for nothing in particular and
      // should come up with what its parent holds.
      manifest: const MiniAppManifest(id: 'widget', name: 'Widget'),
      source: source,
    );

    expect(child.policy.capabilities, parent.policy.capabilities,
        reason: 'a child with no requests inherits the parent’s set');
    expect(await child.governor.allowsApi('net.fetch'), isTrue);

    await parent.dispose();
  }, skip: skip);

  test('a parent can narrow a child', () async {
    final parent = await launchShell('nest-narrow');
    final child = await parent.spawnChild(
      manifest: const MiniAppManifest(id: 'viewer', name: 'Viewer'),
      source: source,
      grant: const MiniAppGrant(
        capabilities: {ElpianCapability.render},
        limits: ElpianLimits.sandboxed,
      ),
    );

    expect(child.policy.capabilities, {ElpianCapability.render});
    expect(await child.governor.allowsApi('net.fetch'), isFalse,
        reason: 'the parent chose not to pass the network down');
    expect(await parent.governor.allowsApi('net.fetch'), isTrue,
        reason: 'narrowing a child must not narrow the parent');

    await parent.dispose();
  }, skip: skip);

  test('a parent cannot widen a child past itself', () async {
    // The parent holds no storage capability. Handing the child a grant that
    // includes it must not work — in the host, and again in the VM.
    final parent = await launchShell('nest-widen');
    expect(
        parent.policy.capabilities, isNot(contains(ElpianCapability.storage)));

    final child = await parent.spawnChild(
      manifest: const MiniAppManifest(id: 'greedy', name: 'Greedy'),
      source: source,
      grant: MiniAppGrant.trusted,
    );

    expect(child.policy.capabilities, isNot(contains(ElpianCapability.storage)),
        reason: 'the host clips the grant to the parent’s own set');
    expect(await child.governor.allowsApi('fs.read'), isFalse,
        reason: 'and the VM clips it again along the ancestor path');

    await parent.dispose();
  }, skip: skip);

  test('a revoke on the parent reaches its children immediately', () async {
    final parent = await launchShell('nest-revoke');
    final child = await parent.spawnChild(
      manifest: const MiniAppManifest(id: 'child', name: 'Child'),
      source: source,
    );
    expect(await child.governor.allowsApi('net.fetch'), isTrue);

    await parent.governor.setCapability(ElpianCapability.network, false);

    expect(await child.governor.allowsApi('net.fetch'), isFalse,
        reason: 'a running child loses access the moment its parent does');

    await parent.dispose();
  }, skip: skip);

  test('a child’s execution counts against its parent', () async {
    final parent = await launchShell('nest-cost');
    final child = await parent.spawnChild(
      manifest: const MiniAppManifest(id: 'worker', name: 'Worker'),
      source: source,
    );

    await parent.runtime.run();
    await child.runtime.run();

    final own = await parent.usage();
    final branch = await parent.branchUsage();
    final childOwn = await child.usage();

    expect(childOwn.instructions, greaterThan(0));
    expect(branch.instructions, own.instructions + childOwn.instructions,
        reason: 'work pushed into a child stays on the parent’s bill');

    await parent.dispose();
  }, skip: skip);

  test('a parent can cap what a child spends', () async {
    final parent = await launchShell('nest-cap');
    final child = await parent.spawnChild(
      manifest: const MiniAppManifest(id: 'bounded', name: 'Bounded'),
      source: source,
      grant: const MiniAppGrant(
        capabilities: {ElpianCapability.render},
        limits: ElpianLimits(maxInstructions: 5),
      ),
    );

    expect(child.policy.limits.maxInstructions, 5);
    expect((await child.governor.getLimits()).maxInstructions, 5,
        reason: 'the cap reached the VM, not just the policy object');

    await parent.dispose();
  }, skip: skip);

  test('nesting is refused when the app was not granted it', () async {
    final plain = await MiniAppHost.launch(
      manifest: const MiniAppManifest(id: 'nest-refused', name: 'Plain'),
      grant: MiniAppGrant.untrusted,
      source: source,
    );

    expect(plain.policy.mayHostChildren, isFalse);
    expect(
      () => plain.spawnChild(
        manifest: const MiniAppManifest(id: 'sneaky', name: 'Sneaky'),
        source: source,
      ),
      throwsA(isA<MiniAppException>()),
    );

    await plain.dispose();
  }, skip: skip);

  test('disposing a parent disposes its whole branch', () async {
    final parent = await launchShell('nest-teardown');
    final child = await parent.spawnChild(
      // Declares nesting itself: `allowsChildren` is not inherited, so a
      // middle app that never asked to host children cannot.
      manifest: const MiniAppManifest(
        id: 'inner',
        name: 'Inner',
        allowsChildren: true,
        requestedCapabilities: {
          ElpianCapability.render,
          ElpianCapability.vmManage,
        },
      ),
      source: source,
    );
    final grandchild = await child.spawnChild(
      manifest: const MiniAppManifest(id: 'deepest', name: 'Deepest'),
      source: source,
    );

    expect(parent.children, contains(child));
    expect(child.children, contains(grandchild));

    await parent.dispose();

    expect(parent.isDisposed, isTrue);
    expect(child.isDisposed, isTrue);
    expect(grandchild.isDisposed, isTrue,
        reason: 'a mini app must not outlive the branch that owned it');
  }, skip: skip);

  test('each mini app in a tree gets its own host state', () async {
    final parent = await launchShell('nest-services');
    final child = await parent.spawnChild(
      manifest: const MiniAppManifest(id: 'inner', name: 'Inner'),
      source: source,
    );

    expect(child.services, isNot(same(parent.services)));
    expect(child.machineId, 'nest-services.inner',
        reason: 'a child is namespaced under its parent');
    expect(
        child.services.scopeId('main'), isNot(parent.services.scopeId('main')),
        reason: 'the same guest-chosen id resolves differently per app');

    await parent.dispose();
  }, skip: skip);

  test('the host-call gate refuses what the policy denies', () async {
    final parent = await launchShell('nest-gate');
    final child = await parent.spawnChild(
      manifest: const MiniAppManifest(id: 'drawer', name: 'Drawer'),
      source: source,
      grant: const MiniAppGrant(
        capabilities: {ElpianCapability.render},
        limits: ElpianLimits.sandboxed,
      ),
    );

    expect(child.authorizes('render'), isTrue);
    expect(child.authorizes('net.fetch'), isFalse);
    expect(child.authorizes('dom.appendChild'), isFalse);

    final refused = <String>[];
    final handler = child.createHostHandler(
      onCallRefused: refused.add,
    );
    final reply = handler.handleHostCall('net.fetch', '{}');

    expect(refused, ['net.fetch']);
    expect(reply, contains('"null"'),
        reason: 'a refused call gets the same typed null the VM produces');

    await parent.dispose();
  }, skip: skip);
}
