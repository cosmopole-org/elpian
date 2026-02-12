import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';

class StacButton {
  static Widget build(StacNode node, List<Widget> children) {
    final text = node.props['text'] as String? ?? 'Button';
    final child = children.isNotEmpty ? children.first : Text(text);
    
    Widget result = ElevatedButton(
      onPressed: () {},
      style: ButtonStyle(
        backgroundColor: node.style?.backgroundColor != null 
          ? WidgetStateProperty.all(node.style!.backgroundColor)
          : null,
      ),
      child: child,
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
