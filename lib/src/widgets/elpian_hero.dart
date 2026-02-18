import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianHero {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    final tag = node.props['tag'] ?? 'hero';
    
    return Hero(
      tag: tag,
      child: child,
    );
  }
}
