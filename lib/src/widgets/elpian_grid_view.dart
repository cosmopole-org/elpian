import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianGridView {
  static Widget build(ElpianNode node, List<Widget> children) {
    final crossAxisCount = node.props['crossAxisCount'] as int? ?? 2;
    
    return GridView.count(
      crossAxisCount: crossAxisCount,
      shrinkWrap: true,
      children: children,
    );
  }
}
