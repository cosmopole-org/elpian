/// A surface's data model: one JSON document addressed by JSON Pointers, with
/// the write semantics the A2UI conformance suite (`data_model.yaml`,
/// `data_deletion.yaml`) fixes:
///
/// - writes auto-vivify missing containers — a list when the next segment is
///   an index, an object otherwise — and pad lists with `null`;
/// - writing through a primitive, a non-numeric (or leading-zero) list
///   segment, or a list index above [maxListIndex] is a `DataError`, and
///   leaves the model untouched;
/// - deleting removes an object key, but sets a list slot to `null` so list
///   length is preserved; deleting the root resets it to `{}`;
/// - observers on a path fire when its value changes — writes to the path, to
///   an ancestor, or to a descendant — but not on same-value rewrites.
///
/// Dart has no `undefined`: [get] answers `null` both for a missing value and
/// for a stored `null` (internally the two stay distinct, so observers see an
/// absent → `null` write as a change, as on the web).
library;

import 'package:flutter/foundation.dart';

import 'errors.dart';
import 'pointer.dart';

const int maxListIndex = 10000;

typedef DataObserver = void Function(Object? value, String path);

/// Marks "nothing there" inside lookups (distinct from a stored `null`).
const Object _absent = _Absent();

class _Absent {
  const _Absent();
}

class _Watch {
  _Watch(this.segments, this.path, this.observer);
  final List<String> segments;
  final String path;
  final DataObserver observer;
}

class DataModel {
  DataModel([Object? initial]) : _root = cloneJson(initial ?? {});

  Object? _root;
  List<_Watch> _watches = [];

  /// The value at [path], or `null` when nothing is there.
  Object? get([String path = '/']) {
    final v = _lookup(_root, parsePointer(path));
    return identical(v, _absent) ? null : v;
  }

  /// Whether a value (possibly `null`) is stored at [path].
  bool has(String path) =>
      !identical(_lookup(_root, parsePointer(path)), _absent);

  /// The whole document (do not mutate).
  Object? get value => _root;

  /// A deep copy of the whole document.
  Object? snapshot() => cloneJson(_root);

  /// Write [value] at [path].
  void set(String path, Object? value) {
    final segments = parsePointer(path);
    final fresh = cloneJson(value);
    if (segments.isEmpty) {
      _mutate(segments, () => _root = fresh);
      return;
    }
    _checkWritable(_root, segments, path);
    _mutate(segments, () {
      _root ??= isIndexSegment(segments[0]) ? <Object?>[] : <String, dynamic>{};
      Object? container = _root;
      for (var i = 0; i < segments.length - 1; i++) {
        final seg = segments[i];
        Object? child;
        if (container is List) {
          final index = int.parse(seg);
          _padList(container, index + 1);
          child = container[index];
          if (child == null) {
            child = isIndexSegment(segments[i + 1])
                ? <Object?>[]
                : <String, dynamic>{};
            container[index] = child;
          }
        } else {
          final map = container as Map;
          child = map[seg];
          if (child == null) {
            child = isIndexSegment(segments[i + 1])
                ? <Object?>[]
                : <String, dynamic>{};
            map[seg] = child;
          }
        }
        container = child;
      }
      final last = segments.last;
      if (container is List) {
        final index = int.parse(last);
        _padList(container, index + 1);
        container[index] = fresh;
      } else {
        (container as Map)[last] = fresh;
      }
    });
  }

  /// Remove the value at [path]: an object key is deleted, a list slot is set
  /// to `null` (length preserved), the root resets to `{}`. A missing path is a
  /// no-op that creates nothing.
  void delete(String path) {
    final segments = parsePointer(path);
    if (segments.isEmpty) {
      _mutate(segments, () => _root = <String, dynamic>{});
      return;
    }
    final parent = _lookup(_root, segments.sublist(0, segments.length - 1));
    final last = segments.last;
    if (parent is List) {
      if (!isIndexSegment(last) || int.parse(last) >= parent.length) return;
      _mutate(segments, () => parent[int.parse(last)] = null);
    } else if (parent is Map) {
      if (!parent.containsKey(last)) return;
      _mutate(segments, () => parent.remove(last));
    }
  }

