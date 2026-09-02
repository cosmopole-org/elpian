/// The Elpian VM's implementation of [VmGovernor] and [VmTreeGovernor].
///
/// This is the layer that finally makes the framework's governance reachable
/// from Flutter. Every mechanism it exposes existed in the Rust VM from the
/// start — capability gating at the `askHost` seam, instruction/memory/storage
/// budgets, pause/resume/terminate, and the spawn tree with inherited
/// permissions and aggregate accounting. None of it crossed the FFI boundary,
/// so a host could start a mini app and then had no say over it.
///
/// Everything here is a thin, typed wrapper over the JSON control plane. The
/// enforcement lives in the VM, where a guest cannot reach around it.
library;

import 'dart:convert';

import '../ffi/api.dart';
import 'governor.dart';
import 'models.dart';
import 'native_bindings.dart' if (dart.library.js_interop) 'web_bindings.dart'
    as bindings;

/// Governs one Elpian VM instance, addressed by its machine id.
class ElpianVmGovernor implements VmGovernor {
  const ElpianVmGovernor(this.machineId);

  final String machineId;

  static bindings.GovernanceBindings get _b => bindings.governanceBindings;

  @override
  GovernanceSupport get governanceSupport => _b.isAvailable
      ? GovernanceSupport.full
      // The runtime is absent or predates this surface. Reporting "none"
      // rather than "full" matters: a host that checks
      // `canSandboxUntrustedCode` before loading a third-party mini app must
      // not be told it is protected when nothing is enforcing anything.
      : GovernanceSupport.none;

  void _requireRuntime(String call) {
    if (!_b.isAvailable) {
      throw ElpianGovernanceException(
        ElpianVmApi.isAvailable
            ? 'the loaded Elpian runtime does not carry the governance surface'
            : 'the Elpian runtime is not available: ${ElpianVmApi.lastError}',
        call: call,
      );
    }
  }

  // -- Budgets --------------------------------------------------------------

  @override
  Future<void> setLimits(ElpianLimits limits) async {
    _requireRuntime('setLimits');
    _b.call2('elpian_set_limits', machineId, jsonEncode(limits.toJson()));
  }

  @override
  Future<ElpianLimits> getLimits() async {
    _requireRuntime('getLimits');
    return ElpianLimits.fromJson(_b.call1('elpian_limits', machineId));
  }

  @override
  Future<ElpianUsage> usage() async {
    _requireRuntime('usage');
    return ElpianUsage.fromJson(_b.call1('elpian_usage', machineId));
  }

  @override
  Future<ElpianUsage> subtreeUsage() async {
    _requireRuntime('subtreeUsage');
    return ElpianUsage.fromJson(_b.call1('elpian_subtree_usage', machineId));
  }

  /// Charge the storage governor on the host filesystem's behalf, so a mini
  /// app's persisted bytes count against the same budget as its heap.
  Future<void> chargeStorage(int deltaBytes) async {
    _requireRuntime('chargeStorage');
    _b.callI64('elpian_charge_storage', machineId, deltaBytes);
  }

  // -- Capabilities ---------------------------------------------------------

  @override
  Future<void> setCapability(ElpianCapability capability, bool allowed) async {
    _requireRuntime('setCapability');
    _b.call2Int(
      'elpian_set_capability',
      machineId,
      capability.wireName,
      allowed ? 1 : 0,
    );
  }

  /// Set several capabilities at once. Capabilities absent from [changes] keep
  /// their current value.
  Future<void> setCapabilities(Map<ElpianCapability, bool> changes) async {
    _requireRuntime('setCapabilities');
    final wire = {
      for (final e in changes.entries) e.key.wireName: e.value,
    };
    _b.call2('elpian_set_capabilities', machineId, jsonEncode(wire));
  }

  @override
  Future<void> sandbox(Set<ElpianCapability> granted) async {
    _requireRuntime('sandbox');
    _b.call2(
      'elpian_sandbox_capabilities',
      machineId,
      jsonEncode(granted.map((c) => c.wireName).toList()),
    );
  }

