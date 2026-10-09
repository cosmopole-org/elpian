/// The contract every Elpian runtime backend implements for governing a mini
/// app: what it may do, how much it may spend, and whether it runs at all.
///
/// Before this existed the whole control plane lived in Rust and stopped at the
/// FFI edge — a Flutter host could create and run a mini app but could not set
/// a budget, read a meter, revoke a permission or pause it. The mechanisms were
/// there; nothing could reach them.
///
/// Three backends implement this:
///
///   * **Elpian VM** (native FFI / WASM) — full enforcement inside the VM.
///   * **QuickJS** — interrupt-driven instruction budget and host-call gating.
///   * **WASM** — fuel metering and host-call gating.
///
/// Backends that cannot enforce a given axis say so through
/// [enforcedAxes] rather than pretending, so a host can refuse to run untrusted
/// code on a runtime that cannot bound it.
library;

import 'models.dart';

/// Which governance axes a backend can actually enforce.
///
/// A host running untrusted mini apps should check this before choosing a
/// runtime: a backend that cannot bound instructions cannot stop an infinite
/// loop, whatever limits are set on it.
class GovernanceSupport {
  const GovernanceSupport({
    required this.capabilities,
    required this.instructionBudget,
    required this.memoryBudget,
    required this.storageBudget,
    required this.lifecycle,
    required this.hierarchy,
  });

  /// Per-API capability gating at the host-call seam.
  final bool capabilities;

  /// A ceiling on interpreter steps — the only thing that stops a runaway loop.
  final bool instructionBudget;

  /// A ceiling on live heap.
  final bool memoryBudget;

  /// A ceiling on persistent storage.
  final bool storageBudget;

  /// Pause, resume and terminate.
  final bool lifecycle;

  /// Parent/child spawn trees with inherited permissions and aggregate budgets.
  final bool hierarchy;

  /// Everything enforced — the Elpian VM.
  static const full = GovernanceSupport(
    capabilities: true,
    instructionBudget: true,
    memoryBudget: true,
    storageBudget: true,
    lifecycle: true,
    hierarchy: true,
  );

  /// Nothing enforced. A runtime reporting this must not be handed untrusted
  /// code.
  static const none = GovernanceSupport(
    capabilities: false,
    instructionBudget: false,
    memoryBudget: false,
    storageBudget: false,
    lifecycle: false,
    hierarchy: false,
  );

  /// Whether this backend can bound untrusted code at all: it must be able to
  /// gate what a mini app reaches for *and* stop it from running forever.
  bool get canSandboxUntrustedCode => capabilities && instructionBudget;

  @override
  String toString() => 'GovernanceSupport(capabilities: $capabilities, '
      'instructions: $instructionBudget, memory: $memoryBudget, '
      'storage: $storageBudget, lifecycle: $lifecycle, hierarchy: $hierarchy)';
}

/// Governs one mini app.
///
/// Every method may throw [ElpianGovernanceException] when the runtime refuses
/// the call — most often because the mini app is gone.
abstract class VmGovernor {
  /// Which axes this backend actually enforces.
  GovernanceSupport get governanceSupport;

  // -- Budgets --------------------------------------------------------------

  /// Bound what this mini app may spend. Usage already accrued is retained, so
  /// tightening a limit below current usage traps it at its next step rather
  /// than retroactively.
  Future<void> setLimits(ElpianLimits limits);

  /// The limits policy currently in force.
  Future<ElpianLimits> getLimits();

  /// What this mini app alone has consumed.
  Future<ElpianUsage> usage();

  /// What this mini app *and every mini app it spawned* have consumed — the
  /// figure its own budget is checked against, so work pushed into a child is
  /// still on the parent's bill.
  Future<ElpianUsage> subtreeUsage();

  // -- Capabilities ---------------------------------------------------------

  /// Grant or revoke one capability.
  ///
  /// This records a *local* grant. What the mini app may actually do is the
  /// intersection with every ancestor, so granting something a parent denies is
  /// recorded but stays inert.
  Future<void> setCapability(ElpianCapability capability, bool allowed);

  /// Deny everything, then grant only [granted] — the posture to start an
  /// untrusted mini app from.
  Future<void> sandbox(Set<ElpianCapability> granted);

  /// What this mini app was granted directly.
  Future<ElpianCapabilities> localCapabilities();

  /// What it may actually do: local grants AND every ancestor's.
  Future<ElpianCapabilities> effectiveCapabilities();

  /// Whether one host API is permitted right now.
  Future<bool> allowsApi(String apiName);

  // -- Lifecycle ------------------------------------------------------------

  /// Run state, trap reason and whether a turn is in flight.
  Future<ElpianVmState> state();

  /// Stop at the next step boundary, preserving the continuation.
  Future<void> pause();

  /// Pick up exactly where [pause] left off.
  Future<void> resumeExecution();

  /// Stop for good. Terminating a mini app terminates everything it spawned.
  Future<void> terminate();
}

/// Governs a *tree* of mini apps — the operations that only make sense across
/// a parent and its children.
///
/// A mini app may spawn other mini apps inside its own GUI box. Children
/// inherit their parent's access by default; a parent may narrow what a child
/// holds but can never widen it past what it holds itself. A child's execution
/// counts against its parent's budget, and a branch whose aggregate breaks its
/// root's budget is destroyed whole.
abstract class VmTreeGovernor {
  /// Make [childId] a child of [parentId], clipping the child's effective
  /// capabilities to the new ancestor path immediately.
  Future<void> adopt({required String parentId, required String childId});

  /// A mini app's parent, direct children, and whole descendant subtree.
  Future<ElpianVmTree> tree(String machineId);

  /// Pause a mini app and everything below it. Returns the ids affected.
  Future<List<String>> pauseTree(String machineId);

  /// Terminate a mini app and everything below it. Returns the ids affected.
  Future<List<String>> terminateTree(String machineId);

  /// Destroy a mini app and everything below it, freeing their runtimes.
  /// Returns the ids affected.
  Future<List<String>> destroyTree(String machineId);

  /// Sweep every tree and destroy any branch whose aggregate usage has broken
  /// its own root's budget.
  ///
  /// This is the "handle it or share its fate" rule: a hung child first traps
  /// on its own per-turn cap and its parent is told, but a parent that never
  /// cleans up eventually pays with the whole branch. Call it periodically —
  /// once a frame, or on a timer.
  Future<List<ElpianBudgetViolation>> enforceTreeBudgets();

  /// Everything a dashboard shows for one mini app and its branch, in one call.
  Future<ElpianVmSnapshot> snapshot(String machineId);
}
