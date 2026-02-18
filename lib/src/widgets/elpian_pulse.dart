import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianPulse {
  static Widget build(ElpianNode node, List<Widget> children) {
    return _ElpianPulseWidget(node: node, children: children);
  }
}

class _ElpianPulseWidget extends StatefulWidget {
  final ElpianNode node;
  final List<Widget> children;

  const _ElpianPulseWidget({
    required this.node,
    required this.children,
  });

  @override
  State<_ElpianPulseWidget> createState() => _ElpianPulseWidgetState();
}

class _ElpianPulseWidgetState extends State<_ElpianPulseWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    final duration = widget.node.style?.animationDuration ??
        const Duration(milliseconds: 1000);
    final curve = widget.node.style?.transitionCurve ?? Curves.easeInOut;

    _controller = AnimationController(
      duration: duration,
      vsync: this,
    );

    final scaleBegin = widget.node.style?.scaleBegin ?? 1.0;
    final scaleEnd = widget.node.style?.scaleEnd ?? 1.05;

    _animation = Tween<double>(begin: scaleBegin, end: scaleEnd).animate(
      CurvedAnimation(parent: _controller, curve: curve),
    );

    _controller.repeat(reverse: true);
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

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, childWidget) {
        return Transform.scale(
          scale: _animation.value,
          child: childWidget,
        );
      },
      child: child,
    );
  }
}
