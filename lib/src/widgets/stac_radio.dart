import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacRadio {
  static Widget build(StacNode node, List<Widget> children) {
    final value = node.props['value'];
    final groupValue = node.props['groupValue'];
    
    return Radio(
      value: value,
      groupValue: groupValue,
      onChanged: (_) {},
    );
  }
}
