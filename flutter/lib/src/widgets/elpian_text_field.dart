import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/elpian_node.dart';
import '../core/elpian_services.dart';
import '../core/event_dispatcher.dart';
import '../css/css_properties.dart';

/// A text input.
///
/// Props: `hint`; `value` (when present the field is controlled — it shows
/// the value and follows changes to it, while the user's typing is reported as
/// `input` events); `obscureText`; `multiline` / `maxLines`; `keyboardType`
/// (`text`, `number`, `email`, `phone`, `url`, or `date` / `time` /
/// `datetime-local`, which open the platform pickers and report
/// `yyyy-MM-dd` / `HH:mm` / `yyyy-MM-ddTHH:mm`); `min` / `max` bound the date
/// pickers. Events: `input` (each change), `submit`.
class ElpianTextField {
  static Widget build(ElpianNode node, List<Widget> children) {
    final elementId = node.key ?? 'element_${node.hashCode}';
    Widget result = _ElpianTextFieldView(
      node: node,
      elementId: elementId,
      dispatcher: ElpianServices.current.events,
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}

class _ElpianTextFieldView extends StatefulWidget {
  const _ElpianTextFieldView({
    required this.node,
    required this.elementId,
    required this.dispatcher,
  });

  final ElpianNode node;
  final String elementId;
  final EventDispatcher dispatcher;

  @override
  State<_ElpianTextFieldView> createState() => _ElpianTextFieldViewState();
}

class _ElpianTextFieldViewState extends State<_ElpianTextFieldView> {
  late final TextEditingController _controller =
      TextEditingController(text: _value ?? '');

  Map<String, dynamic> get _props => widget.node.props;

  String? get _value {
    final v = _props['value'];
    return v == null ? null : '$v';
  }

  String get _mode => _props['keyboardType'] is String
      ? _props['keyboardType'] as String
      : 'text';

  bool get _picker =>
      _mode == 'date' || _mode == 'time' || _mode == 'datetime-local';

  @override
  void didUpdateWidget(_ElpianTextFieldView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final value = _value;
    // Follow the controlling value; leave the user's caret alone when the
    // value is what they just typed.
    if (value != null && value != _controller.text) {
      _controller.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _input(String value) =>
      widget.dispatcher.dispatchInput(widget.elementId, value);

  DateTime? _parse(Object? v) {
    if (v is! String || v.isEmpty) return null;
    return DateTime.tryParse(v);
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

  Future<void> _pick() async {
    final current = _controller.text;
    final now = DateTime.now();
    DateTime? date;
    TimeOfDay? time;
    if (_mode != 'time') {
      final initial = _parse(current) ?? now;
      final first = _parse(_props['min']) ?? DateTime(1900);
      final last = _parse(_props['max']) ?? DateTime(2200);
      date = await showDatePicker(
        context: context,
        initialDate: initial.isBefore(first)
            ? first
            : (initial.isAfter(last) ? last : initial),
        firstDate: first,
        lastDate: last,
      );
      if (date == null || !mounted) return;
    }
    if (_mode != 'date') {
      final m = RegExp(r'(\d{2}):(\d{2})').firstMatch(current);
      time = await showTimePicker(
        context: context,
        initialTime: m != null
            ? TimeOfDay(hour: int.parse(m[1]!), minute: int.parse(m[2]!))
            : TimeOfDay.fromDateTime(now),
      );
      if (time == null || !mounted) return;
    }
    final t = time == null ? '' : '${_two(time.hour)}:${_two(time.minute)}';
    final value = _mode == 'date'
        ? _date(date!)
        : _mode == 'time'
            ? t
            : '${_date(date!)}T$t';
    _controller.text = value;
    _input(value);
  }

  TextInputType get _keyboard => switch (_mode) {
        'number' =>
          const TextInputType.numberWithOptions(decimal: true, signed: true),
        'email' => TextInputType.emailAddress,
        'phone' => TextInputType.phone,
        'url' => TextInputType.url,
        _ => _props['multiline'] == true
            ? TextInputType.multiline
            : TextInputType.text,
      };

  @override
  Widget build(BuildContext context) {
    final hint = _props['hint'] as String? ?? '';
    final obscure = _props['obscureText'] == true;
    final multiline = _props['multiline'] == true;
    final maxLines = obscure
        ? 1
        : (_props['maxLines'] as num?)?.toInt() ?? (multiline ? null : 1);
    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        hintText: hint,
        suffixIcon: _picker
            ? Icon(_mode == 'time' ? Icons.schedule : Icons.calendar_today)
            : null,
      ),
      obscureText: obscure,
      minLines: multiline && !obscure ? 1 : null,
      maxLines: maxLines,
      keyboardType: _keyboard,
      inputFormatters: _mode == 'number'
          ? [FilteringTextInputFormatter.allow(RegExp(r'[-+0-9.eE]'))]
          : null,
      readOnly: _picker,
      onTap: _picker ? _pick : null,
      onChanged: _input,
      onSubmitted: (_) => widget.dispatcher.dispatchSubmit(widget.elementId),
    );
  }
}
