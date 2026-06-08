import 'dart:collection';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../models/css_style.dart';

class CSSParser {
  // D1: memoize parsing. CSS is otherwise re-parsed for every element on every
  // build (regex color/gradient/shadow scans included). The result CSSStyle is
  // immutable and `parse` is pure, so caching keyed by the (deeply-equal) style
  // map is safe. Bounded to avoid unbounded growth on highly dynamic styles.
  static const int _maxCacheSize = 512;
  static const MapEquality<String, dynamic> _mapEquality = MapEquality();
  static final LinkedHashMap<Map<String, dynamic>, CSSStyle> _cache =
      LinkedHashMap<Map<String, dynamic>, CSSStyle>(
    equals: _mapEquality.equals,
    hashCode: _mapEquality.hash,
  );

  /// Visible for testing/diagnostics.
  static int get cacheSize => _cache.length;

  /// Clear the parse cache (e.g. for tests or after a global restyle).
  static void clearCache() => _cache.clear();

  static CSSStyle parse(Map<String, dynamic> styleMap) {
    // Viewport-relative units (`%`, `vw`, `vh`, `vmin`, `vmax`) resolve against
    // the live screen size, so their parsed result must never be cached: it
    // would go stale across devices and on rotate/resize. Parse them fresh.
    if (_hasViewportUnits(styleMap)) {
      return _parseUncached(styleMap);
    }

    final cached = _cache[styleMap];
    if (cached != null) {
      // Promote to most-recently-used (LinkedHashMap keeps insertion order).
      _cache.remove(styleMap);
      _cache[styleMap] = cached;
      return cached;
    }

    final style = _parseUncached(styleMap);

    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first); // evict least-recently-used
    }
    // Store a defensive copy of the key so later mutation of the caller's map
    // cannot corrupt the cache's hashing.
    _cache[Map<String, dynamic>.of(styleMap)] = style;
    return style;
  }

  static CSSStyle _parseUncached(Map<String, dynamic> styleMap) {
    return CSSStyle(
      width: parseDimension(styleMap['width'], isWidth: true),
      height: parseDimension(styleMap['height'], isWidth: false),
      minWidth: parseDimension(styleMap['minWidth'] ?? styleMap['min-width'], isWidth: true),
      maxWidth: parseDimension(styleMap['maxWidth'] ?? styleMap['max-width'], isWidth: true),
      minHeight: parseDimension(styleMap['minHeight'] ?? styleMap['min-height'], isWidth: false),
      maxHeight: parseDimension(styleMap['maxHeight'] ?? styleMap['max-height'], isWidth: false),
      padding: _parseEdgeInsets(styleMap['padding']),
      margin: _parseEdgeInsets(styleMap['margin']),
      alignment: parseAlignment(styleMap['alignment']),
      position: styleMap['position'] as String?,
      top: parseDimension(styleMap['top'], isWidth: false),
      right: parseDimension(styleMap['right'], isWidth: true),
      bottom: parseDimension(styleMap['bottom'], isWidth: false),
      left: parseDimension(styleMap['left'], isWidth: true),
      zIndex: parseDouble(styleMap['zIndex'] ?? styleMap['z-index']),
      display: styleMap['display'] as String?,
      flexDirection:
          styleMap['flexDirection'] ?? styleMap['flex-direction'] as String?,
      justifyContent:
          styleMap['justifyContent'] ?? styleMap['justify-content'] as String?,
      alignItems: styleMap['alignItems'] ?? styleMap['align-items'] as String?,
      flex: parseInt(styleMap['flex']),
      overflow: _parseOverflow(styleMap['overflow']),
      overflowX: _parseOverflow(styleMap['overflowX'] ?? styleMap['overflow-x']),
      overflowY: _parseOverflow(styleMap['overflowY'] ?? styleMap['overflow-y']),
      // CSS `background` shorthand: a `linear-gradient(...)`/`radial-gradient(...)`
      // value resolves to a gradient, any other value to a solid colour. Without
      // this the engine only honoured the explicit `gradient`/`backgroundColor`
      // keys, so every `background: linear-gradient(...)` (the app's primary way
      // of styling bars, cards, buttons, tabs) was silently dropped — flat UI.
      backgroundColor: parseColor(
              styleMap['backgroundColor'] ?? styleMap['background-color']) ??
          (_isGradientValue(styleMap['background'])
              ? null
              : parseColor(styleMap['background'])),
      backgroundImage: styleMap['backgroundImage'] ??
          styleMap['background-image'] as String?,
      backgroundSize: _parseBoxFit(
          styleMap['backgroundSize'] ?? styleMap['background-size']),
      backgroundPosition: parseAlignment(
          styleMap['backgroundPosition'] ?? styleMap['background-position']),
      gradient: _parseGradient(styleMap['gradient']) ??
          (_isGradientValue(styleMap['background'])
              ? _parseGradient(styleMap['background'])
              : null),
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
      rowGap: parseDouble(styleMap['rowGap'] ?? styleMap['row-gap']),
      columnGap: parseDouble(styleMap['columnGap'] ?? styleMap['column-gap']),
      flexWrap: styleMap['flexWrap'] ?? styleMap['flex-wrap'] as String?,
      // CSS grid track definitions. The fields existed on CSSStyle but were
      // never read here, so every `display:grid` container fell through to a
      // plain vertical stack (finding #6). HtmlDiv now maps these to a
      // responsive Wrap.
      gridTemplateColumns: styleMap['gridTemplateColumns'] ??
          styleMap['grid-template-columns'] as String?,
      gridTemplateRows: styleMap['gridTemplateRows'] ??
          styleMap['grid-template-rows'] as String?,
      gridTemplateAreas: styleMap['gridTemplateAreas'] ??
          styleMap['grid-template-areas'] as String?,
      gridAutoColumns: styleMap['gridAutoColumns'] ??
          styleMap['grid-auto-columns'] as String?,
      gridAutoRows:
          styleMap['gridAutoRows'] ?? styleMap['grid-auto-rows'] as String?,
      gridAutoFlow:
          styleMap['gridAutoFlow'] ?? styleMap['grid-auto-flow'] as String?,
      gridColumnGap: parseDouble(
          styleMap['gridColumnGap'] ?? styleMap['grid-column-gap'] ??
              styleMap['columnGap'] ?? styleMap['column-gap']),
      gridRowGap: parseDouble(styleMap['gridRowGap'] ??
          styleMap['grid-row-gap'] ?? styleMap['rowGap'] ?? styleMap['row-gap']),
      gridGap: parseDouble(styleMap['gridGap'] ?? styleMap['grid-gap']),
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

  /// Parse a length value into logical pixels, resolving viewport-relative units
  /// against the live screen size:
  ///
  /// * `42`, `"42"`, `"42px"`  → `42`
  /// * `"100vw"` / `"100vh"`   → full screen width / height
  /// * `"50vmin"` / `"80vmax"` → percentage of the smaller / larger screen edge
  /// * `"100%"`                → full extent of the relevant axis ([isWidth]
  ///   selects width vs height)
  ///
  /// Without this, `replaceAll`-based parsing silently dropped the unit and read
  /// `"100vh"` as `100` *pixels*, so full-viewport containers (the city/world
  /// stage, full-screen panels) collapsed — a near-blank screen on phones, whose
  /// real viewport is nowhere near the desktop-ish fixed sizes that masked it.
  static double? parseDimension(dynamic value, {required bool isWidth}) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is! String) return null;

    final raw = value.trim();
    if (raw.isEmpty) return null;

    final numStr = raw.replaceAll(RegExp(r'[^0-9.\-]'), '');
    final n = double.tryParse(numStr);
    if (n == null) return null;

    final size = _viewportSize();
    if (raw.contains('vmin')) return n / 100.0 * math.min(size.width, size.height);
    if (raw.contains('vmax')) return n / 100.0 * math.max(size.width, size.height);
    if (raw.contains('vw')) return n / 100.0 * size.width;
    if (raw.contains('vh')) return n / 100.0 * size.height;
    if (raw.contains('%')) return n / 100.0 * (isWidth ? size.width : size.height);
    return n;
  }

  /// Dimension properties whose values flow through [parseDimension] and may use
  /// viewport-relative units.
  static const List<String> _dimensionKeys = [
    'width', 'height',
    'minWidth', 'min-width', 'maxWidth', 'max-width',
    'minHeight', 'min-height', 'maxHeight', 'max-height',
    'top', 'right', 'bottom', 'left',
  ];

  /// True when a *dimension* property uses a viewport-relative unit (`%`, `vw`,
  /// `vh`, `vmin`, `vmax`). Such results depend on the live screen size and must
  /// not be served from the (size-agnostic) parse cache. Scoped to dimension
  /// keys so the common `%` inside gradients/colors still caches normally.
  static bool _hasViewportUnits(Map<String, dynamic> styleMap) {
    for (final key in _dimensionKeys) {
      final value = styleMap[key];
      if (value is String &&
          (value.contains('%') ||
              value.contains('vw') ||
              value.contains('vh') ||
              value.contains('vmin') ||
              value.contains('vmax'))) {
        return true;
      }
    }
    return false;
  }

  /// Live logical screen size, with a sane mobile-portrait fallback for early
  /// frames / unit tests where no render view is attached yet.
  static Size _viewportSize() {
    try {
      final view = WidgetsBinding.instance.platformDispatcher.implicitView;
      if (view != null) {
        final physical = view.physicalSize;
        final dpr = view.devicePixelRatio;
        if (physical.width > 0 && physical.height > 0 && dpr > 0) {
          return Size(physical.width / dpr, physical.height / dpr);
        }
      }
    } catch (_) {
      // No binding (e.g. pure unit test) — fall through to the default.
    }
    return const Size(390, 844);
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
    'hidden': Overflow.hidden,
    'clip': Overflow.clip,
    // `auto`/`scroll` both produce a scrollable region (CSS distinguishes them
    // only by when the scrollbar appears, which Flutter handles automatically).
    'auto': Overflow.scroll,
    'scroll': Overflow.scroll,
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

  /// True when [value] is a CSS gradient function string.
  static bool _isGradientValue(dynamic value) =>
      value is String && value.contains('gradient(');

  /// Parse a CSS gradient string into a Flutter [Gradient].
  ///
  /// Supports `linear-gradient([<angle>deg | to <side>,] color [stop%], …)` and
  /// `radial-gradient(…, color, color)`. Colour stop percentages are honoured;
  /// the angle maps to begin/end alignments (rounded to the nearest 45°).
  static Gradient? _parseCssGradientString(String raw) {
    final s = raw.trim();
    final isRadial = s.startsWith('radial-gradient');
    final open = s.indexOf('(');
    final close = s.lastIndexOf(')');
    if (open < 0 || close <= open) return null;

    final parts = _splitTopLevelCommas(s.substring(open + 1, close));
    if (parts.isEmpty) return null;

    double? angleDeg;
    var colorParts = parts;
    final first = parts.first.trim();
    if (first.endsWith('deg')) {
      angleDeg = double.tryParse(first.substring(0, first.length - 3).trim());
      colorParts = parts.sublist(1);
    } else if (first.startsWith('to ')) {
      angleDeg = _angleForSideKeyword(first.substring(3).trim());
      colorParts = parts.sublist(1);
    }

    final colors = <Color>[];
    final stops = <double>[];
    for (final part in colorParts) {
      final t = part.trim();
      if (t.isEmpty) continue;
      final stopMatch = RegExp(r'\s+(-?\d+(?:\.\d+)?)%\s*$').firstMatch(t);
      var colorStr = t;
      double? stop;
      if (stopMatch != null) {
        stop = (double.tryParse(stopMatch.group(1)!) ?? 0) / 100.0;
        colorStr = t.substring(0, stopMatch.start).trim();
      }
      final color = parseColor(colorStr);
      if (color != null) {
        colors.add(color);
        if (stop != null) stops.add(stop.clamp(0.0, 1.0));
      }
    }

    if (colors.isEmpty) return null;
    if (colors.length == 1) colors.add(colors.first);
    final useStops = stops.length == colors.length ? stops : null;

    if (isRadial) {
      return RadialGradient(colors: colors, stops: useStops);
    }
    final (begin, end) = _beginEndForAngle(angleDeg ?? 180);
    return LinearGradient(colors: colors, begin: begin, end: end, stops: useStops);
  }

  /// Split on top-level commas only (commas inside `rgba(...)` etc. are kept).
  static List<String> _splitTopLevelCommas(String input) {
    final out = <String>[];
    var depth = 0;
    var start = 0;
    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        if (depth > 0) depth--;
      } else if (ch == ',' && depth == 0) {
        out.add(input.substring(start, i));
        start = i + 1;
      }
    }
    out.add(input.substring(start));
    return out;
  }

  static double _angleForSideKeyword(String side) {
    switch (side.replaceAll(RegExp(r'\s+'), ' ').trim()) {
      case 'top':
        return 0;
      case 'top right':
      case 'right top':
        return 45;
      case 'right':
        return 90;
      case 'bottom right':
      case 'right bottom':
        return 135;
      case 'bottom':
        return 180;
      case 'bottom left':
      case 'left bottom':
        return 225;
      case 'left':
        return 270;
      case 'top left':
      case 'left top':
        return 315;
      default:
        return 180;
    }
  }

  /// CSS gradient angle (0° = upward) → Flutter begin/end alignments, rounded to
  /// the nearest 45°.
  static (Alignment, Alignment) _beginEndForAngle(double deg) {
    final a = ((deg % 360) + 360) % 360;
    switch ((a / 45).round() % 8) {
      case 0: // to top
        return (Alignment.bottomCenter, Alignment.topCenter);
      case 1: // to top-right
        return (Alignment.bottomLeft, Alignment.topRight);
      case 2: // to right
        return (Alignment.centerLeft, Alignment.centerRight);
      case 3: // to bottom-right
        return (Alignment.topLeft, Alignment.bottomRight);
      case 4: // to bottom
        return (Alignment.topCenter, Alignment.bottomCenter);
      case 5: // to bottom-left
        return (Alignment.topRight, Alignment.bottomLeft);
      case 6: // to left
        return (Alignment.centerRight, Alignment.centerLeft);
      default: // to top-left
        return (Alignment.bottomRight, Alignment.topLeft);
    }
  }

  static Gradient? _parseGradient(dynamic value) {
    if (value == null) return null;
    if (value is Gradient) return value;
    // CSS string form, e.g. `linear-gradient(135deg, #F4C95B, #E0902F)`.
    if (value is String) return _parseCssGradientString(value);
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
      return value.whereType<Map<String, dynamic>>().toList();
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
