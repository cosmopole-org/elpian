import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianCheckbox {
  static Widget build(ElpianNode node, List<Widget> children) {
    final value = node.props['value'] as bool? ?? false;
    
    return Checkbox(
      value: value,
      onChanged: (_) {},
    );
  }
}
