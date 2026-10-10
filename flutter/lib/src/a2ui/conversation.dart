/// `A2UIConversation` — one conversation with one agent: the A2UI processor
/// holding its surfaces, the transcript of prose, UI-local state, and the
/// agent transport. Turns ([A2UIConversation.send],
/// [A2UIConversation.sendAction]) run one at a time; each carries the
/// conversation id, the `sendDataModel` surfaces' data models and the client's
/// supported catalogs. Without an endpoint a conversation renders static A2UI
/// messages ([A2UIConversation.ingest]) and actions are only reported to
/// listeners.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'errors.dart';
import 'lowering.dart';
import 'processor.dart';
import 'transport.dart';

/// `conversation`, `text` ([role] `agent` / `user`), `status`, `error`,
/// `done`, `action`, or `changed` (surfaces, transcript or busy state
/// changed: render again).
class A2UIConversationEvent {
  A2UIConversationEvent(this.type,
      {this.conversationId,
      this.text,
      this.role,
      this.state,
      this.tool,
      this.message,
      this.error,
      this.stopReason,
      this.action});

  final String type;
  final String? conversationId;
  final String? text;
  final String? role;
  final String? state;
  final String? tool;
  final String? message;
  final A2UIError? error;
  final String? stopReason;
  final A2UIClientAction? action;
}

typedef A2UIConversationListener = void Function(A2UIConversationEvent event);

class A2UITranscriptEntry {
  const A2UITranscriptEntry(this.role, this.text);
  final String role;
  final String text;
  Map<String, dynamic> toJson() => {'role': role, 'text': text};
}

class A2UITurnResult {
  const A2UITurnResult(this.conversationId, this.stopReason);
  final String? conversationId;
  final String stopReason;
}

class A2UITurn {
  A2UITurn(this.conversationId, this.done);

  /// Completes once the agent named the conversation (or the turn ended without one).
  final Future<String?> conversationId;

  /// Completes when the turn ends.
  final Future<A2UITurnResult> done;
}

class A2UIConversation {
  A2UIConversation({
    this.endpoint,
    this.conversationId,
    A2UIProcessor? processor,
    this.fetch = httpFetchStream,
  }) : processor = processor ?? A2UIProcessor() {
    this.processor.on((e) {
      switch (e.type) {
        case 'error':
          _emit(A2UIConversationEvent('error',
              message: e.error!.message, error: e.error));
        case 'action':
          _emit(A2UIConversationEvent('action', action: e.action));
          if (endpoint != null) sendAction(e.action!.toJson());
        case 'surfaceDeleted':
          ui.clearSurface('${e.surfaceId}');
          _emit(A2UIConversationEvent('changed'));
        default:
          _emit(A2UIConversationEvent('changed'));
      }
    });
  }

  final A2UIProcessor processor;
  final A2UIUiState ui = A2UIUiState();
  final List<A2UITranscriptEntry> transcript = [];
  AgentEndpoint? endpoint;
  String? conversationId;
  final AgentFetchStream fetch;

  /// A turn is streaming.
  bool busy = false;
  ({String state, String? tool})? status;

  /// The `prompt` of an embedding widget was sent (once per conversation).
  bool prompted = false;

  final List<A2UIConversationListener> _listeners = [];
  Future<void> _queue = Future.value();
  void Function()? _cancel;
  String? _staticKey;
  bool _disposed = false;

