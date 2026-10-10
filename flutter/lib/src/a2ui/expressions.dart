/// The `formatString` template language: literal text with `${…}`
/// interpolations, `\${` as an escaped literal marker. Inside an interpolation:
///
///   - literals: `'…'` / `"…"` strings (backslash escapes), numbers (`-1.5e3`,
///     `.5`, `+1`, `1.`), `true`, `false`, `null`;
///   - data paths: `/absolute/path`, `relative/path`, `./x`, `../x`;
///   - function calls with named arguments: `formatDate(value: /d, format: 'yyyy')`
///     (arguments are themselves expressions; a trailing comma is allowed);
///   - nested interpolations: `${${/path}}`.
///
/// Expressions nest at most [maxExpressionDepth] deep (interpolations and
/// function arguments both count). [parseTemplate] returns the parts with
/// adjacent string literals joined — the representation `expressions.yaml`
/// compares against: strings, numbers, booleans, `{path}` maps and
/// `{call, args, returnType: 'any'}` maps.
library;

import 'errors.dart';

const int maxExpressionDepth = 100;

final RegExp _identChar = RegExp(r'[A-Za-z0-9_\-./~$@#\[\]]');
final RegExp _argNameChar = RegExp(r'[A-Za-z0-9_]');
final RegExp _ws = RegExp(r'\s');
final RegExp _numberLiteral =
    RegExp(r'^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?$');

bool _isDigit(String ch) =>
    ch.isNotEmpty && ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57;

class _Parser {
  _Parser(this.s);
  final String s;
  int i = 0;

  String peek([int offset = 0]) {
    final j = i + offset;
    return j < s.length ? s[j] : '';
  }

  void skipWs() {
    while (i < s.length && _ws.hasMatch(s[i])) {
      i++;
    }
  }

  String _snippet() => s.substring(i, (i + 10).clamp(0, s.length));

  /// The body of one `${…}` whose `${` has been consumed; leaves `}` consumed.
  Object? interpolation(int depth) {
    if (depth > maxExpressionDepth) {
      throw parseError(
          'Max recursion depth ($maxExpressionDepth) exceeded in expression');
    }
    skipWs();
    if (i >= s.length) throw parseError('Unclosed interpolation: expected "}"');
    final value = expression(depth);
    skipWs();
    if (i >= s.length) throw parseError('Unclosed interpolation: expected "}"');
    if (peek() != '}') {
      throw parseError('Unexpected characters "${_snippet()}" in expression');
    }
    i++;
    return value;
  }

  Object? expression(int depth) {
    if (depth > maxExpressionDepth) {
      throw parseError(
          'Max recursion depth ($maxExpressionDepth) exceeded in expression');
    }
    skipWs();
    final c = peek();
    if (c.isEmpty) {
      throw parseError('Unclosed interpolation: expected an expression');
    }
    if (c == r'$' && peek(1) == '{') {
      i += 2;
      return interpolation(depth + 1);
    }
    if (c == "'" || c == '"') return _stringLiteral(c);
    if (_startsNumber()) return _number();
    final start = i;
    while (i < s.length &&
        _identChar.hasMatch(s[i]) &&
        !(s[i] == r'$' && peek(1) == '{')) {
      i++;
    }
    final token = s.substring(start, i);
    if (token.isEmpty) {
      throw parseError('Unexpected characters "${_snippet()}" in expression');
    }
    final save = i;
    skipWs();
    if (peek() == '(') {
      i++;
      return _call(token, depth);
    }
    i = save;
    if (token == 'true') return true;
    if (token == 'false') return false;
    if (token == 'null') return null;
    return <String, dynamic>{'path': token};
  }

  bool _startsNumber() {
    final c = peek();
    if (_isDigit(c)) return true;
    if (c == '.') return _isDigit(peek(1));
    if (c == '+' || c == '-') {
      return _isDigit(peek(1)) || (peek(1) == '.' && _isDigit(peek(2)));
    }
    return false;
  }

  num _number() {
    final start = i;
    if (peek() == '+' || peek() == '-') i++;
    while (i < s.length) {
      final ch = s[i];
      if (_isDigit(ch) || ch == '.') {
        i++;
      } else if (ch == 'e' || ch == 'E') {
        i++;
        if (peek() == '+' || peek() == '-') i++;
      } else {
        break;
      }
    }
    final text = s.substring(start, i);
    if (!_numberLiteral.hasMatch(text)) {
      throw parseError('Invalid number literal "$text"');
    }
    final cleaned = (text.startsWith('+') ? text.substring(1) : text)
        .replaceFirst(RegExp(r'\.(?=[eE]|$)'), '');
    final value = double.tryParse(cleaned);
    if (value == null || !value.isFinite) {
      throw parseError('Number literal "$text" is out of range');
    }
    if (value == 0) return 0;
    // Integral literals stay integers, as JSON numbers compare in the suites.
    if (value == value.truncateToDouble() && value.abs() < 9007199254740992) {
      return value.toInt();
    }
    return value;
  }

  String _stringLiteral(String quote) {
    i++;
    final out = StringBuffer();
    while (i < s.length) {
      final ch = s[i++];
      if (ch == quote) return out.toString();
      if (ch == r'\') {
        final next = i < s.length ? s[i++] : '';
        out.write(next == 'n'
            ? '\n'
            : next == 't'
                ? '\t'
                : next == 'r'
                    ? '\r'
                    : next);
      } else {
        out.write(ch);
      }
    }
    throw parseError('Unclosed string literal in expression');
  }

  Map<String, dynamic> _call(String name, int depth) {
    final args = <String, dynamic>{};
    skipWs();
    if (peek() == ')') {
      i++;
      return {'call': name, 'args': args, 'returnType': 'any'};
    }
    for (;;) {
      skipWs();
      final start = i;
      while (i < s.length && _argNameChar.hasMatch(s[i])) {
        i++;
      }
      final argName = s.substring(start, i);
      skipWs();
      if (argName.isEmpty || peek() != ':') {
        throw parseError('Expected ":" after argument name in call to $name()');
      }
      i++;
      args[argName] = expression(depth + 1);
      skipWs();
      final c = peek();
      if (c == ',') {
        i++;
        skipWs();
        if (peek() == ')') {
          i++;
          break;
        }
        continue;
      }
      if (c == ')') {
        i++;
        break;
      }
      throw parseError(
          'Expected "," or ")" after function arguments in call to $name()');
    }
    return {'call': name, 'args': args, 'returnType': 'any'};
  }
}

/// Parse a `formatString` template into its parts (adjacent literals joined).
List<Object> parseTemplate(String input) {
  final parts = <Object>[];
  final literal = StringBuffer();
  void flush() {
    if (literal.isNotEmpty) parts.add(literal.toString());
    literal.clear();
  }

  final p = _Parser(input);
  while (p.i < input.length) {
    final ch = input[p.i];
    if (ch == r'\' && p.peek(1) == r'$' && p.peek(2) == '{') {
      literal.write(r'${');
      p.i += 3;
      continue;
    }
    if (ch == r'$' && p.peek(1) == '{') {
      p.i += 2;
      final value = p.interpolation(1);
      if (value == null) continue;
      if (value is String) {
        literal.write(value);
      } else {
        flush();
        parts.add(value);
      }
      continue;
    }
    literal.write(ch);
    p.i++;
  }
  flush();
  return parts;
}

/// True when [input] contains an interpolation (an unescaped `${`).
bool hasInterpolation(String input) => RegExp(r'(^|[^\\])\$\{').hasMatch(input);
