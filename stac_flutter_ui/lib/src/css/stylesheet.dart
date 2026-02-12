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
      
      // Store by selector type
      if (selector.startsWith('#')) {
        _idRules[selector.substring(1)] = styles;
      } else if (selector.startsWith('.')) {
        _classRules[selector.substring(1)] = styles;
      } else {
        _rules[selector] = styles;
      }
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
    
    if (selector.startsWith('#')) {
      _idRules[selector.substring(1)] = styles;
    } else if (selector.startsWith('.')) {
      _classRules[selector.substring(1)] = styles;
    } else {
      _rules[selector] = styles;
    }
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
  
  /// Get computed style for an element
  CSSStyle getComputedStyle({
    required String tagName,
    String? id,
    List<String>? classes,
    Map<String, dynamic>? inlineStyles,
  }) {
    final mergedStyles = <String, dynamic>{};
    
    // 1. Apply tag-based rules (lowest priority)
    if (_rules.containsKey(tagName)) {
      mergedStyles.addAll(_rules[tagName]!);
    }
    
    // 2. Apply class-based rules
    if (classes != null) {
      for (final className in classes) {
        if (_classRules.containsKey(className)) {
          mergedStyles.addAll(_classRules[className]!);
        }
      }
    }
    
    // 3. Apply ID-based rules (higher priority)
    if (id != null && _idRules.containsKey(id)) {
      mergedStyles.addAll(_idRules[id]!);
    }
    
    // 4. Apply inline styles (highest priority)
    if (inlineStyles != null) {
      mergedStyles.addAll(inlineStyles);
    }
    
    // Parse merged styles
    return CSSParser.parse(mergedStyles);
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
  
  bool matches(double width, double height) {
    // Simple media query matching
    if (query.contains('min-width')) {
      final match = RegExp(r'min-width:\s*(\d+)').firstMatch(query);
      if (match != null) {
        final minWidth = double.parse(match.group(1)!);
        if (width < minWidth) return false;
      }
    }
    
    if (query.contains('max-width')) {
      final match = RegExp(r'max-width:\s*(\d+)').firstMatch(query);
      if (match != null) {
        final maxWidth = double.parse(match.group(1)!);
        if (width > maxWidth) return false;
      }
    }
    
    if (query.contains('min-height')) {
      final match = RegExp(r'min-height:\s*(\d+)').firstMatch(query);
      if (match != null) {
        final minHeight = double.parse(match.group(1)!);
        if (height < minHeight) return false;
      }
    }
    
    if (query.contains('max-height')) {
      final match = RegExp(r'max-height:\s*(\d+)').firstMatch(query);
      if (match != null) {
        final maxHeight = double.parse(match.group(1)!);
        if (height > maxHeight) return false;
      }
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
    _mediaQueries.add(MediaQuery(
      query: query,
      stylesheet: stylesheet,
    ));
  }
  
  CSSStyle getComputedStyle({
    required String tagName,
    String? id,
    List<String>? classes,
    Map<String, dynamic>? inlineStyles,
    double? screenWidth,
    double? screenHeight,
  }) {
    final mergedStyles = <String, dynamic>{};
    
    // Start with global styles
    _globalStylesheet.getComputedStyle(
      tagName: tagName,
      id: id,
      classes: classes,
      inlineStyles: null,
    );
    
    // Add media query styles
    if (screenWidth != null && screenHeight != null) {
      for (final mediaQuery in _mediaQueries) {
        if (mediaQuery.matches(screenWidth, screenHeight)) {
          final mqStyles = mediaQuery.stylesheet.getStyle(tagName);
          if (mqStyles != null) {
            mergedStyles.addAll(mqStyles);
          }
        }
      }
    }
    
    // Add inline styles last
    if (inlineStyles != null) {
      mergedStyles.addAll(inlineStyles);
    }
    
    return CSSParser.parse(mergedStyles);
  }
  
  void clear() {
    _globalStylesheet.clear();
    _mediaQueries.clear();
  }
}
