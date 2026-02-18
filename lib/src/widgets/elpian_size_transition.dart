import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianSizeTransition {
  static Widget build(ElpianNode node, List<Widget> children) {
    return _ElpianSizeTransitionWidget(node: node, children: children);
  }
}

class _ElpianSizeTransitionWidget extends StatefulWidget {
  final ElpianNode node;
  final List<Widget> children;

  const _ElpianSizeTransitionWidget({
    required this.node,
    required this.children,
  });

  @override
  State<_ElpianSizeTransitionWidget> createState() =>
      _ElpianSizeTransitionWidgetState();
}

class _ElpianSizeTransitionWidgetState extends State<_ElpianSizeTransitionWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

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

    final begin = widget.node.style?.animationFrom ?? 0.0;
    final end = widget.node.style?.animationTo ?? 1.0;

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
    final axis = widget.node.props['axis'] as String?;

    return SizeTransition(
      sizeFactor: _animation,
      axis: axis == 'horizontal' ? Axis.horizontal : Axis.vertical,
      child: child,
    );
  }
}
