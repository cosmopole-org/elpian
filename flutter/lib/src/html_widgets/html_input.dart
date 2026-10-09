import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../core/document_index.dart';
import '../core/elpian_services.dart';
import '../css/css_properties.dart';

/// An `<input>` element (text / number / password / checkbox / radio).
///
/// Stateful so a text field keeps its own edit state (seeded once from
/// `props.value`) and a checkbox keeps its toggle — the page never re-renders
/// mid-edit. On change it dispatches `input` (text) / `change` (checkbox/radio)
/// carrying the value, which the host forwards to the node's
/// `events.input`/`events.change` handler in the page VM (see
/// NextjsServerWidget._routeEvent / _eventToHostJson) so client-driven forms can
/// read what the user typed or chose.
///
/// A text-like input with a `list` attribute naming a `<datalist id>` offers
/// that datalist's options as autocomplete suggestions while typing (options
/// containing the typed text, case-insensitively; all of them when the field
/// is empty). Choosing one fills the field and dispatches `input` and
/// `change` with its value.
class HtmlInput extends StatefulWidget {
  const HtmlInput({
    super.key,
    required this.node,
    required this.children,
    this.document,
  });

  final ElpianNode node;
  final List<Widget> children;

  /// The rendering mini app's document index, for `list` → `<datalist>`.
  final DocumentIndex? document;

  static Widget build(ElpianNode node, List<Widget> children) {
    return HtmlInput(
      key: node.key != null ? ValueKey<String>('input_${node.key}') : null,
      node: node,
      document: ElpianServices.current.document,
      children: children,
    );
  }

  /// Input types that take free text (and so can use a datalist).
  static const textTypes = {
    'text',
    'search',
    'url',
    'tel',
    'email',
    'number',
    'password',
  };

  @override
  State<HtmlInput> createState() => _HtmlInputState();
}

class _HtmlInputState extends State<HtmlInput> {
  TextEditingController? _controller;
  FocusNode? _focusNode;
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
    _focusNode?.dispose();
    super.dispose();
  }

  /// The datalist options this input suggests, or null without a `list`.
  List<DatalistOption>? get _suggestions {
    final listId = widget.node.props['list']?.toString();
    if (listId == null || !HtmlInput.textTypes.contains(_type)) return null;
    return widget.document?.datalist(listId);
  }

  Iterable<DatalistOption> _matching(String typed) {
    final options = _suggestions ?? const <DatalistOption>[];
    final q = typed.trim().toLowerCase();
    if (q.isEmpty) return options;
    return options.where((o) =>
        o.value.toLowerCase().contains(q) || o.label.toLowerCase().contains(q));
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
          ElpianServices.current.events.dispatchChange(_elementId, _checked);
        },
      );
    } else if (_type == 'radio') {
      final Object? value = node.props['value'];
      final Object? groupValue = node.props['groupValue'];
      // groupValue/onChanged moved to a RadioGroup ancestor in Flutter 3.32+.
      result = RadioGroup<Object?>(
        groupValue: groupValue,
        onChanged: (newValue) {
          ElpianServices.current.events.dispatchChange(_elementId, newValue);
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
        onChanged: (value) =>
            ElpianServices.current.events.dispatchInput(_elementId, value),
        onSubmitted: (value) =>
            ElpianServices.current.events.dispatchSubmit(_elementId),
      );
      if (_suggestions != null) {
        result = _withSuggestions(result as TextField);
      }
    }

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }
    return result;
  }

  /// Wrap [field] in an autocomplete fed by the input's datalist.
  Widget _withSuggestions(TextField field) {
    final events = ElpianServices.current.events;
    final controller = _controller!;
    final focusNode = _focusNode ??= FocusNode();
    return RawAutocomplete<DatalistOption>(
      textEditingController: controller,
      focusNode: focusNode,
      displayStringForOption: (o) => o.value,
      optionsBuilder: (value) => _matching(value.text),
      onSelected: (option) {
        events.dispatchInput(_elementId, option.value);
        events.dispatchChange(_elementId, option.value);
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) => TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: field.keyboardType,
        obscureText: field.obscureText,
        style: field.style,
        decoration: field.decoration,
        onChanged: field.onChanged,
        onSubmitted: (value) {
          onSubmit();
          field.onSubmitted?.call(value);
        },
      ),
      optionsViewBuilder: (context, onSelected, options) {
        final list = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 360),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final o = list[i];
                  final highlighted =
                      AutocompleteHighlightedOption.of(context) == i;
                  return InkWell(
                    onTap: () => onSelected(o),
                    child: Container(
                      color: highlighted ? Theme.of(context).focusColor : null,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: o.label == o.value
                          ? Text(o.value)
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(o.value),
                                Text(o.label,
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
