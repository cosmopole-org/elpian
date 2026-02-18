import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

class HtmlAudio {
  static Widget build(ElpianNode node, List<Widget> children) {
    Widget result = Container(
      padding: const EdgeInsets.all(8.0),
      child: const Row(
        children: [
          Icon(Icons.play_arrow),
          Expanded(child: LinearProgressIndicator(value: 0)),
        ],
      ),
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }
}
