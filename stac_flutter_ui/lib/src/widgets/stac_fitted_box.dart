import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacFittedBox {
  static Widget build(StacNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    
    return FittedBox(
      fit: BoxFit.contain,
      alignment: node.style?.alignment ?? Alignment.center,
      child: child,
    );
  }
}
