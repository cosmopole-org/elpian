import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacRotatedBox {
  static Widget build(StacNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    final quarterTurns = node.props['quarterTurns'] as int? ?? 0;
    
    return RotatedBox(
      quarterTurns: quarterTurns,
      child: child,
    );
  }
}
