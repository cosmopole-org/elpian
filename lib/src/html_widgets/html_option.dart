import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class HtmlOption {
  static Widget build(StacNode node, List<Widget> children) {
    final text = node.props['text'] as String? ?? '';
    return Text(text);
  }
}
