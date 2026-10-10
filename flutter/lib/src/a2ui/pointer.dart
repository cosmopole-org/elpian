/// JSON Pointers (RFC 6901) as A2UI uses them: absolute paths (`/user/name`),
/// relative paths resolved against a data scope (`name` inside a template
/// item at `/users/0`), `.`/`..` segments, and tolerant normalisation of empty
/// segments (`//a///b//` is `/a/b`).
library;

import 'errors.dart';

/// Segments refused on read and write (kept for parity with the web
/// renderer, where they would reach a JavaScript prototype).
const Set<String> _forbidden = {'__proto__', 'constructor', 'prototype'};

final RegExp _badEscape = RegExp(r'~(?![01])');
final RegExp _indexSegment = RegExp(r'^(0|[1-9][0-9]*)$');

/// True when [path] only uses valid `~0` / `~1` escapes.
bool isValidPointerSyntax(String path) => !_badEscape.hasMatch(path);

/// Decode one reference token (`~1` → `/`, then `~0` → `~`).
String decodeSegment(String token) =>
    token.replaceAll('~1', '/').replaceAll('~0', '~');

/// Encode one key as a reference token.
String encodeSegment(String key) =>
    key.replaceAll('~', '~0').replaceAll('/', '~1');

/// The decoded segments of an absolute pointer. Empty segments are dropped, so
/// `''`, `'/'` and `'///'` all address the root.
List<String> parsePointer(String path) {
  if (!isValidPointerSyntax(path)) {
    throw A2UIError('ValidationError',
        'Invalid path syntax: "$path" uses an escape other than ~0 or ~1',
        path: path);
  }
  final segments =
      path.split('/').where((s) => s.isNotEmpty).map(decodeSegment).toList();
  for (final s in segments) {
    if (_forbidden.contains(s)) {
      throw dataError('Forbidden path segment "$s" in "$path"');
    }
  }
  return segments;
}

/// The canonical pointer for [segments] (`/` for the root).
String formatPointer(List<String> segments) =>
    segments.isEmpty ? '/' : '/${segments.map(encodeSegment).join('/')}';

/// Normalise a pointer to its canonical spelling.
String normalizePointer(String path) => formatPointer(parsePointer(path));

/// Resolve [path] against the data scope [contextPath] (`/` when absent):
/// absolute paths ignore the scope; `''` and `.` mean the scope itself; `..`
/// walks up one level.
String resolvePath(String path, [String? contextPath]) {
  if (path.startsWith('/')) return path;
  final base =
      (contextPath ?? '/').split('/').where((s) => s.isNotEmpty).toList();
  for (final raw in path.split('/')) {
    if (raw.isEmpty || raw == '.') continue;
    if (raw == '..') {
      if (base.isNotEmpty) base.removeLast();
    } else {
      base.add(raw);
    }
  }
  return base.isEmpty ? '/' : '/${base.join('/')}';
}

/// Array index segments: `0` or a digit run without a leading zero.
bool isIndexSegment(String segment) => _indexSegment.hasMatch(segment);

/// Whether [ancestor] is [path] or a prefix of it, segment-wise.
bool isPrefixOf(List<String> ancestor, List<String> path) {
  if (ancestor.length > path.length) return false;
  for (var i = 0; i < ancestor.length; i++) {
    if (ancestor[i] != path[i]) return false;
  }
  return true;
}
