import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../css/css_properties.dart';
import '../models/elpian_node.dart';

class ElpianMathExpression {
  static const int _maxExpressionLength = 4096;

  static Widget build(ElpianNode node, List<Widget> children) {
    final rawExpression = (node.props['expression'] ??
            node.props['latex'] ??
            node.props['text'] ??
            node.props['data'] ??
            '')
        .toString();

    final processedExpression = _sanitizeExpression(rawExpression);
    final bool isUnsafe = processedExpression != rawExpression;

    Widget result;

    if (processedExpression.trim().isEmpty) {
      result = const Text('Math expression is required');
    } else {
      final textStyle = node.style != null
          ? CSSProperties.createTextStyle(node.style)
          : null;

      result = _MathExpressionSafeView(
        expression: processedExpression,
        textStyle: textStyle,
        isUnsafe: isUnsafe,
      );
    }

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }

  static String _sanitizeExpression(String input) {
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

    for (final pattern in blockedCommands) {
      expression = expression.replaceAll(RegExp(pattern, caseSensitive: false), r'\\text{blocked}');
    }

    return expression;
  }
}

class _MathExpressionSafeView extends StatelessWidget {
  final String expression;
  final TextStyle? textStyle;
  final bool isUnsafe;

  const _MathExpressionSafeView({
    required this.expression,
    required this.textStyle,
    required this.isUnsafe,
  });

  @override
  Widget build(BuildContext context) {
    Widget mathWidget;

    try {
      mathWidget = Math.tex(
        expression,
        textStyle: textStyle,
        mathStyle: MathStyle.display,
        onErrorFallback: (FlutterMathException e) {
          return Text(
            'Invalid math expression: ${e.messageWithType}',
            style: textStyle,
          );
        },
      );
    } catch (_) {
      mathWidget = Text(
        'Invalid math expression syntax',
        style: textStyle,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: mathWidget,
        ),
        if (isUnsafe)
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
}
