import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianSpacer {
  static Widget build(ElpianNode node, List<Widget> children) {
    final flex = node.props['flex'] as int? ?? 1;
    
    return Spacer(flex: flex);
  }
}
