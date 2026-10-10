/// `DataContext` — evaluation of dynamic values within a data scope.
///
/// A dynamic value is a literal, a data binding `{ "path": "…" }` or a function
/// call `{ "call": "…", "args": {…}, "returnType": "…" }`. Paths are absolute
/// (`/user/name`) or relative to the context's scope (the template item a
/// component was instantiated for, e.g. `/users/0`). Function arguments are
/// evaluated recursively — lists element by element — before the function runs.
library;

import 'catalog.dart';
import 'data_model.dart';
import 'errors.dart';
import 'functions.dart';
import 'pointer.dart' as pointer;

class EvaluationHost {
  const EvaluationHost({
    this.locale = 'en-US',
    this.baseUrl,
    this.openUrl,
    this.onCall,
  });

  /// BCP 47 locale for formatting (default `en-US`).
  final String locale;

  /// Base for relative URLs (`openUrl`).
  final String? baseUrl;

  /// Perform `openUrl` (already validated to be http/https).
  final void Function(String url)? openUrl;

  /// Observe a function call before it runs (tests, tracing).
  final void Function(String name, Map<String, dynamic> args)? onCall;
}

/// `{ "path": "…" }` and nothing else.
bool isBinding(Object? v) =>
    v is Map && v['path'] is String && v.keys.every((k) => k == 'path');

/// `{ "call": "…", "args"?: {…}, "returnType"?: "…" }`.
bool isFunctionCall(Object? v) =>
    v is Map &&
    v['call'] is String &&
    v.keys.every((k) => k == 'call' || k == 'args' || k == 'returnType');

class DataContext {
  DataContext(this.model, this.catalog,
      [this.scope = '/', this.host = const EvaluationHost()]);

  final DataModel model;
  final A2UICatalog catalog;

  /// The data scope relative paths resolve against (`/` at the root).
  final String scope;
  final EvaluationHost host;

  String get locale => host.locale;

  /// A context scoped to [scope] (an absolute pointer).
  DataContext child(String scope) => DataContext(model, catalog, scope, host);

  String resolvePath(String path) => pointer.resolvePath(path, scope);

  Object? read(String path) => model.get(resolvePath(path));

  void write(String path, Object? value) => model.set(resolvePath(path), value);

  /// The absolute path a binding writes to, or null when [value] is not a binding.
  String? bindingPath(Object? value) =>
      isBinding(value) ? resolvePath((value as Map)['path'] as String) : null;

  /// Evaluate a dynamic property value (literal lists stay literal).
  Object? evaluate(Object? value) {
    if (isBinding(value)) return read((value as Map)['path'] as String);
    if (isFunctionCall(value)) {
      final m = value as Map;
      return call(m['call'] as String,
          m['args'] is Map ? Map<String, dynamic>.from(m['args'] as Map) : {});
    }
    return value;
  }

  /// Evaluate and coerce to a string (`''` for null).
  String string(Object? value) => stringifyValue(evaluate(value));

  /// Evaluate and coerce to a number (null when not numeric).
  num? number(Object? value) => toNum(evaluate(value));

  bool boolean(Object? value) => toBool(evaluate(value));

  /// Evaluate to a list of strings (non-lists become `[]`, a lone string `[s]`).
  List<String> stringList(Object? value) {
    final v = evaluate(value);
    if (v is List) {
      return v.where((x) => x != null).map(stringifyValue).toList();
    }
    if (v is String && v.isNotEmpty) return [v];
    return [];
  }

  /// Evaluate a function argument: bindings, calls, and lists of them.
  Object? argument(Object? value) {
    if (value is List) return value.map(argument).toList();
    return evaluate(value);
  }

  /// Call catalog function [name] with unevaluated [args].
  Object? call(String name, Map<String, dynamic> args) {
    final impl = catalog.implementations[name];
    if (impl == null) throw expressionError('Unknown function "$name"');
    final resolved = <String, dynamic>{};
    args.forEach((k, v) => resolved[k] = argument(v));
    host.onCall?.call(name, resolved);
    return impl(resolved, _FunctionContext(this));
  }

  /// Evaluate without throwing: expression errors (unknown function, bad
  /// template) yield [fallback] and are reported to [onError].
  T safe<T>(T Function() fn, T fallback,
      [void Function(A2UIError e)? onError]) {
    try {
      return fn();
    } on A2UIError catch (e) {
      onError?.call(e);
      return fallback;
    } catch (e) {
      onError?.call(expressionError(e.toString()));
      return fallback;
    }
  }
}

class _FunctionContext implements FunctionContext {
  _FunctionContext(this.ctx);
  final DataContext ctx;

  @override
  String get locale => ctx.locale;

  @override
  String? get baseUrl => ctx.host.baseUrl;

  @override
  Object? read(String path) => ctx.read(path);

  @override
  Object? call(String name, Map<String, dynamic> args) => ctx.call(name, args);

  @override
  void openUrl(String url) => ctx.host.openUrl?.call(url);
}

/// Run a component's `checks` and return the messages of those that fail. A
/// check is `{ condition, message }`; the protocol document's shorthand
/// `{ call, args, message }` is accepted too.
List<String> evaluateChecks(Object? checks, DataContext ctx,
    [void Function(A2UIError e)? onError]) {
  if (checks is! List) return [];
  final failures = <String>[];
  for (final check in checks) {
    if (check is! Map) continue;
    final Object? condition = check.containsKey('condition')
        ? check['condition']
        : check['call'] is String
            ? <String, dynamic>{
                'call': check['call'],
                'args': check['args'] ?? <String, dynamic>{},
              }
            : true;
    final ok = ctx.safe(() => ctx.boolean(condition), false, onError);
    if (!ok) {
      failures.add(check['message'] is String
          ? check['message'] as String
          : 'Invalid value');
    }
  }
  return failures;
}

/// An `action.event` with its context resolved.
class ResolvedEvent {
  ResolvedEvent(this.name, this.context, [this.userMessage]);
  final String name;
  final Map<String, dynamic> context;
  final String? userMessage;
}

/// Resolve an `Action`: `{ event: { name, context } }` (also the v0.9 shorthand
/// `{ name, context }`) becomes a [ResolvedEvent] with every context value
/// evaluated now; `{ functionCall }` runs locally and yields null.
ResolvedEvent? resolveAction(Object? action, DataContext ctx) {
  if (action is! Map) throw expressionError('Action must be an object');
  final fc = action['functionCall'];
  if (fc is Map) {
    if (fc['call'] is! String) {
      throw expressionError('functionCall needs a "call" name');
    }
    ctx.call(fc['call'] as String,
        fc['args'] is Map ? Map<String, dynamic>.from(fc['args'] as Map) : {});
    return null;
  }
  final Map? event = action['event'] is Map
      ? action['event'] as Map
      : action['name'] is String
          ? action
          : null;
  if (event == null || event['name'] is! String) {
    throw expressionError('Action needs an "event" with a "name"');
  }
  final context = <String, dynamic>{};
  final raw = event['context'];
  if (raw is Map) {
    raw.forEach((k, v) => context[k.toString()] = ctx.evaluate(v));
  }
  return ResolvedEvent(event['name'] as String, context,
      event['userMessage'] is String ? event['userMessage'] as String : null);
}
