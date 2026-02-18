import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacAnimatedSwitcher {
  static Widget build(StacNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : null;
    final duration =
        node.style?.transitionDuration ?? const Duration(milliseconds: 300);
    final transitionType = node.props['transitionType'] as String? ?? 'fade';

    return AnimatedSwitcher(
      duration: duration,
      transitionBuilder: _buildTransition(transitionType),
      child: child,
    );
  }

  static AnimatedSwitcherTransitionBuilder _buildTransition(String type) {
    switch (type) {
      case 'scale':
        return (Widget child, Animation<double> animation) {
          return ScaleTransition(scale: animation, child: child);
        };
      case 'rotation':
        return (Widget child, Animation<double> animation) {
          return RotationTransition(turns: animation, child: child);
        };
      case 'slide':
        return (Widget child, Animation<double> animation) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          );
        };
      case 'fade':
      default:
        return (Widget child, Animation<double> animation) {
          return FadeTransition(opacity: animation, child: child);
        };
    }
  }
}
