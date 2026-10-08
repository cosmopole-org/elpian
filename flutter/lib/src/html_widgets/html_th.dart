import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import 'html_td.dart';

/// `<th>`: a header cell — a `<td>` that is bold and centred by default.
class HtmlTh {
  static Widget build(ElpianNode node, List<Widget> children) =>
      HtmlTd.buildCell(node, children, header: true);
}
