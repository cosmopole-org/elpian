import 'package:flutter/material.dart';
import '../core/node_events.dart';
import '../models/elpian_node.dart';

/// `Dismissible`: swipe the child away.
///
/// Children: the content, plus optional children with `props.slot` of
/// `background` (shown behind while swiping, and for both directions when no
/// `secondaryBackground` is given) and `secondaryBackground` (shown when
/// swiping up / end-to-start). Without a background slot, `style.backgroundColor`
/// fills the gap.
///
/// Props: `direction` (`horizontal` — the default —, `vertical`,
/// `endToStart`, `startToEnd`, `up`, `down`, `none`), `threshold` (fraction
/// of the extent, default 0.4), `resizeDuration` / `movementDuration` (ms).
///
/// Events: `dismiss` and `dismissed` (data `{direction}`) when the child has
/// been swiped away, `dismissupdate` (data `{direction, progress, reached}`)
/// while dragging, `resize` while the gap collapses.
///
/// Once dismissed the element stays gone (a dismissed `Dismissible` must
/// leave the tree); re-rendering with a different `key` brings a new one.
class ElpianDismissible {
  static Widget build(ElpianNode node, List<Widget> children) {
    return _ElpianDismissible(
      key: ValueKey<String>('dismissible:${node.key ?? elementIdOf(node)}'),
      node: node,
      events: NodeEvents(node),
      children: children,
    );
  }

  static DismissDirection parseDirection(Object? value) => switch (value) {
        'vertical' => DismissDirection.vertical,
        'endToStart' || 'left' => DismissDirection.endToStart,
        'startToEnd' || 'right' => DismissDirection.startToEnd,
        'up' => DismissDirection.up,
        'down' => DismissDirection.down,
        'none' => DismissDirection.none,
        _ => DismissDirection.horizontal,
      };
}

class _ElpianDismissible extends StatefulWidget {
  const _ElpianDismissible({
    super.key,
    required this.node,
    required this.children,
    required this.events,
  });

  final ElpianNode node;
  final List<Widget> children;
  final NodeEvents events;

  @override
  State<_ElpianDismissible> createState() => _ElpianDismissibleState();
}

class _ElpianDismissibleState extends State<_ElpianDismissible> {
  bool _dismissed = false;

  static Duration? _ms(Object? v) =>
      v is num ? Duration(milliseconds: v.round()) : null;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final node = widget.node;
    Widget? background;
    Widget? secondaryBackground;
    final content = <Widget>[];
    for (var i = 0;
        i < node.children.length && i < widget.children.length;
        i++) {
      switch (node.children[i].props['slot']) {
        case 'background':
          background = widget.children[i];
          break;
        case 'secondaryBackground':
          secondaryBackground = widget.children[i];
          break;
        default:
          content.add(widget.children[i]);
      }
    }
    final color = node.style?.backgroundColor;
    if (background == null && color != null) {
      background = ColoredBox(color: color);
    }

    final e = widget.events;
    final direction = ElpianDismissible.parseDirection(node.props['direction']);
    final threshold = node.props['threshold'];

    return Dismissible(
      key: ValueKey<String>('dismissible-inner:${e.id}'),
      direction: direction,
      background: background,
      // Flutter requires a background whenever a secondary one is given.
      secondaryBackground: background == null ? null : secondaryBackground,
      dismissThresholds: threshold is num
          ? {
              for (final d in DismissDirection.values)
                d: threshold.toDouble().clamp(0.0, 1.0)
            }
          : const <DismissDirection, double>{},
      resizeDuration: _ms(node.props['resizeDuration']) ??
          const Duration(milliseconds: 300),
      movementDuration: _ms(node.props['movementDuration']) ??
          const Duration(milliseconds: 200),
      onUpdate: e.has('dismissupdate')
          ? (d) => e.emit('dismissupdate', data: {
                'direction': d.direction.name,
                'progress': d.progress,
                'reached': d.reached,
              })
          : null,
      onResize: e.has('resize') ? () => e.emit('resize') : null,
      onDismissed: (direction) {
        setState(() => _dismissed = true);
        final data = {'direction': direction.name};
        e.emit('dismissed', data: data);
        if (e.has('dismiss')) e.emit('dismiss', data: data);
      },
      child: content.isEmpty
          ? Container()
          : content.length == 1
              ? content.first
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: content,
                ),
    );
  }
}
