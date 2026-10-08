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

  /// Island names already registered with the engine, so a re-render does not
  /// re-register them on every frame.
  final Set<String> _registeredIslands = <String>{};

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
    _registerIslands();
    _fetch();
    _scheduleRevalidation();
  }

  /// Teach the engine to build each island this bundle carries.
  ///
  /// The engine resolves a node's `type` through its widget registry, so an
  /// island is just a type the registry happens to know. That is the whole
  /// mechanism: nothing walks the tree looking for islands, and nothing has to
  /// rebuild composition by hand.
  ///
  /// An island the bundle does *not* carry is deliberately left unregistered.
  /// The engine then renders the payload's own node for it — its static form —
  /// rather than the app failing. An app shipping a component that names an
  /// island its client half lacks is a deployment mistake, and a non-interactive
  /// panel is a better answer than a blank screen.
  void _registerIslands() {
    widget.islandBuilders.forEach((name, build) {
      if (_registeredIslands.add(name)) {
        _engine.registerWidget(name, (node, children) {
          // The payload carries the island's props on the node; children are
          // whatever the server put inside it, already rendered, so an island
          // can wrap server-rendered content rather than only replacing it.
          return _IslandHost(
            builder: build,
            props: Map<String, dynamic>.from(node.props),
            children: children,
          );
        });
      }
    });
  }

  @override
  void didUpdateWidget(ServerComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    _registerIslands();
    _didUpdate(oldWidget);
  }

  void _didUpdate(ServerComponent oldWidget) {
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

    final result =
        await widget.client.renderComponent(widget.name, widget.args);

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
        return widget.pending ??
            const Center(child: CircularProgressIndicator());
      }
      return const SizedBox.shrink();
    }

    final component = payload['component'];
    if (component is! Map<String, dynamic>) {
      return _defaultError('the server component returned no component tree');
    }

    final stylesheet = payload['stylesheet'];
    // A payload comes from a server, and a device does not trust one. A tree
    // the engine cannot walk — a mistyped node, a missing field — must show the
    // error state rather than throwing out of `build`, which in Flutter
    // replaces the whole subtree with a red screen and takes the surrounding
    // app down with it.
    try {
      return _engine.renderWithStylesheet(
        component,
        stylesheet: stylesheet is Map<String, dynamic> ? stylesheet : null,
      );
    } catch (error) {
      debugPrint(
          'ServerComponent(${widget.name}): unrenderable payload: $error');
      return widget.errorBuilder?.call(
              context, 'the server sent a payload this app could not render') ??
          _defaultError('the server sent a payload this app could not render');
    }
  }

  /// Islands the payload named that this bundle cannot build.
  ///
  /// Exposed for diagnostics rather than used for control flow: an unresolved
  /// island is not an error at render time, it is a deployment mistake worth
  /// telling somebody about.
  List<String> unresolvedIslands() {
    final declared = _payload?['clientComponents'];
    if (declared is! Map) return const [];
    return declared.keys
        .map((k) => k.toString())
        .where((name) => !widget.islandBuilders.containsKey(name))
        .toList(growable: false);
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

/// Renders one island, with whatever the server put inside it as children.
///
/// A separate widget rather than an inline closure so an island gets its own
/// element in the tree: it can hold state, and rebuilding the server payload
/// around it does not throw that state away as long as its position is stable.
class _IslandHost extends StatelessWidget {
  const _IslandHost({
    required this.builder,
    required this.props,
    required this.children,
  });

  final IslandBuilder builder;
  final Map<String, dynamic> props;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // Server-rendered children are passed through the props under a reserved
    // key, so a builder that wants to wrap them can, and one that does not can
    // ignore them entirely.
    return builder(context, {
      ...props,
      if (children.isNotEmpty) '#children': children,
    });
  }
}
