import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacConstrainedBox {
  static Widget build(StacNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: node.style?.minWidth ?? 0.0,
        maxWidth: node.style?.maxWidth ?? double.infinity,
        minHeight: node.style?.minHeight ?? 0.0,
        maxHeight: node.style?.maxHeight ?? double.infinity,
      ),
      child: child,
    );
  }
}