  VoidCallback on(A2UIConversationListener listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _emit(A2UIConversationEvent event) {
    for (final l in List.of(_listeners)) {
      try {
        l(event);
      } catch (e) {
        debugPrint('A2UI conversation listener failed: $e');
      }
    }
  }

  /// Hooks the lowering uses for this conversation's surfaces.
  LoweringHooks loweringHooks(void Function() invalidate) => LoweringHooks(
        write: processor.setData,
        action: (surfaceId, componentId, action, scope) => processor
            .dispatchAction(surfaceId, componentId, action, scope: scope),
        invalidate: invalidate,
        error: (error) => _emit(A2UIConversationEvent('error',
            message: error.message, error: error)),
      );

  /// Render static A2UI messages (no agent).
  List<A2UIError> ingest(Iterable<Object?> messages) =>
      processor.processAll(messages);

  /// Static messages from a widget prop: re-applied from scratch when they change.
  void syncStatic(Iterable<Object?> messages, String key) {
    if (key == _staticKey) return;
    _staticKey = key;
    processor.reset();
    ingest(messages);
  }

  /// Send a user message to the agent.
  A2UITurn send(String message) {
    transcript.add(A2UITranscriptEntry('user', message));
    _emit(A2UIConversationEvent('text', text: message, role: 'user'));
    return _turn({'message': message});
  }

  /// Send a client-to-server `action` to the agent.
  A2UITurn sendAction(Map<String, dynamic> action) =>
      _turn({'action': Map<String, dynamic>.of(action)});

  /// The current data model of [surfaceId] (a copy), or null.
  Object? dataModel(String surfaceId) => processor.dataModel(surfaceId);

  /// A JSON summary.
  Map<String, dynamic> describe() => {
        'conversationId': conversationId,
        'busy': busy,
        'surfaces': [
          for (final s in processor.surfaces)
            {
              'surfaceId': s.id,
              'catalogId': s.catalogId,
              'components': s.components.length,
              'ready': s.isReady,
            }
        ],
        'transcript': [for (final t in transcript) t.toJson()],
      };

  A2UITurn _turn(Map<String, dynamic> payload) {
    final id = Completer<String?>();
    final done = Completer<A2UITurnResult>();
    _queue = _queue.then((_) {
      final next = Completer<void>();
      void finish(String stopReason) {
        if (!id.isCompleted) id.complete(conversationId);
        busy = false;
        status = null;
        _cancel = null;
        _emit(A2UIConversationEvent('done',
            stopReason: stopReason, conversationId: conversationId));
        _emit(A2UIConversationEvent('changed'));
        done.complete(A2UITurnResult(conversationId, stopReason));
        next.complete();
      }

      if (_disposed) {
        finish('error');
        return next.future;
      }
      final ep = endpoint;
      if (ep == null) {
        _emit(A2UIConversationEvent('error',
            message: 'this conversation has no agent endpoint'));
        finish('error');
        return next.future;
      }
      final body = <String, dynamic>{
        ...payload,
        'capabilities': {'supportedCatalogIds': processor.supportedCatalogIds},
      };
      if (conversationId != null) body['conversationId'] = conversationId;
      final dataModel = processor.clientDataModel();
      if (dataModel != null) body['dataModel'] = dataModel;
      busy = true;
      status = (state: 'working', tool: null);
      _emit(A2UIConversationEvent('changed'));
      String? stopReason;
      _cancel = openAgentStream(
          ep,
          body,
          _Sink(
            onLine: (line) {
              if (line.kind == 'done') stopReason = line.stopReason;
              handleLine(line);
              if (line.kind == 'conversation' && !id.isCompleted) {
                id.complete(line.conversationId);
              }
            },
            onError: (message) =>
                _emit(A2UIConversationEvent('error', message: message)),
            onClose: () => finish(stopReason ?? 'error'),
          ),
          fetch: fetch);
      return next.future;
    });
    return A2UITurn(id.future, done.future);
  }

  /// Apply one response line (exposed for transports other than HTTP).
  void handleLine(AgentStreamLine line) {
    switch (line.kind) {
      case 'a2ui':
        processor.process(line.message);
      case 'conversation':
        conversationId = line.conversationId;
        _emit(A2UIConversationEvent('conversation',
            conversationId: line.conversationId));
      case 'text':
        transcript.add(A2UITranscriptEntry('agent', line.text ?? ''));
        _emit(A2UIConversationEvent('text', text: line.text, role: 'agent'));
        _emit(A2UIConversationEvent('changed'));
      case 'status':
        status = (state: line.state ?? 'working', tool: line.tool);
        _emit(A2UIConversationEvent('status',
            state: line.state, tool: line.tool));
        _emit(A2UIConversationEvent('changed'));
      case 'error':
        _emit(A2UIConversationEvent('error', message: line.text));
    }
  }

  void dispose() {
    _disposed = true;
    _cancel?.call();
    _cancel = null;
    _listeners.clear();
  }
}

class _Sink implements AgentStreamSink {
  _Sink(
      {required void Function(AgentStreamLine) onLine,
      required void Function(String) onError,
      required void Function() onClose})
      : _line = onLine,
        _error = onError,
        _close = onClose;

  final void Function(AgentStreamLine) _line;
  final void Function(String) _error;
  final void Function() _close;

  @override
  void onLine(AgentStreamLine line) => _line(line);
  @override
  void onError(String message) => _error(message);
  @override
  void onClose() => _close();
}
