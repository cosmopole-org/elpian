import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../core/event_dispatcher.dart';

class ElpianCheckbox {
  static Widget build(ElpianNode node, List<Widget> children) {
    final value = node.props['value'] as bool? ?? false;
    final elementId = node.key ?? 'element_${node.hashCode}';

    return Checkbox(
      value: value,
      onChanged: (newValue) {
        final dispatcher = EventDispatcher();
        dispatcher.dispatchChange(elementId, newValue);
      },
    );
  }
}
