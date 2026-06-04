import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';
import '../core/event_dispatcher.dart';

class HtmlInput {
  static Widget build(ElpianNode node, List<Widget> children) {
    final type = node.props['type'] as String? ?? 'text';
    final placeholder = node.props['placeholder'] as String? ?? '';
    final elementId = node.key ?? 'element_${node.hashCode}';

    Widget result;

    if (type == 'checkbox') {
      final value = node.props['checked'] as bool? ?? false;
      result = Checkbox(
        value: value,
        onChanged: (newValue) {
          final dispatcher = EventDispatcher();
          dispatcher.dispatchChange(elementId, newValue);
        },
      );
    } else if (type == 'radio') {
      final Object? value = node.props['value'];
      final Object? groupValue = node.props['groupValue'];
      // groupValue/onChanged moved to a RadioGroup ancestor in Flutter 3.32+.
      result = RadioGroup<Object?>(
        groupValue: groupValue,
        onChanged: (newValue) {
          final dispatcher = EventDispatcher();
          dispatcher.dispatchChange(elementId, newValue);
        },
        child: Radio<Object?>(value: value),
      );
    } else {
      result = TextField(
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
    }

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
