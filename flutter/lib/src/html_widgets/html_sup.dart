import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import 'html_sub.dart';

/// `<sup>`: superscript — smaller text raised above the baseline (see
/// [HtmlScript]).
class HtmlSup {
  static Widget build(ElpianNode node, List<Widget> children) =>
      HtmlScript(node: node, superscript: true, children: children);
}
