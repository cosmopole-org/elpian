/// A2UI errors. Every failure the renderer reports carries a category (the
/// conformance suites' `expect_error.category`) and, for validation failures,
/// the protocol's standard error shape:
///
/// ```json
/// { "code": "VALIDATION_FAILED", "surfaceId": "s1", "path": "/components/0/text", "message": "…" }
/// ```
library;

/// `DataError`, `ParseError`, `ValidationError`, `ExpressionError` or
/// `TransportError`.
typedef A2UIErrorCategory = String;

/// Machine-readable cause of a schema issue (`missing_field`,
/// `invalid_value`, `type_mismatch`, `unknown_field`, `topology`, `limit`).
typedef A2UIIssueCode = String;

class A2UIError implements Exception {
  A2UIError(this.category, this.message,
      {this.surfaceId, this.path, this.issue});

  final A2UIErrorCategory category;
  final String message;
  final String? surfaceId;
  final String? path;
  final A2UIIssueCode? issue;

  /// The client→server `error` payload (A2UI's standard shape).
  Map<String, dynamic> toWire() {
    if (category == 'ValidationError') {
      return {
        'code': 'VALIDATION_FAILED',
        'surfaceId': surfaceId ?? '',
        'path': path ?? '/',
        'message': message,
      };
    }
    return {
      'code':
          '${category.replaceAll(RegExp(r'Error$'), '').toUpperCase()}_ERROR',
      'surfaceId': surfaceId ?? '',
      'message': message,
    };
  }

  @override
  String toString() => '$category: $message';
}

A2UIError dataError(String message) => A2UIError('DataError', message);

A2UIError parseError(String message) => A2UIError('ParseError', message);

A2UIError expressionError(String message) =>
    A2UIError('ExpressionError', message);
