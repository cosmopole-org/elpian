import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class HtmlMeter {
  static Widget build(ElpianNode node, List<Widget> children) {
    final value = (node.props['value'] as num?)?.toDouble() ?? 0.5;
    final min = (node.props['min'] as num?)?.toDouble() ?? 0.0;
    final max = (node.props['max'] as num?)?.toDouble() ?? 1.0;
    
    final normalized = (value - min) / (max - min);
    
    return LinearProgressIndicator(
      value: normalized,
      backgroundColor: Colors.grey[200],
      valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
    );
  }
}
