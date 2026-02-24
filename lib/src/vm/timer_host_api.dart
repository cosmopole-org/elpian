import 'dart:async';
import 'dart:convert';

typedef VmTimerInvoke = Future<void> Function(String funcName, String? inputJson);

class VmTimerHostApi {
  final VmTimerInvoke _invoke;
  final void Function(String message)? _onError;

  int _nextId = 1;
  final Map<int, Timer> _timeouts = {};
  final Map<int, Timer> _intervals = {};

  VmTimerHostApi({
    required VmTimerInvoke invoke,
    void Function(String message)? onError,
  })  : _invoke = invoke,
        _onError = onError;

  String handle(String apiName, String payload) {
    try {
      switch (apiName) {
        case 'setTimeout':
          return _handleSetTimeout(payload);
        case 'setInterval':
          return _handleSetInterval(payload);
        case 'clearTimeout':
          return _handleClear(payload);
        case 'clearInterval':
          return _handleClear(payload);
        default:
          return _makeResponse('i16', 0);
      }
    } catch (e) {
      _onError?.call('VmTimerHostApi error ($apiName): $e');
      return _makeResponse('i16', 0);
    }
  }

  void dispose() {
    for (final timer in _timeouts.values) {
      timer.cancel();
    }
    for (final timer in _intervals.values) {
      timer.cancel();
    }
    _timeouts.clear();
    _intervals.clear();
  }

  String _handleSetTimeout(String payload) {
    final args = _normalizedArgs(payload);
    final handler = _readHandler(args);
    if (handler == null || handler.isEmpty) return _makeResponse('i16', 0);

    final delayMs = _readDelay(args);
    final inputJson = _readInputJson(args);
    final id = _nextId++;

    _timeouts[id] = Timer(Duration(milliseconds: delayMs), () async {
      _timeouts.remove(id);
      await _safeInvoke(handler, inputJson);
    });

    return _makeResponse('i64', id);
  }

  String _handleSetInterval(String payload) {
    final args = _normalizedArgs(payload);
    final handler = _readHandler(args);
    if (handler == null || handler.isEmpty) return _makeResponse('i16', 0);

    final delayMs = _readDelay(args);
    final inputJson = _readInputJson(args);
    final id = _nextId++;

    _intervals[id] = Timer.periodic(Duration(milliseconds: delayMs), (_) async {
      await _safeInvoke(handler, inputJson);
    });

    return _makeResponse('i64', id);
  }

  String _handleClear(String payload) {
    final id = _readId(payload);
    if (id == null) return _makeResponse('i16', 0);

    final timeout = _timeouts.remove(id);
    timeout?.cancel();

    final interval = _intervals.remove(id);
    interval?.cancel();

    return _makeResponse('i16', 0);
  }

  Future<void> _safeInvoke(String handler, String? inputJson) async {
    try {
      if (inputJson == null) {
        await _invoke(handler, null);
      } else {
        await _invoke(handler, inputJson);
      }
    } catch (e) {
      _onError?.call('VmTimerHostApi invoke error ($handler): $e');
    }
  }

  String? _readHandler(Map<String, dynamic> args) {
    final handler = args['handler'] ?? args['callback'] ?? args['fn'];
    return handler?.toString();
  }

  int _readDelay(Map<String, dynamic> args) {
    final raw = args['delay'] ?? args['ms'] ?? args['interval'];
    if (raw is num) return raw.round().clamp(0, 1 << 31);
    if (raw is String) {
      final parsed = int.tryParse(raw);
      if (parsed != null) return parsed.clamp(0, 1 << 31);
    }
    return 0;
  }

  String? _readInputJson(Map<String, dynamic> args) {
    final inputJson = args['inputJson'];
    if (inputJson is String) return inputJson;
    if (args.containsKey('input')) {
      return jsonEncode(args['input']);
    }
    return null;
  }

  int? _readId(String payload) {
    final parsed = _parsePayload(payload);
    if (parsed is Map<String, dynamic>) {
      final value = parsed['id'] ?? parsed['timerId'] ?? parsed['value'];
      if (value is num) return value.round();
      if (value is String) return int.tryParse(value);
    }
    if (parsed is num) return parsed.round();
    if (parsed is String) return int.tryParse(parsed);
    return null;
  }

  Map<String, dynamic> _normalizedArgs(String payload) {
    final parsed = _parsePayload(payload);
    if (parsed is Map<String, dynamic>) return parsed;
    if (parsed is Map) return Map<String, dynamic>.from(parsed);
    return {};
  }

  dynamic _parsePayload(String payload) {
    if (payload.isEmpty) return null;
    dynamic parsed;
    try {
      parsed = jsonDecode(payload);
    } catch (_) {
      if (payload.startsWith('"') && payload.endsWith('"')) {
        return payload.substring(1, payload.length - 1);
      }
      return payload;
    }

    if (parsed is List) {
      if (parsed.isEmpty) return null;
      return parsed.first;
    }

    if (parsed is Map &&
        parsed['data'] is Map &&
        (parsed['data'] as Map).containsKey('value')) {
      return (parsed['data'] as Map)['value'];
    }

    return parsed;
  }

  String _makeResponse(String type, dynamic value) {
    return jsonEncode({
      'type': type,
      'data': {'value': value},
    });
  }
}
