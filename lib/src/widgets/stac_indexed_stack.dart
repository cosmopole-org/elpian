import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacIndexedStack {
  static Widget build(StacNode node, List<Widget> children) {
    final index = node.props['index'] as int? ?? 0;
    
    return IndexedStack(
      index: index,
      children: children,
    );
  }
}
