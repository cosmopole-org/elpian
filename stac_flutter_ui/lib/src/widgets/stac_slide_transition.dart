import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacSlideTransition {
  static Widget build(StacNode node, List<Widget> children) {
    return _StacSlideTransitionWidget(node: node, children: children);
  }
}

class _StacSlideTransitionWidget extends StatefulWidget {
  final StacNode node;
  final List<Widget> children;

  const _StacSlideTransitionWidget({
    required this.node,
    required this.children,
  });

  @override
  State<_StacSlideTransitionWidget> createState() =>
      _StacSlideTransitionWidgetState();
}

class _StacSlideTransitionWidgetState extends State<_StacSlideTransitionWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _animation;

  @override
  void initState() {
    super.initState();

    final duration = widget.node.style?.animationDuration ??
        widget.node.style?.transitionDuration ??
        const Duration(milliseconds: 300);
    final curve = widget.node.style?.transitionCurve ?? Curves.linear;

    _controller = AnimationController(
      duration: duration,
      vsync: this,
    );

    final begin = widget.node.style?.slideBegin ?? const Offset(-1.0, 0.0);
    final end = widget.node.style?.slideEnd ?? Offset.zero;

    _animation = Tween<Offset>(begin: begin, end: end).animate(
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

    return SlideTransition(
      position: _animation,
      child: child,
    );
  }
}
