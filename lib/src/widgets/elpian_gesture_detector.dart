import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianGestureDetector {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    
    return GestureDetector(
      onTap: () {},
      onDoubleTap: () {},
      onLongPress: () {},
      child: child,
    );
  }
}
