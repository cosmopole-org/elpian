import 'package:flutter/material.dart';

import '../models/elpian_node.dart';

class ElpianScope {
  static Widget build(ElpianNode node, List<Widget> children) {
    return _ElpianScopeWidget(node: node, children: children);
  }
}

class _ElpianScopeWidget extends StatefulWidget {
  final ElpianNode node;
  final List<Widget> children;

  const _ElpianScopeWidget({
    required this.node,
    required this.children,
  });

  @override
  State<_ElpianScopeWidget> createState() => _ElpianScopeWidgetState();
}

class _ElpianScopeWidgetState extends State<_ElpianScopeWidget> {
  late int _version;
  late Widget _cachedChild;

  @override
  void initState() {
    super.initState();
    _version = _readVersion(widget.node);
    _cachedChild = _buildChildren(widget.children);
  }

  @override
  void didUpdateWidget(covariant _ElpianScopeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextVersion = _readVersion(widget.node);
    if (nextVersion > _version) {
      setState(() {
        _version = nextVersion;
        _cachedChild = _buildChildren(widget.children);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _cachedChild;
  }

  int _readVersion(ElpianNode node) {
    final raw = node.props['version'] ?? node.props['rev'] ?? node.props['scopeVersion'];
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }

  Widget _buildChildren(List<Widget> children) {
    if (children.isEmpty) return const SizedBox.shrink();
    if (children.length == 1) return children.first;
    return Column(children: children);
  }
}
