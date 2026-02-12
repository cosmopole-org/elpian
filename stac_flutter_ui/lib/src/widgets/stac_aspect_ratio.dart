import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacAspectRatio {
  static Widget build(StacNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    final aspectRatio = node.props['aspectRatio'] as double? ?? 1.0;
    
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: child,
    );
  }
}
