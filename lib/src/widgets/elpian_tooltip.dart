import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianTooltip {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    final message = node.props['message'] as String? ?? '';
    
    return Tooltip(
      message: message,
      child: child,
    );
  }
}
