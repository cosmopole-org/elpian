import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacSizedBox {
  static Widget build(StacNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : null;
    
    return SizedBox(
      width: node.style?.width,
      height: node.style?.height,
      child: child,
    );
  }
}
