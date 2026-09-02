/// One running mini app: its runtime, its isolated host state, and its
/// children.
///
/// This is the unit everything else in the super app hangs off. It owns:
///
///   * a [VmRuntimeClient] — the mini app's own VM instance, governed;
///   * an [ElpianServices] — its own widget registry, event dispatcher, event
///     bus, stylesheets and canvas store, so nothing leaks to a sibling;
///   * an [ElpianEngine] bound to those services;
///   * a [HostHandler] that refuses any call the app's policy does not permit;
///   * and, when permitted, child [MiniAppHost]s running inside its own GUI.
///
/// # Nesting
///
/// A mini app may host mini apps of its own inside its GUI box. The rules come
/// straight from the VM's spawn tree and are enforced there, not here:
///
///   * a child **inherits its parent's access by default** — its effective
///     capabilities are the intersection along the whole ancestor path;
///   * a parent may **narrow** what a child holds, but can never widen it past
///     what the parent itself holds;
///   * a child's execution is **counted against its parent's budget** as well
///     as its own, so work pushed downwards is still on the parent's bill;
///   * a parent may **cap its children directly**, and a branch whose aggregate
///     breaks the parent's budget is destroyed whole.
///
/// [spawnChild] applies the first two by resolving the child's policy against
/// the parent's *effective* grant rather than the super app's; the VM applies
/// all four.
library;

import 'dart:async';

import '../core/elpian_engine.dart';
import '../core/elpian_services.dart';
import '../vm/elpian_vm.dart';
import '../vm/governance/governor.dart';
import '../vm/governance/models.dart';
import '../vm/host_api_catalog.dart';
import '../vm/host_handler.dart';
import '../vm/quickjs_vm.dart';
import '../vm/runtime_kind.dart';
import '../vm/vm_runtime_client.dart';
import '../vm/wasm_vm.dart';
import 'mini_app.dart';

/// Why a mini app could not be started, or was stopped.
class MiniAppException implements Exception {
  const MiniAppException(this.appId, this.reason);

  final String appId;
  final String reason;

  @override
  String toString() => 'MiniAppException($appId): $reason';
}

/// A running mini app.
class MiniAppHost {
  MiniAppHost._({
    required this.policy,
    required this.runtime,
    required this.services,
    required this.parent,
  })  : engine = ElpianEngine(services: services),
        machineId = services.appId;

  /// What this app may do and spend.
  final MiniAppPolicy policy;

  /// The VM instance running its code.
  final VmRuntimeClient runtime;

  /// Its isolated host state. No other mini app can see any of it.
  final ElpianServices services;

  /// The engine rendering its tree, bound to [services].
  final ElpianEngine engine;

  /// The mini app that spawned this one, or null for a top-level app.
  final MiniAppHost? parent;

  /// The VM machine id, which is also the resource namespace.
  final String machineId;

  final List<MiniAppHost> _children = [];
  bool _disposed = false;

  /// Mini apps running inside this one's GUI.
  List<MiniAppHost> get children => List.unmodifiable(_children);

  /// This app's identity as declared in its manifest.
  String get id => policy.manifest.id;

  /// Governs this app: budgets, capabilities, lifecycle.
  VmGovernor get governor => runtime.governor;

  /// Whether this app has been torn down.
  bool get isDisposed => _disposed;

  // -- Launching -------------------------------------------------------------

  /// Start a top-level mini app.
  ///
  /// [source] is the app's program, interpreted according to
  /// `manifest.runtime`. The resolved policy is applied to the VM *before the
  /// program runs*, so a mini app is never briefly unrestricted at boot.
  static Future<MiniAppHost> launch({
    required MiniAppManifest manifest,
    required MiniAppGrant grant,
    required String source,
    MiniAppHost? parent,
    String? machineIdOverride,
  }) async {
    final invalid = manifest.validate();
    if (invalid != null) throw MiniAppException(manifest.id, invalid);

    final policy = MiniAppPolicy.resolve(manifest, grant);
    final machineId = machineIdOverride ??
        (parent == null ? manifest.id : '${parent.machineId}.${manifest.id}');

    final runtime = await _startRuntime(manifest, source, machineId);
    final services = ElpianServices(appId: machineId);

    final host = MiniAppHost._(
      policy: policy,
      runtime: runtime,
      services: services,
      parent: parent,
    );

    // Join the spawn tree first: adoption clips the child's effective
    // capabilities to its ancestor path, so the grants applied next can only
    // ever narrow further, never widen past the parent.
    if (parent != null) {
      await ElpianVm.treeGovernor
          .adopt(parentId: parent.machineId, childId: machineId);
    }

    await host._applyPolicy();
    return host;
  }

  static Future<VmRuntimeClient> _startRuntime(
    MiniAppManifest manifest,
    String source,
    String machineId,
  ) async {
    switch (manifest.runtime) {
      case ElpianRuntime.elpian:
        final vm = await ElpianVm.fromCode(machineId, source);
        if (vm == null) {
          throw MiniAppException(
            manifest.id,
            'the Elpian runtime could not start it: ${ElpianVm.lastApiError}',
          );
        }
        return vm;
      case ElpianRuntime.quickJs:
        return QuickJsVm.fromCode(machineId, source);
      case ElpianRuntime.wasm:
        return WasmVm.fromCode(machineId, source);
    }
  }

