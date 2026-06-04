import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../core/event_dispatcher.dart';

class ElpianRadio {
  static Widget build(ElpianNode node, List<Widget> children) {
    final Object? value = node.props['value'];
    final Object? groupValue = node.props['groupValue'];
    final elementId = node.key ?? 'element_${node.hashCode}';

    // Flutter 3.32+ moved groupValue/onChanged off Radio onto a RadioGroup
    // ancestor. Each Elpian radio is its own group carrying the supplied
    // groupValue and dispatching change events, so wrap it in a RadioGroup.
    return RadioGroup<Object?>(
      groupValue: groupValue,
      onChanged: (newValue) {
        final dispatcher = EventDispatcher();
        dispatcher.dispatchChange(elementId, newValue);
      },
      child: Radio<Object?>(value: value),
    );
  }
}
