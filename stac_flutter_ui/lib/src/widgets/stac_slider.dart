import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacSlider {
  static Widget build(StacNode node, List<Widget> children) {
    final value = (node.props['value'] as num?)?.toDouble() ?? 0.5;
    final min = (node.props['min'] as num?)?.toDouble() ?? 0.0;
    final max = (node.props['max'] as num?)?.toDouble() ?? 1.0;
    
    return Slider(
      value: value,
      min: min,
      max: max,
      onChanged: (_) {},
    );
  }
}
