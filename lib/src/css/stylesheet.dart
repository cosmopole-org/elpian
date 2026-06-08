import '../models/css_style.dart';
import 'css_parser.dart';

/// CSS Stylesheet manager
class CSSStylesheet {
  final Map<String, Map<String, dynamic>> _rules = {};
  final Map<String, Map<String, dynamic>> _classRules = {};
  final Map<String, Map<String, dynamic>> _idRules = {};
  final List<CSSRule> _orderedRules = [];
  final Map<String, List<KeyframeFrame>> _keyframes = {};
  
  /// Parse CSS string
  void parseCSS(String cssString) {
    final lines = cssString.split('}');
    
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      
      final parts = line.split('{');
      if (parts.length != 2) continue;
      
      final selector = parts[0].trim();
      final declarations = parts[1].trim();
      
      final styles = _parseDeclarations(declarations);
      
      final rule = CSSRule(
        selector: selector,
        styles: styles,
      );
      
      _orderedRules.add(rule);
      
      _storeRuleByType(selector, styles);
    }
  }

  void _storeRuleByType(String selector, Map<String, dynamic> styles) {
    if (selector.startsWith('#')) {
      _idRules[selector.substring(1)] = styles;
    } else if (selector.startsWith('.')) {
      _classRules[selector.substring(1)] = styles;
    } else {
      _rules[selector] = styles;
    }
  }

  Map<String, dynamic> _parseDeclarations(String declarations) {
    final styles = <String, dynamic>{};
    final properties = declarations.split(';');
    
    for (final property in properties) {
      if (property.trim().isEmpty) continue;
      
      final parts = property.split(':');
      if (parts.length != 2) continue;
      
      final key = parts[0].trim();
      final value = parts[1].trim();
      
      styles[key] = _parseValue(key, value);
    }
    
    return styles;
  }
  
  dynamic _parseValue(String property, String value) {
    // Handle numeric values
    if (RegExp(r'^\d+(\.\d+)?(px|em|rem|%)?$').hasMatch(value)) {
      final numStr = value.replaceAll(RegExp(r'[^0-9.]'), '');
      return double.tryParse(numStr) ?? value;
    }
    
    // Return as string for complex values
    return value;
  }
  
  /// Add a CSS rule
  void addRule(String selector, Map<String, dynamic> styles) {
    final rule = CSSRule(
      selector: selector,
      styles: styles,
    );
    
    _orderedRules.add(rule);
    _storeRuleByType(selector, styles);
  }

  /// Remove a rule by selector
  void removeRule(String selector) {
    _orderedRules.removeWhere((rule) => rule.selector == selector);
    
    if (selector.startsWith('#')) {
      _idRules.remove(selector.substring(1));
    } else if (selector.startsWith('.')) {
      _classRules.remove(selector.substring(1));
    } else {
      _rules.remove(selector);
    }
  }
  
  /// Build the merged raw style map for an element (cascade order), before
  /// parsing into a [CSSStyle]. Exposed so callers can merge further raw maps
  /// (e.g. inline styles) and parse exactly once — see [getComputedStyle].
  Map<String, dynamic> getComputedStyleMap({
    required String tagName,
    String? id,
    List<String>? classes,
    Map<String, dynamic>? inlineStyles,
  }) {
    final mergedStyles = <String, dynamic>{};

    // 1. Apply tag-based rules (lowest priority)
    final tagStyles = _rules[tagName];
    if (tagStyles != null) mergedStyles.addAll(tagStyles);

    // 2. Apply class-based rules
    if (classes != null) {
      for (final className in classes) {
        final classStyles = _classRules[className];
        if (classStyles != null) mergedStyles.addAll(classStyles);
      }
    }

    // 3. Apply ID-based rules (higher priority)
    if (id != null) {
      final idStyles = _idRules[id];
      if (idStyles != null) mergedStyles.addAll(idStyles);
    }

    // 4. Apply inline styles (highest priority)
    if (inlineStyles != null) {
      mergedStyles.addAll(inlineStyles);
    }

    return mergedStyles;
  }

  /// Get computed style for an element
  CSSStyle getComputedStyle({
    required String tagName,
    String? id,
    List<String>? classes,
    Map<String, dynamic>? inlineStyles,
  }) {
    // Parse is memoized in CSSParser, so repeated identical cascades are cheap.
    return CSSParser.parse(getComputedStyleMap(
      tagName: tagName,
      id: id,
      classes: classes,
      inlineStyles: inlineStyles,
    ));
  }
  
  /// Get style for a specific selector
  Map<String, dynamic>? getStyle(String selector) {
    if (selector.startsWith('#')) {
      return _idRules[selector.substring(1)];
    } else if (selector.startsWith('.')) {
      return _classRules[selector.substring(1)];
    } else {
      return _rules[selector];
    }
  }
  
  /// Export to CSS string
  String toCSS() {
    final buffer = StringBuffer();
    
    for (final rule in _orderedRules) {
      buffer.writeln(rule.toCSS());
    }
    
    return buffer.toString();
  }
  
  /// Clear all rules
  void clear() {
    _rules.clear();
    _classRules.clear();
    _idRules.clear();
    _orderedRules.clear();
  }
  
  /// Get all rules
  List<CSSRule> get rules => List.unmodifiable(_orderedRules);

  /// Register a keyframe animation
  void addKeyframeAnimation(String name, List<KeyframeFrame> frames) {
    _keyframes[name] = frames;
  }

  /// Get keyframe animation by name
  List<KeyframeFrame>? getKeyframes(String name) => _keyframes[name];

  /// Get all keyframe names
  Set<String> get keyframeNames => _keyframes.keys.toSet();
}

