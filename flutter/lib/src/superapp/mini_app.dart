/// What a mini app *is*, as far as the super app is concerned.
///
/// Elpian had every mechanism for governing untrusted code — capability gates,
/// resource budgets, lifecycle control, a spawn tree with inherited permissions
/// and aggregate accounting — and nothing to attach them to. There was no
/// object in the host meaning "one mini app", so there was nothing to enforce a
/// policy *against*, no identity to namespace resources by, and no place to put
/// the difference between what an app asked for and what it was granted.
///
/// This library is that missing layer:
///
///   * [MiniAppManifest] — what an app declares about itself and asks for.
///   * [MiniAppGrant] — what the super app is willing to give it.
///   * [MiniAppPolicy] — the resolved intersection, which is what actually
///     applies. An app can never receive more than it asked for *or* more than
///     it was granted.
library;

import '../vm/governance/models.dart';
import '../vm/runtime_kind.dart';

/// What a mini app declares about itself.
///
/// The manifest is authored by the mini app and is therefore **untrusted
/// input**. Nothing in it is a grant: `requestedCapabilities` is a request, and
/// [MiniAppPolicy.resolve] decides what of it survives.
class MiniAppManifest {
  const MiniAppManifest({
    required this.id,
    required this.name,
    this.version = '0.0.0',
    this.entrypoint = 'main',
    this.runtime = ElpianRuntime.elpian,
    this.requestedCapabilities = const {},
    this.requestedLimits,
    this.allowsChildren = false,
    this.metadata = const {},
  });

  /// Stable identity, unique within a super app. Used to namespace every
  /// host-side resource the app touches, so ids it chooses cannot collide with
  /// another app's.
  final String id;

  /// Human-readable name, for the app switcher and permission prompts.
  final String name;

  final String version;

  /// The guest function the host calls to start the app.
  final String entrypoint;

  /// Which runtime the app wants. A super app may override this: only the
  /// Elpian VM enforces every governance axis, so untrusted code belongs there
  /// whatever the manifest asks for. See `GovernanceSupport`.
  final ElpianRuntime runtime;

  /// What the app says it needs. A request, not a grant.
  final Set<ElpianCapability> requestedCapabilities;

  /// The budget the app would like. Null means it did not ask, and the super
  /// app's default applies.
  final ElpianLimits? requestedLimits;

  /// Whether this app expects to host mini apps of its own inside its GUI.
  ///
  /// Nesting is only possible when the app holds [ElpianCapability.vmManage],
  /// which a super app grants deliberately — an app that can spawn children
  /// can spend the parent's budget on them.
  final bool allowsChildren;

  /// Anything the super app wants to carry alongside — an icon, a category, a
  /// publisher. Opaque here.
  final Map<String, dynamic> metadata;

