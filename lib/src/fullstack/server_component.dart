import 'dart:async';

import 'package:flutter/material.dart';

import '../core/elpian_engine.dart';
import 'server_client.dart';

/// A server component, rendered on the device from the payload its server
/// function returned.
///
/// # A component returns; it does not render
///
/// The server function is a pure function of its arguments and the app's state.
/// It hands back `{component, stylesheet, clientComponents}` and this widget
/// turns that into Flutter. That split is what lets the host cache the payload,
/// lets the component be tested without a device, and stops it half-rendering.
///
/// # Islands degrade rather than fail
///
/// A payload may name interactive pieces in `clientComponents`. Each is
/// resolved against [islandBuilders] — components this *client bundle* already
/// carries, fetched and verified as one artifact. Source is never shipped for
/// the device to compile: that would be a second compile path on the device and
/// a far wider trust surface than a signed bundle.
///
/// An island the bundle does not have renders as its static form from the
/// payload. An app shipping a component that names an island its client half
/// lacks is a deployment mistake, and a blank screen is a worse answer than a
/// non-interactive one.
class ServerComponent extends StatefulWidget {
  const ServerComponent({
    super.key,
    required this.client,
    required this.name,
    this.args = const <String, dynamic>{},
    this.pending,
    this.errorBuilder,
    this.islandBuilders = const <String, IslandBuilder>{},
    this.revalidate,
    this.engine,
  });

  /// The connector for this mini app. Carries the app id, so the component
  /// name is all a caller supplies.
  final ElpianServerClient client;

  /// The server component's function name.
  final String name;

  /// Arguments. Part of the host's cache key, so two different arguments are
  /// two different renders.
  final Map<String, dynamic> args;

  /// Shown while the first render is in flight. A *later* render keeps the
  /// current tree on screen rather than flashing back to this — replacing
  /// content the reader is looking at with a spinner is worse than showing them
  /// content that is a second old.
  final Widget? pending;

  final Widget Function(BuildContext context, String message)? errorBuilder;

  /// Interactive pieces this client bundle carries, by the name a payload uses.
  final Map<String, IslandBuilder> islandBuilders;

  /// Re-fetch on this interval. Null means fetch once.
  final Duration? revalidate;

  final ElpianEngine? engine;

  @override
  State<ServerComponent> createState() => _ServerComponentState();
}

/// Builds an interactive island from the props a payload carried.
typedef IslandBuilder = Widget Function(
    BuildContext context, Map<String, dynamic> props);

class _ServerComponentState extends State<ServerComponent> {
  late final ElpianEngine _engine = widget.engine ?? ElpianEngine();
  Timer? _timer;

  Map<String, dynamic>? _payload;
  String? _error;
  bool _loading = true;

  /// Guards against a late response overwriting a newer one.
  ///
  /// Two fetches can be in flight when arguments change or a revalidation
  /// overlaps a manual refresh, and they can finish out of order. Without this,
  /// the slower — older — answer wins and the component shows stale content
  /// that no further event will correct.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _fetch();
    _scheduleRevalidation();
  }

  @override
  void didUpdateWidget(ServerComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name ||
        !_sameArgs(oldWidget.args, widget.args)) {
      _fetch();
    }
    if (oldWidget.revalidate != widget.revalidate) {
      _scheduleRevalidation();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _scheduleRevalidation() {
    _timer?.cancel();
    final interval = widget.revalidate;
    if (interval != null) {
      _timer = Timer.periodic(interval, (_) => _fetch());
    }
  }

  Future<void> _fetch() async {
    final generation = ++_generation;
    // Only the very first fetch shows the pending state; a revalidation keeps
    // what is already on screen.
    if (_payload == null && mounted) {
      setState(() => _loading = true);
    }

    final result = await widget.client.renderComponent(widget.name, widget.args);

    if (!mounted || generation != _generation) return;
    setState(() {
      _loading = false;
      if (result.error != null) {
        _error = result.error;
        // A failed revalidation does NOT clear a payload that is already
        // showing. Losing working content because a refresh failed is worse
        // than showing content that is slightly old.
      } else {
        _error = null;
        _payload = result.payload;
      }
    });
  }

  bool _sameArgs(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final payload = _payload;

    if (payload == null) {
      if (_error != null) {
        return widget.errorBuilder?.call(context, _error!) ??
            _defaultError(_error!);
      }
      if (_loading) {
        return widget.pending ?? const Center(child: CircularProgressIndicator());
      }
      return const SizedBox.shrink();
    }

    final component = payload['component'];
    if (component is! Map<String, dynamic>) {
      return _defaultError('the server component returned no component tree');
    }

    final stylesheet = payload['stylesheet'];
    final rendered = _engine.renderWithStylesheet(
      _resolveIslands(context, component, payload['clientComponents']),
      stylesheet: stylesheet is Map<String, dynamic> ? stylesheet : null,
    );
    return rendered;
  }

  /// Replace island placeholders with builders this bundle carries.
  ///
  /// Walks the tree looking for nodes whose type names a declared island. One
  /// that resolves is swapped for a marker the engine renders through
  /// [IslandHost]; one that does not is left exactly as it came, so it renders
  /// as its static form.
  Map<String, dynamic> _resolveIslands(
    BuildContext context,
    Map<String, dynamic> node,
    dynamic declared,
  ) {
    if (declared is! Map || widget.islandBuilders.isEmpty) return node;
    return _walk(node, declared.keys.map((k) => k.toString()).toSet());
  }

  Map<String, dynamic> _walk(Map<String, dynamic> node, Set<String> islands) {
    final type = node['type']?.toString();
    if (type != null &&
        islands.contains(type) &&
        widget.islandBuilders.containsKey(type)) {
      // Mark it; `build` cannot return a Widget from inside a JSON tree, so the
      // swap happens at render time via a type the engine knows.
      return {
        ...node,
        '_island': type,
      };
    }
    final children = node['children'];
    if (children is List) {
      return {
        ...node,
        'children': children
            .map((child) =>
                child is Map<String, dynamic> ? _walk(child, islands) : child)
            .toList(growable: false),
      };
    }
    return node;
  }

  Widget _defaultError(String message) => Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
}

/// The result of asking the host to render a component.
class ServerRenderResult {
  const ServerRenderResult({this.payload, this.error});

  final Map<String, dynamic>? payload;

  /// The server's message. Deliberately coarse — the host does not tell a
  /// caller why a function failed, because the caller did not write it.
  final String? error;
}
