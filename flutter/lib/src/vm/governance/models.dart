/// The host-facing model of Elpian's governance control plane.
///
/// These types mirror the Rust `sdk::limits`, `sdk::capabilities`,
/// `sdk::lifecycle` and `sdk::hierarchy` modules. They are plain data with no
/// platform dependency, so the native (dart:ffi) and web (WASM) backends both
/// speak them and host code is written once.
///
/// The wire format is the JSON documented on `rust/src/api/govern.rs`.
library;

import 'dart:convert';

/// Thrown when the runtime refuses a governance call.
///
/// The control plane reports failures in band (`{"error": "vm_not_found"}`)
/// rather than returning a value a host might mistake for a real answer.
class ElpianGovernanceException implements Exception {
  const ElpianGovernanceException(this.reason, {this.call});

  /// The machine-readable reason, e.g. `vm_not_found`, `unknown_capability`.
  final String reason;

  /// Which control-plane call failed, when known.
  final String? call;

  @override
  String toString() => call == null
      ? 'ElpianGovernanceException: $reason'
      : 'ElpianGovernanceException: $call failed: $reason';
}

/// Decode a control-plane reply, raising [ElpianGovernanceException] on the
/// in-band error shape.
Map<String, dynamic> decodeGovernanceReply(String raw, {String? call}) {
  final Object? parsed;
  try {
    parsed = jsonDecode(raw);
  } on FormatException catch (e) {
    throw ElpianGovernanceException('malformed reply: ${e.message}',
        call: call);
  }
  if (parsed is! Map<String, dynamic>) {
    throw ElpianGovernanceException('expected an object, got $raw', call: call);
  }
  final error = parsed['error'];
  if (error is String) {
    throw ElpianGovernanceException(error, call: call);
  }
  return parsed;
}

// ---------------------------------------------------------------------------
// Resource limits
// ---------------------------------------------------------------------------

/// The bounds a host places on one mini app.
///
/// Every field is nullable and `null` means *unbounded*, matching the Rust
/// `Option<u64>`. Construct with [ElpianLimits.unlimited] and tighten only what
/// you care about, or start from [ElpianLimits.sandboxed].
class ElpianLimits {
  const ElpianLimits({
    this.maxInstructions,
    this.maxInstructionsPerTurn,
    this.maxMemoryBytes,
    this.maxStorageBytes,
    this.maxCallDepth,
  });

  /// Total interpreter steps across the mini app's whole life. Caps CPU work
  /// and halts infinite loops.
  final int? maxInstructions;

  /// Interpreter steps in a *single* turn. Caps latency per host call while
  /// still letting a long-lived mini app do a lot of work over many turns.
  final int? maxInstructionsPerTurn;

  /// Live value-memory, in bytes (approximate by construction).
  final int? maxMemoryBytes;

  /// Persistent storage, in bytes.
  final int? maxStorageBytes;

  /// Function-call nesting depth, guarding native-stack exhaustion.
  final int? maxCallDepth;

  /// No limits at all — for trusted first-party code.
  static const unlimited = ElpianLimits();

  /// A conservative sandbox for untrusted third-party mini apps. Mirrors
  /// `ResourceLimits::sandboxed()` in the VM.
  static const sandboxed = ElpianLimits(
    maxInstructions: 50000000,
    maxInstructionsPerTurn: 5000000,
    maxMemoryBytes: 64 * 1024 * 1024,
    maxStorageBytes: 16 * 1024 * 1024,
    maxCallDepth: 1024,
  );

