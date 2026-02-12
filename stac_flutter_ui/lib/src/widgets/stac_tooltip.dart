import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacTooltip {
  static Widget build(StacNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    final message = node.props['message'] as String? ?? '';
    
    return Tooltip(
      message: message,
      child: child,
    );
  }
}
