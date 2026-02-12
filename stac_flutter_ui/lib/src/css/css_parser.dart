import 'package:flutter/material.dart';
import '../models/css_style.dart';

class CSSParser {
  static CSSStyle parse(Map<String, dynamic> styleMap) {
    return CSSStyle(
      width: parseDouble(styleMap['width']),
      height: parseDouble(styleMap['height']),
      minWidth: parseDouble(styleMap['minWidth'] ?? styleMap['min-width']),
      maxWidth: parseDouble(styleMap['maxWidth'] ?? styleMap['max-width']),
      minHeight: parseDouble(styleMap['minHeight'] ?? styleMap['min-height']),
      maxHeight: parseDouble(styleMap['maxHeight'] ?? styleMap['max-height']),
      padding: _parseEdgeInsets(styleMap['padding']),
      margin: _parseEdgeInsets(styleMap['margin']),
      alignment: parseAlignment(styleMap['alignment']),
      position: styleMap['position'] as String?,
      top: parseDouble(styleMap['top']),
      right: parseDouble(styleMap['right']),
      bottom: parseDouble(styleMap['bottom']),
      left: parseDouble(styleMap['left']),
      zIndex: parseDouble(styleMap['zIndex'] ?? styleMap['z-index']),
      display: styleMap['display'] as String?,
      flexDirection:
          styleMap['flexDirection'] ?? styleMap['flex-direction'] as String?,
      justifyContent:
          styleMap['justifyContent'] ?? styleMap['justify-content'] as String?,
      alignItems: styleMap['alignItems'] ?? styleMap['align-items'] as String?,
      flex: parseInt(styleMap['flex']),
      overflow: _parseOverflow(styleMap['overflow']),
      backgroundColor: parseColor(
          styleMap['backgroundColor'] ?? styleMap['background-color']),
      backgroundImage: styleMap['backgroundImage'] ??
          styleMap['background-image'] as String?,
      backgroundSize: _parseBoxFit(
          styleMap['backgroundSize'] ?? styleMap['background-size']),
      backgroundPosition: parseAlignment(
          styleMap['backgroundPosition'] ?? styleMap['background-position']),
      gradient: _parseGradient(styleMap['gradient']),
      border: _parseBorder(styleMap['border']),
      borderRadius: _parseBorderRadius(
          styleMap['borderRadius'] ?? styleMap['border-radius']),
      borderColor:
          parseColor(styleMap['borderColor'] ?? styleMap['border-color']),
      borderWidth:
          parseDouble(styleMap['borderWidth'] ?? styleMap['border-width']),
      borderStyle:
          styleMap['borderStyle'] ?? styleMap['border-style'] as String?,
      color: parseColor(styleMap['color']),
      fontSize: parseDouble(styleMap['fontSize'] ?? styleMap['font-size']),
      fontWeight:
          _parseFontWeight(styleMap['fontWeight'] ?? styleMap['font-weight']),
      fontStyle:
          _parseFontStyle(styleMap['fontStyle'] ?? styleMap['font-style']),
      fontFamily: styleMap['fontFamily'] ?? styleMap['font-family'] as String?,
      letterSpacing:
          parseDouble(styleMap['letterSpacing'] ?? styleMap['letter-spacing']),
      wordSpacing:
          parseDouble(styleMap['wordSpacing'] ?? styleMap['word-spacing']),
      lineHeight:
          parseDouble(styleMap['lineHeight'] ?? styleMap['line-height']),
      textAlign:
          _parseTextAlign(styleMap['textAlign'] ?? styleMap['text-align']),
      textDecoration: _parseTextDecoration(
          styleMap['textDecoration'] ?? styleMap['text-decoration']),
      textOverflow: _parseTextOverflow(
          styleMap['textOverflow'] ?? styleMap['text-overflow']),
      textTransform:
          styleMap['textTransform'] ?? styleMap['text-transform'] as String?,
      boxShadow:
          _parseBoxShadow(styleMap['boxShadow'] ?? styleMap['box-shadow']),
      textShadow:
          _parseTextShadow(styleMap['textShadow'] ?? styleMap['text-shadow']),
      transform: _parseTransform(styleMap['transform']),
      rotate: parseDouble(styleMap['rotate']),
      scale: parseDouble(styleMap['scale']),
      translate: parseOffset(styleMap['translate']),
      opacity: parseDouble(styleMap['opacity']),
      visible: styleMap['visible'] as bool?,
      cursor: styleMap['cursor'] as String?,
      pointerEvents:
          styleMap['pointerEvents'] ?? styleMap['pointer-events'] as String?,
      gap: parseDouble(styleMap['gap']),
      flexWrap: styleMap['flexWrap'] ?? styleMap['flex-wrap'] as String?,
      transitionDuration: _parseDuration(
          styleMap['transitionDuration'] ?? styleMap['transition-duration']),
      transitionCurve: _parseCurve(
          styleMap['transitionCurve'] ?? styleMap['transition-curve']),
    );
  }

