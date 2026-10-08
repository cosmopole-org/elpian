import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Where one cell sits in a table grid.
class HtmlTableSlot {
  final int row;
  final int column;
  final int rowSpan;
  final int columnSpan;

  const HtmlTableSlot(this.row, this.column, this.rowSpan, this.columnSpan);

  @override
  bool operator ==(Object other) =>
      other is HtmlTableSlot &&
      other.row == row &&
      other.column == column &&
      other.rowSpan == rowSpan &&
      other.columnSpan == columnSpan;

  @override
  int get hashCode => Object.hash(row, column, rowSpan, columnSpan);
}

class _CellParentData extends ContainerBoxParentData<RenderBox> {
  HtmlTableSlot slot = const HtmlTableSlot(0, 0, 1, 1);
}

/// Places one cell widget at its [slot] of an [HtmlTableLayout].
class HtmlTableCellSlot extends ParentDataWidget<_CellParentData> {
  const HtmlTableCellSlot(
      {super.key, required this.slot, required super.child});

  final HtmlTableSlot slot;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _CellParentData;
    if (data.slot != slot) {
      data.slot = slot;
      final parent = renderObject.parent;
      if (parent is RenderObject) parent.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => HtmlTableLayout;
}

/// The HTML table layout algorithm (the "auto" table layout of CSS 2.1,
/// §17.5.2.2, simplified): cells may span rows and columns; columns get
/// their content's min/max widths (spanning cells spread any excess over
/// the columns they cover); the table shrink-wraps its content up to the
/// available width — or fills it when its width is fixed (tight
/// constraints) — and distributes width between each column's minimum and
/// maximum; rows are as tall as their tallest cell (row-spanning cells
/// spread excess over their rows); every cell is then laid out to fill its
/// whole slot so backgrounds and borders span the row.
///
/// [spacing] is `border-spacing` (0 when borders collapse). [gridLines]
/// draws the HTML `border` attribute's cell and table outlines.
class HtmlTableLayout extends MultiChildRenderObjectWidget {
  const HtmlTableLayout({
    super.key,
    required this.rows,
    required this.columns,
    this.spacing = 2,
    this.gridLines,
    this.columnWidths = const [],
    super.children,
  });

  final int rows;
  final int columns;
  final double spacing;
  final BorderSide? gridLines;

  /// Preferred widths per column (`<col width>`, a cell's `width`); `null`
  /// entries are auto.
  final List<double?> columnWidths;

  @override
  RenderHtmlTable createRenderObject(BuildContext context) => RenderHtmlTable(
        rows: rows,
        columns: columns,
        spacing: spacing,
        gridLines: gridLines,
        columnWidths: columnWidths,
      );

  @override
  void updateRenderObject(BuildContext context, RenderHtmlTable renderObject) {
    renderObject
      ..rows = rows
      ..columns = columns
      ..spacing = spacing
      ..gridLines = gridLines
      ..columnWidths = columnWidths;
  }
}

class RenderHtmlTable extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _CellParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _CellParentData> {
  RenderHtmlTable({
    required int rows,
    required int columns,
    double spacing = 2,
    BorderSide? gridLines,
    List<double?> columnWidths = const [],
  })  : _rows = rows,
        _columns = columns,
        _spacing = spacing,
        _gridLines = gridLines,
        _columnWidths = columnWidths;

  int _rows;
  int get rows => _rows;
  set rows(int v) {
    if (v == _rows) return;
    _rows = v;
    markNeedsLayout();
  }

  int _columns;
  int get columns => _columns;
  set columns(int v) {
    if (v == _columns) return;
    _columns = v;
    markNeedsLayout();
  }

  double _spacing;
  double get spacing => _spacing;
  set spacing(double v) {
    if (v == _spacing) return;
    _spacing = v;
    markNeedsLayout();
  }

  BorderSide? _gridLines;
  BorderSide? get gridLines => _gridLines;
  set gridLines(BorderSide? v) {
    if (v == _gridLines) return;
    _gridLines = v;
    markNeedsPaint();
  }

  List<double?> _columnWidths;
  List<double?> get columnWidths => _columnWidths;
  set columnWidths(List<double?> v) {
    if (listEquals(v, _columnWidths)) return;
    _columnWidths = v;
    markNeedsLayout();
  }

