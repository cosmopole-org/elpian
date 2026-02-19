import 'package:flutter/material.dart';
import '../core/event_dispatcher.dart';
import '../core/event_system.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

class ElpianTextField {
  static Widget build(ElpianNode node, List<Widget> children) {
    final hint = node.props['hint'] as String? ?? '';
    final hasChangeEvent =
        node.events != null && node.events!.containsKey('change');
    final hasInputEvent =
        node.events != null && node.events!.containsKey('input');
    final elementId = node.key ?? 'element_${node.hashCode}';

    Widget result = TextField(
      decoration: InputDecoration(hintText: hint),
      onChanged: (hasChangeEvent || hasInputEvent)
          ? (value) {
              final dispatcher = EventDispatcher();
              if (hasChangeEvent) {
                dispatcher.dispatchChange(elementId, value);
              }
              if (hasInputEvent) {
                dispatcher.dispatchInput(elementId, value);
              }
            }
          : null,
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
