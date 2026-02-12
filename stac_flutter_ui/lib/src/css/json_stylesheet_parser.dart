import 'package:flutter/material.dart';
import '../css/stylesheet.dart';

/// JSON-based CSS stylesheet parser
/// Allows defining stylesheets in JSON format
class JsonStylesheetParser {
  /// Parse a JSON stylesheet object
  /// 
  /// Format:
  /// {
  ///   "rules": [
  ///     {
  ///       "selector": ".my-class",
  ///       "styles": {
  ///         "backgroundColor": "#FF0000",
  ///         "padding": "16",
  ///         ...
  ///       }
  ///     }
  ///   ],
  ///   "mediaQueries": [
  ///     {
  ///       "query": "min-width: 768",
  ///       "rules": [...]
  ///     }
  ///   ]
  /// }
  static CSSStylesheet parseJsonStylesheet(Map<String, dynamic> json) {
    final stylesheet = CSSStylesheet();
    
    // Parse regular rules
    if (json.containsKey('rules') && json['rules'] is List) {
      final rules = json['rules'] as List;
      for (final rule in rules) {
        if (rule is Map<String, dynamic>) {
          _parseRule(rule, stylesheet);
        }
      }
    }
    
    // Parse media queries
    if (json.containsKey('mediaQueries') && json['mediaQueries'] is List) {
      final mediaQueries = json['mediaQueries'] as List;
      for (final mq in mediaQueries) {
        if (mq is Map<String, dynamic>) {
          _parseMediaQuery(mq, stylesheet);
        }
      }
    }
    
    // Parse variables (CSS custom properties)
    if (json.containsKey('variables') && json['variables'] is Map) {
      _parseVariables(json['variables'] as Map<String, dynamic>, stylesheet);
    }
    
    // Parse keyframes (animations)
    if (json.containsKey('keyframes') && json['keyframes'] is List) {
      final keyframes = json['keyframes'] as List;
      for (final kf in keyframes) {
        if (kf is Map<String, dynamic>) {
          _parseKeyframe(kf, stylesheet);
        }
      }
    }
    
    return stylesheet;
  }
  
  /// Parse a single rule
  static void _parseRule(Map<String, dynamic> rule, CSSStylesheet stylesheet) {
    final selector = rule['selector'] as String?;
    if (selector == null) return;
    
    final styles = rule['styles'] as Map<String, dynamic>?;
    if (styles == null) return;
    
    stylesheet.addRule(selector, styles);
  }
  
  /// Parse media query
  static void _parseMediaQuery(Map<String, dynamic> mq, CSSStylesheet stylesheet) {
    final query = mq['query'] as String?;
    if (query == null) return;
    
    final mqStylesheet = CSSStylesheet();
    
    if (mq.containsKey('rules') && mq['rules'] is List) {
      final rules = mq['rules'] as List;
      for (final rule in rules) {
        if (rule is Map<String, dynamic>) {
          _parseRule(rule, mqStylesheet);
        }
      }
    }
    
    GlobalStylesheetManager().addMediaQuery(query, mqStylesheet);
  }
  
  /// Parse CSS variables
  static void _parseVariables(Map<String, dynamic> variables, CSSStylesheet stylesheet) {
    // CSS variables are stored as custom properties
    final varStyles = <String, dynamic>{};
    variables.forEach((key, value) {
      varStyles['--$key'] = value;
    });
    
    stylesheet.addRule(':root', varStyles);
  }
  
  /// Parse keyframes for animations
  static void _parseKeyframe(Map<String, dynamic> keyframe, CSSStylesheet stylesheet) {
    final name = keyframe['name'] as String?;
    if (name == null) return;

    final frames = keyframe['frames'] as List?;
    if (frames != null) {
      final keyframeFrames = <KeyframeFrame>[];
      for (final frame in frames) {
        if (frame is Map<String, dynamic>) {
          final offset = frame['offset'] as num?;
          final styles = frame['styles'] as Map<String, dynamic>?;

          if (offset != null && styles != null) {
            keyframeFrames.add(KeyframeFrame(
              offset: offset.toDouble(),
              styles: styles,
            ));
            stylesheet.addRule('@keyframes $name $offset', styles);
          }
        }
      }
      stylesheet.addKeyframeAnimation(name, keyframeFrames);
    }
  }
  
  /// Parse JSON stylesheet from string
  static CSSStylesheet parseJsonString(String jsonString) {
    try {
      final json = Map<String, dynamic>.from(
        // In production, use dart:convert
        {} // Placeholder
      );
      return parseJsonStylesheet(json);
    } catch (e) {
      debugPrint('Error parsing JSON stylesheet: $e');
      return CSSStylesheet();
    }
  }
  
