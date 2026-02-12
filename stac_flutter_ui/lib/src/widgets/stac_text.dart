import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';

class StacText {
  static Widget build(StacNode node, List<Widget> children) {
    final text = node.props['text'] as String? ?? node.props['data'] as String? ?? '';
    
    TextStyle? textStyle = node.props['style'] as TextStyle?;
    if (node.style != null) {
      textStyle = CSSProperties.createTextStyle(node.style);
    }

    Widget result = Text(
      text,
      style: textStyle,
      textAlign: node.props['textAlign'] as TextAlign? ?? node.style?.textAlign,
      maxLines: node.props['maxLines'] as int?,
      overflow: node.props['overflow'] as TextOverflow? ?? node.style?.textOverflow,
      softWrap: node.props['softWrap'] as bool?,
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
