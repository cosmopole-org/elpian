import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianAlign {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    final alignment = node.style?.alignment ?? Alignment.center;
    
    return Align(
      alignment: alignment,
      child: child,
    );
  }
}
