import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianDragTarget {
  static Widget build(ElpianNode node, List<Widget> children) {
    return DragTarget(
      onAcceptWithDetails: (data) {},
      builder: (context, candidateData, rejectedData) {
        return children.isNotEmpty ? children.first : Container();
      },
    );
  }
}
