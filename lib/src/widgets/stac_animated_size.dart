import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacAnimatedSize {
  static Widget build(StacNode node, List<Widget> children) {
    return _StacAnimatedSizeWidget(node: node, children: children);
  }
}

class _StacAnimatedSizeWidget extends StatefulWidget {
  final StacNode node;
  final List<Widget> children;

  const _StacAnimatedSizeWidget({
    required this.node,
    required this.children,
  });

  @override
  State<_StacAnimatedSizeWidget> createState() =>
      _StacAnimatedSizeWidgetState();
}

class _StacAnimatedSizeWidgetState extends State<_StacAnimatedSizeWidget>
    with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    final child = widget.children.isNotEmpty
        ? widget.children.first
        : const SizedBox.shrink();
    final duration = widget.node.style?.transitionDuration ??
        const Duration(milliseconds: 300);
    final curve = widget.node.style?.transitionCurve ?? Curves.linear;

    return AnimatedSize(
      duration: duration,
      curve: curve,
      child: child,
    );
  }
}
