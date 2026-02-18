import 'package:flutter/material.dart';
import '../models/stac_node.dart';
import '../models/css_style.dart';
import '../css/css_properties.dart';

class StacCard {
  static Widget build(StacNode node, List<Widget> children) {
    final child = children.isNotEmpty
      ? (children.length == 1 ? children.first : Column(children: children))
      : null;

    // Extract elevation from boxShadow or props
    final elevation = node.style?.boxShadow != null && node.style!.boxShadow!.isNotEmpty
        ? node.style!.boxShadow!.first.blurRadius / 2
        : node.props['elevation'] as double? ?? 1.0;

    Widget cardChild = child ?? const SizedBox.shrink();
    // Apply padding inside the Card if specified
    if (node.style?.padding != null) {
      cardChild = Padding(
        padding: node.style!.padding!,
        child: cardChild,
      );
    }

    Widget result = Card(
      elevation: elevation,
      color: node.style?.backgroundColor,
      shape: node.style?.borderRadius != null || node.style?.borderColor != null
          ? RoundedRectangleBorder(
              borderRadius: node.style?.borderRadius ?? BorderRadius.zero,
              side: node.style?.borderColor != null
                  ? BorderSide(
                      color: node.style!.borderColor!,
                      width: node.style?.borderWidth ?? 1.0,
                    )
                  : BorderSide.none,
            )
          : null,
      clipBehavior: Clip.antiAlias,
      child: cardChild,
    );

    if (node.style != null) {
      // Create a style with only external/layout properties (not Card-internal ones)
      final externalStyle = CSSStyle(
        width: node.style!.width,
        height: node.style!.height,
        minWidth: node.style!.minWidth,
        maxWidth: node.style!.maxWidth,
        minHeight: node.style!.minHeight,
        maxHeight: node.style!.maxHeight,
        margin: node.style!.margin,
        opacity: node.style!.opacity,
        flex: node.style!.flex,
        transform: node.style!.transform,
        rotate: node.style!.rotate,
        scale: node.style!.scale,
        alignment: node.style!.alignment,
        visible: node.style!.visible,
      );
      result = CSSProperties.applyStyle(result, externalStyle);
    }

    return result;
  }
}