  factory ElpianLimits.fromJson(Map<String, dynamic> json) => ElpianLimits(
        maxInstructions: json['maxInstructions'] as int?,
        maxInstructionsPerTurn: json['maxInstructionsPerTurn'] as int?,
        maxMemoryBytes: json['maxMemoryBytes'] as int?,
        maxStorageBytes: json['maxStorageBytes'] as int?,
        maxCallDepth: json['maxCallDepth'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'maxInstructions': maxInstructions,
        'maxInstructionsPerTurn': maxInstructionsPerTurn,
        'maxMemoryBytes': maxMemoryBytes,
        'maxStorageBytes': maxStorageBytes,
        'maxCallDepth': maxCallDepth,
      };

  ElpianLimits copyWith({
    int? maxInstructions,
    int? maxInstructionsPerTurn,
    int? maxMemoryBytes,
    int? maxStorageBytes,
    int? maxCallDepth,
  }) =>
      ElpianLimits(
        maxInstructions: maxInstructions ?? this.maxInstructions,
        maxInstructionsPerTurn:
            maxInstructionsPerTurn ?? this.maxInstructionsPerTurn,
        maxMemoryBytes: maxMemoryBytes ?? this.maxMemoryBytes,
        maxStorageBytes: maxStorageBytes ?? this.maxStorageBytes,
        maxCallDepth: maxCallDepth ?? this.maxCallDepth,
      );

  @override
  String toString() => 'ElpianLimits(${toJson()})';
}

// ---------------------------------------------------------------------------
// Usage meters
// ---------------------------------------------------------------------------

/// What a mini app is actually consuming.
///
/// Read it for one mini app with `usage`, or for a mini app *and everything it
/// spawned* with `subtreeUsage` — the figure a parent is accountable for.
class ElpianUsage {
  const ElpianUsage({
    required this.instructions,
    required this.instructionsThisTurn,
    required this.memoryBytes,
    required this.peakMemoryBytes,
    required this.storageBytes,
    required this.callDepth,
    required this.peakCallDepth,
  });

  final int instructions;
  final int instructionsThisTurn;
  final int memoryBytes;
  final int peakMemoryBytes;
  final int storageBytes;
  final int callDepth;
  final int peakCallDepth;

  static const zero = ElpianUsage(
    instructions: 0,
    instructionsThisTurn: 0,
    memoryBytes: 0,
    peakMemoryBytes: 0,
    storageBytes: 0,
    callDepth: 0,
    peakCallDepth: 0,
  );

  factory ElpianUsage.fromJson(Map<String, dynamic> json) => ElpianUsage(
        instructions: (json['instructions'] as num?)?.toInt() ?? 0,
        instructionsThisTurn:
            (json['instructionsThisTurn'] as num?)?.toInt() ?? 0,
        memoryBytes: (json['memoryBytes'] as num?)?.toInt() ?? 0,
        peakMemoryBytes: (json['peakMemoryBytes'] as num?)?.toInt() ?? 0,
        storageBytes: (json['storageBytes'] as num?)?.toInt() ?? 0,
        callDepth: (json['callDepth'] as num?)?.toInt() ?? 0,
        peakCallDepth: (json['peakCallDepth'] as num?)?.toInt() ?? 0,
      );

  /// How much of [limits] this usage has consumed, per axis, as a 0..1 ratio.
  /// Unbounded axes are absent. Useful for a host that wants to warn before a
  /// mini app is killed rather than after.
  Map<String, double> pressureAgainst(ElpianLimits limits) {
    final out = <String, double>{};
    void add(String axis, int used, int? max) {
      if (max != null && max > 0) out[axis] = used / max;
    }

    add('instructions', instructions, limits.maxInstructions);
    add('instructionsPerTurn', instructionsThisTurn,
        limits.maxInstructionsPerTurn);
    add('memory', memoryBytes, limits.maxMemoryBytes);
    add('storage', storageBytes, limits.maxStorageBytes);
    add('callDepth', callDepth, limits.maxCallDepth);
    return out;
  }

  @override
  String toString() => 'ElpianUsage(instructions: $instructions, '
      'memoryBytes: $memoryBytes, storageBytes: $storageBytes)';
}

// ---------------------------------------------------------------------------
// Capabilities
// ---------------------------------------------------------------------------

/// A class of side effect a mini app may be permitted to perform.
///
/// Names match `Capability::as_str` in the VM exactly — they are the wire
/// format, not a display label.
enum ElpianCapability {
  logging('logging'),
  gpu('gpu'),
  moduleImport('module_import'),
  network('network'),
  storage('storage'),
  clock('clock'),
  randomness('randomness'),
  vmManage('vm_manage'),
  dom('dom'),
  canvas('canvas'),
  render('render'),
  timers('timers'),
  environment('environment'),
  tasks('tasks'),
  hostMessaging('host_messaging'),

  /// The host's drawing surface: the op seams a guest submits UI through
  /// (`godot.*`, `flutter.*`). One gate for both because they speak the same op
  /// vocabulary, and a mini app that may draw at all may draw on whichever
  /// surface its host provides.
  ///
  /// This was missing while the VM had it, so `godot.op` and `flutter.op` —
  /// which the generated catalog maps to `surface` — resolved to [other] here
  /// instead. That failed safe, but it re-coupled the drawing surface to the
  /// catch-all gate the `surface` split existed to get it out of: a host could
  /// not deny a mini app the drawing surface without denying every unrecognised
  /// API too. The Rust test `host_api_catalog::the_dart_capability_enum_matches_the_vms`
  /// now fails if the two enums drift again.
  surface('surface'),

