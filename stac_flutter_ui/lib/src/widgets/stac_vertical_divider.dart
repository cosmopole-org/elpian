import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacVerticalDivider {
  static Widget build(StacNode node, List<Widget> children) {
    return VerticalDivider(
      color: node.style?.borderColor,
      thickness: node.style?.borderWidth,
      width: node.style?.width,
    );
  }
}