/// Represents a single CSS rule
class CSSRule {
  final String selector;
  final Map<String, dynamic> styles;
  
  CSSRule({
    required this.selector,
    required this.styles,
  });
  
  String toCSS() {
    final buffer = StringBuffer();
    buffer.writeln('$selector {');
    
    styles.forEach((key, value) {
      buffer.writeln('  $key: $value;');
    });
    
    buffer.writeln('}');
    return buffer.toString();
  }
  
  @override
  String toString() => toCSS();
}

/// Media query support
class MediaQuery {
  final String query;
  final CSSStylesheet stylesheet;
  
  MediaQuery({
    required this.query,
    required this.stylesheet,
  });
  
  static final _dimensionPattern = RegExp(r'(min|max)-(width|height):\s*(\d+)');

  bool matches(double width, double height) {
    for (final match in _dimensionPattern.allMatches(query)) {
      final isMin = match.group(1) == 'min';
      final isWidth = match.group(2) == 'width';
      final threshold = double.parse(match.group(3)!);
      final actual = isWidth ? width : height;
      if (isMin && actual < threshold) return false;
      if (!isMin && actual > threshold) return false;
    }
    return true;
  }
}

/// Represents a single keyframe frame with offset and styles
class KeyframeFrame {
  final double offset; // 0.0 to 1.0
  final Map<String, dynamic> styles;

  KeyframeFrame({
    required this.offset,
    required this.styles,
  });
}

/// Global stylesheet manager
class GlobalStylesheetManager {
  static final GlobalStylesheetManager _instance = GlobalStylesheetManager._internal();
  factory GlobalStylesheetManager() => _instance;
  GlobalStylesheetManager._internal();
  
  final CSSStylesheet _globalStylesheet = CSSStylesheet();
  final List<MediaQuery> _mediaQueries = [];
  
  CSSStylesheet get global => _globalStylesheet;
  
