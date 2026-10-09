import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';
import '../widgets/elpian_canvas_widget.dart';

class HtmlCanvas {
  static Widget build(ElpianNode node, List<Widget> children) {
    final normalizedNode = node.copyWith(
      props: {
        ...node.props,
        if (node.props['width'] == null && node.style?.width != null)
          'width': node.style!.width,
        if (node.props['height'] == null && node.style?.height != null)
          'height': node.style!.height,
      },
    );

    Widget result = ElpianCanvasWidget.build(normalizedNode, children);

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
