import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import 'html_table.dart';

/// `<tr>`: a row of cells. Its table lays the cells out on the grid (see
/// `HtmlTable`); a row outside a table shows them side by side.
/// `style.backgroundColor` paints behind the row's cells.
class HtmlTr {
  static Widget build(ElpianNode node, List<Widget> children) {
    return HtmlTableRow(
      node: node,
      cells: children,
      cellNodes: node.children,
    );
  }
}
