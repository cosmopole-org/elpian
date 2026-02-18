import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianIndexedStack {
  static Widget build(ElpianNode node, List<Widget> children) {
    final index = node.props['index'] as int? ?? 0;
    
    return IndexedStack(
      index: index,
      children: children,
    );
  }
}
