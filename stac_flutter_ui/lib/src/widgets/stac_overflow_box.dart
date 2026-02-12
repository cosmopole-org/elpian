import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacOverflowBox {
  static Widget build(StacNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    
    return OverflowBox(
      alignment: node.style?.alignment ?? Alignment.center,
      minWidth: node.style?.minWidth,
      maxWidth: node.style?.maxWidth,
      minHeight: node.style?.minHeight,
      maxHeight: node.style?.maxHeight,
      child: child,
    );
  }
}
