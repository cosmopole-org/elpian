import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

class HtmlPicture {
  static Widget build(ElpianNode node, List<Widget> children) {
    // Get the first image child
    Widget result = children.isNotEmpty ? children.first : Container();

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
