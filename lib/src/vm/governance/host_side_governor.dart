/// Governance for runtimes that cannot enforce it themselves.
///
/// The Elpian VM gates every `askHost` and meters every interpreter step inside
/// the VM, where a guest cannot reach around it. The two alternative backends
/// cannot do all of that:
///
///   * **QuickJS** (via `flutter_js`) exposes no interrupt handler through its
///     Dart API, so there is no way to stop a `while (true) {}` from Dart. What
///     *can* be enforced is everything crossing the host-call seam: which APIs
///     a mini app may reach, how many calls it may make, and how many bytes it
///     may move.
///   * **WASM** (via `wasm_run`) supports fuel metering, so an instruction
///     budget is enforceable there in addition to the seam.
///
/// This class implements the seam half for both. It reports honestly what it
/// enforces through [governanceSupport], so a host checking
/// [GovernanceSupport.canSandboxUntrustedCode] is told the truth rather than
/// being handed a false sense of protection.
///
/// A host that must run untrusted third-party code should use the Elpian VM.
library;

import '../host_api_catalog.dart';
import 'governor.dart';
import 'models.dart';

/// Enforces capabilities and host-call budgets at the Dart host-call seam.
///
/// Wrap a backend's host-call dispatch in [checkAndCharge] and the gate applies
/// to every call a guest makes, whatever engine is underneath.
class HostSideGovernor implements VmGovernor {
  HostSideGovernor({
    required this.machineId,
    required bool enforcesInstructionBudget,
    this.onTerminate,
    this.onPause,
    this.onResume,
  }) : _enforcesInstructions = enforcesInstructionBudget;

  final String machineId;
  final bool _enforcesInstructions;

  /// Called when the host asks for the instance to be stopped, or when a budget
  /// is broken. The backend tears its engine down.
  final void Function()? onTerminate;
  final void Function()? onPause;
  final void Function()? onResume;

  ElpianLimits _limits = ElpianLimits.unlimited;
  ElpianUsage _usage = ElpianUsage.zero;
  ElpianRunState _state = ElpianRunState.running;
  String? _trapReason;

  /// Local capability grants. Absent means allowed, matching the VM's
  /// `CapabilitySet` default for an unrestricted instance.
  final Map<ElpianCapability, bool> _capabilities = {};
  bool _defaultAllow = true;

  @override
  GovernanceSupport get governanceSupport => GovernanceSupport(
        capabilities: true,
        instructionBudget: _enforcesInstructions,
        // Neither backend surfaces a live heap figure Dart can cap against.
        memoryBudget: false,
        // Storage is charged by the host filesystem, which this governor does
        // not own.
        storageBudget: false,
        lifecycle: true,
        // Nested spawn trees are an Elpian VM feature; these backends have no
        // notion of a child instance.
        hierarchy: false,
      );

  /// Why this instance was stopped, if it was.
  String? get trapReason => _trapReason;

  // -- The seam --------------------------------------------------------------

  /// Gate and meter one host call.
  ///
  /// Returns null when the call may proceed. Otherwise returns the reason it
  /// was refused, which the backend turns into a typed null reply — the same
  /// "interface unplugged" shape the Elpian VM produces for a denied
  /// capability, so a guest sees one behaviour across all three runtimes.
  String? checkAndCharge(String apiName, {int bytes = 0}) {
    if (_state != ElpianRunState.running) {
      return 'instance is ${_state.wireName}';
    }

    final capability = ElpianCapability.fromWireName(
          VmHostApiCatalog.capabilityFor(apiName),
        ) ??
        // An unrecognised gate must never be a pass.
        ElpianCapability.other;

    if (!_allows(capability)) {
      return 'capability ${capability.wireName} is denied';
    }

    // Host calls are the unit of work this governor can actually see, so the
    // instruction budget is charged against them. It is a coarser proxy than
    // the VM's per-step accounting and is documented as such.
    final next = _usage.instructions + 1;
    final max = _limits.maxInstructions;
    if (max != null && next > max) {
      _trap('host-call limit exceeded ($max)');
      return _trapReason;
    }

    final nextBytes = _usage.storageBytes + bytes;
    final maxBytes = _limits.maxStorageBytes;
    if (maxBytes != null && nextBytes > maxBytes) {
      _trap('host-byte limit exceeded ($maxBytes)');
      return _trapReason;
    }

    _usage = ElpianUsage(
      instructions: next,
      instructionsThisTurn: _usage.instructionsThisTurn + 1,
      memoryBytes: _usage.memoryBytes,
      peakMemoryBytes: _usage.peakMemoryBytes,
      storageBytes: nextBytes,
      callDepth: _usage.callDepth,
      peakCallDepth: _usage.peakCallDepth,
    );
    return null;
  }

  /// Record engine-reported work — WASM fuel, for instance — so an instruction
  /// budget can be enforced where the engine supports it.
  void chargeInstructions(int steps) {
    _usage = ElpianUsage(
      instructions: _usage.instructions + steps,
      instructionsThisTurn: _usage.instructionsThisTurn + steps,
      memoryBytes: _usage.memoryBytes,
      peakMemoryBytes: _usage.peakMemoryBytes,
      storageBytes: _usage.storageBytes,
      callDepth: _usage.callDepth,
      peakCallDepth: _usage.peakCallDepth,
    );
    final max = _limits.maxInstructions;
    if (max != null && _usage.instructions > max) {
      _trap('instruction limit exceeded ($max)');
    }
  }