  @override
  Future<ElpianCapabilities> localCapabilities() async {
    _requireRuntime('localCapabilities');
    return ElpianCapabilities.fromJson(
        _b.call1('elpian_local_capabilities', machineId));
  }

  @override
  Future<ElpianCapabilities> effectiveCapabilities() async {
    _requireRuntime('effectiveCapabilities');
    return ElpianCapabilities.fromJson(
        _b.call1('elpian_effective_capabilities', machineId));
  }

  @override
  Future<bool> allowsApi(String apiName) async {
    _requireRuntime('allowsApi');
    final r = _b.call2('elpian_capability_allows', machineId, apiName);
    return r['allowed'] as bool? ?? false;
  }

  // -- Lifecycle ------------------------------------------------------------

  @override
  Future<ElpianVmState> state() async {
    _requireRuntime('state');
    return ElpianVmState.fromJson(_b.call1('elpian_state', machineId));
  }

  @override
  Future<void> pause() async {
    _requireRuntime('pause');
    _b.call1('elpian_pause', machineId);
  }

  @override
  Future<void> resumeExecution() async {
    _requireRuntime('resumeExecution');
    _b.call1('elpian_resume', machineId);
  }

  @override
  Future<void> terminate() async {
    _requireRuntime('terminate');
    _b.call1('elpian_terminate', machineId);
  }
}

/// Governs the spawn tree: the operations that span a parent and its children.
///
/// A mini app may spawn other mini apps. Children inherit their parent's access
/// by default and can be narrowed but never widened past it; their execution
/// counts against the parent's budget; and a branch that breaks its root's
/// budget is destroyed whole.
class ElpianTreeGovernor implements VmTreeGovernor {
  const ElpianTreeGovernor();

  static bindings.GovernanceBindings get _b => bindings.governanceBindings;

  /// Whether the loaded runtime carries the tree surface.
  bool get isAvailable => _b.isAvailable;

  void _requireRuntime(String call) {
    if (!_b.isAvailable) {
      throw ElpianGovernanceException(
        'the Elpian runtime does not carry the governance surface',
        call: call,
      );
    }
  }

  @override
  Future<void> adopt({
    required String parentId,
    required String childId,
  }) async {
    _requireRuntime('adopt');
    _b.call2('elpian_adopt', parentId, childId);
  }

  @override
  Future<ElpianVmTree> tree(String machineId) async {
    _requireRuntime('tree');
    return ElpianVmTree.fromJson(_b.call1('elpian_tree', machineId));
  }

  List<String> _affected(Map<String, dynamic> reply) =>
      (reply['affected'] as List?)?.map((e) => e as String).toList() ??
      const <String>[];

  @override
  Future<List<String>> pauseTree(String machineId) async {
    _requireRuntime('pauseTree');
    return _affected(_b.call1('elpian_pause_tree', machineId));
  }

  @override
  Future<List<String>> terminateTree(String machineId) async {
    _requireRuntime('terminateTree');
    return _affected(_b.call1('elpian_terminate_tree', machineId));
  }

  @override
  Future<List<String>> destroyTree(String machineId) async {
    _requireRuntime('destroyTree');
    return _affected(_b.call1('elpian_destroy_tree', machineId));
  }

  @override
  Future<List<ElpianBudgetViolation>> enforceTreeBudgets() async {
    _requireRuntime('enforceTreeBudgets');
    final rows = _b.call0List('elpian_enforce_tree_budgets');
    return rows
        .whereType<Map<String, dynamic>>()
        .map(ElpianBudgetViolation.fromJson)
        .toList();
  }

  @override
  Future<ElpianVmSnapshot> snapshot(String machineId) async {
    _requireRuntime('snapshot');
    return ElpianVmSnapshot.fromJson(_b.call1('elpian_snapshot', machineId));
  }
}
