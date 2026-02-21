import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../core/event_dispatcher.dart';

class ElpianSlider {
  static Widget build(ElpianNode node, List<Widget> children) {
    final value = (node.props['value'] as num?)?.toDouble() ?? 0.5;
    final min = (node.props['min'] as num?)?.toDouble() ?? 0.0;
    final max = (node.props['max'] as num?)?.toDouble() ?? 1.0;
    final elementId = node.key ?? 'element_${node.hashCode}';

    return Slider(
      value: value,
      min: min,
      max: max,
      onChanged: (newValue) {
        final dispatcher = EventDispatcher();
        dispatcher.dispatchChange(elementId, newValue);
      },
    );
  }
}
