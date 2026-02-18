import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacFadeTransition {
  static Widget build(StacNode node, List<Widget> children) {
    return _StacFadeTransitionWidget(node: node, children: children);
  }
}

class _StacFadeTransitionWidget extends StatefulWidget {
  final StacNode node;
  final List<Widget> children;

  const _StacFadeTransitionWidget({
    required this.node,
    required this.children,
  });

  @override
  State<_StacFadeTransitionWidget> createState() =>
      _StacFadeTransitionWidgetState();
}

class _StacFadeTransitionWidgetState extends State<_StacFadeTransitionWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    final duration = widget.node.style?.animationDuration ??
        widget.node.style?.transitionDuration ??
        const Duration(milliseconds: 300);
    final curve =
        widget.node.style?.transitionCurve ?? Curves.linear;

    _controller = AnimationController(
      duration: duration,
      vsync: this,
    );

    final begin = widget.node.style?.fadeBegin ?? 0.0;
    final end = widget.node.style?.fadeEnd ?? 1.0;

    _animation = Tween<double>(begin: begin, end: end).animate(
      CurvedAnimation(parent: _controller, curve: curve),
    );

    final repeat = widget.node.style?.animationRepeat ?? false;
    final autoReverse = widget.node.style?.animationAutoReverse ?? false;

    if (repeat) {
      _controller.repeat(reverse: autoReverse);
    } else if (autoReverse) {
      _controller.forward().then((_) => _controller.reverse());
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child =
        widget.children.isNotEmpty ? widget.children.first : const SizedBox();

    return FadeTransition(
      opacity: _animation,
      child: child,
    );
  }
}
