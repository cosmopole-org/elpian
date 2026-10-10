/// The basic catalog's client-side functions, implemented as the basic catalog
/// implementation guide describes them: validation (`required`, `regex`,
/// `length`, `numeric`, `email`), formatting (`formatString`, `formatNumber`,
/// `formatCurrency`, `formatDate`, `pluralize`), logic (`and`, `or`, `not`)
/// and the `openUrl` side effect.
///
/// A function receives its arguments already resolved (bindings read, nested
/// calls evaluated) and a [FunctionContext]; only `formatString` reaches back
/// into the context, to evaluate the expressions inside its template.
///
/// Dart has no `Intl` in this package's dependencies, so number, currency,
/// date and plural formatting follow the `en-US` conventions whatever the
/// locale (the web renderer uses the platform's `Intl` for other locales).
library;

import 'dart:convert';

import 'errors.dart';
import 'expressions.dart';

abstract class FunctionContext {
  String get locale;

  /// Resolve a data path (relative paths against the current scope).
  Object? read(String path);

  /// Evaluate a function call with unresolved (expression) arguments.
  Object? call(String name, Map<String, dynamic> args);

  /// Open a URL (already validated); does nothing when the host cannot.
  void openUrl(String url);

  /// The base for resolving relative URLs in `openUrl`.
  String? get baseUrl;
}

typedef A2UIFunction = Object? Function(
    Map<String, dynamic> args, FunctionContext ctx);

/// A number the way JavaScript's `String(n)` prints it (`1.0` → `1`).
String numberToString(num n) {
  if (n is int) return n.toString();
  if (n.isNaN) return 'NaN';
  if (n.isInfinite) return n > 0 ? 'Infinity' : '-Infinity';
  if (n == n.truncateToDouble() && n.abs() < 1e21) return n.toInt().toString();
  return n.toString();
}

/// Stringify an interpolated value the way the protocol prescribes.
String stringifyValue(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  if (value is num) return numberToString(value);
  if (value is bool) return value.toString();
  try {
    return jsonEncode(value);
  } catch (_) {
    return value.toString();
  }
}

bool toBool(Object? value) => value == true || value == 'true';

num? toNum(Object? value) {
  if (value is num) return value.isFinite ? value : null;
  if (value is String && value.trim().isNotEmpty) {
    final n = num.tryParse(value.trim());
    return n != null && n.isFinite ? n : null;
  }
  return null;
}

final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// Evaluate one parsed template value against [ctx].
Object? evaluateTemplateValue(Object? value, FunctionContext ctx) {
  if (value is Map) {
    if (value.containsKey('path')) return ctx.read(value['path'] as String);
    return ctx.call(value['call'] as String,
        Map<String, dynamic>.from(value['args'] as Map? ?? const {}));
  }
  return value;
}