  /// Calling this mini app's *own* server functions (`server.*`).
  ///
  /// Its own gate, separate from [network], because the two answer different
  /// questions. A mini app in a closed network posture holds no [network] at
  /// all and still needs to reach its own backend: that pair — may talk to my
  /// server, may not talk to anything else — is the closed cycle, and it is not
  /// expressible with a single gate.
  serverCall('server_call'),

  /// Durable per-app key/value state (`kv.*`), and the declared secrets a
  /// server function may read (`secret.get`).
  ///
  /// Separate from [storage], which is the fabricated filesystem: a server
  /// function is routinely given state without being given a filesystem.
  state('state'),

  /// The fail-safe gate for anything the VM does not recognise. Never grant it
  /// to widen a mini app's reach — narrow the API into a real family instead.
  other('other');

  const ElpianCapability(this.wireName);

  final String wireName;

  static ElpianCapability? fromWireName(String name) {
    for (final c in ElpianCapability.values) {
      if (c.wireName == name) return c;
    }
    return null;
  }
}

/// Which capabilities a mini app holds.
///
/// Two sets matter and they are not the same. *Local* is what this mini app was
/// granted directly. *Effective* is that AND every ancestor's — what it may
/// actually do. A parent that lacks a capability can never confer it, so a
/// local grant an ancestor denies is recorded but inert.
class ElpianCapabilities {
  const ElpianCapabilities(this._allowed);

  final Map<ElpianCapability, bool> _allowed;

  factory ElpianCapabilities.fromJson(Map<String, dynamic> json) {
    final map = <ElpianCapability, bool>{};
    for (final entry in json.entries) {
      final cap = ElpianCapability.fromWireName(entry.key);
      if (cap != null && entry.value is bool) {
        map[cap] = entry.value as bool;
      }
    }
    return ElpianCapabilities(map);
  }

  /// Whether [capability] is permitted. Unknown to this build reads as denied —
  /// an unrecognised gate must never be a pass.
  bool allows(ElpianCapability capability) => _allowed[capability] ?? false;

  /// The capabilities currently permitted.
  Set<ElpianCapability> get granted =>
      _allowed.entries.where((e) => e.value).map((e) => e.key).toSet();

  /// The capabilities currently denied.
  Set<ElpianCapability> get denied =>
      _allowed.entries.where((e) => !e.value).map((e) => e.key).toSet();

  Map<String, bool> toJson() =>
      {for (final e in _allowed.entries) e.key.wireName: e.value};

  @override
  String toString() =>
      'ElpianCapabilities(granted: ${granted.map((c) => c.wireName).toList()})';
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

/// A mini app's run state, as the executor's step loop sees it.
enum ElpianRunState {
  running('running'),
  pauseRequested('pause_requested'),
  paused('paused'),
  terminateRequested('terminate_requested'),
  terminated('terminated');

  const ElpianRunState(this.wireName);

  final String wireName;

  static ElpianRunState fromWireName(String name) => ElpianRunState.values
      .firstWhere((s) => s.wireName == name, orElse: () => terminated);
}

/// Run state, trap reason and in-flight status in one read.
class ElpianVmState {
  const ElpianVmState({
    required this.state,
    required this.trapReason,
    required this.processing,
  });

  final ElpianRunState state;

  /// Why the mini app was stopped, if it was — a limit overrun, or a guest
  /// fault the VM turned into a trap. Null while it is healthy.
  final String? trapReason;

  /// Whether a turn is in flight right now.
  final bool processing;

  /// Whether this mini app has stopped for good.
  bool get isDead =>
      state == ElpianRunState.terminated ||
      state == ElpianRunState.terminateRequested;

  /// Whether it stopped because something went wrong, as opposed to a clean
  /// host-ordered terminate.
  bool get isTrapped => trapReason != null && trapReason!.isNotEmpty;

