import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../canvas/canvas_widget.dart';

class StacCanvasWidget {
  static Widget build(StacNode node, List<Widget> children) {
    final width = node.props['width'] as double?;
    final height = node.props['height'] as double?;
    final backgroundColor = node.props['backgroundColor'] as Color?;
    
    // Get commands from props
    final commands = node.props['commands'] as List<Map<String, dynamic>>? ?? [];
    
    return StacCanvas(
      commands: commands,
      width: width ?? node.style?.width,
      height: height ?? node.style?.height,
      backgroundColor: backgroundColor ?? node.style?.backgroundColor,
    );
  }
}
