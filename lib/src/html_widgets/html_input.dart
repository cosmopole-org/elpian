import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';
import '../core/event_dispatcher.dart';

/// An `<input>` element (text / number / password / checkbox / radio).
///
/// Stateful so a text field keeps its own edit state (seeded once from
/// `props.value`) and a checkbox keeps its toggle — the page never re-renders
/// mid-edit. On change it dispatches `input` (text) / `change` (checkbox/radio)
/// carrying the value, which the host forwards to the node's
/// `events.input`/`events.change` handler in the page VM (see
/// NextjsServerWidget._routeEvent / _eventToHostJson) so client-driven forms can
/// read what the user typed or chose.
class HtmlInput extends StatefulWidget {
  const HtmlInput({super.key, required this.node, required this.children});

  final ElpianNode node;
  final List<Widget> children;

  static Widget build(ElpianNode node, List<Widget> children) {
    return HtmlInput(
      key: node.key != null ? ValueKey<String>('input_${node.key}') : null,
      node: node,
      children: children,
    );
  }

  @override
  State<HtmlInput> createState() => _HtmlInputState();
}

class _HtmlInputState extends State<HtmlInput> {
  TextEditingController? _controller;
  bool _checked = false;

  String get _elementId => widget.node.key ?? 'element_${widget.node.hashCode}';
  String get _type => widget.node.props['type'] as String? ?? 'text';

  @override
  void initState() {
    super.initState();
    if (_type == 'checkbox') {
      _checked = widget.node.props['checked'] as bool? ?? false;
    } else if (_type != 'radio') {
      _controller = TextEditingController(
        text: widget.node.props['value']?.toString() ?? '',
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final placeholder = node.props['placeholder'] as String? ?? '';
    Widget result;

    if (_type == 'checkbox') {
      result = Checkbox(
        value: _checked,
        onChanged: (newValue) {
          setState(() => _checked = newValue ?? false);
          EventDispatcher().dispatchChange(_elementId, _checked);
        },
      );
    } else if (_type == 'radio') {
      final Object? value = node.props['value'];
      final Object? groupValue = node.props['groupValue'];
      // groupValue/onChanged moved to a RadioGroup ancestor in Flutter 3.32+.
      result = RadioGroup<Object?>(
        groupValue: groupValue,
        onChanged: (newValue) {
          EventDispatcher().dispatchChange(_elementId, newValue);
        },
        child: Radio<Object?>(value: value),
      );
    } else {
      const textColor = Color(0xFFF7EEDC);
      const fieldFill = Color(0xFF0A1626);
      const fieldBorder = Color(0xFF1C3450);
      const fieldBorderFocus = Color(0xFFD6B36A);
      result = TextField(
        controller: _controller,
        keyboardType:
            _type == 'number' ? TextInputType.number : TextInputType.text,
        obscureText: _type == 'password',
        style: const TextStyle(color: textColor, fontSize: 13),
        decoration: InputDecoration(
          hintText: placeholder,
          hintStyle: const TextStyle(color: Color(0xFF6B7E92), fontSize: 13),
          isDense: true,
          filled: true,
          fillColor: fieldFill,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: fieldBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: fieldBorderFocus),
          ),
        ),
        onChanged: (value) => EventDispatcher().dispatchInput(_elementId, value),
        onSubmitted: (value) => EventDispatcher().dispatchSubmit(_elementId),
      );
    }

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }
    return result;
  }
}
