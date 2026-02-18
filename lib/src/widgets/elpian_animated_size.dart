import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianAnimatedSize {
  static Widget build(ElpianNode node, List<Widget> children) {
    return _ElpianAnimatedSizeWidget(node: node, children: children);
  }
}

class _ElpianAnimatedSizeWidget extends StatefulWidget {
  final ElpianNode node;
  final List<Widget> children;

  const _ElpianAnimatedSizeWidget({
    required this.node,
    required this.children,
  });

  @override
  State<_ElpianAnimatedSizeWidget> createState() =>
      _ElpianAnimatedSizeWidgetState();
}

class _ElpianAnimatedSizeWidgetState extends State<_ElpianAnimatedSizeWidget>
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
