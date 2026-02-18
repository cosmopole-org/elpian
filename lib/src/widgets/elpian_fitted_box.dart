import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianFittedBox {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    
    return FittedBox(
      fit: BoxFit.contain,
      alignment: node.style?.alignment ?? Alignment.center,
      child: child,
    );
  }
}
