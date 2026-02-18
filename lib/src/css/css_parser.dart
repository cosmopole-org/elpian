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

  static FontWeight? _parseFontWeight(dynamic value) {
    if (value == null) return null;
    if (value is FontWeight) return value;
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
        case 'w100':
          return FontWeight.w100;
        case 'w200':
          return FontWeight.w200;
        case 'w300':
          return FontWeight.w300;
        case 'w400':
          return FontWeight.w400;
        case 'w500':
          return FontWeight.w500;
        case 'w600':
          return FontWeight.w600;
        case 'w700':
          return FontWeight.w700;
        case 'w800':
          return FontWeight.w800;
        case 'w900':
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
    if (value is TextAlign) return value;
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

  static Curve? parseCurve(dynamic value) {
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
        case 'bouncein':
        case 'bounce-in':
          return Curves.bounceIn;
        case 'bounceout':
        case 'bounce-out':
          return Curves.bounceOut;
        case 'bounceinout':
        case 'bounce-in-out':
          return Curves.bounceInOut;
        case 'elastic':
        case 'elasticin':
        case 'elastic-in':
          return Curves.elasticIn;
        case 'elasticout':
        case 'elastic-out':
          return Curves.elasticOut;
        case 'elasticinout':
        case 'elastic-in-out':
          return Curves.elasticInOut;
        case 'decelerate':
          return Curves.decelerate;
        case 'fastoutslowin':
        case 'fast-out-slow-in':
          return Curves.fastOutSlowIn;
        case 'slowmiddle':
        case 'slow-middle':
          return Curves.slowMiddle;
        case 'easeincubic':
        case 'ease-in-cubic':
          return Curves.easeInCubic;
        case 'easeoutcubic':
        case 'ease-out-cubic':
          return Curves.easeOutCubic;
        case 'easeinoutcubic':
        case 'ease-in-out-cubic':
          return Curves.easeInOutCubic;
        case 'easeinquart':
        case 'ease-in-quart':
          return Curves.easeInQuart;
        case 'easeoutquart':
        case 'ease-out-quart':
          return Curves.easeOutQuart;
        case 'easeinoutquart':
        case 'ease-in-out-quart':
          return Curves.easeInOutQuart;
        case 'easeinquint':
        case 'ease-in-quint':
          return Curves.easeInQuint;
        case 'easeoutquint':
        case 'ease-out-quint':
          return Curves.easeOutQuint;
        case 'easeinoutquint':
        case 'ease-in-out-quint':
          return Curves.easeInOutQuint;
        case 'easeinexpo':
        case 'ease-in-expo':
          return Curves.easeInExpo;
        case 'easeoutexpo':
        case 'ease-out-expo':
          return Curves.easeOutExpo;
        case 'easeinoutexpo':
        case 'ease-in-out-expo':
          return Curves.easeInOutExpo;
        case 'easeincirc':
        case 'ease-in-circ':
          return Curves.easeInCirc;
        case 'easeoutcirc':
        case 'ease-out-circ':
          return Curves.easeOutCirc;
        case 'easeinoutcirc':
        case 'ease-in-out-circ':
          return Curves.easeInOutCirc;
        case 'easeinback':
        case 'ease-in-back':
          return Curves.easeInBack;
        case 'easeoutback':
        case 'ease-out-back':
          return Curves.easeOutBack;
        case 'easeinoutback':
        case 'ease-in-out-back':
          return Curves.easeInOutBack;
      }
    }
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
