import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacPadding {
  static Widget build(StacNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    final padding = node.style?.padding ?? const EdgeInsets.all(8.0);
    
    return Padding(
      padding: padding,
      child: child,
    );
  }
}
