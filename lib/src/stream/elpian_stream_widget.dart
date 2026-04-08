import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/elpian_engine.dart';

class ElpianStreamCommand {
  const ElpianStreamCommand({
    required this.action,
    this.view,
    this.patch,
    this.stylesheet,
    this.animate,
    this.animationDurationMs,
    this.animationCurve,
  });

  final String action;
  final Map<String, dynamic>? view;
  final Map<String, dynamic>? patch;
  final Map<String, dynamic>? stylesheet;
  final bool? animate;
  final int? animationDurationMs;
  final String? animationCurve;

  factory ElpianStreamCommand.fromDynamic(dynamic data) {
    if (data is ElpianStreamCommand) return data;

    if (data is String) {
      final decoded = jsonDecode(data);
      return ElpianStreamCommand.fromDynamic(decoded);
    }

    if (data is Map) {
      final map = Map<String, dynamic>.from(data);

      if (map.containsKey('type') && !map.containsKey('action')) {
        return ElpianStreamCommand(action: 'setView', view: map);
      }

      final action = map['action']?.toString();
      if (action == null || action.isEmpty) {
        throw FormatException('Stream command must contain a non-empty "action".');
      }

      return ElpianStreamCommand(
        action: action,
        view: _mapOrNull(map['view']),
        patch: _mapOrNull(map['patch']),
        stylesheet: _mapOrNull(map['stylesheet']),
        animate: _boolOrNull(map['animate']),
        animationDurationMs: _intOrNull(map['animationDurationMs']),
        animationCurve: map['animationCurve']?.toString(),
      );
    }

    throw FormatException('Unsupported stream payload type: ${data.runtimeType}.');
  }

  static Map<String, dynamic>? _mapOrNull(dynamic value) {
    if (value == null) return null;
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw FormatException('Expected a JSON object, got ${value.runtimeType}.');
  }

  static bool? _boolOrNull(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.toLowerCase().trim();
      if (normalized == 'true') return true;
      if (normalized == 'false') return false;
    }
    throw FormatException('Expected a bool, got ${value.runtimeType}.');
  }

  static int? _intOrNull(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    throw FormatException('Expected an int, got ${value.runtimeType}.');
  }
}

class ElpianStreamWidget extends StatefulWidget {
  const ElpianStreamWidget({
    super.key,
    required this.stream,
    this.engine,
    this.initialStylesheet,
    this.loadingWidget,
    this.errorBuilder,
    this.onCommand,
    this.onStreamDone,
    this.defaultAnimationDuration = const Duration(milliseconds: 240),
    this.defaultAnimationCurve = Curves.easeInOut,
  });

  final Stream<dynamic> stream;
  final ElpianEngine? engine;
  final Map<String, dynamic>? initialStylesheet;
  final Widget? loadingWidget;
  final Widget Function(String error)? errorBuilder;
  final void Function(ElpianStreamCommand command)? onCommand;
  final VoidCallback? onStreamDone;
  final Duration defaultAnimationDuration;
  final Curve defaultAnimationCurve;

  @override
  State<ElpianStreamWidget> createState() => _ElpianStreamWidgetState();
}

class _ElpianStreamWidgetState extends State<ElpianStreamWidget> {
  late final ElpianEngine _engine;
  StreamSubscription<dynamic>? _subscription;

  Map<String, dynamic>? _currentView;
  String? _error;
  int _viewVersion = 0;
  Duration _activeAnimationDuration = Duration.zero;
  Curve _activeAnimationCurve = Curves.linear;

  @override
  void initState() {
    super.initState();
    _engine = widget.engine ?? ElpianEngine();
    if (widget.initialStylesheet != null) {
      _engine.loadStylesheet(widget.initialStylesheet!);
    }
    _listenToStream();
  }

