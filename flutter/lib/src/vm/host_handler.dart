import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../canvas/canvas_api.dart';
import '../canvas/canvas_context_store.dart';
import '../core/dom_api.dart';
import '../core/elpian_services.dart';
import 'host_api_catalog.dart';

typedef RenderHostCallback = void Function(
  Map<String, dynamic> viewJson,
  String? scopeKey,
);

class HostHandler {
  final RenderHostCallback? onRender;
  final void Function(Map<String, dynamic> updateData)? onUpdateApp;
  final void Function(String message)? onPrintln;
  final Map<String, dynamic> Function()? onGetEnvironment;

  /// Called when a guest reaches for a host API this handler does not
  /// implement. `advertised` distinguishes an API the VM offers but Dart has
  /// not wired up from a name nothing knows. Useful for a super-app host that
  /// wants to see what its mini apps are asking for.
  final void Function(String apiName, bool advertised)? onUnservicedApi;

  /// Called when [onAuthorize] refuses a call — the hook a super app uses to
  /// log or surface what a mini app tried to reach for.
  final void Function(String apiName)? onCallRefused;

  final ElpianDOM dom;
  final CanvasAPIExecutor canvas;

  /// The mini app this handler serves. Its canvas store is the one guests
  /// reach, and its [ElpianServices.appId] namespaces every id they choose.
  final ElpianServices services;

  /// Where `canvas.ctx.*` calls land.
  ///
  /// This used to be the process-wide `CanvasContextStore.instance`, keyed by
  /// an id the *guest* supplies. `create(id: "main")` returned the existing
  /// context if that id was taken, so one mini app asking for an obvious name
  /// was handed another's pixels and command list. Now each mini app has its
  /// own store, and [_scoped] prefixes every id with the app it belongs to, so
  /// a collision cannot cross an app boundary even if the stores were shared.
  CanvasContextStore get _canvasContexts => services.canvasContexts;

  String _scoped(String id) => services.scopeId(id);

  HostHandler({
    this.onRender,
    this.onUpdateApp,
    this.onPrintln,
    this.onGetEnvironment,
    this.onUnservicedApi,
    this.onAuthorize,
    this.onCallRefused,
    ElpianDOM? dom,
    CanvasAPIExecutor? canvas,
    ElpianServices? services,
  })  : dom = dom ?? ElpianDOM(),
        canvas = canvas ?? CanvasAPIExecutor(),
        services = services ?? ElpianServices.shared;

  /// Consulted before every host call. Return false to refuse it.
  ///
  /// The Elpian VM gates `askHost` by capability before a call ever reaches
  /// Dart, so this is a second gate rather than the only one. It matters for
  /// two reasons: the QuickJS and WASM backends have no such gate of their
  /// own, and a super-app host may want a policy the VM's capability families
  /// cannot express — a per-mini-app allowlist, a consent prompt, a kill
  /// switch. Left null, every call the handler implements is serviced.
  final bool Function(String apiName)? onAuthorize;

  String handleHostCall(String apiName, String payload) {
    if (onAuthorize != null && !onAuthorize!(apiName)) {
      onCallRefused?.call(apiName);
      assert(() {
        debugPrint(
            'HostHandler[${services.appId}]: $apiName refused by policy');
        return true;
      }());
      // The typed null the VM produces for a denied capability, so a guest sees
      // one behaviour whether the refusal came from the VM or from here.
      return _nullResponse();
    }

    if (VmHostApiCatalog.domApiNames.contains(apiName)) {
      return _handleDomApi(apiName, payload);
    }
    if (VmHostApiCatalog.canvasApiNames.contains(apiName)) {
      return _handleCanvasApi(apiName, payload);
    }

    switch (apiName) {
      case 'render':
        return handleRender(payload);
      case 'updateApp':
        return handleUpdateApp(payload);
      case 'println':
        return handlePrintln(payload);
      case 'env.get':
        return handleEnvGet(payload);
      case 'stringify':
        return handleStringify(payload);
      default:
        return _unserviced(apiName);
    }
  }