/// Group the integer digits of [digits] with commas.
String _group(String digits) {
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// `en-US` decimal formatting: [minFraction]..[maxFraction] digits, optional
/// grouping, half-away-from-zero rounding.
String formatDecimal(num n,
    {int minFraction = 0, int maxFraction = 3, bool grouping = true}) {
  final negative = n < 0;
  var text = n.abs().toStringAsFixed(maxFraction);
  // Trim optional trailing zeros down to minFraction.
  if (maxFraction > minFraction && text.contains('.')) {
    var end = text.length;
    final dot = text.indexOf('.');
    while (end > dot + 1 + minFraction && text[end - 1] == '0') {
      end--;
    }
    if (end == dot + 1) end = dot;
    text = text.substring(0, end);
  }
  final dot = text.indexOf('.');
  final intPart = dot < 0 ? text : text.substring(0, dot);
  final frac = dot < 0 ? '' : text.substring(dot);
  final body = (grouping ? _group(intPart) : intPart) + frac;
  final isZero = double.parse(text) == 0;
  return negative && !isZero ? '-$body' : body;
}

({int min, int max})? _decimals(Map<String, dynamic> args) {
  final decimals = toNum(args['decimals']);
  if (decimals == null) return null;
  final d = decimals.truncate().clamp(0, 20);
  return (min: d, max: d);
}

const Map<String, String> _currencySymbols = {
  'USD': r'$',
  'EUR': '€',
  'GBP': '£',
  'JPY': '¥',
  'INR': '₹',
  'CNY': 'CN¥',
  'CAD': r'CA$',
  'AUD': r'A$',
  'KRW': '₩',
  'BRL': r'R$',
  'MXN': r'MX$',
  'ILS': '₪',
  'VND': '₫',
  'NZD': r'NZ$',
  'HKD': r'HK$',
  'TWD': r'NT$',
  'PHP': '₱',
};

/// Currencies whose minor unit has no digits.
const Set<String> _zeroDecimalCurrencies = {'JPY', 'KRW', 'VND', 'CLP', 'ISK'};

final Map<String, A2UIFunction> basicFunctions = {
  'required': (args, _) {
    final value = args['value'];
    return !(value == null || value == '' || (value is List && value.isEmpty));
  },
  'regex': (args, _) {
    final pattern = args['pattern'];
    if (pattern is! String) {
      throw expressionError('regex: "pattern" must be a string');
    }
    RegExp re;
    try {
      re = RegExp(pattern);
    } catch (_) {
      throw expressionError('regex: invalid pattern "$pattern"');
    }
    return re.hasMatch(stringifyValue(args['value']));
  },
  'length': (args, _) {
    final n = stringifyValue(args['value']).length;
    final min = toNum(args['min']);
    final max = toNum(args['max']);
    if (min != null && n < min) return false;
    if (max != null && n > max) return false;
    return true;
  },
  'numeric': (args, _) {
    final n = toNum(args['value']);
    if (n == null) return false;
    final min = toNum(args['min']);
    final max = toNum(args['max']);
    if (min != null && n < min) return false;
    if (max != null && n > max) return false;
    return true;
  },
  'email': (args, _) {
    final value = args['value'];
    return value is String && _email.hasMatch(value);
  },
  'formatString': (args, ctx) {
    final value = args['value'];
    if (value == null) return '';
    final parts = parseTemplate(stringifyValue(value));
    return parts
        .map((p) => stringifyValue(evaluateTemplateValue(p, ctx)))
        .join();
  },
  'formatNumber': (args, ctx) {
    final n = toNum(args['value']);
    if (n == null) return '';
    final d = _decimals(args);
    return formatDecimal(n,
        minFraction: d?.min ?? 0,
        maxFraction: d?.max ?? 3,
        grouping: args['grouping'] != false);
  },
  'formatCurrency': (args, ctx) {
    final n = toNum(args['value']);
    if (n == null) return '';
    final raw = args['currency'];
    final currency = raw is String && RegExp(r'^[A-Za-z]{3}$').hasMatch(raw)
        ? raw.toUpperCase()
        : 'USD';
    final standard = _zeroDecimalCurrencies.contains(currency) ? 0 : 2;
    final d = _decimals(args);
    final body = formatDecimal(n.abs(),
        minFraction: d?.min ?? standard,
        maxFraction: d?.max ?? standard,
        grouping: args['grouping'] != false);
    final symbol = _currencySymbols[currency] ?? '$currency ';
    final negative = n < 0 && double.parse(body.replaceAll(',', '')) != 0;
    return '${negative ? '-' : ''}$symbol$body';
  },
  'formatDate': (args, ctx) {
    final date = parseDate(args['value']);
    if (date == null) return '';
    final format = args['format'];
    return formatDatePattern(
        date, format is String && format.isNotEmpty ? format : 'yyyy-MM-dd',
        locale: ctx.locale);
  },
  'pluralize': (args, ctx) {
    final n = toNum(args['value']);
    if (n == null) return stringifyValue(args['other']);
    var category = n == 1 ? 'one' : 'other';
    // English reports 0 as "other"; an explicit zero form wins.
    if (n == 0 && args.containsKey('zero') && args['zero'] != null) {
      category = 'zero';
    }
    final chosen = args[category] ?? args['other'];
    return stringifyValue(chosen);
  },
  'openUrl': (args, ctx) {
    final resolved = validateOpenUrl(args['url'], ctx.baseUrl);
    ctx.openUrl(resolved);
    return null;
  },
  'and': (args, _) {
    final values = args['values'];
    if (values is! List) throw expressionError('and: "values" must be a list');
    for (final v in values) {
      if (!toBool(v)) return false;
    }
    return true;
  },
  'or': (args, _) {
    final values = args['values'];
    if (values is! List) throw expressionError('or: "values" must be a list');
    for (final v in values) {
      if (toBool(v)) return true;
    }
    return false;
  },
  'not': (args, _) => !toBool(args['value']),
};

final RegExp _scheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):');

/// `openUrl`'s mandatory checks: resolve relative URLs against [base], then
/// allow only `http:` and `https:` (no `javascript:`, `data:`, …).
String validateOpenUrl(Object? url, String? base) {
  if (url is! String || url.trim().isEmpty) {
    throw expressionError('openUrl: "url" must be a non-empty string');
  }
  final raw = url.trim();
  var resolved = raw;
  if (!_scheme.hasMatch(raw)) {
    if (base == null) {
      throw expressionError('openUrl: cannot resolve relative URL "$raw"');
    }
    try {
      resolved = Uri.parse(base).resolve(raw).toString();
    } catch (_) {
      throw expressionError('openUrl: invalid URL "$raw"');
    }
  }
  final protocol = (_scheme.firstMatch(resolved)?.group(1) ?? '').toLowerCase();
  if (protocol != 'http' && protocol != 'https') {
    throw expressionError(
        'openUrl: the "$protocol:" scheme is not allowed (http and https only)');
  }
  return resolved;
}

