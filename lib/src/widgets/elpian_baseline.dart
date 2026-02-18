import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianBaseline {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    final baseline = node.props['baseline'] as double? ?? 0.0;
    
    return Baseline(
      baseline: baseline,
      baselineType: TextBaseline.alphabetic,
      child: child,
    );
  }
}
