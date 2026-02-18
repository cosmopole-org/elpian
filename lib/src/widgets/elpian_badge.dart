import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianBadge {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    final label = node.props['label'] as String? ?? '';
    
    return Badge(
      label: Text(label),
      child: child,
    );
  }
}
