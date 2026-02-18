import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';
import '../models/css_style.dart';

class HtmlBlockquote {
  static Widget build(ElpianNode node, List<Widget> children) {
    final text = node.props['text'] as String? ?? '';
    final child = children.isNotEmpty ? children.first : Text(text);
    
    final defaultStyle = const CSSStyle(
      padding: EdgeInsets.all(16.0),
      margin: EdgeInsets.symmetric(vertical: 8.0),
      borderColor: Colors.grey,
      borderWidth: 4.0,
    );
    final mergedStyle = node.style ?? defaultStyle;
    
    Widget result = Container(
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Colors.grey, width: 4)),
      ),
      padding: const EdgeInsets.all(16.0),
      child: child,
    );

    result = CSSProperties.applyStyle(result, mergedStyle);
  
    return result;
  }
}
