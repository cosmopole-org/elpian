import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianChip {
  static Widget build(ElpianNode node, List<Widget> children) {
    final label = node.props['label'] as String? ?? '';
    
    return Chip(
      label: Text(label),
      backgroundColor: node.style?.backgroundColor,
    );
  }
}
