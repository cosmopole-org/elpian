/// The web transport: a Godot HTML5 export drained from the page.
///
/// Mirrors Victor's `WebGodotEngine`. The Godot web build cannot be called
/// synchronously from Dart, so ops are pushed onto a queue on the page and the
/// running engine drains it each frame through `JavaScriptBridge` — the same
/// `window.__elpianGodotDrain()` hook `OpSink.gd` already looks for, so the
/// engine-side project is reused unchanged.
///
/// Replies come back over a completion map keyed by request id, because the
/// drain is one-way.
///
/// This file is only compiled into web builds (see the conditional import in
/// `godot_binding.dart`); `dart:js_interop` never reaches a native build.
library;

import 'dart:async';
import 'dart:convert';

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';

import 'godot_binding.dart';
import 'protocol.dart';

/// Construct the web transport. Called by the conditional import in
/// `godot_binding.dart`, so nothing has to be installed by hand.
GodotBinding? createWebGodotBinding() => WebGodotBinding();

/// Install this binding as the web factory.
///
/// Redundant now that `godot_binding.dart` resolves the transport through a
/// conditional import; kept for an embedder that wants to force it (or install
/// a subclass) before the first `Scene3D` builds.
void installWebGodotBinding() {
  webGodotBindingFactory = WebGodotBinding.new;
}

// The queue and reply slot live on the page, not in Dart, so the Godot export
// (which sees only JavaScript) can reach them without a Dart round trip. They
// are addressed through `globalContext` rather than typed externals so a page
// that has not installed the hooks yet simply reads back null.
const _queueKey = '__elpianGodotQueue';
const _repliesKey = '__elpianGodotReplies';
const _drainKey = '__elpianGodotDrain';

JSArray<JSString>? get _queue =>
    globalContext.getProperty(_queueKey.toJS) as JSArray<JSString>?;

set _queue(JSArray<JSString>? value) =>
    globalContext.setProperty(_queueKey.toJS, value);

JSObject? get _replies => globalContext.getProperty(_repliesKey.toJS) as JSObject?;

class WebGodotBinding implements GodotBinding {
  WebGodotBinding() {
    _ensureQueue();
  }

  int _nextRequestId = 1;
  bool _polling = false;
  final Map<int, Completer<List<Wire>>> _awaiting = {};
  Timer? _poll;

  @override
  GodotSignalDispatch? onSignal;

  /// A Godot web export is only live once the page has installed the drain
  /// hook; until then the surface shows its placeholder.
  @override
  bool get isLive => _hasDrainHook();

  void _ensureQueue() {
    _queue ??= <JSString>[].toJS;
    _ensurePolling();
  }

  /// Replies and signals arrive asynchronously from the engine, so they are
  /// polled rather than blocking a frame on them.
  ///
  /// Two cadences, because this binding is now constructed on **every** web
  /// page whether or not a Godot export is present (see `resolveGodotBinding`).
  /// Draining at 60 Hz forever on a page that has no engine would be pure
  /// waste, so until the drain hook appears we only look once a second, then
  /// upgrade to per-frame and stay there.
  void _ensurePolling() {
    if (_polling == _hasDrainHook()) return;
    _polling = _hasDrainHook();
    _poll?.cancel();
    _poll = Timer.periodic(
      _polling ? const Duration(milliseconds: 16) : const Duration(seconds: 1),
      (_) {
        if (!_polling) {
          _ensurePolling();
          return;
        }
        _drainReplies();
      },
    );
  }

  bool _hasDrainHook() {
    try {
      return globalContext.has(_drainKey);
    } catch (_) {
      return false;
    }
  }

  void _push(String payload) {
    _ensureQueue();
    _queue?.toDart.add(payload.toJS);
  }

  @override
  void post(List<Op> ops) {
    if (ops.isEmpty) return;
    _push(jsonEncode({'ops': ops}));
  }

  @override
  Future<List<Wire>> send(List<Op> ops) {
    if (ops.isEmpty) return Future.value(const []);
    final id = _nextRequestId++;
    final completer = Completer<List<Wire>>();
    _awaiting[id] = completer;
    _push(jsonEncode({'ops': ops, 'req': id}));
    // A reply that never arrives must not wedge the caller — the engine may not
    // be running at all on this page.
    return completer.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        _awaiting.remove(id);
        return List<Wire>.filled(ops.length, null);
      },
    );
  }

  void _drainReplies() {
    final replies = _replies;
    if (replies == null) return;
    try {
      final raw = replies.getProperty('pending'.toJS);
      if (raw == null) return;
      final decoded = jsonDecode((raw as JSString).toDart);
      if (decoded is! List) return;
      replies.setProperty('pending'.toJS, null);
      for (final entry in decoded) {
        if (entry is! Map) continue;
        if (entry['cb'] is int) {
          final args = entry['args'];
          onSignal?.call(entry['cb'] as int, args is List ? args : const []);
          continue;
        }
        final id = entry['req'];
        if (id is int) {
          final completer = _awaiting.remove(id);
          final values = entry['values'];
          completer?.complete(values is List ? values : const []);
        }
      }
    } catch (e) {
      debugPrint('ElpianGodot(web): reply drain failed: $e');
    }
  }

  @override
  Future<void> mountSurface(int surfaceId, int mountHandle) async =>
      _push(jsonEncode({'mount': surfaceId, 'node': mountHandle}));

  @override
  Future<void> releaseSurface(int surfaceId) async =>
      _push(jsonEncode({'release': surfaceId}));

  @override
  Future<Map<String, Object?>?> stats() async =>
      {'queued': _queue?.toDart.length ?? 0, 'awaiting': _awaiting.length};

  @override
  void dispose() {
    _poll?.cancel();
    _poll = null;
    _polling = false;
    _awaiting.clear();
  }
}
