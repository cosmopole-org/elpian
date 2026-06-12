import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';
import '../core/event_dispatcher.dart';

/// A `<select>` dropdown.
///
/// Options come from either `props.options` (a list of `{ value, label }` maps —
/// the common JSON-driven case) or `<option>` children (`props.value` +
/// `props.text`). The current selection is `props.value`; choosing an item
/// dispatches a `change` event carrying the chosen value, which the host routes
/// to the node's `events.change` handler in the page VM (see
/// NextjsServerWidget._routeEvent / _eventToHostJson). Stateful so the closed
/// button reflects the selection immediately, without the page needing to
/// re-render the whole form on every change.
class HtmlSelect extends StatefulWidget {
  const HtmlSelect({super.key, required this.node, required this.children});

  final ElpianNode node;
  final List<Widget> children;

  /// Registry adapter (every html widget is built as `build(node, children)`).
  static Widget build(ElpianNode node, List<Widget> children) {
    return HtmlSelect(
      key: node.key != null ? ValueKey<String>('select_${node.key}') : null,
      node: node,
      children: children,
    );
  }

  @override
  State<HtmlSelect> createState() => _HtmlSelectState();
}

class _SelectOption {
  const _SelectOption(this.value, this.label);
  final String value;
  final String label;
}

class _HtmlSelectState extends State<HtmlSelect> {
  String? _value;

  String get _elementId => widget.node.key ?? 'element_${widget.node.hashCode}';

  @override
  void initState() {
    super.initState();
    _value = widget.node.props['value']?.toString();
  }

  @override
  void didUpdateWidget(covariant HtmlSelect oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Honour an externally controlled value (e.g. the page reset the form).
    final incoming = widget.node.props['value']?.toString();
    if (incoming != null &&
        incoming != oldWidget.node.props['value']?.toString()) {
      _value = incoming;
    }
  }

  List<_SelectOption> _options() {
    final out = <_SelectOption>[];
    final raw = widget.node.props['options'];
    if (raw is List) {
      for (final o in raw) {
        if (o is Map) {
          final v = (o['value'] ?? o['label'] ?? '').toString();
          out.add(_SelectOption(v, (o['label'] ?? v).toString()));
        } else if (o != null) {
          out.add(_SelectOption(o.toString(), o.toString()));
        }
      }
    }
    if (out.isEmpty) {
      // Fall back to `<option>` children.
      for (final child in widget.node.children) {
        if (child.type == 'option') {
          final v = (child.props['value'] ?? child.props['text'] ?? '').toString();
          out.add(_SelectOption(v, (child.props['text'] ?? v).toString()));
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.node.style;
    final options = _options();
    // Keep the controlled value valid against the available options.
    final value = options.any((o) => o.value == _value)
        ? _value
        : (options.isNotEmpty ? options.first.value : null);

    const textColor = Color(0xFFF7EEDC);
    const fieldFill = Color(0xFF0A1626);

    Widget dropdown = DropdownButton<String>(
      value: value,
      isExpanded: true,
      isDense: true,
      dropdownColor: fieldFill,
      iconEnabledColor: const Color(0xFFD6B36A),
      underline: const SizedBox.shrink(),
      style: TextStyle(
        color: style?.color ?? textColor,
        fontSize: style?.fontSize ?? 13,
      ),
      items: [
        for (final o in options)
          DropdownMenuItem<String>(
            value: o.value,
            child: Text(o.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (newValue) {
        if (newValue == null) return;
        setState(() => _value = newValue);
        EventDispatcher().dispatchChange(_elementId, newValue);
      },
    );

    // Sit the control on the navy glass field surface so it matches inputs.
    dropdown = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: fieldFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1C3450)),
      ),
      child: dropdown,
    );

    if (style != null) {
      dropdown = CSSProperties.applyStyle(dropdown, style);
    }
    return dropdown;
  }
}
