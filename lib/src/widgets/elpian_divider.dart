import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianDivider {
  static Widget build(ElpianNode node, List<Widget> children) {
    return Divider(
      color: node.style?.borderColor,
      thickness: node.style?.borderWidth,
      height: node.style?.height,
    );
  }
}
