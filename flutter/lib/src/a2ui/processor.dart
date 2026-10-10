/// The A2UI message processor — pure state, no UI.
///
/// It applies server-to-client messages to surfaces:
///
/// - `createSurface` registers a surface with its catalog (unknown catalog ids
///   are an error), theme and `sendDataModel` flag; creating an existing
///   surface is an error;
/// - `updateComponents` upserts the flat adjacency list. Components arriving
///   before `root` are buffered: a surface is renderable once `root` exists;
/// - `updateDataModel` writes (or, with no / null value, deletes) a JSON
///   Pointer path of the surface's data model; path `/` replaces it;
/// - `deleteSurface` removes the surface.
///
/// Inputs write back through [A2UIProcessor.setData] (two-way binding), and
/// interactions go through [A2UIProcessor.dispatchAction], which resolves an
/// `action.event` into the client-to-server `action` (name, surfaceId,
/// sourceComponentId, ISO timestamp, resolved context) and emits it, or runs
/// an `action.functionCall` locally. Listeners observe every change, action
/// and error.
library;

import 'package:flutter/foundation.dart';

import 'catalog.dart';
import 'context.dart';
import 'data_model.dart';
import 'errors.dart';
import 'validator.dart';

/// The protocol version this renderer speaks.
const String a2uiVersion = 'v0.9.1';

/// `strict` rejects a message with any schema issue; `lenient` (default)
/// reports issues but still applies what it can (unknown components render as
/// placeholders); `off` skips schema validation.
enum ValidationMode { strict, lenient, off }

/// A component: its JSON (`id`, `component` and its properties).
typedef A2UIComponent = Map<String, dynamic>;

/// The client-to-server `action` payload.
class A2UIClientAction {
  A2UIClientAction({
    required this.name,
    required this.surfaceId,
    required this.sourceComponentId,
    required this.timestamp,
    required this.context,
    this.userMessage,
  });

  final String name;
  final String surfaceId;
  final String sourceComponentId;
  final String timestamp;
  final Map<String, dynamic> context;

  /// Carried through when the action defines one (conformance `userMessage`).
  final String? userMessage;

  Map<String, dynamic> toJson() => {
        'name': name,
        'surfaceId': surfaceId,
        'sourceComponentId': sourceComponentId,
        'timestamp': timestamp,
        'context': context,
        if (userMessage != null) 'userMessage': userMessage,
      };
}

/// What happened in a processor: `surfaceCreated`, `surfaceUpdated` (with a
/// [reason] of `components`, `data` or `local`), `surfaceDeleted`, `action`
/// or `error`.
class A2UIProcessorEvent {
  A2UIProcessorEvent(this.type,
      {this.surfaceId, this.reason, this.action, this.error});
  final String type;
  final String? surfaceId;
  final String? reason;
  final A2UIClientAction? action;
  final A2UIError? error;
}

typedef A2UIProcessorListener = void Function(A2UIProcessorEvent event);

class A2UISurfaceModel {
  A2UISurfaceModel(this.id, this.catalog, this.catalogId, this.theme,
      this.sendDataModel, this._host);

  final String id;
  final A2UICatalog catalog;

  /// The catalog id exactly as `createSurface` named it.
  final String catalogId;
  final Map<String, dynamic> theme;
  final bool sendDataModel;
  final EvaluationHost _host;

  /// Components by id, in arrival order.
  final Map<String, A2UIComponent> components = {};
  final DataModel dataModel = DataModel();

  /// Bumped on every change (components, data, local writes).
  int version = 0;

  /// The `root` component, once it has arrived.
  A2UIComponent? get root => components['root'];

  /// Whether the surface can render (components are buffered until `root` exists).
  bool get isReady => components.containsKey('root');

  /// An evaluation context scoped to [scope].
  DataContext context([String scope = '/']) =>
      DataContext(dataModel, catalog, scope, _host);
}

class A2UIProcessor {
  A2UIProcessor({
    List<A2UICatalog>? catalogs,
    this.validation = ValidationMode.lenient,
    this.host = const EvaluationHost(),
  }) : catalogs = catalogs ?? [basicCatalog];