  factory MiniAppManifest.fromJson(Map<String, dynamic> json) {
    final caps = <ElpianCapability>{};
    for (final raw in (json['requestedCapabilities'] as List? ?? const [])) {
      final cap = ElpianCapability.fromWireName(raw.toString());
      // An unrecognised capability name is dropped rather than rejected: a
      // manifest written against a newer Elpian must not brick the app, and
      // dropping is the safe direction — it can only narrow what is asked for.
      if (cap != null) caps.add(cap);
    }
    final limits = json['requestedLimits'];
    return MiniAppManifest(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? json['id'] as String? ?? 'Untitled',
      version: json['version'] as String? ?? '0.0.0',
      entrypoint: json['entrypoint'] as String? ?? 'main',
      runtime: _runtimeFromName(json['runtime'] as String?),
      requestedCapabilities: caps,
      requestedLimits:
          limits is Map<String, dynamic> ? ElpianLimits.fromJson(limits) : null,
      allowsChildren: json['allowsChildren'] as bool? ?? false,
      metadata: (json['metadata'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'entrypoint': entrypoint,
        'runtime': runtime.name,
        'requestedCapabilities':
            requestedCapabilities.map((c) => c.wireName).toList(),
        if (requestedLimits != null)
          'requestedLimits': requestedLimits!.toJson(),
        'allowsChildren': allowsChildren,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  static ElpianRuntime _runtimeFromName(String? name) {
    switch (name) {
      case 'quickJs':
      case 'quickjs':
        return ElpianRuntime.quickJs;
      case 'wasm':
        return ElpianRuntime.wasm;
      default:
        return ElpianRuntime.elpian;
    }
  }

  /// Why this manifest is unusable, or null if it is well formed.
  String? validate() {
    if (id.isEmpty) return 'a mini app must declare an id';
    if (id.contains('::')) {
      // `::` is the resource-namespacing separator; allowing it in an id would
      // let one app forge another's namespace.
      return 'a mini app id may not contain "::"';
    }
    if (entrypoint.isEmpty) return 'a mini app must declare an entrypoint';
    return null;
  }

  @override
  String toString() => 'MiniAppManifest($id v$version, ${runtime.name})';
}

/// What the super app is willing to give a mini app.
///
/// Authored by the super app, not the mini app. This is the trusted half.
class MiniAppGrant {
  const MiniAppGrant({
    required this.capabilities,
    required this.limits,
    this.mayHostChildren = false,
    this.allowedApis,
  });

  /// The most this app may ever hold.
  final Set<ElpianCapability> capabilities;

  /// The budget it is held to.
  final ElpianLimits limits;

  /// Whether it may spawn mini apps of its own.
  final bool mayHostChildren;

  /// An optional allowlist of individual host APIs, finer than a capability.
  ///
  /// Null means "anything the capabilities permit". A non-null set is an
  /// additional narrowing — an app may hold [ElpianCapability.network] and
  /// still be restricted to `net.fetch`.
  final Set<String>? allowedApis;

  /// The posture for code the super app does not trust: nothing but the ability
  /// to draw itself.
  ///
  /// [ElpianCapability.surface] belongs here alongside the other drawing gates:
  /// on a Flutter host a mini app submits its UI through the `flutter.*` op
  /// seam, so without it "nothing but the ability to draw itself" would not
  /// include drawing itself. It was absent only because the enum was missing
  /// the member entirely.
  static const untrusted = MiniAppGrant(
    capabilities: {
      ElpianCapability.render,
      ElpianCapability.dom,
      ElpianCapability.canvas,
      ElpianCapability.surface,
      ElpianCapability.logging,
    },
    limits: ElpianLimits.sandboxed,
  );

  /// The posture for first-party code: everything, unbounded.
  static final trusted = MiniAppGrant(
    capabilities: ElpianCapability.values.toSet(),
    limits: ElpianLimits.unlimited,
    mayHostChildren: true,
  );

  @override
  String toString() => 'MiniAppGrant(${capabilities.length} capabilities, '
      'children: $mayHostChildren)';
}

/// What a mini app actually gets: the intersection of what it asked for and
/// what it was granted.
///
/// Both directions matter. Intersecting with the grant is the security
/// property — an app cannot take more than the super app allows. Intersecting
/// with the request is least privilege — an app that asked for nothing but
/// rendering does not silently receive the network because its grant was
/// generous.
class MiniAppPolicy {
  const MiniAppPolicy({
    required this.manifest,
    required this.grant,
    required this.capabilities,
    required this.limits,
    required this.mayHostChildren,
    required this.deniedRequests,
  });

  final MiniAppManifest manifest;
  final MiniAppGrant grant;

  /// What the app holds. Never wider than the grant, never wider than the
  /// request.
  final Set<ElpianCapability> capabilities;

  /// The budget in force. The tighter of the two where both specify one.
  final ElpianLimits limits;

  final bool mayHostChildren;

  /// What the app asked for and did not get. A super app shows this in a
  /// permission prompt, or logs it; a mini app seeing unexpected denials can be
  /// told exactly which.
  final Set<ElpianCapability> deniedRequests;

  /// Resolve a manifest against a grant.
  ///
  /// A manifest that requests nothing is treated as requesting everything it
  /// was granted — otherwise a mini app that simply omitted the field would
  /// launch with no capabilities and fail confusingly. Least privilege applies
  /// to what an app *states*, not to what it forgot to state.
  factory MiniAppPolicy.resolve(MiniAppManifest manifest, MiniAppGrant grant) {
    final requested = manifest.requestedCapabilities.isEmpty
        ? grant.capabilities
        : manifest.requestedCapabilities;

    final allowed = requested.intersection(grant.capabilities);
    final denied = requested.difference(grant.capabilities);

    return MiniAppPolicy(
      manifest: manifest,
      grant: grant,
      capabilities: allowed,
      limits: tightest(manifest.requestedLimits, grant.limits),
      mayHostChildren: manifest.allowsChildren &&
          grant.mayHostChildren &&
          allowed.contains(ElpianCapability.vmManage),
      deniedRequests: denied,
    );
  }

  /// Whether [apiName] is permitted: its capability must be held, and it must
  /// survive the grant's API allowlist if there is one.
  bool allowsApi(String apiName, ElpianCapability capability) {
    if (!capabilities.contains(capability)) return false;
    final allowlist = grant.allowedApis;
    return allowlist == null || allowlist.contains(apiName);
  }

  /// The tighter of two budgets, axis by axis.
  ///
  /// A null on either side means "unbounded from this side", so the other
  /// wins; null on both stays null. Public because nesting needs it too: a
  /// child's budget is the tighter of what it was offered and what its parent
  /// holds.
  static ElpianLimits tightest(ElpianLimits? a, ElpianLimits b) {
    if (a == null) return b;
    int? min(int? x, int? y) {
      if (x == null) return y;
      if (y == null) return x;
      return x < y ? x : y;
    }

    return ElpianLimits(
      maxInstructions: min(a.maxInstructions, b.maxInstructions),
      maxInstructionsPerTurn:
          min(a.maxInstructionsPerTurn, b.maxInstructionsPerTurn),
      maxMemoryBytes: min(a.maxMemoryBytes, b.maxMemoryBytes),
      maxStorageBytes: min(a.maxStorageBytes, b.maxStorageBytes),
      maxCallDepth: min(a.maxCallDepth, b.maxCallDepth),
    );
  }

  @override
  String toString() => 'MiniAppPolicy(${manifest.id}: '
      '${capabilities.map((c) => c.wireName).toList()}'
      '${deniedRequests.isEmpty ? '' : ', denied: '
          '${deniedRequests.map((c) => c.wireName).toList()}'})';
}
