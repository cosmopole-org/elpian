import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../css/css_properties.dart';

class HtmlButton {
  static Widget build(StacNode node, List<Widget> children) {
    final text = node.props['text'] as String? ?? 'Button';
    final textColor = node.style?.color ?? Colors.white;
    final child = children.isNotEmpty
        ? children.first
        : Text(text, style: TextStyle(color: textColor));

    Widget result = ElevatedButton(
      onPressed: () {},
      style: ButtonStyle(
        backgroundColor: node.style?.backgroundColor != null
            ? WidgetStateProperty.all(node.style!.backgroundColor)
            : null,
        foregroundColor: node.style?.color != null
            ? WidgetStateProperty.all(node.style!.color)
            : null,
        padding: node.style?.padding != null
            ? WidgetStateProperty.all(node.style!.padding)
            : null,
        shape: node.style?.borderRadius != null
            ? WidgetStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: node.style!.borderRadius!,
                ),
              )
            : null,
      ),
      child: child,
    );

    if (node.style != null) {
      if (node.style!.margin != null) {
        result = Padding(padding: node.style!.margin!, child: result);
      }
      if (node.style!.opacity != null && node.style!.opacity! < 1.0) {
        result = Opacity(opacity: node.style!.opacity!, child: result);
      }
      if (node.style!.width != null || node.style!.height != null) {
        result = SizedBox(
          width: node.style!.width,
          height: node.style!.height,
          child: result,
        );
      }
    }

    return result;
  }
}
