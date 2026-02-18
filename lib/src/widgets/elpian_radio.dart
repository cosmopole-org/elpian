import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianRadio {
  static Widget build(ElpianNode node, List<Widget> children) {
    final value = node.props['value'];
    final groupValue = node.props['groupValue'];
    
    return Radio(
      value: value,
      groupValue: groupValue,
      onChanged: (_) {},
    );
  }
}
