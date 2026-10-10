import 'package:flutter/material.dart';

import '../core/elpian_engine.dart';
import '../core/elpian_services.dart';
import '../core/event_system.dart';
import 'conversation.dart';
import 'elpian.dart';
import 'transport.dart';

/// A full-screen agent app: every surface the agent creates, its prose and a
/// chat row — the Flutter counterpart of the native hosts' `agent` session
/// kind (`ElpianHostView.open("agent", …)`, `mountElpian(el, 'agent', …)`).
///
/// ```dart
/// ElpianAgentView(
///   baseUrl: 'https://host.example',
///   appId: 'shop',
///   agent: 'assistant',
///   prompt: 'Show me what you have.',
/// )
/// ```
///
/// It runs in its own [ElpianServices] (one app), so its conversations,
/// events and stylesheets do not mix with the embedding app's. Use a
/// [GlobalKey<ElpianAgentViewState>] to [ElpianAgentViewState.send] messages
/// or [ElpianAgentViewState.action]s from outside.
class ElpianAgentView extends StatefulWidget {
  const ElpianAgentView({
    super.key,
    required this.baseUrl,
    required this.appId,
    required this.agent,
    this.conversationId,
    this.prompt,
    this.chat = true,
    this.showText = true,
    this.showAttribution = true,
    this.stylesheet,
    this.headers = const {},
    this.padding = const EdgeInsets.all(16),
    this.onEvent,
    this.fetch,
  });

  /// The host serving the app (`<baseUrl>/apps/<appId>/agent/<agent>`).
  final String baseUrl;
  final String appId;

  /// The agent's name in the app's `elpian.app.json`.
  final String agent;

  /// Continue an existing conversation.
  final String? conversationId;

  /// First message, sent when the view appears.
  final String? prompt;

  /// Show an input row for messaging the agent.
  final bool chat;

  /// Show the agent's prose.
  final bool showText;

  /// Show the surface theme's `agentDisplayName`.
  final bool showAttribution;

  /// An Elpian JSON stylesheet applied to the view.
  final Map<String, dynamic>? stylesheet;

  /// Extra request headers (e.g. authorization) for the agent endpoint.
  final Map<String, String> headers;

  final EdgeInsetsGeometry padding;

  /// Every conversation event: `a2uiAction`, `a2uiText`, `a2uiError`, `a2uiDone`.
  final void Function(String type, Map<String, dynamic> payload)? onEvent;

  /// The transport (defaults to HTTP; custom hosts and tests replace it).
  final AgentFetchStream? fetch;

  @override
  State<ElpianAgentView> createState() => ElpianAgentViewState();
}

class ElpianAgentViewState extends State<ElpianAgentView> {
  late ElpianServices _services;
  late ElpianEngine _engine;

  static const _conversationKey = 'agent-view';

  @override
  void initState() {
    super.initState();
    _setUp();
  }

  @override
  void didUpdateWidget(ElpianAgentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appId != widget.appId ||
        oldWidget.baseUrl != widget.baseUrl ||
        oldWidget.agent != widget.agent ||
        oldWidget.conversationId != widget.conversationId) {
      _setUp();
    } else if (oldWidget.stylesheet != widget.stylesheet &&
        widget.stylesheet != null) {
      _engine.loadStylesheet(widget.stylesheet!);
    }
  }

  void _setUp() {
    _services = ElpianServices(appId: widget.appId);
    _engine = ElpianEngine(services: _services);
    final registry = a2uiRegistry(_services)
      ..defaults = A2UIDefaults(
        baseUrl: widget.baseUrl,
        appId: widget.appId,
        headers: widget.headers,
      );
    if (widget.fetch != null) registry.fetch = widget.fetch!;
    if (widget.stylesheet != null) _engine.loadStylesheet(widget.stylesheet!);
  }

  /// The app services this view renders in.
  ElpianServices get services => _services;

  /// The conversation this view shows (created on first render).
  A2UIConversation? get conversation =>
      a2uiRegistry(_services)[_conversationKey];

  /// Send [message] to the agent.
  A2UITurn? send(String message) => conversation?.send(message);

  /// Send a client-to-server A2UI `action` to the agent.
  A2UITurn? action(Map<String, dynamic> action) =>
      conversation?.sendAction(action);

  /// The conversation id, once the agent has named it.
  String? get conversationId => conversation?.conversationId;

  Map<String, dynamic> _node() {
    final events = <String, dynamic>{};
    final onEvent = widget.onEvent;
    if (onEvent != null) {
      for (final type in const [
        'a2uiAction',
        'a2uiText',
        'a2uiError',
        'a2uiDone'
      ]) {
        events[type] = (ElpianEvent event) =>
            onEvent(type, Map<String, dynamic>.of(event.data)..remove('value'));
      }
    }
    return {
      'type': 'A2UISurface',
      'key': 'agent-view',
      'props': {
        'agent': widget.agent,
        'conversation': _conversationKey,
        if (widget.conversationId != null)
          'conversationId': widget.conversationId,
        if (widget.prompt != null) 'prompt': widget.prompt,
        'chat': widget.chat,
        'showText': widget.showText,
        'showAttribution': widget.showAttribution,
      },
      if (events.isNotEmpty) 'events': events,
    };
  }

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: SingleChildScrollView(
          padding: widget.padding,
          child: _engine.renderFromJson(_node()),
        ),
      );
}