// ----------------------------------------------------------------------------
// Dates
// ----------------------------------------------------------------------------

final RegExp _dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final RegExp _timeOnly = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?$');

/// Parse an A2UI date value: an ISO 8601 date-time (`2026-02-02T15:17:00Z`),
/// a date (`2026-02-02`, local midnight), a time (`14:30`, today), or epoch
/// milliseconds. The result is in local time.
DateTime? parseDate(Object? value) {
  if (value is DateTime) return value.toLocal();
  if (value is num) {
    return value.isFinite
        ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
        : null;
  }
  if (value is! String || value.trim().isEmpty) return null;
  final s = value.trim();
  var m = _dateOnly.firstMatch(s);
  if (m != null) {
    return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }
  m = _timeOnly.firstMatch(s);
  if (m != null) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, int.parse(m[1]!),
        int.parse(m[2]!), int.parse(m[3] ?? '0'));
  }
  // A date-time without an offset is local time; with one, absolute.
  return DateTime.tryParse(s)?.toLocal();
}

String _pad(int n, int width) => n.toString().padLeft(width, '0');

const List<String> _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', //
  'August', 'September', 'October', 'November', 'December',
];
const List<String> _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', //
  'Sunday',
];

final RegExp _letter = RegExp(r'[A-Za-z]');

/// Format [date] with a Unicode TR35 pattern (`yyyy-MM-dd`,
/// `EEEE, MMM d 'at' h:mm a`, …).
String formatDatePattern(DateTime date, String pattern,
    {String locale = 'en-US'}) {
  final out = StringBuffer();
  var i = 0;
  while (i < pattern.length) {
    final ch = pattern[i];
    if (ch == "'") {
      // Quoted literal; '' is a single quote.
      if (i + 1 < pattern.length && pattern[i + 1] == "'") {
        out.write("'");
        i += 2;
        continue;
      }
      var j = i + 1;
      while (j < pattern.length) {
        if (pattern[j] == "'" &&
            j + 1 < pattern.length &&
            pattern[j + 1] == "'") {
          out.write("'");
          j += 2;
          continue;
        }
        if (pattern[j] == "'") break;
        out.write(pattern[j++]);
      }
      i = j + 1;
      continue;
    }
    if (!_letter.hasMatch(ch)) {
      out.write(ch);
      i++;
      continue;
    }
    var n = 1;
    while (i + n < pattern.length && pattern[i + n] == ch) {
      n++;
    }
    i += n;
    out.write(_field(date, ch, n));
  }
  return out.toString();
}

String _field(DateTime d, String ch, int n) {
  switch (ch) {
    case 'y':
    case 'Y':
    case 'u':
      return n == 2 ? _pad(d.year % 100, 2) : _pad(d.year, n);
    case 'M':
    case 'L':
      if (n >= 4) return _months[d.month - 1];
      if (n == 3) return _months[d.month - 1].substring(0, 3);
      return _pad(d.month, n);
    case 'd':
      return _pad(d.day, n);
    case 'D':
      final start = DateTime(d.year, 1, 1);
      return _pad(
          DateTime(d.year, d.month, d.day).difference(start).inDays + 1, n);
    case 'E':
    case 'e':
    case 'c':
      final name = _weekdays[d.weekday - 1];
      if (n == 5) return name.substring(0, 1);
      if (n >= 4) return name;
      return name.substring(0, 3);
    case 'a':
      return d.hour < 12 ? 'AM' : 'PM';
    case 'h':
      return _pad(d.hour % 12 == 0 ? 12 : d.hour % 12, n);
    case 'K':
      return _pad(d.hour % 12, n);
    case 'H':
      return _pad(d.hour, n);
    case 'k':
      return _pad(d.hour == 0 ? 24 : d.hour, n);
    case 'm':
      return _pad(d.minute, n);
    case 's':
      return _pad(d.second, n);
    case 'S':
      return _pad(d.millisecond, 3).substring(0, n.clamp(1, 3));
    case 'z':
    case 'Z':
    case 'x':
    case 'X':
      final offset = d.timeZoneOffset.inMinutes;
      if (offset == 0 && (ch == 'X' || ch == 'x')) return 'Z';
      final sign = offset >= 0 ? '+' : '-';
      final abs = offset.abs();
      return '$sign${_pad(abs ~/ 60, 2)}:${_pad(abs % 60, 2)}';
    default:
      return ch * n;
  }
}