  /// Convert CSS text to JSON format
  static Map<String, dynamic> cssToJson(String cssText) {
    final rules = <Map<String, dynamic>>[];
    final lines = cssText.split('}');
    
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      
      final parts = line.split('{');
      if (parts.length != 2) continue;
      
      final selector = parts[0].trim();
      final declarations = parts[1].trim();
      
      final styles = <String, dynamic>{};
      final properties = declarations.split(';');
      
      for (final property in properties) {
        if (property.trim().isEmpty) continue;
        
        final propParts = property.split(':');
        if (propParts.length != 2) continue;
        
        final key = propParts[0].trim();
        final value = propParts[1].trim();
        
        styles[key] = _parseValue(key, value);
      }
      
      rules.add({
        'selector': selector,
        'styles': styles,
      });
    }
    
    return {'rules': rules};
  }
  
  /// Parse CSS value to appropriate type
  static dynamic _parseValue(String property, String value) {
    // Remove quotes if present
    if (value.startsWith('"') && value.endsWith('"')) {
      return value.substring(1, value.length - 1);
    }
    if (value.startsWith("'") && value.endsWith("'")) {
      return value.substring(1, value.length - 1);
    }
    
    // Try to parse as number
    final numMatch = RegExp(r'^-?\d+(\.\d+)?(px|em|rem|%)?$').firstMatch(value);
    if (numMatch != null) {
      final numStr = value.replaceAll(RegExp(r'[^0-9.-]'), '');
      final num = double.tryParse(numStr);
      if (num != null) return num;
    }
    
    // Return as string
    return value;
  }
  
  /// Create a complete stylesheet definition from JSON
  static Map<String, dynamic> createStylesheetDefinition({
    List<Map<String, dynamic>>? rules,
    List<Map<String, dynamic>>? mediaQueries,
    Map<String, dynamic>? variables,
    List<Map<String, dynamic>>? keyframes,
  }) {
    final definition = <String, dynamic>{};
    
    if (rules != null && rules.isNotEmpty) {
      definition['rules'] = rules;
    }
    
    if (mediaQueries != null && mediaQueries.isNotEmpty) {
      definition['mediaQueries'] = mediaQueries;
    }
    
    if (variables != null && variables.isNotEmpty) {
      definition['variables'] = variables;
    }
    
    if (keyframes != null && keyframes.isNotEmpty) {
      definition['keyframes'] = keyframes;
    }
    
    return definition;
  }
  
  /// Helper to create a rule
  static Map<String, dynamic> createRule(
    String selector,
    Map<String, dynamic> styles,
  ) {
    return {
      'selector': selector,
      'styles': styles,
    };
  }
  
  /// Helper to create a media query
  static Map<String, dynamic> createMediaQuery(
    String query,
    List<Map<String, dynamic>> rules,
  ) {
    return {
      'query': query,
      'rules': rules,
    };
  }
  
  /// Helper to create a keyframe animation
  static Map<String, dynamic> createKeyframe(
    String name,
    List<Map<String, dynamic>> frames,
  ) {
    return {
      'name': name,
      'frames': frames,
    };
  }
  
  /// Helper to create a keyframe frame
  static Map<String, dynamic> createFrame(
    num offset,
    Map<String, dynamic> styles,
  ) {
    return {
      'offset': offset,
      'styles': styles,
    };
  }
}

/// Extension for easy stylesheet parsing
extension StylesheetExtension on CSSStylesheet {
  /// Load stylesheet from JSON
  void loadFromJson(Map<String, dynamic> json) {
    final parsed = JsonStylesheetParser.parseJsonStylesheet(json);
    
    // Copy rules from parsed stylesheet
    for (final rule in parsed.rules) {
      addRule(rule.selector, rule.styles);
    }
  }
  
  /// Export stylesheet to JSON
  Map<String, dynamic> toJson() {
    final rules = <Map<String, dynamic>>[];
    
    for (final rule in this.rules) {
      rules.add({
        'selector': rule.selector,
        'styles': rule.styles,
      });
    }
    
    return {'rules': rules};
  }
}

/// Comprehensive JSON stylesheet builder
class JsonStylesheetBuilder {
  final List<Map<String, dynamic>> _rules = [];
  final List<Map<String, dynamic>> _mediaQueries = [];
  final Map<String, dynamic> _variables = {};
  final List<Map<String, dynamic>> _keyframes = [];
  
