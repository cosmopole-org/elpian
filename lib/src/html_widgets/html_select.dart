import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

class HtmlSelect {
  static Widget build(ElpianNode node, List<Widget> children) {
    Widget result = DropdownButton<String>(
      items: const [],
      onChanged: (_) {},
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
