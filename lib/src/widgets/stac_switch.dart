import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacSwitch {
  static Widget build(StacNode node, List<Widget> children) {
    final value = node.props['value'] as bool? ?? false;
    
    return Switch(
      value: value,
      onChanged: (_) {},
    );
  }
}
