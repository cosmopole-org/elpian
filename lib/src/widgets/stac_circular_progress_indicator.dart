import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacCircularProgressIndicator {
  static Widget build(StacNode node, List<Widget> children) {
    return CircularProgressIndicator(
      value: node.props['value'] as double?,
      backgroundColor: node.style?.backgroundColor,
      color: node.style?.color,
      strokeWidth: node.style?.borderWidth ?? 4.0,
    );
  }
}
