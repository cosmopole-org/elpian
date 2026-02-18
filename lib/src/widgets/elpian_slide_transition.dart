import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianSlideTransition {
  static Widget build(ElpianNode node, List<Widget> children) {
    return _ElpianSlideTransitionWidget(node: node, children: children);
  }
}

class _ElpianSlideTransitionWidget extends StatefulWidget {
  final ElpianNode node;
  final List<Widget> children;

  const _ElpianSlideTransitionWidget({
    required this.node,
    required this.children,
  });

  @override
  State<_ElpianSlideTransitionWidget> createState() =>
      _ElpianSlideTransitionWidgetState();
}

class _ElpianSlideTransitionWidgetState extends State<_ElpianSlideTransitionWidget>
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
