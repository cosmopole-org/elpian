import 'package:flutter/material.dart';

import '../css/css_properties.dart';
import '../models/elpian_node.dart';

class ElpianMathExpression {
  static const int _maxExpressionLength = 4096;

  static const Map<String, String> _symbols = {
    r'\\alpha': 'α',
    r'\\beta': 'β',
    r'\\gamma': 'γ',
    r'\\delta': 'δ',
    r'\\theta': 'θ',
    r'\\lambda': 'λ',
    r'\\mu': 'μ',
    r'\\pi': 'π',
    r'\\sigma': 'σ',
    r'\\phi': 'φ',
    r'\\omega': 'ω',
    r'\\sum': '∑',
    r'\\prod': '∏',
    r'\\int': '∫',
    r'\\infty': '∞',
    r'\\sqrt': '√',
    r'\\neq': '≠',
    r'\\leq': '≤',
    r'\\geq': '≥',
    r'\\approx': '≈',
    r'\\times': '×',
    r'\\cdot': '·',
    r'\\pm': '±',
    r'\\to': '→',
    r'\\leftarrow': '←',
    r'\\Rightarrow': '⇒',
    r'\\forall': '∀',
    r'\\exists': '∃',
    r'\\in': '∈',
    r'\\notin': '∉',
    r'\\subset': '⊂',
    r'\\subseteq': '⊆',
    r'\\cup': '∪',
    r'\\cap': '∩',
  };

  static const Map<String, String> _superMap = {
    '0': '⁰',
    '1': '¹',
    '2': '²',
    '3': '³',
    '4': '⁴',
    '5': '⁵',
    '6': '⁶',
    '7': '⁷',
    '8': '⁸',
    '9': '⁹',
    '+': '⁺',
    '-': '⁻',
    '=': '⁼',
    '(': '⁽',
    ')': '⁾',
    'n': 'ⁿ',
    'i': 'ⁱ',
  };

  static const Map<String, String> _subMap = {
    '0': '₀',
    '1': '₁',
    '2': '₂',
    '3': '₃',
    '4': '₄',
    '5': '₅',
    '6': '₆',
    '7': '₇',
    '8': '₈',
    '9': '₉',
    '+': '₊',
    '-': '₋',
    '=': '₌',
    '(': '₍',
    ')': '₎',
  };

  static Widget build(ElpianNode node, List<Widget> children) {
    final rawExpression = (node.props['expression'] ??
            node.props['latex'] ??
            node.props['text'] ??
            node.props['data'] ??
            '')
        .toString();

    final sanitizeResult = _sanitizeExpression(rawExpression);
    final rendered = _renderMathToUnicode(sanitizeResult.value);

    Widget result;
    final textStyle = node.style != null
        ? CSSProperties.createTextStyle(node.style)
        : const TextStyle(fontSize: 18);

    if (rendered.trim().isEmpty) {
      result = Text('Math expression is required', style: textStyle);
    } else {
      result = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(rendered, style: textStyle),
          ),
          if (sanitizeResult.sanitized)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Unsafe commands were sanitized from the expression.',
                style: TextStyle(fontSize: 11, color: Colors.orange),
              ),
            ),
        ],
      );
    }

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }

  static _SanitizeResult _sanitizeExpression(String input) {
    var expression = input
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), ' ')
        .trim();

    if (expression.length > _maxExpressionLength) {
      expression = expression.substring(0, _maxExpressionLength);
    }

    const blockedCommands = <String>[
      r'\\write',
      r'\\input',
      r'\\include',
      r'\\openout',
      r'\\read',
      r'\\catcode',
      r'\\usepackage',
      r'\\newcommand',
      r'\\renewcommand',
      r'\\def',
      r'\\csname',
      r'\\every',
      r'\\special',
    ];

    var sanitized = false;
    for (final pattern in blockedCommands) {
      final reg = RegExp(pattern, caseSensitive: false);
      if (reg.hasMatch(expression)) sanitized = true;
      expression = expression.replaceAll(reg, r'\text{blocked}');
    }

    return _SanitizeResult(expression, sanitized);
  }

  static String _renderMathToUnicode(String expression) {
    var out = expression;

    // \frac{a}{b} -> (a)/(b)
    final frac = RegExp(r'\\frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}');
    for (var i = 0; i < 24 && frac.hasMatch(out); i++) {
      out = out.replaceAllMapped(frac, (m) => '(${m[1]})/(${m[2]})');
    }

    for (final entry in _symbols.entries) {
      out = out.replaceAll(RegExp(entry.key), entry.value);
    }

    // superscripts: x^{2} or x^2
    out = out.replaceAllMapped(
      RegExp(r'\^\{([^{}]+)\}|\^([A-Za-z0-9+\-=()])'),
      (m) => _toMappedScript(m[1] ?? m[2] ?? '', _superMap),
    );

    // subscripts: x_{2} or x_2
    out = out.replaceAllMapped(
      RegExp(r'_\{([^{}]+)\}|_([A-Za-z0-9+\-=()])'),
      (m) => _toMappedScript(m[1] ?? m[2] ?? '', _subMap),
    );

    // remove harmless tex wrappers
    out = out
        .replaceAll(RegExp(r'\\left|\\right'), '')
        .replaceAll(RegExp(r'\\text\{([^{}]*)\}'), r'$1')
        .replaceAll('{', '')
        .replaceAll('}', '');

    return out.trim();
  }

  static String _toMappedScript(String value, Map<String, String> map) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final c = String.fromCharCode(rune);
      buffer.write(map[c] ?? c);
    }
    return buffer.toString();
  }
}

class _SanitizeResult {
  final String value;
  final bool sanitized;

  const _SanitizeResult(this.value, this.sanitized);
}
