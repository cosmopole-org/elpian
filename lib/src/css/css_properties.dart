import 'package:flutter/material.dart';
import '../models/css_style.dart';

class CSSProperties {
  /// Apply CSS styles to a widget using Container or other wrappers
  static Widget applyStyle(Widget child, CSSStyle? style) {
    if (style == null) return child;

    Widget result = child;

    // Apply opacity
    if (style.opacity != null && style.opacity! < 1.0) {
      result = Opacity(
        opacity: style.opacity!,
        child: result,
      );
    }

    // Apply transform
    if (style.transform != null || style.rotate != null || style.scale != null) {
      Matrix4 transform = style.transform ?? Matrix4.identity();
      
      if (style.rotate != null) {
        transform = Matrix4.rotationZ(style.rotate! * 3.14159 / 180);
      }
      
      if (style.scale != null) {
        transform = Matrix4.diagonal3Values(style.scale!, style.scale!, 1.0);
      }
      
      result = Transform(
        transform: transform,
        alignment: Alignment.center,
        child: result,
      );
    }

    // Apply visibility
    if (style.visible == false) {
      result = Visibility(
        visible: false,
        child: result,
      );
    }

    // Apply alignment
    if (style.alignment != null) {
      result = Align(
        alignment: style.alignment!,
        child: result,
      );
    }

    // Apply size constraints (before flex so Flexible is outermost)
    if (style.width != null || style.height != null ||
        style.minWidth != null || style.maxWidth != null ||
        style.minHeight != null || style.maxHeight != null) {
      result = ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: style.minWidth ?? 0.0,
          maxWidth: style.maxWidth ?? double.infinity,
          minHeight: style.minHeight ?? 0.0,
          maxHeight: style.maxHeight ?? double.infinity,
        ),
        child: SizedBox(
          width: style.width,
          height: style.height,
          child: result,
        ),
      );
    }

    // Apply Container for styling
    if (_needsContainer(style)) {
      result = Container(
        padding: style.padding,
        decoration: BoxDecoration(
          color: style.backgroundColor,
          gradient: style.gradient,
          border: style.border ?? (style.borderColor != null && style.borderWidth != null
              ? Border.all(
                  color: style.borderColor!,
                  width: style.borderWidth!,
                )
              : null),
          borderRadius: style.borderRadius,
          boxShadow: style.boxShadow,
        ),
        child: result,
      );
    }

    // Apply margin
    if (style.margin != null) {
      result = Padding(
        padding: style.margin!,
        child: result,
      );
    }

    // Wrap with implicit animations if transition properties are set
    if (style.transitionDuration != null && style.animateOnBuild == true) {
      result = _wrapWithAnimations(result, style);
    }

    // Apply flex LAST so Flexible is a direct child of Row/Column/Flex
    if (style.flex != null) {
      result = Flexible(
        flex: style.flex!,
        child: result,
      );
    }

    return result;
  }

  /// Wrap widget with implicit animation wrappers based on style
  static Widget _wrapWithAnimations(Widget child, CSSStyle style) {
    Widget result = child;
    final duration = style.transitionDuration ?? const Duration(milliseconds: 300);
    final curve = style.transitionCurve ?? Curves.linear;

    if (style.opacity != null) {
      result = AnimatedOpacity(
        opacity: style.opacity!,
        duration: duration,
        curve: curve,
        child: result,
      );
    }

    if (style.padding != null) {
      result = AnimatedPadding(
        padding: style.padding!,
        duration: duration,
        curve: curve,
        child: result,
      );
    }

    if (style.alignment != null) {
      result = AnimatedAlign(
        alignment: style.alignment!,
        duration: duration,
        curve: curve,
        child: result,
      );
    }

    return result;
  }

  static bool _needsContainer(CSSStyle style) {
    return style.padding != null ||
        style.backgroundColor != null ||
        style.gradient != null ||
        style.border != null ||
        style.borderRadius != null ||
        style.boxShadow != null ||
        style.borderColor != null;
  }

  /// Create a TextStyle from CSS style
  static TextStyle? createTextStyle(CSSStyle? style) {
    if (style == null) return null;

    return TextStyle(
      color: style.color,
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      fontStyle: style.fontStyle,
      fontFamily: style.fontFamily,
      letterSpacing: style.letterSpacing,
      wordSpacing: style.wordSpacing,
      height: style.lineHeight,
      decoration: style.textDecoration,
      shadows: style.textShadow,
    );
  }

  static const _mainAxisAlignmentMap = <String, MainAxisAlignment>{
    'center': MainAxisAlignment.center,
    'flex-start': MainAxisAlignment.start,
    'start': MainAxisAlignment.start,
    'flex-end': MainAxisAlignment.end,
    'end': MainAxisAlignment.end,
    'space-between': MainAxisAlignment.spaceBetween,
    'space-around': MainAxisAlignment.spaceAround,
    'space-evenly': MainAxisAlignment.spaceEvenly,
  };

  /// Get main axis alignment from CSS justifyContent
  static MainAxisAlignment getMainAxisAlignment(String? justifyContent) {
    return _mainAxisAlignmentMap[justifyContent?.toLowerCase()] ?? MainAxisAlignment.start;
  }

  static const _crossAxisAlignmentMap = <String, CrossAxisAlignment>{
    'center': CrossAxisAlignment.center,
    'flex-start': CrossAxisAlignment.start,
    'start': CrossAxisAlignment.start,
    'flex-end': CrossAxisAlignment.end,
    'end': CrossAxisAlignment.end,
    'stretch': CrossAxisAlignment.stretch,
    'baseline': CrossAxisAlignment.baseline,
  };

  /// Get cross axis alignment from CSS alignItems
  static CrossAxisAlignment getCrossAxisAlignment(String? alignItems) {
    return _crossAxisAlignmentMap[alignItems?.toLowerCase()] ?? CrossAxisAlignment.start;
  }
}
