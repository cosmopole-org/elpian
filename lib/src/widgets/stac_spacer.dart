import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacSpacer {
  static Widget build(StacNode node, List<Widget> children) {
    final flex = node.props['flex'] as int? ?? 1;
    
    return Spacer(flex: flex);
  }
}
