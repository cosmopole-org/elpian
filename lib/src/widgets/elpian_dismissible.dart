import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianDismissible {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    final key = node.key ?? 'dismissible';
    
    return Dismissible(
      key: Key(key),
      onDismissed: (_) {},
      child: child,
    );
  }
}
