import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../core/event_dispatcher.dart';

class ElpianRadio {
  static Widget build(ElpianNode node, List<Widget> children) {
    final value = node.props['value'];
    final groupValue = node.props['groupValue'];
    final elementId = node.key ?? 'element_${node.hashCode}';

    return Radio(
      value: value,
      groupValue: groupValue,
      onChanged: (newValue) {
        final dispatcher = EventDispatcher();
        dispatcher.dispatchChange(elementId, newValue);
      },
    );
  }
}