  /// Observe [path]; returns the unsubscribe function.
  VoidCallback watch(String path, DataObserver observer) {
    final segments = parsePointer(path);
    final entry = _Watch(segments, formatPointer(segments), observer);
    _watches.add(entry);
    return () => _watches = _watches.where((w) => w != entry).toList();
  }

  /// Detach every observer.
  void dispose() => _watches = [];

  /// Run [change] (which replaces or removes the value at [target]) and notify
  /// every observer whose value changed: ancestors when the target changed,
  /// the target itself, and descendants whose own value differs afterwards.
  void _mutate(List<String> target, void Function() change) {
    final related = _watches
        .where((w) =>
            isPrefixOf(w.segments, target) || isPrefixOf(target, w.segments))
        .toList();
    // Snapshots: in-place writes would otherwise alias the "before" values.
    final before = cloneJson(_lookup(_root, target));
    final descendantsBefore = related
        .where((w) => w.segments.length > target.length)
        .map((w) => cloneJson(_lookup(_root, w.segments)))
        .toList();
    change();
    if (related.isEmpty) return;
    final after = _lookup(_root, target);
    final targetChanged = !jsonEqual(before, after);
    var d = 0;
    final fire = <_Watch>[];
    for (final w in related) {
      if (w.segments.length <= target.length) {
        if (targetChanged) fire.add(w);
      } else {
        final old = descendantsBefore[d++];
        if (!jsonEqual(old, _lookup(_root, w.segments))) fire.add(w);
      }
    }
    for (final w in fire) {
      try {
        final v = _lookup(_root, w.segments);
        w.observer(identical(v, _absent) ? null : v, w.path);
      } catch (e) {
        debugPrint('A2UI data observer failed: $e');
      }
    }
  }
}

Object? _lookup(Object? root, List<String> segments) {
  Object? current = root;
  for (final seg in segments) {
    if (current is List) {
      if (!isIndexSegment(seg)) return _absent;
      final i = int.parse(seg);
      if (i >= current.length) return _absent;
      current = current[i];
    } else if (current is Map) {
      if (!current.containsKey(seg)) return _absent;
      current = current[seg];
    } else {
      return _absent;
    }
  }
  return current;
}

/// Validate a write before touching the model, so a failed write changes nothing.
void _checkWritable(Object? root, List<String> segments, String path) {
  Object? current = root;
  var vivified = false;
  for (var i = 0; i < segments.length; i++) {
    final seg = segments[i];
    bool isList;
    if (vivified || current == null) {
      // A missing or null slot (including a null root) becomes a container.
      isList = isIndexSegment(seg);
      vivified = true;
    } else if (current is List) {
      isList = true;
    } else if (current is Map) {
      isList = false;
    } else {
      throw dataError(
          'Cannot set path "$path": "${formatPointer(segments.sublist(0, i))}" holds a primitive value');
    }
    if (isList) {
      if (!isIndexSegment(seg)) {
        throw dataError(
            'Cannot set path "$path": non-numeric segment "$seg" addresses a list');
      }
      if (int.parse(seg) > maxListIndex) {
        throw dataError(
            'Cannot set path "$path": list index $seg exceeds the maximum of $maxListIndex');
      }
    }
    if (!vivified) {
      Object? next;
      if (current is List) {
        final idx = int.parse(seg);
        next = idx < current.length ? current[idx] : null;
      } else {
        next = (current as Map)[seg];
      }
      if (next == null) vivified = true;
      current = next;
    }
  }
}

void _padList(List list, int length) {
  while (list.length < length) {
    list.add(null);
  }
}

/// Deep copy of a JSON value into growable, `String`-keyed collections.
T cloneJson<T>(T value) {
  if (value is Map) {
    final out = <String, dynamic>{};
    value.forEach((k, v) {
      if (v is Function || identical(v, _absent)) return;
      out[k.toString()] = cloneJson(v);
    });
    return out as T;
  }
  if (value is List) {
    return value
        .map((v) => identical(v, _absent) ? null : cloneJson(v))
        .toList() as T;
  }
  return value;
}

/// Structural equality of JSON values (`-0` equals `0`, `1` equals `1.0`).
bool jsonEqual(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is num && b is num) return a == b;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!jsonEqual(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k)) return false;
      if (!jsonEqual(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List || b is List || a is Map || b is Map) return false;
  return a == b;
}
