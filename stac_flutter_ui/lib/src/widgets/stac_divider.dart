import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacDivider {
  static Widget build(StacNode node, List<Widget> children) {
    return Divider(
      color: node.style?.borderColor,
      thickness: node.style?.borderWidth,
      height: node.style?.height,
    );
  }
}