  @override
  void didUpdateWidget(covariant ElpianStreamWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.stream, oldWidget.stream)) {
      _listenToStream();
    }
  }

  void _listenToStream() {
    _subscription?.cancel();
    _subscription = widget.stream.listen(
      _onMessage,
      onError: _onStreamError,
      onDone: () => widget.onStreamDone?.call(),
    );
  }

  void _onMessage(dynamic data) {
    try {
      final command = ElpianStreamCommand.fromDynamic(data);
      widget.onCommand?.call(command);
      _applyCommand(command);
      if (_error != null && mounted) {
        setState(() {
          _error = null;
        });
      }
    } catch (e) {
      _onStreamError(e);
    }
  }

  void _onStreamError(Object error) {
    if (!mounted) return;
    setState(() {
      _error = error.toString();
    });
  }

  void _applyCommand(ElpianStreamCommand command) {
    final animate = command.animate ?? false;
    final duration = command.animationDurationMs == null
        ? widget.defaultAnimationDuration
        : Duration(milliseconds: command.animationDurationMs!.clamp(0, 30000));
    final curve = _curveFromName(command.animationCurve) ?? widget.defaultAnimationCurve;

    switch (command.action) {
      case 'setView':
        if (command.view == null) {
          throw const FormatException('setView requires "view" object.');
        }
        _updateView(
          Map<String, dynamic>.from(command.view!),
          animate: animate,
          duration: duration,
          curve: curve,
        );
        return;

      case 'patchView':
        if (command.patch == null) {
          throw const FormatException('patchView requires "patch" object.');
        }
        if (_currentView == null) {
          throw StateError('patchView received before any setView command.');
        }
        _updateView(
          _deepMerge(
            Map<String, dynamic>.from(_currentView!),
            command.patch!,
          ),
          animate: animate,
          duration: duration,
          curve: curve,
        );
        return;

      case 'setStylesheet':
        if (command.stylesheet == null) {
          throw const FormatException('setStylesheet requires "stylesheet" object.');
        }
        _engine.loadStylesheet(command.stylesheet!);
        if (mounted) {
          setState(() {
            _activeAnimationDuration = animate ? duration : Duration.zero;
            _activeAnimationCurve = curve;
          });
        }
        return;

      case 'renderWithStylesheet':
        if (command.stylesheet == null || command.view == null) {
          throw const FormatException(
            'renderWithStylesheet requires both "stylesheet" and "view".',
          );
        }
        _engine.loadStylesheet(command.stylesheet!);
        _updateView(
          Map<String, dynamic>.from(command.view!),
          animate: animate,
          duration: duration,
          curve: curve,
        );
        return;

      case 'clear':
        setState(() {
          _currentView = null;
          _viewVersion++;
          _activeAnimationDuration = animate ? duration : Duration.zero;
          _activeAnimationCurve = curve;
        });
        return;

      default:
        throw FormatException('Unknown stream action: ${command.action}.');
    }
  }

  void _updateView(
    Map<String, dynamic> nextView, {
    required bool animate,
    required Duration duration,
    required Curve curve,
  }) {
    setState(() {
      _currentView = nextView;
      _viewVersion++;
      _activeAnimationDuration = animate ? duration : Duration.zero;
      _activeAnimationCurve = curve;
    });
  }

  Curve? _curveFromName(String? curveName) {
    if (curveName == null || curveName.trim().isEmpty) return null;
    switch (curveName.trim()) {
      case 'linear':
        return Curves.linear;
      case 'easeIn':
        return Curves.easeIn;
      case 'easeOut':
        return Curves.easeOut;
      case 'easeInOut':
        return Curves.easeInOut;
      case 'fastOutSlowIn':
        return Curves.fastOutSlowIn;
      case 'bounceIn':
        return Curves.bounceIn;
      case 'bounceOut':
        return Curves.bounceOut;
      default:
        return null;
    }
  }

  Map<String, dynamic> _deepMerge(
    Map<String, dynamic> base,
    Map<String, dynamic> patch,
  ) {
    final result = Map<String, dynamic>.from(base);

    for (final entry in patch.entries) {
      final key = entry.key;
      final patchValue = entry.value;
      final baseValue = result[key];

      if (patchValue is Map && baseValue is Map) {
        result[key] = _deepMerge(
          Map<String, dynamic>.from(baseValue),
          Map<String, dynamic>.from(patchValue),
        );
      } else {
        result[key] = patchValue;
      }
    }

    return result;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(_error!);
      }
      return Container(
        padding: const EdgeInsets.all(16),
        color: Colors.red.withOpacity(0.1),
        child: Text(
          'Stream Error: $_error',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }

    final view = _currentView;
    if (view == null) {
      return widget.loadingWidget ?? const SizedBox.shrink();
    }

    try {
      return AnimatedSwitcher(
        duration: _activeAnimationDuration,
        switchInCurve: _activeAnimationCurve,
        switchOutCurve: _activeAnimationCurve,
        child: KeyedSubtree(
          key: ValueKey(_viewVersion),
          child: _engine.renderFromJson(view),
        ),
      );
    } catch (e) {
      final message = 'Render Error: $e';
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(message);
      }
      return Container(
        padding: const EdgeInsets.all(16),
        color: Colors.orange.withOpacity(0.1),
        child: Text(
          message,
          style: const TextStyle(color: Colors.orange),
        ),
      );
    }
  }
}