  /// The reply for a host API this handler does not implement.
  ///
  /// This branch used to return `i16 0`, which is indistinguishable from a
  /// successful call that happened to return zero. It catches every API the VM
  /// advertises but Dart does not service — all of `fs.*`, `net.*`, `gpu.*`,
  /// `time.*`, `random.*`, `task.*` and `host.*` — so a guest calling
  /// `time.now()` was quietly told the time was 0 rather than that nothing was
  /// listening.
  ///
  /// Returning null instead matches what the VM itself does for a
  /// capability-denied call: the interface is unplugged, and a guest that
  /// checks its result can tell. [onUnservicedApi] lets a host see which
  /// surface a mini app is reaching for.
  String _unserviced(String apiName) {
    final known = VmHostApiCatalog.allHostApiNames.contains(apiName);
    onUnservicedApi?.call(apiName, known);
    assert(() {
      debugPrint(
        known
            ? 'HostHandler: $apiName is advertised by the VM but not serviced '
                'here; returning null'
            : 'HostHandler: unknown host API $apiName; returning null',
      );
      return true;
    }());
    return _nullResponse();
  }

  /// A typed null — the same shape the VM produces when a capability is denied.
  String _nullResponse() => jsonEncode({
        'type': 'null',
        'data': {'value': null},
      });

  String handleRender(String payload) {
    try {
      final dynamic parsed = _parseVmPayload(payload);
      final args = _asHostArgs(parsed);
      final viewArg = args.isNotEmpty ? args.first : null;
      final scopeKey = args.length > 1 ? _asNullableString(args[1]) : null;

      final viewJson = _coerceJsonMap(viewArg);
      if (viewJson != null) {
        onRender?.call(viewJson, scopeKey);
      } else if (viewArg is String) {
        onRender?.call(
          {
            'type': 'Text',
            'props': {'text': viewArg},
          },
          scopeKey,
        );
      }
      return _makeResponse('i16', 0);
    } catch (e) {
      debugPrint('HostHandler: render error: $e');
      return _makeResponse('i16', 0);
    }
  }

  String handleUpdateApp(String payload) {
    try {
      final dynamic parsed = _unwrapHostArgs(_parseVmPayload(payload));
      if (parsed is Map<String, dynamic>) {
        onUpdateApp?.call(parsed);
      }
      return _makeResponse('i16', 0);
    } catch (e) {
      debugPrint('HostHandler: updateApp error: $e');
      return _makeResponse('i16', 0);
    }
  }

  String handlePrintln(String payload) {
    final dynamic parsed = _unwrapHostArgs(_parseVmPayload(payload));
    final message = parsed is String ? parsed : payload;
    onPrintln?.call(message);
    return _makeResponse('i16', 0);
  }

  String handleStringify(String payload) {
    return _makeResponse('string', payload);
  }

  String handleEnvGet(String payload) {
    final data = onGetEnvironment?.call() ?? const <String, dynamic>{};
    return _makeResponse('object', data);
  }

