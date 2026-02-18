import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacAppBar {
  static Widget build(StacNode node, List<Widget> children) {
    final title = node.props['title'] as String? ?? '';
    
    return AppBar(
      title: Text(title),
    ) as Widget;
  }
}
