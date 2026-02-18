import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacAlign {
  static Widget build(StacNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    final alignment = node.style?.alignment ?? Alignment.center;
    
    return Align(
      alignment: alignment,
      child: child,
    );
  }
}