  String _handleDomApi(String apiName, String payload) {
    try {
      final args = _normalizedArgs(payload);
      switch (apiName) {
        case 'dom.createElement':
          final tagName = args['tagName']?.toString() ?? 'div';
          final id = args['id']?.toString();
          final classes =
              (args['classes'] as List?)?.map((e) => e.toString()).toList();
          final element = dom.createElement(tagName, id: id, classes: classes);
          return _makeResponse('object', _encodeElement(element));
        case 'dom.getElementById':
          return _makeResponse('object',
              _encodeElement(dom.getElementById(args['id']?.toString() ?? '')));
        case 'dom.getElementsByClassName':
          return _makeResponse(
              'array',
              _encodeElements(dom.getElementsByClassName(
                  args['className']?.toString() ?? '')));
        case 'dom.getElementsByTagName':
          return _makeResponse(
              'array',
              _encodeElements(
                  dom.getElementsByTagName(args['tagName']?.toString() ?? '')));
        case 'dom.querySelector':
          return _makeResponse(
              'object',
              _encodeElement(
                  dom.querySelector(args['selector']?.toString() ?? '')));
        case 'dom.querySelectorAll':
          return _makeResponse(
              'array',
              _encodeElements(
                  dom.querySelectorAll(args['selector']?.toString() ?? '')));
        case 'dom.removeElement':
          final element = _elementFromArgs(args);
          if (element != null) dom.removeElement(element);
          return _makeResponse('i16', 0);
        case 'dom.clear':
          dom.clear();
          return _makeResponse('i16', 0);
        case 'dom.setTextContent':
          _elementFromArgs(args)?.textContent = args['text']?.toString();
          return _makeResponse('i16', 0);
        case 'dom.setInnerHtml':
          _elementFromArgs(args)?.innerHTML = args['html']?.toString();
          return _makeResponse('i16', 0);
        case 'dom.setAttribute':
          _elementFromArgs(args)
              ?.setAttribute(args['name']?.toString() ?? '', args['value']);
          return _makeResponse('i16', 0);
        case 'dom.getAttribute':
          return _makeResponse(
              'string',
              (_elementFromArgs(args)
                          ?.getAttribute(args['name']?.toString() ?? '') ??
                      '')
                  .toString());
        case 'dom.removeAttribute':
          _elementFromArgs(args)
              ?.removeAttribute(args['name']?.toString() ?? '');
          return _makeResponse('i16', 0);
        case 'dom.hasAttribute':
          return _makeResponse(
              'bool',
              _elementFromArgs(args)
                      ?.hasAttribute(args['name']?.toString() ?? '') ??
                  false);
        case 'dom.setStyle':
          _elementFromArgs(args)
              ?.setStyle(args['property']?.toString() ?? '', args['value']);
          return _makeResponse('i16', 0);
        case 'dom.getStyle':
          return _makeResponse(
              'string',
              (_elementFromArgs(args)
                          ?.getStyle(args['property']?.toString() ?? '') ??
                      '')
                  .toString());
        case 'dom.setStyleObject':
          final styles =
              Map<String, dynamic>.from(args['styles'] as Map? ?? const {});
          _elementFromArgs(args)?.setStyleObject(styles);
          return _makeResponse('i16', 0);
        case 'dom.addClass':
          _elementFromArgs(args)?.addClass(args['className']?.toString() ?? '');
          return _makeResponse('i16', 0);
        case 'dom.removeClass':
          _elementFromArgs(args)
              ?.removeClass(args['className']?.toString() ?? '');
          return _makeResponse('i16', 0);
        case 'dom.hasClass':
          return _makeResponse(
              'bool',
              _elementFromArgs(args)
                      ?.hasClass(args['className']?.toString() ?? '') ??
                  false);
        case 'dom.toggleClass':
          _elementFromArgs(args)
              ?.toggleClass(args['className']?.toString() ?? '');
          return _makeResponse('i16', 0);
        case 'dom.appendChild':
          final parent = _elementFromArgs(args, key: 'parentId');
          final child = _elementFromArgs(args, key: 'childId');
          if (parent != null && child != null) parent.appendChild(child);
          return _makeResponse('i16', 0);
        case 'dom.insertBefore':
          final parent = _elementFromArgs(args, key: 'parentId');
          final newChild = _elementFromArgs(args, key: 'newChildId');
          final refChild = _elementFromArgs(args, key: 'referenceChildId');
          if (parent != null && newChild != null) {
            parent.insertBefore(newChild, refChild);
          }
          return _makeResponse('i16', 0);
        case 'dom.removeChild':
          final parent = _elementFromArgs(args, key: 'parentId');
          final child = _elementFromArgs(args, key: 'childId');
          if (parent != null && child != null) parent.removeChild(child);
          return _makeResponse('i16', 0);
        case 'dom.replaceChild':
          final parent = _elementFromArgs(args, key: 'parentId');
          final newChild = _elementFromArgs(args, key: 'newChildId');
          final oldChild = _elementFromArgs(args, key: 'oldChildId');
          if (parent != null && newChild != null && oldChild != null) {
            parent.replaceChild(newChild, oldChild);
          }
          return _makeResponse('i16', 0);
        case 'dom.addEventListener':
          final element = _elementFromArgs(args);
          final event = args['event']?.toString() ?? '';
          final callbackName = args['callback']?.toString();
          if (element != null && callbackName != null) {
            element.addEventListener(
                event,
                () => onUpdateApp?.call({
                      'domEvent': callbackName,
                      'elementId': element.id,
                      'event': event
                    }));
          }
          return _makeResponse('i16', 0);
        case 'dom.removeEventListener':
          _elementFromArgs(args)
              ?.removeEventListener(args['event']?.toString() ?? '');
          return _makeResponse('i16', 0);
        case 'dom.dispatchEvent':
          _elementFromArgs(args)?.dispatchEvent(args['event']?.toString() ?? '',
              data: args['data']);
          return _makeResponse('i16', 0);
        case 'dom.toJson':
          final element = _elementFromArgs(args);
          return _makeResponse(
              'object',
              element == null
                  ? <String, dynamic>{}
                  : element.toElpianNode().toJson());
        case 'dom.getAllElements':
          return _makeResponse('array', _encodeElements(dom.allElements));
      }
      return _makeResponse('i16', 0);
    } catch (e) {
      debugPrint('HostHandler: dom API error ($apiName): $e');
      return _makeResponse('i16', 0);
    }
  }

