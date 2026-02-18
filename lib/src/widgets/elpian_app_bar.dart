import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianAppBar {
  static Widget build(ElpianNode node, List<Widget> children) {
    final title = node.props['title'] as String? ?? '';
    
    return AppBar(
      title: Text(title),
    ) as Widget;
  }
}
