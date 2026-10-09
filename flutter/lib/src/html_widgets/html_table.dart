import 'package:flutter/material.dart';
import '../core/event_enabled_widget.dart';
import '../css/css_properties.dart';
import '../models/elpian_node.dart';
import 'html_table_layout.dart';

/// A built `<tr>`: its cell widgets and the nodes they came from, so the
/// table can read `colspan` / `rowspan`. Outside a table it lays the cells
/// out in a row.
class HtmlTableRow extends StatelessWidget {
  const HtmlTableRow({
    super.key,
    required this.node,
    required this.cells,
    required this.cellNodes,
  });

  final ElpianNode node;
  final List<Widget> cells;
  final List<ElpianNode> cellNodes;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: cells,
      );
}

/// A built `<thead>` / `<tbody>` / `<tfoot>`: its rows. Outside a table it
/// stacks them.
class HtmlTableSection extends StatelessWidget {
  const HtmlTableSection({
    super.key,
    required this.node,
    required this.rows,
    required this.rowNodes,
  });

  final ElpianNode node;
  final List<Widget> rows;
  final List<ElpianNode> rowNodes;

  static Widget fromNode(ElpianNode node, List<Widget> children) =>
      HtmlTableSection(node: node, rows: children, rowNodes: node.children);

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      );
}

/// `<caption>`: centred text above (or, with `caption-side: bottom`,
/// below) its table.
class HtmlCaption {
  static Widget build(ElpianNode node, List<Widget> children) {
    final text = node.props['text']?.toString() ?? '';
    Widget result = children.isNotEmpty
        ? Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (text.isNotEmpty)
                Text(text, style: CSSProperties.createTextStyle(node.style)),
              ...children,
            ],
          )
        : Text(
            text,
            textAlign: node.style?.textAlign ?? TextAlign.center,
            style: CSSProperties.createTextStyle(node.style),
          );
    result = Padding(
      padding: node.style?.padding ?? const EdgeInsets.symmetric(vertical: 4),
      child: result,
    );
    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }
    return result;
  }
}

/// `<colgroup>` / `<col>`: column width hints (`width`, repeated `span`
/// times). Renders nothing; the table reads the hints.
class HtmlColgroup extends StatelessWidget {
  const HtmlColgroup({super.key, required this.widths});

  /// One entry per column (`null` = auto).
  final List<double?> widths;

  static Widget fromNode(ElpianNode node, List<Widget> children) {
    final widths = <double?>[];
    void add(ElpianNode col) {
      final span = _int(col.props['span']) ?? 1;
      final w = _px(col.props['width']) ?? col.style?.width;
      for (var i = 0; i < span.clamp(1, 1000); i++) {
        widths.add(w);
      }
    }

    if (node.type == 'col') {
      add(node);
    } else if (node.children.any((c) => c.type == 'col')) {
      for (final c in node.children) {
        if (c.type == 'col') add(c);
      }
    } else {
      add(node);
    }
    return HtmlColgroup(widths: widths);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

int? _int(Object? v) =>
    v is num ? v.toInt() : (v is String ? int.tryParse(v.trim()) : null);

/// A pixel length (`120`, `"120"`, `"120px"`); percentages are not pixels.
double? _px(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) {
    final s = v.trim();
    if (s.endsWith('%')) return null;
    return double.tryParse(s.endsWith('px') ? s.substring(0, s.length - 2) : s);
  }
  return null;
}

/// The widget [T] the engine built, looking through the wrappers it adds
/// (a [KeyedSubtree] for a keyed node, an [EventEnabledWidget] for one with
/// events). Returns the found widget and a function re-applying an event
/// wrapper to another widget (so a row's events still reach its cells).
(T?, Widget Function(Widget)?) _unwrap<T extends Widget>(Widget widget) {
  Widget? current = widget;
  Widget Function(Widget)? rewrap;
  while (current != null) {
    if (current is T) return (current, rewrap);
    if (current is KeyedSubtree) {
      current = current.child;
    } else if (current is EventEnabledWidget) {
      final events = current;
      final outer = rewrap;
      Widget wrap(Widget w) => EventEnabledWidget(
            node: events.node,
            parentId: events.parentId,
            handleGestures: events.handleGestures,
            child: w,
          );
      rewrap = outer == null ? wrap : (w) => outer(wrap(w));
      current = current.child;
    } else {
      current = null;
    }
  }
  return (null, null);
}

class _RowSpec {
  _RowSpec(this.cells);
  final List<_CellSpec> cells;
}

class _CellSpec {
  _CellSpec(this.widget, this.colSpan, this.rowSpan, this.width);
  final Widget widget;

