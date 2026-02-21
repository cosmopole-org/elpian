import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';
import '../core/event_dispatcher.dart';

class ElpianTextField {
  static Widget build(ElpianNode node, List<Widget> children) {
    final hint = node.props['hint'] as String? ?? '';
    final elementId = node.key ?? 'element_${node.hashCode}';

    Widget result = TextField(
      decoration: InputDecoration(hintText: hint),
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
