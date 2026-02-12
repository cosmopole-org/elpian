import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacBaseline {
  static Widget build(StacNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    final baseline = node.props['baseline'] as double? ?? 0.0;
    
    return Baseline(
      baseline: baseline,
      baselineType: TextBaseline.alphabetic,
      child: child,
    );
  }
}
