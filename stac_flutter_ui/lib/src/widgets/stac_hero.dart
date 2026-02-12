import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacHero {
  static Widget build(StacNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    final tag = node.props['tag'] ?? 'hero';
    
    return Hero(
      tag: tag,
      child: child,
    );
  }
}
