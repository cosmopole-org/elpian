import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianPadding {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    final padding = node.style?.padding ?? const EdgeInsets.all(8.0);
    
    return Padding(
      padding: padding,
      child: child,
    );
  }
}
