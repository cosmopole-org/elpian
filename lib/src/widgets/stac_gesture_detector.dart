import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacGestureDetector {
  static Widget build(StacNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    
    return GestureDetector(
      onTap: () {},
      onDoubleTap: () {},
      onLongPress: () {},
      child: child,
    );
  }
}
