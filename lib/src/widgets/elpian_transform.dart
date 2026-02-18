import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

class ElpianTransform {
  static Widget build(ElpianNode node, List<Widget> children) {
    final child = children.isNotEmpty ? children.first : Container();
    
    Matrix4 transform = node.style?.transform ?? Matrix4.identity();
    
    if (node.style?.rotate != null) {
      transform = Matrix4.rotationZ(node.style!.rotate! * 3.14159 / 180);
    }
    
    if (node.style?.scale != null) {
      transform = Matrix4.diagonal3Values(node.style!.scale!, node.style!.scale!, 1.0);
    }
    
    return Transform(
      transform: transform,
      alignment: Alignment.center,
      child: child,
    );
  }
}