  /// Column x offsets and widths, row y offsets and heights of the last
  /// layout (for painting the grid).
  List<double> _colX = const [];
  List<double> _colW = const [];
  List<double> _rowY = const [];
  List<double> _rowH = const [];

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _CellParentData) {
      child.parentData = _CellParentData();
    }
  }

  Iterable<RenderBox> get _cells sync* {
    var child = firstChild;
    while (child != null) {
      yield child;
      child = (child.parentData! as _CellParentData).nextSibling;
    }
  }

  HtmlTableSlot _slotOf(RenderBox child) {
    final s = (child.parentData! as _CellParentData).slot;
    int fit(int v, int lo, int hi) => math.max(lo, math.min(v, hi));
    final column = fit(s.column, 0, math.max(0, _columns - 1));
    final row = fit(s.row, 0, math.max(0, _rows - 1));
    return HtmlTableSlot(
      row,
      column,
      fit(s.rowSpan, 1, math.max(1, _rows - row)),
      fit(s.columnSpan, 1, math.max(1, _columns - column)),
    );
  }

  static double _safe(double Function() measure) {
    try {
      final v = measure();
      return v.isFinite ? v : 0.0;
    } catch (_) {
      // Some widgets (e.g. LayoutBuilder) cannot report intrinsic sizes.
      return 0.0;
    }
  }

  /// Per-column (min, max) content widths.
  (List<double>, List<double>) _columnRanges() {
    final mins = List<double>.filled(_columns, 0);
    final maxs = List<double>.filled(_columns, 0);
    final spanning = <(HtmlTableSlot, double, double)>[];
    for (final child in _cells) {
      final s = _slotOf(child);
      final min = _safe(() => child.getMinIntrinsicWidth(double.infinity));
      final max = math.max(
          min, _safe(() => child.getMaxIntrinsicWidth(double.infinity)));
      if (s.columnSpan == 1) {
        mins[s.column] = math.max(mins[s.column], min);
        maxs[s.column] = math.max(maxs[s.column], max);
      } else {
        spanning.add((s, min, max));
      }
    }
    for (var c = 0; c < _columns && c < _columnWidths.length; c++) {
      final hint = _columnWidths[c];
      if (hint == null || hint <= 0) continue;
      mins[c] = math.max(mins[c], hint);
      maxs[c] = mins[c];
    }
    // Spanning cells: widen their columns evenly when the columns are too
    // narrow for them.
    for (final (s, min, max) in spanning) {
      final inner = _spacing * (s.columnSpan - 1);
      double sum(List<double> l) {
        var t = inner;
        for (var c = s.column; c < s.column + s.columnSpan; c++) {
          t += l[c];
        }
        return t;
      }

      final minExtra = min - sum(mins);
      if (minExtra > 0) {
        for (var c = s.column; c < s.column + s.columnSpan; c++) {
          mins[c] += minExtra / s.columnSpan;
        }
      }
      final maxExtra = max - sum(maxs);
      if (maxExtra > 0) {
        for (var c = s.column; c < s.column + s.columnSpan; c++) {
          maxs[c] += maxExtra / s.columnSpan;
        }
      }
    }
    for (var c = 0; c < _columns; c++) {
      maxs[c] = math.max(maxs[c], mins[c]);
    }
    return (mins, maxs);
  }

  List<double> _resolveColumnWidths(BoxConstraints constraints) {
    final (mins, maxs) = _columnRanges();
    final chrome = _spacing * (_columns + 1);
    final sumMin = mins.fold<double>(0, (a, b) => a + b);
    final sumMax = maxs.fold<double>(0, (a, b) => a + b);
    if (!constraints.hasBoundedWidth) return maxs;

    final available = math.max(0.0, constraints.maxWidth - chrome);
    final fill = constraints.hasTightWidth;
    final minTarget = math.max(0.0, constraints.minWidth - chrome);
    final target =
        fill ? available : math.max(minTarget, math.min(sumMax, available));

    if (target >= sumMax) {
      final extra = target - sumMax;
      if (extra <= 0) return maxs;
      return [
        for (var c = 0; c < _columns; c++)
          maxs[c] + (sumMax > 0 ? extra * maxs[c] / sumMax : extra / _columns)
      ];
    }
    if (target >= sumMin && sumMax > sumMin) {
      final t = (target - sumMin) / (sumMax - sumMin);
      return [
        for (var c = 0; c < _columns; c++) mins[c] + (maxs[c] - mins[c]) * t
      ];
    }
    return mins;
  }

  double _span(List<double> sizes, int start, int count) {
    var total = _spacing * (count - 1);
    for (var i = start; i < start + count; i++) {
      total += sizes[i];
    }
    return total;
  }

  List<double> _resolveRowHeights(
      List<double> widths, double Function(RenderBox, double) measure) {
    final heights = List<double>.filled(_rows, 0);
    final spanning = <(HtmlTableSlot, double)>[];
    for (final child in _cells) {
      final s = _slotOf(child);
      final h = measure(child, _span(widths, s.column, s.columnSpan));
      if (s.rowSpan == 1) {
        heights[s.row] = math.max(heights[s.row], h);
      } else {
        spanning.add((s, h));
      }
    }
    for (final (s, h) in spanning) {
      final extra = h - _span(heights, s.row, s.rowSpan);
      if (extra > 0) {
        for (var r = s.row; r < s.row + s.rowSpan; r++) {
          heights[r] += extra / s.rowSpan;
        }
      }
    }
    return heights;
  }

  List<double> _offsets(List<double> sizes) {
    final out = <double>[];
    var x = _spacing;
    for (final s in sizes) {
      out.add(x);
      x += s + _spacing;
    }
    return out;
  }

  Size _sizeFor(List<double> widths, List<double> heights) => Size(
        widths.fold<double>(0, (a, b) => a + b) + _spacing * (_columns + 1),
        heights.fold<double>(0, (a, b) => a + b) + _spacing * (_rows + 1),
      );

  @override
  void performLayout() {
    if (_rows == 0 || _columns == 0 || firstChild == null) {
      for (final child in _cells) {
        child.layout(BoxConstraints.tight(Size.zero));
      }
      size = constraints.constrain(Size.zero);
      _colX = _colW = _rowY = _rowH = const [];
      return;
    }
    final widths = _resolveColumnWidths(constraints);
    final heights = _resolveRowHeights(widths, (child, width) {
      child.layout(BoxConstraints(minWidth: width, maxWidth: width),
          parentUsesSize: true);
      return child.size.height;
    });
    final xs = _offsets(widths);
    final ys = _offsets(heights);
    for (final child in _cells) {
      final s = _slotOf(child);
      final w = _span(widths, s.column, s.columnSpan);
      final h = _span(heights, s.row, s.rowSpan);
      child.layout(BoxConstraints.tight(Size(w, h)));
      (child.parentData! as _CellParentData).offset =
          Offset(xs[s.column], ys[s.row]);
    }
    _colX = xs;
    _colW = widths;
    _rowY = ys;
    _rowH = heights;
    size = constraints.constrain(_sizeFor(widths, heights));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    if (_rows == 0 || _columns == 0 || firstChild == null) {
      return constraints.constrain(Size.zero);
    }
    final widths = _resolveColumnWidths(constraints);
    final heights = _resolveRowHeights(
      widths,
      (child, width) => _safe(() => child
          .getDryLayout(BoxConstraints(minWidth: width, maxWidth: width))
          .height),
    );
    return constraints.constrain(_sizeFor(widths, heights));
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    if (_columns == 0) return 0;
    final (mins, _) = _columnRanges();
    return mins.fold<double>(0, (a, b) => a + b) + _spacing * (_columns + 1);
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    if (_columns == 0) return 0;
    final (_, maxs) = _columnRanges();
    return maxs.fold<double>(0, (a, b) => a + b) + _spacing * (_columns + 1);
  }

  double _intrinsicHeight(double width, bool max) {
    if (_rows == 0 || _columns == 0) return 0;
    final widths = _resolveColumnWidths(width.isFinite
        ? BoxConstraints(maxWidth: width)
        : const BoxConstraints());
    final heights = _resolveRowHeights(
      widths,
      (child, w) => _safe(() => max
          ? child.getMaxIntrinsicHeight(w)
          : child.getMinIntrinsicHeight(w)),
    );
    return heights.fold<double>(0, (a, b) => a + b) + _spacing * (_rows + 1);
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _intrinsicHeight(width, false);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _intrinsicHeight(width, true);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
    final side = _gridLines;
    if (side == null || side.style == BorderStyle.none || side.width <= 0) {
      return;
    }
    final paint = side.toPaint();
    final canvas = context.canvas;
    final half = side.width / 2;
    // Each cell's outline, then the table's own.
    for (final child in _cells) {
      final s = _slotOf(child);
      if (s.column >= _colX.length || s.row >= _rowY.length) continue;
      final rect = Rect.fromLTWH(
        offset.dx + _colX[s.column],
        offset.dy + _rowY[s.row],
        _span(_colW, s.column, s.columnSpan),
        _span(_rowH, s.row, s.rowSpan),
      );
      // Collapsed borders: neighbouring cells share an edge, drawn once on
      // the line itself; separated cells each get their own inset outline.
      canvas.drawRect(_spacing == 0 ? rect : rect.deflate(half), paint);
    }
    canvas.drawRect((offset & size).deflate(half), paint);
  }
}
