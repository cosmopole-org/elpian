import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacLinearProgressIndicator {
  static Widget build(StacNode node, List<Widget> children) {
    return LinearProgressIndicator(
      value: node.props['value'] as double?,
      backgroundColor: node.style?.backgroundColor,
      color: node.style?.color,
    );
  }
}