  String _handleCanvasApi(String apiName, String payload) {
    try {
      if (apiName.startsWith('canvas.ctx.')) {
        return _handleCanvasContextApi(apiName, payload);
      }

      final args = _normalizedArgs(payload);
      if (apiName == 'canvas.clear') {
        canvas.clear();
        return _makeResponse('i16', 0);
      }
      if (apiName == 'canvas.getCommands') {
        return _makeResponse(
            'array', canvas.commands.map((c) => c.toJson()).toList());
      }
      if (apiName == 'canvas.addCommand') {
        final command = _canvasCommandFromArgs(args);
        if (command != null) canvas.addCommand(command);
        return _makeResponse('i16', 0);
      }
      if (apiName == 'canvas.addCommands') {
        final raw = args['commands'] as List? ?? const [];
        final commands = raw
            .whereType<Map>()
            .map((e) => CanvasCommand.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        canvas.addCommands(commands);
        return _makeResponse('i16', 0);
      }

      final commandName = apiName.replaceFirst('canvas.', '');
      final type = _findCanvasType(commandName);
      if (type != null) {
        canvas.addCommand(CanvasCommand(type: type, params: args));
      }
      return _makeResponse('i16', 0);
    } catch (e) {
      debugPrint('HostHandler: canvas API error ($apiName): $e');
      return _makeResponse('i16', 0);
    }
  }

  String _handleCanvasContextApi(String apiName, String payload) {
    final args = _normalizedArgs(payload);
    switch (apiName) {
      case 'canvas.ctx.create':
        {
          final id = args['id']?.toString();
          final width = _toDouble(args['width']) ?? 0;
          final height = _toDouble(args['height']) ?? 0;
          final ctx = _canvasContexts.create(
            id: (id == null || id.isEmpty) ? null : _scoped(id),
            width: width,
            height: height,
          );
          // Hand back the id the guest asked for, not the namespaced one it is
          // stored under: the guest passes its own id to every later
          // `canvas.ctx.*` call, and those scope it again on the way in.
          // Returning the scoped id would double-prefix on the next lookup.
          return _makeResponse('string', id ?? ctx.id);
        }
      case 'canvas.ctx.dispose':
        {
          final id = args['id']?.toString();
          if (id != null && id.isNotEmpty) {
            _canvasContexts.dispose(_scoped(id));
          }
          return _makeResponse('i16', 0);
        }
      case 'canvas.ctx.clear':
        {
          final id = args['id']?.toString();
          final ctx = id == null ? null : _canvasContexts.get(_scoped(id));
          ctx?.clear();
          return _makeResponse('i16', 0);
        }
      case 'canvas.ctx.setSize':
        {
          final id = args['id']?.toString();
          final ctx = id == null ? null : _canvasContexts.get(_scoped(id));
          if (ctx != null) {
            final width = _toDouble(args['width']) ?? ctx.width;
            final height = _toDouble(args['height']) ?? ctx.height;
            ctx.setSize(width, height);
          }
          return _makeResponse('i16', 0);
        }
      case 'canvas.ctx.addCommand':
        {
          final id = args['id']?.toString();
          final ctx = id == null ? null : _canvasContexts.get(_scoped(id));
          if (ctx == null) return _makeResponse('i16', 0);
          final commandJson = args['command'] ?? args;
          if (commandJson is Map) {
            final cmd =
                CanvasCommand.fromJson(Map<String, dynamic>.from(commandJson));
            ctx.addCommand(cmd);
          }
          return _makeResponse('i16', 0);
        }
      case 'canvas.ctx.addCommands':
        {
          final id = args['id']?.toString();
          final ctx = id == null ? null : _canvasContexts.get(_scoped(id));
          if (ctx == null) return _makeResponse('i16', 0);
          final raw = args['commands'];
          if (raw is List) {
            final commands = raw
                .whereType<Map>()
                .map((entry) =>
                    CanvasCommand.fromJson(Map<String, dynamic>.from(entry)))
                .toList();
            ctx.addCommands(commands);
          }
          return _makeResponse('i16', 0);
        }
    }
    return _makeResponse('i16', 0);
  }

  double? _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  CanvasCommandType? _findCanvasType(String commandName) {
    for (final value in CanvasCommandType.values) {
      if (value.name == commandName) return value;
    }
    return null;
  }

  CanvasCommand? _canvasCommandFromArgs(Map<String, dynamic> args) {
    final typeRaw = args['type']?.toString();
    if (typeRaw == null) return null;
    final type = _findCanvasType(typeRaw);
    if (type == null) return null;
    final params =
        Map<String, dynamic>.from(args['params'] as Map? ?? const {});
    return CanvasCommand(
        type: type, params: params, id: args['id']?.toString());
  }

  ElpianElement? _elementFromArgs(Map<String, dynamic> args,
      {String key = 'id'}) {
    final id = args[key]?.toString() ?? args['selector']?.toString();
    if (id == null || id.isEmpty) return null;
    return dom.getElementById(id) ?? dom.querySelector(id);
  }

  List<Map<String, dynamic>> _encodeElements(List<ElpianElement> elements) {
    return elements
        .map(_encodeElement)
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Map<String, dynamic>? _encodeElement(ElpianElement? element) {
    if (element == null) return null;
    return {
      'id': element.id,
      'tagName': element.tagName,
      'classes': element.classes,
      'attributes': element.attributes,
      'style': element.style,
      'textContent': element.textContent,
      'children': element.children.map((child) => child.id).toList(),
    };
  }

  dynamic _parseVmPayload(String payload) {
    if (payload.isEmpty) return null;
    try {
      return jsonDecode(payload);
    } catch (_) {
      if (payload.startsWith('"') && payload.endsWith('"')) {
        return payload.substring(1, payload.length - 1);
      }
      return payload;
    }
  }

  dynamic _unwrapHostArgs(dynamic parsed) {
    if (parsed is List<dynamic>) {
      if (parsed.isEmpty) return null;
      return parsed.first;
    }
    return parsed;
  }

  Map<String, dynamic> _normalizedArgs(String payload) {
    final parsed = _parseVmPayload(payload);
    final unwrapped = _unwrapHostArgs(parsed);
    if (unwrapped is Map<String, dynamic>) return unwrapped;
    if (unwrapped is Map) return Map<String, dynamic>.from(unwrapped);
    return {};
  }

  List<dynamic> _asHostArgs(dynamic parsed) {
    if (parsed is List<dynamic>) return parsed;
    return <dynamic>[parsed];
  }

  String? _asNullableString(dynamic value) {
    if (value == null) return null;
    final parsed = value.toString().trim();
    if (parsed.isEmpty || parsed == 'null') return null;
    return parsed;
  }

  Map<String, dynamic>? _coerceJsonMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is! String) return null;

    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Not a JSON map; caller can decide fallback behavior.
    }
    return null;
  }

  String _makeResponse(String type, dynamic value) {
    return jsonEncode({
      'type': type,
      'data': {'value': value},
    });
  }
}