  factory ElpianVmState.fromJson(Map<String, dynamic> json) {
    final reason = json['trapReason'];
    return ElpianVmState(
      state:
          ElpianRunState.fromWireName(json['state'] as String? ?? 'terminated'),
      trapReason: reason is String && reason.isNotEmpty ? reason : null,
      processing: json['processing'] as bool? ?? false,
    );
  }

  @override
  String toString() => 'ElpianVmState(${state.wireName}'
      '${isTrapped ? ', trapped: $trapReason' : ''})';
}

// ---------------------------------------------------------------------------
// The tree
// ---------------------------------------------------------------------------

/// A mini app's place in the spawn tree.
///
/// A mini app may spawn other mini apps. Each child's execution is counted
/// against its parent's budget as well as its own, and a parent holds full
/// control of its children's limits and permissions.
class ElpianVmTree {
  const ElpianVmTree({
    required this.parent,
    required this.children,
    required this.subtree,
  });

  /// The mini app that spawned this one, or null for a root.
  final String? parent;

  /// Direct children.
  final List<String> children;

  /// This mini app and every descendant, pre-order.
  final List<String> subtree;

  factory ElpianVmTree.fromJson(Map<String, dynamic> json) => ElpianVmTree(
        parent: json['parent'] as String?,
        children:
            (json['children'] as List?)?.map((e) => e as String).toList() ?? [],
        subtree:
            (json['subtree'] as List?)?.map((e) => e as String).toList() ?? [],
      );

  bool get isRoot => parent == null;

  @override
  String toString() => 'ElpianVmTree(parent: $parent, children: $children)';
}

/// One branch destroyed for breaking its own root's aggregate budget.
class ElpianBudgetViolation {
  const ElpianBudgetViolation({
    required this.machineId,
    required this.axis,
    required this.destroyed,
  });

  /// The mini app whose aggregate budget was broken.
  final String machineId;

  /// Which budget: `instructions`, `memory` or `storage`.
  final String axis;

  /// Every mini app taken down with it — the whole branch shares its fate.
  final List<String> destroyed;

  factory ElpianBudgetViolation.fromJson(Map<String, dynamic> json) =>
      ElpianBudgetViolation(
        machineId: json['machineId'] as String? ?? '',
        axis: json['axis'] as String? ?? 'unknown',
        destroyed:
            (json['destroyed'] as List?)?.map((e) => e as String).toList() ??
                [],
      );

  @override
  String toString() =>
      'ElpianBudgetViolation($machineId broke $axis; destroyed $destroyed)';
}

/// Everything a host dashboard shows for one mini app and its branch, from a
/// single call.
class ElpianVmSnapshot {
  const ElpianVmSnapshot({
    required this.machineId,
    required this.state,
    required this.limits,
    required this.usage,
    required this.subtreeUsage,
    required this.localCapabilities,
    required this.effectiveCapabilities,
    required this.tree,
  });

  final String machineId;
  final ElpianVmState state;
  final ElpianLimits limits;

  /// This mini app's own consumption.
  final ElpianUsage usage;

  /// Its consumption plus every mini app it spawned — what its budget is
  /// actually checked against.
  final ElpianUsage subtreeUsage;

  final ElpianCapabilities localCapabilities;
  final ElpianCapabilities effectiveCapabilities;
  final ElpianVmTree tree;

  factory ElpianVmSnapshot.fromJson(Map<String, dynamic> json) =>
      ElpianVmSnapshot(
        machineId: json['machineId'] as String? ?? '',
        state: ElpianVmState.fromJson(
            json['state'] as Map<String, dynamic>? ?? {}),
        limits: ElpianLimits.fromJson(
            json['limits'] as Map<String, dynamic>? ?? {}),
        usage:
            ElpianUsage.fromJson(json['usage'] as Map<String, dynamic>? ?? {}),
        subtreeUsage: ElpianUsage.fromJson(
            json['subtreeUsage'] as Map<String, dynamic>? ?? {}),
        localCapabilities: ElpianCapabilities.fromJson(
            json['localCapabilities'] as Map<String, dynamic>? ?? {}),
        effectiveCapabilities: ElpianCapabilities.fromJson(
            json['effectiveCapabilities'] as Map<String, dynamic>? ?? {}),
        tree:
            ElpianVmTree.fromJson(json['tree'] as Map<String, dynamic>? ?? {}),
      );

  @override
  String toString() => 'ElpianVmSnapshot($machineId, ${state.state.wireName}, '
      'instructions: ${subtreeUsage.instructions})';
}
