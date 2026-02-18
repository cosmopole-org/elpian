import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacLimitedBox {
  static Widget build(StacNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    
    return LimitedBox(
      maxWidth: node.style?.maxWidth ?? double.infinity,
      maxHeight: node.style?.maxHeight ?? double.infinity,
      child: child,
    );
  }
}
