import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../core/elpian_services.dart';
import '../css/css_properties.dart';

class HtmlTextarea {
  static Widget build(ElpianNode node, List<Widget> children) {
    // Captured while the engine's service scope is active: the handlers
    // run later, outside it.
    final dispatcher = ElpianServices.current.events;
    final placeholder = node.props['placeholder'] as String? ?? '';
    final elementId = node.key ?? 'element_${node.hashCode}';

    Widget result = TextField(
      maxLines: 5,
      decoration: InputDecoration(
        hintText: placeholder,
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) {
        dispatcher.dispatchInput(elementId, value);
      },
      onSubmitted: (value) {
        dispatcher.dispatchSubmit(elementId);
      },
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