  /// Push the resolved policy into the runtime.
  Future<void> _applyPolicy() async {
    await governor.sandbox(policy.capabilities);
    await governor.setLimits(policy.limits);
  }

  // -- The host-call gate ----------------------------------------------------

  /// A [HostHandler] wired to this mini app: its own DOM and canvas store, and
  /// an authorization gate that refuses anything the policy does not permit.
  ///
  /// The VM already gates `askHost` by capability, so for an Elpian-backed app
  /// this is a second gate. It is not redundant: it covers the QuickJS and WASM
  /// backends, and it applies the grant's per-API allowlist, which the VM's
  /// capability families cannot express.
  HostHandler createHostHandler({
    RenderHostCallback? onRender,
    void Function(Map<String, dynamic>)? onUpdateApp,
    void Function(String)? onPrintln,
    Map<String, dynamic> Function()? onGetEnvironment,
    void Function(String apiName)? onCallRefused,
  }) =>
      HostHandler(
        services: services,
        onRender: onRender,
        onUpdateApp: onUpdateApp,
        onPrintln: onPrintln,
        onGetEnvironment: onGetEnvironment,
        onAuthorize: authorizes,
        onCallRefused: onCallRefused,
      );

  /// Whether this mini app may make [apiName].
  bool authorizes(String apiName) {
    final capability = ElpianCapability.fromWireName(
          VmHostApiCatalog.capabilityFor(apiName),
        ) ??
        // An unrecognised gate is never a pass.
        ElpianCapability.other;
    return policy.allowsApi(apiName, capability);
  }

  // -- Nesting ---------------------------------------------------------------

  /// Start a mini app inside this one's GUI.
  ///
  /// The child's grant is **this app's own policy**, not the super app's, which
  /// is what makes "a parent can never confer what it lacks" true at the host
  /// layer as well as inside the VM. A parent narrows its children by passing a
  /// [MiniAppGrant] tighter than its own; it cannot widen them, because
  /// [MiniAppPolicy.resolve] intersects against the grant it is given.
  Future<MiniAppHost> spawnChild({
    required MiniAppManifest manifest,
    required String source,
    MiniAppGrant? grant,
  }) async {
    if (_disposed) {
      throw MiniAppException(id, 'cannot spawn a child from a disposed app');
    }
    if (!policy.mayHostChildren) {
      throw MiniAppException(
        id,
        'this mini app is not permitted to host children — it needs '
        '`allowsChildren` in its manifest, `mayHostChildren` in its grant, and '
        'the vm_manage capability',
      );
    }

    final childGrant = _narrow(grant);
    final child = await MiniAppHost.launch(
      manifest: manifest,
      grant: childGrant,
      source: source,
      parent: this,
    );
    _children.add(child);
    return child;
  }

  /// A grant for a child, clipped to what this app itself holds.
  ///
  /// Passing a wider grant than the parent's own is not an error — it is simply
  /// clipped, in the host and again in the VM. That keeps the rule impossible
  /// to get wrong by accident: there is no call a parent can make that widens a
  /// child past itself.
  MiniAppGrant _narrow(MiniAppGrant? requested) {
    final base = requested ??
        MiniAppGrant(
          capabilities: policy.capabilities,
          limits: policy.limits,
          mayHostChildren: policy.mayHostChildren,
          allowedApis: policy.grant.allowedApis,
        );
    return MiniAppGrant(
      capabilities: base.capabilities.intersection(policy.capabilities),
      limits: MiniAppPolicy.tightest(base.limits, policy.limits),
      mayHostChildren: base.mayHostChildren && policy.mayHostChildren,
      allowedApis: _intersectApis(base.allowedApis, policy.grant.allowedApis),
    );
  }

  static Set<String>? _intersectApis(Set<String>? a, Set<String>? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.intersection(b);
  }

  // -- Metering --------------------------------------------------------------

  /// What this app alone has consumed.
  Future<ElpianUsage> usage() => governor.usage();

  /// What this app **and every app it spawned** have consumed — the figure its
  /// budget is checked against.
  Future<ElpianUsage> branchUsage() => governor.subtreeUsage();

  /// How close this app's branch is to each of its ceilings, 0..1. A super app
  /// uses this to warn, throttle or prompt before a mini app is killed.
  Future<Map<String, double>> pressure() async =>
      (await branchUsage()).pressureAgainst(policy.limits);

  // -- Lifecycle -------------------------------------------------------------

  /// Stop this app and everything it spawned, then release its host state.
  ///
  /// Children go first so a parent's teardown cannot orphan them, mirroring the
  /// VM's rule that terminating a mini app terminates its whole subtree.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    for (final child in List.of(_children)) {
      await child.dispose();
    }
    _children.clear();

    try {
      await runtime.dispose();
    } finally {
      services.dispose();
    }
  }

  @override
  String toString() => 'MiniAppHost($machineId, '
      '${policy.capabilities.length} capabilities'
      '${_children.isEmpty ? '' : ', ${_children.length} children'})';
}
