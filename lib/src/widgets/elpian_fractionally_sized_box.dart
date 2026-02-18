import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianFractionallySizedBox {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : null;
    
    return FractionallySizedBox(
      widthFactor: node.props['widthFactor'] as double?,
      heightFactor: node.props['heightFactor'] as double?,
      alignment: node.style?.alignment ?? Alignment.center,
      child: child,
    );
  }
}
