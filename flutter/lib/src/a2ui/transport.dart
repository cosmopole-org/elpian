/// The agent transport: `POST <baseUrl>/apps/<app>/agent/<agent>`, answered
/// with NDJSON (`application/x-ndjson`, one JSON object per line), read
/// incrementally. Chunk boundaries fall anywhere — mid-line, several lines at
/// once — and the decoder reassembles lines across them (UTF-8 is decoded by a
/// streaming decoder, so a character split across chunks survives).
///
/// Response lines (the Elpian agent contract):
///   {"type":"conversation","conversationId":"…"}          always first
///   {"version":"v0.9.1","createSurface":{…}}               A2UI messages, verbatim
///   {"type":"text","text":"…"}                             the agent's prose
///   {"type":"status","state":"working"|"tool","tool":"…"}  progress
///   {"type":"error","message":"…"}
///   {"type":"done","stopReason":"end_turn"|…}              always last
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'validator.dart';

/// Where an agent lives.
class AgentEndpoint {
  const AgentEndpoint({
    required this.baseUrl,
    required this.appId,
    required this.agent,
    this.headers = const {},
    this.timeout = const Duration(minutes: 5),
  });

  final String baseUrl;
  final String appId;
  final String agent;
  final Map<String, String> headers;
  final Duration timeout;

  /// `<baseUrl>/apps/<app>/agent/<agent>` (names percent-encoded).
  String get url =>
      '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/apps/${Uri.encodeComponent(appId)}/agent/${Uri.encodeComponent(agent)}';
}

/// One decoded response line: `a2ui` ([message]), `conversation`
/// ([conversationId]), `text`, `status` ([state], [tool]), `error`
/// ([message] as [text]) or `done` ([stopReason]).
class AgentStreamLine {
  const AgentStreamLine(this.kind,
      {this.message,
      this.conversationId,
      this.text,
      this.state,
      this.tool,
      this.stopReason});

  final String kind;
  final Map<String, dynamic>? message;
  final String? conversationId;
  final String? text;
  final String? state;
  final String? tool;
  final String? stopReason;
}

/// Classify one decoded response line (null for lines this client does not know).
AgentStreamLine? classifyLine(Object? value) {
  if (value is! Map) return null;
  final v = Map<String, dynamic>.from(value);
  if (messageKind(v) != null) return AgentStreamLine('a2ui', message: v);
  switch (v['type']) {
    case 'conversation':
      return v['conversationId'] is String
          ? AgentStreamLine('conversation',
              conversationId: v['conversationId'] as String)
          : null;
    case 'text':
      return AgentStreamLine('text',
          text:
              v['text'] is String ? v['text'] as String : '${v['text'] ?? ''}');
    case 'status':
      return AgentStreamLine('status',
          state: '${v['state'] ?? 'working'}',
          tool: v['tool'] is String ? v['tool'] as String : null);
    case 'error':
      return AgentStreamLine('error',
          text: v['message'] is String
              ? v['message'] as String
              : 'the agent failed');
    case 'done':
      return AgentStreamLine('done',
          stopReason: v['stopReason'] is String
              ? v['stopReason'] as String
              : 'end_turn');
  }
  return null;
}

/// Newline-delimited JSON decoding across arbitrary chunk boundaries. Blank
/// lines are skipped; a line that is not JSON is reported and skipped.
class NdjsonDecoder {
  NdjsonDecoder([this.onBadLine]);

  final void Function(String line)? onBadLine;
  final StringBuffer _buffer = StringBuffer();

  /// Feed a chunk; returns the complete values it finished.
  List<Object?> push(String chunk) {
    _buffer.write(chunk);
    final text = _buffer.toString();
    final out = <Object?>[];
    var start = 0;
    int i;
    while ((i = text.indexOf('\n', start)) >= 0) {
      _decode(text.substring(start, i), out);
      start = i + 1;
    }
    _buffer
      ..clear()
      ..write(text.substring(start));
    return out;
  }

