import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianVerticalDivider {
  static Widget build(ElpianNode node, List<Widget> children) {
    return VerticalDivider(
      color: node.style?.borderColor,
      thickness: node.style?.borderWidth,
      width: node.style?.width,
    );
  }
}
