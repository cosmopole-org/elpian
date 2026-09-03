import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// No public entrypoint may reach `dart:ffi` except through a conditional
/// import.
///
/// `dart:ffi` does not exist on the web. The codebase handles that with
/// conditional imports — `import 'ffi/api.dart' if (dart.library.js_interop)
/// 'ffi/api_web.dart'` — which dart2js resolves to the web variant. One plain
/// import anywhere on the path defeats it.
///
/// That happened: `governance/elpian_governor.dart` imported `../ffi/api.dart`
/// unconditionally, one line above a correctly conditional import of its own
/// bindings. Every native gate passed — the analyzer, `flutter test`, clippy,
/// all of them run natively — and the web build of the showcase app failed with
/// "Dart library 'dart:ffi' is not available on this platform", in a separate
/// workflow, at the end of a template generation.
///
/// This is the gate that was missing. It is a source-level reachability check
/// rather than a web compile because it costs milliseconds instead of a minute,
/// and it names the offending edge instead of dumping an import chain.
void main() {
  test('no public entrypoint reaches dart:ffi unconditionally', () {
    final lib = Directory('lib');
    final files = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    // path -> the set of libraries it imports *unconditionally*.
    final edges = <String, Set<String>>{};
    final touchesFfi = <String>{};

    for (final f in files) {
      final src = f.readAsStringSync();
      final self = _norm(f.path);
      final out = <String>{};
      // Directives can span lines — the `if (dart.library.js_interop)` clause is
      // routinely wrapped onto the next one — so join each up to its `;` before
      // deciding whether it is conditional. Reading line by line reports every
      // wrapped conditional import as a plain one.
      for (final t in _directives(src)) {
        if (!t.startsWith('import ') && !t.startsWith('export ')) continue;
        // A conditional import resolves to the web variant off-native, so it is
        // not an unconditional edge.
        if (t.contains('if (dart.library.')) continue;
        final m = RegExp("['\"]([^'\"]+)['\"]").firstMatch(t);
        if (m == null) continue;
        final target = m.group(1)!;
        if (target == 'dart:ffi') {
          touchesFfi.add(self);
          continue;
        }
        if (target.startsWith('dart:') || target.startsWith('package:')) {
          continue;
        }
        out.add(_resolve(self, target));
      }
      edges[self] = out;
    }

    // Propagate: unconditionally importing a web-unsafe library is web-unsafe.
    final unsafe = Set<String>.from(touchesFfi);
    var grew = true;
    while (grew) {
      grew = false;
      for (final entry in edges.entries) {
        if (unsafe.contains(entry.key)) continue;
        if (entry.value.any(unsafe.contains)) {
          unsafe.add(entry.key);
          grew = true;
        }
      }
    }

    expect(touchesFfi, isNotEmpty,
        reason:
            'the scan found no dart:ffi imports at all — it has stopped matching');

    // The barrels an app actually imports. Each must be web-safe.
    const entrypoints = [
      'lib/elpian_ui.dart',
      'lib/elpian_governance.dart',
      'lib/elpian_runtime.dart',
      'lib/elpian_godot.dart',
    ];
    for (final e in entrypoints) {
      if (!File(e).existsSync()) continue;
      if (!unsafe.contains(e)) continue;

      // Name the edge, not just the verdict: report one shortest path.
      final path = _pathTo(e, edges, touchesFfi);
      fail('$e reaches dart:ffi through plain imports, so the web build of any '
          'app importing it fails with "Dart library \'dart:ffi\' is not '
          'available on this platform".\n'
          'The chain: ${path.join(' -> ')} -> dart:ffi\n'
          'Fix the last hop before dart:ffi with a conditional import, e.g. '
          "import 'x.dart' if (dart.library.js_interop) 'x_web.dart';");
    }
  });
}

/// The `import`/`export` directives in [src], each joined into one line.
List<String> _directives(String src) {
  final out = <String>[];
  final buf = StringBuffer();
  var open = false;
  for (final line in src.split('\n')) {
    final t = line.trimLeft();
    if (!open && !(t.startsWith('import ') || t.startsWith('export '))) {
      continue;
    }
    open = true;
    buf.write(buf.isEmpty ? t : ' $t');
    if (t.contains(';')) {
      out.add(buf.toString());
      buf.clear();
      open = false;
    }
  }
  return out;
}

String _norm(String p) => p.replaceAll('\\', '/');

String _resolve(String from, String rel) {
  final base = from.substring(0, from.lastIndexOf('/'));
  final parts = <String>[];
  for (final seg in '$base/$rel'.split('/')) {
    if (seg == '.' || seg.isEmpty) continue;
    if (seg == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(seg);
  }
  return parts.join('/');
}

/// Breadth-first: the shortest plain-import chain from [start] to a file that
/// imports `dart:ffi`.
List<String> _pathTo(
    String start, Map<String, Set<String>> edges, Set<String> ffi) {
  final queue = <List<String>>[
    [start]
  ];
  final seen = <String>{start};
  while (queue.isNotEmpty) {
    final path = queue.removeAt(0);
    final node = path.last;
    if (ffi.contains(node)) return path;
    for (final next in edges[node] ?? const <String>{}) {
      if (seen.add(next)) queue.add([...path, next]);
    }
  }
  return [start];
}
