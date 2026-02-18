import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class HtmlProgress {
  static Widget build(ElpianNode node, List<Widget> children) {
    final value = (node.props['value'] as num?)?.toDouble();
    final max = (node.props['max'] as num?)?.toDouble() ?? 1.0;
    
    return LinearProgressIndicator(
      value: value != null ? value / max : null,
      backgroundColor: Colors.grey[200],
    );
  }
}
