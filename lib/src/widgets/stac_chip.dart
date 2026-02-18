import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacChip {
  static Widget build(StacNode node, List<Widget> children) {
    final label = node.props['label'] as String? ?? '';
    
    return Chip(
      label: Text(label),
      backgroundColor: node.style?.backgroundColor,
    );
  }
}
