import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacDecoratedBox {
  static Widget build(StacNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    
    return DecoratedBox(
      decoration: BoxDecoration(
        color: node.style?.backgroundColor,
        gradient: node.style?.gradient,
        border: node.style?.border,
        borderRadius: node.style?.borderRadius,
        boxShadow: node.style?.boxShadow,
      ),
      child: child,
    );
  }
}
