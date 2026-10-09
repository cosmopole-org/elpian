import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../core/elpian_services.dart';

class ElpianSwitch {
  static Widget build(ElpianNode node, List<Widget> children) {
    final value = node.props['value'] as bool? ?? false;
    final elementId = node.key ?? 'element_${node.hashCode}';

    return Switch(
      value: value,
      onChanged: (newValue) {
        final dispatcher = ElpianServices.current.events;
        dispatcher.dispatchChange(elementId, newValue);
      },
    );
  }
}
