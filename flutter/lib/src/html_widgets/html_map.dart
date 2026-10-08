import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

/// `<map name>`: an image map. Not rendered itself — the engine indexes its
/// `<area>`s (`DocumentIndex`) and an `<img usemap="#name">` becomes
/// clickable in those regions (see `HtmlImg`).
class HtmlMap {
  static Widget build(ElpianNode node, List<Widget> children) {
    return const SizedBox.shrink();
  }
}
