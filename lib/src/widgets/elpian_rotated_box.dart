import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianRotatedBox {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    final quarterTurns = node.props['quarterTurns'] as int? ?? 0;
    
    return RotatedBox(
      quarterTurns: quarterTurns,
      child: child,
    );
  }
}
