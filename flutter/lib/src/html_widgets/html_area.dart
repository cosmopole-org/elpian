import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

/// `<area shape coords href>`: one clickable region of a `<map>`. Not
/// rendered itself — the `<img usemap>` using the map hit-tests taps against
/// it, dispatches the area's `click`/`tap` events and follows its `href`.
class HtmlArea {
  static Widget build(ElpianNode node, List<Widget> children) {
    return const SizedBox.shrink();
  }
}
