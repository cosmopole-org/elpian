import 'package:flutter/material.dart';
import '../core/node_events.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

/// `<details>`: a disclosure widget. Its `<summary>` child (or "Details")
/// is always shown with a disclosure triangle; tapping it shows or hides the
/// other children.
///
/// Starts open when the `open` attribute is present (`true`, `"open"` or
/// `""`); a later render that changes `open` moves it to match. Each toggle
/// dispatches `toggle` with data `{open}`.
class HtmlDetails {
  static Widget build(ElpianNode node, List<Widget> children) {
    return _HtmlDetails(
      key: node.key != null ? ValueKey<String>('details_${node.key}') : null,
      node: node,
      events: NodeEvents(node),
      children: children,
    );
  }

  /// Whether an HTML boolean attribute is present / on.
  static bool isOpen(Object? v) =>
      v == true || v == '' || v == 'open' || v == 'true';
}

class _HtmlDetails extends StatefulWidget {
  const _HtmlDetails({
    super.key,
    required this.node,
    required this.children,
    required this.events,
  });

  final ElpianNode node;
  final List<Widget> children;
  final NodeEvents events;

  @override
  State<_HtmlDetails> createState() => _HtmlDetailsState();
}

class _HtmlDetailsState extends State<_HtmlDetails> {
  late bool _open = HtmlDetails.isOpen(widget.node.props['open']);

  @override
  void didUpdateWidget(covariant _HtmlDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    final was = HtmlDetails.isOpen(oldWidget.node.props['open']);
    final now = HtmlDetails.isOpen(widget.node.props['open']);
    if (was != now) _open = now;
  }

  void _toggle() {
    setState(() => _open = !_open);
    widget.events.emit('toggle', data: {'open': _open});
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final summaryIndex = node.children.indexWhere((c) => c.type == 'summary');
    final Widget summary = summaryIndex >= 0 &&
            summaryIndex < widget.children.length
        ? widget.children[summaryIndex]
        : const Text('Details', style: TextStyle(fontWeight: FontWeight.bold));
    final body = <Widget>[
      for (var i = 0; i < widget.children.length; i++)
        if (i != summaryIndex) widget.children[i],
    ];
    final text = node.props['text']?.toString();
    if (text != null && text.isNotEmpty) body.insert(0, Text(text));

    final marker = AnimatedRotation(
      turns: _open ? 0.25 : 0,
      duration: const Duration(milliseconds: 150),
      child: Icon(
        Icons.arrow_right,
        size: 20,
        color: node.style?.color,
      ),
    );

    final header = Semantics(
      button: true,
      expanded: _open,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                marker,
                // Let a long summary wrap when the width is bounded.
                if (constraints.hasBoundedWidth)
                  Flexible(child: summary)
                else
                  summary,
              ],
            ),
          ),
        ),
      ),
    );

    Widget result = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.topLeft,
          child: _open && body.isNotEmpty
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: body,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }
    return result;
  }
}
