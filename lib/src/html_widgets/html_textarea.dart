import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';
import '../core/event_dispatcher.dart';

class HtmlTextarea {
  static Widget build(ElpianNode node, List<Widget> children) {
    final placeholder = node.props['placeholder'] as String? ?? '';
    final elementId = node.key ?? 'element_${node.hashCode}';

    Widget result = TextField(
      maxLines: 5,
      decoration: InputDecoration(
        hintText: placeholder,
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) {
        final dispatcher = EventDispatcher();
        dispatcher.dispatchInput(elementId, value);
      },
      onSubmitted: (value) {
        final dispatcher = EventDispatcher();
        dispatcher.dispatchSubmit(elementId);
      },
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