  void addMediaQuery(String query, CSSStylesheet stylesheet) {
    // Dedupe by query so re-applying the same theme on every render (the
    // server-driven host re-loads the stylesheet each build) can't accumulate
    // duplicate media queries unboundedly.
    _mediaQueries.removeWhere((mq) => mq.query == query);
    _mediaQueries.add(MediaQuery(
      query: query,
      stylesheet: stylesheet,
    ));
  }
  
  /// Build the merged **raw** style map for an element (global + matching
  /// `@media` + inline cascade), before parsing. Lets callers merge further raw
  /// maps and parse exactly once.
  ///
  /// Cascade order (lowest → highest priority): global rules, then any matching
  /// media-query rules (evaluated against the live viewport when no explicit
  /// screen size is given), then inline styles. The whole **raw** map is carried
  /// through — previously only six properties survived, which silently dropped
  /// every class-based `width`/`position`/`border`/`boxShadow`/gradient/flex.
  ///
  /// CSS `!important` is honoured: an important declaration outranks every
  /// normal one, *including inline styles*. This is what lets a responsive
  /// `@media` rule (e.g. the mobile `.game-window` full-screen override) beat
  /// the element's own inline `position/left/top` — without it the inline drag
  /// offset always won and panels never went full-screen on phones. We do two
  /// passes: normal declarations in cascade order, then important declarations
  /// in cascade order on top. The `!important` flag is stripped from the value
  /// either way so it still parses.
  Map<String, dynamic> getComputedStyleMap({
    required String tagName,
    String? id,
    List<String>? classes,
    Map<String, dynamic>? inlineStyles,
    double? screenWidth,
    double? screenHeight,
  }) {
    final mergedStyles = <String, dynamic>{};
    final importantStyles = <String, dynamic>{};

    void mergeRaw(Map<String, dynamic>? raw) {
      if (raw == null) return;
      for (final entry in raw.entries) {
        final stripped = CSSParser.stripImportant(entry.value);
        // Normal layer: applied in cascade order (later wins).
        mergedStyles[entry.key] = stripped;
        // Important layer: collected separately so it can override the normal
        // layer (incl. inline) afterwards, also in cascade order (later wins).
        if (CSSParser.isImportant(entry.value)) {
          importantStyles[entry.key] = stripped;
        }
      }
    }

    // 1. Global rules — the full raw cascade (tag + class + id), every property.
    mergeRaw(_globalStylesheet.getComputedStyleMap(
      tagName: tagName,
      id: id,
      classes: classes,
    ));

    // 2. Matching `@media` rules. Default to the live viewport so responsive
    //    rules work without the caller having to thread a screen size through.
    if (_mediaQueries.isNotEmpty) {
      final size = CSSParser.viewportSize();
      final w = screenWidth ?? size.width;
      final h = screenHeight ?? size.height;
      for (final mediaQuery in _mediaQueries) {
        if (mediaQuery.matches(w, h)) {
          // Resolve against the SAME element (tag + class + id), so class/id
          // media rules (e.g. `.game-window`) match, not just bare tags.
          mergeRaw(mediaQuery.stylesheet.getComputedStyleMap(
            tagName: tagName,
            id: id,
            classes: classes,
          ));
        }
      }
    }

    // 3. Inline styles win — among *normal* declarations.
    if (inlineStyles != null) {
      mergeRaw(inlineStyles);
    }

    // 4. `!important` declarations override the normal layer (incl. inline).
    mergedStyles.addAll(importantStyles);

    return mergedStyles;
  }

  CSSStyle getComputedStyle({
    required String tagName,
    String? id,
    List<String>? classes,
    Map<String, dynamic>? inlineStyles,
    double? screenWidth,
    double? screenHeight,
  }) {
    return CSSParser.parse(getComputedStyleMap(
      tagName: tagName,
      id: id,
      classes: classes,
      inlineStyles: inlineStyles,
      screenWidth: screenWidth,
      screenHeight: screenHeight,
    ));
  }
  
  void clear() {
    _globalStylesheet.clear();
    _mediaQueries.clear();
  }
}
