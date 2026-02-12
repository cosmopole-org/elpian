import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacAnimatedGradient {
  static Widget build(StacNode node, List<Widget> children) {
    return _StacAnimatedGradientWidget(node: node, children: children);
  }
}

class _StacAnimatedGradientWidget extends StatefulWidget {
  final StacNode node;
  final List<Widget> children;

  const _StacAnimatedGradientWidget({
    required this.node,
    required this.children,
  });

  @override
  State<_StacAnimatedGradientWidget> createState() =>
      _StacAnimatedGradientWidgetState();
}

class _StacAnimatedGradientWidgetState
    extends State<_StacAnimatedGradientWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    final duration = widget.node.style?.animationDuration ??
        const Duration(milliseconds: 2000);

    _controller = AnimationController(
      duration: duration,
      vsync: this,
    );

    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.linear),
    );

    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.children.isNotEmpty ? widget.children.first : null;
    final colors = widget.node.style?.gradientColors ??
        [Colors.blue, Colors.purple, Colors.pink, Colors.blue];
    final borderRadius = widget.node.style?.borderRadius;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, childWidget) {
        final shift = _animation.value;
        final shiftedStops = List.generate(
          colors.length,
          (i) => ((i / (colors.length - 1)) + shift) % 1.0,
        );
        shiftedStops.sort();

        return Container(
          width: widget.node.style?.width,
          height: widget.node.style?.height,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
              stops: shiftedStops,
            ),
          ),
          child: childWidget,
        );
      },
      child: child,
    );
  }
}
