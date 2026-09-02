/// Native (dart:ffi) bindings for the Elpian governance control plane.
///
/// The whole control plane crosses as JSON, so five call shapes cover 22
/// exports and the bindings stay a table rather than a page of near-identical
/// typedefs. Every reply is freed through the same allocator that produced it
/// (`ElpianVmApi.freeNativeString`), so there is one loader and one free path
/// for the library as a whole.
///
/// Symbols are resolved lazily and individually: a library built before this
/// surface existed simply reports the missing call rather than failing to load,
/// which keeps an older `libelpian_vm.so` usable for everything else.
library;

import 'dart:convert';
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import '../frb_generated/api.dart';
import 'models.dart';

// ── Call shapes ─────────────────────────────────────────────────────

typedef _Str1C = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);
typedef _Str1Dart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);

typedef _Str2C = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
typedef _Str2Dart = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);

typedef _Str2IntC = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Int32);
typedef _Str2IntDart = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, int);

typedef _StrI64C = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>, ffi.Int64);
typedef _StrI64Dart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>, int);

typedef _Str0C = ffi.Pointer<Utf8> Function();
typedef _Str0Dart = ffi.Pointer<Utf8> Function();

/// The native governance surface.
///
/// Callers use `ElpianVmGovernor` rather than this directly; it is the thin
/// symbol layer beneath it. The web build provides a class of the same name and
/// shape in `web_bindings.dart`, selected by conditional import.
class GovernanceBindings {
  GovernanceBindings._();

  // `lookupFunction` needs a concrete native type at the call site, so the
  // cache is per shape rather than one generic map. Each entry records the
  // resolution attempt — including a failure — so a missing export is looked up
  // once, not on every call.
  final Map<String, _Str1Dart?> _str1 = {};
  final Map<String, _Str2Dart?> _str2 = {};
  final Map<String, _Str2IntDart?> _str2Int = {};
  final Map<String, _StrI64Dart?> _strI64 = {};
  final Map<String, _Str0Dart?> _str0 = {};

  /// Whether the loaded library carries the governance surface at all.
  ///
  /// False for a library built before this surface existed: everything else
  /// keeps working, and each governance call reports the missing export by
  /// name rather than crashing.
  bool get isAvailable =>
      ElpianVmApi.library != null && _resolve1('elpian_usage') != null;

  _Str1Dart? _resolve1(String symbol) => _str1.putIfAbsent(symbol, () {
        try {
          return ElpianVmApi.library?.lookupFunction<_Str1C, _Str1Dart>(symbol);
        } catch (_) {
          return null;
        }
      });

  _Str2Dart? _resolve2(String symbol) => _str2.putIfAbsent(symbol, () {
        try {
          return ElpianVmApi.library?.lookupFunction<_Str2C, _Str2Dart>(symbol);
        } catch (_) {
          return null;
        }
      });

  _Str2IntDart? _resolve2Int(String symbol) => _str2Int.putIfAbsent(symbol, () {
        try {
          return ElpianVmApi.library
              ?.lookupFunction<_Str2IntC, _Str2IntDart>(symbol);
        } catch (_) {
          return null;
        }
      });

  _StrI64Dart? _resolveI64(String symbol) => _strI64.putIfAbsent(symbol, () {
        try {
          return ElpianVmApi.library
              ?.lookupFunction<_StrI64C, _StrI64Dart>(symbol);
        } catch (_) {
          return null;
        }
      });

  _Str0Dart? _resolve0(String symbol) => _str0.putIfAbsent(symbol, () {
        try {
          return ElpianVmApi.library?.lookupFunction<_Str0C, _Str0Dart>(symbol);
        } catch (_) {
          return null;
        }
      });

  /// Consume a native reply: decode it, free it, and raise on the in-band
  /// error shape.
  Map<String, dynamic> _take(ffi.Pointer<Utf8> ptr, String call) {
    if (ptr == ffi.nullptr) {
      throw ElpianGovernanceException('native call returned null', call: call);
    }
    final raw = ptr.toDartString();
    ElpianVmApi.freeNativeString(ptr);
    return decodeGovernanceReply(raw, call: call);
  }

  /// Some replies are JSON arrays rather than objects (`enforceTreeBudgets`,
  /// the tree operations' `affected` lists are objects, but the sweep is an
  /// array), so this variant does not impose the object shape.
  List<dynamic> _takeList(ffi.Pointer<Utf8> ptr, String call) {
    if (ptr == ffi.nullptr) {
      throw ElpianGovernanceException('native call returned null', call: call);
    }
    final raw = ptr.toDartString();
    ElpianVmApi.freeNativeString(ptr);
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      throw ElpianGovernanceException('malformed reply: ${e.message}',
          call: call);
    }
    if (decoded is List) return decoded;
    if (decoded is Map && decoded['error'] is String) {
      throw ElpianGovernanceException(decoded['error'] as String, call: call);
    }
    throw ElpianGovernanceException('expected an array, got $raw', call: call);
  }

  ElpianGovernanceException _missing(String call) => ElpianGovernanceException(
        'the loaded native library does not export $call — rebuild it '
        '(cd rust && cargo build --release)',
        call: call,
      );

  /// `(machineId) -> json`
  Map<String, dynamic> call1(String symbol, String machineId) {
    final fn = _resolve1(symbol);
    if (fn == null) throw _missing(symbol);
    final id = machineId.toNativeUtf8();
    try {
      return _take(fn(id), symbol);
    } finally {
      malloc.free(id);
    }
  }

  /// `(machineId) -> json array`
  List<dynamic> call1List(String symbol, String machineId) {
    final fn = _resolve1(symbol);
    if (fn == null) throw _missing(symbol);
    final id = machineId.toNativeUtf8();
    try {
      return _takeList(fn(id), symbol);
    } finally {
      malloc.free(id);
    }
  }

  /// `(machineId, arg) -> json`
  Map<String, dynamic> call2(String symbol, String machineId, String arg) {
    final fn = _resolve2(symbol);
    if (fn == null) throw _missing(symbol);
    final id = machineId.toNativeUtf8();
    final a = arg.toNativeUtf8();
    try {
      return _take(fn(id, a), symbol);
    } finally {
      malloc.free(id);
      malloc.free(a);
    }
  }

  /// `(machineId, arg, flag) -> json`
  Map<String, dynamic> call2Int(
      String symbol, String machineId, String arg, int flag) {
    final fn = _resolve2Int(symbol);
    if (fn == null) throw _missing(symbol);
    final id = machineId.toNativeUtf8();
    final a = arg.toNativeUtf8();
    try {
      return _take(fn(id, a, flag), symbol);
    } finally {
      malloc.free(id);
      malloc.free(a);
    }
  }

  /// `(machineId, i64) -> json`
  Map<String, dynamic> callI64(String symbol, String machineId, int value) {
    final fn = _resolveI64(symbol);
    if (fn == null) throw _missing(symbol);
    final id = machineId.toNativeUtf8();
    try {
      return _take(fn(id, value), symbol);
    } finally {
      malloc.free(id);
    }
  }

  /// `() -> json array`
  List<dynamic> call0List(String symbol) {
    final fn = _resolve0(symbol);
    if (fn == null) throw _missing(symbol);
    return _takeList(fn(), symbol);
  }
}

/// The platform's governance bindings. The web build provides the same name
/// from `web_bindings.dart`, so callers need no conditional logic of their own.
final GovernanceBindings governanceBindings = GovernanceBindings._();