  /// Reset the per-turn counter. Backends call this when a turn begins.
  void beginTurn() {
    _usage = ElpianUsage(
      instructions: _usage.instructions,
      instructionsThisTurn: 0,
      memoryBytes: _usage.memoryBytes,
      peakMemoryBytes: _usage.peakMemoryBytes,
      storageBytes: _usage.storageBytes,
      callDepth: _usage.callDepth,
      peakCallDepth: _usage.peakCallDepth,
    );
  }

  void _trap(String reason) {
    _trapReason ??= reason;
    _state = ElpianRunState.terminated;
    onTerminate?.call();
  }

  bool _allows(ElpianCapability capability) =>
      _capabilities[capability] ?? _defaultAllow;

  // -- VmGovernor ------------------------------------------------------------

  @override
  Future<void> setLimits(ElpianLimits limits) async {
    _limits = limits;
  }

  @override
  Future<ElpianLimits> getLimits() async => _limits;

  @override
  Future<ElpianUsage> usage() async => _usage;

  /// Identical to [usage]: these backends have no notion of a child instance,
  /// so an instance's subtree is itself. [governanceSupport] reports
  /// `hierarchy: false` so a host knows not to rely on nesting here.
  @override
  Future<ElpianUsage> subtreeUsage() async => _usage;

  @override
  Future<void> setCapability(ElpianCapability capability, bool allowed) async {
    _capabilities[capability] = allowed;
  }

  @override
  Future<void> sandbox(Set<ElpianCapability> granted) async {
    _capabilities.clear();
    _defaultAllow = false;
    for (final c in granted) {
      _capabilities[c] = true;
    }
  }

  @override
  Future<ElpianCapabilities> localCapabilities() async => ElpianCapabilities({
        for (final c in ElpianCapability.values) c: _allows(c),
      });

  /// Identical to [localCapabilities]: with no ancestors there is nothing to
  /// intersect with.
  @override
  Future<ElpianCapabilities> effectiveCapabilities() => localCapabilities();

  @override
  Future<bool> allowsApi(String apiName) async {
    final capability = ElpianCapability.fromWireName(
          VmHostApiCatalog.capabilityFor(apiName),
        ) ??
        ElpianCapability.other;
    return _allows(capability);
  }

  @override
  Future<ElpianVmState> state() async => ElpianVmState(
        state: _state,
        trapReason: _trapReason,
        processing: false,
      );

  @override
  Future<void> pause() async {
    if (_state == ElpianRunState.running) {
      _state = ElpianRunState.paused;
      onPause?.call();
    }
  }

  @override
  Future<void> resumeExecution() async {
    if (_state == ElpianRunState.paused) {
      _state = ElpianRunState.running;
      onResume?.call();
    }
  }

  @override
  Future<void> terminate() async {
    _state = ElpianRunState.terminated;
    onTerminate?.call();
  }
}

/// The governor for a backend that enforces nothing at all.
///
/// Used by the compile-time stubs that stand in when a runtime is unavailable
/// on the current platform. Every call is a no-op and
/// [GovernanceSupport.canSandboxUntrustedCode] is false, so a host is told
/// plainly that nothing is protecting it.
class UnenforcedGovernor implements VmGovernor {
  const UnenforcedGovernor(this.reason);

  /// Why nothing is enforced — surfaced in the exception every mutating call
  /// throws, so a misconfiguration is loud rather than silent.
  final String reason;

  @override
  GovernanceSupport get governanceSupport => GovernanceSupport.none;

  Never _unavailable(String call) =>
      throw ElpianGovernanceException(reason, call: call);

  @override
  Future<void> setLimits(ElpianLimits limits) async =>
      _unavailable('setLimits');

  @override
  Future<ElpianLimits> getLimits() async => ElpianLimits.unlimited;

  @override
  Future<ElpianUsage> usage() async => ElpianUsage.zero;

  @override
  Future<ElpianUsage> subtreeUsage() async => ElpianUsage.zero;

  @override
  Future<void> setCapability(ElpianCapability capability, bool allowed) async =>
      _unavailable('setCapability');

  @override
  Future<void> sandbox(Set<ElpianCapability> granted) async =>
      _unavailable('sandbox');

  @override
  Future<ElpianCapabilities> localCapabilities() async =>
      const ElpianCapabilities({});

  @override
  Future<ElpianCapabilities> effectiveCapabilities() async =>
      const ElpianCapabilities({});

  @override
  Future<bool> allowsApi(String apiName) async => false;

  @override
  Future<ElpianVmState> state() async => const ElpianVmState(
        state: ElpianRunState.terminated,
        trapReason: null,
        processing: false,
      );

  @override
  Future<void> pause() async {}

  @override
  Future<void> resumeExecution() async {}

  @override
  Future<void> terminate() async {}
}