  final List<A2UICatalog> catalogs;
  final ValidationMode validation;
  final EvaluationHost host;
  final Map<String, A2UISurfaceModel> _surfaces = {};
  final List<A2UIProcessorListener> _listeners = [];

  /// Catalog ids this client supports (for `a2uiClientCapabilities`).
  List<String> get supportedCatalogIds => catalogs.map((c) => c.id).toList();

  A2UICatalog? catalogFor(String catalogId) {
    for (final c in catalogs) {
      if (c.id == catalogId || c.aliases.contains(catalogId)) return c;
    }
    return null;
  }

  VoidCallback on(A2UIProcessorListener listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _emit(A2UIProcessorEvent event) {
    for (final l in List.of(_listeners)) {
      try {
        l(event);
      } catch (e) {
        debugPrint('A2UI listener failed: $e');
      }
    }
  }

  A2UIError _report(A2UIError error) {
    _emit(
        A2UIProcessorEvent('error', surfaceId: error.surfaceId, error: error));
    return error;
  }

  /// Surfaces in creation order.
  List<A2UISurfaceModel> get surfaces => _surfaces.values.toList();

  A2UISurfaceModel? surface(String surfaceId) => _surfaces[surfaceId];

  /// Apply several messages; returns every error.
  List<A2UIError> processAll(Iterable<Object?> messages) => [
        for (final m in messages) ...process(m),
      ];

  /// Apply one server-to-client message; returns its errors (also emitted).
  List<A2UIError> process(Object? message) {
    final kind = messageKind(message);
    if (kind == null || message is! Map) {
      return [
        _report(A2UIError('ValidationError',
            'Not an A2UI message: expected one of createSurface, updateComponents, updateDataModel, deleteSurface',
            path: '/'))
      ];
    }
    final body = message[kind];
    final surfaceId = body is Map && body['surfaceId'] is String
        ? body['surfaceId'] as String
        : null;
    final errors = <A2UIError>[];
    if (validation != ValidationMode.off) {
      final catalog = surfaceId == null ? null : _surfaces[surfaceId]?.catalog;
      final issues = validateMessage(message, catalog ?? catalogs.first,
          requireVersion: validation == ValidationMode.strict);
      for (final e in issues) {
        errors.add(_report(e));
      }
      if (issues.isNotEmpty && validation == ValidationMode.strict) {
        return errors;
      }
    }
    if (surfaceId == null) {
      if (errors.isEmpty) {
        errors.add(_report(A2UIError(
            'ValidationError', '$kind requires a "surfaceId"',
            path: '/$kind/surfaceId')));
      }
      return errors;
    }
    final b = body as Map;
    List<A2UIError> fail(String message, [String? path]) {
      errors.add(_report(A2UIError('ValidationError', message,
          surfaceId: surfaceId, path: path ?? '/$kind')));
      return errors;
    }

    switch (kind) {
      case 'createSurface':
        if (_surfaces.containsKey(surfaceId)) {
          return fail(
              'Surface "$surfaceId" already exists; delete it before creating it again');
        }
        final catalogId =
            b['catalogId'] is String ? b['catalogId'] as String : '';
        final catalog = catalogFor(catalogId);
        if (catalog == null) {
          return fail(
              'Unsupported catalog "$catalogId" (supported: ${supportedCatalogIds.join(', ')})',
              '/createSurface/catalogId');
        }
        _surfaces[surfaceId] = A2UISurfaceModel(
            surfaceId,
            catalog,
            catalogId,
            b['theme'] is Map
                ? Map<String, dynamic>.from(b['theme'] as Map)
                : {},
            b['sendDataModel'] == true,
            host);
        _emit(A2UIProcessorEvent('surfaceCreated', surfaceId: surfaceId));
        return errors;
      case 'updateComponents':
        final surface = _surfaces[surfaceId];
        if (surface == null) {
          return fail('Surface "$surfaceId" has not been created');
        }
        final comps = b['components'];
        if (comps is! List) return errors;
        for (final c in comps) {
          if (c is! Map || c['id'] is! String || c['component'] is! String) {
            continue;
          }
          surface.components[c['id'] as String] =
              cloneJson(Map<String, dynamic>.from(c));
        }
        surface.version++;
        _emit(A2UIProcessorEvent('surfaceUpdated',
            surfaceId: surfaceId, reason: 'components'));
        return errors;
      case 'updateDataModel':
        final surface = _surfaces[surfaceId];
        if (surface == null) {
          return fail('Surface "$surfaceId" has not been created');
        }
        final path = b['path'] is String ? b['path'] as String : '/';
        try {
          // An omitted or null value removes the key (list slots become null).
          if (b['value'] == null) {
            surface.dataModel.delete(path);
          } else {
            surface.dataModel.set(path, b['value']);
          }
        } on A2UIError catch (e) {
          errors.add(_report(A2UIError(
              e.category == 'DataError' ? 'DataError' : 'ValidationError',
              e.message,
              surfaceId: surfaceId,
              path: '/updateDataModel/path')));
          return errors;
        }
        surface.version++;
        _emit(A2UIProcessorEvent('surfaceUpdated',
            surfaceId: surfaceId, reason: 'data'));
        return errors;
      case 'deleteSurface':
        final surface = _surfaces[surfaceId];
        if (surface == null) return fail('Surface "$surfaceId" does not exist');
        surface.dataModel.dispose();
        _surfaces.remove(surfaceId);
        _emit(A2UIProcessorEvent('surfaceDeleted', surfaceId: surfaceId));
        return errors;
    }
    return errors;
  }

  /// A local write through a two-way binding (an input changed).
  void setData(String surfaceId, String path, Object? value) {
    final surface = _surfaces[surfaceId];
    if (surface == null) return;
    try {
      surface.dataModel.set(path, value);
    } on A2UIError catch (e) {
      _report(
          A2UIError(e.category, e.message, surfaceId: surfaceId, path: path));
      return;
    }
    surface.version++;
    _emit(A2UIProcessorEvent('surfaceUpdated',
        surfaceId: surfaceId, reason: 'local'));
  }

  /// The surface's current data model (a copy), or null.
  Object? dataModel(String surfaceId) =>
      _surfaces[surfaceId]?.dataModel.snapshot();

  /// The `a2uiClientDataModel` metadata: the models of the surfaces created
  /// with `sendDataModel: true`, or null when there are none.
  Map<String, dynamic>? clientDataModel() {
    final surfaces = <String, dynamic>{};
    for (final s in _surfaces.values) {
      if (!s.sendDataModel) continue;
      surfaces[s.id] = s.dataModel.snapshot();
    }
    return surfaces.isEmpty
        ? null
        : {'version': a2uiVersion, 'surfaces': surfaces};
  }

  /// The user interacted with [componentId]: resolve its [action] in [scope].
  /// An `event` becomes an [A2UIClientAction], emitted and returned; a
  /// `functionCall` runs locally (returns null). Failures are reported and
  /// return null.
  A2UIClientAction? dispatchAction(
      String surfaceId, String componentId, Object? action,
      {String scope = '/', DateTime? now}) {
    final surface = _surfaces[surfaceId];
    if (surface == null) return null;
    try {
      final event = resolveAction(action, surface.context(scope));
      if (event == null) {
        surface.version++;
        _emit(A2UIProcessorEvent('surfaceUpdated',
            surfaceId: surfaceId, reason: 'local'));
        return null;
      }
      final out = A2UIClientAction(
        name: event.name,
        surfaceId: surfaceId,
        sourceComponentId: componentId,
        timestamp: (now ?? DateTime.now()).toUtc().toIso8601String(),
        context: event.context,
        userMessage: event.userMessage,
      );
      _emit(A2UIProcessorEvent('action', surfaceId: surfaceId, action: out));
      return out;
    } on A2UIError catch (e) {
      _report(A2UIError(e.category, e.message, surfaceId: surfaceId));
      return null;
    } catch (e) {
      _report(A2UIError('ExpressionError', e.toString(), surfaceId: surfaceId));
      return null;
    }
  }

  /// Remove every surface.
  void reset() {
    for (final id in _surfaces.keys.toList()) {
      _surfaces.remove(id)!.dataModel.dispose();
      _emit(A2UIProcessorEvent('surfaceDeleted', surfaceId: id));
    }
  }
}

/// The client-to-server message carrying [action].
Map<String, dynamic> clientActionMessage(A2UIClientAction action) =>
    {'version': a2uiVersion, 'action': action.toJson()};
