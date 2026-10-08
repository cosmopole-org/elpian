import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class HtmlOption {
  static Widget build(ElpianNode node, List<Widget> children) {
    final text = node.props['text'] as String? ?? '';
    return Text(text);
  }
}
