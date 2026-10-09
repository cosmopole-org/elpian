/// Web (WASM) bindings for the Elpian governance control plane.
///
/// The twin of `native_bindings.dart`: same class name, same call shapes,
/// selected by conditional import so `ElpianVmGovernor` is written once. A mini
/// app running on the web is governed by the same VM code enforcing the same
/// budgets — the only difference is how the call crosses.
///
/// The WASM module must be loaded first (see `elpian_wasm_loader.js`). Until it
/// is, [GovernanceBindings.isAvailable] is false and the governor reports
/// [GovernanceSupport.none] rather than claiming protection it cannot give.
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'models.dart';

// ── JS interop bindings ──────────────────────────────────────────────
//
// wasm-bindgen exports each function as a global. Rather than one `external`
// per export, the dispatch below looks the function up by name on the global
// object, which keeps this file a table like its native counterpart and lets a
// module built before this surface existed report the missing call by name.

/// The web governance surface.
class GovernanceBindings {
  GovernanceBindings._();

  final Map<String, JSFunction?> _resolved = {};

  /// Whether the loaded WASM module carries the governance surface.
  bool get isAvailable => _resolve('elpian_wasm_usage') != null;

  JSFunction? _resolve(String symbol) => _resolved.putIfAbsent(symbol, () {
        try {
          // `getProperty<JSFunction?>` rather than `isA`, which needs a
          // newer SDK than this package's floor.
          return globalContext.getProperty<JSFunction?>(symbol.toJS);
        } catch (_) {
          return null;
        }
      });

  /// The native symbol names are `elpian_*`; the WASM exports are
  /// `elpian_wasm_*`. Callers use the native spelling so the two backends take
  /// identical call sites.
  String _wasmName(String symbol) =>
      symbol.startsWith('elpian_') && !symbol.startsWith('elpian_wasm_')
          ? symbol.replaceFirst('elpian_', 'elpian_wasm_')
          : symbol;

  Never _missing(String call) => throw ElpianGovernanceException(
        'the loaded Elpian WASM module does not export ${_wasmName(call)} — '
        'rebuild it (cd rust/crates/elpian-vm && wasm-pack build --target web)',
        call: call,
      );

  Object? _decode(JSAny? raw, String call) {
    final text = (raw as JSString?)?.toDart;
    if (text == null) {
      throw ElpianGovernanceException('wasm call returned nothing', call: call);
    }
    try {
      return jsonDecode(text);
    } on FormatException catch (e) {
      throw ElpianGovernanceException('malformed reply: ${e.message}',
          call: call);
    }
  }

  Map<String, dynamic> _asObject(Object? decoded, String call) {
    if (decoded is! Map<String, dynamic>) {
      throw ElpianGovernanceException('expected an object, got $decoded',
          call: call);
    }
    final error = decoded['error'];
    if (error is String) {
      throw ElpianGovernanceException(error, call: call);
    }
    return decoded;
  }

  List<dynamic> _asList(Object? decoded, String call) {
    if (decoded is List) return decoded;
    if (decoded is Map && decoded['error'] is String) {
      throw ElpianGovernanceException(decoded['error'] as String, call: call);
    }
    throw ElpianGovernanceException('expected an array, got $decoded',
        call: call);
  }

  JSAny? _invoke(String symbol, List<JSAny?> args) {
    final fn = _resolve(_wasmName(symbol));
    if (fn == null) _missing(symbol);
    return fn.callAsFunction(null, args[0], args.length > 1 ? args[1] : null,
        args.length > 2 ? args[2] : null);
  }

  /// `(machineId) -> json`
  Map<String, dynamic> call1(String symbol, String machineId) =>
      _asObject(_decode(_invoke(symbol, [machineId.toJS]), symbol), symbol);

  /// `(machineId) -> json array`
  List<dynamic> call1List(String symbol, String machineId) =>
      _asList(_decode(_invoke(symbol, [machineId.toJS]), symbol), symbol);

  /// `(machineId, arg) -> json`
  Map<String, dynamic> call2(String symbol, String machineId, String arg) =>
      _asObject(
          _decode(_invoke(symbol, [machineId.toJS, arg.toJS]), symbol), symbol);

  /// `(machineId, arg, flag) -> json`
  ///
  /// The WASM export takes a real boolean where the C ABI takes an int, so the
  /// flag is converted here and call sites stay identical across backends.
  Map<String, dynamic> call2Int(
          String symbol, String machineId, String arg, int flag) =>
      _asObject(
          _decode(_invoke(symbol, [machineId.toJS, arg.toJS, (flag != 0).toJS]),
              symbol),
          symbol);

  /// `(machineId, number) -> json`
  Map<String, dynamic> callI64(String symbol, String machineId, int value) =>
      _asObject(_decode(_invoke(symbol, [machineId.toJS, value.toJS]), symbol),
          symbol);

  /// `() -> json array`
  List<dynamic> call0List(String symbol) {
    final fn = _resolve(_wasmName(symbol));
    if (fn == null) _missing(symbol);
    return _asList(_decode(fn.callAsFunction(), symbol), symbol);
  }
}

/// The platform's governance bindings. The native build provides the same name
/// from `native_bindings.dart`.
final GovernanceBindings governanceBindings = GovernanceBindings._();