  /// Add a rule
  JsonStylesheetBuilder addRule(String selector, Map<String, dynamic> styles) {
    _rules.add(JsonStylesheetParser.createRule(selector, styles));
    return this;
  }
  
  /// Add multiple rules
  JsonStylesheetBuilder addRules(List<Map<String, dynamic>> rules) {
    _rules.addAll(rules);
    return this;
  }
  
  /// Add a media query
  JsonStylesheetBuilder addMediaQuery(
    String query,
    List<Map<String, dynamic>> rules,
  ) {
    _mediaQueries.add(JsonStylesheetParser.createMediaQuery(query, rules));
    return this;
  }
  
  /// Add CSS variable
  JsonStylesheetBuilder addVariable(String name, dynamic value) {
    _variables[name] = value;
    return this;
  }
  
  /// Add multiple variables
  JsonStylesheetBuilder addVariables(Map<String, dynamic> variables) {
    _variables.addAll(variables);
    return this;
  }
  
  /// Add keyframe animation
  JsonStylesheetBuilder addKeyframe(
    String name,
    List<Map<String, dynamic>> frames,
  ) {
    _keyframes.add(JsonStylesheetParser.createKeyframe(name, frames));
    return this;
  }
  
  /// Build the final JSON stylesheet
  Map<String, dynamic> build() {
    return JsonStylesheetParser.createStylesheetDefinition(
      rules: _rules.isNotEmpty ? _rules : null,
      mediaQueries: _mediaQueries.isNotEmpty ? _mediaQueries : null,
      variables: _variables.isNotEmpty ? _variables : null,
      keyframes: _keyframes.isNotEmpty ? _keyframes : null,
    );
  }
  
  /// Build and parse to CSSStylesheet
  CSSStylesheet buildStylesheet() {
    return JsonStylesheetParser.parseJsonStylesheet(build());
  }
  
  /// Clear all rules
  JsonStylesheetBuilder clear() {
    _rules.clear();
    _mediaQueries.clear();
    _variables.clear();
    _keyframes.clear();
    return this;
  }
}

/// Predefined common style patterns
class StylePresets {
  /// Flexbox center
  static Map<String, dynamic> get flexCenter => {
    'display': 'flex',
    'justifyContent': 'center',
    'alignItems': 'center',
  };
  
  /// Flexbox row
  static Map<String, dynamic> get flexRow => {
    'display': 'flex',
    'flexDirection': 'row',
  };
  
  /// Flexbox column
  static Map<String, dynamic> get flexColumn => {
    'display': 'flex',
    'flexDirection': 'column',
  };
  
  /// Card style
  static Map<String, dynamic> card({
    String? backgroundColor,
    double? padding,
    double? borderRadius,
  }) => {
    'backgroundColor': backgroundColor ?? '#FFFFFF',
    'padding': padding ?? 16,
    'borderRadius': borderRadius ?? 8,
    'boxShadow': [
      {
        'color': 'rgba(0,0,0,0.1)',
        'offset': {'x': 0, 'y': 2},
        'blur': 4,
      }
    ],
  };
  
  /// Button style
  static Map<String, dynamic> button({
    String? backgroundColor,
    String? color,
    double? padding,
  }) => {
    'backgroundColor': backgroundColor ?? '#2196F3',
    'color': color ?? '#FFFFFF',
    'padding': padding ?? 12,
    'borderRadius': 4,
    'cursor': 'pointer',
  };
  
  /// Text truncate
  static Map<String, dynamic> get textTruncate => {
    'textOverflow': 'ellipsis',
    'overflow': 'hidden',
    'whiteSpace': 'nowrap',
  };
  
  /// Absolute center
  static Map<String, dynamic> get absoluteCenter => {
    'position': 'absolute',
    'top': '50%',
    'left': '50%',
    'transform': 'translate(-50%, -50%)',
  };
  
  /// Full width/height
  static Map<String, dynamic> get fullSize => {
    'width': '100%',
    'height': '100%',
  };
  
  /// Shadow elevation
  static Map<String, dynamic> elevation(int level) {
    final elevations = {
      1: {'y': 1, 'blur': 3, 'opacity': 0.12},
      2: {'y': 2, 'blur': 4, 'opacity': 0.14},
      3: {'y': 3, 'blur': 6, 'opacity': 0.16},
      4: {'y': 4, 'blur': 8, 'opacity': 0.18},
      5: {'y': 6, 'blur': 10, 'opacity': 0.20},
    };
    
    final config = elevations[level] ?? elevations[1]!;
    
    return {
      'boxShadow': [
        {
          'color': 'rgba(0,0,0,${config['opacity']})',
          'offset': {'x': 0, 'y': config['y']},
          'blur': config['blur'],
        }
      ],
    };
  }
  