  /// The stream ended: decode a final unterminated line.
  List<Object?> end() {
    final out = <Object?>[];
    final rest = _buffer.toString();
    _buffer.clear();
    _decode(rest, out);
    return out;
  }

  void _decode(String raw, List<Object?> out) {
    final line = raw.trim();
    if (line.isEmpty) return;
    try {
      out.add(jsonDecode(line));
    } catch (_) {
      onBadLine?.call(line);
    }
  }
}

abstract class AgentStreamSink {
  void onLine(AgentStreamLine line);

  /// Transport-level failure (no connection, HTTP error, unparseable line).
  void onError(String message);

  /// The response ended (after any error).
  void onClose();
}

/// Opens one streaming POST: delivers text chunks to [onChunk], then exactly
/// one of [onDone] / [onError]. Returns a canceller. Injectable for tests and
/// for hosts with their own networking.
typedef AgentFetchStream = void Function() Function(
  AgentEndpoint endpoint,
  String body, {
  required void Function(String chunk) onChunk,
  required void Function() onDone,
  required void Function(String message) onError,
});

/// The default [AgentFetchStream], over `package:http`.
void Function() httpFetchStream(
  AgentEndpoint endpoint,
  String body, {
  required void Function(String chunk) onChunk,
  required void Function() onDone,
  required void Function(String message) onError,
}) {
  final client = http.Client();
  var cancelled = false;
  StreamSubscription<String>? sub;
  Timer? timer;
  void finish() {
    timer?.cancel();
    client.close();
  }

  final request = http.Request('POST', Uri.parse(endpoint.url))
    ..headers.addAll({
      'content-type': 'application/json',
      'accept': 'application/x-ndjson',
      ...endpoint.headers,
    })
    ..body = body;
  timer = Timer(endpoint.timeout, () {
    if (cancelled) return;
    cancelled = true;
    sub?.cancel();
    finish();
    onError('the agent timed out');
  });
  client.send(request).then((response) async {
    if (cancelled) return;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final text = await response.stream.bytesToString();
      if (cancelled) return;
      cancelled = true;
      finish();
      onError('the agent answered HTTP ${response.statusCode}'
          '${text.trim().isEmpty ? '' : ': ${text.trim()}'}');
      return;
    }
    sub = response.stream.transform(utf8.decoder).listen(
      (chunk) {
        if (!cancelled) onChunk(chunk);
      },
      onDone: () {
        if (cancelled) return;
        cancelled = true;
        finish();
        onDone();
      },
      onError: (Object e) {
        if (cancelled) return;
        cancelled = true;
        finish();
        onError('$e');
      },
      cancelOnError: true,
    );
  }, onError: (Object e) {
    if (cancelled) return;
    cancelled = true;
    finish();
    onError('the agent could not be reached: $e');
  });
  return () {
    if (cancelled) return;
    cancelled = true;
    sub?.cancel();
    finish();
  };
}

/// Start one agent turn; returns a canceller.
void Function() openAgentStream(
    AgentEndpoint endpoint, Map<String, dynamic> body, AgentStreamSink sink,
    {AgentFetchStream fetch = httpFetchStream}) {
  final decoder =
      NdjsonDecoder((_) => sink.onError('the agent sent an unreadable line'));
  var closed = false;
  void deliver(List<Object?> values) {
    for (final v in values) {
      final line = classifyLine(v);
      if (line != null) sink.onLine(line);
    }
  }

  void close() {
    if (closed) return;
    closed = true;
    sink.onClose();
  }

  final cancel = fetch(
    endpoint,
    jsonEncode(body),
    onChunk: (text) {
      if (!closed) deliver(decoder.push(text));
    },
    onDone: () {
      if (closed) return;
      deliver(decoder.end());
      close();
    },
    onError: (message) {
      if (closed) return;
      deliver(decoder.end());
      sink.onError(
          message.isEmpty ? 'the agent could not be reached' : message);
      close();
    },
  );
  return () {
    closed = true;
    cancel();
  };
}
