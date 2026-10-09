import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianLinearProgressIndicator {
  static Widget build(ElpianNode node, List<Widget> children) {
    return LinearProgressIndicator(
      value: node.props['value'] as double?,
      backgroundColor: node.style?.backgroundColor,
      color: node.style?.color,
    );
  }
}
