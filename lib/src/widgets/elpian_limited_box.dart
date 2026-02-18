import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianLimitedBox {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    
    return LimitedBox(
      maxWidth: node.style?.maxWidth ?? double.infinity,
      maxHeight: node.style?.maxHeight ?? double.infinity,
      child: child,
    );
  }
}
