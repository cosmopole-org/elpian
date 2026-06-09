import 'package:flutter/foundation.dart';

/// Lightweight, opt-in timing trace for diagnosing interaction latency
/// (e.g. "a 15s delay opening the menu").
///
/// Each [mark] logs the wall-clock delta since the previous mark, so a long
/// stall shows up as a single large `+Nms` gap between two adjacent labels —
/// telling you exactly which step (event delivery, the QuickJS handler, a
/// fragment fetch, the Flutter rebuild, …) is eating the time.
///
/// Disabled by default in release; enabled automatically in debug. To capture
/// timings from a profile/release web build, compile with:
///   flutter build web --dart-define=ELPIAN_TRACE=1
class ElpianTrace {
  ElpianTrace._();

  /// Master switch. On in debug builds, or whenever `ELPIAN_TRACE` is defined to
  /// a truthy value. Accepts `1`/`true`/`yes`/`on` (so the documented
  /// `--dart-define=ELPIAN_TRACE=1` works — `bool.fromEnvironment` alone only
  /// recognises the literal string `true`).
  static bool enabled = kDebugMode || _envEnabled();

  static bool _envEnabled() {
    const raw = String.fromEnvironment('ELPIAN_TRACE');
    final v = raw.trim().toLowerCase();
    return v == '1' || v == 'true' || v == 'yes' || v == 'on';
  }

  static final Stopwatch _sw = Stopwatch()..start();
  static int _lastMs = 0;

  /// Record a checkpoint. Prints `[elpian-trace] +<delta>ms (@<abs>ms) <label>`.
  static void mark(String label) {
    if (!enabled) return;
    final now = _sw.elapsedMilliseconds;
    final delta = now - _lastMs;
    _lastMs = now;
    debugPrint('[elpian-trace] +${delta}ms (@${now}ms) $label');
  }
}