  /// Gradient background
  static Map<String, dynamic> gradient({
    required List<String> colors,
    String? direction,
  }) => {
    'gradient': {
      'type': 'linear',
      'colors': colors,
      'begin': direction ?? 'topLeft',
      'end': 'bottomRight',
    }
  };
  
  /// Grid layout
  static Map<String, dynamic> grid({
    String? columns,
    double? gap,
  }) => {
    'display': 'grid',
    'gridTemplateColumns': columns ?? 'repeat(3, 1fr)',
    'gridGap': gap ?? 16,
  };
  
  /// Responsive text
  static Map<String, dynamic> responsiveText({
    double? mobile,
    double? tablet,
    double? desktop,
  }) => {
    'fontSize': mobile ?? 14,
    // Media queries would be handled separately
  };

  /// Fade-in animation preset
  static Map<String, dynamic> fadeIn({
    int duration = 300,
    String curve = 'ease',
  }) => {
    'fadeBegin': 0.0,
    'fadeEnd': 1.0,
    'animationDuration': duration,
    'transitionCurve': curve,
    'animateOnBuild': true,
  };

  /// Fade-out animation preset
  static Map<String, dynamic> fadeOut({
    int duration = 300,
    String curve = 'ease',
  }) => {
    'fadeBegin': 1.0,
    'fadeEnd': 0.0,
    'animationDuration': duration,
    'transitionCurve': curve,
    'animateOnBuild': true,
  };

  /// Slide-in from left
  static Map<String, dynamic> slideInLeft({
    int duration = 300,
    String curve = 'ease-out',
  }) => {
    'slideBegin': {'x': -1.0, 'y': 0.0},
    'slideEnd': {'x': 0.0, 'y': 0.0},
    'animationDuration': duration,
    'transitionCurve': curve,
    'animateOnBuild': true,
  };

  /// Slide-in from right
  static Map<String, dynamic> slideInRight({
    int duration = 300,
    String curve = 'ease-out',
  }) => {
    'slideBegin': {'x': 1.0, 'y': 0.0},
    'slideEnd': {'x': 0.0, 'y': 0.0},
    'animationDuration': duration,
    'transitionCurve': curve,
    'animateOnBuild': true,
  };

  /// Slide-in from bottom
  static Map<String, dynamic> slideInUp({
    int duration = 300,
    String curve = 'ease-out',
  }) => {
    'slideBegin': {'x': 0.0, 'y': 1.0},
    'slideEnd': {'x': 0.0, 'y': 0.0},
    'animationDuration': duration,
    'transitionCurve': curve,
    'animateOnBuild': true,
  };

  /// Scale-in animation preset
  static Map<String, dynamic> scaleIn({
    int duration = 300,
    String curve = 'ease-out',
  }) => {
    'scaleBegin': 0.0,
    'scaleEnd': 1.0,
    'animationDuration': duration,
    'transitionCurve': curve,
    'animateOnBuild': true,
  };

  /// Pulse animation preset
  static Map<String, dynamic> pulse({
    int duration = 1000,
  }) => {
    'scaleBegin': 1.0,
    'scaleEnd': 1.05,
    'animationDuration': duration,
    'transitionCurve': 'ease-in-out',
    'animationRepeat': true,
    'animationAutoReverse': true,
  };

  /// Shimmer animation preset
  static Map<String, dynamic> shimmer({
    String baseColor = '#E0E0E0',
    String highlightColor = '#F5F5F5',
    int duration = 1500,
  }) => {
    'shimmerBaseColor': baseColor,
    'shimmerHighlightColor': highlightColor,
    'animationDuration': duration,
    'animationRepeat': true,
  };

  /// Bounce animation preset
  static Map<String, dynamic> bounce({
    int duration = 600,
  }) => {
    'scaleBegin': 0.3,
    'scaleEnd': 1.0,
    'animationDuration': duration,
    'transitionCurve': 'bounce-out',
    'animateOnBuild': true,
  };

  /// Rotation animation preset
  static Map<String, dynamic> spin({
    int duration = 1000,
  }) => {
    'rotationBegin': 0.0,
    'rotationEnd': 1.0,
    'animationDuration': duration,
    'transitionCurve': 'linear',
    'animationRepeat': true,
  };
}
