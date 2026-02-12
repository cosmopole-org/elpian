import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacDragTarget {
  static Widget build(StacNode node, List<Widget> children) {
    return DragTarget(
      onAccept: (data) {},
      builder: (context, candidateData, rejectedData) {
        return children.isNotEmpty ? children.first : Container();
      },
    );
  }
}
