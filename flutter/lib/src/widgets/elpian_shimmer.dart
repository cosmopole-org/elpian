import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianShimmer {
  static Widget build(ElpianNode node, List<Widget> children) {
    return _ElpianShimmerWidget(node: node, children: children);
  }
}

class _ElpianShimmerWidget extends StatefulWidget {
  final ElpianNode node;
  final List<Widget> children;

  const _ElpianShimmerWidget({
    required this.node,
    required this.children,
  });

  @override
  State<_ElpianShimmerWidget> createState() => _ElpianShimmerWidgetState();
}

class _ElpianShimmerWidgetState extends State<_ElpianShimmerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    final duration = widget.node.style?.animationDuration ??
        const Duration(milliseconds: 1500);

    _controller = AnimationController(
      duration: duration,
      vsync: this,
    );

    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
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
    final style = widget.node.style;
    final baseColor = style?.shimmerBaseColor ?? const Color(0xFFE0E0E0);
    final highlightColor =
        style?.shimmerHighlightColor ?? const Color(0xFFF5F5F5);

    // The shimmer gradient is painted with `srcATop`, i.e. only where the
    // child is already opaque. The skeleton placeholder must therefore be
    // filled (with the base colour) — an undecorated box is transparent and
    // the shimmer would paint nothing at all.
    final child = widget.children.isNotEmpty
        ? (widget.children.length == 1
            ? widget.children.first
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.children,
              ))
        : Container(
            width: style?.width ?? 200,
            height: style?.height ?? 20,
            margin: style?.margin,
            decoration: BoxDecoration(
              color: style?.backgroundColor ?? baseColor,
              borderRadius: style?.borderRadius ?? BorderRadius.circular(4),
            ),
          );

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, childWidget) {
        final t = _animation.value;
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [baseColor, highlightColor, baseColor],
              stops: [
                (t - 0.3).clamp(0.0, 1.0),
                t.clamp(0.0, 1.0),
                (t + 0.3).clamp(0.0, 1.0),
              ],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: childWidget,
        );
      },
      child: child,
    );
  }
}