  /// 0 = span every column (a stray non-row child of the table).
  int colSpan;
  final int rowSpan;
  final double? width;
}

/// `<table>`: a real table layout — rows and cells (with `colspan` /
/// `rowspan`) from `<tr>` children and `<thead>` / `<tbody>` / `<tfoot>`
/// sections (head first, foot last, as HTML renders them), a `<caption>`,
/// and `<col>` / `<colgroup>` width hints. See [HtmlTableLayout] for the
/// layout rules.
///
/// Borders: `border-collapse: collapse` removes the gaps between cells;
/// otherwise `border-spacing` (or the `cellspacing` attribute; default 2)
/// separates them. The `border` attribute outlines the table and every cell
/// (`style.borderColor` colours it).
class HtmlTable {
  static Widget build(ElpianNode node, List<Widget> children) {
    final head = <_RowSpec>[];
    final body = <_RowSpec>[];
    final foot = <_RowSpec>[];
    final colHints = <double?>[];
    Widget? caption;
    var captionBottom = false;

    _RowSpec rowOf(Widget widget, ElpianNode rowNode) {
      final (row, rewrap) = _unwrap<HtmlTableRow>(widget);
      if (row == null) {
        return _RowSpec([_CellSpec(widget, 0, 1, null)]);
      }
      final background = rowNode.style?.backgroundColor;
      final cells = <_CellSpec>[];
      for (var i = 0; i < row.cells.length; i++) {
        final cellNode = i < row.cellNodes.length ? row.cellNodes[i] : null;
        var cell = row.cells[i];
        if (background != null) {
          cell = ColoredBox(color: background, child: cell);
        }
        if (rewrap != null) cell = rewrap(cell);
        final props = cellNode?.props ?? const {};
        cells.add(_CellSpec(
          cell,
          (_int(props['colspan'] ?? props['colSpan']) ?? 1).clamp(1, 1000),
          (_int(props['rowspan'] ?? props['rowSpan']) ?? 1).clamp(0, 65534),
          _px(props['width']),
        ));
      }
      return _RowSpec(cells);
    }

    for (var i = 0; i < node.children.length && i < children.length; i++) {
      final childNode = node.children[i];
      final widget = children[i];
      switch (childNode.type) {
        case 'caption':
          caption = widget;
          captionBottom =
              (childNode.style?.captionSide ?? node.style?.captionSide) ==
                  'bottom';
          break;
        case 'thead':
        case 'tbody':
        case 'tfoot':
          final target = childNode.type == 'thead'
              ? head
              : childNode.type == 'tfoot'
                  ? foot
                  : body;
          final (section, _) = _unwrap<HtmlTableSection>(widget);
          if (section == null) {
            target.add(_RowSpec([_CellSpec(widget, 0, 1, null)]));
            break;
          }
          for (var r = 0;
              r < section.rows.length && r < section.rowNodes.length;
              r++) {
            target.add(rowOf(section.rows[r], section.rowNodes[r]));
          }
          break;
        case 'tr':
          body.add(rowOf(widget, childNode));
          break;
        case 'colgroup':
        case 'col':
          final (cols, _) = _unwrap<HtmlColgroup>(widget);
          if (cols != null) colHints.addAll(cols.widths);
          break;
        default:
          body.add(_RowSpec([_CellSpec(widget, 0, 1, null)]));
      }
    }
    final rows = [...head, ...body, ...foot];

    // Place cells on the grid, skipping slots taken by row-spanning cells
    // from rows above.
    final occupied = <List<bool>>[];
    bool taken(int r, int c) =>
        r < occupied.length && c < occupied[r].length && occupied[r][c];
    void take(int r, int c) {
      while (occupied.length <= r) {
        occupied.add(<bool>[]);
      }
      final row = occupied[r];
      while (row.length <= c) {
        row.add(false);
      }
      row[c] = true;
    }

    final placed = <(HtmlTableSlot, _CellSpec)>[];
    var columns = 0;
    for (var r = 0; r < rows.length; r++) {
      var c = 0;
      for (final cell in rows[r].cells) {
        while (taken(r, c)) {
          c++;
        }
        final colSpan = cell.colSpan == 0 ? 1 : cell.colSpan;
        // rowspan="0" spans to the end of the table.
        final rowSpan = cell.rowSpan == 0
            ? rows.length - r
            : cell.rowSpan.clamp(1, rows.length - r);
        for (var dr = 0; dr < rowSpan; dr++) {
          for (var dc = 0; dc < colSpan; dc++) {
            take(r + dr, c + dc);
          }
        }
        placed.add((HtmlTableSlot(r, c, rowSpan, colSpan), cell));
        c += colSpan;
        if (c > columns) columns = c;
      }
    }

    final hints = List<double?>.filled(columns, null);
    for (var c = 0; c < columns && c < colHints.length; c++) {
      hints[c] = colHints[c];
    }
    final slotted = <Widget>[];
    for (final (slot, cell) in placed) {
      final spansAll = cell.colSpan == 0;
      final s = spansAll
          ? HtmlTableSlot(slot.row, 0, slot.rowSpan, columns == 0 ? 1 : columns)
          : slot;
      if (!spansAll && s.columnSpan == 1 && cell.width != null) {
        final w = cell.width!;
        hints[s.column] = hints[s.column] == null
            ? w
            : (hints[s.column]! > w ? hints[s.column] : w);
      }
      slotted.add(HtmlTableCellSlot(slot: s, child: cell.widget));
    }

    final style = node.style;
    final collapse = style?.borderCollapse == 'collapse';
    final spacing = collapse
        ? 0.0
        : style?.borderSpacing ?? _px(node.props['cellspacing']) ?? 2.0;
    final border = node.props['border'];
    final bordered = border != null &&
        border != false &&
        border != 0 &&
        border != '0' &&
        border != 'false';

    Widget result = HtmlTableLayout(
      rows: rows.length,
      columns: columns,
      spacing: spacing,
      gridLines: bordered
          ? BorderSide(
              color: style?.borderColor ?? const Color(0xFF808080),
              width: _px(border)?.clamp(1.0, 10.0) ?? 1.0,
            )
          : null,
      columnWidths: hints,
      children: slotted,
    );

    if (caption != null) {
      result = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: captionBottom ? [result, caption] : [caption, result],
      );
      // Keep the caption as wide as the table, not the page.
      result = IntrinsicWidth(child: result);
    }

    if (style != null) {
      result = CSSProperties.applyStyle(result, style);
    }
    return result;
  }
}
