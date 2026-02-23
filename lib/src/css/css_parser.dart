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
      transitionDuration: parseDuration(
          styleMap['transitionDuration'] ?? styleMap['transition-duration']),
      transitionCurve: parseCurve(
          styleMap['transitionCurve'] ?? styleMap['transition-curve']),
      transitionProperty:
          styleMap['transitionProperty'] ?? styleMap['transition-property'] as String?,
      transitionDelay: parseDuration(
          styleMap['transitionDelay'] ?? styleMap['transition-delay']),
      animationName:
          styleMap['animationName'] ?? styleMap['animation-name'] as String?,
      animationDuration: parseDuration(
          styleMap['animationDuration'] ?? styleMap['animation-duration']),
      animationTimingFunction:
          styleMap['animationTimingFunction'] ?? styleMap['animation-timing-function'] as String?,
      animationDelay: parseDuration(
          styleMap['animationDelay'] ?? styleMap['animation-delay']),
      animationIterationCount: parseInt(
          styleMap['animationIterationCount'] ?? styleMap['animation-iteration-count']),
      animationDirection:
          styleMap['animationDirection'] ?? styleMap['animation-direction'] as String?,
      animationFillMode:
          styleMap['animationFillMode'] ?? styleMap['animation-fill-mode'] as String?,
      animationPlayState:
          styleMap['animationPlayState'] ?? styleMap['animation-play-state'] as String?,
      animateOnBuild: styleMap['animateOnBuild'] ?? styleMap['animate-on-build'] as bool?,
      staggerDelay: parseDuration(
          styleMap['staggerDelay'] ?? styleMap['stagger-delay']),
      staggerChildren: parseInt(
          styleMap['staggerChildren'] ?? styleMap['stagger-children']),
      animationFrom: parseDouble(
          styleMap['animationFrom'] ?? styleMap['animation-from']),
      animationTo: parseDouble(
          styleMap['animationTo'] ?? styleMap['animation-to']),
      slideBegin: parseOffset(
          styleMap['slideBegin'] ?? styleMap['slide-begin']),
      slideEnd: parseOffset(
          styleMap['slideEnd'] ?? styleMap['slide-end']),
      scaleBegin: parseDouble(
          styleMap['scaleBegin'] ?? styleMap['scale-begin']),
      scaleEnd: parseDouble(
          styleMap['scaleEnd'] ?? styleMap['scale-end']),
      rotationBegin: parseDouble(
          styleMap['rotationBegin'] ?? styleMap['rotation-begin']),
      rotationEnd: parseDouble(
          styleMap['rotationEnd'] ?? styleMap['rotation-end']),
      fadeBegin: parseDouble(
          styleMap['fadeBegin'] ?? styleMap['fade-begin']),
      fadeEnd: parseDouble(
          styleMap['fadeEnd'] ?? styleMap['fade-end']),
      colorBegin: parseColor(
          styleMap['colorBegin'] ?? styleMap['color-begin']),
      colorEnd: parseColor(
          styleMap['colorEnd'] ?? styleMap['color-end']),
      paddingBegin: _parseEdgeInsets(
          styleMap['paddingBegin'] ?? styleMap['padding-begin']),
      paddingEnd: _parseEdgeInsets(
          styleMap['paddingEnd'] ?? styleMap['padding-end']),
      alignmentBegin: parseAlignment(
          styleMap['alignmentBegin'] ?? styleMap['alignment-begin']),
      alignmentEnd: parseAlignment(
          styleMap['alignmentEnd'] ?? styleMap['alignment-end']),
      shimmerBaseColor: parseColor(
          styleMap['shimmerBaseColor'] ?? styleMap['shimmer-base-color']),
      shimmerHighlightColor: parseColor(
          styleMap['shimmerHighlightColor'] ?? styleMap['shimmer-highlight-color']),
      animationAutoReverse: styleMap['animationAutoReverse'] ?? styleMap['animation-auto-reverse'] as bool?,
      animationRepeat: styleMap['animationRepeat'] ?? styleMap['animation-repeat'] as bool?,
      keyframes: _parseKeyframes(styleMap['keyframes']),
    );
  }

  static double? parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      final numStr = value.replaceAll(RegExp(r'[^0-9.\-]'), '');
      return double.tryParse(numStr);
    }
    return null;
  }

  static int? parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      if (value.toLowerCase() == 'infinite') return -1;
      return int.tryParse(value);
    }
    return null;
  }

  static Color? parseColor(dynamic value) {
    if (value == null) return null;
    if (value is Color) return value;
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

      // HSL/HSLA
      if (colorStr.startsWith('hsl')) {
        final match =
            RegExp(r'hsla?\((\d+),\s*(\d+)%?,\s*(\d+)%?(?:,\s*([\d.]+))?\)')
                .firstMatch(colorStr);
        if (match != null) {
          final h = double.parse(match.group(1)!);
          final s = double.parse(match.group(2)!) / 100;
          final l = double.parse(match.group(3)!) / 100;
          final a = match.group(4) != null
              ? double.parse(match.group(4)!)
              : 1.0;
          return HSLColor.fromAHSL(a, h, s, l).toColor();
        }
      }

      // Named colors
      return _namedColors[colorStr.toLowerCase()];
    }
    return null;
  }

  static EdgeInsets? _parseEdgeInsets(dynamic value) {
    if (value == null) return null;
    if (value is EdgeInsets) return value;

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
      } else if (parts.length == 3) {
        final top = parseDouble(parts[0]) ?? 0;
        final h = parseDouble(parts[1]) ?? 0;
        final bottom = parseDouble(parts[2]) ?? 0;
        return EdgeInsets.only(
          top: top,
          right: h,
          bottom: bottom,
          left: h,
        );
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

  static const _alignmentMap = <String, Alignment>{
    'center': Alignment.center,
    'topleft': Alignment.topLeft,
    'top-left': Alignment.topLeft,
    'topcenter': Alignment.topCenter,
    'top-center': Alignment.topCenter,
    'topright': Alignment.topRight,
    'top-right': Alignment.topRight,
    'centerleft': Alignment.centerLeft,
    'center-left': Alignment.centerLeft,
    'centerright': Alignment.centerRight,
    'center-right': Alignment.centerRight,
    'bottomleft': Alignment.bottomLeft,
    'bottom-left': Alignment.bottomLeft,
    'bottomcenter': Alignment.bottomCenter,
    'bottom-center': Alignment.bottomCenter,
    'bottomright': Alignment.bottomRight,
    'bottom-right': Alignment.bottomRight,
  };

  static AlignmentGeometry? parseAlignment(dynamic value) {
    if (value == null) return null;
    if (value is String) return _alignmentMap[value.toLowerCase()];
    if (value is Map) {
      final x = parseDouble(value['x']) ?? 0.0;
      final y = parseDouble(value['y']) ?? 0.0;
      return Alignment(x, y);
    }
    return null;
  }

  static BorderRadius? _parseBorderRadius(dynamic value) {
    if (value == null) return null;
    if (value is BorderRadius) return value;
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

  static const _fontWeightMap = <String, FontWeight>{
    'bold': FontWeight.bold,
    'normal': FontWeight.normal,
    'light': FontWeight.w300,
    '100': FontWeight.w100,
    '200': FontWeight.w200,
    '300': FontWeight.w300,
    '400': FontWeight.w400,
    '500': FontWeight.w500,
    '600': FontWeight.w600,
    '700': FontWeight.w700,
    '800': FontWeight.w800,
    '900': FontWeight.w900,
    'w100': FontWeight.w100,
    'w200': FontWeight.w200,
    'w300': FontWeight.w300,
    'w400': FontWeight.w400,
    'w500': FontWeight.w500,
    'w600': FontWeight.w600,
    'w700': FontWeight.w700,
    'w800': FontWeight.w800,
    'w900': FontWeight.w900,
  };

  static FontWeight? _parseFontWeight(dynamic value) {
    if (value == null) return null;
    if (value is FontWeight) return value;
    if (value is String) return _fontWeightMap[value.toLowerCase()];
    if (value is int) return FontWeight.values[(value ~/ 100).clamp(1, 9) - 1];
    return null;
  }

  static const _fontStyleMap = <String, FontStyle>{
    'italic': FontStyle.italic,
    'normal': FontStyle.normal,
  };

  static FontStyle? _parseFontStyle(dynamic value) {
    if (value == null) return null;
    if (value is String) return _fontStyleMap[value.toLowerCase()];
    return null;
  }

  static const _textAlignMap = <String, TextAlign>{
    'left': TextAlign.left,
    'right': TextAlign.right,
    'center': TextAlign.center,
    'justify': TextAlign.justify,
    'start': TextAlign.start,
    'end': TextAlign.end,
  };

  static TextAlign? _parseTextAlign(dynamic value) {
    if (value == null) return null;
    if (value is TextAlign) return value;
    if (value is String) return _textAlignMap[value.toLowerCase()];
    return null;
  }

  static const _textDecorationMap = <String, TextDecoration>{
    'underline': TextDecoration.underline,
    'overline': TextDecoration.overline,
    'line-through': TextDecoration.lineThrough,
    'linethrough': TextDecoration.lineThrough,
    'none': TextDecoration.none,
  };

  static TextDecoration? _parseTextDecoration(dynamic value) {
    if (value == null) return null;
    if (value is String) return _textDecorationMap[value.toLowerCase()];
    return null;
  }

  static const _textOverflowMap = <String, TextOverflow>{
    'ellipsis': TextOverflow.ellipsis,
    'clip': TextOverflow.clip,
    'fade': TextOverflow.fade,
    'visible': TextOverflow.visible,
  };

  static TextOverflow? _parseTextOverflow(dynamic value) {
    if (value == null) return null;
    if (value is String) return _textOverflowMap[value.toLowerCase()];
    return null;
  }

  static const _overflowMap = <String, Overflow>{
    'visible': Overflow.visible,
    'clip': Overflow.clip,
  };

  static Overflow? _parseOverflow(dynamic value) {
    if (value == null) return null;
    if (value is String) return _overflowMap[value.toLowerCase()];
    return null;
  }

  static const _boxFitMap = <String, BoxFit>{
    'fill': BoxFit.fill,
    'contain': BoxFit.contain,
    'cover': BoxFit.cover,
    'fitwidth': BoxFit.fitWidth,
    'fit-width': BoxFit.fitWidth,
    'fitheight': BoxFit.fitHeight,
    'fit-height': BoxFit.fitHeight,
    'none': BoxFit.none,
    'scaledown': BoxFit.scaleDown,
    'scale-down': BoxFit.scaleDown,
  };

  static BoxFit? _parseBoxFit(dynamic value) {
    if (value == null) return null;
    if (value is String) return _boxFitMap[value.toLowerCase()];
    return null;
  }

  static List<BoxShadow>? _parseBoxShadow(dynamic value) {
    if (value == null) return null;
    if (value is List<BoxShadow>) return value;
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
    if (value is List<Shadow>) return value;
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
        parseDouble(value['x'] ?? value['dx']) ?? 0,
        parseDouble(value['y'] ?? value['dy']) ?? 0,
      );
    }
    if (value is List && value.length == 2) {
      return Offset(
        parseDouble(value[0]) ?? 0,
        parseDouble(value[1]) ?? 0,
      );
    }
    return null;
  }

  static Matrix4? _parseTransform(dynamic value) {
    if (value == null) return null;
    if (value is List && value.length == 16) {
      return Matrix4.fromList(
        value.map((e) => (e as num).toDouble()).toList(),
      );
    }
    return null;
  }

  static Gradient? _parseGradient(dynamic value) {
    if (value == null) return null;
    if (value is Gradient) return value;
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
        } else if (type == 'sweep') {
          return SweepGradient(
            colors: colors,
            center: parseAlignment(value['center']) as Alignment? ??
                Alignment.center,
          );
        }
      }
    }
    return null;
  }

  static Duration? parseDuration(dynamic value) {
    if (value == null) return null;
    if (value is int) return Duration(milliseconds: value);
    if (value is double) return Duration(milliseconds: value.toInt());
    if (value is String) {
      final trimmed = value.trim().toLowerCase();
      // Support 's' suffix for seconds
      if (trimmed.endsWith('s') && !trimmed.endsWith('ms')) {
        final numStr = trimmed.substring(0, trimmed.length - 1);
        final seconds = double.tryParse(numStr);
        if (seconds != null) return Duration(milliseconds: (seconds * 1000).toInt());
      }
      // Support 'ms' suffix for milliseconds
      if (trimmed.endsWith('ms')) {
        final numStr = trimmed.substring(0, trimmed.length - 2);
        final ms = int.tryParse(numStr);
        if (ms != null) return Duration(milliseconds: ms);
      }
      final ms = int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), ''));
      if (ms != null) return Duration(milliseconds: ms);
    }
    return null;
  }

  static const _curveMap = <String, Curve>{
    'linear': Curves.linear,
    'ease': Curves.ease,
    'easein': Curves.easeIn,
    'ease-in': Curves.easeIn,
    'easeout': Curves.easeOut,
    'ease-out': Curves.easeOut,
    'easeinout': Curves.easeInOut,
    'ease-in-out': Curves.easeInOut,
    'bounce': Curves.bounceIn,
    'bouncein': Curves.bounceIn,
    'bounce-in': Curves.bounceIn,
    'bounceout': Curves.bounceOut,
    'bounce-out': Curves.bounceOut,
    'bounceinout': Curves.bounceInOut,
    'bounce-in-out': Curves.bounceInOut,
    'elastic': Curves.elasticIn,
    'elasticin': Curves.elasticIn,
    'elastic-in': Curves.elasticIn,
    'elasticout': Curves.elasticOut,
    'elastic-out': Curves.elasticOut,
    'elasticinout': Curves.elasticInOut,
    'elastic-in-out': Curves.elasticInOut,
    'decelerate': Curves.decelerate,
    'fastoutslowin': Curves.fastOutSlowIn,
    'fast-out-slow-in': Curves.fastOutSlowIn,
    'slowmiddle': Curves.slowMiddle,
    'slow-middle': Curves.slowMiddle,
    'easeincubic': Curves.easeInCubic,
    'ease-in-cubic': Curves.easeInCubic,
    'easeoutcubic': Curves.easeOutCubic,
    'ease-out-cubic': Curves.easeOutCubic,
    'easeinoutcubic': Curves.easeInOutCubic,
    'ease-in-out-cubic': Curves.easeInOutCubic,
    'easeinquart': Curves.easeInQuart,
    'ease-in-quart': Curves.easeInQuart,
    'easeoutquart': Curves.easeOutQuart,
    'ease-out-quart': Curves.easeOutQuart,
    'easeinoutquart': Curves.easeInOutQuart,
    'ease-in-out-quart': Curves.easeInOutQuart,
    'easeinquint': Curves.easeInQuint,
    'ease-in-quint': Curves.easeInQuint,
    'easeoutquint': Curves.easeOutQuint,
    'ease-out-quint': Curves.easeOutQuint,
    'easeinoutquint': Curves.easeInOutQuint,
    'ease-in-out-quint': Curves.easeInOutQuint,
    'easeinexpo': Curves.easeInExpo,
    'ease-in-expo': Curves.easeInExpo,
    'easeoutexpo': Curves.easeOutExpo,
    'ease-out-expo': Curves.easeOutExpo,
    'easeinoutexpo': Curves.easeInOutExpo,
    'ease-in-out-expo': Curves.easeInOutExpo,
    'easeincirc': Curves.easeInCirc,
    'ease-in-circ': Curves.easeInCirc,
    'easeoutcirc': Curves.easeOutCirc,
    'ease-out-circ': Curves.easeOutCirc,
    'easeinoutcirc': Curves.easeInOutCirc,
    'ease-in-out-circ': Curves.easeInOutCirc,
    'easeinback': Curves.easeInBack,
    'ease-in-back': Curves.easeInBack,
    'easeoutback': Curves.easeOutBack,
    'ease-out-back': Curves.easeOutBack,
    'easeinoutback': Curves.easeInOutBack,
    'ease-in-out-back': Curves.easeInOutBack,
  };

  static Curve? parseCurve(dynamic value) {
    if (value == null) return null;
    if (value is String) return _curveMap[value.toLowerCase()];
    return null;
  }

  static List<Map<String, dynamic>>? _parseKeyframes(dynamic value) {
    if (value == null) return null;
    if (value is List) {
      return value
          .where((item) => item is Map<String, dynamic>)
          .map((item) => item as Map<String, dynamic>)
          .toList();
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
    'amber': Colors.amber,
    'deeporange': Colors.deepOrange,
    'deep-orange': Colors.deepOrange,
    'deeppurple': Colors.deepPurple,
    'deep-purple': Colors.deepPurple,
    'lightblue': Colors.lightBlue,
    'light-blue': Colors.lightBlue,
    'lightgreen': Colors.lightGreen,
    'light-green': Colors.lightGreen,
    'bluegrey': Colors.blueGrey,
    'blue-grey': Colors.blueGrey,
  };
}
