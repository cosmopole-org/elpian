import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacGridView {
  static Widget build(StacNode node, List<Widget> children) {
    final crossAxisCount = node.props['crossAxisCount'] as int? ?? 2;
    
    return GridView.count(
      crossAxisCount: crossAxisCount,
      shrinkWrap: true,
      children: children,
    );
  }
}
