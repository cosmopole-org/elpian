import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';

class HtmlInput {
  static Widget build(StacNode node, List<Widget> children) {
    final type = node.props['type'] as String? ?? 'text';
    final placeholder = node.props['placeholder'] as String? ?? '';
    
    Widget result;
    
    if (type == 'checkbox') {
      result = Checkbox(value: false, onChanged: (_) {});
    } else if (type == 'radio') {
      result = Radio(value: false, groupValue: null, onChanged: (_) {});
    } else {
      result = TextField(
        decoration: InputDecoration(
          hintText: placeholder,
          border: const OutlineInputBorder(),
        ),
      );
    }

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
