import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacCheckbox {
  static Widget build(StacNode node, List<Widget> children) {
    final value = node.props['value'] as bool? ?? false;
    
    return Checkbox(
      value: value,
      onChanged: (_) {},
    );
  }
}
