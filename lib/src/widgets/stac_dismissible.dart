import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacDismissible {
  static Widget build(StacNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    final key = node.key ?? 'dismissible';
    
    return Dismissible(
      key: Key(key),
      onDismissed: (_) {},
      child: child,
    );
  }
}
