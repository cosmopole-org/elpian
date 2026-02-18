import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacBadge {
  static Widget build(StacNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    final label = node.props['label'] as String? ?? '';
    
    return Badge(
      label: Text(label),
      child: child,
    );
  }
}