  static double? parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      final numStr = value.replaceAll(RegExp(r'[^0-9.]'), '');
      return double.tryParse(numStr);
    }
    return null;
  }

  static int? parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static Color? parseColor(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      String colorStr = value.trim();

      // Hex colors
      if (colorStr.startsWith('#')) {
        colorStr = colorStr.substring(1);
        if (colorStr.length == 6) {
          return Color(int.parse('FF$colorStr', radix: 16));
        } else if (colorStr.length == 8) {
          return Color(int.parse(colorStr, radix: 16));
        }
      }

      // RGB/RGBA
      if (colorStr.startsWith('rgb')) {
        final match =
            RegExp(r'rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)')
                .firstMatch(colorStr);
        if (match != null) {
          final r = int.parse(match.group(1)!);
          final g = int.parse(match.group(2)!);
          final b = int.parse(match.group(3)!);
          final a = match.group(4) != null
              ? (double.parse(match.group(4)!) * 255).toInt()
              : 255;
          return Color.fromARGB(a, r, g, b);
        }
      }

      // Named colors
      return _namedColors[colorStr.toLowerCase()];
    }
    return null;
  }

  static EdgeInsets? _parseEdgeInsets(dynamic value) {
    if (value == null) return null;

    if (value is Map) {
      return EdgeInsets.only(
        top: parseDouble(value['top']) ?? 0,
        right: parseDouble(value['right']) ?? 0,
        bottom: parseDouble(value['bottom']) ?? 0,
        left: parseDouble(value['left']) ?? 0,
      );
    }

    if (value is String || value is num) {
      final parts = value.toString().split(RegExp(r'\s+'));
      if (parts.length == 1) {
        final val = parseDouble(parts[0]) ?? 0;
        return EdgeInsets.all(val);
      } else if (parts.length == 2) {
        final v = parseDouble(parts[0]) ?? 0;
        final h = parseDouble(parts[1]) ?? 0;
        return EdgeInsets.symmetric(vertical: v, horizontal: h);
      } else if (parts.length == 4) {
        return EdgeInsets.only(
          top: parseDouble(parts[0]) ?? 0,
          right: parseDouble(parts[1]) ?? 0,
          bottom: parseDouble(parts[2]) ?? 0,
          left: parseDouble(parts[3]) ?? 0,
        );
      }
    }

    return null;
  }

  static AlignmentGeometry? parseAlignment(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'center':
          return Alignment.center;
        case 'topleft':
        case 'top-left':
          return Alignment.topLeft;
        case 'topcenter':
        case 'top-center':
          return Alignment.topCenter;
        case 'topright':
        case 'top-right':
          return Alignment.topRight;
        case 'centerleft':
        case 'center-left':
          return Alignment.centerLeft;
        case 'centerright':
        case 'center-right':
          return Alignment.centerRight;
        case 'bottomleft':
        case 'bottom-left':
          return Alignment.bottomLeft;
        case 'bottomcenter':
        case 'bottom-center':
          return Alignment.bottomCenter;
        case 'bottomright':
        case 'bottom-right':
          return Alignment.bottomRight;
      }
    }
    return null;
  }

  static BorderRadius? _parseBorderRadius(dynamic value) {
    if (value == null) return null;
    final radius = parseDouble(value);
    if (radius != null) {
      return BorderRadius.circular(radius);
    }
    return null;
  }

  static Border? _parseBorder(dynamic value) {
    if (value == null) return null;

    if (value is Map) {
      return Border(
        top: _parseBorderSide(value['top']) ?? BorderSide.none,
        right: _parseBorderSide(value['right']) ?? BorderSide.none,
        bottom: _parseBorderSide(value['bottom']) ?? BorderSide.none,
        left: _parseBorderSide(value['left']) ?? BorderSide.none,
      );
    }

    return null;
  }

  static BorderSide? _parseBorderSide(dynamic value) {
    if (value == null) return null;
    if (value is Map) {
      return BorderSide(
        color: parseColor(value['color']) ?? Colors.black,
        width: parseDouble(value['width']) ?? 1.0,
      );
    }
    return null;
  }

  static FontWeight? _parseFontWeight(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'bold':
          return FontWeight.bold;
        case 'normal':
          return FontWeight.normal;
        case 'light':
          return FontWeight.w300;
        case '100':
          return FontWeight.w100;
        case '200':
          return FontWeight.w200;
        case '300':
          return FontWeight.w300;
        case '400':
          return FontWeight.w400;
        case '500':
          return FontWeight.w500;
        case '600':
          return FontWeight.w600;
        case '700':
          return FontWeight.w700;
        case '800':
          return FontWeight.w800;
        case '900':
          return FontWeight.w900;
      }
    }
    if (value is int) {
      return FontWeight.values[(value ~/ 100).clamp(1, 9) - 1];
    }
    return null;
  }

  static FontStyle? _parseFontStyle(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'italic':
          return FontStyle.italic;
        case 'normal':
          return FontStyle.normal;
      }
    }
    return null;
  }

  static TextAlign? _parseTextAlign(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'left':
          return TextAlign.left;
        case 'right':
          return TextAlign.right;
        case 'center':
          return TextAlign.center;
        case 'justify':
          return TextAlign.justify;
        case 'start':
          return TextAlign.start;
        case 'end':
          return TextAlign.end;
      }
    }
    return null;
  }

  static TextDecoration? _parseTextDecoration(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'underline':
          return TextDecoration.underline;
        case 'overline':
          return TextDecoration.overline;
        case 'line-through':
        case 'linethrough':
          return TextDecoration.lineThrough;
        case 'none':
          return TextDecoration.none;
      }
    }
    return null;
  }

  static TextOverflow? _parseTextOverflow(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'ellipsis':
          return TextOverflow.ellipsis;
        case 'clip':
          return TextOverflow.clip;
        case 'fade':
          return TextOverflow.fade;
        case 'visible':
          return TextOverflow.visible;
      }
    }
    return null;
  }

  static Overflow? _parseOverflow(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'visible':
          return Overflow.visible;
        case 'clip':
          return Overflow.clip;
      }
    }
    return null;
  }

  static BoxFit? _parseBoxFit(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'fill':
          return BoxFit.fill;
        case 'contain':
          return BoxFit.contain;
        case 'cover':
          return BoxFit.cover;
        case 'fitwidth':
        case 'fit-width':
          return BoxFit.fitWidth;
        case 'fitheight':
        case 'fit-height':
          return BoxFit.fitHeight;
        case 'none':
          return BoxFit.none;
        case 'scaledown':
        case 'scale-down':
          return BoxFit.scaleDown;
      }
    }
    return null;
  }

  static List<BoxShadow>? _parseBoxShadow(dynamic value) {
    if (value == null) return null;
    if (value is List) {
      return value.map((shadow) {
        if (shadow is Map) {
          return BoxShadow(
            color: parseColor(shadow['color']) ?? Colors.black26,
            offset: parseOffset(shadow['offset']) ?? Offset.zero,
            blurRadius:
                parseDouble(shadow['blurRadius'] ?? shadow['blur']) ?? 0,
            spreadRadius:
                parseDouble(shadow['spreadRadius'] ?? shadow['spread']) ?? 0,
          );
        }
        return const BoxShadow();
      }).toList();
    }
    return null;
  }

  static List<Shadow>? _parseTextShadow(dynamic value) {
    if (value == null) return null;
    if (value is List) {
      return value.map((shadow) {
        if (shadow is Map) {
          return Shadow(
            color: parseColor(shadow['color']) ?? Colors.black26,
            offset: parseOffset(shadow['offset']) ?? Offset.zero,
            blurRadius:
                parseDouble(shadow['blurRadius'] ?? shadow['blur']) ?? 0,
          );
        }
        return const Shadow();
      }).toList();
    }
    return null;
  }

  static Offset? parseOffset(dynamic value) {
    if (value == null) return null;
    if (value is Map) {
      return Offset(
        parseDouble(value['x']) ?? 0,
        parseDouble(value['y']) ?? 0,
      );
    }
    return null;
  }

  static Matrix4? _parseTransform(dynamic value) {
    // Simplified transform parsing
    return null;
  }

  static Gradient? _parseGradient(dynamic value) {
    if (value == null) return null;
    if (value is Map) {
      final type = value['type'] as String?;
      final colors = (value['colors'] as List?)
          ?.map((c) => parseColor(c) ?? Colors.transparent)
          .toList();

      if (colors != null && colors.isNotEmpty) {
        if (type == 'linear') {
          return LinearGradient(
            colors: colors,
            begin: parseAlignment(value['begin']) as Alignment? ??
                Alignment.topCenter,
            end: parseAlignment(value['end']) as Alignment? ??
                Alignment.bottomCenter,
          );
        } else if (type == 'radial') {
          return RadialGradient(
            colors: colors,
            center: parseAlignment(value['center']) as Alignment? ??
                Alignment.center,
          );
        }
      }
    }
    return null;
  }

  static Duration? _parseDuration(dynamic value) {
    if (value == null) return null;
    if (value is int) return Duration(milliseconds: value);
    if (value is String) {
      final ms = int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), ''));
      if (ms != null) return Duration(milliseconds: ms);
    }
    return null;
  }

  static Curve? _parseCurve(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'linear':
          return Curves.linear;
        case 'ease':
          return Curves.ease;
        case 'easein':
        case 'ease-in':
          return Curves.easeIn;
        case 'easeout':
        case 'ease-out':
          return Curves.easeOut;
        case 'easeinout':
        case 'ease-in-out':
          return Curves.easeInOut;
        case 'bounce':
          return Curves.bounceIn;
      }
    }
    return null;
  }

  static final Map<String, Color> _namedColors = {
    'transparent': Colors.transparent,
    'black': Colors.black,
    'white': Colors.white,
    'red': Colors.red,
    'green': Colors.green,
    'blue': Colors.blue,
    'yellow': Colors.yellow,
    'orange': Colors.orange,
    'purple': Colors.purple,
    'pink': Colors.pink,
    'grey': Colors.grey,
    'gray': Colors.grey,
    'brown': Colors.brown,
    'cyan': Colors.cyan,
    'indigo': Colors.indigo,
    'lime': Colors.lime,
    'teal': Colors.teal,
  };
}
