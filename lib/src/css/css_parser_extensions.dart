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
  
  static const _clipBehaviorMap = <String, Clip>{
    'none': Clip.none,
    'hardedge': Clip.hardEdge,
    'hard-edge': Clip.hardEdge,
    'antialias': Clip.antiAlias,
    'anti-alias': Clip.antiAlias,
    'antialiaswithdavepath': Clip.antiAliasWithSaveLayer,
    'antialias-with-save-layer': Clip.antiAliasWithSaveLayer,
  };

  /// Parse clip behavior
  static Clip? parseClipBehavior(dynamic value) {
    if (value == null) return null;
    if (value is String) return _clipBehaviorMap[value.toLowerCase()];
    return null;
  }

  static const _boxShapeMap = <String, BoxShape>{
    'rectangle': BoxShape.rectangle,
    'circle': BoxShape.circle,
  };

  /// Parse box shape
  static BoxShape? parseBoxShape(dynamic value) {
    if (value == null) return null;
    if (value is String) return _boxShapeMap[value.toLowerCase()];
    return null;
  }

  static const _textDecorationStyleMap = <String, TextDecorationStyle>{
    'solid': TextDecorationStyle.solid,
    'double': TextDecorationStyle.double,
    'dotted': TextDecorationStyle.dotted,
    'dashed': TextDecorationStyle.dashed,
    'wavy': TextDecorationStyle.wavy,
  };

  /// Parse text decoration style
  static TextDecorationStyle? parseTextDecorationStyle(dynamic value) {
    if (value == null) return null;
    if (value is String) return _textDecorationStyleMap[value.toLowerCase()];
    return null;
  }

  static const _textBaselineMap = <String, TextBaseline>{
    'alphabetic': TextBaseline.alphabetic,
    'ideographic': TextBaseline.ideographic,
  };

  /// Parse text baseline
  static TextBaseline? parseTextBaseline(dynamic value) {
    if (value == null) return null;
    if (value is String) return _textBaselineMap[value.toLowerCase()];
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
  
  static const _wrapAlignmentMap = <String, WrapAlignment>{
    'start': WrapAlignment.start,
    'end': WrapAlignment.end,
    'center': WrapAlignment.center,
    'space-between': WrapAlignment.spaceBetween,
    'space-around': WrapAlignment.spaceAround,
    'space-evenly': WrapAlignment.spaceEvenly,
  };

  /// Parse wrap alignment
  static WrapAlignment parseWrapAlignment(String? value) {
    return _wrapAlignmentMap[value?.toLowerCase()] ?? WrapAlignment.start;
  }

  static const _wrapCrossAlignmentMap = <String, WrapCrossAlignment>{
    'start': WrapCrossAlignment.start,
    'end': WrapCrossAlignment.end,
    'center': WrapCrossAlignment.center,
  };

  /// Parse wrap cross alignment
  static WrapCrossAlignment parseWrapCrossAlignment(String? value) {
    return _wrapCrossAlignmentMap[value?.toLowerCase()] ?? WrapCrossAlignment.start;
  }

  static const _axisMap = <String, Axis>{
    'horizontal': Axis.horizontal,
    'row': Axis.horizontal,
    'vertical': Axis.vertical,
    'column': Axis.vertical,
  };

  /// Parse axis direction
  static Axis parseAxis(String? value) {
    return _axisMap[value?.toLowerCase()] ?? Axis.horizontal;
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
  
  static const _timingFunctionMap = <String, Curve>{
    'linear': Curves.linear,
    'ease': Curves.ease,
    'ease-in': Curves.easeIn,
    'ease-out': Curves.easeOut,
    'ease-in-out': Curves.easeInOut,
    'bounce': Curves.bounceIn,
    'bounce-in': Curves.bounceIn,
    'bounce-out': Curves.bounceOut,
    'bounce-in-out': Curves.bounceInOut,
    'elastic': Curves.elasticIn,
    'elastic-in': Curves.elasticIn,
    'elastic-out': Curves.elasticOut,
    'elastic-in-out': Curves.elasticInOut,
    'decelerate': Curves.decelerate,
    'fast-out-slow-in': Curves.fastOutSlowIn,
  };

  /// Parse animation timing function
  static Curve parseAnimationTimingFunction(String? value) {
    return _timingFunctionMap[value?.toLowerCase()] ?? Curves.linear;
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

  /// Parse animation direction to determine if it should reverse
  static bool parseAnimationReverse(String? direction) {
    switch (direction?.toLowerCase()) {
      case 'reverse':
      case 'alternate':
      case 'alternate-reverse':
        return true;
      default:
        return false;
    }
  }

  /// Parse animation fill mode
  static String parseAnimationFillMode(String? value) {
    switch (value?.toLowerCase()) {
      case 'forwards':
      case 'backwards':
      case 'both':
      case 'none':
        return value!.toLowerCase();
      default:
        return 'none';
    }
  }

  /// Parse animation play state
  static bool parseAnimationRunning(String? value) {
    return value?.toLowerCase() != 'paused';
  }
  
  static const _backgroundRepeatMap = <String, ImageRepeat>{
    'repeat': ImageRepeat.repeat,
    'repeat-x': ImageRepeat.repeatX,
    'repeat-y': ImageRepeat.repeatY,
    'no-repeat': ImageRepeat.noRepeat,
  };

  /// Parse background repeat
  static ImageRepeat parseBackgroundRepeat(String? value) {
    return _backgroundRepeatMap[value?.toLowerCase()] ?? ImageRepeat.noRepeat;
  }

  static const _objectFitMap = <String, BoxFit>{
    'fill': BoxFit.fill,
    'contain': BoxFit.contain,
    'cover': BoxFit.cover,
    'none': BoxFit.none,
    'scale-down': BoxFit.scaleDown,
  };

  /// Parse object fit
  static BoxFit parseObjectFit(String? value) {
    return _objectFitMap[value?.toLowerCase()] ?? BoxFit.contain;
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
