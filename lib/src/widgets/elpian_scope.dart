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
  late int _renderToken;
  late Widget _cachedChild;

  @override
  void initState() {
    super.initState();
    _renderToken = _readRenderToken(widget.node);
    _cachedChild = _buildChildren(widget.children);
  }

  @override
  void didUpdateWidget(covariant _ElpianScopeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextToken = _readRenderToken(widget.node);
    if (nextToken != _renderToken) {
      _renderToken = nextToken;
      _cachedChild = _buildChildren(widget.children);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _cachedChild;
  }

  int _readRenderToken(ElpianNode node) {
    final raw = node.props['__scopeRenderToken'];
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
