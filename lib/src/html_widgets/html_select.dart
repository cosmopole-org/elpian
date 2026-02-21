import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';
import '../core/event_dispatcher.dart';

class HtmlSelect {
  static Widget build(ElpianNode node, List<Widget> children) {
    final elementId = node.key ?? 'element_${node.hashCode}';

    Widget result = DropdownButton<String>(
      items: const [],
      onChanged: (newValue) {
        final dispatcher = EventDispatcher();
        dispatcher.dispatchChange(elementId, newValue);
      },
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
