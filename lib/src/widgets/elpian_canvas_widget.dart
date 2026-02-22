import 'package:flutter/material.dart';

import '../canvas/canvas_widget.dart';
import '../models/elpian_node.dart';

class ElpianCanvasWidget {
  static Widget build(ElpianNode node, List<Widget> children) {
    final width = node.props['width'] as double?;
    final height = node.props['height'] as double?;
    final backgroundColor = node.props['backgroundColor'] as Color?;

    final commands = _normalizeCommands(node.props['commands']);

    return ElpianCanvas(
      commands: commands,
      width: width ?? node.style?.width,
      height: height ?? node.style?.height,
      backgroundColor: backgroundColor ?? node.style?.backgroundColor,
    );
  }

  static List<Map<String, dynamic>> _normalizeCommands(dynamic rawCommands) {
    if (rawCommands is List<Map<String, dynamic>>) {
      return rawCommands;
    }

    if (rawCommands is List) {
      return rawCommands
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    }

    return const [];
  }
}
