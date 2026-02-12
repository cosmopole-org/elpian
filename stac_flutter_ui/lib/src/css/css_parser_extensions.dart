import 'package:flutter/material.dart';
import 'css_parser.dart';

/// Extended CSS parsing utilities for advanced properties
class CSSParserExtensions {
  /// Parse grid template columns
  static String? parseGridTemplateColumns(dynamic value) {
    if (value == null) return null;
    return value.toString();
  }
  
  /// Parse grid template rows
  static String? parseGridTemplateRows(dynamic value) {
    if (value == null) return null;
    return value.toString();
  }
  
  /// Parse clip behavior
  static Clip? parseClipBehavior(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'none':
          return Clip.none;
        case 'hardedge':
        case 'hard-edge':
          return Clip.hardEdge;
        case 'antialias':
        case 'anti-alias':
          return Clip.antiAlias;
        case 'antialiaswithdavepath':
        case 'antialias-with-save-layer':
          return Clip.antiAliasWithSaveLayer;
      }
    }
    return null;
  }
  
  /// Parse box shape
  static BoxShape? parseBoxShape(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'rectangle':
          return BoxShape.rectangle;
        case 'circle':
          return BoxShape.circle;
      }
    }
    return null;
  }
  
  /// Parse text decoration style
  static TextDecorationStyle? parseTextDecorationStyle(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'solid':
          return TextDecorationStyle.solid;
        case 'double':
          return TextDecorationStyle.double;
        case 'dotted':
          return TextDecorationStyle.dotted;
        case 'dashed':
          return TextDecorationStyle.dashed;
        case 'wavy':
          return TextDecorationStyle.wavy;
      }
    }
    return null;
  }
  
  /// Parse text baseline
  static TextBaseline? parseTextBaseline(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'alphabetic':
          return TextBaseline.alphabetic;
        case 'ideographic':
          return TextBaseline.ideographic;
      }
    }
    return null;
  }
  
  /// Parse border side
  static BorderSide parseBorderSide(Map<String, dynamic> value) {
    return BorderSide(
      color: CSSParser.parseColor(value['color']) ?? Colors.black,
      width: CSSParser.parseDouble(value['width']) ?? 1.0,
      style: parseBorderStyle(value['style']),
    );
  }
  
  /// Parse border style
  static BorderStyle parseBorderStyle(dynamic value) {
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'solid':
          return BorderStyle.solid;
        case 'none':
          return BorderStyle.none;
      }
    }
    return BorderStyle.solid;
  }
  
  /// Parse individual border radii
  static double? parseBorderRadiusValue(dynamic value) {
    return CSSParser.parseDouble(value);
  }
  
  /// Parse gradient colors list
  static List<Color>? parseGradientColors(dynamic value) {
    if (value == null) return null;
    if (value is List) {
      return value
          .map((c) => CSSParser.parseColor(c))
          .where((c) => c != null)
          .cast<Color>()
          .toList();
    }
    return null;
  }
  
  /// Parse gradient stops
  static List<double>? parseGradientStops(dynamic value) {
    if (value == null) return null;
    if (value is List) {
      return value
          .map((s) => CSSParser.parseDouble(s))
          .where((s) => s != null)
          .cast<double>()
          .toList();
    }
    return null;
  }
  
  /// Parse shadow from map
  static Shadow? parseShadow(Map<String, dynamic> value) {
    return Shadow(
      color: CSSParser.parseColor(value['color']) ?? Colors.black26,
      offset: CSSParser.parseOffset(value['offset']) ?? Offset.zero,
      blurRadius: CSSParser.parseDouble(value['blurRadius'] ?? value['blur']) ?? 0,
    );
  }
  
  /// Parse box shadow from map
  static BoxShadow? parseBoxShadowSingle(Map<String, dynamic> value) {
    return BoxShadow(
      color: CSSParser.parseColor(value['color']) ?? Colors.black26,
      offset: CSSParser.parseOffset(value['offset']) ?? Offset.zero,
      blurRadius: CSSParser.parseDouble(value['blurRadius'] ?? value['blur']) ?? 0,
      spreadRadius: CSSParser.parseDouble(value['spreadRadius'] ?? value['spread']) ?? 0,
    );
  }
  
  /// Parse multiple box shadows
  static List<BoxShadow?>? parseBoxShadows(dynamic value) {
    if (value == null) return null;
    if (value is List) {
      return value
          .where((item) => item is Map<String, dynamic>)
          .map((item) => parseBoxShadowSingle(item as Map<String, dynamic>))
          .toList();
    } else if (value is Map<String, dynamic>) {
      return [parseBoxShadowSingle(value)];
    }
    return null;
  }
  
  /// Parse flex basis
  static String? parseFlexBasis(dynamic value) {
    if (value == null) return null;
    return value.toString();
  }
  
  /// Parse wrap alignment
  static WrapAlignment parseWrapAlignment(String? value) {
    switch (value?.toLowerCase()) {
      case 'start':
        return WrapAlignment.start;
      case 'end':
        return WrapAlignment.end;
      case 'center':
        return WrapAlignment.center;
      case 'space-between':
        return WrapAlignment.spaceBetween;
      case 'space-around':
        return WrapAlignment.spaceAround;
      case 'space-evenly':
        return WrapAlignment.spaceEvenly;
      default:
        return WrapAlignment.start;
    }
  }
  
  /// Parse wrap cross alignment
  static WrapCrossAlignment parseWrapCrossAlignment(String? value) {
    switch (value?.toLowerCase()) {
      case 'start':
        return WrapCrossAlignment.start;
      case 'end':
        return WrapCrossAlignment.end;
      case 'center':
        return WrapCrossAlignment.center;
      default:
        return WrapCrossAlignment.start;
    }
  }
  
  /// Parse axis direction
  static Axis parseAxis(String? value) {
    switch (value?.toLowerCase()) {
      case 'horizontal':
      case 'row':
        return Axis.horizontal;
      case 'vertical':
      case 'column':
        return Axis.vertical;
      default:
        return Axis.horizontal;
    }
  }
  
  /// Parse matrix4 from string or map
  static Matrix4? parseMatrix4(dynamic value) {
    if (value == null) return null;
    
    if (value is List && value.length == 16) {
      return Matrix4.fromList(
        value.map((e) => (e as num).toDouble()).toList(),
      );
    }
    
    return null;
  }
  
  /// Parse transform origin
  static Alignment? parseTransformOrigin(dynamic value) {
    return CSSParser.parseAlignment(value) as Alignment?;
  }
  
  /// Parse multiple transforms and combine them
  static Matrix4? parseTransforms(Map<String, dynamic> transforms) {
    Matrix4 result = Matrix4.identity();
    
    if (transforms['translateX'] != null || transforms['translateY'] != null) {
      final tx = CSSParser.parseDouble(transforms['translateX']) ?? 0.0;
      final ty = CSSParser.parseDouble(transforms['translateY']) ?? 0.0;
      result = Matrix4.translationValues(tx, ty, 0.0);
    }
    
    if (transforms['rotate'] != null) {
      final angle = CSSParser.parseDouble(transforms['rotate']) ?? 0.0;
      result = result * Matrix4.rotationZ(angle * 3.14159 / 180);
    }
    
    if (transforms['rotateX'] != null) {
      final angle = CSSParser.parseDouble(transforms['rotateX']) ?? 0.0;
      result = result * Matrix4.rotationX(angle * 3.14159 / 180);
    }
    
    if (transforms['rotateY'] != null) {
      final angle = CSSParser.parseDouble(transforms['rotateY']) ?? 0.0;
      result = result * Matrix4.rotationY(angle * 3.14159 / 180);
    }
    
    if (transforms['rotateZ'] != null) {
      final angle = CSSParser.parseDouble(transforms['rotateZ']) ?? 0.0;
      result = result * Matrix4.rotationZ(angle * 3.14159 / 180);
    }
    
    if (transforms['scale'] != null) {
      final scale = CSSParser.parseDouble(transforms['scale']) ?? 1.0;
      result = result * Matrix4.diagonal3Values(scale, scale, 1.0);
    }
    
    if (transforms['scaleX'] != null || transforms['scaleY'] != null) {
      final sx = CSSParser.parseDouble(transforms['scaleX']) ?? 1.0;
      final sy = CSSParser.parseDouble(transforms['scaleY']) ?? 1.0;
      result = result * Matrix4.diagonal3Values(sx, sy, 1.0);
    }
    
    if (transforms['skewX'] != null) {
      final angle = CSSParser.parseDouble(transforms['skewX']) ?? 0.0;
      result = result * Matrix4.skewX(angle * 3.14159 / 180);
    }
    
    if (transforms['skewY'] != null) {
      final angle = CSSParser.parseDouble(transforms['skewY']) ?? 0.0;
      result = result * Matrix4.skewY(angle * 3.14159 / 180);
    }
    
    return result;
  }
  
  /// Parse filter values (for blur, brightness, etc.)
  static double? parseFilterValue(dynamic value) {
    return CSSParser.parseDouble(value);
  }
  
  /// Parse animation timing function
  static Curve parseAnimationTimingFunction(String? value) {
    switch (value?.toLowerCase()) {
      case 'linear':
        return Curves.linear;
      case 'ease':
        return Curves.ease;
      case 'ease-in':
        return Curves.easeIn;
      case 'ease-out':
        return Curves.easeOut;
      case 'ease-in-out':
        return Curves.easeInOut;
      case 'bounce':
        return Curves.bounceIn;
      case 'elastic':
        return Curves.elasticIn;
      default:
        return Curves.linear;
    }
  }
  
  /// Parse iteration count
  static int? parseIterationCount(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) {
      if (value.toLowerCase() == 'infinite') return -1;
      return int.tryParse(value);
    }
    return null;
  }
  
  /// Parse background repeat
  static ImageRepeat parseBackgroundRepeat(String? value) {
    switch (value?.toLowerCase()) {
      case 'repeat':
        return ImageRepeat.repeat;
      case 'repeat-x':
        return ImageRepeat.repeatX;
      case 'repeat-y':
        return ImageRepeat.repeatY;
      case 'no-repeat':
        return ImageRepeat.noRepeat;
      default:
        return ImageRepeat.noRepeat;
    }
  }
  
  /// Parse object fit
  static BoxFit parseObjectFit(String? value) {
    switch (value?.toLowerCase()) {
      case 'fill':
        return BoxFit.fill;
      case 'contain':
        return BoxFit.contain;
      case 'cover':
        return BoxFit.cover;
      case 'none':
        return BoxFit.none;
      case 'scale-down':
        return BoxFit.scaleDown;
      default:
        return BoxFit.contain;
    }
  }
  
  /// Parse list style type
  static String parseListStyleType(String? value) {
    return value ?? 'disc';
  }
  
  /// Parse vertical align
  static String parseVerticalAlign(String? value) {
    return value ?? 'baseline';
  }
  
  /// Parse writing mode
  static String parseWritingMode(String? value) {
    return value ?? 'horizontal-tb';
  }
}
