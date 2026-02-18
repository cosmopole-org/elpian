import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianStaggeredAnimation {
  static Widget build(ElpianNode node, List<Widget> children) {
    return _ElpianStaggeredAnimationWidget(node: node, children: children);
  }
}

class _ElpianStaggeredAnimationWidget extends StatefulWidget {
  final ElpianNode node;
  final List<Widget> children;

  const _ElpianStaggeredAnimationWidget({
    required this.node,
    required this.children,
  });

  @override
  State<_ElpianStaggeredAnimationWidget> createState() =>
      _ElpianStaggeredAnimationWidgetState();
}

class _ElpianStaggeredAnimationWidgetState
    extends State<_ElpianStaggeredAnimationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();

    final totalDuration = widget.node.style?.animationDuration ??
        const Duration(milliseconds: 1000);

    _controller = AnimationController(
      duration: totalDuration,
      vsync: this,
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final staggerDelay = widget.node.style?.staggerDelay ??
        const Duration(milliseconds: 100);
    final curve = widget.node.style?.transitionCurve ?? Curves.easeOut;
    final childCount = widget.children.length;
    if (childCount == 0) return const SizedBox.shrink();

    final totalDelayMs = staggerDelay.inMilliseconds * (childCount - 1);
    final totalMs = _controller.duration!.inMilliseconds;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(childCount, (index) {
        final startFraction =
            (staggerDelay.inMilliseconds * index) / totalMs;
        final endFraction =
            ((staggerDelay.inMilliseconds * index) + (totalMs - totalDelayMs)) /
                totalMs;

        final animation = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _controller,
            curve: Interval(
              startFraction.clamp(0.0, 1.0),
              endFraction.clamp(0.0, 1.0),
              curve: curve,
            ),
          ),
        );

        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            return Opacity(
              opacity: animation.value.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, 20 * (1 - animation.value)),
                child: child,
              ),
            );
          },
          child: widget.children[index],
        );
      }),
    );
  }
}
